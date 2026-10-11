#!/usr/bin/env python3
"""Sweep PS3 Eye exposure/gain and recommend settings for motion tracking.

Hand-Me-Down Homelab, section 10.4 (playbook 10.4-speed-camera-pi)
Deploys to:     /usr/local/bin/speedcam-tune-exposure.py

MUST be re-run at every deployment site. There is no universal setting: the
workshop bench and a sunlit street differ by orders of magnitude, and the
values that look right indoors blow out completely outdoors.

It does NOT pick the best-looking picture. For a speed camera the objective is
different from photography:

    the LOWEST exposure whose histogram is still usable

because exposure is shutter time, and shutter time is motion blur, and motion
blur is what destroys pixel-displacement speed measurement. Noise from high
gain costs little accuracy; blur costs a lot. So among all settings with an
acceptable histogram this recommends the shortest shutter, not the prettiest
frame - those are usually different answers.

  speedcam-tune-exposure.py           sweep and recommend
  speedcam-tune-exposure.py --apply   also leave the winner applied
"""

import argparse
import subprocess
import sys
import time

import cv2

DEV = "/dev/video0"
EXPOSURES = (5, 10, 15, 20, 30, 40, 60, 80, 120)
GAINS = (0, 20, 40, 63)

# Acceptable histogram: not clipped at either end, roughly mid-grey.
MAX_BLOWN, MAX_CRUSH = 3.0, 5.0
MEAN_LO, MEAN_HI = 80.0, 155.0


def setc(k, v):
    subprocess.run([ "v4l2-ctl", "-d", DEV, "--set-ctrl", "%s=%s" % (k, v) ],
                   capture_output=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    setc("auto_exposure", 1)
    setc("gain_automatic", 0)
    setc("white_balance_automatic", 0)

    cap = cv2.VideoCapture(0, cv2.CAP_V4L2)
    if not cap.isOpened():
        sys.exit("ERROR: cannot open %s - speed-camera.service may hold it" % DEV)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

    print("%-9s %-5s %7s %8s %8s  %s" %
          ("exposure", "gain", "mean", "blown%", "crush%", "usable"))
    usable = []
    for exp in EXPOSURES:
        for gain in GAINS:
            setc("exposure", exp)
            setc("gain", gain)
            time.sleep(0.35)
            frame = None
            for _ in range(8):
                ok, f = cap.read()
                if ok:
                    frame = f
            if frame is None:
                continue
            g = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            mean = float(g.mean())
            blown = 100.0 * float((g >= 250).sum()) / g.size
            crush = 100.0 * float((g <= 5).sum()) / g.size
            ok_hist = (blown <= MAX_BLOWN and crush <= MAX_CRUSH
                       and MEAN_LO <= mean <= MEAN_HI)
            if ok_hist:
                usable.append((exp, gain, mean, blown, crush))
            print("%-9d %-5d %7.1f %8.2f %8.2f  %s" %
                  (exp, gain, mean, blown, crush, "yes" if ok_hist else ""))
    cap.release()

    if not usable:
        print("\nNo setting produced a usable histogram.")
        print("Too dark everywhere -> the scene needs more light, or accept "
              "a longer exposure and more blur.")
        print("Too bright everywhere -> try exposure below %d." % min(EXPOSURES))
        sys.exit(1)

    # Shortest shutter first; break ties on the mid-greyest frame.
    usable.sort(key=lambda r: (r[0], abs(r[2] - 115)))
    exp, gain, mean, blown, crush = usable[0]
    print("\nRECOMMENDED  exposure=%d  gain=%d" % (exp, gain))
    print("  mean %.1f, blown %.2f%%, crush %.2f%%" % (mean, blown, crush))
    print("  Chosen as the SHORTEST usable shutter, not the best-looking frame.")

    others = [r for r in usable if r[0] > exp][:3]
    if others:
        print("  Also usable but with more motion blur: " +
              ", ".join("exp=%d/gain=%d" % (r[0], r[1]) for r in others))

    print("\nApply persistently by setting these in speed-camera.service's")
    print("environment, or edit the defaults in speedcam-camera-init.sh:")
    print("  SPEEDCAM_EXPOSURE=%d SPEEDCAM_GAIN=%d" % (exp, gain))

    if args.apply:
        setc("exposure", exp)
        setc("gain", gain)
        print("\n--apply: left applied to the live device (not persistent "
              "across a service restart).")


if __name__ == "__main__":
    main()
