#!/usr/bin/env bash
# ssh-menu.sh - a launcher: your hosts, plus the commands you run often
# enough to deserve a keystroke. Hand-Me-Down Homelab, section 2.5.
# Called by the `m` shell function in m.zsh (install notes there).
#
#   m              draw the menu
#   m gpu-tower    connect straight to a host (name or number)
#   m a            run a command entry without the menu
#
# CONTRACT WITH THE CALLER: everything a human reads goes to stderr, and
# exactly one shell command goes to stdout. The `m` function evals that line
# IN YOUR CURRENT SHELL. That indirection is the point: an entry can be a
# shell function from your ~/.zshrc, which a child bash process can't see,
# and a function's Ctrl-C trap only fires in the shell that owns the
# connection. Print anything else to stdout and `m` will try to run it.
#
# Parallel arrays, not associative: readable under bash and zsh, and they
# keep menu order.

# --- Hosts: EDIT THESE -------------------------------------------------------
NAMES=(proxmox pmx2 pihole pihole2 ha gpu-tower ids ca)
TARGETS=(
  "you@proxmox.home.arpa"
  "you@pmx2.home.arpa"
  "you@pihole.home.arpa"
  "you@pihole2.home.arpa"
  "root@ha.home.arpa"
  "you@gpu-tower.home.arpa"
  "you@ids.home.arpa"
  "root@ca.home.arpa"
)

# --- Commands: EDIT THESE ----------------------------------------------------
# Key, label, and the command line handed back to your shell. Keys are single
# letters so they can never collide with a host number. Case matters.
# An entry can be a shell function (for example one that opens an SSH tunnel
# to a web app on the GPU tower and closes it on Ctrl-C).
CKEYS=(a r d t)
CLABELS=(
  "audit.sh (all hosts)"
  "audit.sh: reboot needed?"
  "audit.sh: disk space"
  "tunnel to GPU tower :8080"
)
CCMDS=(
  '~/bin/audit.sh'
  '~/bin/audit.sh "test -f /var/run/reboot-required && echo REBOOT NEEDED || echo ok"'
  '~/bin/audit.sh "df -h /"'
  'ssh -N -L 8080:localhost:8080 you@gpu-tower.home.arpa'
)

BOLD="\033[1m"; CYAN="\033[36m"; GREEN="\033[32m"; DIM="\033[2m"; RESET="\033[0m"
RULE="────────────────────────────────────────────────────────────────────────"

# host_entry <index> -> "  N name target", padded to <width>
host_entry() {
  local i=$1 w=$2
  printf "  ${CYAN}%2d${RESET} %-10s ${DIM}%-*s${RESET}" \
    "$((i + 1))" "${NAMES[$i]}" "$w" "${TARGETS[$i]}"
}

draw_menu() {
  local half=$(( (${#NAMES[@]} + 1) / 2 )) i right
  clear >&2
  echo -e "${BOLD}Homelab Menu${RESET}   ${DIM}numbers = hosts, letters = commands${RESET}" >&2
  echo -e "${DIM}${RULE}${RESET}" >&2

  for (( i = 0; i < half; i++ )); do
    right=$(( i + half ))
    if (( right < ${#NAMES[@]} )); then
      echo -e "$(host_entry "$i" 22)$(host_entry "$right" 0)" >&2
    else
      echo -e "$(host_entry "$i" 0)" >&2
    fi
  done

  echo -e "${DIM}${RULE}${RESET}" >&2
  # Commands in three columns, filled down each column.
  local n=${#CKEYS[@]} rows=$(( (${#CKEYS[@]} + 2) / 3 )) r c idx line
  for (( r = 0; r < rows; r++ )); do
    line=""
    for (( c = 0; c < 3; c++ )); do
      idx=$(( r + c * rows ))
      (( idx < n )) || continue
      line+=$(printf "  ${CYAN}%s${RESET} %-21s" "${CKEYS[$idx]}" "${CLABELS[$idx]}")
    done
    echo -e "$line" >&2
  done

  echo -e "${DIM}${RULE}${RESET}" >&2
  echo -e "  ${CYAN}q${RESET} Quit" >&2
  echo "" >&2
}

# resolve <choice> -- emits the command on stdout, or returns 1
resolve() {
  local choice="$1" i idx

  case "$choice" in
    q|Q) return 2 ;;
  esac

  # A host number
  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    idx=$((choice - 1))
    if (( idx >= 0 && idx < ${#NAMES[@]} )); then
      echo -e "\n${GREEN}Connecting to ${BOLD}${NAMES[$idx]}${RESET}${GREEN} (${TARGETS[$idx]})${RESET}" >&2
      printf 'ssh %s\n' "${TARGETS[$idx]}"
      return 0
    fi
    return 1
  fi

  # A host name, typed in full
  for i in "${!NAMES[@]}"; do
    if [[ "${NAMES[$i]}" == "$choice" ]]; then
      echo -e "\n${GREEN}Connecting to ${BOLD}${NAMES[$i]}${RESET}${GREEN} (${TARGETS[$i]})${RESET}" >&2
      printf 'ssh %s\n' "${TARGETS[$i]}"
      return 0
    fi
  done

  # A command key -- case matters here, p and P differ
  for i in "${!CKEYS[@]}"; do
    if [[ "${CKEYS[$i]}" == "$choice" ]]; then
      printf '%s\n' "${CCMDS[$i]}"
      return 0
    fi
  done

  return 1
}

case "${1:-}" in
  -h|--help)
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 0
    ;;
esac

# Direct dispatch: m gpu-tower / m 3 / m a
if [[ $# -gt 0 ]]; then
  resolve "$1"; rc=$?
  (( rc == 0 )) && exit 0          # command already on stdout
  (( rc == 2 )) && exit 0          # q
  echo "m: no host or command matching '$1' (run m for the menu)" >&2
  exit 1
fi

draw_menu
printf 'Choose: ' >&2
read -r choice < /dev/tty || exit 0

resolve "$choice"; rc=$?
(( rc == 0 )) && exit 0
(( rc == 2 )) && { echo "Bye." >&2; exit 0; }
echo "Invalid choice." >&2
exit 1
