#!/usr/bin/env python3
# =====================================================================
# guard_bash.py — Claude Code PreToolUse hook (matcher: Bash)
#
# Enforces the vault's hard security policy (CLAUDE.md §1) by PARSING the
# command, not by substring-matching it. Substring matching both over-blocks
# (`-n` inside a quoted commit message) and under-blocks (`git -C dir commit
# --no-verify`, `git -c commit.gpgsign=false commit`, `sh -c '...'`).
#
# Contract:
#   stdin : PreToolUse JSON  {"tool_name":"Bash","tool_input":{"command":...}}
#   exit 2: BLOCK  (stderr is fed back to Claude)   <- fail CLOSED on a match
#   exit 0: allow                                   <- fail OPEN on crash
#
# Fail-mode policy (deliberate): a crash or an unparseable payload must never
# brick the session, so every unexpected exception exits 0. A *matched*
# violation always exits 2. Bypass attempts that the parser cannot decompose
# are treated as matches, not as crashes.
# =====================================================================
import json
import os
import re
import shlex
import sys

# --- policy tables ---------------------------------------------------

# Paths that are part of the enforcement layer itself. Mutating them from the
# shell disarms the harness, so only read-only inspection is permitted.
# No trailing slash: the marker must match the bare directory too, so a `find`
# whose start-dir is `scripts/claude` (no slash) is still recognised.
PROTECTED_PATH_MARKERS = (
    ".git/hooks",
    "hooks/pre-commit",        # catches $(git rev-parse --git-dir)/hooks/pre-commit
    "scripts/claude",
    "scripts/pre-commit",
    ".claude/settings",
    ".git/config",             # editing it disables signing / redirects hooks
    ".nopublish",              # the marker that makes a tree no-publish
)

# Basenames of enforcement-layer files. A `find -name <basename>` names the
# target without ever writing the full protected path, so the marker scan alone
# misses it — this set closes that.
PROTECTED_BASENAMES = {
    "pre-commit", "settings.json", "settings.local.json",
    "bash-guard.sh", "session-guard.sh", "write-guard.sh",
    "guard_bash.py", "guard_write.py", "guard_index.sh",
}

# Content that must never reach the index or the remote (platform ToS, or —
# for GoN — because the entrance problems are reused for the next cohort).
#
# `path_hits` is a case-SENSITIVE substring test, which is why "GoN" is safe to
# list bare: lowercase "gon" (dragon, polygon, hexagon) cannot collide with it.
# A lowercase spelling on macOS's case-insensitive APFS would slip past this
# tuple, but not past the `.nopublish` marker scan in pre-commit/guard_index.sh
# — those resolve the marker through the filesystem, which is case-insensitive
# too. Proactive layer here, state-based backstop there.
NO_PUBLISH_MARKERS = ("Pwn_College", "pwn_college", "pwn.college", "GoN")

# Private key material. A security vault has no reason to read the operator's
# own keys, and anything read here can end up quoted in a note.
SECRET_READ_MARKERS = (
    "/.ssh", "/.gnupg", "/etc/shadow", "/.aws/credentials",
    "/.docker/config.json",
)

# Commands that only read. A protected path may appear in these.
READONLY_CMDS = {
    "cat", "less", "more", "head", "tail", "grep", "egrep", "fgrep", "rg", "ag",
    "ls", "find", "stat", "file", "wc", "diff", "cmp", "md5", "md5sum",
    "shasum", "sha256sum", "echo", "printf", "test", "true", "false", "which",
    "type", "command", "realpath", "readlink", "dirname", "basename", "sort",
    "uniq", "cut", "awk", "column", "jq", "xxd", "od", "strings", "pwd", "env",
}

# Commands that write, move, or destroy a path given as an argument.
# Executing or reading a protected file is fine; rewriting it is not.
PATH_MUTATORS = {
    "rm", "mv", "cp", "chmod", "chown", "chgrp", "ln", "truncate", "dd", "tee",
    "install", "shred", "unlink", "rmdir", "sed", "patch", "ed", "ex", "rsync",
    "mktemp", "gsed", "vim", "vi", "nano", "awk", "sponge", "gawk", "mawk",
    "unzip", "tar", "cpio", "pax", "gtar", "bsdtar", "zip", "xxd", "xz",
    "link", "ditto", "gcp",
}

# Any interpreter that can be handed code to run. For these, EVERY string
# argument is treated as a program and scanned — the code can arrive via -e,
# -c, `eval`, or a positional, and enumerating each interpreter's flag is a
# losing game (round 3/4 found lua, Rscript, deno, bun, tclsh gaps this way).
INTERPRETERS = {
    "python", "python3", "perl", "ruby", "node", "php", "lua", "luajit",
    "rscript", "bun", "deno", "tclsh", "wish", "osascript",
    "pwsh", "powershell",
    # tools that can shell out from a script/eval argument
    "sqlite3", "emacs", "gdb", "expect", "gawk", "jjs", "groovy", "scala",
}

# Wrappers whose string argument is CODE and must be re-analysed.
SHELL_WRAPPERS = {"sh", "bash", "zsh", "dash", "ksh", "csh", "tcsh", "fish"}
# interpreter -> flags whose VALUE is an inline program
INLINE_CODE_FLAGS = {
    "python": {"-c"}, "python3": {"-c"}, "perl": {"-e", "-E"},
    "ruby": {"-e"}, "node": {"-e", "--eval", "-p"}, "php": {"-r"},
    "awk": set(), "osascript": {"-e"},
}
# find(1) is read-only until one of these turns it into an executor
FIND_MUTATING_ACTIONS = {"-delete", "-exec", "-execdir", "-ok", "-okdir"}
# Transparent prefixes: strip and analyse the remainder as the real command.
TRANSPARENT_PREFIXES = {
    "sudo", "doas", "env", "nohup", "time", "nice", "ionice", "stdbuf",
    "setsid", "timeout", "command", "builtin", "exec", "caffeinate",
    "busybox", "toybox", "watch", "taskset", "setarch", "chrt", "unbuffer",
    "proxychains", "proxychains4", "parallel", "flock", "rlwrap", "catchsegv",
}
# Interpreters that can be handed a program on stdin (`python3 -`, heredoc).
STDIN_INTERPRETERS = {"python", "python3", "perl", "ruby", "node", "php"}

REDIRECT_OPS = {">", ">>", "&>", ">|", "&>>"}
SEGMENT_SEPARATORS = {";", "&&", "||", "|", "&", "(", ")", "{", "}", "\n", "|&"}

# git subcommand flags that take a value we must NOT scan as a flag.
# Flags whose value is the NEXT token (so a bypass flag hiding after them is
# not a value). NOTE: -S / --gpg-sign are deliberately EXCLUDED — git takes
# their key-id as an OPTIONAL attached-only argument (`-S<keyid>`), so
# `git commit -S --no-verify` leaves --no-verify live, not swallowed.
COMMIT_VALUE_FLAGS = {
    "-m", "--message", "-F", "--file", "-C", "--reuse-message", "-c",
    "--reedit-message", "--author", "--date", "--fixup", "--squash",
    "--cleanup", "--pathspec-from-file", "-t", "--template",
}
# git top-level (pre-subcommand) options that consume the next token.
GIT_GLOBAL_VALUE_OPTS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace",
                         "--exec-path", "--config-env"}
# top-level options that, like -C, relocate where a staging op writes — a
# no-publish tree reached through them is the same violation as via -C.
GIT_WORKTREE_OPTS = {"-C", "--work-tree", "--git-dir"}

