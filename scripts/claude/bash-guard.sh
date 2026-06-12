#!/usr/bin/env bash
# =================================================================
# bash-guard.sh — Claude Code PreToolUse hook (matcher: Bash)
# Purpose: enforce CLAUDE.md §1 at the harness layer.
#   - Block `git commit --no-verify` / `-n` (pre-commit bypass)
#   - Block `--no-gpg-sign` and disabling commit.gpgsign
# Exit 2 = block the tool call; stderr is fed back to Claude.
# =================================================================

set -uo pipefail

INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
else
    # Fail-degraded: scan the raw JSON if jq is unavailable
    CMD="$INPUT"
fi

[ -z "$CMD" ] && exit 0

if printf '%s' "$CMD" | grep -qE 'git[[:space:]]+commit'; then
    if printf '%s' "$CMD" | grep -qE '(--no-verify|[[:space:]]-n([[:space:]]|$))'; then
        echo "BLOCKED by vault policy (CLAUDE.md §1.2): pre-commit secret scan must not be bypassed with --no-verify. If this is a confirmed false positive (e.g. PGP fingerprint), ask the user to run the command themselves." >&2
        exit 2
    fi
    if printf '%s' "$CMD" | grep -qE -- '--no-gpg-sign'; then
        echo "BLOCKED by vault policy (CLAUDE.md §1.3): all commits must be GPG-signed. Remove --no-gpg-sign." >&2
        exit 2
    fi
fi

if printf '%s' "$CMD" | grep -qE 'git[[:space:]]+config[^&|;]*commit\.gpgsign[[:space:]]+(false|0)'; then
    echo "BLOCKED by vault policy (CLAUDE.md §1.3): disabling commit.gpgsign is not allowed in this vault." >&2
    exit 2
fi

exit 0
