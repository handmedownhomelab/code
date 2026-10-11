# comfy.zsh — Hand-Me-Down Homelab, section 7.4. Runs on your workstation.
# `comfy` opens an SSH tunnel to the GPU box, runs comfyui-run.sh there, and
# opens ComfyUI in the browser when it answers. Port 8188 is never opened in
# the firewall. Ctrl-C (or closing the terminal) stops ComfyUI on the GPU box
# and loads the chat model back. Same pattern as forge.zsh (7.3): -tt so the
# remote side gets a hangup, plus a trap in case it doesn't.
#
# Install: source it from ~/.zshrc and edit the settings.
GPU_HOST="${GPU_HOST:-you@gpu-box.home.arpa}"
CHAT_MODEL="${CHAT_MODEL:-gemma4:12b-it-q8_0}"

_comfy_stop() {
  [[ ${_COMFY_STOPPED:-0} == 1 ]] && return     # INT and EXIT both fire
  _COMFY_STOPPED=1
  echo "Stopping ComfyUI; loading $CHAT_MODEL back in the background..."
  ssh -o LogLevel=ERROR "$GPU_HOST" \
    "pkill -f '[m]ain.py --listen 0.0.0.0 --port 8188' 2>/dev/null; nohup setsid ollama run $CHAT_MODEL hi >/dev/null 2>&1 </dev/null &" 2>/dev/null
}

comfy() {
  echo "Starting ComfyUI on $GPU_HOST (the chat model pauses while it runs)..."
  ( for i in {1..90}; do sleep 2; curl -sf -o /dev/null http://localhost:8188/ \
      && { open "http://localhost:8188" 2>/dev/null || xdg-open "http://localhost:8188"; break; }; done ) >/dev/null 2>&1 &
  _COMFY_STOPPED=0
  trap _comfy_stop EXIT INT TERM
  ssh -o LogLevel=ERROR -tt -L 8188:localhost:8188 "$GPU_HOST" './comfyui-run.sh'
  trap - EXIT INT TERM
  _comfy_stop
  unset _COMFY_STOPPED
}