FALSY = {"false", "0", "no", "off", "", "n"}


def is_git_falsy(value):
    """git's own boolean parse is looser than a fixed word set: `00`, `0x0`,
    `+0`, `-0` all mean false. Treat any explicit falsy word OR any integer
    literal equal to zero as falsy, so commit.gpgsign can't be turned off with
    an unusual spelling."""
    v = value.strip().strip("\"'").lower()
    if v in FALSY:
        return True
    try:
        return int(v, 0) == 0
    except (ValueError, TypeError):
        return False


def fail_open(msg):
    """Internal problem: never brick the session."""
    if msg and os.environ.get("GUARD_DEBUG"):
        sys.stderr.write("guard_bash: %s\n" % msg)
    sys.exit(0)


def block(rule, detail, fix):
    sys.stderr.write(
        "BLOCKED by vault policy [%s]\n  %s\n  → %s\n" % (rule, detail, fix)
    )
    sys.exit(2)


def ask(rule, detail, fix):
    """Not forbidden — but the user's call, not the agent's.

    Emits the PreToolUse `ask` decision so the permission prompt reaches a
    human instead of the model deciding for itself.
    """
    sys.stdout.write(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": "[%s] %s → %s" % (rule, detail, fix),
        }
    }))
    sys.exit(0)


def is_prefix_flag(token, full, min_len):
    """git accepts unambiguous long-option prefixes: --no-veri == --no-verify."""
    return (
        len(token) >= min_len
        and full.startswith(token)
        and token.startswith("--")
    )


def normalize_newlines(cmd):
    """Turn unquoted newlines into `;` so each LINE is its own command.

    shlex treats a newline as plain whitespace, which collapsed a multi-line
    script into a single segment: the first line's command name was applied to
    every later line's arguments. That produced both false positives (`cp` on
    line 1 "owning" a path from line 6) and — worse — false negatives, since a
    benign first line hid a `git commit --no-verify` further down.
    A backslash-newline is a line continuation and becomes a space instead.
    """
    out = []
    quote = None
    i = 0
    while i < len(cmd):
        ch = cmd[i]
        if quote:
            out.append(ch)
            if ch == quote and quote == '"' and i and cmd[i - 1] == "\\":
                pass                       # escaped quote inside "..."
            elif ch == quote:
                quote = None
            i += 1
            continue
        if ch == "\\":
            if i + 1 < len(cmd) and cmd[i + 1] == "\n":
                out.append(" ")            # line continuation
                i += 2
                continue
            out.append(ch)
            if i + 1 < len(cmd):
                out.append(cmd[i + 1])
                i += 2
                continue
            i += 1
            continue
        if ch in ("'", '"'):
            quote = ch
            out.append(ch)
            i += 1
            continue
        out.append(";" if ch == "\n" else ch)
        i += 1
    return "".join(out)


def tokenize(cmd):
    lex = shlex.shlex(normalize_newlines(cmd), posix=True,
                      punctuation_chars=True)
    lex.whitespace_split = True
    return list(lex)


def split_segments(tokens):
    """Split a token stream into simple commands on shell operators."""
    segments, cur = [], []
    for tok in tokens:
        if tok in SEGMENT_SEPARATORS:
            if cur:
                segments.append(cur)
            cur = []
        else:
            cur.append(tok)
    if cur:
        segments.append(cur)
    return segments


def check_env_assignment(tok):
    """git reads config from the environment too — GIT_CONFIG_* smuggling."""
    key, _, val = tok.partition("=")
    ku, vl = key.upper(), val.strip().strip("\"'").lower()
    if ku.startswith("GIT_CONFIG_KEY_") and vl in ("commit.gpgsign",
                                                   "core.hookspath",
                                                   "tag.gpgsign"):
        block(
            "CLAUDE.md §1.2/§1.3 — config smuggling",
            "`%s` injects a config override through the environment, "
            "bypassing `git config`." % tok,
            "Signing and hook path are not negotiable per-command.",
        )
    if ku in ("GIT_WORK_TREE", "GIT_DIR") and path_hits(val, NO_PUBLISH_MARKERS):
        block(
            "CLAUDE.md §1.6 — no-publish set",
            "`%s` relocates git's work tree into pwn.college material." % tok,
            "That tree is local-only; nothing under it may enter the index.",
        )
    if ku in ("GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM", "GIT_CONFIG"):
        block(
            "CLAUDE.md §1.2/§1.3 — config smuggling",
            "`%s` repoints git at a different config file, which can carry its "
            "own core.hooksPath or unset signing." % tok,
            "Leave git's global/system config attached; the vault never "
            "reassigns it.",
        )
    if ku == "GIT_CONFIG_PARAMETERS":
        low = val.lower()
        # ANY mention of a signing/hook key is refused regardless of value or
        # quoting form — git accepts both `k=v` and the split `'k'='v'`, and an
        # EMPTY value means false, so a value-regex misses `commit.gpgsign=` and
        # `'commit.gpgsign'='false'`.
        if any(k in low for k in ("commit.gpgsign", "tag.gpgsign",
                                  "core.hookspath", "gpg.program")):
            block(
                "CLAUDE.md §1.2/§1.3 — config smuggling",
                "`%s` injects signing/hook git config through the "
                "environment." % tok,
                "Signing and hook path are not negotiable per-command.",
            )
    if ku == "GIT_ALLOW_PROTOCOL" or ku.startswith("GIT_SSH"):
        return
    if ku == "HUSKY" and vl == "0":
        block("harness integrity", "`%s` disables hook execution." % tok,
              "Hooks must run.")


SHELL_KEYWORDS = {"do", "then", "else", "elif", "!", "time", "coproc"}


def strip_prefixes(seg):
    """Drop env assignments (FOO=bar), transparent wrappers (sudo, env...) and
    leading shell keywords (`do rm …` inside a for-loop body)."""
    i = 0
    while i < len(seg):
        tok = seg[i]
        if tok in SHELL_KEYWORDS:
            i += 1
            continue
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok):
            check_env_assignment(tok)
            i += 1
            continue
        base = os.path.basename(tok)
        if base in TRANSPARENT_PREFIXES:
            i += 1
            # `timeout 5s cmd` / `nice -n 5 cmd`: skip numeric/flag operands
            while i < len(seg) and (
                seg[i].startswith("-") or re.match(r"^[0-9]+[smhd]?$", seg[i])
            ):
                i += 1
            # flock takes a mandatory lockfile/fd positional before the command
            if base == "flock" and i < len(seg):
                i += 1
            continue
        break
    return seg[i:]


def path_hits(token, markers):
    """Substring match AFTER normalization, so `.git/./hooks`,
    `.git//hooks`, and `foo/../.git/hooks` cannot slip a marker past a raw
    substring test (the red team's `rm .git/./hooks/pre-commit` bypass).
    """
    raw = token.replace("\\", "/")
    norm = os.path.normpath(raw)          # collapse ./  //  and resolve ..
    return any(m in raw or m in norm for m in markers)


_GLOB_CHARS = "*?[{"
# partial prefixes catch a glob that stops short of the full marker, e.g.
# `scripts/cla*` (→ scripts/claude) or `.git/hook*`.
_PARTIALS = ("scripts/cla", "scripts/pre-commit", ".git/hook",
             "hooks/pre-commit", ".claude/set")
# keywords that make a glob suspicious when it also carries a wildcard
_GLOB_KEYWORDS = ("claude", "hook", "pre-commit", "settings", "/.git", "guard")


