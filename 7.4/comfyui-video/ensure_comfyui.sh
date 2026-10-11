#!/usr/bin/env bash
# ensure_comfyui.sh — Hand-Me-Down Homelab, section 7.4. Part of the
# comfyui-video skill; runs on your workstation.
# Ensure the local ComfyUI API is reachable at 127.0.0.1:8188.
# If it's down, launch the tunnel + comfyui-run.sh on the GPU box in the background
# and wait until the API responds. Exit 0 = ready, non-zero = could not start.
set -u
GPU_HOST="${GPU_HOST:-you@gpu-box.home.arpa}"   # edit, or set in the environment

HOST="127.0.0.1:8188"
LOG="$(dirname "$0")/comfyui-run.log"

up() { curl -s -m 4 "http://$HOST/system_stats" 2>/dev/null | grep -q '"system"'; }

if up; then
  echo "comfyui: already up"
  exit 0
fi

echo "comfyui: down — launching tunnel + comfyui-run.sh on $GPU_HOST (logging to $LOG)"
ssh -f -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
    -L 8188:localhost:8188 "$GPU_HOST" './comfyui-run.sh' \
    > "$LOG" 2>&1

echo -n "comfyui: starting"
for i in $(seq 1 40); do            # up to ~120s for startup
  if up; then echo " — ready"; exit 0; fi
  echo -n "."
  sleep 3
done

echo
echo "comfyui: did not become ready in time — check $LOG and the GPU box" >&2
exit 1
