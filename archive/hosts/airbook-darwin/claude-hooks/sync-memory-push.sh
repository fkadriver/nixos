#!/usr/bin/env bash
# Auto-commit and push memory changes after Claude writes a memory file.
# Called as a PostToolUse hook; receives tool input JSON on stdin.

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
sync-memory-push.sh - auto-commit and push Claude memory changes.

Installed to ~/.claude/ by home-manager and registered as a PostToolUse hook
(matcher Write|Edit) in ~/.claude/settings.json. Takes no arguments; reads the
tool-call JSON on stdin and exits 0 unless the written file resolves into
~/.claude/shared-memory.

Failures are appended to ~/.claude/sync-memory.log.
EOF
    exit 0
fi

input=$(cat)
file=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.path // ""')
[[ -n "$file" ]] || exit 0

LOG=/Users/scott/.claude/sync-memory.log
REPO=/Users/scott/.claude/shared-memory

# Resolve symlinks BEFORE matching. Sessions write memory through
# ~/.claude/projects/<project>/memory/..., which is a symlink to shared-memory: same
# inode, different path string. Matching the unresolved string silently skipped every
# such write, which is how 12 memories sat uncommitted from 2026-04 to 2026-10.
# Fall back to resolving the parent dir in case the file no longer exists.
resolved=$(realpath "$file" 2>/dev/null) \
  || resolved="$(realpath "$(dirname "$file")" 2>/dev/null)/$(basename "$file")"
[[ "$resolved" == "$REPO"/* ]] || exit 0

cd "$REPO" || exit 1
git add -A
git diff --staged --quiet && exit 0   # nothing to commit

if ! git commit -m "auto: update memory [$(hostname)]" >>"$LOG" 2>&1; then
    echo "$(date -Iseconds) COMMIT FAILED for $resolved" >>"$LOG"
    echo "memory auto-commit failed; see $LOG" >&2
    exit 0
fi

# Don't swallow push failures: the commit is local-only until this succeeds, and a silent
# push failure is the other way this repo drifts behind.
if ! git push >>"$LOG" 2>&1; then
    echo "$(date -Iseconds) PUSH FAILED -- commit is LOCAL ONLY. Recover with:" >>"$LOG"
    echo "  git -C $REPO push" >>"$LOG"
    echo "memory push failed; commit is local only. See $LOG" >&2
fi
exit 0