def expand_braces(tok):
    """Expand a single `{a,b,c}` group so `scripts/{claude,pre-commit}` and
    `scripts/{cla,pre}*` are checked as their variants."""
    m = re.search(r"\{([^{}]*,[^{}]*)\}", tok)
    if not m:
        return [tok]
    pre, post = tok[:m.start()], tok[m.end():]
    out = []
    for opt in m.group(1).split(","):
        out.extend(expand_braces(pre + opt + post))
    return out


def aims_at_guard(token, loose=False):
    """Does this token name — or glob toward — the enforcement layer?"""
    return any(_aims_one(v, loose) for v in expand_braces(token))


def _aims_one(token, loose=False):
    """`loose=True` (for find -name patterns) also matches a bare `guard*`.
    The glob-keyword branch catches `rm -rf scripts/cla*`, `*guard*`,
    `scr*/claude`, where the literal marker never appears but the shell
    expansion would hit a guard file.
    """
    n = os.path.normpath(token.replace("\\", "/")).lower()
    if any(m.lower() in n for m in PROTECTED_PATH_MARKERS):
        return True
    if any(p in n for p in _PARTIALS):
        return True
    base = os.path.basename(n).strip("*")
    if base in PROTECTED_BASENAMES:
        return True
    if base.startswith("guard_") or base.endswith("-guard.sh"):
        return True
    if loose and base.startswith("guard"):
        return True
    if "claude/settings" in n or (".git" in n and "hooks" in n):
        return True
    if any(g in n for g in _GLOB_CHARS) and any(k in n for k in _GLOB_KEYWORDS):
        return True
    return False


def find_targets_protected(seg):
    """Does any find(1) argument aim at the enforcement layer?

    Covers the start-dir written without a trailing slash (`scripts/claude`),
    the file named via `-name`/`-path` (`guard*`, `*claude*`), and a protected
    path buried in an `-exec` payload.
    """
    for tok in seg[1:]:
        if aims_at_guard(tok, loose=True):
            return tok
    return None


# --- git analysis ----------------------------------------------------

# Reading is not publishing. These subcommands never mutate the index, a ref,
# or the remote, so a no-publish path appearing in their args is fine.
GIT_READONLY = {
    "status", "log", "show", "diff", "ls-files", "ls-tree", "cat-file",
    "rev-parse", "check-ignore", "blame", "grep", "describe", "shortlog",
    "reflog", "whatchanged", "verify-commit", "verify-tag", "for-each-ref",
    "count-objects", "symbolic-ref", "name-rev", "rev-list", "cherry",
    "merge-base", "show-ref", "var", "help", "version",
}
# Subcommands that put a path INTO the index. `git -C <no-publish-dir>` plus a
# marker-free relative path is a real smuggling route, so a no-publish `-C`
# directory here is itself the violation.
GIT_INDEX_MUTATORS = {"add", "stage", "update-index", "mv", "rm", "commit"}
# Plumbing that creates commits or moves refs — never part of JY's workflow, and
# the route the red team used to skirt the pre-commit hook. A human vets these.
GIT_REF_PLUMBING = {"commit-tree", "update-ref", "fast-import"}
# Subcommands that delete, move, or overwrite working files — they can erase or
# revert a guard file just like `rm`/`mv` (round 4: git rm/mv/checkout/restore/
# stash on a guard path). Their path args get the aims_at_guard check.
GIT_FILE_MUTATORS = {"rm", "mv", "checkout", "restore", "switch", "clean"}


