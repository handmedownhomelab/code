#!/usr/bin/env python3
"""
fetch.py — copy your homelab's alert mail into a local archive, read-only.

Companion file for playbook 3.4 of Hand-Me-Down Homelab. Run it from cron
every 15 minutes on an always-on Linux host. It logs in to your mailbox
over IMAP, finds mail from your lab's sender addresses, and writes each new
message to the archive. It never moves, flags or deletes anything: folders
are opened read-only and bodies are fetched with BODY.PEEK, so unread mail
stays unread.

Layout (ALERT_MAIL_HOME, default ~/alert-mail):
  settings.env                       non-secret settings (see below)
  archive/YYYY/MM-DD/HHMM_<subject>.eml   the raw message
  archive/YYYY/MM-DD/HHMM_<subject>.txt   Date/From/Subject/Folder + plain text
  state/seen-ids                     Message-IDs already archived or skipped
  state/skipped.log                  what the filters dropped, for audit
  state/fetch.log                    one line per run

settings.env (KEY=value):
  IMAP_HOST=imap.example.com
  IMAP_PORT=993
  IMAP_FOLDERS=Homelab,INBOX          folders to search, comma-separated
  SENDERS=alerts@example.com          the From addresses your lab sends as
  SKIP_SUBJECT_REGEX=                 optional: your own notes from those addresses

~/.config/alert-mail.creds (mode 600, KEY=value):
  IMAP_USER=<login>                   often not the same as the From address
  IMAP_PASS=<app-specific password>

Usage: fetch.py [--since-days N]   (default 2; use 30 once to backfill)
"""
import argparse
import email
import email.policy
import email.utils
import fcntl
import hashlib
import html.parser
import imaplib
import os
import re
import sys
from datetime import datetime, timedelta

BASE = os.path.expanduser(os.environ.get("ALERT_MAIL_HOME", "~/alert-mail"))
ARCHIVE = os.path.join(BASE, "archive")
STATE = os.path.join(BASE, "state")
SETTINGS = os.path.join(BASE, "settings.env")
CREDS = os.path.expanduser("~/.config/alert-mail.creds")

# Always skipped: replies and forwards, and triage.py's own report, so the
# triage never reviews itself.
SKIP_ALWAYS = [re.compile(r"^\s*(re|fwd?):", re.I),
               re.compile(r"^\[alert triage\]", re.I)]
SHORT_TEXT = 200   # a text/plain part shorter than this loses to the HTML part


def load_kv(path):
    out = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip().strip('"').strip("'")
    return out


class _HTMLText(html.parser.HTMLParser):
    BREAKS = {"br", "p", "div", "tr", "li", "h1", "h2", "h3", "table"}

    def __init__(self):
        super().__init__()
        self.parts, self._skip = [], 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style"):
            self._skip += 1
        elif tag in self.BREAKS:
            self.parts.append("\n")
        elif tag in ("td", "th"):
            self.parts.append("  ")

    def handle_endtag(self, tag):
        if tag in ("script", "style") and self._skip:
            self._skip -= 1

    def handle_data(self, data):
        if not self._skip:
            self.parts.append(data)


def html_to_text(s):
    p = _HTMLText()
    p.feed(s)
    text = "".join(p.parts)
    return re.sub(r"\n\s*\n+", "\n\n", text).strip()


def body_text(msg):
    plain = html_body = None
    for part in msg.walk():
        if part.is_multipart() or part.get_content_disposition() == "attachment":
            continue
        ctype = part.get_content_type()
        try:
            content = part.get_content()
        except (LookupError, KeyError, ValueError):
            continue
        if ctype == "text/plain" and plain is None:
            plain = content
        elif ctype == "text/html" and html_body is None:
            html_body = content
    # Some senders ship a stub text part ("HTML-capable client required")
    # and put the real report in HTML. Keep whichever says more.
    if plain and (len(plain.strip()) >= SHORT_TEXT or not html_body):
        return plain.strip()
    if html_body:
        converted = html_to_text(html_body)
        if not plain or len(converted) > len(plain.strip()):
            return converted
    return (plain or "").strip()


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")[:60] or "no-subject"


