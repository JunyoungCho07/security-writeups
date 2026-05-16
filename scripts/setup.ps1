# =================================================================
# setup.ps1 — Initial vault git configuration
# Usage: .\scripts\setup.ps1
# Run ONCE after copying vault files to final location.
# =================================================================

# Error handling: see push.ps1 for rationale. Git's stderr usage (warnings,
# verification info, progress) is non-error but $ErrorActionPreference="Stop"
# treats it as terminating. Use "Continue" + explicit $LASTEXITCODE checks.
$ErrorActionPreference = "Continue"

function Write-Info($msg) { Write-Host "ℹ  $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "✓ $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "⚠ $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "✗ $msg" -ForegroundColor Red }

# Resolve vault root (parent of scripts/)
$VaultRoot = Split-Path -Parent $PSScriptRoot
Set-Location $VaultRoot

Write-Info "Vault root: $VaultRoot"

# -----------------------------------------------------------------
# 1. git init (if needed)
# -----------------------------------------------------------------
if (-not (Test-Path ".git")) {
    Write-Info "Initializing git repository..."
    git init -b main
    Write-Ok "git init done (branch: main)"
} else {
    Write-Ok "Git repo already initialized"
}

# -----------------------------------------------------------------
# 2. Configure GPG signing
# -----------------------------------------------------------------
Write-Info "Configuring GPG signing..."
git config commit.gpgsign true
git config user.signingkey "E81313B5B651B0D9"

$ConfiguredKey = git config --get user.signingkey
Write-Ok "GPG signing key set: $ConfiguredKey"

# -----------------------------------------------------------------
# 3. Configure user name/email
# -----------------------------------------------------------------
$CurrentName  = git config --get user.name
$CurrentEmail = git config --get user.email

if ([string]::IsNullOrEmpty($CurrentName)) {
    git config user.name "Junyoung Cho"
    Write-Ok "user.name set: Junyoung Cho"
} else {
    Write-Ok "user.name already set: $CurrentName"
}

if ([string]::IsNullOrEmpty($CurrentEmail)) {
    git config user.email "chojunyoung070523@gmail.com"
    Write-Ok "user.email set: chojunyoung070523@gmail.com"
} else {
    Write-Ok "user.email already set: $CurrentEmail"
}

# -----------------------------------------------------------------
# 3.5. Configure SSH to use Windows native OpenSSH
# -----------------------------------------------------------------
# Windows has TWO OpenSSH binaries: Git for Windows' bundled MSYS2 ssh
# (uses MSYS2 ssh-agent, per-session, no DPAPI) and Windows native OpenSSH
# (uses Windows ssh-agent service, persistent via DPAPI).
# When user runs `ssh-add` from PowerShell, key is cached in Windows agent.
# But git defaults to Git for Windows' SSH -> can't see the cached key
# -> passphrase prompt on every push.
# Fix: force git to use Windows native OpenSSH (global config).
$WindowsSshPath = "C:\Windows\System32\OpenSSH\ssh.exe"
if (Test-Path $WindowsSshPath) {
    $SshPathForwardSlash = $WindowsSshPath.Replace('\','/')
    $CurrentSshCmd = git config --global --get core.sshCommand
    if ([string]::IsNullOrEmpty($CurrentSshCmd)) {
        git config --global core.sshCommand "$SshPathForwardSlash"
        Write-Ok "core.sshCommand set to Windows native OpenSSH (global): $SshPathForwardSlash"
    } else {
        Write-Ok "core.sshCommand already configured: $CurrentSshCmd"
    }
} else {
    Write-Warn "Windows native OpenSSH not found at $WindowsSshPath"
    Write-Warn "Install via: Settings -> Apps -> Optional features -> Add: OpenSSH Client"
    Write-Warn "Without this, git push will prompt for SSH passphrase every time."
}

# -----------------------------------------------------------------
# 4. Add remote (if not present)
# -----------------------------------------------------------------
# Use git config to check (avoids stderr noise from `git remote get-url`)
$ExistingRemote = git config --get remote.origin.url
if ([string]::IsNullOrEmpty($ExistingRemote)) {
    Write-Info "Adding remote origin..."
    git remote add origin "git@github.com:JunyoungCho07/security-writeups.git"
    Write-Ok "Remote 'origin' added (SSH)"
} else {
    Write-Warn "Remote 'origin' already exists: $ExistingRemote"
    Write-Warn "If wrong: git remote set-url origin git@github.com:JunyoungCho07/security-writeups.git"
}

# -----------------------------------------------------------------
# 5. Install pre-commit hook
# -----------------------------------------------------------------
$HookSrc = Join-Path $VaultRoot "scripts\pre-commit"
$HookDst = Join-Path $VaultRoot ".git\hooks\pre-commit"

if (Test-Path $HookSrc) {
    Copy-Item -Path $HookSrc -Destination $HookDst -Force
    # Make executable (Git for Windows respects this for hooks)
    & "C:\Program Files\Git\bin\bash.exe" -c "chmod +x '$($HookDst.Replace('\','/'))'"
    Write-Ok "Pre-commit hook installed to .git/hooks/pre-commit"
} else {
    Write-Warn "scripts/pre-commit not found — security scan will not run automatically"
}

# -----------------------------------------------------------------
# 6. Verify SSH connection to GitHub
# -----------------------------------------------------------------
Write-Info "Testing SSH connection to GitHub..."
$SshTest = ssh -T -o StrictHostKeyChecking=accept-new git@github.com 2>&1
if ($SshTest -match "successfully authenticated") {
    Write-Ok "GitHub SSH authentication works"
} else {
    Write-Warn "SSH test output: $SshTest"
    Write-Warn "Make sure your SSH public key is registered on GitHub."
}

# -----------------------------------------------------------------
# 7. Verify GPG can sign
# -----------------------------------------------------------------
Write-Info "Testing GPG signing capability..."
$GpgTest = "test" | gpg --clearsign --local-user "E81313B5B651B0D9" 2>&1
if ($GpgTest -match "BEGIN PGP SIGNATURE") {
    Write-Ok "GPG signing works"
} else {
    Write-Warn "GPG test failed. Make sure gpg-agent is running and key is loaded."
    Write-Warn "Output: $GpgTest"
}

# -----------------------------------------------------------------
# 8. Summary
# -----------------------------------------------------------------
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Setup complete" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Info "Next: First commit"
Write-Host "  .\scripts\push.ps1 `"chore(infra): initial vault structure`""
Write-Host ""
Write-Info "Vault status:"
git status -s
Write-Host ""