def check_git(seg, raw):
    """seg[0] basename is git (or git-<subcmd>). Enforce the git policy."""
    base = os.path.basename(seg[0])
    args = seg[1:]
    subcmd = None
    cdir = None
    if base.startswith("git-") and len(base) > 4:
        subcmd = base[4:]

    i = 0
    if subcmd is None:
        # Parse the top-level option block that precedes the subcommand.
        while i < len(args):
            tok = args[i]
            if tok in GIT_GLOBAL_VALUE_OPTS:
                val = args[i + 1] if i + 1 < len(args) else ""
                if tok in GIT_WORKTREE_OPTS:
                    cdir = val          # -C / --work-tree / --git-dir relocate writes
                else:
                    check_git_config_kv(tok, val, inline=False)
                i += 2
                continue
            if tok.startswith("--") and "=" in tok:
                k, v = tok.split("=", 1)
                if k in GIT_GLOBAL_VALUE_OPTS:
                    if k in GIT_WORKTREE_OPTS:
                        cdir = v
                    else:
                        check_git_config_kv(k, v, inline=True)
                    i += 1
                    continue
            if tok.startswith("-"):
                i += 1
                continue
            subcmd = tok
            i += 1
            break

    rest = args[i:]

    # `git -C <no-publish tree> <index-mutator> <relpath>`: the marker rides in
    # the -C value, and the path arg is marker-free, so a per-token scan of
    # `rest` alone would miss it.
    if cdir and path_hits(cdir, NO_PUBLISH_MARKERS) and subcmd in GIT_INDEX_MUTATORS:
        block(
            "CLAUDE.md §1.6 — no-publish set",
            "`git -C %s %s …` stages pwn.college material via the working "
            "directory, so the path itself carries no marker." % (cdir, subcmd),
            "That tree is local-only; nothing under it may enter the index.",
        )

    if subcmd in GIT_READONLY:
        return                                  # reading never publishes
    if subcmd == "commit":
        check_git_commit(rest)
        ask(
            "CLAUDE.md §1.7 — the user owns the commit",
            "committing is JY's step, not the agent's: commits are GPG-signed "
            "with his key and split by theme, one concern per commit.",
            "Draft the thematic `git add … && git commit -S -m …` sequence and "
            "let him run it. Proceed only if he explicitly asked you to commit.",
        )
    elif subcmd == "config":
        check_git_config(rest)
    elif subcmd in ("add", "stage"):
        check_git_add(rest)
    elif subcmd == "update-index":
        check_git_update_index(rest)
    elif subcmd in GIT_REF_PLUMBING:
        block(
            "CLAUDE.md §1.2/§1.3 — plumbing bypass",
            "`git %s` builds a commit or moves a ref directly, producing an "
            "UNSIGNED commit and skipping the pre-commit secret scan that only "
            "fires on porcelain `git commit`." % subcmd,
            "This vault commits with `git commit -S`. A red-team agent used "
            "exactly this route to land an unsigned commit on main — if you "
            "genuinely need plumbing, JY runs it himself.",
        )
    elif subcmd == "push":
        check_no_verify_tokens(rest, "git push")
        check_no_publish(rest, "git push")
        ask(
            "CLAUDE.md §1.7 — the user owns the push",
            "pushing publishes to a public GitHub repo; that is JY's call.",
            "Hand him the command instead of running it.",
        )
    elif subcmd == "apply":
        # `git apply` writes files/index from a patch whose paths and body the
        # guard cannot see. Inspection variants are read-only and fine.
        if any(a in ("--stat", "--numstat", "--summary", "--check") for a in rest):
            return
        block(
            "CLAUDE.md §1.6/§1.8 — patch application",
            "`git apply` modifies files or the index from a patch whose "
            "contents the policy layer cannot inspect (paths and secrets ride "
            "inside the patch).",
            "Not part of this vault's workflow; make reviewed changes as plain "
            "edits. The index sentinel would still reject a no-publish path.",
        )
    elif subcmd == "am":
        block(
            "CLAUDE.md §1.6/§1.8 — patch application",
            "`git am` replays commits straight from an mbox, skipping the "
            "staging and secret-scan path.",
            "Not used in this vault.",
        )
    elif subcmd in GIT_FILE_MUTATORS:
        check_no_publish(rest, "git " + str(subcmd))
        for tok in rest:
            if tok == "--":
                continue
            if aims_at_guard(tok):
                block(
                    "harness integrity",
                    "`git %s` deletes, moves, or reverts a guard file (%s)."
                    % (subcmd, tok),
                    "The enforcement layer changes through the audited, "
                    "consent-gated edit path — not git file operations.",
                )
    elif subcmd in ("filter-branch", "filter-repo"):
        # rewrite the branch into new (unsigned, hook-skipping) commits; the
        # filter payloads are re-analysed like rebase --exec, then blocked.
        for i2, tok in enumerate(rest):
            if tok in ("--tree-filter", "--commit-filter", "--index-filter",
                       "--msg-filter", "--env-filter") and i2 + 1 < len(rest):
                analyse(rest[i2 + 1], depth_guard=True)
        block(
            "CLAUDE.md §1.2/§1.3 — plumbing bypass",
            "`git %s` rewrites history into commits outside the signed "
            "`git commit` path." % subcmd,
            "Not a vault operation; if genuinely needed, JY runs it himself.",
        )
    elif subcmd == "notes":
        # notes add/append/edit/copy/merge create unsigned commit objects; show/
        # list/get-ref are read-only.
        if rest and rest[0] in ("add", "append", "edit", "copy", "merge",
                                "remove", "prune"):
            block(
                "CLAUDE.md §1.3 — plumbing bypass",
                "`git notes %s` creates an unsigned commit object." % rest[0],
                "Not a vault operation.",
            )
    elif subcmd == "replace":
        # --graft/--edit/-d create/replace commit objects; --list/-l is read-only.
        if not any(a in ("--list", "-l") for a in rest):
            block(
                "CLAUDE.md §1.3 — plumbing bypass",
                "`git replace` substitutes an unsigned commit object.",
                "Not a vault operation.",
            )
    elif subcmd == "submodule":
        # `git submodule foreach '<cmd>'` runs <cmd> in each submodule — the
        # quoted payload can hide a bypass, so re-analyse it (like rebase --exec).
        for i2, tok in enumerate(rest):
            if tok == "foreach" and i2 + 1 < len(rest):
                analyse(rest[i2 + 1], depth_guard=True)
        check_no_publish(rest, "git submodule")
    elif subcmd == "stash":
        # already handled by GIT_FILE_MUTATORS above for path args; here refuse
        # `--all` / `-a` / `-u`, which sweep IGNORED files (incl. pwn.college)
        # into a stash commit that `git diff --cached` (the index sentinel) can't
        # see.
        for tok in rest:
            if tok in ("--all", "-a", "--include-untracked", "-u"):
                block(
                    "CLAUDE.md §1.6 — no-publish set",
                    "`git stash %s` sweeps ignored/untracked files — including "
                    "pwn.college material — into a stash commit invisible to "
                    "the index check." % tok,
                    "Do not stash ignored content.",
                )
        check_no_publish(rest, "git stash")
        for tok in rest:
            if tok != "--" and aims_at_guard(tok):
                block("harness integrity",
                      "`git stash` targets a guard file (%s)." % tok,
                      "Guards change through the audited edit path.")
    elif subcmd in ("merge", "cherry-pick", "revert", "rebase"):
        # every one of these can CREATE a commit, so --no-gpg-sign here produces
        # an unsigned commit just like `git commit --no-gpg-sign` (the else
        # branch below only looked for --no-verify).
        check_no_verify_tokens(rest, "git " + str(subcmd))
        for tok in rest:
            if tok.startswith("--") and "=" in tok:
                tok = tok.split("=", 1)[0]
            if is_prefix_flag(tok, "--no-gpg-sign", 6):
                block(
                    "CLAUDE.md §1.3 — GPG signing",
                    "`git %s %s` creates an UNSIGNED commit." % (subcmd, tok),
                    "Remove the flag; all vault commits are GPG-signed.",
                )
        # `git rebase --exec '<cmd>'` runs <cmd> after each commit — re-analyse it
        for i2, tok in enumerate(rest):
            if tok in ("--exec", "-x") and i2 + 1 < len(rest):
                analyse(rest[i2 + 1], depth_guard=True)
            elif tok.startswith("--exec="):
                analyse(tok.split("=", 1)[1], depth_guard=True)
    elif subcmd in ("format-patch", "bundle", "archive", "fast-export"):
        check_no_publish(rest, "git " + str(subcmd))
    elif subcmd is None:
        # `git` with only options and no subcommand: nothing to do.
        pass
    else:
        # Unknown/aliased subcommand: we cannot reason about its flags, so any
        # bypass flag present at all is treated as a violation.
        check_no_verify_tokens(rest, "git " + str(subcmd))
        check_no_publish(rest, "git " + str(subcmd))


def check_git_config_kv(key, value, inline):
    """`git -c k=v` / `--config-env=k=v` smuggling."""
    if key == "-c" or key == "--config-env":
        if "=" in value:
            k, v = value.split("=", 1)
        else:
            k, v = value, ""
        kl = k.strip().lower()
        # --config-env=key=ENVVAR reads the value from an env var whose contents
        # the guard cannot see, so a protected key is refused regardless of value.
        if key == "--config-env" and kl in ("commit.gpgsign", "core.hookspath",
                                            "tag.gpgsign"):
            block(
                "CLAUDE.md §1.2/§1.3 — config smuggling",
                "`git --config-env=%s=%s` sets a signing/hook key from an "
                "environment variable the guard cannot inspect." % (k, v),
                "Do not route signing or hook config through --config-env.",
            )
        if kl in ("commit.gpgsign", "tag.gpgsign") and is_git_falsy(v):
            block(
                "CLAUDE.md §1.3 — GPG signing",
                "`git -c %s=%s` disables signing for one command." % (k, v),
                "Every vault commit must be signed. Remove the -c override.",
            )
        if kl == "core.hookspath":
            block(
                "CLAUDE.md §1.2 — pre-commit scan",
                "`git -c core.hooksPath=%s` redirects hooks away from the "
                "secret scanner for this command." % v,
                "The pre-commit secret scan must run. Remove the -c override.",
            )
        if kl in ("gpg.program", "gpg.openpgp.program"):
            block(
                "CLAUDE.md §1.3 — GPG signing",
                "`git -c %s=%s` substitutes the signing binary." % (k, v),
                "Do not override the GPG program.",
            )
        if kl.startswith("alias."):
            block(
                "harness integrity",
                "`git -c %s=…` defines an alias whose body runs arbitrary git, "
                "which then executes below this guard's view." % k,
                "No inline aliases in this vault; run the real command directly.",
            )
        if kl in ("core.fsmonitor", "core.sshcommand", "uploadpack.packobjectshook",
                  "core.pager") and v.strip():
            # config keys whose value is executed as a command
            block(
                "harness integrity",
                "`git -c %s=%s` sets a config value git will execute." % (k, v),
                "Do not route commands through git config.",
            )


