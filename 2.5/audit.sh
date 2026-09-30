#!/bin/bash
# =============================================================================
# audit.sh - run the same commands on every host, get one plain-text report
# Hand-Me-Down Homelab, section 2.5.
#
# Usage: audit.sh "command1" "command2" ...
#   or:  audit.sh -f commands.txt
#   or:  audit.sh                       (reachability check: uptime + uname -a)
#
# Each command runs on this machine and on every host below. The report goes
# to stdout, to read, save or paste back to an AI. Built during a software
# supply-chain scare as a deliberate, run-by-hand alternative to giving an AI
# a shell on every host.
# =============================================================================

# --- Hosts: EDIT THESE -------------------------------------------------------
# Parallel arrays rather than an associative array: they keep report order and
# work the same way as ssh-menu.sh.
#
# Each target carries its own user, because it often isn't the same everywhere
# (Home Assistant's SSH add-on, for one, logs in as root, into a minimal shell
# where not every Linux command exists).
LABELS=(proxmox pmx2 pihole pihole2 ha gpu-tower ids ca)
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

# BatchMode=yes: a host that wants a password fails at once instead of hanging
# the run. It also means a host with no key installed for this machine can
# never succeed, however healthy it is, so the probe below reports NO KEY
# separately from UNREACHABLE. Keep that branch: it's what makes the next key
# revocation legible (section 2.5's war story).
SSH_OPTS=(-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o BatchMode=yes)
LOCAL_HOST="$(hostname -s)"

# --- Collect commands --------------------------------------------------------
COMMANDS=()

case "${1:-}" in
  -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

if [[ "$1" == "-f" && -f "$2" ]]; then
    # Read commands from file, skip blank lines and comments
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        COMMANDS+=("$line")
    done < "$2"
elif [[ "$1" == "-f" ]]; then
    echo "audit.sh: -f needs a readable file (got '${2:-nothing}')" >&2
    exit 2
elif [[ $# -gt 0 ]]; then
    for arg in "$@"; do
        COMMANDS+=("$arg")
    done
else
    # Default: basic reachability + uptime
    COMMANDS=("uptime" "uname -a")
fi

# --- Header ------------------------------------------------------------------
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')
echo "============================================================"
echo " HOMELAB AUDIT REPORT"
echo " Generated: $TIMESTAMP"
echo " Hosts:     ${#LABELS[@]} remote + $LOCAL_HOST (local)"
echo " Commands:"
for cmd in "${COMMANDS[@]}"; do
    echo "   - $cmd"
done
echo "============================================================"
echo ""

# --- Run locally -------------------------------------------------------------
run_local() {
    echo "------------------------------------------------------------"
    echo " HOST: $LOCAL_HOST (local)"
    echo "------------------------------------------------------------"
    for cmd in "${COMMANDS[@]}"; do
        echo ""
        echo "  \$ $cmd"
        # PIPESTATUS, not $? -- $? here would be sed's status, so every
        # failing command would report [exit: 0].
        eval "$cmd" 2>&1 | sed 's/^/  /'
        echo "  [exit: ${PIPESTATUS[0]}]"
    done
    echo ""
}

# --- Run on remote host via SSH ----------------------------------------------
run_remote() {
    local label="$1" target="$2" probe

    echo "------------------------------------------------------------"
    echo " HOST: $label ($target)"
    echo "------------------------------------------------------------"

    # Probe first, and keep stderr so we can tell "no key" from "host down".
    if ! probe=$(ssh "${SSH_OPTS[@]}" "$target" "exit" 2>&1); then
        if [[ "$probe" == *"Permission denied"* ]]; then
            echo "  [NO KEY - skipping; host answered but rejected key auth]"
        else
            echo "  [UNREACHABLE - skipping]"
            [[ -n "$probe" ]] && echo "  ${probe%%$'\n'*}"
        fi
        echo ""
        return
    fi

    for cmd in "${COMMANDS[@]}"; do
        echo ""
        echo "  \$ $cmd"
        ssh "${SSH_OPTS[@]}" "$target" "$cmd" 2>&1 | sed 's/^/  /'
        echo "  [exit: ${PIPESTATUS[0]}]"
    done
    echo ""
}

# --- Execute -----------------------------------------------------------------
run_local

for i in "${!LABELS[@]}"; do
    run_remote "${LABELS[$i]}" "${TARGETS[$i]}"
done

echo "============================================================"
echo " END OF REPORT"
echo "============================================================"
