#!/bin/bash
# check-wiki-log.sh: warn when a wiki changed without a log.md entry.
# Hand-Me-Down Homelab, section 2.2. Claude Code Stop hook; install as
# ~/.claude/hooks/check-wiki-log.sh on every workstation.
#
# Checks each git clone under ~/wiki: uncommitted wiki/ changes with no
# log.md change, and a last commit that touched wiki/ but not log.md.
#
# If it can't find anything to check, it SAYS SO. The author's first version
# pointed at a folder retired months earlier and passed silently for three
# months while enforcing nothing (the book's war story).

WIKI_BASE="$HOME/wiki"
warn=0

[ -d "$WIKI_BASE" ] || {
	echo "WIKI-LOG-CHECK: $WIKI_BASE does not exist — this hook is not checking anything." >&2
	exit 0
}

found=0
for d in "$WIKI_BASE"/*/; do
	[ -d "$d/.git" ] || continue
	found=$((found + 1))
	name=$(basename "$d")
	[ -f "$d/log.md" ] || continue

	# Uncommitted: wiki/ pages touched but log.md untouched.
	status=$(git -C "$d" status --porcelain 2>/dev/null)
	if printf '%s\n' "$status" | grep -qE '^.{1,2} *"?wiki/'; then
		if ! printf '%s\n' "$status" | grep -qE '^.{1,2} *"?log\.md'; then
			echo "WIKI-LOG-CHECK: $name has modified wiki/ pages but no log.md change. Add a log.md entry before committing." >&2
			warn=1
		fi
	fi

	# Last commit: touched wiki/ but not log.md.
	last=$(git -C "$d" diff --name-only HEAD~1 HEAD 2>/dev/null)
	if printf '%s\n' "$last" | grep -q '^wiki/'; then
		if ! printf '%s\n' "$last" | grep -qx 'log\.md'; then
			echo "WIKI-LOG-CHECK: $name's last commit touched wiki/ pages but not log.md. Add an entry in a follow-up commit." >&2
			warn=1
		fi
	fi
done

[ "$found" -gt 0 ] || echo "WIKI-LOG-CHECK: no git clones under $WIKI_BASE — not checking anything." >&2
exit 0
