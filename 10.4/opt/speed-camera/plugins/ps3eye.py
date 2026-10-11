# ---------------------------------------------------------------------------
# speed-cam.py plugin - Sony PlayStation 3 Eye on a Raspberry Pi 3B v1.2
# Hand-Me-Down Homelab, section 10.4 (playbook 10.4-speed-camera-pi)
# Deploys to:     /opt/speed-camera/plugins/ps3eye.py
#
# speed-cam.py imports this file AFTER config.py and it OVERRIDES config.py.
# Every tunable for this build lives here so config.py stays stock - the only
# two lines patched in config.py are PLUGIN_ENABLE_ON and PLUGIN_NAME.
#
# Activated by /usr/local/bin/speedcam-provision.sh.
# ---------------------------------------------------------------------------

# --- Camera ----------------------------------------------------------------
CAMERA = "usbcam"
USBCAM_SRC = 0
CAM_LOCATION = "Portable - unset"   # set per deployment; lands in the sqlite row

# 640x480 @ 30 fps = 18.4 MB/s of uncompressed YUYV. The PS3 Eye can do 60 fps
# at this size, but that is 36.9 MB/s and the Pi 3B shares one USB 2.0
# controller with its Ethernet NIC - it will drop frames. Do not raise this to
# 60 without dropping to 320x240 first. See the playbook.
IM_SIZE = (640, 480)
IM_FRAMERATE = 30

# --- CALIBRATION - MUST BE SET PER DEPLOYMENT ------------------------------
# These four numbers are the entire speed measurement. Wrong values produce
# confident, plausible, wrong speeds - there is no error that reveals them.
#
# CAL_OBJ_MM_* is the true length of a reference vehicle in millimetres.
# CAL_OBJ_PX_* is that same vehicle's length in pixels, read off a captured
# image, measured SEPARATELY per direction because the near and far lanes sit
# at different distances from the camera and therefore different px/m scales.
#
# Procedure: playbook 10.4, step "Calibrate".
# 4500 mm is a typical midsize sedan; measure the actual car you use.
#
# The PX values below are UPSTREAM PLACEHOLDERS, not measurements - they are
# deliberately non-zero because speed-cam.py computes CAL_OBJ_MM / CAL_OBJ_PX
# at startup, so a zero here is a ZeroDivisionError before the program can even
# open the camera - which would make the calibration procedure (run it, look at
# the alignment image, measure a car) impossible to perform.
#
# The real gate is SPEEDCAM_CALIBRATED below.
CAL_OBJ_MM_L2R = 4500.0
CAL_OBJ_PX_L2R = 80         # PLACEHOLDER - measure this
CAL_OBJ_MM_R2L = 4500.0
CAL_OBJ_PX_R2L = 85         # PLACEHOLDER - measure this

# Set True ONLY after measuring a reference vehicle in BOTH directions and
# validating against a known-speed pass. speedcam-provision.sh refuses to
# enable speed-camera.service while this is False, because an uncalibrated run
# does not fail - it logs confident wrong speeds that cannot be told apart from
# real ones afterwards.
SPEEDCAM_CALIBRATED = False

# Upstream default is True and speed-cam.py inherits it, so set it here
# deliberately rather than by accident. CALIBRATE_ON draws hash markers every
# 10 px on every saved image - that is the ruler you measure CAL_OBJ_PX with,
# so it must be ON while calibrating. It also forces every track to be logged
# regardless of MO_MAX_SPEED_OVER and disables recent-folder pruning, so it
# must be turned OFF for production or images accumulate unpruned.
# Flip this to False at the same moment SPEEDCAM_CALIBRATED becomes True.
CALIBRATE_ON = True

# --- Motion tracking window ------------------------------------------------
# A NARROW horizontal band. speed-cam applies ONE px/mm constant per direction,
# which is only true at one distance from the camera, so every measurement must
# happen at roughly constant range. A tall crop silently mixes scales.
# Values below are a starting point for a camera square-on to the street at
# 640x480 - retune during calibration with IM_SHOW_CROP_AREA_ON.
MO_CROP_AUTO_ON = False
MO_CROP_X_LEFT = 40
MO_CROP_X_RIGHT = 600
MO_CROP_Y_UPPER = 200
MO_CROP_Y_LOWER = 300

# --- Motion event tuning ---------------------------------------------------
# At 640x480/30fps a 30 mph car moves ~27 px/frame and a 60 mph car ~54 px.
# MO_MAX_X_DIFF_PX must clear the fastest vehicle worth recording or it is
# silently discarded - the stock default of 20 would drop everything.
MO_MAX_X_DIFF_PX = 70
MO_MIN_X_DIFF_PX = 1
MO_TRACK_EVENT_COUNT = 8      # quad-core Pi; more samples = smoother average
MO_MIN_AREA_PX = 300          # rejects birds/leaves, keeps motorcycles
MO_X_LR_SIDE_BUFF_PX = 10
MO_TRACK_TIMEOUT_SEC = 0.5
MO_EVENT_TIMEOUT_SEC = 0.3
MO_LOG_OUT_RANGE_ON = True

# Log EVERY vehicle, including slow ones. A traffic report's headline statistic
# is the share exceeding the limit, which needs the whole distribution as its
# denominator. Filtering here would silently inflate every percentage.
MO_MAX_SPEED_OVER = 0

# --- Units and output ------------------------------------------------------
MO_SPEED_MPH_ON = True
LOG_DATA_TO_CSV = True        # raw sidecar CSV; the exporter reads sqlite
LOG_TO_FILE_ON = False        # journald captures stdout instead

# --- Headless --------------------------------------------------------------
GUI_WINDOW_ON = False         # required when running over SSH / as a service
GUI_IMAGE_WIN_ON = False
GUI_THRESH_WIN_ON = False
GUI_CROP_WIN_ON = False
ALIGN_CAM_ON = False          # flip True temporarily to aim the camera

# --- Saved images ----------------------------------------------------------
# Kept small: the SD card is the only storage on a portable unit.
IM_BIGGER = 1.0
IM_SHOW_CROP_AREA_ON = True   # draws the crop band - keep on, it is how you
                              # confirm the band is still on the road
IM_SHOW_SPEED_FILENAME_ON = True
IM_SHOW_TEXT_ON = True
IM_SHOW_TEXT_BOTTOM_ON = True
IM_FONT_SIZE_PX = 16
IM_FONT_SCALE = 0.5
IM_FONT_THICKNESS = 2
IM_FONT_COLOR = (255, 255, 255)
