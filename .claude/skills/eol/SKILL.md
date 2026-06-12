---
name: eol
description: Run the End-of-Learning protocol — verify bidirectional links, update MOC, write the session log, and draft the push command. Use when the user types <<EOL>> or /eol at the end of a study session.
---

# End-of-Learning Protocol

## Steps (in order)

1. **Read first** (lazy-load contract — do not skip):
   - `_System/EOL_Protocol.md` (the 6-step execution order — follow it exactly)
   - `_System/Link_Protocol.md` (link verification rules)
2. Execute all 6 EOL steps in order: concept-note completeness → level-note completeness → bidirectional link verification (output the table format from the protocol) → MOC update → session log `_Log/{YYYY-MM-DD}_session.md` → push suggestion.
3. For the push suggestion, read `_System/Commit_Convention.md` and output the macOS command line: `./scripts/push.sh "type(scope): message"`. **DO NOT execute the push.**

## Hard rules

- Use `git status` / `git diff` to enumerate touched files — do not rely on conversation memory alone.
- Unresolved `[[links]]` are reported, not silently dropped.
- The session log records struggle points honestly; it feeds the next session's context.
