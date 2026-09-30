#!/bin/bash
# install-mbpfan.sh — give a Mac running Linux (Proxmox, Debian, Ubuntu) a
# working fan curve. Hand-Me-Down Homelab, section 1.2.
#
# WHY: a Mac's fan curve is run by a chip called the SMC, which takes its cues
# from macOS. Under Linux it gets no input and does something unhelpful. On one
# Mac mini it pinned the fan at full speed all day; on another it parked the
# fan at its minimum while the CPU climbed past 85 degC. Same cause, opposite
# symptoms.
#
# mbpfan takes manual control of the fan (fan1_manual = 1) and drives it from
# the CPU temperature sensors.
#
# RUN ON THE MAC, as root:
#     scp install-mbpfan.sh you@your-mac:/tmp/
#     ssh -t you@your-mac 'sudo bash /tmp/install-mbpfan.sh'
#
# Override the curve with environment variables, e.g.
#     sudo LOW_TEMP=50 HIGH_TEMP=60 MAX_TEMP=80 bash /tmp/install-mbpfan.sh
#
# Don't pipe it in as `ssh -t host 'sudo bash -s' < script`: stdin is then not
# a terminal, ssh won't allocate a terminal, and sudo can't ask for a password.
#
# Safe to re-run. An existing /etc/mbpfan.conf is backed up to
# /etc/mbpfan.conf.bak-<timestamp> before being rewritten.
#
# THE FAILURE THIS GUARDS AGAINST: once fan1_manual = 1, the fan holds whatever
# speed was last written. If mbpfan dies while the fan is slow, it STAYS slow.
# mbpfan hands control back on a clean stop, but not if it's killed or
# crashes, so this script adds a Restart=always drop-in.

set -euo pipefail

SMC="${SMC:-/sys/devices/platform/applesmc.768}"
CONF=/etc/mbpfan.conf
DROPIN_DIR=/etc/systemd/system/mbpfan.service.d
DROPIN="$DROPIN_DIR/10-restart.conf"

# Temperature curve, in degC. Below LOW_TEMP the fan sits at its minimum;
# above HIGH_TEMP it ramps; at MAX_TEMP it's at full speed. 60/70/90 is what
# the book uses on a 2012 Mac mini that idles at 56-68 degC: lower thresholds
# would have the fan audible around the clock. Check your CPU's limits with
# `sensors` before going higher.
LOW_TEMP="${LOW_TEMP:-60}"
HIGH_TEMP="${HIGH_TEMP:-70}"
MAX_TEMP="${MAX_TEMP:-90}"
POLL="${POLL:-5}"

[ "$(id -u)" -eq 0 ] || { echo "must run as root" >&2; exit 1; }

# --- preflight -------------------------------------------------------------
# Refuse rather than guess: writing a fan curve to the wrong sysfs node is not
# something to do on a best-effort basis.
[ -d "$SMC" ] || { echo "no applesmc at $SMC — is this a Mac? aborting" >&2; exit 1; }
for f in fan1_min fan1_max fan1_output fan1_manual fan1_input; do
    [ -e "$SMC/$f" ] || { echo "missing $SMC/$f — aborting" >&2; exit 1; }
done
ls /sys/devices/platform/coretemp.*/hwmon/hwmon*/temp*_input >/dev/null 2>&1 \
    || { echo "no coretemp inputs — mbpfan would have nothing to read; aborting" >&2; exit 1; }

FAN_MIN="$(cat "$SMC/fan1_min")"
FAN_MAX="$(cat "$SMC/fan1_max")"
# What the fan was ACTUALLY doing before we touched it. Don't assume
# fan1_max here: some Macs pin the fan at maximum under Linux and others park
# it at minimum.
FAN_WAS="$(cat "$SMC/fan1_output")"
echo "== host: $(hostname)"
echo "== fan1: min=$FAN_MIN max=$FAN_MAX  now: input=$(cat "$SMC/fan1_input") output=$(cat "$SMC/fan1_output") manual=$(cat "$SMC/fan1_manual")"
echo "== curve: low=$LOW_TEMP high=$HIGH_TEMP max=$MAX_TEMP degC, poll=${POLL}s"

