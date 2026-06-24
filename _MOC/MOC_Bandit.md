---
moc: true
scope: Bandit
last_updated: 2026-06-24
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
    L07[Level_07<br/>grep pattern match]
    L08[Level_08<br/>sort+uniq dedup]
    L09[Level_09<br/>strings extraction]
    L10[Level_10<br/>base64 decode]
    L11[Level_11<br/>ROT13 / tr]
    L12[Level_12<br/>repeated decompression]
    L13[Level_13<br/>SSH key auth]

    L00 -->|Leads_To| L01
    L01 -->|Leads_To| L02
    L02 -->|Leads_To| L03
    L03 -->|Leads_To| L04
    L04 -->|Leads_To| L05
    L05 -->|Leads_To| L06
    L06 -->|Leads_To| L07
    L07 -->|Leads_To| L08
    L08 -->|Leads_To| L09
    L09 -->|Leads_To| L10
    L10 -->|Leads_To| L11
    L11 -->|Leads_To| L12
    L12 -->|Leads_To| L13

    L00 -.->|uses| T_SSH[Tools/ssh]
    L01 -.->|uses| T_CAT[Tools/cat]
    L01 -.->|introduces| C_DASH[Concepts/Linux/Dashed_Filename]
    L02 -.->|uses| T_CAT
    L02 -.->|introduces| C_QUOTE[Concepts/Linux/Shell_Quoting]
    L02 -.->|introduces| C_OPT[Concepts/Linux/Option_Flag_Collision]
    L03 -.->|uses| T_LS[Tools/ls]
    L03 -.->|introduces| C_HIDDEN[Concepts/Linux/Hidden_Files]
    L04 -.->|uses| T_FILE[Tools/file]
    L05 -.->|uses| T_FIND[Tools/find]
    L06 -.->|uses| T_FIND
    L07 -.->|uses| T_GREP[Tools/grep]
    L07 -.->|introduces| C_REGEX[Concepts/Linux/Regex_Flavors]
    L08 -.->|uses| T_SORT[Tools/sort]
    L08 -.->|uses| T_UNIQ[Tools/uniq]
    L08 -.->|introduces| C_DEDUP[Concepts/Linux/Stream_Deduplication]
    L09 -.->|uses| T_STRINGS[Tools/strings]
    L09 -.->|uses| T_GREP
    L09 -.->|introduces| C_STRINGS[Concepts/Linux/Strings_Extraction]
    L10 -.->|uses| T_B64[Tools/base64]
    L10 -.->|introduces| C_B64[Concepts/Linux/Base64_Encoding]
    L11 -.->|uses| T_TR[Tools/tr]
    L11 -.->|introduces| C_ROT13[Concepts/Crypto/ROT13_Cipher]
    L12 -.->|uses| T_XXD[Tools/xxd]
    L12 -.->|uses| T_FILE
    L12 -.->|uses| T_GZIP[Tools/gzip]
    L12 -.->|uses| T_BZIP2[Tools/bzip2]
    L12 -.->|uses| T_TAR[Tools/tar]
    L12 -.->|introduces| C_SIG[Concepts/Linux/File_Signatures]
    L12 -.->|introduces| C_HEXREV[Concepts/Linux/Hexdump_Reversal]
    L13 -.->|uses| T_SSH
    L13 -.->|uses| T_SCP[Tools/scp]
    L13 -.->|uses| T_CHMOD[Tools/chmod]
    L13 -.->|introduces| C_SSHKEY[Concepts/Network/SSH_Key_Authentication]
    L13 -.->|introduces| C_FILEPERM[Concepts/Linux/File_Permissions]
    L13 -.->|uses| C_EXITCODE
    C_SSHKEY -.->|requires| C_FILEPERM
    C_STRINGS -.->|related| C_REGEX
    C_STRINGS -.->|confer| C_B64
    C_SIG -.->|related| C_HEXREV
    C_SIG -.->|seeded by| T_FILE
    L04 -.->|seeds| C_SIG

    %% Foundational concepts (general-purpose, not tied to single level)
    C_SUBSHELL[Concepts/Linux/Subshell]
    C_EXITCODE[Concepts/Linux/Exit_Code]
    T_FIND -.->|implements| C_SUBSHELL
    T_FIND -.->|implements| C_EXITCODE
    L06 -.->|uses| C_EXITCODE

    click L00 "Wargames/Bandit/Level_00.md"
    click L01 "Wargames/Bandit/Level_01.md"
    click L02 "Wargames/Bandit/Level_02.md"
    click L03 "Wargames/Bandit/Level_03.md"
    click L04 "Wargames/Bandit/Level_04.md"
    click L05 "Wargames/Bandit/Level_05.md"
    click L06 "Wargames/Bandit/Level_06.md"
    click L07 "Wargames/Bandit/Level_07.md"
    click L08 "Wargames/Bandit/Level_08.md"
    click L09 "Wargames/Bandit/Level_09.md"
    click L10 "Wargames/Bandit/Level_10.md"
    click L11 "Wargames/Bandit/Level_11.md"
    click L12 "Wargames/Bandit/Level_12.md"
    click L13 "Wargames/Bandit/Level_13.md"

    %% Filled = 🟢 solid; outlined = 🟡 developing / 🔴 raw
    style L00 fill:#22543d,stroke:#38a169,color:#fff
    style L01 fill:#22543d,stroke:#38a169,color:#fff
    style L02 fill:#22543d,stroke:#38a169,color:#fff
    style L03 fill:#22543d,stroke:#38a169,color:#fff
    style L08 fill:#22543d,stroke:#38a169,color:#fff
    style L09 stroke:#d69e2e,stroke-width:2px
    style L10 stroke:#d69e2e,stroke-width:2px
    style L11 stroke:#d69e2e,stroke-width:2px
    style L12 stroke:#d69e2e,stroke-width:2px
    style L13 stroke:#d69e2e,stroke-width:2px