def check_git_commit(rest):
    i = 0
    while i < len(rest):
        tok = rest[i]
        if tok in COMMIT_VALUE_FLAGS:
            i += 2                      # skip the flag AND its value
            continue
        if tok.startswith("--") and "=" in tok:
            key = tok.split("=", 1)[0]
            # a fused value on a bypass flag is still the bypass flag
            if is_prefix_flag(key, "--no-verify", 6):
                block(
                    "CLAUDE.md §1.2 — pre-commit scan",
                    "`%s` skips the pre-commit secret scan." % tok,
                    "Remove it; the USER runs any confirmed-false-positive "
                    "bypass, never the agent.",
                )
            if is_prefix_flag(key, "--no-gpg-sign", 6):
                block(
                    "CLAUDE.md §1.3 — GPG signing",
                    "`%s` produces an unsigned commit." % tok,
                    "Remove the flag; all vault commits are GPG-signed.",
                )
            i += 1                      # --message=... : value is fused, safe
            continue
        if tok == "--":
            break
        if tok.startswith("--"):
            if is_prefix_flag(tok, "--no-verify", 6):
                block(
                    "CLAUDE.md §1.2 — pre-commit scan",
                    "`%s` skips the pre-commit secret scan." % tok,
                    "The scan is the last gate before a password reaches a "
                    "public repo. On a confirmed false positive the USER runs "
                    "the bypass themselves — never the agent.",
                )
            if is_prefix_flag(tok, "--no-gpg-sign", 6):
                block(
                    "CLAUDE.md §1.3 — GPG signing",
                    "`%s` produces an unsigned commit." % tok,
                    "Remove the flag; all vault commits are GPG-signed.",
                )
        elif tok.startswith("-") and len(tok) > 1:
            # bundled short options: -n, -nm, -am -> look for 'n'
            if "n" in tok[1:]:
                block(
                    "CLAUDE.md §1.2 — pre-commit scan",
                    "`%s` bundles -n (--no-verify), skipping the secret scan."
                    % tok,
                    "Drop the -n. If the scan is a confirmed false positive, "
                    "the USER runs the bypass themselves.",
                )
        i += 1


def check_git_config(rest):
    args = [a for a in rest]
    lowered = [a.lower() for a in args]

    # A read never changes anything — allow `--get`/`--list`/`--show-*`.
    # (Fixes the false positive on `git config --get core.hooksPath`.)
    READ_FLAGS = {"--get", "--get-all", "--get-regexp", "--get-urlmatch",
                  "-l", "--list", "--show-origin", "--show-scope",
                  "--name-only", "--get-color", "--get-colorbool"}
    has_edit = any(a in ("--edit", "-e") for a in lowered)
    if any(a in READ_FLAGS for a in lowered) and not has_edit:
        return

    if any(a in ("--edit", "-e") for a in lowered):
        block(
            "CLAUDE.md §1.3 — git config integrity",
            "`git config --edit` opens an interactive editor on the config "
            "that holds the signing policy.",
            "Read it with `git config --list` instead.",
        )

    for idx, a in enumerate(lowered):
        if a in ("--unset", "--unset-all", "--remove-section"):
            target = lowered[idx + 1] if idx + 1 < len(lowered) else ""
            if target.startswith(("commit.gpgsign", "user.signingkey",
                                  "tag.gpgsign", "core.hookspath", "commit",
                                  "user")):
                block(
                    "CLAUDE.md §1.3 — GPG signing",
                    "`git config %s %s` removes the signing/hook policy."
                    % (a, target),
                    "The vault's signing key and hook path must stay set.",
                )

    positional = [a for a in args if not a.startswith("-")]
    for idx, key in enumerate(positional):
        kl = key.lower()
        val = positional[idx + 1] if idx + 1 < len(positional) else None
        if kl in ("commit.gpgsign", "tag.gpgsign") and val is not None:
            if is_git_falsy(val):
                block(
                    "CLAUDE.md §1.3 — GPG signing",
                    "`git config %s %s` disables signing for the whole repo."
                    % (key, val),
                    "All vault commits are GPG-signed (key E81313B5B651B0D9).",
                )
        if kl in ("gpg.program", "gpg.openpgp.program") and val is not None:
            block(
                "CLAUDE.md §1.3 — GPG signing",
                "`git config %s %s` substitutes the signing binary, so commits "
                "carry a signature that is not the vault key." % (key, val),
                "Do not override the GPG program.",
            )
        if kl.startswith("alias.") and val is not None:
            # an alias body runs as a git subcommand later, out of the guard's
            # view — re-analyse it now (mirrors the -c alias block).
            analyse("git " + val, depth_guard=True)
        if kl == "core.hookspath" and val is not None:
            block(
                "CLAUDE.md §1.2 — pre-commit scan",
                "`git config core.hooksPath %s` points git away from the "
                "installed secret scanner." % val,
                "Leave hooksPath unset so .git/hooks/pre-commit runs.",
            )
        if kl == "user.signingkey" and val is not None and not val.strip():
            block(
                "CLAUDE.md §1.3 — GPG signing",
                "Clearing user.signingkey disables signing.",
                "Keep the vault signing key configured.",
            )


def check_git_update_index(rest):
    # `git update-index` bypasses .gitignore, and its paths can arrive via
    # stdin where a per-token scan cannot see them. It is not part of JY's
    # workflow (he stages with plain `git add`), so the smuggling forms are
    # refused outright and explicit paths still get the no-publish scan.
    for tok in rest:
        if (tok == "--stdin" or tok == "--index-info"
                or tok == "--cacheinfo"
                or tok.startswith("--pathspec-from-file")
                or tok.startswith("--cacheinfo")):
            block(
                "CLAUDE.md §1.6 — no-publish set",
                "`git update-index %s` stages content by blob/stdin, bypassing "
                ".gitignore and hiding the path from the no-publish check "
                "(a route to launder pwn.college content under a clean name)."
                % tok,
                "Stage with `git add <path>` so the no-publish check sees the "
                "path.",
            )
    check_no_publish(rest, "git update-index")


def check_git_add(rest):
    check_no_publish(rest, "git add")
    for tok in rest:
        if tok.startswith("--pathspec-from-file"):
            block(
                "CLAUDE.md §1.6 — no-publish set",
                "`git add %s` reads the file list from elsewhere, hiding the "
                "paths from the no-publish check." % tok,
                "Pass the paths explicitly: `git add <path> …`.",
            )
    for tok in rest:
        if tok == "--":
            break
        if tok == "--force" or (
            tok.startswith("-") and not tok.startswith("--") and "f" in tok[1:]
        ):
            block(
                "CLAUDE.md §1.6 — no-publish set",
                "`git add %s` force-stages a path that .gitignore excludes."
                % tok,
                "Everything .gitignore excludes here is excluded on purpose: "
                "credential files, local scratch, and pwn.college material "
                "whose platform ToS forbids public writeups. Stage the file "
                "normally or leave it local.",
            )


def check_no_verify_tokens(tokens, ctx):
    for tok in tokens:
        if is_prefix_flag(tok, "--no-verify", 6):
            block(
                "CLAUDE.md §1.2 — pre-commit scan",
                "`%s` on `%s` skips the repository's hook gate." % (tok, ctx),
                "Run the command without the bypass flag.",
            )


def check_no_publish(tokens, ctx):
    for tok in tokens:
        if path_hits(tok, NO_PUBLISH_MARKERS):
            block(
                "CLAUDE.md §1.6 — no-publish set",
                "`%s` targets pwn.college material (%s)." % (ctx, tok),
                "pwn.college prohibits public writeups; that directory is "
                "local-only and must never enter the index or the remote. "
                "Only general theory, with no challenge specifics, may be "
                "atomised into the public Concepts/.",
            )


# --- generic segment analysis ---------------------------------------

