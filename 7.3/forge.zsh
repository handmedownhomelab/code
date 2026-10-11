# forge.zsh — Hand-Me-Down Homelab, section 7.3. Runs on your workstation.
# `forge` opens an SSH tunnel to the GPU box, runs forge-run.sh there, and
# opens Forge in the browser when it answers. Port 7860 is never opened in
# the firewall. Ctrl-C (or closing the terminal) stops Forge on the GPU box
# and loads the chat model back, so its other callers don't pay a cold load.
#
# Install: source it from ~/.zshrc and edit the settings.
#   -tt, not -t: forces a remote terminal even when this shell has none, so
#   the remote side gets a hangup when you quit.
#   The trap is a second, direct cleanup in case that hangup never arrives:
#   without it a non-interactive launch once left Forge holding the card.
GPU_HOST="${GPU_HOST:-you@gpu-box.home.arpa}"
CHAT_MODEL="${CHAT_MODEL:-gemma4:12b-it-q8_0}"

_forge_stop() {
  [[ ${_FORGE_STOPPED:-0} == 1 ]] && return     # INT and EXIT both fire
  _FORGE_STOPPED=1
  echo "Stopping Forge; loading $CHAT_MODEL back in the background..."
  ssh -o LogLevel=ERROR "$GPU_HOST" \
    "pkill -f 'sd-webui-forge-neo/venv/bin/[p]ython' 2>/dev/null; nohup setsid ollama run $CHAT_MODEL hi >/dev/null 2>&1 </dev/null &" 2>/dev/null
}

forge() {
  echo "Starting Forge on $GPU_HOST (the chat model pauses while it runs)..."
  ( for i in {1..90}; do sleep 2; curl -sf -o /dev/null http://localhost:7860/ \
      && { open "http://localhost:7860" 2>/dev/null || xdg-open "http://localhost:7860"; break; }; done ) >/dev/null 2>&1 &
  _FORGE_STOPPED=0
  trap _forge_stop EXIT INT TERM
  ssh -o LogLevel=ERROR -tt -L 7860:localhost:7860 "$GPU_HOST" './forge-run.sh'
  trap - EXIT INT TERM
  _forge_stop
  unset _FORGE_STOPPED
}
