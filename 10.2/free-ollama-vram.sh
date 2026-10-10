#!/usr/bin/env bash
# free-ollama-vram.sh — Hand-Me-Down Homelab, sections 7.7 and 10.2.
# Unload any GPU-resident Ollama models so a (re)starting Frigate detector can
# initialize. On a 16 GB card, a large model kept loaded (keep_alive
# "forever", ~14 GB) leaves too little VRAM for Frigate's detector to
# cold-start, and it crash-loops. The two fit once both are running; it's the
# cold start that fails.
#
# Safe to run anytime: no-op if nothing is loaded; the model reloads on demand
# on the next Ollama query. Bounded and tolerant so it can be used as a systemd
# ExecStartPre without ever blocking Docker startup.
set -u
OLLAMA="${OLLAMA:-ollama}"

command -v "$OLLAMA" >/dev/null 2>&1 || { echo "free-ollama-vram: ollama not found"; exit 0; }

# Column 1 of `ollama ps` (minus the header) is the model NAME.
models="$(timeout 10 "$OLLAMA" ps 2>/dev/null | awk 'NR>1 && NF {print $1}')"
if [ -z "${models}" ]; then
  echo "free-ollama-vram: no models loaded"
  exit 0
fi

for m in ${models}; do
  echo "free-ollama-vram: stopping ${m}"
  timeout 20 "$OLLAMA" stop "${m}" 2>/dev/null || echo "free-ollama-vram: could not stop ${m} (continuing)"
done
exit 0
