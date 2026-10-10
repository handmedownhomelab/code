#!/bin/bash
# Prune the central syslog tree on the collector.
# Hand-Me-Down Homelab, section 3.2. Install as /usr/local/sbin/prune-remote-logs.sh
# (mode 755) with prune-remote-logs.service and .timer from this folder.
#
#   - compress per-day files once they are no longer being written
#   - delete anything past the retention horizon
#   - drop host directories that have gone empty
#
# Files are named by date (<host>/<YYYY-MM-DD>.log), so rsyslog opens a new
# file at midnight on its own. Nothing here signals rsyslog and nothing here
# touches the file it currently holds open -- that is what -mtime +1 buys.
#
# The loop walks host directories one at a time rather than pointing find at
# $ROOT, because a separate log disk's lost+found is mode 700 and owned by real
# root: an unprivileged container cannot descend into it, and the resulting
# "Permission denied" is enough to kill the whole run under `set -e`.
set -euo pipefail
shopt -s nullglob

ROOT=/var/log/remote
COMPRESS_AFTER=1     # days
RETAIN_DAYS=90       # days

[[ -d $ROOT ]] || { echo "$ROOT missing -- is the mountpoint attached?" >&2; exit 1; }

for hostdir in "$ROOT"/*/; do
    [[ $(basename "$hostdir") == lost+found ]] && continue

    find "$hostdir" -type f -name '*.log' -mtime +$COMPRESS_AFTER \
         -exec gzip -9 {} +

    find "$hostdir" -type f \( -name '*.log' -o -name '*.log.gz' \) \
         -mtime +$RETAIN_DAYS -delete

    # Only removes it if the retention sweep emptied it -- a host that has
    # simply been quiet today still has yesterday's file and survives.
    rmdir --ignore-fail-on-non-empty "$hostdir"
done
