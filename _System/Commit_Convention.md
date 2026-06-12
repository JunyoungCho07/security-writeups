---
doc_type: system_protocol
purpose: Conventional Commits format for vault
load_when: User triggers <<Push>>, generating commit messages
companion: scripts/push.sh (macOS/Linux), scripts/push.ps1 (Windows)
source: extracted from CLAUDE.md v1.0 §13 on 2026-05-19
---

# Commit Message Convention (Conventional Commits)

When generating `<<Push>>` output, use this format:

```
{type}({scope}): {short description}

{optional body explaining what and why}
```

## Types

- `feat`: new writeup or concept note
- `fix`: correction to existing writeup
- `docs`: README / MOC updates
- `chore`: vault structure, scripts, tooling
- `refactor`: restructuring without content change

## Scopes

- `bandit`, `natas`, `htb` etc. for wargame writeups
- `concept`, `tool`, `moc` for cross-cutting
- `infra` for scripts/config

## Examples

- `feat(bandit): level 3 - hidden file discovery`
- `feat(concept): add Hidden_Files atomic note`
- `docs(moc): update Bandit mermaid graph`
- `chore(infra): add pre-commit password leak guard`
