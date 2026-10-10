#!/usr/bin/env python3
"""
Frigate detection watchdog — Hand-Me-Down Homelab, section 10.2.

Catches the failure behind the book's 45-hour outage: Frigate ran for 45
hours reporting `Up (healthy)` and streaming live video while detecting
nothing. `docker ps`, the container healthcheck and the Frigate UI all passed
throughout; the only honest signal was `process_fps`.

Polls the Frigate API on localhost and emails when detection is dead. It
deliberately depends on **neither MQTT nor Home Assistant**: in that outage
MQTT also dropped and never reconnected, so anything routed through Home
Assistant would have been silent too.

Failure modes detected:
  blind       frames arriving but not processed (camera_fps > 0,
              process_fps ~ 0): the silent 45-hour outage
  no_frames   camera delivering nothing (camera_fps == 0): a stalled stream
  api_down    Frigate API unreachable: container down or wedged

Debounced: alerts only after N consecutive bad polls, so a normal restart
(including a ~90-second GPU warm-up after an NVIDIA driver upgrade, which is
what set off the original outage) doesn't page you. One alert per episode
plus a recovery notice, never a stream of repeats.

INSTALL (as your user, on the Frigate host):
  install -m 755 frigate-detect-watchdog.py ~/bin/
  mkdir -p ~/.config/frigate-watchdog
  install -m 600 /dev/null ~/.config/frigate-watchdog/smtp_creds   # then fill it in:
      SMTP_HOST=smtp.example.com
      SMTP_PORT=587
      SMTP_USER=you@example.com
      SMTP_PASS=<app-specific password>
      ALERT_TO=you@example.com
  cp frigate-detect-watchdog.service frigate-detect-watchdog.timer ~/.config/systemd/user/
  systemctl --user daemon-reload
  systemctl --user enable --now frigate-detect-watchdog.timer
  loginctl enable-linger $USER      # keep user timers running when logged out

Test the alert path before trusting it: `--dry-run` prints the email it
would send, and FRIGATE_STATS_URL=file:///tmp/stats.json (a copy of
/api/stats with process_fps set to 0.1) exercises the "blind" branch without
touching the real NVR. Run it three times: the alert fires on the third.
"""

import argparse
import json
import os
import smtplib
import socket
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from email.mime.text import MIMEText
from pathlib import Path

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
# FRIGATE_URL / STATE_PATH are overridable so the failure paths can be
# exercised against synthetic stats without breaking the live NVR.
FRIGATE_URL = os.environ.get("FRIGATE_STATS_URL", "http://127.0.0.1:5000/api/stats")
OLLAMA_URL = "http://127.0.0.1:11434/api/ps"
CREDS_PATH = os.environ.get(
    "FRIGATE_WATCHDOG_CREDS",
    os.path.expanduser("~/.config/frigate-watchdog/smtp_creds"),
)
STATE_PATH = Path(
    os.environ.get(
        "FRIGATE_WATCHDOG_STATE",
        os.path.expanduser("~/.local/state/frigate-detect-watchdog.json"),
    )
)

# Healthy steady state is process_fps ~10 (the detect fps in config.yml); the
# 45-hour outage sat at 0.1.
MIN_PROCESS_FPS = 1.0

# Consecutive bad polls before alerting. At the timer's 5 min cadence, 3 =>
# ~15 min to alert, comfortably longer than any legitimate warmup.
FAIL_THRESHOLD = 3

HTTP_TIMEOUT = 10

REMEDY = f"ssh {socket.gethostname()} '~/bin/frigate-safe-restart.sh'"


def log(msg):
    """Log to stdout; systemd captures it into the journal."""
    print(f"[{datetime.now().astimezone():%Y-%m-%d %H:%M:%S %Z}] {msg}", flush=True)


def get_json(url, timeout=HTTP_TIMEOUT):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return json.load(r)


def load_creds(path=CREDS_PATH):
    creds = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            key, _, val = line.partition("=")
            creds[key.strip()] = val.strip()
    return creds


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------
def check():
    """Return (ok, reason, detail_lines)."""
    try:
        stats = get_json(FRIGATE_URL)
    except (urllib.error.URLError, socket.timeout, OSError, ValueError) as e:
        return False, "api_down", [f"Frigate API unreachable at {FRIGATE_URL}", f"  {e}"]

    cameras = stats.get("cameras") or {}
    if not cameras:
        return False, "api_down", ["Frigate API returned no cameras."]

    detail = []
    bad = []
    for name, c in sorted(cameras.items()):
        cam_fps = float(c.get("camera_fps") or 0)
        proc_fps = float(c.get("process_fps") or 0)
        skipped = float(c.get("skipped_fps") or 0)
        det_fps = float(c.get("detection_fps") or 0)
        detail.append(
            f"  {name}: camera_fps={cam_fps} process_fps={proc_fps} "
            f"skipped_fps={skipped} detection_fps={det_fps}"
        )
        if cam_fps <= 0:
            bad.append((name, "no_frames"))
        elif proc_fps < MIN_PROCESS_FPS:
            bad.append((name, "blind"))

    for dname, d in sorted((stats.get("detectors") or {}).items()):
        detail.append(f"  detector {dname}: inference_speed={d.get('inference_speed')} ms")

    for gname, g in sorted((stats.get("gpu_usages") or {}).items()):
        detail.append(f"  gpu {gname}: mem={g.get('mem')} util={g.get('gpu')}")

    if not bad:
        return True, "ok", detail

    reason = bad[0][1]
    names = ", ".join(f"{n} ({r})" for n, r in bad)
    return False, reason, [f"Unhealthy cameras: {names}"] + detail


