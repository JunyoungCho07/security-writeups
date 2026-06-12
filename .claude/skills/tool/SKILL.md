---
name: tool
description: Create a 1-page command/tool reference in Tools/. Use when the user types <<Tool name>>, /tool name, or a tool is first used non-trivially in a level.
argument-hint: <tool-name>
---

# Tool 1-Pager

Argument: the tool name (lowercase, e.g. `xxd`). `$ARGUMENTS`

## Steps (in order)

1. **Read first** (lazy-load contract — do not skip):
   - `_Templates/Tool_Template.md`
   - `_System/Frontmatter.md`
2. Create `Tools/{name}.md` — filename **lowercase** (the one exception to Pascal_Snake_Case).
3. Fill frontmatter: `category`, `man_section`, `related`, `last_used` (today).
4. One page maximum. Every flag shown must be explained: what it does AND why you would reach for it.
5. Link back: add this tool to the active level note's "Tools Used" section (bidirectional).
