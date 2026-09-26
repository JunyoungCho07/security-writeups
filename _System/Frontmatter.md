---
doc_type: system_protocol
purpose: Frontmatter YAML schemas for all note types
load_when: Creating any new note file (Level / Concept / Tool)
companion: _Templates/*.md
source: extracted from CLAUDE.md v1.0 §4 on 2026-05-19
---

# Frontmatter Schemas

Single source of truth for YAML frontmatter across note types. When creating a new file, copy the matching block and fill in values.

## Wargame Level Note

```yaml
---
date: YYYY-MM-DD
wargame: Bandit
level: NN                              # integer
title: "Bandit Level N → N+1"
difficulty: ★☆☆ | ★★☆ | ★★★         # subjective, 3-tier
time_spent: NNmin
tags: [bandit, linux, {category}]
status: 🔴 raw | 🟡 developing | 🟢 solid | ⭐ mastered
tools_used: [tool1, tool2, ...]
new_concepts: [concept1, concept2]
prerequisites: [Level_NN-1]
---
```

## Concept Atom

```yaml
---
date: YYYY-MM-DD
domain: Linux | Crypto | Network | Web | Git | Binary
topic: {English_Topic_Name}
tags: [domain-tag, technique-tag]
status: 🔴 | 🟡 | 🟢 | ⭐
note_tier: lite                          # lite notes only; a full 15-step atom omits it
mastery: 0-100
first_encountered: [[Wargames/Bandit/Level_NN]]   # or "External: local-only wargame tree (no-publish) — <context>"
reapplied_in: []
last_reviewed: YYYY-MM-DD                # full atoms only
---
```

## Tool Reference

```yaml
---
tool: {tool_name}
category: file-discovery | network | crypto | text-processing | ...
man_section: 1
related: [tool1, tool2]
last_used: YYYY-MM-DD
tags: [tool, {platform-or-domain-tag}]
---
```

## Rules

- `date` always `YYYY-MM-DD` (ISO 8601, dash-separated)
- `tags` lowercase, hyphen-separated, no spaces
- `status` exactly one of: 🔴 raw | 🟡 developing | 🟢 solid | ⭐ mastered
- `level` integer in frontmatter (no leading zero); filename uses 2-digit (`Level_03.md`)
- `mastery` 0–100 integer (Concept Atom only)
- Empty list fields use `[]`, never omit the key
