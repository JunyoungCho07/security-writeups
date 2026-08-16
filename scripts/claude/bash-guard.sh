#!/usr/bin/env bash
# =================================================================
# bash-guard.sh — Claude Code PreToolUse hook (matcher: Bash)
#
# Stable entry point. The real policy engine is guard_bash.py, which
# TOKENIZES the command instead of substring-matching it (substring
# matching both over-blocks `-n` inside a quoted commit message and
# under-blocks `git -C dir commit --no-verify`, `git -c
# commit.gpgsign=false commit`, `sh -c '...'`, `xargs git ...`).
#
# If python3 is unavailable this falls back to the legacy regex checks:
# strictly weaker, but better than no enforcement. Never fails closed on
# a missing dependency — a guard bug must not brick the session.
#
# Exit 2 = block the tool call; stderr is fed back to Claude.
# =================================================================

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$HERE/guard_bash.py"

if command -v python3 >/dev/null 2>&1 && [ -f "$ENGINE" ]; then
    exec python3 "$ENGINE"
fi

# ---------------- degraded fallback (no python3) ----------------
INPUT=$(cat)
if command -v jq >/dev/null 2>&1; then
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
else
    CMD="$INPUT"
fi
[ -z "$CMD" ] && exit 0

deny() { printf 'BLOCKED by vault policy [%s]\n  %s\n' "$1" "$2" >&2; exit 2; }

if printf '%s' "$CMD" | grep -qE '(^|[^a-zA-Z0-9_-])(--no-verify|--no-gpg-sign)([^a-zA-Z0-9_-]|$)'; then
    deny "CLAUDE.md §1.2/§1.3" "pre-commit scan / GPG signing must not be bypassed."
fi
if printf '%s' "$CMD" | grep -qiE 'commit\.gpgsign[[:space:]=]+["'\'']?(false|0|no|off)'; then
    deny "CLAUDE.md §1.3" "disabling commit.gpgsign is not allowed in this vault."
fi
if printf '%s' "$CMD" | grep -qiE 'core\.hookspath'; then
    deny "CLAUDE.md §1.2" "redirecting core.hooksPath disarms the secret scan."
fi
if printf '%s' "$CMD" | grep -qE 'Pwn_College'; then
    deny "CLAUDE.md §1.6" "pwn.college material is local-only (platform ToS)."
fi
exit 0
