#!/usr/bin/env python3
"""Grab a frame from the PS3 Eye with the measurement band drawn on it.

Hand-Me-Down Homelab, section 10.4 (playbook 10.4-speed-camera-pi)
Deploys to:     /usr/local/bin/speedcam-snapshot.py

This is the aiming and calibration tool. It reads the live crop-band settings
straight out of the plugin, so what it draws is what speed-cam.py will actually
measure - not a guess.

  speedcam-snapshot.py                  -> /tmp/speedcam-snap.jpg
  speedcam-snapshot.py -o /tmp/a.jpg    -> chosen path
  speedcam-snapshot.py --plain          -> no overlay, raw frame

Overlay:
  green box    the motion crop band. Vehicles are only measured inside it, and
               it must stay NARROW vertically - one px/mm scale is applied per
               direction, so a tall band silently mixes scales.
  cyan ticks   10 px hash marks along the band's bottom edge. This is the ruler
               for CAL_OBJ_PX: park a car of known length in a lane, count the
               ticks it spans, multiply by 10.

Will fail if speed-camera.service is running - it holds /dev/video0. Stop it
first, or just take the snapshot before enabling the service.
"""

import argparse
import re
import sys
import time

import cv2

PLUGIN = "/opt/speed-camera/plugins/ps3eye.py"


def plugin_vals(path):
    """Read the settings that matter from the plugin, with sane fallbacks."""
    out = {}
    try:
        src = open(path).read()
    except OSError:
        return out
    for key in ("MO_CROP_X_LEFT", "MO_CROP_X_RIGHT",
                "MO_CROP_Y_UPPER", "MO_CROP_Y_LOWER"):
        m = re.search(r"^%s\s*=\s*(\d+)" % key, src, re.M)
        if m:
            out[key] = int(m.group(1))
    m = re.search(r"^IM_SIZE\s*=\s*\((\d+)\s*,\s*(\d+)\)", src, re.M)
    if m:
        out["W"], out["H"] = int(m.group(1)), int(m.group(2))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out", default="/tmp/speedcam-snap.jpg")
    ap.add_argument("-d", "--device", type=int, default=0)
    ap.add_argument("--plain", action="store_true", help="no overlay")
    ap.add_argument("--warmup", type=int, default=12,
                    help="frames to discard before capturing (clears the buffer)")
    args = ap.parse_args()

    v = plugin_vals(PLUGIN)
    w, h = v.get("W", 640), v.get("H", 480)

    cap = cv2.VideoCapture(args.device, cv2.CAP_V4L2)
    if not cap.isOpened():
        sys.exit("ERROR: cannot open /dev/video%d - is speed-camera.service "
                 "running and holding it? (systemctl status speed-camera)"
                 % args.device)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, w)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, h)

    frame = None
    for _ in range(max(1, args.warmup)):
        ok, f = cap.read()
        if ok:
            frame = f
        time.sleep(0.03)
    cap.release()

    if frame is None:
        sys.exit("ERROR: opened the device but read no frames")

    ah, aw = frame.shape[:2]
    if (aw, ah) != (w, h):
        print("NOTE: asked for %dx%d, got %dx%d" % (w, h, aw, ah))

    if not args.plain and all(k in v for k in
                              ("MO_CROP_X_LEFT", "MO_CROP_X_RIGHT",
                               "MO_CROP_Y_UPPER", "MO_CROP_Y_LOWER")):
        x1, x2 = v["MO_CROP_X_LEFT"], v["MO_CROP_X_RIGHT"]
        y1, y2 = v["MO_CROP_Y_UPPER"], v["MO_CROP_Y_LOWER"]
        cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 1)
        # 10 px ruler along the bottom edge of the band
        for x in range(x1, x2 + 1, 10):
            tall = ((x - x1) % 100 == 0)
            cv2.line(frame, (x, y2), (x, y2 - (10 if tall else 5)),
                     (255, 255, 0), 1)
            if tall:
                cv2.putText(frame, str(x - x1), (x + 2, y2 - 12),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.3, (255, 255, 0), 1)
        cv2.putText(frame, "band %d-%d x  %d-%d y   ticks=10px" % (x1, x2, y1, y2),
                    (4, 14), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 255, 0), 1)
        cv2.putText(frame, time.strftime("%Y-%m-%d %H:%M:%S"),
                    (4, ah - 6), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)

    if not cv2.imwrite(args.out, frame):
        sys.exit("ERROR: could not write %s" % args.out)
    print("wrote %s (%dx%d)" % (args.out, aw, ah))


if __name__ == "__main__":
    main()
