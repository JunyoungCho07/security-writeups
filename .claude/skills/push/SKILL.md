---
name: push
description: Draft a Conventional Commit message and the push command for current changes. DRAFT ONLY — never executes git commit or push. Use when the user types <<Push>> or /push.
---

# Push Draft (DOES NOT EXECUTE)

## Steps (in order)

1. **Read first**: `_System/Commit_Convention.md`.
2. Run `git status` and `git diff --stat` to summarize what changed.
3. Pre-flight secret check: scan changed files for unmasked credential-looking strings (the pre-commit hook is the final gate, but catch it here first).
4. Draft the commit message per convention (`type(scope): description`).
5. Output exactly one suggested command line and stop:
   - macOS/Linux: `./scripts/push.sh "type(scope): message"`
   - Windows: `.\scripts\push.ps1 "type(scope): message"`

## Hard rules

- **NEVER execute** `git commit`, `git push`, or the push scripts. The user runs the command (GPG pinentry needs their passphrase anyway).
- Never suggest `--no-verify`.
