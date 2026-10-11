# music.zsh — Hand-Me-Down Homelab, section 7.6. Runs on your workstation.
# `music` opens an SSH tunnel to the GPU box, runs acestep-run.sh there, and
# opens ACE-Step in the browser when it answers (about 15 s). Ctrl-C (or
# closing the terminal) stops it on the GPU box and loads the chat model back.
# Same pattern as forge.zsh (7.3).
#
# The pkill pattern is bracketed ([.]venv) on purpose: over ssh the remote
# command runs as `bash -c '<the whole string>'`, so an unbracketed pattern
# matches that shell too. pkill kills its own shell, ssh exits 255, and the
# reload after it never runs, while the target dies and nothing looks wrong.
#
# Install: source it from ~/.zshrc and edit the settings.
GPU_HOST="${GPU_HOST:-you@gpu-box.home.arpa}"
CHAT_MODEL="${CHAT_MODEL:-gemma4:12b-it-q8_0}"

_music_stop() {
  [[ ${_MUSIC_STOPPED:-0} == 1 ]] && return     # INT and EXIT both fire
  _MUSIC_STOPPED=1
  echo "Stopping ACE-Step; loading $CHAT_MODEL back in the background..."
  ssh -o LogLevel=ERROR "$GPU_HOST" \
    "pkill -f 'ACE-Step/[.]venv/bin' 2>/dev/null; nohup setsid ollama run $CHAT_MODEL hi >/dev/null 2>&1 </dev/null &" 2>/dev/null
}

music() {
  echo "Starting ACE-Step on $GPU_HOST (the chat model pauses while it runs)..."
  # LogLevel=ERROR hides the harmless "channel N: open failed" lines this
  # poll causes while the interface is still starting; real errors still print.
  ( for i in {1..90}; do sleep 2; curl -sf -o /dev/null http://localhost:7861/ \
      && { open "http://localhost:7861" 2>/dev/null || xdg-open "http://localhost:7861"; break; }; done ) >/dev/null 2>&1 &
  _MUSIC_STOPPED=0
  trap _music_stop EXIT INT TERM
  ssh -o LogLevel=ERROR -tt -L 7861:localhost:7861 "$GPU_HOST" './acestep-run.sh'
  trap - EXIT INT TERM
  _music_stop
  unset _MUSIC_STOPPED
}
