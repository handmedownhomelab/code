#!/bin/bash
# Lock the PS3 Eye's exposure, gain and white balance before speed-cam.py
# opens it.
#
# Hand-Me-Down Homelab, section 10.4 (playbook 10.4-speed-camera-pi)
# Deploys to:     /usr/local/bin/speedcam-camera-init.sh
#
# Why: with auto-exposure on, the camera re-meters when a vehicle enters frame.
# The whole image shifts brightness, frame differencing sees that as motion
# across the entire crop band, and the tracker emits phantom events - or loses
# a real vehicle mid-track and reports a fragment of its true speed.
#
# Control names/ranges below were read off the live gspca_ov534 driver on
# the author's Pi (kernel 6.18, Trixie) on 2026-09-09, not guessed:
#
#   auto_exposure           menu  0=Auto 1=Manual      default 0
#   gain_automatic          bool                       default 1
#   white_balance_automatic bool                       default 1
#   exposure                int   0-255                default 120  (auto-gated)
#   gain                    int   0-63                 default 20   (auto-gated)
#   sharpness               int   0-63                 default 0
#
# ORDER MATTERS: exposure and gain report flags=inactive,volatile while their
# auto controls are on, so the auto controls must be turned off FIRST or the
# manual values are silently discarded.

set -uo pipefail

DEV="${1:-/dev/video0}"

# Daylight starting points. LOWER exposure = shorter shutter = less motion
# blur, which is the whole reason this camera was chosen. If the image is too
# dark, raise GAIN first and only then exposure - noise costs little accuracy,
# blur costs a lot.
EXPOSURE="${SPEEDCAM_EXPOSURE:-40}"
GAIN="${SPEEDCAM_GAIN:-20}"

if [ ! -e "$DEV" ]; then
    echo "ERROR: $DEV not present - is the PS3 Eye plugged in?" >&2
    exit 1
fi

set_ctrl() {
    if v4l2-ctl -d "$DEV" --set-ctrl="$1=$2" >/dev/null 2>&1; then
        echo "  set $1=$2"
    else
        echo "  WARN: could not set $1=$2" >&2
    fi
}

echo "speedcam-camera-init: $DEV"

# 1. Auto controls OFF first - this is what makes the manual ones settable.
set_ctrl auto_exposure 1              # 1 = Manual Mode
set_ctrl gain_automatic 0
set_ctrl white_balance_automatic 0

# 2. Now the manual values will stick.
set_ctrl exposure "$EXPOSURE"
set_ctrl gain "$GAIN"
set_ctrl sharpness 0                  # sharpening adds edge artifacts that
                                      # frame differencing reads as motion

# 3. Verify rather than trust the sets above: a control that is still
#    auto-gated accepts the ioctl and keeps its old value.
echo "--- verifying ---"
rc=0
for pair in "auto_exposure=1" "gain_automatic=0" "white_balance_automatic=0" \
            "exposure=$EXPOSURE" "gain=$GAIN"; do
    k="${pair%%=*}"; want="${pair##*=}"
    # Menu controls read back as "1 (Manual Mode)", so keep only the numeric
    # token - otherwise a correctly-set control compares unequal.
    got=$(v4l2-ctl -d "$DEV" --get-ctrl="$k" 2>/dev/null | awk -F': ' '{print $2}' | awk '{print $1}')
    if [ "$got" = "$want" ]; then
        echo "  ok   $k=$got"
    else
        echo "  FAIL $k: wanted $want, got ${got:-<unreadable>}" >&2
        rc=1
    fi
done

[ $rc -eq 0 ] && echo "speedcam-camera-init: all controls confirmed" \
              || echo "speedcam-camera-init: one or more controls did NOT stick" >&2
exit $rc
