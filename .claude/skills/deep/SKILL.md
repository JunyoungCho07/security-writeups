---
name: deep
description: Create an atomic concept note in Concepts/{domain}/ with the full 15-step deep-dive structure. Use when the user types <<Deep X>>, /deep X, or a NEW and significant concept is first encountered in a level.
argument-hint: <Concept_Name>
---

# Concept Atom Deep Dive

Argument: the concept name. `$ARGUMENTS`

## Steps (in order)

1. **Read first** (lazy-load contract — do not skip):
   - `_Templates/Concept_Template.md`
   - `_System/Frontmatter.md`
   - `_System/Link_Protocol.md`
2. Decide domain: `Concepts/{Linux|Crypto|Network|Web}/`. Filename in `English_Pascal_Snake_Case.md` (e.g. `File_Signatures.md`).
3. Check the target file does not already exist — if it does, extend it instead of recreating.
4. Write the full 15-step structure from the template. Definition-first, NOT analogy-first. EN for formal sections, KR for intuition.
5. Block IDs: exactly `^definition` and `^intuition`, nowhere else.
6. Bidirectional links: set `first_encountered:` to the active level note AND add this concept under that level's "Concepts Introduced" — both directions, same turn.

## Quality gates (must pass before output)

- [ ] `[Cognitive Validation]` block with ≥1 tool (Limit Test / Control Knob / Nullity)
- [ ] Counter-opinion or alternative method presented
- [ ] Graduate-level quiz at the end
- [ ] Only the 6 allowed callouts (`!definition !tip !warning !flashcard !theorem !proof`)
- [ ] Atomic principle respected: this concept is NEW + significant, not a generic term
