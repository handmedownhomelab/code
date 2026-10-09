#!/bin/bash
# pihole-sync.sh — keep a secondary Pi-hole (v6) in step with the primary.
# Hand-Me-Down Homelab, section 3.2.
#
# One-way: the primary is the source of truth. The script logs into the
# primary's API, downloads its teleporter export, and imports it here, but only
# when the primary's configuration actually changed. It then puts back the one
# setting the import overwrites (this Pi-hole's own web hostname), waits for
# Pi-hole's own restart to finish, and checks DNS really answers before
# recording the change as done.
#
# INSTALL (on the secondary, as root):
#   install -m 755 pihole-sync.sh /usr/local/bin/pihole-sync
#   install -m 600 /dev/null /etc/pihole/sync-credentials   # then fill it in:
#       PRIMARY_URL=https://pihole.home.arpa
#       PRIMARY_PASS='<primary admin password>'
#       SECONDARY_URL=https://127.0.0.1
#       SECONDARY_PASS='<the PRIMARY's admin password>'
#       SECONDARY_DOMAIN=pihole2.home.arpa      # optional; this is the default
#   echo '*/15 * * * * root /usr/local/bin/pihole-sync' > /etc/cron.d/pihole-sync
#
# SECONDARY_PASS is the primary's password, and the secondary's admin password
# should be set to it before the first sync: the import copies the primary's
# password hash, so from then on the secondary only accepts the primary's
# password. With a different one, the first sync works and every later one
# fails with "failed to auth to self".
#
# `curl -k` skips certificate checks, because a home Pi-hole usually has a
# private or self-signed certificate. If yours chains to a CA this machine
# trusts (section 3.4), you can drop the -k.
#
# WHY THE CHANGE GATE, AND WHY NO RESTART: the original version imported and
# then ran `systemctl restart pihole-FTL` every 15 minutes. But the import
# makes FTL restart itself, and so does the webserver.domain fix below; a
# systemctl restart on top of those hits an FTL that is already restarting,
# the stop hangs for systemd's full 60-second timeout, and FTL is killed. The
# secondary dropped DNS for about a minute every 15 minutes, 10,472 times over
# three and a half months, silently, because `systemctl restart` still returns
# 0 after the kill. Now the script imports only when the configuration changed
# and never restarts FTL itself: it waits for FTL's own restart and checks DNS.
# Tested 2026-10-08: about 3 seconds from import to serving, no timeout.

set -euo pipefail

LOGFILE=/var/log/pihole-sync.log
STATEDIR=/var/lib/pihole-sync
STATEFILE="$STATEDIR/last-applied.sha256"
TMPFILE=$(mktemp /tmp/pihole-sync-XXXXXX.zip)
trap 'rm -f "$TMPFILE"' EXIT

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$LOGFILE"; }

mkdir -p "$STATEDIR"

# Load credentials
source /etc/pihole/sync-credentials

# Authenticate to primary
PRIMARY_SID=$(curl -sk -X POST "${PRIMARY_URL}/api/auth" \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"${PRIMARY_PASS}\"}" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['session']['sid'] or '')" 2>/dev/null || true)

if [[ -z "$PRIMARY_SID" || "$PRIMARY_SID" == "null" ]]; then
  log "ERROR: failed to auth to primary"
  exit 1
fi

# Download teleporter export from primary
HTTP_STATUS=$(curl -sk -o "$TMPFILE" -w "%{http_code}" \
  -H "X-FTL-SID: ${PRIMARY_SID}" \
  "${PRIMARY_URL}/api/teleporter")

if [[ "$HTTP_STATUS" != "200" ]]; then
  log "ERROR: teleporter export failed (HTTP $HTTP_STATUS)"
  exit 1
fi

# Skip the import — and therefore the FTL restart — when nothing changed
# upstream.
#
# Do NOT checksum the whole zip: the export also carries the primary's
# pihole-FTL.db (its query log, millions of rows), which the primary rewrites about
# once a minute while serving DNS. A whole-archive checksum therefore differs
# on essentially every run and would never skip anything. Hash only the
# config-bearing members, by content, with the member name — never the
# extraction path, which is a fresh mktemp dir each run.
SUMDIR=$(mktemp -d /tmp/pihole-sync-sum-XXXXXX)
trap 'rm -f "$TMPFILE"; rm -rf "$SUMDIR"' EXIT
# If the export can't be unpacked (unzip missing, a truncated download), every
# member hashes as "absent", the checksum never changes again, and every later
# sync would be skipped as "no change". Fail loudly instead.
if ! unzip -qo "$TMPFILE" -d "$SUMDIR" 2>/dev/null \
   || [[ ! -f "$SUMDIR/etc/pihole/pihole.toml" || ! -f "$SUMDIR/etc/pihole/gravity.db" ]]; then
  log "ERROR: could not unpack the export (is unzip installed?); nothing imported"
  exit 1
