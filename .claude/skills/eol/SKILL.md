---
name: eol
description: End-of-Learning protocol — drain the parking lot into notes, verify bidirectional links, update the MOC, write the session log, and draft the commit plan. Use when JY types /eol or <<EOL>>, or says it in Korean - "세션 종료", "세션 마감", "기록하고 세션 마감", "메모리 업데이트 후 세션 종료", "오늘 여기까지".
---

# End-of-Learning Protocol

This is the most-used skill in the vault. It is what turns a session of
terminal output into knowledge that survives it.

## Steps (in order)

1. **Read first** (lazy-load contract — do not skip):
   - `_System/EOL_Protocol.md` — the execution order; follow it exactly
   - `_System/Link_Protocol.md` — link verification rules
   - `_System/Vault_Structure.md` — routing, and the pruning cadence in §6
2. **Drain `_Log/_Parking_Lot.md` first.** Every parked question becomes a lite
   concept note, a forward-link in the session log, or is deleted as answered.
   The file ends the session empty. This runs *before* the other steps because
   it creates notes the link verification then has to check.
3. Execute the protocol's steps in order: concept-note completeness → level-note
   completeness → bidirectional link verification (output the table format) →
   MOC update → session log `_Log/{YYYY-MM-DD}_session.md`.
4. **Lite notes.** Every concept he *substantively explored* this session earns a
   note, even without `/deep` — a real Q&A thread or a multi-step exploration,
   not a passing mention. `_Templates/Concept_Lite_Template.md`,
   `note_tier: lite`. This is policy, not a judgement call.
5. Update agent memory if — and only if — the session produced a durable fact
   about how to work with him. `_System/Vault_Structure.md` §5 says what earns a
   memory file and what must never go in one.
6. Finish by invoking `/commit` for the thematic commit plan. **Do not commit.**

## Hard rules

- Use `git status` / `git diff` to enumerate touched files — never conversation
  memory alone.
- Unresolved `[[links]]` are reported, never silently dropped. An unresolved link
  is a to-do; deleting it destroys the to-do.
- The session log records struggle points **honestly**. It feeds the next
  session's context, and a log that only records successes is worthless for
  that.
- Session logs are never pruned or tidied afterwards.
- No passwords anywhere in the output, including the log.
