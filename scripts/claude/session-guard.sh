#!/usr/bin/env bash
# =================================================================
# session-guard.sh — Claude Code SessionStart hook
# Purpose: self-heal the security layer at every session start and say,
# in ONE terse line, what state it is in. Output (stdout) is injected into
# Claude's context. Exit 0 always: a broken guard must never brick a
# session — it reports, loudly, instead.
#
#   1. Install/refresh the three git hooks from their sources:
#        pre-commit        <- scripts/pre-commit   (index gate)
#        pre-merge-commit  <- scripts/pre-commit   (a --no-ff merge never
#                                                  ran pre-commit)
#        pre-push          <- scripts/pre-push     (publication boundary)
#      The hooks dir is asked from git (`rev-parse --git-path hooks`), so a
#      worktree gets the shared dir. A symlink or directory at the hook path
#      is removed first — `cp` used to write THROUGH a symlink to /dev/null
#      and still report INSTALLED. The post-condition (regular file, not a
#      symlink, executable, byte-equal to the source) is what decides
#      between "ok", "INSTALLED" and "FAILED … DISARMED": nothing is
#      reported that was not verified.
#   2. core.hooksPath set → git never reads .git/hooks: reported DISARMED,
#      never "ok".
#   3. Signing: commit.gpgsign=true, gpg.format openpgp (or unset),
#      user.signingkey is the declared key, gpg.program is real GnuPG, and
#      the secret key is in the keyring (a listing — prints no material).
#   4. No-publish markers: a missing .nopublish in a hardcoded tree is
#      restored (markers are untracked, so a fresh clone has none).
#   5. Hook inventory: any non-.sample file in the hooks dir that is not one
#      of the three managed hooks is NAMED, never deleted — that is JY's call.
#   6. Identifiers (§1.5): a count of <git-dir>/info/identifiers entries,
#      never their contents; the file is never created or edited here.
# =================================================================

set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -z "$ROOT" ] && exit 0
cd "$ROOT" || exit 0

DECLARED_KEY="E81313B5B651B0D9"   # CLAUDE.md §1.3 — a constant, no env override
# Keep in sync with scripts/pre-commit, scripts/pre-push, scripts/claude/guard_index.sh
NO_PUBLISH_DIRS=("Wargames/Pwn_College" "Wargames/GoN")
MANAGED_HOOKS="pre-commit pre-merge-commit pre-push"
STATUS=()

# --- 1. git hooks: install if missing, refresh if stale, verify -----
HOOKS_DIR=$(git rev-parse --git-path hooks 2>/dev/null || echo .git/hooks)
HP=$(git config --get core.hooksPath 2>/dev/null || true)
if [ -n "$HP" ]; then
    STATUS+=("hooks: DISARMED — core.hooksPath=$HP redirects git away from $ROOT/.git/hooks; JY: git config --unset core.hooksPath")
else
    mkdir -p "$HOOKS_DIR" 2>/dev/null
    OK=""
    for pair in pre-commit:scripts/pre-commit pre-merge-commit:scripts/pre-commit pre-push:scripts/pre-push; do
        h=${pair%%:*}; src=${pair#*:}; dst="$HOOKS_DIR/$h"
        if [ ! -f "$src" ]; then
            STATUS+=("$h hook: MISSING SOURCE ($src) — DISARMED"); continue
        fi
        if [ -L "$dst" ] || [ -d "$dst" ]; then rm -rf "$dst" 2>/dev/null; fi   # never legitimate here
        if [ -f "$dst" ] && [ ! -L "$dst" ] && [ -x "$dst" ] && cmp -s "$src" "$dst"; then
            OK="$OK $h"; continue
        fi
        cp "$src" "$dst" 2>/dev/null && chmod +x "$dst" 2>/dev/null
        if [ -f "$dst" ] && [ ! -L "$dst" ] && [ -x "$dst" ] && cmp -s "$src" "$dst"; then
            STATUS+=("$h hook: INSTALLED from $src")
        else
            STATUS+=("$h hook: FAILED to install at $dst — DISARMED")
        fi
    done
    [ -n "$OK" ] && STATUS+=("hooks ok:$OK")

    # --- 1b. inventory: anything else in the hooks dir is named, not touched
    UNEXPECTED=""
    for f in "$HOOKS_DIR"/*; do
        [ -e "$f" ] || continue
        n=${f##*/}
        case "$n" in *.sample) continue ;; esac
        case " $MANAGED_HOOKS " in *" $n "*) continue ;; esac
        UNEXPECTED="$UNEXPECTED $n"
    done
    [ -n "$UNEXPECTED" ] && STATUS+=("unexpected hook(s):$UNEXPECTED — left in place, JY decides")
