#!/usr/bin/env python3
# =====================================================================
# guard_write.py — Claude Code PostToolUse hook
#                  (matcher: Write|Edit|MultiEdit|NotebookEdit)
#
# Two jobs, both advisory (exit 2 = warning fed back to the model; the
# write has already happened, so this layer never blocks — it corrects):
#
#   1. CREDENTIALS + IDENTIFIERS — catch an unmasked password or a personal
#      identifier the moment it lands in a note, not at commit time. The
#      rules live in secret_scan.py, shared with the git hooks, so what
#      this layer warns about is exactly what the hard gate will block.
#   2. PLACEMENT + NAMING — the vault's structure is a real convention
#      (_System/Vault_Structure.md). A misfiled note is invisible to the
#      MOC and to future search, so drift is worth catching immediately.
#
# Scope: files inside the vault only. The harness's own scratchpad and
# anything outside the repo are none of this hook's business.
#
# Input shapes read (2026-09-26 audit): Write {file_path, content},
# Edit {file_path, new_string}, MultiEdit {file_path, edits[].new_string},
# NotebookEdit {notebook_path, new_source}. Anything malformed — a
# tool_input that is a string, a file_path that is an int — exits 0:
# an advisory layer never bricks a session with a traceback.
# =====================================================================
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import secret_scan                  # the shared rule set
except Exception:
    secret_scan = None                  # advisory: no scanner, no credential check

VAULT_DIRS = {
    "Wargames", "Concepts", "Tools", "_MOC", "_Log", "_System", "_Templates",
    "scripts", ".claude", ".obsidian",
}
CONCEPT_DOMAINS = {"Linux", "Crypto", "Network", "Web", "Git", "Binary"}
ROOT_FILES = {
    "CLAUDE.md", "README.md", "COWORK_PROJECT_INSTRUCTIONS.md",
    ".gitignore", ".gitattributes", "Roadmap_Post_Bandit.md",
}

PASCAL_SNAKE = re.compile(r"^[A-Z][A-Za-z0-9]*(_[A-Z0-9][A-Za-z0-9]*)*$")
LEVEL_RE = re.compile(r"^Level_\d{2}$")
LOG_RE = re.compile(r"^\d{4}-\d{2}-\d{2}_session$")
MOC_RE = re.compile(r"^MOC_[A-Z][A-Za-z0-9_]*$")
LOWER_TOOL = re.compile(r"^[a-z0-9][a-z0-9_.-]*$")

notes = []


def warn(msg):
    notes.append(msg)


def repo_root(data):
    root = os.environ.get("CLAUDE_PROJECT_DIR")
    if root:
        return os.path.realpath(root)
    cwd = data.get("cwd")
    if not isinstance(cwd, str) or not cwd:
        cwd = os.getcwd()
    cur = os.path.realpath(cwd)
    while cur != "/":
        if os.path.isdir(os.path.join(cur, ".git")):
            return cur
        cur = os.path.dirname(cur)
    return os.path.realpath(cwd)


def extract_content(ti):
    """Every piece of text the tool wrote, whatever the tool's shape."""
    parts = []
    for key in ("content", "new_string", "new_source"):
        v = ti.get(key)
        if isinstance(v, str):
            parts.append(v)
    edits = ti.get("edits")
    if isinstance(edits, list):
        for e in edits:
            if isinstance(e, dict) and isinstance(e.get("new_string"), str):
                parts.append(e["new_string"])
    return "\n".join(parts)


def check_credentials(content, rel, identifiers):
    if secret_scan is None:
        return
    hits = secret_scan.scan_text(secret_scan.normalise(content), binary=False,
                                 identifiers=identifiers)
    if not hits:
        return
    lineno, rule, prev = hits[0]
    more = " (+%d more)" % (len(hits) - 1) if len(hits) > 1 else ""
    if rule == "identifier":
        warn(
            "PERSONAL IDENTIFIER in %s line %d: %s%s.\n"
            "   Committed files carry the GitHub handle and nothing else "
            "(CLAUDE.md §1.5) — remove it NOW; the pre-commit hook will refuse it."
            % (rel, lineno, prev, more)
        )
    else:
        warn(
            "possible UNMASKED CREDENTIAL in %s line %d [%s]: %s%s.\n"
            "   If it is a real password, replace it with "
            "'<password masked>' NOW — this repo is public (CLAUDE.md §1.1)."
            % (rel, lineno, rule, prev, more)
        )


