#!/bin/bash
# Provision a Raspberry Pi 3B + PS3 Eye as a portable speed camera.
#
# Hand-Me-Down Homelab, section 10.4 (playbook 10.4-speed-camera-pi)
# Deploys to:     /usr/local/bin/speedcam-provision.sh
#
# Idempotent: safe to re-run after editing the plugin or the exporter.
# Run as: sudo speedcam-provision.sh
#
# Deliberately does NOT use pageauc's curl|bash installer. That script pulls a
# desktop-oriented dependency set and can try to build OpenCV from source,
# which on a 1 GB Pi 3B takes many hours and can OOM. Everything here comes
# from apt.

set -euo pipefail

REPO_URL="https://github.com/pageauc/speed-camera.git"
INSTALL_DIR="/opt/speed-camera"
# The account the tracker runs as: the one that ran sudo, unless set.
RUN_USER="${RUN_USER:-${SUDO_USER:-}}"
PLUGIN="ps3eye"
STATE_DIR="/var/lib/speedcam"
STAGE="${STAGE:-/home/${RUN_USER}/speedcam-stage}"

log()  { printf '\n=== %s\n' "$*"; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run with sudo"
[ -n "$RUN_USER" ] || die "set RUN_USER, or run through sudo from that account"
id "$RUN_USER" >/dev/null 2>&1 || die "user $RUN_USER does not exist"
[ -d "$STAGE" ] || die "staging dir $STAGE not found - copy the companion 10.4/ tree there first (see the playbook)"

# ---------------------------------------------------------------- packages --
log "Installing packages from apt"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    git python3 python3-opencv python3-numpy v4l-utils sqlite3 i2c-tools

python3 -c 'import cv2, numpy' \
    || die "python3 cannot import cv2/numpy after install"
echo "OpenCV $(python3 -c 'import cv2; print(cv2.__version__)') present"

# -------------------------------------------------------------------- repo --
log "Installing speed-camera into $INSTALL_DIR"
if [ -d "$INSTALL_DIR/.git" ]; then
    git -C "$INSTALL_DIR" pull --ff-only || echo "WARN: pull failed, keeping existing checkout"
else
    tmp="$(mktemp -d)"
    git clone --depth 1 "$REPO_URL" "$tmp/sc"
    mkdir -p "$INSTALL_DIR"
    cp -r "$tmp/sc/source/." "$INSTALL_DIR/"
    rm -rf "$tmp"
fi
mkdir -p "$INSTALL_DIR/plugins" "$INSTALL_DIR/data" "$STATE_DIR"

# ------------------------------------------------------------- our overlay --
log "Installing plugin, exporter and export config"
# NEVER clobber a calibrated plugin. CAL_OBJ_PX_* are measurements taken with a
# tape measure at the deployment site; overwriting them with the shipped
# placeholders would silently reset the instrument to garbage and the service
# would keep running, logging confident wrong speeds.
if [ -f "$INSTALL_DIR/plugins/${PLUGIN}.py" ] \
   && grep -qE '^SPEEDCAM_CALIBRATED[[:space:]]*=[[:space:]]*True' "$INSTALL_DIR/plugins/${PLUGIN}.py"; then
    echo "  KEEPING calibrated plugin ${PLUGIN}.py (SPEEDCAM_CALIBRATED=True)"
    echo "  To take the shipped version, move it aside first."
else
    install -m 0644 "$STAGE/opt/speed-camera/plugins/${PLUGIN}.py" "$INSTALL_DIR/plugins/${PLUGIN}.py"
    echo "  installed plugin ${PLUGIN}.py"
fi
install -m 0755 "$STAGE/opt/speed-camera/speedcam_export.py"   "$INSTALL_DIR/speedcam_export.py"
# Never clobber a tuned conf on re-run - direction mapping is per deployment.
if [ -f "$INSTALL_DIR/speedcam.conf" ]; then
    echo "  keeping existing speedcam.conf (edit it by hand)"
else
    install -m 0644 "$STAGE/opt/speed-camera/speedcam.conf" "$INSTALL_DIR/speedcam.conf"
fi
for tool in speedcam-camera-init.sh speedcam-provision.sh \
            speedcam-apply-firstboot-settings.sh \
            speedcam-snapshot.py speedcam-preview.py speedcam-tune-exposure.py \
            speedcam-clock-check.sh; do
    if [ -f "$STAGE/usr/local/bin/$tool" ]; then
        install -m 0755 "$STAGE/usr/local/bin/$tool" "/usr/local/bin/$tool"
        echo "  installed /usr/local/bin/$tool"
    else
        echo "  WARN: $tool missing from stage - skipped"
    fi
done

# --------------------------------------------------- activate plugin in cfg --
# Two anchored, idempotent line rewrites. Fails loudly if a key is absent,
# because a silently-unpatched config.py runs the stock picam settings and
# produces plausible nonsense rather than an error.
log "Activating plugin '$PLUGIN' in config.py"
python3 - "$INSTALL_DIR/config.py" "$PLUGIN" <<'PYEOF'
import re, sys
path, plugin = sys.argv[1], sys.argv[2]
src = open(path).read()
edits = {"PLUGIN_ENABLE_ON": "True", "PLUGIN_NAME": '"%s"' % plugin}
for key, val in edits.items():
    pat = re.compile(r"^%s\s*=.*$" % re.escape(key), re.M)
    if not pat.search(src):
        sys.exit("ERROR: %s not found in %s - upstream config.py changed" % (key, path))
    src = pat.sub("%s = %s" % (key, val), src, count=1)
open(path, "w").write(src)
# Read back rather than trusting the write.
back = open(path).read()
for key, val in edits.items():
    if not re.search(r"^%s\s*=\s*%s\s*(#.*)?$" % (re.escape(key), re.escape(val)), back, re.M):
        sys.exit("ERROR: verification failed for %s" % key)
print("  config.py patched and verified: PLUGIN_ENABLE_ON=True PLUGIN_NAME=%s" % plugin)
PYEOF

chown -R "$RUN_USER":"$RUN_USER" "$INSTALL_DIR" "$STATE_DIR"

# --------------------------------------------------------------------- RTC --
# A portable unit has no network, and a Pi has no battery-backed clock. Without
# this, every timestamp after a cold boot is wrong and the CSV is unusable.
log "Configuring DS3231 real-time clock"
BOOTCFG=/boot/firmware/config.txt
[ -f "$BOOTCFG" ] || BOOTCFG=/boot/config.txt
if grep -q "^dtoverlay=i2c-rtc,ds3231" "$BOOTCFG"; then
    echo "  overlay already present in $BOOTCFG"
else
    printf '\n# DS3231 RTC for portable speed camera\ndtparam=i2c_arm=on\ndtoverlay=i2c-rtc,ds3231\n' >> "$BOOTCFG"
    echo "  overlay appended to $BOOTCFG (takes effect next boot)"
    OVERLAY_ADDED=1
fi
if dpkg -l fake-hwclock 2>/dev/null | grep -q '^ii'; then
    systemctl disable --now fake-hwclock 2>/dev/null || true
    echo "  fake-hwclock disabled (it would overwrite the real RTC at boot)"
fi
# >>> rtc-detect
# Detect the RTC the way the kernel sees it, through sysfs. NOT via i2cdetect:
# that needs the i2c-dev userspace module, which this build never loads, so it
# failed silently and printed "no DS3231 seen" on 2026-09-10 with the module
# fitted and registered as rtc0. For manual bus debugging: sudo modprobe i2c-dev
RTC_SYSFS="${SPEEDCAM_TEST_RTC_SYSFS:-/sys/class/rtc}"
RTC_FOUND=""
for r in "$RTC_SYSFS"/rtc*; do
    [ -e "$r/device" ] || continue
    case "$(readlink -f "$r/device")" in
        */i2c-1/1-0068) RTC_FOUND="$(basename "$r") ($(cat "$r/name" 2>/dev/null))"; break ;;
    esac
