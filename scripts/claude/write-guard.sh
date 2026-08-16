#!/usr/bin/env bash
# =================================================================
# write-guard.sh — Claude Code PostToolUse hook (matcher: Write|Edit)
#
# Stable entry point for guard_write.py: credential detection plus vault
# placement/naming checks, the moment content lands rather than at commit
# time. Advisory by design — exit 2 feeds a correction back to the model;
# the git pre-commit hook remains the hard gate.
#
# Falls back to the legacy inline scan if python3 is unavailable.
# =================================================================

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$HERE/guard_write.py"

if command -v python3 >/dev/null 2>&1 && [ -f "$ENGINE" ]; then
    exec python3 "$ENGINE"
fi

# ---------------- degraded fallback (no python3) ----------------
command -v jq >/dev/null 2>&1 || exit 0   # warn-only layer: fail open

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null)
[ -z "$CONTENT" ] && exit 0

case "$FILE" in
    *.md|*.txt|*.sh|*.ps1|*.py|*.json|*.yml|*.yaml) ;;
    *) exit 0 ;;
esac

SUSPECT=$(printf '%s' "$CONTENT" | grep -nE '[a-zA-Z0-9]{30,}' | \
    grep -ivE '(masked|redacted|example|placeholder|<.*>|sha256|sha-256|sha512|fingerprint|hash|digest|uuid|public[[:space:]]+key|key[[:space:]]+id|ssh-ed25519|ssh-rsa)' || true)

if [ -n "$SUSPECT" ]; then
    {
        echo "⚠ write-guard: possible UNMASKED CREDENTIAL just written to $FILE:"
        echo "$SUSPECT" | head -3
        echo "This repo is public. Replace a real password with '<password masked>' NOW (CLAUDE.md §1.1)."
    } >&2
    exit 2
fi
exit 0
