---
name: level
description: Write up a wargame level (Wargames/{Game}/Level_NN.md) — Bandit, Leviathan, Natas, or any other. Fires when JY pastes raw terminal output from a level he has solved, or types /level N or <<Bandit N>>. Paste-driven: the paste IS the trigger.
argument-hint: "[game] <level-number>"
---

# Wargame Level Writeup

Argument (optional): game and level, e.g. `bandit 13` or just `13`. `$ARGUMENTS`

**The usual entry point is not this argument.** JY solves levels in his own
terminal and pastes the session. A raw paste with no trigger word means:
auto-populate the Solution section of the active level note.

## Steps (in order)

1. **Read first** (lazy-load contract — do not skip):
   - `_Templates/Level_Template.md`
   - `_System/Frontmatter.md`
2. Create or open `Wargames/{Game}/Level_NN.md` — filename uses a **2-digit**
   level (`Level_03.md`); frontmatter `level:` uses the integer with no leading
   zero. Infer `{Game}` from context; ask only if genuinely ambiguous.
3. Populate frontmatter from the schema: today's date, `wargame:`, `title:`,
   `status: 🔴 raw`, empty lists as `[]` — never omit keys.
4. Fill Phase 1 (Goal) from the level description. Leave Solution **empty** until
   he pastes.
5. On a paste: reconstruct what he did, command by command.

## Hard rules

- **He solves it. You do not.** *"내가 풀거야. 절대 풀이나 답을 알려주지마."*
  Before he has solved a level, give building blocks and the *why* — never the
  walkthrough, never the answer, never the next command in sequence. After he
  has solved it, write up what *he* did.
- Passwords are `<password masked>` or `[REDACTED]` — including in intermediate
  drafts. This repo is public.
- **Every flag gets explained: what it does AND why it is needed here.** That
  includes flags in the Phase 4 alternatives. `%s`, `2>&1`, `+x`, a `stat`
  format string — if it appears, it is explained.
- Explain from zero. No C background is assumed. When a mechanism is unfamiliar,
  rebuild it from first principles with a runnable demo rather than analogy.
- When he restates his own mental model to check it, validate or correct **the
  exact bit that is wrong** — not the whole chain.
- Phase 4 (Better Methods) is mandatory before the note can reach `🟢 solid`.
- A concept he genuinely dug into during the level gets parked in
  `_Log/_Parking_Lot.md` for `/eol` to turn into a note.

For a game whose platform forbids public writeups, see
`_System/Vault_Structure.md` §4 before writing anything.
