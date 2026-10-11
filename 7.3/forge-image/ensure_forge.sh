#!/usr/bin/env bash
# ensure_forge.sh — Hand-Me-Down Homelab, section 7.3. Part of the forge-image
# skill; runs on your workstation. If Forge's API isn't answering on
# localhost:7860, open the tunnel and run forge-run.sh on the GPU box in the
# background, then wait for the API. Exit 0 = ready, non-zero = it didn't start.
set -u
GPU_HOST="${GPU_HOST:-you@gpu-box.home.arpa}"   # edit, or set in the environment
HOST="127.0.0.1:7860"
LOG="$(dirname "$0")/forge-run.log"

up() { curl -s -m 4 "http://$HOST/sdapi/v1/sd-models" 2>/dev/null | grep -q '"title"'; }

if up; then echo "forge: already up"; exit 0; fi

echo "forge: down, launching tunnel + forge-run.sh on $GPU_HOST (log: $LOG)"
# -f backgrounds ssh after login; the remote forge-run.sh keeps the session,
# and with it the port forward, alive while Forge runs.
ssh -f -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
    -L 7860:localhost:7860 "$GPU_HOST" './forge-run.sh' > "$LOG" 2>&1

echo -n "forge: starting"
for i in $(seq 1 40); do            # up to ~120 s for the model to load
  if up; then echo " ready"; exit 0; fi
  echo -n "."; sleep 3
done
echo
echo "forge: not ready in time; check $LOG and the GPU box" >&2
exit 1
