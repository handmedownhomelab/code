#!/usr/bin/env python3
"""Live MJPEG preview of the PS3 Eye, for aiming the camera from a phone.

Hand-Me-Down Homelab, section 10.4 (playbook 10.4-speed-camera-pi)
Deploys to:     /usr/local/bin/speedcam-preview.py

Open http://<pi>:8081/ in any browser. Draws the same overlay as
speedcam-snapshot.py - the motion crop band in green and a 10 px tick ruler -
read live from the plugin, so what you see is what speed-cam.py will measure.

This exists because aiming is the one genuinely interactive step: point, look,
adjust, repeat. A snapshot round-trip is fine for calibration but painful for
aiming, and a monitor on the Pi does not help - the Pi has to be out at the
street with the camera, and a monitor cannot follow it there. A phone can.

Run it only while aiming. It holds /dev/video0, so speed-camera.service cannot
run at the same time; the systemd unit declares Conflicts= to enforce that.

Unauthenticated and LAN-only by design. Do not leave it running.
"""

import argparse
import re
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import cv2

PLUGIN = "/opt/speed-camera/plugins/ps3eye.py"
BOUNDARY = "speedcamframe"


def plugin_vals(path=PLUGIN):
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
    return out


def overlay(frame, v):
    if not all(k in v for k in ("MO_CROP_X_LEFT", "MO_CROP_X_RIGHT",
                                "MO_CROP_Y_UPPER", "MO_CROP_Y_LOWER")):
        return frame
    x1, x2 = v["MO_CROP_X_LEFT"], v["MO_CROP_X_RIGHT"]
    y1, y2 = v["MO_CROP_Y_UPPER"], v["MO_CROP_Y_LOWER"]
    cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 1)
    for x in range(x1, x2 + 1, 10):
        tall = ((x - x1) % 100 == 0)
        cv2.line(frame, (x, y2), (x, y2 - (10 if tall else 5)), (255, 255, 0), 1)
        if tall:
            cv2.putText(frame, str(x - x1), (x + 2, y2 - 12),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.3, (255, 255, 0), 1)
    cv2.putText(frame, "band %d-%d x  %d-%d y   ticks=10px" % (x1, x2, y1, y2),
                (4, 14), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 255, 0), 1)
    cv2.putText(frame, time.strftime("%H:%M:%S"), (4, frame.shape[0] - 6),
                cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)
    return frame


PAGE = b"""<!doctype html><meta name=viewport content="width=device-width,initial-scale=1">
<title>speed camera aim</title>
<style>body{margin:0;background:#111;color:#ccc;font:14px system-ui;text-align:center}
img{width:100%;max-width:960px;image-rendering:pixelated}
p{margin:.5em}</style>
<p>Speed camera &mdash; live aim view. Green = measurement band, ticks = 10&nbsp;px.</p>
<img src="/stream.mjpg">
<p>Stop when done: <code>sudo systemctl stop speedcam-preview</code></p>
"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(PAGE)))
            self.end_headers()
            self.wfile.write(PAGE)
            return
        if self.path != "/stream.mjpg":
            self.send_error(404)
            return

        self.send_response(200)
        self.send_header("Age", "0")
        self.send_header("Cache-Control", "no-cache, private")
        self.send_header("Content-Type",
                         "multipart/x-mixed-replace; boundary=%s" % BOUNDARY)
        self.end_headers()
        v = plugin_vals()
        try:
            while True:
                ok, frame = self.server.cap.read()
                if not ok:
                    time.sleep(0.05)
                    continue
                ok, jpg = cv2.imencode(".jpg", overlay(frame, v),
                                       [cv2.IMWRITE_JPEG_QUALITY, 70])
                if not ok:
                    continue
                buf = jpg.tobytes()
                self.wfile.write(b"--%s\r\n" % BOUNDARY.encode())
                self.send_header("Content-Type", "image/jpeg")
                self.send_header("Content-Length", str(len(buf)))
                self.end_headers()
                self.wfile.write(buf)
                self.wfile.write(b"\r\n")
        except (BrokenPipeError, ConnectionResetError):
            pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-p", "--port", type=int, default=8081)
    args = ap.parse_args()

    cap = cv2.VideoCapture(0, cv2.CAP_V4L2)
    if not cap.isOpened():
        raise SystemExit("ERROR: cannot open /dev/video0 - is "
                         "speed-camera.service running and holding it?")
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    # Small buffer so the preview shows now, not three frames ago - it is
    # useless for aiming if it lags behind your hand on the camera.
    try:
        cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    except Exception:
        pass

    srv = ThreadingHTTPServer(("", args.port), Handler)
    srv.cap = cap
    srv.daemon_threads = True
    print("preview on http://0.0.0.0:%d/  (ctrl-c to stop)" % args.port)
    try:
        srv.serve_forever()
    finally:
        cap.release()


if __name__ == "__main__":
    main()
