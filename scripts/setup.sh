#!/usr/bin/env bash
# =================================================================
# setup.sh — Initial vault git configuration (macOS/Linux)
# Usage: ./scripts/setup.sh
# Run ONCE after cloning the vault. Windows counterpart: setup.ps1
# =================================================================

set -uo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info() { echo -e "${CYAN}ℹ  $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
err()  { echo -e "${RED}✗ $1${NC}"; }

VAULT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$VAULT_ROOT"
info "Vault root: $VAULT_ROOT"

# --- 1. git init (if needed) -------------------------------------
if [ ! -d ".git" ]; then
    git init -b main && ok "git init done (branch: main)"
else
    ok "Git repo already initialized"
fi

# --- 2. GPG signing ------------------------------------------------
git config commit.gpgsign true
git config user.signingkey "E81313B5B651B0D9"
ok "GPG signing configured (key: $(git config --get user.signingkey))"

# --- 3. Identity ----------------------------------------------------
[ -z "$(git config --get user.name)" ]  && git config user.name "Junyoung Cho"
[ -z "$(git config --get user.email)" ] && git config user.email "chojunyoung070523@gmail.com"
ok "Identity: $(git config --get user.name) <$(git config --get user.email)>"

# --- 4. Remote ------------------------------------------------------
if [ -z "$(git config --get remote.origin.url || true)" ]; then
    git remote add origin "git@github.com:JunyoungCho07/security-writeups.git"
    ok "Remote 'origin' added (SSH)"
else
    ok "Remote 'origin': $(git config --get remote.origin.url)"
fi

# --- 5. Install pre-commit hook --------------------------------------
if [ -f "scripts/pre-commit" ]; then
    cp scripts/pre-commit .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    ok "Pre-commit hook installed to .git/hooks/pre-commit"
else
    warn "scripts/pre-commit not found — secret scan will NOT run automatically"
fi

# --- 6. Make Claude Code hook scripts executable ----------------------
chmod +x scripts/claude/*.sh 2>/dev/null && ok "Claude Code guard hooks executable"

# --- 7. Verify SSH to GitHub ------------------------------------------
info "Testing SSH connection to GitHub..."
if ssh -T -o StrictHostKeyChecking=accept-new git@github.com 2>&1 | grep -q "successfully authenticated"; then
    ok "GitHub SSH authentication works"
else
    warn "GitHub SSH test inconclusive — make sure your public key is registered on GitHub"
fi

# --- 8. Verify GPG can sign -------------------------------------------
info "Testing GPG signing capability..."
if echo "test" | gpg --clearsign --local-user "E81313B5B651B0D9" 2>/dev/null | grep -q "BEGIN PGP SIGNATURE"; then
    ok "GPG signing works"
else
    warn "GPG test failed — check gpg-agent is running and the key is loaded"
fi

echo ""
ok "Setup complete. First push: ./scripts/push.sh \"chore(infra): message\""
