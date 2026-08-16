---
name: commit
description: Draft the thematic commit sequence for the current changes. DRAFT ONLY — JY runs the commits himself. Use at the end of /eol, or when he asks for a commit plan, <<Push>>, or /push.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash(git status:*)
  - Bash(git diff:*)
  - Bash(git log:*)
  - Bash(git ls-files:*)
  - Bash(git check-ignore:*)
---

# Commit Plan (never executed)

This skill has no write tools and no `git commit` on its allow-list. It cannot
commit even if asked to — that is deliberate, not an oversight.

## Steps (in order)

1. **Read first**: `_System/Commit_Convention.md`.
2. `git status` + `git diff --stat` to enumerate what actually changed. Do not
   rely on conversation memory.
3. Pre-flight secret check: scan the changed files for unmasked credential-like
   strings. The pre-commit hook is the hard gate; catch it here first so he does
   not hit a blocked commit.
4. **Group the changes by theme, not by file.** One concern per commit — this is
   how he commits, and a squashed "everything" commit is a regression.
5. Output the sequence as one copy-pasteable block, `git push` last:

```bash
# 1) <theme>
git add <files for that theme>
git commit -S -m "feat(bandit): levels 21-22 - cron password leak"

# 2) <theme>
git add <files>
git commit -S -m "feat(concept): Shell_Fundamentals lite note"

git push
```

## Hard rules

- **Never execute** `git commit`, `git push`, or `scripts/push.sh`. He runs them
  — GPG pinentry needs his passphrase, and the signature is his, not the
  agent's.
- Never suggest `--no-verify` or `--no-gpg-sign`. If the secret scan fires on a
  confirmed false positive, say so and let *him* decide — the bypass is his to
  run, never the agent's.
- `-S` on every commit.
- Nothing under a no-publish tree (`Wargames/Pwn_College/`, any `.nopublish`
  directory) appears in any `git add` line, ever.
- No attribution trailer — this repo's history has none.