fi

# --- 2. GPG signing: the declared key, openpgp, real GnuPG, secret present
GPGSIGN=$(git config --get commit.gpgsign 2>/dev/null || true)
SIGNKEY=$(git config --get user.signingkey 2>/dev/null || true)
FMT=$(git config --get gpg.format 2>/dev/null || true)
PROG=$(git config --get gpg.program 2>/dev/null || true); [ -z "$PROG" ] && PROG=gpg
key_ok() { case "$(printf '%s' "$1" | tr 'a-z' 'A-Z')" in *"$DECLARED_KEY") return 0 ;; esac; return 1; }
if [ "$GPGSIGN" != "true" ]; then
    STATUS+=("gpg signing: NOT CONFIGURED (commit.gpgsign=${GPGSIGN:-unset}) — run ./scripts/setup.sh")
elif [ -n "$FMT" ] && [ "$FMT" != "openpgp" ]; then
    STATUS+=("gpg signing: WRONG FORMAT gpg.format=$FMT (expected openpgp)")
elif ! key_ok "$SIGNKEY"; then
    STATUS+=("gpg signing: WRONG KEY user.signingkey=${SIGNKEY:-unset} (declared $DECLARED_KEY)")
elif ! "$PROG" --version 2>/dev/null | head -1 | grep -q '^gpg (GnuPG)'; then
    STATUS+=("gpg signing: gpg.program=$PROG is not GnuPG")
elif ! "$PROG" --batch --list-secret-keys "$DECLARED_KEY" >/dev/null 2>&1; then
    STATUS+=("gpg signing: SECRET KEY $DECLARED_KEY NOT IN KEYRING — commits will fail to sign")
else
    STATUS+=("gpg signing: ok (key $DECLARED_KEY, secret present)")
fi

# --- 3. no-publish markers: the layer that survives case games ------
M=""
for d in "${NO_PUBLISH_DIRS[@]}"; do
    [ -d "$d" ] || continue
    [ -e "$d/.nopublish" ] && continue
    if : > "$d/.nopublish" 2>/dev/null; then M="$M $d"
    else STATUS+=("no-publish marker: FAILED to create $d/.nopublish"); fi
done
if [ -n "$M" ]; then STATUS+=("no-publish markers RESTORED in:$M"); else STATUS+=("no-publish markers: ok"); fi

# --- 4. identifiers (§1.5): count only, never the contents ---------
IDF=$(git rev-parse --git-path info/identifiers 2>/dev/null || true)
NID=0
if [ -n "$IDF" ] && [ -f "$IDF" ]; then
    NID=$(awk '{ s=$0; gsub(/^[ \t]+|[ \t]+$/, "", s); if (length(s) >= 3 && s !~ /^#/) n++ } END { print n+0 }' "$IDF" 2>/dev/null)
fi
if [ "${NID:-0}" -gt 0 ]; then STATUS+=("identifiers: $NID entries"); else STATUS+=("identifiers: none configured"); fi

LINE=""; for s in "${STATUS[@]}"; do LINE="${LINE:+$LINE | }$s"; done
printf '[security-writeups guard] %s\n' "$LINE"
exit 0