```

> Legend: solid arrow = level progression, dashed arrow = uses tool/introduces concept.
> Filled nodes = completed levels.

## Level Metadata Table

| Level | Title | Status | Difficulty | Time | Tools | New Concepts |
|---|---|---|---|---|---|---|
| 00 | SSH connection | 🟢 solid | ★☆☆ | 5min | ssh, cat, ls | SSH_Protocol |
| 01 | Filename `-` | 🟢 solid | ★☆☆ | 15min | cat, ls | Dashed_Filename |
| 02 | Filename `--spaces--` | 🟢 solid | ★☆☆ | 5min | cat, ls | Shell_Quoting, Option_Flag_Collision |
| 03 | Hidden file (`...`) | 🟢 solid | ★☆☆ | 5min | ls, cat | Hidden_Files |
| 04 | Human-readable file detect | 🔴 raw | ★☆☆ | — | file, find | File_Type_Detection |
| 05 | find by size + perms | 🔴 raw | ★★☆ | — | find | Find_Filters |
| 06 | find by owner/group | 🔴 raw | ★★☆ | — | find | Ownership_Filters |
| 07 | grep pattern match | 🔴 raw | ★☆☆ | 5min | grep | Regex_Flavors / Grep_Pattern_Matching |
| 08 | sort + uniq dedup | 🟢 solid | ★☆☆ | 5min | sort, uniq | Stream_Deduplication |
| 09 | strings extraction | 🟡 developing | ★☆☆ | 8min | strings, grep, xxd | Strings_Extraction |
| 10 | base64 decode | 🟡 developing | ★☆☆ | 3min | base64 | Base64_Encoding |
| 11 | ROT13 / tr | 🟡 developing | ★★☆ | 12min | tr, cat | ROT13_Cipher |
| 12 | repeated decompression | 🟡 developing | ★★☆ | 20min | xxd, file, gzip, bzip2, tar, mktemp | File_Signatures, Hexdump_Reversal |
| 13 | SSH key auth (private key) | 🟡 developing | ★★☆ | 15min | ssh, scp, chmod, cat | SSH_Key_Authentication, File_Permissions |

## Status Legend
- 🔴 raw — captured but not formally written
- 🟡 developing — partial writeup, missing phases
- 🟢 solid — complete 5-phase writeup, reviewed
- ⭐ mastered — flashcard-recall verified

## Foundational Concepts (general, cross-level)

| Concept | Status | Domain | First Introduced | Why It Matters |
|---|---|---|---|---|
| Subshell | 🟡 developing | Linux | chat-session 2026-05-28 | `( )` isolation, `$()`, pipeline subshell semantics — 모든 shell scripting의 hidden mechanic |
| Exit_Code | 🟡 developing | Linux | chat-session 2026-05-28 | `$?`, `set -e`, `pipefail`, signal coalescing (`128+N`) — control flow의 atomic unit |

## Foundational Tools (general, cross-level)

| Tool | Status | Category | First Used | Mastery Level |
|---|---|---|---|---|
| find | 🟡 developing | file-discovery | Level_05 | Tool reference 작성됨 (`Tools/find.md`) |

## Progress

```
[############                   ] 14/34 level notes written (00–13)
   └ 🟢 solid: 5 (00,01,02,03,08)   🟡 developing: 5 (09,10,11,12,13)   🔴 raw: 4 (04,05,06,07)
Concept Atoms: 7 written (Subshell, Exit_Code, Regex_Flavors, Strings_Extraction, Base64_Encoding, File_Signatures, SSH_Key_Authentication[Network])
Tool References: 3 written (find, sort, uniq)
Pending atoms (dangling): ROT13_Cipher, Stream_Deduplication, Pipe_Composition, Hexdump_Reversal, File_Permissions, Asymmetric_Cryptography, Digital_Signature
Pending tools (dangling): strings, grep, xxd, base64, tr, ssh, scp, chmod, ssh-keygen, cat, file, gzip, bzip2, tar, mktemp
```

## Update Protocol

When a new Level note is created:
1. Add node to mermaid graph (above)
2. Add edges (Leads_To from previous, dotted edges to tools/concepts introduced)
3. Append row to metadata table
4. Update progress bar
5. `last_updated` frontmatter field
