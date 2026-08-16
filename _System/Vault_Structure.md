---
doc_type: system_protocol
purpose: Where every kind of knowledge lives, when a folder may be created, and how the vault is pruned
load_when: Creating any file, creating any folder, writing agent memory, or running /eol
companion: _System/EOL_Protocol.md, _System/Link_Protocol.md, _System/Frontmatter.md
enforced_by: scripts/claude/guard_write.py (placement + naming, advisory)
source: written 2026-08-16 during the v4 harness rebuild
---

# Vault Structure & Memory Protocol

Four stores exist. They are not interchangeable, and the most common mistake is
writing the right content into the wrong one.

## [1] The four stores

| Store | Location | Holds | Lifetime |
|---|---|---|---|
| **Vault notes** | `Wargames/`, `Concepts/`, `Tools/`, `_MOC/` | Knowledge that stays true after the session ends | Permanent, public |
| **Session log** | `_Log/YYYY-MM-DD_session.md` | What happened, in order: struggle points, what broke, what to hit next | Permanent, append-only in spirit |
| **Parking lot** | `_Log/_Parking_Lot.md` | Questions raised mid-session that deserve a note but would derail the current thread | Transient — **drained empty at every `/eol`** |
| **Agent memory** | `~/.claude/projects/-Users-jycho-Developer-security-writeups/memory/` | Facts about *how to work with JY* — not vault content | Cross-session, private, never committed |

> [!warning] The dividing line
> Vault = what I learned. Agent memory = how to teach me.
> A fact about `setuid` is a vault note. "JY solves levels himself, never give
> the answer" is agent memory. Neither belongs in the other, and duplicating a
> fact into both means the two copies drift.

## [2] Routing: where does this go?

Ask in order; take the first match.

1. Is it a **credential, a flag, or a level answer**? → **nowhere**. Mask it.
   This applies to all four stores including agent memory.
2. Is it **local-only material** (pwn.college and anything under a `.nopublish`
   marker)? → the game's local tree only. Never `Concepts/`, never the log,
   never a commit. Only *general* theory — stripped of challenge specifics —
   may be atomised into the public `Concepts/`.
3. Does it describe **a level I solved**? → `Wargames/{Game}/Level_NN.md`.
4. Is it **a concept I genuinely dug into** — a real Q&A thread or a multi-step
   exploration, not a passing mention? → `Concepts/{domain}/{Topic_Name}.md`.
   Lite tier is the default; a full 15-step atom is earned, not assumed.
5. Is it **a command or binary I used non-trivially**? → `Tools/{name}.md`.
6. Is it **how the session went**? → `_Log/{date}_session.md`.
7. Is it **a question I want answered later**? → `_Log/_Parking_Lot.md`.
8. Is it **a durable fact about JY, his preferences, or a standing correction**?
   → agent memory (see §5).
9. Is it **a rule the agent must follow**? → `CLAUDE.md` or `_System/`, never a
   note. Rules are not knowledge; mixing them makes both unreadable.

## [3] When a new folder may be created

A folder is a promise that more things like this are coming. Creating one for a
single file is how a vault turns into a junk drawer.

**All three must hold:**
1. At least **three** files of that kind are expected, and one already exists.
2. The category is **not** expressible as a domain inside an existing folder.
3. The folder is **named in this document first**, in the same change.

**Then update, in the same commit:**
- this file (the tree in §4),
- `scripts/claude/guard_write.py` (`VAULT_DIRS` / `CONCEPT_DOMAINS`) — otherwise
  the write-guard will flag every file you put there,
- the relevant `_MOC/` entry.

New **concept domain** (a subfolder of `Concepts/`) follows the same rule.
Current domains: `Linux`, `Network`, `Crypto`, `Web`, `Git`, `Binary`.
`Crypto` and `Web` are declared but still empty — that is intentional headroom,
not drift.

**Never create:** a folder for one note, a dated folder (the filename carries the
date), a `misc/`, `tmp/`, or `notes/` folder, or a second folder that overlaps an
existing one. Temporary working files belong in the harness scratchpad, outside
the vault entirely.

## [4] Canonical tree

```
security-writeups/
├── CLAUDE.md                    ← agent contract (rules, not knowledge)
├── README.md, Roadmap_Post_Bandit.md
├── .claude/{settings.json, skills/}
├── _System/                     ← protocols the agent loads on demand
├── _Templates/                  ← note skeletons
├── _MOC/MOC_{Scope}.md          ← one map per wargame/scope
├── _Log/{YYYY-MM-DD}_session.md, _Parking_Lot.md
├── Wargames/{Game}/Level_NN.md  ← 2-digit, always
├── Concepts/{Domain}/{Topic_Name}.md
├── Tools/{name}.md              ← lowercase, named after the binary
└── scripts/                     ← setup, push helper, guards, tests
```

**Exception — no-publish trees.** A game whose platform forbids public writeups
(currently `Wargames/Pwn_College/`) keeps *everything* inside its own folder,
including its MOC (`MOC_Pwn_College.md`) and an `_LOCAL_ONLY.md` marker. It does
**not** get an entry in the public `_MOC/`. This is deliberate: a public MOC that
indexes a private tree leaks the tree's shape. Mark such a folder with an empty
`.nopublish` file — the pre-commit hook refuses to stage anything beneath it.

## [5] Agent memory policy

Location: `~/.claude/projects/-Users-jycho-Developer-security-writeups/memory/`
One fact per file, plus a one-line pointer in `MEMORY.md`.

**Earns a memory file:**
- a standing correction JY gave, with the reason ("explain every flag — what
  *and* why", "rebuild from zero, assume no C")
- a durable preference about how work is delivered
- a project-level constraint not derivable from the repo (a platform's
  publication ban, the chosen next target and why)
- a pointer to an external resource that will be needed again

**Never goes there:**
- passwords, flags, or level solutions — the same masking rule as the vault
- anything the repo already records: file structure, past fixes, git history,
  or the contents of `CLAUDE.md`
- state that matters only inside the current session — that is the parking lot's
  job, and it gets drained at `/eol`

**Maintenance:** before writing, check whether an existing file already covers
it and update that one instead of creating a near-duplicate. Delete memories
that turn out to be wrong; a stale memory is worse than a missing one because it
is asserted with the same confidence. A memory naming a file or flag is a claim
about the repo — verify it still exists before acting on it.

## [6] Pruning cadence

Run at `/eol`, in this order:

1. **Drain the parking lot.** Every entry becomes a lite concept note, a
   forward-link line in the session log, or is deleted as answered. The file
   ends the session empty. Nothing is silently dropped.
2. **Promote.** A lite note the session revisited a third time is a candidate
   for a full 15-step atom (`/deep`). Note the candidacy in the log; do not
   promote unasked.
3. **Merge.** Two notes that always appear together and neither of which stands
   alone should be one note. Merging is a real edit: fix every inbound `[[link]]`
   in the same pass.
4. **Sweep links.** Unresolved `[[targets]]` are *reported*, never silently
   dropped — an unresolved link is a to-do, and deleting it destroys the to-do.
5. **Leave the logs alone.** Session logs are never pruned, merged, or tidied.
   They are the only record of what the learning actually felt like, and their
   value is precisely that they were written before anyone knew how it turned
   out.
