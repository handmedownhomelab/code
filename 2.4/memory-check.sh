#!/bin/bash
# memory-check.sh - a read-only hygiene report on Claude Code's memory folder.
# Hand-Me-Down Homelab, section 2.4. Install notes: playbooks/2.4-auto-memory.md
#
#   memory-check.sh [memory-folder]
#
# Two halves:
#   1. Mechanical checks, in plain shell: each file's `name:` matches its
#      filename, every memory is in MEMORY.md, every MEMORY.md link points at a
#      file, [[links]] resolve, and the index is under Claude Code's load limit
#      (the first 200 lines or 25 KB of MEMORY.md; the rest is never read).
#   2. A judgment pass by `claude -p` with READ-ONLY tools: contradictions,
#      stale claims, merge candidates. It can't edit the store, because it
#      isn't given a tool that writes. Skipped with --no-ai.
#
# It writes a report and changes nothing. Applying a finding is your decision,
# in a normal session. Run it weekly, not nightly: the store grows by a lesson
# or two a week, so "clean" is the usual answer.
#
# Exit: 0 report written (read it for findings) · 2 no memory folder ·
#       3 the claude run failed (the mechanical half is still in the report)

set -u

NO_AI=0
if [ "${1:-}" = "--no-ai" ]; then NO_AI=1; shift; fi

# --- EDIT THESE --------------------------------------------------------------
# Your memory folder. Find it with: ls -d ~/.claude/projects/*/memory ~/.agents/memory
MEM_DIR="${1:-${MEM_DIR:-}}"
OUT_DIR="$HOME/memory-reports"
KEEP=8 # reports to keep
# -----------------------------------------------------------------------------

if [ -z "$MEM_DIR" ]; then
	# Exactly one memory folder? Use it. Otherwise make the reader choose.
	found=$(ls -d "$HOME"/.claude/projects/*/memory "$HOME"/.agents/memory 2>/dev/null)
	if [ "$(printf '%s\n' "$found" | grep -c .)" = 1 ]; then
		MEM_DIR="$found"
	else
		echo "memory-check: pass the memory folder; candidates:" >&2
		printf '  %s\n' $found >&2
		exit 2
	fi
fi
[ -f "$MEM_DIR/MEMORY.md" ] || {
	echo "memory-check: no MEMORY.md in $MEM_DIR" >&2
	exit 2
}

mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/memory-report-$(date +%F).md"
INDEX="$MEM_DIR/MEMORY.md"
problems=0
# Every memory's name, one per line, to resolve [[links]] against.
NAMES=$(sed -n 's/^name:[[:space:]]*//p' "$MEM_DIR"/*.md | tr -d '"'"'"'"')

note() {
	echo "- $*" >>"$REPORT"
	problems=$((problems + 1))
}

{
	echo "# Memory report, $(date +%F)"
	echo
	echo "Folder: \`$MEM_DIR\`"
	echo
	echo "## Mechanical checks"
	echo
} >"$REPORT"

for f in "$MEM_DIR"/*.md; do
	base=$(basename "$f" .md)
	[ "$base" = MEMORY ] && continue
	name=$(sed -n 's/^name:[[:space:]]*//p' "$f" | head -1 | tr -d '"'"'")
	[ -z "$name" ] && note "\`$base.md\` has no \`name:\` in its header"
	[ -n "$name" ] && [ "$name" != "$base" ] && note "\`$base.md\`: name is \`$name\`, filename is \`$base\`"
	grep -qF "($base.md)" "$INDEX" || note "\`$base.md\` is not listed in MEMORY.md"
	# [[links]] must name an existing memory (by name or filename).
	for link in $(grep -o '\[\[[^]|]*' "$f" | sed 's/^\[\[//' | sort -u); do
		[ -f "$MEM_DIR/$link.md" ] || printf '%s\n' "$NAMES" | grep -qxF -- "$link" ||
			note "\`$base.md\` links to [[$link]], which doesn't exist"
	done
done

for target in $(grep -o '](\([^)]*\.md\))' "$INDEX" | sed 's/^](//; s/)$//' | sort -u); do
	[ -f "$MEM_DIR/$target" ] || note "MEMORY.md points at \`$target\`, which doesn't exist"
done

lines=$(wc -l <"$INDEX" | tr -d ' ')
bytes=$(wc -c <"$INDEX" | tr -d ' ')
[ "$lines" -gt 200 ] && note "MEMORY.md is $lines lines; only the first 200 are loaded"
[ "$bytes" -gt 25000 ] && note "MEMORY.md is $bytes bytes; only the first 25 KB are loaded"

memories=$(ls "$MEM_DIR"/*.md | grep -cv '/MEMORY\.md$')
{
	[ "$problems" = 0 ] && echo "Clean."
	echo
	echo "$memories memories; MEMORY.md is $lines lines, $bytes bytes."
	echo
} >>"$REPORT"

rc=0
if [ "$NO_AI" = 0 ]; then
	PROMPT="Read-only hygiene check of the Claude Code memory folder $MEM_DIR.
You have no tools that write; do not try to edit anything.
Read MEMORY.md and every memory file, then report only:
1. CONTRADICTIONS: two memories saying different things about the same fact,
   or a MEMORY.md line that disagrees with its own file.
2. STALENESS: dated claims, open items or 'as of' figures that have probably
   moved on. Flag them; do not guess new values.
3. OVERLAP: memories one of which should absorb the other. Name the survivor
   and what a merge would lose. Memories that share a principle but fire at
   different moments should stay separate.
4. VAGUE INDEX LINES: MEMORY.md lines too vague to tell when they apply. Each
   should lead with the moment it matters ('Before ...').
Markdown. Start with one line: 'clean' or the number of findings. Quote the
evidence for each finding and give the exact change you'd make. If nothing
needs attention, say so in two lines; don't invent work. End with a section
'## To apply' listing what's worth doing, phrased as instructions to paste
into a session."
	echo "## Judgment pass" >>"$REPORT"
	echo >>"$REPORT"
	# No settings, hooks or saved session: a scheduled check shouldn't pull,
	# push or load anything while it reads the store.
	claude -p "$PROMPT" \
		--setting-sources "" --no-session-persistence \
		--allowedTools "Read,Grep,Glob" \
		--disallowedTools "Edit,Write,NotebookEdit,Bash,WebFetch,WebSearch" \
		--add-dir "$MEM_DIR" >>"$REPORT" 2>>"$OUT_DIR/memory-check.err"
	rc=$?
	if [ "$rc" != 0 ]; then
		echo "**The claude run failed (exit $rc); see memory-check.err.**" >>"$REPORT"
		rc=3
	fi
fi

ln -sf "$REPORT" "$OUT_DIR/latest.md"
ls -1t "$OUT_DIR"/memory-report-*.md 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
	rm -f "$old"
done

echo "report: $REPORT ($problems mechanical finding(s))"
exit "$rc"
