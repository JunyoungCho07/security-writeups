---
name: bandit
description: Create a new OverTheWire Bandit level writeup note (Wargames/Bandit/Level_NN.md). Use when the user types <<Bandit N>>, /bandit N, or asks to start a new Bandit level.
argument-hint: <level-number>
---

# Bandit Level Writeup Bootstrap

Argument: the Bandit level number N (e.g. `13`). `$ARGUMENTS`

## Steps (in order)

1. **Read first** (lazy-load contract — do not skip):
   - `_Templates/Level_Template.md`
   - `_System/Frontmatter.md`
2. Create `Wargames/Bandit/Level_NN.md` — filename uses **2-digit** level (`Level_03.md`), frontmatter `level:` uses the **integer without leading zero**.
3. Populate frontmatter from the schema: today's date, `wargame: Bandit`, `title: "Bandit Level N → N+1"`, `status: 🔴 raw`, empty lists as `[]` (never omit keys).
4. Fill [Phase 1] Goal from the official level page description if known; leave Solution **empty**.
5. **Stand by for terminal output.** Do NOT fabricate shell output, do NOT guess commands the user has not run, do NOT write a solution before the user pastes their session.

## Hard rules

- Passwords are NEVER written in plaintext — `<password masked>` or `[REDACTED]` only, including in intermediate drafts (write-guard hook will flag violations).
- Respect OverTheWire ToS: teach the technique, never hand over the answer.
- Phase 4 (Better Methods) is mandatory before the note can reach `🟢 solid` — every flag in every command (including alternatives) must be explained: what it does AND why it is needed here.
- When the user later pastes terminal output with no trigger, auto-populate the Solution section of this (most recent active) level note.

For other wargames (`<<Natas N>>` etc.) follow the identical procedure under `Wargames/{Game}/`.