fi

NEW_SUM=$(
  for member in etc/hosts etc/pihole/pihole.toml etc/pihole/gravity.db; do
    if [[ -f "$SUMDIR/$member" ]]; then
      printf '%s %s\n' "$member" "$(sha256sum < "$SUMDIR/$member" | awk '{print $1}')"
    else
      printf '%s absent\n' "$member"
    fi
  done | sha256sum | awk '{print $1}'
)

OLD_SUM=""
[[ -r "$STATEFILE" ]] && OLD_SUM=$(< "$STATEFILE")

if [[ -n "$OLD_SUM" && "$NEW_SUM" == "$OLD_SUM" ]]; then
  log "no change: export matches last applied sync, skipping import and restart"
  exit 0
fi

# Authenticate to self (teleporter syncs password hash so password = primary's)
SELF_SID=$(curl -sk -X POST "${SECONDARY_URL}/api/auth" \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"${SECONDARY_PASS}\"}" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['session']['sid'] or '')" 2>/dev/null || true)

if [[ -z "$SELF_SID" || "$SELF_SID" == "null" ]]; then
  log "ERROR: failed to auth to self"
  exit 1
fi

# Import teleporter backup
IMPORT_RESULT=$(curl -sk -w "\n%{http_code}" -X POST \
  -H "X-FTL-SID: ${SELF_SID}" \
  -F "file=@${TMPFILE};type=application/zip" \
  "${SECONDARY_URL}/api/teleporter")

IMPORT_STATUS=$(echo "$IMPORT_RESULT" | tail -1)

if [[ "$IMPORT_STATUS" != "200" ]]; then
  log "ERROR: teleporter import failed (HTTP $IMPORT_STATUS)"
  exit 1
fi

# Restore the setting the import overwrote: this Pi-hole's own web hostname,
# not the primary's.
pihole-FTL --config webserver.domain "${SECONDARY_DOMAIN:-pihole2.home.arpa}" > /dev/null 2>&1 || true

# Do NOT restart FTL here. The import makes FTL restart itself, and the
# webserver.domain change above makes it restart again. A `systemctl restart`
# on top of that hits an FTL that is already restarting: the stop hangs for
# systemd's full 60-second timeout and FTL is killed, a minute of no DNS on
# every sync. Instead, wait for FTL's own restarts to finish and check that
# it serves DNS with this Pi-hole's own settings.
T0=$(date +%s)
ACTIVE=no; DNS_OK=no; DOMAIN_OK=no
sleep 3
while (( $(date +%s) - T0 < 90 )); do
  ACTIVE=$(systemctl is-active pihole-FTL 2>/dev/null || true)
  DNS_OK=no
  dig +short +time=2 +tries=1 @127.0.0.1 pi.hole > /dev/null 2>&1 && DNS_OK=yes
  [[ "$(pihole-FTL --config webserver.domain 2>/dev/null)" == "${SECONDARY_DOMAIN:-pihole2.home.arpa}" ]] \
    && DOMAIN_OK=yes || DOMAIN_OK=no
  [[ "$ACTIVE" == "active" && "$DNS_OK" == "yes" && "$DOMAIN_OK" == "yes" ]] && break
  sleep 2
done
ELAPSED=$(( $(date +%s) - T0 ))

if [[ "$ACTIVE" != "active" || "$DNS_OK" != "yes" || "$DOMAIN_OK" != "yes" ]]; then
  log "ERROR: FTL not serving after import (active=$ACTIVE dns=$DNS_OK domain=$DOMAIN_OK ${ELAPSED}s); checksum not recorded, will retry next cycle"
  exit 1
fi

# Only record the checksum once the change is confirmed applied and serving,
# so a failed cycle retries rather than being skipped as "already applied".
printf '%s\n' "$NEW_SUM" > "$STATEFILE"

# A clean pair of FTL self-restarts takes seconds. If FTL was ever killed for
# overrunning its stop timeout, journalctl shows it; report that, don't hide it.
if journalctl -u pihole-FTL --since "@$T0" --no-pager 2>/dev/null | grep -q "Failed with result 'timeout'"; then
  log "OK: sync complete (config changed) — WARNING: FTL stop timed out and was killed (${ELAPSED}s)"
else
  log "OK: sync complete (config changed, serving again after ${ELAPSED}s)"
fi
