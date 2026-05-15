---
moc: true
scope: Bandit
last_updated: 2026-05-15
tags: [moc, bandit, wargame]
---

# MOC — OverTheWire Bandit

> Map of Content for Bandit wargame. Navigate via mermaid graph below.
> **Rule**: This file MUST contain ZERO `[[Wiki_Links]]` outside of mermaid code blocks (graph hygiene).

## Concept Dependency Graph

```mermaid
graph TD
    L00[Level_00<br/>SSH connection]
    L01[Level_01<br/>Special filename]
    L02[Level_02<br/>Spaces in filename]
    L03[Level_03<br/>Hidden files]
    L04[Level_04<br/>Human-readable detect]
    L05[Level_05<br/>find by size/perms]
    L06[Level_06<br/>find by owner]

    L00 -->|Leads_To| L01
    L01 -->|Leads_To| L02
    L02 -->|Leads_To| L03
    L03 -->|Leads_To| L04
    L04 -->|Leads_To| L05
    L05 -->|Leads_To| L06

    L00 -.->|uses| T_SSH[Tools/ssh]
    L01 -.->|uses| T_CAT[Tools/cat]
    L02 -.->|uses| T_CAT
    L03 -.->|uses| T_LS[Tools/ls]
    L03 -.->|introduces| C_HIDDEN[Concepts/Linux/Hidden_Files]
    L04 -.->|uses| T_FILE[Tools/file]
    L05 -.->|uses| T_FIND[Tools/find]
    L06 -.->|uses| T_FIND

    click L00 "Wargames/Bandit/Level_00.md"
    click L01 "Wargames/Bandit/Level_01.md"
    click L02 "Wargames/Bandit/Level_02.md"
    click L03 "Wargames/Bandit/Level_03.md"
    click L04 "Wargames/Bandit/Level_04.md"
    click L05 "Wargames/Bandit/Level_05.md"
    click L06 "Wargames/Bandit/Level_06.md"

    style L00 fill:#2d3748,stroke:#4a5568,color:#fff
    style L03 fill:#22543d,stroke:#38a169,color:#fff
```

> Legend: solid arrow = level progression, dashed arrow = uses tool/introduces concept.
> Filled nodes = completed levels.

## Level Metadata Table

| Level | Title | Status | Difficulty | Time | Tools | New Concepts |
|---|---|---|---|---|---|---|
| 00 | SSH connection | 🔴 raw | ★☆☆ | — | ssh | — |
| 01 | Filename `-` | 🔴 raw | ★☆☆ | — | cat | special-files |
| 02 | Filename with spaces | 🔴 raw | ★☆☆ | — | cat | shell-escaping |
| 03 | Hidden file | 🔴 raw | ★☆☆ | — | ls | Hidden_Files |
| 04 | Human-readable file detect | 🔴 raw | ★☆☆ | — | file, find | File_Type_Detection |
| 05 | find by size + perms | 🔴 raw | ★★☆ | — | find | Find_Filters |
| 06 | find by owner/group | 🔴 raw | ★★☆ | — | find | Ownership_Filters |

## Status Legend
- 🔴 raw — captured but not formally written
- 🟡 developing — partial writeup, missing phases
- 🟢 solid — complete 5-phase writeup, reviewed
- ⭐ mastered — flashcard-recall verified

## Progress

```
[                              ] 0/34 levels complete
```

## Update Protocol

When a new Level note is created:
1. Add node to mermaid graph (above)
2. Add edges (Leads_To from previous, dotted edges to tools/concepts introduced)
3. Append row to metadata table
4. Update progress bar
5. `last_updated` frontmatter field
