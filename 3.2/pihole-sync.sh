#!/bin/bash
# pihole-sync.sh — keep a secondary Pi-hole (v6) in step with the primary.
# Hand-Me-Down Homelab, section 3.2.
#
# One-way: the primary is the source of truth. The script logs into the
# primary's API, downloads its teleporter export, and imports it here, but only
# when the primary's configuration actually changed. It then puts back the one
# setting the import overwrites (this Pi-hole's own web hostname), restarts
# Pi-hole, and checks DNS really answers before recording the change as done.
#
# INSTALL (on the secondary, as root):
#   install -m 755 pihole-sync.sh /usr/local/bin/pihole-sync
#   install -m 600 /dev/null /etc/pihole/sync-credentials   # then fill it in:
#       PRIMARY_URL=https://pihole.home.arpa
#       PRIMARY_PASS='<primary admin password>'
#       SECONDARY_URL=https://127.0.0.1
#       SECONDARY_PASS='<secondary admin password>'
#       SECONDARY_DOMAIN=pihole2.home.arpa      # optional; this is the default
#   echo '*/15 * * * * root /usr/local/bin/pihole-sync' > /etc/cron.d/pihole-sync
#
# After the first sync the two admin passwords are the same, because the
# password hash is part of what's copied.
#
# `curl -k` skips certificate checks, because a home Pi-hole usually has a
# private or self-signed certificate. If yours chains to a CA this machine
# trusts (section 3.4), you can drop the -k.
#
# WHY THE CHANGE GATE: restarting Pi-hole's FTL right after a teleporter import
# leaves it unable to stop cleanly. systemd waits out the full 60-second stop
# timeout and then kills it, so the secondary dropped DNS for about a minute
# every 15 minutes: 10,472 times over three and a half months, silently,
# because `systemctl restart` still returns 0 after the kill. A restart with no
# import before it takes about 2 seconds. The likely reason is that the import
# also brings in the primary's query log (millions of rows), and FTL won't shut
# down cleanly in the middle of ingesting it. The primary's config changes
# rarely, so importing only on change removes almost every restart.

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
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['session']['sid'])" 2>/dev/null)

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
unzip -qo "$TMPFILE" -d "$SUMDIR" 2>/dev/null || true

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
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['session']['sid'])" 2>/dev/null)

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

# Restart FTL to apply imported config.
RESTART_RC=0
T0=$(date +%s)
systemctl restart pihole-FTL || RESTART_RC=$?
ELAPSED=$(( $(date +%s) - T0 ))

# `systemctl restart` returns 0 even when the stop phase timed out and FTL was
# SIGKILLed, so verify the service is genuinely serving instead of trusting the
# exit status. A restart that took ~60s is the stop-timeout path.
sleep 2
ACTIVE=$(systemctl is-active pihole-FTL 2>/dev/null || true)
DNS_OK=no
dig +short +time=3 +tries=1 @127.0.0.1 pi.hole > /dev/null 2>&1 && DNS_OK=yes

if [[ "$RESTART_RC" -ne 0 || "$ACTIVE" != "active" || "$DNS_OK" != "yes" ]]; then
  log "ERROR: FTL unhealthy after restart (rc=$RESTART_RC active=$ACTIVE dns=$DNS_OK ${ELAPSED}s); checksum not recorded, will retry next cycle"
  exit 1
fi

# Only record the checksum once the change is confirmed applied and serving,
# so a failed cycle retries rather than being skipped as "already applied".
printf '%s\n' "$NEW_SUM" > "$STATEFILE"

if [[ "$ELAPSED" -ge 30 ]]; then
  log "OK: sync complete (config changed) — WARNING: FTL stop timed out, SIGKILLed, restart took ${ELAPSED}s"
else
  log "OK: sync complete (config changed, restart ${ELAPSED}s)"
fi
