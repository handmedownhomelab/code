#!/usr/bin/env bash
# comfyui-run.sh — Hand-Me-Down Homelab, section 7.4. Runs on the GPU box.
# Start ComfyUI only after freeing the card: unload EVERY loaded Ollama model
# and stop the other GPU apps (Forge never gives its memory back on its own; a
# stale one once held 10.5 GB and starved a video render). Ctrl-C stops
# ComfyUI; the comfy() function on the workstation (comfy.zsh) then loads the
# chat model back.
#
# Install: copy to ~/comfyui-run.sh on the GPU box, chmod +x, edit the settings.
set -e
# ---- settings ----------------------------------------------------------
COMFY_DIR="${COMFY_DIR:-$HOME/ComfyUI}"
CHAT_MODEL="${CHAT_MODEL:-gemma4:12b-it-q8_0}"   # stopped even if /api/ps is down
# Command-line patterns of other GPU apps to stop first (pkill -f patterns).
# Bracket one letter so a pattern can't match this script's own command.
OTHER_GPU_APPS=(
  "sd-webui-forge-neo/venv/bin/[p]ython"   # Forge (7.3)
  "ACE-Step/.venv/bi[n]"                   # ACE-Step (7.6)
)
# ------------------------------------------------------------------------
echo ">> Unloading all loaded Ollama models..."
for m in "$CHAT_MODEL" $(curl -s -m5 http://127.0.0.1:11434/api/ps 2>/dev/null \
    | python3 -c 'import sys,json; [print(x["name"]) for x in json.load(sys.stdin).get("models",[])]' 2>/dev/null); do
  echo "   ollama stop $m"; ollama stop "$m" 2>/dev/null || true
done

echo ">> Stopping other GPU apps..."
for p in "${OTHER_GPU_APPS[@]}"; do pkill -f "$p" 2>/dev/null || true; done
sleep 2
nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader

echo ">> Starting ComfyUI on port 8188..."
cd "$COMFY_DIR"
# ABSOLUTE paths on purpose: started as ./venv/bin/python main.py, the
# process's command line is relative, and a pkill written against the full
# path matches nothing. The stop "succeeds" and ComfyUI keeps running.
# --disable-smart-memory: give the VRAM back after every job, so the chat
# model isn't pushed onto the CPU between jobs. Costs a few seconds a job.
exec "$COMFY_DIR/venv/bin/python" "$COMFY_DIR/main.py" \
  --listen 0.0.0.0 --port 8188 --disable-smart-memory "$@"
