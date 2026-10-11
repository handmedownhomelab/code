#!/usr/bin/env python3
"""Export speed-cam.py sqlite events into the traffic CSV schema.

Hand-Me-Down Homelab, section 10.4 (playbook 10.4-speed-camera-pi)
Deploys to:     /opt/speed-camera/speedcam_export.py

Emits exactly the four columns the fixed camera's logger writes (book 10.3):

    timestamp,speed_mph,direction,vehicle_type

so a portable deployment's CSV drops straight into the same report script
with no code changes there.

Append-only and incremental: a cursor file holds the last exported sqlite idx
(a sortable "YYYYMMDD-HHMMSSs" string), so re-running never duplicates rows.

Run:  speedcam_export.py            append new rows
      speedcam_export.py --dry-run  show what would be written
      speedcam_export.py --rebuild  discard cursor, rewrite the whole CSV
"""

import argparse
import csv
import os
import sqlite3
import sys
from datetime import datetime
from zoneinfo import ZoneInfo

CONF_PATH = "/opt/speed-camera/speedcam.conf"

DEFAULTS = {
    "DB_PATH": "/opt/speed-camera/data/speed_cam.db",
    "DB_TABLE": "speed",
    "CSV_PATH": "/var/lib/speedcam/speedcam_traffic.csv",
    "CURSOR_PATH": "/var/lib/speedcam/.export_cursor",
    "TIMEZONE": "America/New_York",
    "L2R_DIRECTION": "east",
    "R2L_DIRECTION": "west",
    "MIN_VALID_YEAR": "2026",
}

FIELDNAMES = ["timestamp", "speed_mph", "direction", "vehicle_type"]


def load_conf(path):
    conf = dict(DEFAULTS)
    if os.path.exists(path):
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                conf[k.strip()] = v.strip().strip('"').strip("'")
    return conf


def clean(value):
    """speed-cam builds its INSERT by string formatting, so text columns can
    arrive wrapped in literal quote characters. Strip them."""
    if value is None:
        return ""
    return str(value).strip().strip('"').strip("'").strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--rebuild", action="store_true",
                    help="ignore and reset the cursor, rewriting the CSV from scratch")
    ap.add_argument("--conf", default=CONF_PATH)
    args = ap.parse_args()

    conf = load_conf(args.conf)
    tz = ZoneInfo(conf["TIMEZONE"])
    min_year = int(conf["MIN_VALID_YEAR"])
    dirmap = {"L2R": conf["L2R_DIRECTION"], "R2L": conf["R2L_DIRECTION"]}

    if not os.path.exists(conf["DB_PATH"]):
        sys.exit("ERROR: no sqlite db at %s - has speed-camera run yet?" % conf["DB_PATH"])

    cursor_path = conf["CURSOR_PATH"]
    last_idx = ""
    if not args.rebuild and os.path.exists(cursor_path):
        with open(cursor_path) as f:
            last_idx = f.read().strip()

    conn = sqlite3.connect("file:%s?mode=ro" % conf["DB_PATH"], uri=True)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        "SELECT idx, log_timestamp, ave_speed, speed_units, direction "
        "FROM %s WHERE idx > ? ORDER BY idx ASC" % conf["DB_TABLE"],
        (last_idx,),
    ).fetchall()
    conn.close()

    out, skipped_clock, skipped_units, skipped_dir, newest = [], 0, 0, 0, last_idx
    for r in rows:
        units = clean(r["speed_units"]).lower()
        if units and units != "mph":
            # MO_SPEED_MPH_ON got flipped; kph rows would silently read as mph.
            skipped_units += 1
            continue

        raw_ts = clean(r["log_timestamp"])
        try:
            ts = datetime.strptime(raw_ts, "%Y-%m-%d %H:%M:%S").replace(tzinfo=tz)
        except ValueError:
            skipped_clock += 1
            continue

        # A portable Pi has no network time source. Without a working RTC the
        # clock free-runs from whatever it was at boot and every row after that
        # is mistimed - which a report cannot detect. Refuse those rows.
        if ts.year < min_year:
            skipped_clock += 1
            continue

        raw_dir = clean(r["direction"]).upper()
        direction = dirmap.get(raw_dir)
        if direction is None:
            skipped_dir += 1
            direction = ""

        out.append({
            "timestamp": ts.isoformat(),
            "speed_mph": "%.1f" % float(r["ave_speed"]),
            "direction": direction,
            "vehicle_type": "",   # speed-cam does no classification
        })
        newest = r["idx"]

    csv_path = conf["CSV_PATH"]
    print("read %d new sqlite rows -> %d exportable" % (len(rows), len(out)))
    for label, n in (("clock/timestamp", skipped_clock),
                     ("wrong speed units", skipped_units),
                     ("unmapped direction", skipped_dir)):
        if n:
            print("  WARN: %d rows skipped (%s)" % (n, label))

    if args.dry_run:
        for row in out[:10]:
            print("   ", row)
        if len(out) > 10:
            print("    ... and %d more" % (len(out) - 10))
        print("dry run - nothing written")
        return

    if not out and not args.rebuild:
        print("nothing to append; cursor unchanged at %s" % (last_idx or "(none)"))
        return

    os.makedirs(os.path.dirname(csv_path), exist_ok=True)
    write_header = args.rebuild or not os.path.exists(csv_path) or os.path.getsize(csv_path) == 0
    mode = "w" if args.rebuild else "a"
    with open(csv_path, mode, newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDNAMES)
        if write_header:
            w.writeheader()
        w.writerows(out)

    with open(cursor_path, "w") as f:
        f.write(newest)

    print("appended %d rows to %s (cursor now %s)" % (len(out), csv_path, newest))


if __name__ == "__main__":
    main()