def check_placement(rel):
    parts = rel.split(os.sep)
    top = parts[0]

    if len(parts) == 1:
        if rel not in ROOT_FILES:
            warn(
                "`%s` was written to the vault ROOT. The root holds only %s.\n"
                "   Put notes under an existing top-level dir, or add the new "
                "folder to _System/Vault_Structure.md first — an undocumented "
                "folder is one nobody will look in again."
                % (rel, ", ".join(sorted(ROOT_FILES)))
            )
        return

    if top not in VAULT_DIRS:
        warn(
            "`%s` creates a new top-level folder `%s/`. Allowed: %s.\n"
            "   A new top-level folder needs a line in "
            "_System/Vault_Structure.md saying what belongs in it and what "
            "does not — otherwise it silently becomes a junk drawer."
            % (rel, top, ", ".join(sorted(VAULT_DIRS)))
        )
        return

    name = os.path.basename(rel)
    stem, ext = os.path.splitext(name)

    if " " in name:
        warn("`%s` contains a space. Vault filenames are "
             "English_Pascal_Snake_Case with no spaces (CLAUDE.md §3)." % rel)
        return

    if ext != ".md":
        return                      # scripts, configs, markers: not our business

    if top == "Wargames":
        if stem.startswith("_") or MOC_RE.match(stem):
            return                  # _LOCAL_ONLY.md marker, per-game MOC
        if len(parts) == 2:
            warn(
                "`%s` sits directly in Wargames/. Level notes live in a game "
                "folder: Wargames/{Game}/Level_NN.md (CLAUDE.md §2)." % rel
            )
            return
        if not LEVEL_RE.match(stem):
            warn(
                "`%s` should be `Level_NN.md` with a TWO-DIGIT number "
                "(Level_03.md, not Level_3.md) so the notes sort correctly "
                "in the file listing (CLAUDE.md §3)." % rel
            )
    elif top == "Concepts":
        if len(parts) < 3:
            warn("`%s` sits directly in Concepts/. Concepts live in a domain: "
                 "Concepts/{%s}/." % (rel, "|".join(sorted(CONCEPT_DOMAINS))))
            return
        if parts[1] not in CONCEPT_DOMAINS:
            warn(
                "`%s` uses an unrecognised concept domain `%s`. Known: %s.\n"
                "   Adding a domain is a real decision — record it in "
                "_System/Vault_Structure.md so the MOC and future notes agree."
                % (rel, parts[1], ", ".join(sorted(CONCEPT_DOMAINS)))
            )
        if not PASCAL_SNAKE.match(stem):
            warn("`%s` should be English_Pascal_Snake_Case.md, e.g. "
                 "File_Signatures.md (CLAUDE.md §3)." % rel)
    elif top == "Tools":
        if not LOWER_TOOL.match(stem):
            warn("`%s` should be lowercase — tool notes are named after the "
                 "binary (xxd.md, not Xxd.md). CLAUDE.md §3." % rel)
    elif top == "_MOC":
        if not MOC_RE.match(stem):
            warn("`%s` should be MOC_{Scope}.md (CLAUDE.md §3)." % rel)
    elif top == "_Log":
        if stem.startswith("_"):
            return                  # _Parking_Lot.md and friends
        if not LOG_RE.match(stem):
            warn("`%s` should be YYYY-MM-DD_session.md so logs sort "
                 "chronologically (CLAUDE.md §3)." % rel)
    elif top in ("_System", "_Templates"):
        if not PASCAL_SNAKE.match(stem):
            warn("`%s` should be English_Pascal_Snake_Case.md." % rel)


def main():
    try:
        data = json.loads(sys.stdin.read() or "{}")
        if not isinstance(data, dict):
            return 0

        ti = data.get("tool_input")
        if not isinstance(ti, dict):
            return 0
        path = ti.get("file_path") or ti.get("notebook_path")
        if not isinstance(path, str) or not path:
            return 0
        content = extract_content(ti)

        root = repo_root(data)
        real = os.path.realpath(path)
        if not real.startswith(root + os.sep):
            return 0                # outside the vault: not policed
        rel = os.path.relpath(real, root)
        if rel.split(os.sep)[0] in (".git",):
            return 0

        identifiers = ()
        if secret_scan is not None:
            try:
                identifiers = secret_scan.load_identifiers(root)
            except Exception:
                identifiers = ()
        if content.strip():
            check_credentials(content, rel, identifiers)
        check_placement(rel)
    except Exception:
        return 0                    # advisory layer: never brick a session

    if notes:
        sys.stderr.write("⚠ write-guard:\n" + "\n".join(" • " + n for n in notes)
                         + "\n")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
