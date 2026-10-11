#!/bin/bash
#
# kismet-log-maintenance.sh — Hand-Me-Down Homelab, section 11.4.
# Kismet log maintenance: replaces logrotate, which cannot work for Kismet.
#
# Install: /usr/local/sbin/kismet-log-maintenance.sh (0755), and root cron:
#   30 4 * * *  /usr/local/sbin/kismet-log-maintenance.sh prune
#   45 5 1 * *  /usr/local/sbin/kismet-log-maintenance.sh rotate
# (move the rotate time to after YOUR daily report).
#
# Kismet has no built-in rotation: it opens one timestamped log set per launch
# (log_template=%p/%n-%D-%t-%i.%l) and appends to it until the process exits.
# /etc/logrotate.d/kismet could never work -- logrotate refused the directory
# (/var/log/kismet was group-writable by a non-root group, no `su` directive, so logrotate.service
# exited 1 every night) and even with `su` its rename-then-compress model never
# expires a file whose base name never reappears.  Retired 2026-08-25 in favour
# of this script.
#
#   prune    delete closed log sets older than RETENTION_DAYS (daily, 04:30)
#   rotate   restart Kismet, closing the current set and opening a new one
#            (monthly, 1st at 05:45 -- see the timing note below)
#
# TIMING: never restart Kismet before the daily report.  A report that reads
# Kismet's in-memory state (the last day's alerts and devices) loses both on a
# restart, and every device returns with a fresh first-seen time, so the next
# report calls the whole air "new devices".  Each restart costs one noisy
# report.  That is why rotation is monthly, and runs after the report (the
# author's runs at 05:00 and takes ~90 s; rotation is at 05:45).
#
# The live log is never pruned: it is written to continuously, so its mtime
# can never satisfy -mtime +RETENTION_DAYS.

set -euo pipefail

LOGDIR=/var/log/kismet
RETENTION_DAYS=7

case "${1:-}" in
    prune)
        find "$LOGDIR" -maxdepth 1 -type f \
            \( -name 'Kismet-*.kismet' \
               -o -name 'Kismet-*.kismet-journal' \
               -o -name 'Kismet-*.pcapng' \) \
            -mtime +"$RETENTION_DAYS" -print -delete
        ;;
    rotate)
        systemctl restart kismet
        ;;
    *)
        echo "usage: ${0##*/} {prune|rotate}" >&2
        exit 2
        ;;
esac
