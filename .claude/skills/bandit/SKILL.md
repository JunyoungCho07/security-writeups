---
name: bandit
description: Alias for /level, kept so <<Bandit N>> and /bandit N still work. The level writeup skill is now game-agnostic.
argument-hint: <level-number>
disable-model-invocation: true
---

# Superseded by `/level`

This skill was Bandit-specific; the vault now covers Leviathan and others, so
the writeup contract lives in `.claude/skills/level/SKILL.md`.

**Invoke `/level $ARGUMENTS`** and follow it exactly.

Kept only as a typed alias — it no longer fires on its own. Safe to delete once
`/bandit` is out of muscle memory.
