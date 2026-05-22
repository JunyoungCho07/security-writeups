---
doc_type: system_protocol
purpose: Bidirectional wiki-link rules and link type taxonomy
load_when: Creating cross-references, running <<EOL>> verification
companion: _System/EOL_Protocol.md
source: extracted from CLAUDE.md v1.0 §6 on 2026-05-19
---

# Link Protocol

## Bidirectional Rule (MANDATORY)

Every `[[Wiki_Link]]` must be reciprocated:

- `Level_03.md` mentions `[[Hidden_Files]]` → `Hidden_Files.md` MUST contain `[[Level_03]]` (as `Encountered_In`)
- After `<<EOL>>`, run link verification on all touched files (see `_System/EOL_Protocol.md`)

## Link Types

| Type | Direction | Where to use |
|---|---|---|
| **Prerequisite** | Earlier concept → current | "Before this, understand X" |
| **Leads_To** | Current → future concept | "This unlocks Y" |
| **Related** | Bidirectional, structural similarity | Dual concepts, opposite techniques |
| **Cross_Domain** | Same idea in different field | Modular arithmetic ↔ RSA |
| **Encountered_In** | Concept → wargame level | "First seen in Level_03" |
| **Tool_For** | Concept → tool that implements | "Hidden files → ls -la" |

## When NOT to Link

- Generic terms ("file", "command", "input") unless a dedicated note exists
- Self-references
- More than 15 links in a single note (signal: note is not atomic — split it)
