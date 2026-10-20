#!/bin/bash
# claude-memory-sync.sh - keep Claude Code's memory folder the same on every
# workstation, through a bare git repository on your hub.
# Hand-Me-Down Homelab, section 2.4. Install notes: playbooks/2.4-auto-memory.md
#
# Usage:
#   claude-memory-sync.sh pull   # SessionStart hook: fetch what other machines wrote
#   claude-memory-sync.sh push   # Stop hook: commit and push what this session wrote
#
# Unlike the wiki sync (2.2), this one DOES commit: memory files are written by
# Claude Code itself, one fact per file, and there is no log entry to wait for.
#
# Never blocks a session: every path exits 0, and SSH fails fast if the hub is
# unreachable. Pulls rebase; a failed rebase is aborted, so local memory is
# left exactly as it was.

MODE="${1:-}"
LOG="$HOME/.claude/memory-sync.log"

# --- EDIT THESE --------------------------------------------------------------
# A memory folder is synced only if it is a git clone whose origin URL
# contains this text, so other git repositories are never touched.
REMOTE_MATCH="claude-memory.git"
BRANCH="main"
# Memory folders are found under ~/.claude/projects/*/memory. If you moved
# yours with the autoMemoryDirectory setting, list it here as well.
EXTRA_STORES=()
# -----------------------------------------------------------------------------

LOCK_MAX_AGE=300 # seconds before a lock is considered stale

export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new"

log() {
	printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$MODE" "$*" >>"$LOG"
}

trim_log() {
	[ -f "$LOG" ] || return 0
	local lines
	lines=$(wc -l <"$LOG")
	if [ "$lines" -gt 500 ]; then
		tail -n 300 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
	fi
}

case "$MODE" in
pull | push) ;;
*)
	echo "usage: $(basename "$0") pull|push" >&2
	exit 0
	;;
esac

# The folder name under ~/.claude/projects encodes the path a session started
# in, so it differs between machines. Discover it; don't hard-code it.
for MEM in "$HOME"/.claude/projects/*/memory "${EXTRA_STORES[@]}"; do
	[ -d "$MEM/.git" ] || continue
	git -C "$MEM" remote get-url origin 2>/dev/null | grep -q "$REMOTE_MATCH" || continue

	LOCK="$MEM/.git/memory-sync.lock.d"
	if ! mkdir "$LOCK" 2>/dev/null; then
		# Clear a lock left behind by a killed run, otherwise skip this pass.
		if [ -d "$LOCK" ]; then
			# Try GNU `stat -c` FIRST. On Linux `stat -f` means "filesystem
			# status" and prints a block of text before failing, which would
			# land in this substitution. macOS stat rejects -c outright and
			# falls through to -f cleanly.
			lock_mtime=$(stat -c %Y "$LOCK" 2>/dev/null || stat -f %m "$LOCK" 2>/dev/null || echo 0)
			age=$(($(date +%s) - ${lock_mtime:-0}))
			if [ "$age" -gt "$LOCK_MAX_AGE" ]; then
				log "clearing stale lock (${age}s old)"
				rmdir "$LOCK" 2>/dev/null
				mkdir "$LOCK" 2>/dev/null || continue
			else
				log "another sync in progress, skipping"
				continue
			fi
		else
			continue
		fi
	fi
	# shellcheck disable=SC2064
	trap "rmdir '$LOCK' 2>/dev/null" EXIT

	if [ "$MODE" = pull ]; then
		if out=$(git -C "$MEM" pull --rebase --autostash -q origin "$BRANCH" 2>&1); then
			log "pulled ok, now at $(git -C "$MEM" rev-parse --short HEAD)"
		else
			git -C "$MEM" rebase --abort 2>/dev/null
			log "pull failed (local memory unchanged): ${out//$'\n'/ | }"
		fi
	else
		dirty=$(git -C "$MEM" status --porcelain)
		ahead=$(git -C "$MEM" rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo 0)

		# Fast path: nothing changed and nothing unpushed, so no network at all.
		# This hook runs at the end of every turn; it has to be cheap.
		if [ -z "$dirty" ] && [ "$ahead" = "0" ]; then
			rmdir "$LOCK" 2>/dev/null
			trap - EXIT
			continue
		fi

		if [ -n "$dirty" ]; then
			git -C "$MEM" add -A
			if git -C "$MEM" commit -q -m "memory: $(hostname -s) $(date '+%Y-%m-%d %H:%M')" \
				-m "$(echo "$dirty" | sed 's/^/  /')" 2>/dev/null; then
				log "committed $(echo "$dirty" | wc -l | tr -d ' ') change(s)"
			else
				log "commit FAILED: is git user.name / user.email set on this machine?"
			fi
		fi

		if ! git -C "$MEM" pull --rebase --autostash -q origin "$BRANCH" 2>/dev/null; then
			git -C "$MEM" rebase --abort 2>/dev/null
			log "pre-push rebase failed; commits left local for a manual merge"
			rmdir "$LOCK" 2>/dev/null
			trap - EXIT
			continue
		fi

		if out=$(git -C "$MEM" push -q origin "$BRANCH" 2>&1); then
			log "pushed ok"
		else
			log "push failed (commits are safe locally): ${out//$'\n'/ | }"
		fi
	fi

	rmdir "$LOCK" 2>/dev/null
	trap - EXIT
done

trim_log
exit 0
