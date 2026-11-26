#!/usr/bin/env bash
# Pull latest memory before Claude reads it.
# Called as a UserPromptSubmit hook.
#
# Two things to know:
#   * UserPromptSubmit fires on EVERY prompt, not once per conversation as the original
#     comment claimed, so the pull is throttled to once per PULL_INTERVAL seconds
#     instead of hitting the remote dozens of times a session.
#   * stdout from a UserPromptSubmit hook is injected into Claude's context, so this
#     script writes only to the log and to stderr -- never stdout.

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
sync-memory-pull.sh - pull the latest Claude memory from origin.

Installed to ~/.claude/ by home-manager and registered as a UserPromptSubmit
hook in ~/.claude/settings.json. Takes no arguments. That hook fires on every
prompt, so the pull is throttled to once per PULL_INTERVAL seconds via a stamp
file at ~/.claude/.sync-memory-last-pull.

Failures (including a diverged branch) are appended to ~/.claude/sync-memory.log.
EOF
    exit 0
fi

REPO=/Users/scott/.claude/shared-memory
LOG=/Users/scott/.claude/sync-memory.log
STAMP=/Users/scott/.claude/.sync-memory-last-pull
PULL_INTERVAL=300

cd "$REPO" || exit 0

now=$(date +%s)
if [[ -f "$STAMP" ]]; then
    last=$(cat "$STAMP" 2>/dev/null || echo 0)
    [[ "$last" =~ ^[0-9]+$ ]] || last=0
    (( now - last < PULL_INTERVAL )) && exit 0
fi
# Stamped before the pull on purpose: a failing remote should not be retried every prompt.
echo "$now" >"$STAMP"

# Don't swallow the outcome. A non-fast-forward means local and remote have both moved,
# and memories written on latitude or vm01 will never arrive until that is reconciled --
# the silent `2>/dev/null || true` here is how that would go unnoticed indefinitely.
if ! out=$(git pull --ff-only 2>&1); then
    {
        echo "$(date -Iseconds) PULL FAILED on $(hostname)"
        echo "$out" | sed 's/^/  /'
        if counts=$(git rev-list --left-right --count origin/main...main 2>/dev/null); then
            echo "  behind/ahead vs origin: $counts"
            echo "  diverged -> reconcile with: git -C $REPO pull --rebase"
        fi
    } >>"$LOG"
    echo "memory pull failed (see $LOG); local may be diverged from origin" >&2
fi
exit 0
