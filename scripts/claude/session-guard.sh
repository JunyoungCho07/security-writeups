#!/usr/bin/env bash
# =================================================================
# session-guard.sh — Claude Code SessionStart hook
# Purpose: self-heal the security layer at every session start.
#   1. Install/refresh .git/hooks/pre-commit from scripts/pre-commit
#   2. Verify GPG signing config is active
# Output (stdout) is injected into Claude's context — keep it terse.
# =================================================================

set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -z "$ROOT" ] && exit 0
cd "$ROOT" || exit 0

STATUS=()

# --- 1. pre-commit hook: install if missing, refresh if stale ----
SRC="scripts/pre-commit"
DST=".git/hooks/pre-commit"
if [ -f "$SRC" ]; then
    if [ ! -f "$DST" ] || ! cmp -s "$SRC" "$DST"; then
        cp "$SRC" "$DST" && chmod +x "$DST"
        STATUS+=("pre-commit hook: INSTALLED/UPDATED from $SRC")
    else
        STATUS+=("pre-commit hook: ok")
    fi
else
    STATUS+=("pre-commit hook: MISSING SOURCE ($SRC) — secret scan disabled!")
fi

# --- 2. GPG signing config -----------------------------------------
GPGSIGN=$(git config --get commit.gpgsign || true)
SIGNKEY=$(git config --get user.signingkey || true)
if [ "$GPGSIGN" = "true" ] && [ -n "$SIGNKEY" ]; then
    STATUS+=("gpg signing: ok (key ${SIGNKEY})")
else
    STATUS+=("gpg signing: NOT CONFIGURED — run ./scripts/setup.sh before committing")
fi

printf '[security-writeups guard] %s | %s\n' "${STATUS[0]}" "${STATUS[1]}"
exit 0