def touches_secret(token):
    """Private-key / credential path, tolerant of globs (`~/.ss[h]`, `~/.ss*`).

    Runs for EVERY command — including find and archivers — so `find ~/.ssh
    -exec cat` and `tar cf - ~/.ssh` are caught, not just `cat ~/.ssh/id_rsa`.
    """
    norm = os.path.expanduser(token).replace("\\", "/")
    stripped = re.sub(r"[\[\]{}]", "", norm)          # .ss[h] -> .ssh
    for m in SECRET_READ_MARKERS:
        if m in norm or m in stripped:
            return True
    # a glob sitting right after a secret-dir prefix: ~/.ss*  ~/.gnu*  ~/.aw*
    if re.search(r"/\.(ss|gnupg|gpg|aws|gnu|aw)[*?\[]", norm):
        return True
    return False


def check_segment(seg, raw):
    seg = strip_prefixes(seg)
    if not seg:
        return
    cmd = os.path.basename(seg[0])

    # 0a. `export`/`declare`/`typeset` NAME=val — inspect the assignment the
    #     same way a leading inline `NAME=val cmd` prefix is inspected.
    if cmd in ("export", "declare", "typeset", "local", "readonly"):
        for tok in seg[1:]:
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok):
                check_env_assignment(tok)

    # 0b. relocating no-publish CONTENT out of the tree (cp/mv/tar/… a pwn path)
    #     launders it under a publishable name; block the copy/move/archive.
    if cmd in ("cp", "mv", "rsync", "install", "tar", "gtar", "bsdtar", "cpio",
               "pax", "dd", "ln", "link", "ditto", "zip", "7z", "scp", "gcp",
               "cat", "head", "tail", "xxd", "od", "strings", "base64", "nl",
               "tac", "rev", "gzip", "bzip2", "cpio", "pv"):
        for tok in seg[1:]:
            if path_hits(tok, NO_PUBLISH_MARKERS):
                block(
                    "CLAUDE.md §1.6 — no-publish set",
                    "`%s` reads or relocates pwn.college material (%s) — that "
                    "content stays local, however it is renamed or piped."
                    % (cmd, tok),
                    "Do not relocate or extract no-publish content; it must "
                    "never leave its tree. (View it in your editor instead.)",
                )

    # 0. the operator's own private keys are never vault material — checked
    #    FIRST so it also covers find/xargs/archivers that return early below.
    for tok in seg[1:]:
        if touches_secret(tok):
            block(
                "CLAUDE.md §1.1 — credential hygiene",
                "`%s` touches private key material (%s)." % (cmd, tok),
                "Nothing in this vault requires your own keys, and anything "
                "read here can end up quoted in a note that gets published.",
            )

    # 1. xargs: the operand IS the real command -> re-check the remainder
    if cmd == "xargs":
        rest = seg[1:]
        j = 0
        while j < len(rest) and rest[j].startswith("-"):
            j += 2 if rest[j] in ("-I", "-n", "-P", "-d", "-E", "-s") else 1
        if rest[j:]:
            check_segment(rest[j:], raw)
        return

    # 2. find(1): block if it is pointed at the enforcement layer in ANY way —
    #    by start-dir, by a -name/-path pattern, or inside an -exec payload. A
    #    `find` that names a guard file is only ever a prelude to -exec/-delete
    #    or a pipe into a mutator (the red team's truncate bypass), and nothing
    #    legitimate enumerates the guard files from a shell command.
    if cmd == "find":
        hit = find_targets_protected(seg)
        if hit is not None:
            block(
                "harness integrity",
                "`find` is aimed at the enforcement layer (%s) — the next step "
                "is -exec/-delete or a pipe into a mutator." % hit,
                "Guard sources, git hooks and settings change through the "
                "audited, consent-gated edit path, never a find sweep.",
            )
        for act in ("-exec", "-execdir"):
            if act in seg:
                k = seg.index(act)
                inner = [t for t in seg[k + 1:]
                         if t not in (";", "+", "\\;", "{}")]
                if inner:
                    check_segment(inner, raw)
        return

    # 2c. archive extraction writes paths that live INSIDE the archive, unseen
    #     by the guard. An explicit -C/-d target is path-checked below; with no
    #     target the files land in the cwd (possibly the repo root) and could
    #     overwrite a guard, so extraction-to-cwd is refused (not a vault task).
    if cmd in ("tar", "gtar", "bsdtar", "cpio", "pax", "unzip", "ar", "7z",
               "7za", "7zr", "unrar", "rar"):
        joined = " ".join(seg[1:])
        listing = bool(re.search(r"(^|\s)(-?t|--list|-l|-tf|-tvf)(\s|$)",
                                 joined)) or "-t" in seg[1:]
        extracting = (
            cmd == "unzip" and not listing
            or (cmd in ("tar", "gtar", "bsdtar")
                and re.search(r"(^|\s)-?[a-z]*x", joined) and not listing)
            or (cmd == "cpio" and re.search(r"-[a-z]*i", joined))
            or (cmd == "pax" and re.search(r"(^|\s)-r(\s|$)", joined))
            or (cmd == "ar" and re.search(r"(^|\s)-?[a-z]*x", joined))
            or (cmd in ("7z", "7za", "7zr")
                and re.search(r"(^|\s)[ex](\s|$)", joined))
            or (cmd in ("unrar", "rar")
                and re.search(r"(^|\s)[ex](\s|$)", joined)))
        has_target = any(f in seg for f in ("-C", "-d", "--directory")) or \
            any(t.startswith(("-C", "-d", "--directory=")) for t in seg[1:])
        if extracting and not has_target:
            block(
                "harness integrity",
                "`%s` extracts an archive into the current directory; the "
                "member paths live inside the archive where the guard cannot "
                "see them, and could overwrite a guard file." % cmd,
                "Extraction is not a vault task. If you must, extract to an "
                "explicit directory outside the repo.",
            )

    # 3. protected enforcement paths: reading/executing is fine, rewriting is not
    if cmd in PATH_MUTATORS:
        for tok in seg[1:]:
            if aims_at_guard(tok):
                block(
                    "harness integrity",
                    "`%s` rewrites the enforcement layer itself (%s)."
                    % (cmd, tok),
                    "The guards, the pre-commit hook and .claude/settings.json "
                    "are why this vault has never leaked a password. Change "
                    "them through the audited edit path, with the user's "
                    "consent — not from the shell.",
                )

    # 3b. trap '<cmd>' SIG runs <cmd> later — re-analyse the command argument.
    if cmd == "trap":
        for tok in seg[1:]:
            if not tok.startswith("-") and tok not in (
                    "EXIT", "DEBUG", "ERR", "RETURN") and not tok.isdigit() \
                    and not re.match(r"^(SIG)?[A-Z]+$", tok):
                analyse(tok, depth_guard=True)
                break

    # 4. code wrappers: re-analyse the embedded program text
    if cmd == "eval":
        # eval joins all its arguments with spaces and executes the result, so
        # `eval rm scripts/claude/guard_bash.py` must be re-assembled — analysing
        # each token in isolation never sees the `rm <path>` command.
        analyse(" ".join(seg[1:]), depth_guard=True)
    elif cmd in SHELL_WRAPPERS:
        for idx, tok in enumerate(seg):
            # -c, or any short-flag cluster containing c (bash -lc, sh -xc)
            if (tok == "-c" or (
                    tok.startswith("-") and not tok.startswith("--")
                    and "c" in tok[1:])) and idx + 1 < len(seg):
                analyse(seg[idx + 1], depth_guard=True)
    elif cmd.lower() in INTERPRETERS:
        # scan every argument: the program may ride on -e/-c/eval or a positional
        for tok in seg[1:]:
            scan_markers_in_code(tok, cmd)
            # shell commands the interpreter shells out to — re-analyse them, so
            # `os.system("git commit -n")` / `system("rm <guard>")` are caught.
            for sh in re.findall(
                    r"(?:system|popen|exec\w*|shell_exec|passthru|"
                    r"shell[_-]command|do shell script|subprocess\.\w+)"
                    r"\s*\(?\s*\[?\s*[\"']([^\"']+)[\"']", tok, re.I):
                analyse(sh, depth_guard=True)
            for sh in re.findall(r"`([^`]+)`", tok):
                analyse(sh, depth_guard=True)
        # argv injection: the write VERB lives in the code token while the guard
        # PATH rides in a separate argv token (`python3 -c 'os.remove(sys.argv[1])'
        # <guard>`). Scan the JOINED args so marker + verb co-occur.
        scan_markers_in_code(" ".join(seg[1:]), cmd)
        # split-literal key read: `open("~/."+"ssh/id_rsa")`. Collapse string
        # concatenation and quotes, then run the secret-path check.
        joined = " ".join(seg[1:])
        canon = re.sub(r"['\"]\s*[.+]?\s*['\"]", "", joined)
        canon = canon.replace('"', " ").replace("'", " ")
        for piece in re.split(r"\s+", canon):
            if not piece:
                continue
            if touches_secret(piece):
                block(
                    "CLAUDE.md §1.1 — credential hygiene",
                    "an interpreter payload assembles a private-key path (%s)."
                    % piece,
                    "Private keys are never vault material, however the path "
                    "is spelled.",
                )
            if path_hits(piece, NO_PUBLISH_MARKERS):
                block(
                    "CLAUDE.md §1.6 — no-publish set",
                    "an interpreter payload assembles a pwn.college path (%s) "
                    "to read or relocate its content." % piece,
                    "No-publish content stays local, however the path is "
                    "spelled or split.",
                )
        # perl/ruby -i (in-place) rewrite their file operands; a bundled cluster
        # like -ni / -pi counts. Then a guard path operand is a write target.
        if cmd.lower() in ("perl", "ruby"):
            inplace = any(
                t == "-i" or (t.startswith("-") and not t.startswith("--")
                              and "i" in t[1:]) for t in seg[1:])
            if inplace:
                for tok in seg[1:]:
                    if not tok.startswith("-") and aims_at_guard(tok):
                        block(
                            "harness integrity",
                            "`%s -i` rewrites a guard file in place (%s)."
                            % (cmd, tok),
                            "Guard sources change through the audited edit "
                            "path, not an in-place interpreter edit.",
                        )

    # 5. the push helper commits AND publishes in one shot
    if cmd in ("push.sh", "push.ps1"):
        ask(
            "CLAUDE.md §1.7 — the user owns the commit",
            "scripts/push.sh stages everything, commits, and pushes to the "
            "public repo in one shot.",
            "Hand JY the command. (In practice he commits by theme instead — "
            "prefer drafting that sequence.)",
        )

    # 6. git
    if cmd == "git" or cmd.startswith("git-"):
        check_git(seg, raw)


