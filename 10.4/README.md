# 10.4 — the portable speed camera

A Raspberry Pi 3B and a Sony PlayStation 3 Eye running
[pageauc/speed-camera](https://github.com/pageauc/speed-camera), writing the
same CSV columns as the fixed camera's logger (book 10.3):
`timestamp,speed_mph,direction,vehicle_type`.

Start with the playbook, `playbooks/10.4-speed-camera-pi.md`. The folders
here mirror where each file goes on the Pi; `speedcam-provision.sh` installs
them from a copy of this folder.

```
opt/speed-camera/plugins/ps3eye.py     every tuning setting, and the calibration
opt/speed-camera/speedcam_export.py    sqlite → CSV, every 10 minutes, never duplicates
opt/speed-camera/speedcam.conf         CSV path, time zone, direction names
usr/local/bin/speedcam-provision.sh    run once, safe to re-run (sudo)
usr/local/bin/speedcam-apply-firstboot-settings.sh   time zone, locale, key-only SSH
usr/local/bin/speedcam-clock-check.sh  refuses to start on an untrustworthy clock
usr/local/bin/speedcam-camera-init.sh  locks exposure, gain, white balance
usr/local/bin/speedcam-preview.py      live aiming view (MJPEG, port 8081)
usr/local/bin/speedcam-snapshot.py     one frame with the crop band and a 10 px ruler
usr/local/bin/speedcam-tune-exposure.py  shortest exposure with a usable picture
etc/systemd/system/                    the tracker, the exporter + timer, the preview
```

Two settings are wrong until you set them, and nothing in the data shows it:

1. **The calibration** (`CAL_OBJ_MM_*`, `CAL_OBJ_PX_*`, then
   `SPEEDCAM_CALIBRATED = True`) in `ps3eye.py`. Provisioning won't enable
   the tracker until the flag is set.
2. **The direction names** (`L2R_DIRECTION`, `R2L_DIRECTION`) in
   `speedcam.conf`. They are camera-relative: turn the unit around and they
   swap.

Not tested on a clean Pi for the book; these are the author's working files
with the user, time zone and names made settings. See the playbook header.