def ollama_context():
    """Best-effort: what Ollama is holding. Usually the other half of the story."""
    try:
        d = get_json(OLLAMA_URL, timeout=5)
    except Exception:
        return ["  (ollama not reachable)"]
    models = d.get("models") or []
    if not models:
        return ["  no models loaded"]
    return [
        f"  {m.get('name')}: {round((m.get('size_vram') or 0) / 1e9, 1)} GB VRAM"
        for m in models
    ]


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
def load_state():
    try:
        return json.loads(STATE_PATH.read_text())
    except Exception:
        return {"fails": 0, "alerted": False}


def save_state(state):
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, indent=2))


# ---------------------------------------------------------------------------
# Email
# ---------------------------------------------------------------------------
def send_email(subject, body):
    creds = load_creds()
    sender = creds["SMTP_USER"]
    to = [a.strip() for a in creds.get("ALERT_TO", sender).split(",") if a.strip()]
    msg = MIMEText(body)
    msg["Subject"] = subject
    msg["From"] = sender
    msg["To"] = ", ".join(to)
    with smtplib.SMTP(creds["SMTP_HOST"], int(creds.get("SMTP_PORT", 587)), timeout=30) as smtp:
        smtp.ehlo()
        smtp.starttls()
        smtp.login(sender, creds["SMTP_PASS"])
        smtp.sendmail(sender, to, msg.as_string())
    log(f"email sent: {subject}")


def alert_body(reason, detail, fails):
    when = datetime.now(timezone.utc).astimezone()
    headline = {
        "blind": "Frigate is running but DETECTING NOTHING.",
        "no_frames": "Frigate is receiving no frames from the camera.",
        "api_down": "Frigate API is unreachable.",
    }.get(reason, "Frigate detection is unhealthy.")

    return "\n".join(
        [
            headline,
            "",
            f"Detected at : {when:%Y-%m-%d %H:%M:%S %Z}",
            f"Failure mode: {reason}",
            f"Confirmed over {fails} consecutive checks (~{fails * 5} min).",
            "",
            "Frigate stats:",
            *detail,
            "",
            "Ollama VRAM:",
            *ollama_context(),
            "",
            "Note: `docker ps` and the Frigate UI banner are NOT valid checks for",
            "this. In the outage this watchdog exists for, both reported healthy",
            "for 45 hours while detection was dead. Only process_fps > 0 proves",
            "it is alive.",
            "",
            "Remediation (frees Ollama VRAM, recreates, verifies the detector):",
            f"  {REMEDY}",
        ]
    )


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="Frigate detection watchdog")
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="print the alert that would be sent instead of emailing it",
    )
    args = ap.parse_args()

    global send_email
    if args.dry_run:
        real_send = send_email

        def send_email(subject, body):  # noqa: F811
            print(f"--- DRY RUN: would send ---\nSubject: {subject}\n\n{body}\n---")

        del real_send

    ok, reason, detail = check()
    state = load_state()

    if ok:
        if state.get("alerted"):
            log("recovered — sending recovery notice")
            try:
                send_email(
                    "[RESOLVED] Frigate detection is alive again",
                    "\n".join(
                        [
                            "Frigate detection has recovered.",
                            "",
                            f"Recovered at: {datetime.now().astimezone():%Y-%m-%d %H:%M:%S %Z}",
                            "",
                            "Frigate stats:",
                            *detail,
                        ]
                    ),
                )
            except Exception as e:
                log(f"ERROR sending recovery email: {e}")
        else:
            log(f"ok — {'; '.join(detail)}")
        save_state({"fails": 0, "alerted": False})
        return 0

    fails = int(state.get("fails", 0)) + 1
    log(f"UNHEALTHY ({reason}) fail {fails}/{FAIL_THRESHOLD} — {'; '.join(detail)}")

    already = bool(state.get("alerted"))
    if fails >= FAIL_THRESHOLD and not already:
        try:
            send_email(
                f"[ALERT] Frigate detection DOWN on {socket.gethostname()} ({reason})",
                alert_body(reason, detail, fails),
            )
            already = True
        except Exception as e:
            # Keep alerted False so the next run retries the send.
            log(f"ERROR sending alert email: {e}")

    save_state({"fails": fails, "alerted": already})
    return 1


if __name__ == "__main__":
    sys.exit(main())
