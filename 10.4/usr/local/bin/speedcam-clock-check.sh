#!/bin/bash
# speedcam-clock-check.sh - refuse to start the tracker on an untrustworthy clock.
#
# Hand-Me-Down Homelab, section 10.4 (playbook 10.4-speed-camera-pi)
# Deploys to:     /usr/local/bin/speedcam-clock-check.sh
# Runs as:        ExecStartPre of speed-camera.service
#
# Every row the tracker logs is stamped with the system clock, so a wrong clock
# makes every row wrong, and nothing in the data can reveal it afterwards.
#
# Why this exists - the first boot with the DS3231 fitted, 2026-09-10, by
# seconds since boot:
#    8.57 s  kernel sets the clock from the still-unset RTC  -> 2000-01-01
#    8.58 s  systemd advances it to the timesyncd clock file -> 2026-09-10 15:12:26
#   42.49 s  NTP syncs                                       -> 15:19:37
# For 34 s the clock read a plausible current-year time about 7 minutes slow:
# the moment the Pi was last running. Offline with a dead RTC cell there is no
# NTP step, so every row would be shifted back by however long the unit sat
# unpowered - hours or days in transit - and the exporter's MIN_VALID_YEAR
# would pass all of it. That guard only catches a clock stuck at the epoch,
# and systemd's clock-file advance means this OS never leaves it there.
#
# Rule: the clock is trustworthy if NTP has synchronised it, or if it agrees
# with a readable RTC. A dead cell leaves the RTC near 2000 while systemd has
# advanced the system clock to the current year, so they disagree by decades.
#
# Deliberately NOT a reason to refuse: the kernel's "rtc-ds1307 ... SET TIME!"
# oscillator-stop warning. On this module it appeared on both power-loss boots
# measured on 2026-09-10 - after outages of minutes and of 5 hours - with the
# clock only ~6 s off each time. Refusing on it would block every offline start.
#
# Compared against the RTC directly rather than by grepping the boot log: the
# runtime journal rotates, so a tracker restart days into a deployment would no
# longer find the boot-time kernel warning.

set -uo pipefail

# Normal drift allowance. Without NTP the system clock free-runs on the Pi's
# crystal after boot while the RTC keeps better time - seconds per day apart.
# A dead cell disagrees by years, so 600 s tolerates weeks of drift and still
# separates the two cases by orders of magnitude.
MAX_SKEW="${SPEEDCAM_MAX_CLOCK_SKEW:-600}"

# Test overrides, so the offline and dead-cell branches can be exercised on a
# healthy unit. Not for production.
NTP="${SPEEDCAM_TEST_NTP:-$(timedatectl show -p NTPSynchronized --value 2>/dev/null)}"
RTC_SRC="${SPEEDCAM_TEST_RTC_EPOCH_FILE:-/sys/class/rtc/rtc0/since_epoch}"

if [ "$NTP" = "yes" ]; then
    echo "clock-check: OK - NTP synchronised"
    exit 0
fi

RTC=$(cat "$RTC_SRC" 2>/dev/null)
if ! [[ "$RTC" =~ ^[0-9]+$ ]]; then
    echo "clock-check: REFUSING - NTP not synchronised and no readable RTC ($RTC_SRC)." >&2
    echo "  Rows would be stamped with an unverified clock. Reseat or replace the" >&2
    echo "  DS3231, or give the unit network until timedatectl shows synchronized: yes." >&2
    exit 1
fi

SYS=$(date +%s)
SKEW=$(( SYS > RTC ? SYS - RTC : RTC - SYS ))

if [ "$SKEW" -le "$MAX_SKEW" ]; then
    echo "clock-check: OK - no NTP, system clock agrees with RTC (skew ${SKEW}s)"
    exit 0
fi

echo "clock-check: REFUSING - NTP not synchronised and system clock disagrees with the RTC by ${SKEW}s." >&2
echo "  system: $(date -u -d "@$SYS" '+%F %T UTC')    rtc: $(date -u -d "@$RTC" '+%F %T UTC')" >&2
echo "  This is the dead-RTC-cell signature. Nothing will be logged. Replace the" >&2
echo "  DS3231 module, then with network up and synchronized: yes, run: sudo hwclock -w" >&2
exit 1