def first_bytes(resp):
    # An IMAP FETCH reply can carry a bare flags line and no body tuple.
    for part in resp or []:
        if isinstance(part, tuple) and len(part) > 1 and isinstance(part[1], bytes):
            return part[1]
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since-days", type=int, default=2)
    args = ap.parse_args()

    settings, creds = load_kv(SETTINGS), load_kv(CREDS)
    folders = [f.strip() for f in settings["IMAP_FOLDERS"].split(",") if f.strip()]
    senders = [s.strip() for s in settings["SENDERS"].split(",") if s.strip()]
    skip = list(SKIP_ALWAYS)
    if settings.get("SKIP_SUBJECT_REGEX"):
        skip.append(re.compile(settings["SKIP_SUBJECT_REGEX"], re.I))

    for d in (ARCHIVE, STATE):
        os.makedirs(d, exist_ok=True)
    os.chmod(ARCHIVE, 0o700)
    lock = open(os.path.join(STATE, "fetch.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return 0  # the previous run is still going

    seen_path = os.path.join(STATE, "seen-ids")
    seen = set(open(seen_path).read().split("\n")) if os.path.exists(seen_path) else set()
    new_ids, n_new, n_skip = [], 0, 0
    since = (datetime.now() - timedelta(days=args.since_days)).strftime("%d-%b-%Y")

    imap = imaplib.IMAP4_SSL(settings["IMAP_HOST"], int(settings.get("IMAP_PORT", "993")))
    imap.login(creds["IMAP_USER"], creds["IMAP_PASS"])
    try:
        for folder in folders:
            typ, _ = imap.select(f'"{folder}"', readonly=True)
            if typ != "OK":
                print(f"folder not found: {folder}", file=sys.stderr)
                continue
            for sender in senders:
                typ, data = imap.uid("SEARCH", None, "FROM", f'"{sender}"', "SINCE", since)
                if typ != "OK":
                    continue
                for uid in data[0].split():
                    typ, resp = imap.uid("FETCH", uid, "(BODY.PEEK[])")
                    raw = first_bytes(resp)
                    if raw is None:
                        continue
                    msg = email.message_from_bytes(raw, policy=email.policy.default)
                    mid = (msg.get("Message-ID") or "").strip() or \
                        "sha1:" + hashlib.sha1(raw).hexdigest()
                    if mid in seen:
                        continue
                    seen.add(mid)
                    new_ids.append(mid)
                    subject = str(msg.get("Subject", "")).replace("\n", " ")
                    if any(r.search(subject) for r in skip):
                        with open(os.path.join(STATE, "skipped.log"), "a") as f:
                            f.write(f"{datetime.now():%F %T}\t{folder}\t{subject}\n")
                        n_skip += 1
                        continue
                    try:
                        when = email.utils.parsedate_to_datetime(msg["Date"]).astimezone()
                    except (TypeError, ValueError):
                        when = datetime.now().astimezone()
                    day = os.path.join(ARCHIVE, f"{when:%Y}", f"{when:%m-%d}")
                    os.makedirs(day, mode=0o700, exist_ok=True)
                    stem = os.path.join(day, f"{when:%H%M}_{slug(subject)}")
                    k = 2
                    while os.path.exists(stem + ".eml"):
                        stem = os.path.join(day, f"{when:%H%M}_{slug(subject)}-{k}")
                        k += 1
                    with open(stem + ".eml", "wb") as f:
                        f.write(raw)
                    with open(stem + ".txt", "w") as f:
                        f.write(f"Date: {when.isoformat()}\nFrom: {msg.get('From', '')}\n"
                                f"Subject: {subject}\nFolder: {folder}\n\n{body_text(msg)}\n")
                    n_new += 1
    finally:
        try:
            imap.logout()
        except Exception:
            pass
        if new_ids:
            with open(seen_path, "a") as f:
                f.write("\n".join(new_ids) + "\n")

    with open(os.path.join(STATE, "fetch.log"), "a") as f:
        f.write(f"{datetime.now():%F %T} archived {n_new}, skipped {n_skip}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
