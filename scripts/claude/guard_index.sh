#!/usr/bin/env bash
# =================================================================
# guard_index.sh — Claude Code PostToolUse hook (matcher: Bash)
#
# State-based backstop for the no-publish rule. The PreToolUse bash guard
# blocks known *command forms*; this checks the *result*: after any shell
# command, if a no-publish path ended up staged — by whatever route,
# including stdin smuggling (`update-index --stdin`), a `git -C <dir>`
# working-directory trick, or a plumbing write — it is unstaged and a
# warning is fed back. Enforcing on index STATE catches routes no
# command-string filter can enumerate.
#
# Advisory + self-healing: exit 2 warns; the offending path is already
# removed from the index. Fails open on any error (no git, etc.).
# =================================================================
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -z "$ROOT" ] && exit 0
cd "$ROOT" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Directories whose contents must never be staged (platform ToS). Extend by
# dropping an empty `.nopublish` file into any tree.
NO_PUBLISH_DIRS=("Wargames/Pwn_College")

is_no_publish() {
    local p="$1" nd dir
    for nd in "${NO_PUBLISH_DIRS[@]}"; do
        case "$p" in "$nd"/*|"$nd") return 0 ;; esac
    done
    dir=$(dirname "$p")
    while [ "$dir" != "." ] && [ "$dir" != "/" ]; do
        [ -f "$ROOT/$dir/.nopublish" ] && return 0
        dir=$(dirname "$dir")
    done
    return 1
}

BAD=""
while IFS= read -r -d '' path; do
    [ -z "$path" ] && continue
    if is_no_publish "$path"; then
        git reset -q -- "$path" 2>/dev/null   # self-heal: unstage it
        BAD="$BAD $path"
    fi
done < <(git diff --cached --name-only -z 2>/dev/null)

if [ -n "$BAD" ]; then
    {
        echo "⚠ index-guard: no-publish path(s) were staged and have been UNSTAGED:"
        for p in $BAD; do echo "    $p"; done
        echo "These trees are local-only (platform ToS forbids public writeups)."
        echo "They must never enter the index — however the staging happened, it is undone."
    } >&2
    exit 2
fi
exit 0