# --- install ---------------------------------------------------------------
if ! dpkg -s mbpfan >/dev/null 2>&1; then
    echo "== installing mbpfan from apt"
    # Non-fatal: a mirror hiccup (or a Proxmox host's enterprise repo) should
    # not abort the run when the package is already indexed. The install
    # itself stays fatal, so a genuinely missing package still stops us.
    DEBIAN_FRONTEND=noninteractive apt-get update -qq || \
        echo "!! apt-get update failed — continuing with the existing package index"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mbpfan
else
    echo "== mbpfan already installed: $(dpkg-query -W -f='${Version}' mbpfan)"
fi

# --- config ----------------------------------------------------------------
if [ -f "$CONF" ]; then
    BAK="$CONF.bak-$(date +%Y%m%d-%H%M%S)"
    cp -a "$CONF" "$BAK"
    echo "== backed up existing config to $BAK"
fi

cat > "$CONF" <<EOF
# /etc/mbpfan.conf — written by install-mbpfan.sh. Re-run it to change the
# curve rather than editing this file by hand.
#
# Speeds are read from the SMC's own limits rather than hard-coded, so this
# file is correct on any Mac this script is run on.
[general]
min_fan1_speed = $FAN_MIN
max_fan1_speed = $FAN_MAX
low_temp = $LOW_TEMP
high_temp = $HIGH_TEMP
max_temp = $MAX_TEMP
polling_interval = $POLL
EOF
echo "== wrote $CONF"

# --- restart guard ---------------------------------------------------------
# See the header: a dead mbpfan leaves the fan wherever it was last set.
mkdir -p "$DROPIN_DIR"
cat > "$DROPIN" <<'EOF'
# Added by install-mbpfan.sh. Once fan1_manual = 1 the fan holds its last
# commanded speed, so an mbpfan that dies while the fan is low leaves it low.
# mbpfan restores automatic mode on a clean SIGTERM but not on SIGKILL/OOM.
[Service]
Restart=always
RestartSec=5
EOF
echo "== wrote $DROPIN"

systemctl daemon-reload
systemctl enable mbpfan >/dev/null 2>&1 || true
systemctl restart mbpfan

# --- verify ----------------------------------------------------------------
# `systemctl is-active` only says the process started. Read the fan.
sleep "$((POLL * 3))"
ACTIVE="$(systemctl is-active mbpfan || true)"
MANUAL="$(cat "$SMC/fan1_manual")"
OUTPUT="$(cat "$SMC/fan1_output")"
INPUT="$(cat "$SMC/fan1_input")"
echo
echo "== RESULT"
echo "   service   : $ACTIVE ($(systemctl is-enabled mbpfan 2>/dev/null || echo '?'))"
echo "   restart   : $(systemctl show -p Restart --value mbpfan)"
echo "   fan1_manual: $MANUAL   (1 = mbpfan is driving it)"
echo "   fan1_output: $OUTPUT   (was $FAN_WAS; min=$FAN_MIN max=$FAN_MAX)"
echo "   fan1_input : $INPUT"
echo "   temps      : $(for f in /sys/devices/platform/coretemp.*/hwmon/hwmon*/temp*_input; do printf '%s ' "$(( $(cat "$f") / 1000 ))C"; done)"
echo
journalctl -u mbpfan -n 15 --no-pager 2>/dev/null || true

RC=0
[ "$ACTIVE" = "active" ] || { echo "!! mbpfan is not active" >&2; RC=1; }
[ "$MANUAL" = "1" ]      || { echo "!! fan1_manual is $MANUAL, expected 1 — mbpfan is not driving the fan" >&2; RC=1; }
[ "$OUTPUT" -lt "$FAN_MAX" ] 2>/dev/null \
    || echo "!! fan1_output is still $OUTPUT — check the journal above; if the CPU is genuinely hot this may be correct" >&2
exit $RC
