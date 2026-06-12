#!/usr/bin/env bash
# =================================================================
# write-guard.sh — Claude Code PostToolUse hook (matcher: Write|Edit)
# Purpose: defense-in-depth ABOVE the git pre-commit hook — warn the
# moment credential-looking content lands in a file, not at commit time.
# Same suspect pattern + whitelist as scripts/pre-commit (keep in sync).
# Exit 2 = warning fed back to Claude (tool already ran; non-blocking).
# =================================================================

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0   # warn-only layer: fail open

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null)

[ -z "$CONTENT" ] && exit 0

# Only police vault note/script files
case "$FILE" in
    *.md|*.txt|*.sh|*.ps1) ;;
    *) exit 0 ;;
esac

SUSPECT=$(printf '%s' "$CONTENT" | grep -nE '[a-zA-Z0-9]{30,}' | \
    grep -ivE '(masked|redacted|example|placeholder|<.*>|sha256|sha-256|sha512|fingerprint|hash|commit|uuid|public[[:space:]]+key|key[[:space:]]+id|ssh-ed25519|ssh-rsa|aaaa[a-z]{4})' || true)

if [ -n "$SUSPECT" ]; then
    {
        echo "⚠ write-guard: possible UNMASKED CREDENTIAL just written to $FILE:"
        echo "$SUSPECT" | head -3
        echo "If this is a real password, replace it with '<password masked>' NOW (CLAUDE.md §1.1). If it is a safe high-entropy string (hash, fingerprint, base64 sample), add a whitelist word to the line or leave as is — the git pre-commit hook will make the final call."
    } >&2
    exit 2
fi

exit 0
