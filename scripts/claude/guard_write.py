#!/usr/bin/env python3
# =====================================================================
# guard_write.py — Claude Code PostToolUse hook (matcher: Write|Edit)
#
# Two jobs, both advisory (exit 2 = warning fed back to the model; the
# write has already happened, so this layer never blocks — it corrects):
#
#   1. CREDENTIALS — catch an unmasked password the moment it lands in a
#      note, not at commit time. The git pre-commit hook is the hard gate;
#      this is the fast one.
#   2. PLACEMENT + NAMING — the vault's structure is a real convention
#      (_System/Vault_Structure.md). A misfiled note is invisible to the
#      MOC and to future search, so drift is worth catching immediately.
#
# Scope: files inside the vault only. The harness's own scratchpad and
# anything outside the repo are none of this hook's business.
# =====================================================================
import json
import os
import re
import sys

VAULT_DIRS = {
    "Wargames", "Concepts", "Tools", "_MOC", "_Log", "_System", "_Templates",
    "scripts", ".claude", ".obsidian",
}
CONCEPT_DOMAINS = {"Linux", "Crypto", "Network", "Web", "Git", "Binary"}
ROOT_FILES = {
    "CLAUDE.md", "README.md", "COWORK_PROJECT_INSTRUCTIONS.md",
    ".gitignore", "Roadmap_Post_Bandit.md",
}

PASCAL_SNAKE = re.compile(r"^[A-Z][A-Za-z0-9]*(_[A-Z0-9][A-Za-z0-9]*)*$")
LEVEL_RE = re.compile(r"^Level_\d{2}$")
LOG_RE = re.compile(r"^\d{4}-\d{2}-\d{2}_session$")
MOC_RE = re.compile(r"^MOC_[A-Z][A-Za-z0-9_]*$")
LOWER_TOOL = re.compile(r"^[a-z0-9][a-z0-9_.-]*$")

SAFE_HEX = re.compile(
    r"^(?:[0-9a-fA-F]{32}|[0-9a-fA-F]{40}|[0-9a-fA-F]{56}"
    r"|[0-9a-fA-F]{64}|[0-9a-fA-F]{96}|[0-9a-fA-F]{128})$"
)
WHITELIST_LINE = re.compile(
    r"(masked|redacted|example|placeholder|fingerprint|sha-?(1|224|256|384|512)"
    r"|md5|checksum|digest|uuid|public\s+key|key\s+id|ssh-ed25519|ssh-rsa|<[^>]*>)",
    re.I,
)
TOKEN = re.compile(r"[a-zA-Z0-9]{30,}")

notes = []


def warn(msg):
    notes.append(msg)


def repo_root(data):
    root = os.environ.get("CLAUDE_PROJECT_DIR")
    if root:
        return os.path.realpath(root)
    cwd = data.get("cwd") or os.getcwd()
    cur = os.path.realpath(cwd)
    while cur != "/":
        if os.path.isdir(os.path.join(cur, ".git")):
            return cur
        cur = os.path.dirname(cur)
    return os.path.realpath(cwd)


def check_credentials(content, rel):
    for i, line in enumerate(content.splitlines(), start=1):
        if WHITELIST_LINE.search(line):
            continue
        for tok in TOKEN.findall(line):
            if SAFE_HEX.match(tok) or tok.startswith(("AAAAB3Nza", "AAAAC3Nza")):
                continue
            warn(
                "possible UNMASKED CREDENTIAL in %s line %d: %s…(%d chars).\n"
                "   If it is a real password, replace it with "
                "'<password masked>' NOW — this repo is public (CLAUDE.md §1.1)."
                % (rel, i, tok[:12], len(tok))
            )
            return


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
        if len(parts) < 3:
            return
        if stem.startswith("_") or MOC_RE.match(stem):
            return                  # _LOCAL_ONLY.md marker, per-game MOC
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
    except Exception:
        sys.exit(0)
    if not isinstance(data, dict):
        sys.exit(0)

    ti = data.get("tool_input") or {}
    path = ti.get("file_path") or ""
    content = ti.get("content") or ti.get("new_string") or ""
    if not path:
        sys.exit(0)

    root = repo_root(data)
    real = os.path.realpath(path)
    if not real.startswith(root + os.sep):
        sys.exit(0)                 # outside the vault: not policed
    rel = os.path.relpath(real, root)
    if rel.split(os.sep)[0] in (".git",):
        sys.exit(0)

    try:
        if isinstance(content, str) and content.strip():
            check_credentials(content, rel)
        check_placement(rel)
    except Exception:
        sys.exit(0)                 # advisory layer: never brick a session

    if notes:
        sys.stderr.write("⚠ write-guard:\n" + "\n".join(" • " + n for n in notes)
                         + "\n")
        sys.exit(2)
    sys.exit(0)


if __name__ == "__main__":
    main()
