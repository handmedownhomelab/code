#!/usr/bin/env bash
# acestep-run.sh — Hand-Me-Down Homelab, section 7.6. Runs on the GPU box.
# Start ACE-Step's web interface only after freeing the card: unload EVERY
# loaded Ollama model and stop the other GPU apps (none of them gives its
# memory back on its own). Ctrl-C stops it; the music() function on the
# workstation (music.zsh) then loads the chat model back.
#
# Always runs with --cpu_offload and --overlapped_decode. Measured on a 16 GB
# card: offload peaked at 7.9 GB and took 44 s; without it, 15.2 GB, 54 s and
# a near out-of-memory error. Offload is faster AND safer; keep the flags.
#
# Binds 127.0.0.1: reached through the SSH tunnel only, never the LAN.
#
# Install: copy to ~/acestep-run.sh on the GPU box, chmod +x, edit the settings.
set -e
# ---- settings ----------------------------------------------------------
ACESTEP_DIR="${ACESTEP_DIR:-$HOME/ACE-Step}"
CHAT_MODEL="${CHAT_MODEL:-gemma4:12b-it-q8_0}"   # stopped even if /api/ps is down
PORT=7861
# Command-line patterns of other GPU apps to stop first (pkill -f patterns).
# Bracket one letter so a pattern can't match the command carrying it.
OTHER_GPU_APPS=(
  "sd-webui-forge-neo/venv/bin/[p]ython"   # Forge (7.3)
  "[m]ain.py --listen 0.0.0.0 --port 8188" # ComfyUI (7.4)
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

echo ">> Starting ACE-Step on http://127.0.0.1:$PORT ..."
cd "$ACESTEP_DIR"
# ABSOLUTE path on purpose: started as ./.venv/bin/acestep, the command line
# is relative, and a pkill on "ACE-Step/.venv/bin" (music.zsh, the other
# launchers) matches nothing. The stop "succeeds"; the GPU stays taken.
exec "$ACESTEP_DIR/.venv/bin/acestep" --server_name 127.0.0.1 --port "$PORT" \
  --bf16 true --cpu_offload true --overlapped_decode true "$@"