# Signals that an interpreter payload WRITES rather than reads. A payload that
# merely mentions a guard path (e.g. `ast.parse(open(path).read())`) is fine;
# one that removes or overwrites it is not.
_CODE_WRITE = re.compile(
    # destructive / write verbs across python, ruby, node, perl, php, osascript.
    # \w* suffixes catch unlinkSync / rmSync / writeFileSync / removeSync etc.
    r"\b(remove\w*|unlink\w*|rmtree|truncate\w*|rename\w*|replace|rmdir|chmod|"
    r"chown|symlink|mkdir|makedirs|move\w*|copy\w*|delete\w*|write\w*|"
    r"put_contents|file_put_contents|writelines|shutil|set-content|out-file)\b"
    # shelling out from an interpreter (os.system, subprocess, exec, backticks…)
    r"|\b(system|popen|spawn\w*|exec\w*|subprocess|shell_exec|passthru|"
    r"proc_open)\b"
    r"|do\s+shell\s+script"
    r"|open\s*\([^)]*,\s*['\"][wax]\+?b?['\"]"   # open(path, 'w'|'a'|'x')
    r"|\brm\b|\btruncate\b|\btee\b",             # an embedded shell mutator
    re.I,
)


def scan_markers_in_code(text, lang):
    """Interpreter payloads we cannot parse: flag policy violations.

    Policy tokens (bypass flags, config keys, pwn.college) are flagged on any
    mention — they never appear in a benign read. Enforcement-layer PATHS are
    flagged only alongside a write verb, so reading a guard file from python is
    allowed while `os.remove("scripts/claude/guard_bash.py")` is blocked.
    """
    always = {
        "--no-verify": "CLAUDE.md §1.2 — pre-commit scan",
        "--no-gpg-sign": "CLAUDE.md §1.3 — GPG signing",
        "core.hookspath": "CLAUDE.md §1.2 — pre-commit scan",
        "commit.gpgsign": "CLAUDE.md §1.3 — GPG signing",
        "pwn_college": "CLAUDE.md §1.6 — no-publish set",
    }
    low = text.lower()
    for marker, rule in always.items():
        if marker in low:
            block(rule,
                  "a %s payload carries `%s`, which the shell parser cannot "
                  "verify." % (lang, marker),
                  "Run the operation as a plain shell command so the policy "
                  "layer can inspect it.")

    path_markers = [m.lower() for m in PROTECTED_PATH_MARKERS] + \
                   [b.lower() for b in PROTECTED_BASENAMES]
    if any(m in low for m in path_markers) and _CODE_WRITE.search(text):
        block("harness integrity",
              "a %s payload writes to the enforcement layer, which the shell "
              "parser cannot verify." % lang,
              "Change guard sources through the audited, consent-gated edit "
              "path, not an interpreter one-liner.")


_SUBST = re.compile(r"\$\(([^()]*)\)|`([^`]*)`")


def extract_substitutions(cmd):
    """Pull out `$(...)` / backtick command substitutions.

    Returns (inner_commands, rewritten). A substitution whose inner command is
    `echo`/`printf` is RESOLVED to its literal argument — otherwise
    `rm $(echo <guard>)` and `eval "$(echo git commit --no-verify)"` would hand
    the outer sink a benign `SUBST` placeholder and slip the real payload past
    the guard (a flaw the substitution rewrite itself introduced). Other
    substitutions keep a placeholder glued to the surrounding path so
    `rm $(git rev-parse --git-dir)/hooks/pre-commit` still resolves the marker.
    """
    inners = []

    def repl(m):
        inner = (m.group(1) if m.group(1) is not None else m.group(2)).strip()
        inners.append(inner)
        em = re.match(r"(?:echo|printf)\s+(?:-\S+\s+)*(.*)", inner)
        if em:
            # collapse the echoed/printf'd text to its literal (drop quotes)
            return em.group(1).replace('"', "").replace("'", "")
        return "SUBST"

    return inners, _SUBST.sub(repl, cmd)


_VAR_ASSIGN = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", re.S)
_VAR_REF = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?")


