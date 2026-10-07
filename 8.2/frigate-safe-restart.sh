#!/usr/bin/env bash
# frigate-safe-restart.sh — Hand-Me-Down Homelab, section 8.2.
# The safe way to restart or update Frigate on a GPU it shares with Ollama.
# Frees Ollama's VRAM first (so the detector can cold-start), recreates the
# container, then VERIFIES the detector is processing frames -- not just that
# the container is "healthy", which is NOT evidence detection works.
# Expects free-ollama-vram.sh beside it in ~/bin, and Frigate's compose file
# in ~/frigate (override with FRIGATE_DIR).
#
#   frigate-safe-restart.sh          # restart on the current image
#   PULL=1 frigate-safe-restart.sh   # pull newer image first, then restart
#
# Exit 0 = detector confirmed processing frames. Exit 1 = detector did not
# recover (investigate: VRAM, model_cache, image regression).
set -u
DIR="${FRIGATE_DIR:-$HOME/frigate}"
GUARD="${GUARD:-$HOME/bin/free-ollama-vram.sh}"

echo "== 1/3 free Ollama VRAM =="
if [ -x "$GUARD" ]; then "$GUARD"; else echo "guard $GUARD not found, continuing"; fi
sleep 4
nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader 2>/dev/null || true

echo "== 2/3 recreate frigate ($DIR) =="
if [ "${PULL:-0}" = "1" ]; then ( cd "$DIR" && docker compose pull ); fi
( cd "$DIR" && docker compose up -d --force-recreate ) || { echo "compose up failed"; exit 1; }

echo "== 3/3 verify detector init (up to ~90s) =="
for i in $(seq 1 18); do
  sleep 5
  maxp="$(curl -s --max-time 6 http://localhost:5000/api/stats 2>/dev/null \
    | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
except Exception:
    print(0); raise SystemExit
cams=d.get("cameras",{})
print(max([ (s.get("process_fps") or 0) for s in cams.values() ] or [0]))' 2>/dev/null || echo 0)"
  stuck="$(docker logs --since 12s frigate 2>&1 | grep -ciE 'stuck|force killing' || true)"
  echo "  check $i: max process_fps=${maxp} stuck_msgs=${stuck}"
  if awk "BEGIN{exit !(${maxp:-0}>=1.0)}" && [ "${stuck:-0}" = "0" ]; then
    echo "OK: detector processing frames (process_fps=${maxp}); Frigate detection restored."
    exit 0
  fi
done
echo "FAIL: detector did not stabilize. Check 'docker logs frigate' and GPU VRAM (nvidia-smi)."
exit 1
