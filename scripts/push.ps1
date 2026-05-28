# =================================================================
# push.ps1 — security-writeups GPG-signed push helper
# Usage: .\scripts\push.ps1 "feat(bandit): level 3 - hidden files"
# =================================================================

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$CommitMessage,

    [Parameter(Mandatory=$false)]
    [switch]$DryRun,

    [Parameter(Mandatory=$false)]
    [switch]$SkipPush
)

# -----------------------------------------------------------------
# Error handling strategy
# -----------------------------------------------------------------
# Git writes non-error info to stderr (warnings, progress, GPG verification).
# $ErrorActionPreference = "Stop" + native command stderr capture causes
# false terminations. Instead use "Continue" and check $LASTEXITCODE explicitly
# after every critical git operation. This is PowerShell best practice for
# native commands.
$ErrorActionPreference = "Continue"

# -----------------------------------------------------------------
# Color helpers
# -----------------------------------------------------------------
function Write-Info($msg)    { Write-Host "ℹ  $msg" -ForegroundColor Cyan }
function Write-Ok($msg)      { Write-Host "✓ $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "⚠ $msg" -ForegroundColor Yellow }
function Write-Err($msg)     { Write-Host "✗ $msg" -ForegroundColor Red }

# -----------------------------------------------------------------
# 1. Verify we're in vault root
# -----------------------------------------------------------------
$VaultRoot = Split-Path -Parent $PSScriptRoot
Set-Location $VaultRoot

if (-not (Test-Path ".git")) {
    Write-Err "Not a git repository: $VaultRoot"
    Write-Err "Run setup.ps1 first or 'cd' to vault root."
    exit 1
}

Write-Info "Vault: $VaultRoot"

# -----------------------------------------------------------------
# 2. Verify GPG signing config
# -----------------------------------------------------------------
$GpgSign = git config --get commit.gpgsign
$SigningKey = git config --get user.signingkey

if ($GpgSign -ne "true") {
    Write-Err "commit.gpgsign is not enabled."
    Write-Err "Run: git config commit.gpgsign true"
    exit 1
}

if ([string]::IsNullOrEmpty($SigningKey)) {
    Write-Err "user.signingkey is not set."
    Write-Err "Run: git config user.signingkey E81313B5B651B0D9"
    exit 1
}

Write-Ok "GPG signing enabled (key: $SigningKey)"

# -----------------------------------------------------------------
# 3. Pre-commit security scan (manual run, since Windows git may skip hooks)
# -----------------------------------------------------------------
Write-Info "Running pre-commit security scan..."

$HookPath = Join-Path $VaultRoot "scripts\pre-commit"
if (Test-Path $HookPath) {
    # Stage everything first so hook can scan
    git add -A
    if ($LASTEXITCODE -ne 0) {
        Write-Err "git add -A failed (exit $LASTEXITCODE). Aborting."
        exit 1
    }

    # Run hook via bash (Git for Windows includes bash.exe)
    # Resolve bash dynamically: PATH first, then common install locations
    $BashExe = (Get-Command bash -ErrorAction SilentlyContinue).Source
    if (-not $BashExe) {
        $candidates = @(
            "C:\Program Files\Git\bin\bash.exe",
            "C:\Program Files (x86)\Git\bin\bash.exe",
            "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe",
            "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
        )
        $BashExe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if (-not $BashExe) { throw "bash not found. Install Git for Windows or add bash to PATH." }

    # PS cwd is already $VaultRoot (Set-Location at L39) → bash child inherits cwd.
    # Avoid explicit `cd` inside bash: Git Bash refuses to translate `C:/...` paths
    # inside single quotes (MSYS path mangling disabled), which would trigger a
    # false-positive "security violation" report (cd failure ≠ hook failure).
    & $BashExe -c "./scripts/pre-commit"
    $HookExit = $LASTEXITCODE

    if ($HookExit -ne 0) {
        # Distinguish bash/cd error from hook security failure.
        # Sentinel convention: hook itself exits 1 on violation; bash startup
        # errors typically exit 127 (command not found) or 126 (cannot execute).
        if ($HookExit -eq 126 -or $HookExit -eq 127) {
            Write-Err "Pre-commit hook FAILED TO START (bash exit $HookExit). Investigate hook permissions or shebang."
        } else {
            Write-Err "Pre-commit hook BLOCKED the commit (security violation, exit $HookExit)."
            Write-Err "Fix violations, then re-run push.ps1."
        }
        # Unstage to clean state
        git reset
        exit 1
    }
    Write-Ok "Pre-commit scan passed"
} else {
    Write-Warn "Pre-commit hook not found at $HookPath — proceeding without scan"
    git add -A
    if ($LASTEXITCODE -ne 0) {
        Write-Err "git add -A failed (exit $LASTEXITCODE). Aborting."
        exit 1
    }
}

# -----------------------------------------------------------------
# 4. Show diff summary
# -----------------------------------------------------------------
$StagedFiles = git diff --cached --name-status
if ([string]::IsNullOrWhiteSpace($StagedFiles)) {
    Write-Warn "No staged changes. Nothing to commit."
    exit 0
}

Write-Info "Staged changes:"
$StagedFiles | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
Write-Host ""

$StagedCount = ($StagedFiles -split "`n").Count
$LinesAdded = (git diff --cached --shortstat | Select-String -Pattern '\d+ insertions?' | ForEach-Object { $_.Matches[0].Value }) -replace ' insertions?', ''
$LinesRemoved = (git diff --cached --shortstat | Select-String -Pattern '\d+ deletions?' | ForEach-Object { $_.Matches[0].Value }) -replace ' deletions?', ''

Write-Info "Summary: $StagedCount file(s), +$LinesAdded -$LinesRemoved lines"
Write-Info "Commit message: `"$CommitMessage`""
Write-Host ""

# -----------------------------------------------------------------
# 5. Dry run mode — show what would happen, don't execute
# -----------------------------------------------------------------
if ($DryRun) {
    Write-Warn "DRY RUN — no commit or push will execute"
    git reset  # unstage
    exit 0
}

# -----------------------------------------------------------------
# 6. Commit (signed)
# -----------------------------------------------------------------
Write-Info "Committing (GPG passphrase may be required if agent cache expired)..."

git commit -S -m $CommitMessage
if ($LASTEXITCODE -ne 0) {
    Write-Err "Commit failed (likely GPG passphrase issue)."
    Write-Err "Verify gpg-agent is running and key is loaded."
    exit 1
}

Write-Ok "Commit created and signed"

# -----------------------------------------------------------------
# 7. Push (unless --SkipPush)
# -----------------------------------------------------------------
if ($SkipPush) {
    Write-Warn "SkipPush flag set — commit local only, not pushed"
    exit 0
}

Write-Info "Pushing to origin..."
git push origin HEAD
if ($LASTEXITCODE -ne 0) {
    Write-Err "Push failed. Commit is local. Run: git push origin HEAD"
    exit 1
}

Write-Ok "Pushed to GitHub"

# -----------------------------------------------------------------
# 8. Verify Verified badge will show
# Note: git verify-commit writes verification info to stderr even on success.
# Global $ErrorActionPreference = "Continue" makes this safe; check $LASTEXITCODE.
# -----------------------------------------------------------------
$LatestCommit = git log -1 --pretty=format:"%H"

$VerifyResult = git verify-commit $LatestCommit 2>&1 | Out-String
$VerifyExit = $LASTEXITCODE

if ($VerifyExit -eq 0) {
    Write-Ok "Commit signature verified locally: $LatestCommit"
    Write-Info "Check GitHub: https://github.com/JunyoungCho07/security-writeups/commit/$LatestCommit"
} else {
    Write-Warn "Local signature verification failed (exit $VerifyExit). GitHub may still show Verified if key uploaded correctly."
    Write-Warn "Verify output: $VerifyResult"
}

Write-Host ""
Write-Ok "Done."
