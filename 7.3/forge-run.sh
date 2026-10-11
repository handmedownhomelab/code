#!/usr/bin/env bash
# forge-run.sh — Hand-Me-Down Homelab, section 7.3. Runs on the GPU box.
# Start Forge Neo only after freeing the card: unload EVERY loaded Ollama
# model (not just the chat model; whatever ran last stays pinned with
# KEEP_ALIVE=-1), and stop the other GPU apps. None of them gives VRAM back
# on its own. Ctrl-C stops Forge; the forge() function on the workstation
# (forge.zsh) then loads the chat model back.
#
# Install: copy to ~/forge-run.sh on the GPU box, chmod +x, edit the settings.
set -e
# ---- settings ----------------------------------------------------------
FORGE_DIR="${FORGE_DIR:-$HOME/sd-webui-forge-neo}"
CHAT_MODEL="${CHAT_MODEL:-gemma4:12b-it-q8_0}"   # stopped even if /api/ps is down
# Command-line patterns of other GPU apps to stop first (pkill -f patterns).
# Bracket one letter so the pattern can't match this script's own command.
OTHER_GPU_APPS=(
  "main.py --listen 0.0.0.0 --port 818[8]"   # ComfyUI (7.4)
  "ACE-Step/.venv/bi[n]"                     # ACE-Step (7.6)
)
# ------------------------------------------------------------------------
export PATH="$HOME/.local/bin:$PATH"           # uv lives here

echo ">> Unloading all loaded Ollama models..."
for m in "$CHAT_MODEL" $(curl -s -m5 http://127.0.0.1:11434/api/ps 2>/dev/null \
    | python3 -c 'import sys,json; [print(x["name"]) for x in json.load(sys.stdin).get("models",[])]' 2>/dev/null); do
  echo "   ollama stop $m"; ollama stop "$m" 2>/dev/null || true
done

echo ">> Stopping other GPU apps..."
for p in "${OTHER_GPU_APPS[@]}"; do pkill -f "$p" 2>/dev/null || true; done
sleep 2
nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader

echo ">> Starting Forge Neo on port 7860..."
cd "$FORGE_DIR"
exec ./webui-user.sh