def resolve_vars(tokens):
    """Expand simple `NAME=literal` assignments used later as `$NAME`.

    Closes the `G=scripts/claude/guard_bash.py; rm $G` indirection, where the
    dangerous path never appears as a literal in the `rm` command. Only literal
    right-hand sides are tracked (no command substitution), which is exactly the
    smuggling case; anything fancier is left untouched.
    """
    env = {}
    # bind `for X in <values>` so `rm $X` in the body sees the real path; if any
    # value aims at the enforcement layer, that is the value worth binding.
    for idx, tok in enumerate(tokens):
        if tok == "for" and idx + 2 < len(tokens) and tokens[idx + 2] == "in":
            name = tokens[idx + 1]
            vals = []
            j = idx + 3
            while j < len(tokens) and tokens[j] not in (";", "do", "\n"):
                vals.append(tokens[j])
                j += 1
            if vals:
                pick = next((v for v in vals if aims_at_guard(v)), vals[0])
                env.setdefault(name, pick)

    out = []
    for tok in tokens:
        m = _VAR_ASSIGN.match(tok)
        if m and "$" not in m.group(2) and "`" not in m.group(2):
            env[m.group(1)] = m.group(2)
            out.append(tok)
            continue
        if "$" in tok and env:
            expanded = _VAR_REF.sub(
                lambda r: env.get(r.group(1), r.group(0)), tok)
            out.append(expanded)
        else:
            out.append(tok)
    return out


_DEPTH = [0]


def analyse(cmd_text, depth_guard=False):
    if depth_guard:
        _DEPTH[0] += 1
        if _DEPTH[0] > 6:
            return

    # word-split evasion: `$IFS` / `${IFS}` and ANSI-C `$'…\t…'` reassemble a
    # command at exec time. Normalize them to whitespace so `rm${IFS}<guard>`
    # and `$'rm\t<guard>'` tokenize into `rm` + `<guard>`.
    cmd_text = re.sub(r'"?\$\{IFS[^}]*\}"?|"?\$IFS\b"?', ' ', cmd_text)
    cmd_text = re.sub(
        r"\$'([^']*)'",
        lambda m: "'" + m.group(1).replace("\\t", " ").replace("\\n", " ")
                                  .replace("\\r", " ").replace("\\040", " ")
        + "'",
        cmd_text)

    # interpreter fed its program via a heredoc (`python3 - <<EOF … EOF`):
    # normalize_newlines would split the body into orphan segments, so scan the
    # heredoc BODY here first. Scanning only the body (not the whole command)
    # avoids false positives on surrounding shell redirections like 2>/dev/null.
    _INTERP_RE = (r"\b(python3?|perl|ruby|node|php|lua|luajit|tclsh|deno|bun|"
                  r"rscript|osascript|wish|pwsh|powershell)\b")
    if re.search(_INTERP_RE + r"[^\n]*<<", cmd_text, re.I):
        for m in re.finditer(r"<<-?\s*['\"]?(\w+)['\"]?\n(.*?)\n\1", cmd_text,
                             re.S):
            scan_markers_in_code(m.group(2), "heredoc")
    # process substitution feeding an interpreter: python3 <(echo '…code…')
    if re.search(_INTERP_RE + r"[^\n]*<\(", cmd_text, re.I):
        for m in re.finditer(r"<\((.*?)\)", cmd_text):
            scan_markers_in_code(m.group(1), "procsub")

    inner_cmds, cmd_text = extract_substitutions(cmd_text)
    for ic in inner_cmds:
        if ic.strip():
            analyse(ic, depth_guard=True)

    try:
        tokens = tokenize(cmd_text)
    except ValueError:
        # Unbalanced quotes: fall back to a coarse marker scan rather than
        # letting an unparseable command through unchecked.
        scan_markers_in_code(cmd_text, "unparseable")
        return

    tokens = resolve_vars(tokens)

    # pipe-into-shell: `... | sh`, `... | bash -s`
    for idx, tok in enumerate(tokens):
        if tok in ("|", "|&") and idx + 1 < len(tokens):
            nxt = os.path.basename(tokens[idx + 1])
            if nxt in SHELL_WRAPPERS:
                block(
                    "harness integrity",
                    "piping a generated string into `%s` executes code the "
                    "policy layer cannot inspect." % nxt,
                    "Write the command out literally instead.",
                )

    # redirection onto a protected path — regex over the raw text so it catches
    # `>guard` (no space), `2>guard`, `>|guard`, `exec 3<>guard`, and a bare
    # basename target like `>pre-commit` (via aims_at_guard, not just dir markers).
    for m in re.finditer(
            r"(?:[0-9]*>>?|[0-9]*<>|&>>?|>\|)\s*['\"]?([^\s'\";|&()<>]+)",
            cmd_text):
        tgt = m.group(1)
        if aims_at_guard(tgt):
            block(
                "harness integrity",
                "redirecting output onto `%s` overwrites the enforcement "
                "layer." % tgt,
                "Edit guard sources through the audited, consent-gated edit "
                "path.",
            )
        if touches_secret(tgt):
            block(
                "CLAUDE.md §1.1 — credential hygiene",
                "redirecting onto private-key material (%s)." % tgt,
                "Never write over or through the operator's keys.",
            )

    pipeline_flow(tokens)

    for seg in split_segments(tokens):
        check_segment(seg, cmd_text)


def pipeline_flow(tokens):
    """Follow data across a pipe: `producer | consumer`.

    - consumer is an interpreter/shell → producer's stdout is its PROGRAM
      (`echo '…os.remove…' | python3`), so scan the producer's args as code.
    - consumer is a mutator, or xargs feeding one → producer's stdout is a
      file OPERAND (`echo <guard> | xargs rm`), so check the producer's tokens
      as paths.
    """
    runs, connected, cur = [], [], []
    for tok in tokens:
        if tok in ("|", "|&"):
            runs.append(cur); connected.append(True); cur = []
        elif tok in (";", "&&", "||", "&", "\n", "(", ")", "{", "}"):
            runs.append(cur); connected.append(False); cur = []
        else:
            cur.append(tok)
    runs.append(cur)

    for k, conn in enumerate(connected):
        if not conn or k + 1 >= len(runs):
            continue
        producer = strip_prefixes(runs[k])
        consumer = strip_prefixes(runs[k + 1])
        if not producer or not consumer:
            continue
        ccmd = os.path.basename(consumer[0]).lower()

        if ccmd in INTERPRETERS or ccmd in SHELL_WRAPPERS or ccmd == "eval":
            for t in producer[1:]:
                scan_markers_in_code(t, "pipe->" + ccmd)

        target = ccmd
        if ccmd == "xargs":
            j = 1
            while j < len(consumer) and consumer[j].startswith("-"):
                j += 2 if consumer[j] in ("-I", "-n", "-P", "-d", "-E",
                                          "-s") else 1
            target = os.path.basename(consumer[j]).lower() if j < len(
                consumer) else ""
        if target in PATH_MUTATORS or target in INTERPRETERS:
            for t in producer[1:]:
                if aims_at_guard(t):
                    block(
                        "harness integrity",
                        "a guard path is piped into `%s` (%s)." % (target, t),
                        "The enforcement layer is not edited through a pipe.",
                    )
                if touches_secret(t):
                    block(
                        "CLAUDE.md §1.1 — credential hygiene",
                        "a private-key path is piped into `%s` (%s)."
                        % (target, t),
                        "Private keys are never vault material.",
                    )


def main():
    try:
        payload = sys.stdin.read()
    except Exception as exc:
        fail_open("stdin: %s" % exc)
    if not payload.strip():
        fail_open("empty stdin")
    try:
        data = json.loads(payload)
    except Exception as exc:
        fail_open("json: %s" % exc)
    if not isinstance(data, dict):
        fail_open("payload not an object")

    cmd = (data.get("tool_input") or {}).get("command") or ""
    if not isinstance(cmd, str) or not cmd.strip():
        fail_open("no command")

    try:
        analyse(cmd)
    except SystemExit:
        raise
    except Exception as exc:                        # noqa: BLE001
        fail_open("analysis error: %s" % exc)

    sys.exit(0)


if __name__ == "__main__":
    main()
