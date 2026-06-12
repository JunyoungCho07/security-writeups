---
doc_type: system_protocol
purpose: End-of-Learning workflow execution
load_when: User triggers <<EOL>>
companion: _System/Link_Protocol.md, _System/Commit_Convention.md
source: extracted from CLAUDE.md v1.0 §7 + §14 merged on 2026-05-19
---

# End-of-Learning (`<<EOL>>`) Protocol

## Execution Order

Execute these 6 steps in order:

1. **Concept Notes**: For every `<<Deep>>` triggered in session, verify Concept Note exists with full 15-step structure populated.
2. **Level Note**: Complete all Phase 1-5 sections, add Lessons Learned.
3. **Bidirectional Link Verification**: Scan all touched files, ensure reciprocal links present, list unresolved targets. See `_System/Link_Protocol.md`.
4. **MOC Update**: Append new nodes to `_MOC/MOC_Bandit.md` mermaid graph, update metadata table.
5. **Session Log**: Create `_Log/{YYYY-MM-DD}_session.md` with:
   - Concepts covered (with status)
   - Tools first-used
   - Struggle points
   - Forward links / next session targets
6. **Push Command Suggestion**: Output suggested commit message + push script invocation line. Reference `_System/Commit_Convention.md` for format. **DO NOT execute push from agent.**
   - macOS/Linux (Bash): `./scripts/push.sh "..."`
   - Windows (PowerShell): `.\scripts\push.ps1 "..."`

## Link Verification Output Format

```
[Link Verification]
| Source File | Link Target | Direction | Status |
|-------------|-------------|-----------|--------|
| Level_03.md | [[Hidden_Files]] | → | ✓ exists, reciprocal ✓ |
| Hidden_Files.md | [[Level_03]] | ← added | ✓ |
| Level_03.md | [[Find_Command_Mastery]] | → | ⚠ unresolved (no file yet) |
```

## Session Memory (internal tracking)

Track during session (internal scratchpad, not output unless asked). This feeds `<<EOL>>` Step 5 output.

```
SESSION_LOG:
- date: {today}
- wargame: {Bandit/Natas/...}
- levels_covered: [{Level_NN: covered_phases}]
- concepts_atomized: [{name: covered_steps_count}]
- tools_documented: [list]
- links_created: [list]
- unresolved_links: [list]
- push_pending: true/false
```