done
if [ -n "$RTC_FOUND" ]; then
    echo "  DS3231 detected: $RTC_FOUND"
elif [ "${OVERLAY_ADDED:-0}" = 1 ]; then
    echo "  overlay added this run - reboot, then re-run to confirm the module"
else
    echo "  WARN: no RTC registered on i2c-1 at 0x68 - module not fitted, not seated,"
    echo "        or its overlay is not active. Offline, the Pi would then boot to a"
    echo "        plausible but wrong clock; speedcam-clock-check.sh refuses to start"
    echo "        the tracker until NTP syncs or a working RTC is present."
fi
# <<< rtc-detect

# ----------------------------------------------------------------- systemd --
log "Installing systemd units"
for unit in speed-camera.service speedcam-export.service speedcam-export.timer \
            speedcam-preview.service; do
    # The units ship with User=/Group= placeholders; fill in RUN_USER.
    sed -e "s/^User=.*/User=$RUN_USER/" -e "s/^Group=.*/Group=$RUN_USER/" \
        "$STAGE/etc/systemd/system/$unit" > "/etc/systemd/system/$unit"
    chmod 0644 "/etc/systemd/system/$unit"
done
# speedcam-preview.service is installed but never enabled - it has no [Install]
# section, holds /dev/video0 and is unauthenticated. Started by hand for aiming.
systemctl daemon-reload
systemctl enable --now speedcam-export.timer

