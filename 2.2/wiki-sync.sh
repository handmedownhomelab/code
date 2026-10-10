#!/bin/bash
# wiki-sync.sh: keep every git clone under ~/wiki in step with the hub.
# Hand-Me-Down Homelab, section 2.2.
#
# Run by Claude Code hooks (~/.claude/settings.json; see settings-hooks.json):
#   wiki-sync.sh            SessionStart: fast-forward every clean clone
#   wiki-sync.sh push       Stop: push committed work, warn about uncommitted
#
# Install on every workstation as ~/.claude/hooks/wiki-sync.sh and set
# WIKI_HUB below to the user@host that holds the bare repositories.
# Log: ~/.claude/wiki-sync.log (the hooks themselves stay quiet).
#
# Design, because it matters more than the code:
#  - It never blocks a session: every path exits 0.
#  - ONE reachability probe gates all network work, so a laptop away from
#    home costs about 3 seconds, not a timeout per wiki.
#  - Pull is fast-forward only. A clone with uncommitted work is skipped,
#    not fought.
#  - Push never commits. An automatic commit would bypass the rule that every
#    change carries a log.md entry, so uncommitted work is reported instead.
#  - Optional: if a `wiki-lock` command exists in ~/bin (one writer per clone
#    when several AI sessions share a machine), the Stop hook releases this
#    session's locks and both halves leave a locked clone alone.

MODE="${1:-pull}"
WIKI_BASE="$HOME/wiki"
LOG="$HOME/.claude/wiki-sync.log"
WIKI_HUB="you@hub.home.arpa"      # YOUR hub: user@host with ~/git/<repo>.git
LOG_MAX_LINES=400

export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=accept-new"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG" 2>/dev/null; }

trim_log() {
	[ -f "$LOG" ] || return 0
	local n
	n=$(wc -l <"$LOG" 2>/dev/null) || return 0
	if [ "$n" -gt "$LOG_MAX_LINES" ]; then
		tail -n "$LOG_MAX_LINES" "$LOG" >"$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
	fi
}

[ -d "$WIKI_BASE" ] || exit 0

# Optional wiki-lock (~/bin/wiki-lock): one writer per clone. The Stop hook frees this
# session's locks at the end of every turn, BEFORE the reachability gate so a
# laptop off the LAN still releases. `release --mine` finds the owner by the
# `claude` process above this hook, the same one the session's Bash calls see.
WIKI_LOCK="$HOME/bin/wiki-lock"
[ -x "$WIKI_LOCK" ] || WIKI_LOCK=""
lock_holder() {  # prints "held by …" for a clone locked by anyone, else nothing
	[ -n "$WIKI_LOCK" ] || return 0
	local st
	st=$("$WIKI_LOCK" status "$1" 2>/dev/null) || return 0
	case "$st" in *"held by"*) printf '%s' "${st#* held by }" ;; esac
}
if [ "$MODE" = "push" ] && [ -n "$WIKI_LOCK" ]; then
	"$WIKI_LOCK" release --mine --quiet 2>/dev/null
fi

# ONE reachability probe gates everything. Six repos x a 4 s connect timeout
# would be a 24 s stall at session start on a laptop that is off the LAN;
# this caps the offline case at ~3 s total.
if ! ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new \
	"$WIKI_HUB" true 2>/dev/null; then
	log "SKIP: $WIKI_HUB unreachable — clones left as-is"
	trim_log
	exit 0
fi

if [ "$MODE" = "push" ]; then
	pushed=0 dirty=0 failed=0
	for d in "$WIKI_BASE"/*/; do
		[ -d "$d/.git" ] || continue
		name=$(basename "$d")

		if [ -n "$(git -C "$d" status --porcelain 2>/dev/null)" ]; then
			dirty=$((dirty + 1))
			holder=$(lock_holder "$d")
			if [ -n "$holder" ]; then
				# Our locks were released above, so a holder now is ANOTHER session.
				echo "WIKI: $name has uncommitted changes, but another session holds its lock ($holder) — its work in progress, not yours." >&2
				log "dirty $name (locked by $holder)"
			else
				echo "WIKI: $name has UNCOMMITTED changes — commit them (with a log.md entry) and push, or they stay on this host only." >&2
				log "dirty $name (left alone — not auto-committed by design)"
			fi
		fi

		ahead=$(git -C "$d" rev-list --count '@{u}..HEAD' 2>/dev/null) || continue
		if [ "${ahead:-0}" -gt 0 ]; then
			if git -C "$d" push -q origin HEAD 2>/dev/null; then
				pushed=$((pushed + 1))
				log "push $name ($ahead commit(s))"
			else
				failed=$((failed + 1))
				echo "WIKI: $name has $ahead unpushed commit(s) and the push FAILED — push by hand." >&2
				log "FAIL push $name ($ahead ahead)"
			fi
		fi
	done
	[ "$pushed" -gt 0 ] || [ "$dirty" -gt 0 ] || [ "$failed" -gt 0 ] \
		&& log "done(push): $pushed pushed, $dirty dirty, $failed failed"
	trim_log
	exit 0
fi

pulled=0 skipped=0 failed=0
for d in "$WIKI_BASE"/*/; do
	[ -d "$d/.git" ] || continue
	name=$(basename "$d")

	# Another session is mid-edit: pulling under it could change files it has
	# already read. Leave the clone for that session to pull and push.
	holder=$(lock_holder "$d")
	if [ -n "$holder" ]; then
		skipped=$((skipped + 1))
		log "skip $name (locked by $holder)"
		continue
	fi

	# A dirty tree means uncommitted work, maybe a program mid-write.
	# Never pull over it; --ff-only would refuse anyway, but skipping
	# keeps the log honest about why.
	if [ -n "$(git -C "$d" status --porcelain 2>/dev/null)" ]; then
		skipped=$((skipped + 1))
		log "skip $name (dirty)"
		continue
	fi

	before=$(git -C "$d" rev-parse --short HEAD 2>/dev/null)
	if git -C "$d" pull -q --ff-only 2>/dev/null; then
		after=$(git -C "$d" rev-parse --short HEAD 2>/dev/null)
		if [ "$before" != "$after" ]; then
			pulled=$((pulled + 1))
			log "pull $name $before -> $after"
		fi
	else
		failed=$((failed + 1))
		log "FAIL $name (diverged or no upstream) — pull by hand"
	fi
done

[ "$pulled" -gt 0 ] || [ "$skipped" -gt 0 ] || [ "$failed" -gt 0 ] \
	&& log "done: $pulled pulled, $skipped skipped, $failed failed"
trim_log
exit 0
