---
name: init-wargame
description: Scaffold a new wargame - folder, MOC, Level_00 note, connection details, and no-publish handling if the platform forbids public writeups. Use when JY says to init/start/scaffold a new wargame (e.g. "Leviathan 폴더 생성 및 init", "pwn.college init해줘").
argument-hint: <game-name>
---

# New Wargame Scaffold

Argument: the game name, e.g. `Leviathan`. `$ARGUMENTS`

## Step 0 — publication check (do this FIRST)

Before creating anything, establish whether the platform **permits public
writeups**. Ask JY if it is not already recorded. This decision changes every
following step, and getting it wrong retroactively is expensive — content that
should never have been public may already be pushed.

**If writeups are forbidden** (pwn.college is the standing example):
- create `Wargames/{Game}/` and an empty `Wargames/{Game}/.nopublish` marker —
  the pre-commit hook refuses to stage anything beneath a marked directory
- add `Wargames/{Game}/` to `.gitignore`
- keep the MOC **inside** the game folder as `Wargames/{Game}/MOC_{Game}.md`; it
  does **not** get an entry in the public `_MOC/`, because a public index of a
  private tree leaks the tree's shape
- add `_LOCAL_ONLY.md` stating the platform's rule and the date it was checked
- only *general* theory, stripped of challenge specifics, may later be atomised
  into the public `Concepts/`

**If writeups are permitted**: normal public layout, MOC at `_MOC/MOC_{Game}.md`.

## Steps

1. **Read first**: `_System/Vault_Structure.md`, `_Templates/Level_Template.md`,
   `_System/Frontmatter.md`.
2. Create the game folder and the MOC (location per Step 0), with an empty
   mermaid graph and metadata table ready to grow.
3. Create `Level_00.md` recording the entry point: host, **port**, starting
   username, and how to connect. The port is the detail most often wrong on a
   new game — verify it against the official page rather than assuming 22.
4. If public: add the game to the roadmap and link it from the relevant MOC.
5. Report what was created and what JY still needs to do (register an account,
   fetch the level-0 password) — do not fabricate credentials or level content.

## Hard rules

- No level solutions. Level_00 records *how to connect*, not how to win.
- Never guess the publication policy. Unverified means ask.