# ------------------------------------------------------- calibration gate ---
# Refuse to start collecting until the camera is calibrated. An uncalibrated
# run does not fail; it silently produces confident wrong speeds, and there is
# no way to tell them apart afterwards.
#
# Gated on an explicit SPEEDCAM_CALIBRATED flag rather than on CAL_OBJ_PX being
# zero: speed-cam.py divides by that value at startup, so a zero sentinel would
# crash it before the operator could run it in order to calibrate.
CAL=$(grep -oE '^SPEEDCAM_CALIBRATED[[:space:]]*=[[:space:]]*(True|False)' \
      "$INSTALL_DIR/plugins/${PLUGIN}.py" | grep -oE '(True|False)$')
[ -n "$CAL" ] || CAL=MISSING

log "Provisioning complete"
if [ "$CAL" = "MISSING" ]; then
    echo "  ERROR: SPEEDCAM_CALIBRATED not found in the plugin - refusing to enable." >&2
elif [ "$CAL" != "True" ]; then
    cat <<MSG

  speed-camera.service is installed but NOT enabled: the camera is
  uncalibrated (SPEEDCAM_CALIBRATED=$CAL).

  Calibrate first - see playbook 10.4-speed-camera-pi, step "Calibrate". Then set
  CAL_OBJ_PX_L2R / CAL_OBJ_PX_R2L and flip SPEEDCAM_CALIBRATED = True in
  $INSTALL_DIR/plugins/${PLUGIN}.py, then run:

      sudo systemctl enable --now speed-camera.service

MSG
else
    systemctl enable speed-camera.service
    L2R=$(grep -oE '^CAL_OBJ_PX_L2R[[:space:]]*=[[:space:]]*[0-9.]+' "$INSTALL_DIR/plugins/${PLUGIN}.py" | grep -oE '[0-9.]+$')
    R2L=$(grep -oE '^CAL_OBJ_PX_R2L[[:space:]]*=[[:space:]]*[0-9.]+' "$INSTALL_DIR/plugins/${PLUGIN}.py" | grep -oE '[0-9.]+$')
    echo "  calibrated (L2R=$L2R px, R2L=$R2L px). Start with:"
    echo "      sudo systemctl start speed-camera.service"
fi
