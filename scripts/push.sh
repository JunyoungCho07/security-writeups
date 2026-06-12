#!/usr/bin/env bash
# =================================================================
# push.sh — security-writeups GPG-signed push helper (macOS/Linux)
# Usage: ./scripts/push.sh "feat(bandit): level 3 - hidden files"
# Flags: --dry-run (scan + summary only)  --skip-push (commit only)
# Windows counterpart: push.ps1
# =================================================================

set -uo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}ℹ  $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
err()  { echo -e "${RED}✗ $1${NC}"; }

# --- Args -----------------------------------------------------------
COMMIT_MESSAGE=""
DRY_RUN=false
SKIP_PUSH=false
for arg in "$@"; do
    case "$arg" in
        --dry-run)   DRY_RUN=true ;;
        --skip-push) SKIP_PUSH=true ;;
        *)           COMMIT_MESSAGE="$arg" ;;
    esac
done
if [ -z "$COMMIT_MESSAGE" ]; then
    err "Usage: ./scripts/push.sh \"type(scope): message\" [--dry-run] [--skip-push]"
    exit 1
fi

# --- 1. Vault root ----------------------------------------------------
VAULT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$VAULT_ROOT"
[ -d ".git" ] || { err "Not a git repository: $VAULT_ROOT — run ./scripts/setup.sh first"; exit 1; }
info "Vault: $VAULT_ROOT"

# --- 2. GPG config check ------------------------------------------------
[ "$(git config --get commit.gpgsign)" = "true" ] || { err "commit.gpgsign not enabled. Run: git config commit.gpgsign true"; exit 1; }
SIGNKEY=$(git config --get user.signingkey || true)
[ -n "$SIGNKEY" ] || { err "user.signingkey not set. Run: git config user.signingkey E81313B5B651B0D9"; exit 1; }
ok "GPG signing enabled (key: $SIGNKEY)"

# --- 3. Stage + security scan -----------------------------------------
git add -A
if [ -x "scripts/pre-commit" ] || [ -f "scripts/pre-commit" ]; then
    info "Running pre-commit security scan..."
    if ! bash scripts/pre-commit; then
        err "Security scan BLOCKED the commit. Fix violations, then re-run."
        git reset >/dev/null
        exit 1
    fi
else
    warn "scripts/pre-commit not found — proceeding WITHOUT secret scan"
fi

# --- 4. Diff summary ------------------------------------------------------
STAGED=$(git diff --cached --name-status)
if [ -z "$STAGED" ]; then
    warn "No staged changes. Nothing to commit."
    exit 0
fi
info "Staged changes:"
echo "$STAGED" | sed 's/^/  /'
info "Summary: $(git diff --cached --shortstat | sed 's/^ //')"
info "Commit message: \"$COMMIT_MESSAGE\""
echo ""

# --- 5. Dry run -------------------------------------------------------------
if $DRY_RUN; then
    warn "DRY RUN — no commit or push"
    git reset >/dev/null
    exit 0
fi

# --- 6. Signed commit ---------------------------------------------------------
info "Committing (GPG passphrase may be required)..."
git commit -S -m "$COMMIT_MESSAGE" || { err "Commit failed (likely GPG passphrase/agent issue)."; exit 1; }
ok "Commit created and signed"

# --- 7. Push ---------------------------------------------------------------------
if $SKIP_PUSH; then
    warn "--skip-push set — commit is local only"
    exit 0
fi
git push origin HEAD || { err "Push failed. Commit is local. Retry: git push origin HEAD"; exit 1; }
ok "Pushed to GitHub"

# --- 8. Verify signature ----------------------------------------------------------
LATEST=$(git log -1 --pretty=format:'%H')
if git verify-commit "$LATEST" >/dev/null 2>&1; then
    ok "Signature verified: $LATEST"
    info "Check: https://github.com/JunyoungCho07/security-writeups/commit/$LATEST"
else
    warn "Local signature verification failed — GitHub may still show Verified if the key is uploaded"
fi
ok "Done."
