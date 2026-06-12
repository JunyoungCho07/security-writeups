---
name: quick
description: Terse 3-step answer mode — Direct Answer, Boundary, Forward Link. No file creation, no deep dive. Use when the user types <<Quick>> or /quick before a question.
argument-hint: <question>
---

# Quick Query Mode

Question: `$ARGUMENTS`

Answer in exactly 3 steps, nothing else:

1. **Direct Answer** — the answer itself, 1-3 sentences, EN technical terms.
2. **Boundary** — where this answer stops being true (one limit, edge case, or counterexample).
3. **Forward Link** — one pointer for deeper study: an existing `[[Concept]]` note if one exists, otherwise a suggested `<<Deep X>>` trigger.

No file creation. No templates. No quiz. If the question actually requires a full writeup or concept atom, say so in the Forward Link instead of expanding inline.
