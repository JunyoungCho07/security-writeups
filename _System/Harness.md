---
doc_type: system_protocol
purpose: How the harness enforces CLAUDE.md §1 — layers, fail modes, layer strength, documented limits, changelog
load_when: Touching any guard, git hook, settings rule or test; running a harness audit
companion: CLAUDE.md §1, scripts/claude/tests/run_tests.sh
enforced_by: scripts/claude/tests/run_tests.sh (wiring + doc/guard drift checks)
source: relocated from CLAUDE.md v4.0 §3 and footer on 2026-09-26 (harness v4.1)
---

# Harness — layers, fail modes, limits

CLAUDE.md §1 says *what* must hold. This file says *which mechanism holds it*,
how each one fails, and what none of them can hold. The behaviour in every
row is pinned by `bash scripts/claude/tests/run_tests.sh` (must print ALL
GREEN); its drift checks fail when a script, hook, key id or settings rule
named here goes missing. The prose itself is checked by audits, not by tests.

## [1] Layers (v4.1)

| Layer | Script | Enforces | Fail mode |
|---|---|---|---|
| git pre-commit (+ pre-merge-commit, same file) | `scripts/pre-commit` → `secret_scan.py` | Every staged blob: credentials (R0–R3, incl. 10-char passwords), private/API keys, personal identifiers; forbidden filenames; no-publish paths (case-folded dirs, any `.nopublish` marker, any `.gitignore`d path) | **closed** — scanner missing or crashing blocks the commit |
| git pre-push | `scripts/pre-push` → `secret_scan.py` | Every commit new to the remote: signature `G` by `E81313B5B651B0D9`; no no-publish or ignored path in any pushed tree; forbidden filenames; every new blob and every commit message through the scanner. `--check <range>` is the read-only audit mode | **closed** — undeterminable range or scanner failure refuses the push |
| SessionStart | `session-guard.sh` | Installs and *verifies* the three git hooks (regular file, executable, byte-equal); `core.hooksPath` → DISARMED; signing (key, openpgp, real GnuPG, secret key present); restores missing `.nopublish` markers; names unexpected hooks; counts identifiers. One terse line | open (reports, never bricks) |
| PreToolUse(Bash) | `bash-guard.sh` → `guard_bash.py` | Command forms for §1.1 key reads and §1.2/1.3/1.6/1.7/1.8. **Terminal** — see [2] | **closed** on a match; a crash on a command naming a gated marker blocks, a marker-free crash fails open; no python3 → degraded regex fallback |
| PostToolUse(Write\|Edit\|MultiEdit\|NotebookEdit) | `write-guard.sh` → `guard_write.py` → `secret_scan.py` | Warns on credentials/identifiers the moment they land, and on misplaced/misnamed files | open (advisory) |
| PostToolUse(Bash) | `guard_index.sh` | Unstages any no-publish or ignored path, whatever route staged it | open (self-healing) |
| settings `permissions` | `.claude/settings.json` | `deny`: key/token-store and identifier-file reads, signing/hook-bypass prefixes; `ask`: commit, push, edits to `.claude/**` and `scripts/**` | `deny` holds in every mode; `ask` forces a prompt in auto mode |

`secret_scan.py` is the single rule set: the write guard warns about exactly
what the hooks will block, and a rule changed in one place changes all three.

## [2] Layer strength and the terminal parser

Strongest first:

1. **Server-side rules** — none yet. GitHub branch protection ("Require signed
   commits") on `main` is the only layer a human `--no-verify` cannot skip;
   it is JY's decision.
2. **Git state gates** — `pre-commit`, `pre-push`, `guard_index.sh`. They
   inspect the objects and the index, not the command that produced them, so
   a novel command form cannot route around them.
3. **Tool-level path rules** — settings `deny` on `Read`/`Edit`/`Write`: the
   path arrives structured, so matching is sound.
4. **Shell-string parsing** — `guard_bash.py`. Best-effort by construction:
   a denylist over an unbounded command space.

**The parser is terminal (decided 2026-09-26).** Seven red-team rounds, then
the 2026-09-26 audit, each found new bypass classes. That is not a mandate for
another round: the §1 invariants rest on layers 2–3, and the parser is the
fast, friendly first gate. A bypass class found from now on is recorded in [3]
as a documented limit — or, if it threatens an invariant, the asset is raised
to a stronger layer. Never call something "blocked" when only layer 4 covers it.

## [3] Documented limits (2026-09-26)

- A human `git commit --no-verify` / `git push --no-verify` — by design (§1.2):
  JY runs any bypass himself. Only a server-side rule would catch it.
- Guard self-protection from the shell is a denylist. Its backstop is settings
  `ask` on `scripts/**` and `.claude/**`, plus `session-guard.sh` reinstalling
  the hooks from source every session.
- Heredoc bodies used as operand lists (`xargs rm <<EOF`) are not modelled.
- Key reads that name no path (`find ~ -name id_rsa -exec cat {} \;`,
  `grep -r "PRIVATE KEY" ~`) pass the parser; `~/.sshrc` is refused by the
  `/.ssh` substring (conservative).
- Scanner, missed shapes: a bare uppercase word with no context (Krypton) is
  indistinguishable from a heading; about 2% of bare 10-char tokens with ≤ 2
  character classes and < 3 class changes pass; a token of exactly three
  single-class blocks (`Computing101`) is exempt as an identifier; a secret
  split across two lines, or spelled with homoglyphs, is not reassembled.
  Exemptions are shape-bounded, and a secret that fits the shape passes: up
  to 11 chars inside a YouTube URL, up to 12 after `tmp.`, up to 20 after `@`
  or `github.com/`; exactly 43 chars after `SHA256:` (the host-key
  fingerprint shape); a one-case hex run of 12+ chars (an id or dump) unless
  a password label or a pass-file read sits right before it; a token of at
  most two distinct characters (`xxxx`, `AAAA` placeholders); a token that
  itself contains `masked`, `redacted`, `example` or `placeholder`. A file with a
  NUL *and* more than 5% control or undecodable bytes (e.g. BOM-less UTF-16
  mixed with Korean) is binary, so only 30+ runs, keys and identifiers are
  judged in it.
- Scanner, over-blocking (deliberate — mask or rephrase, never whitelist):
  JWTs (a web-wargame session token is a credential), multi-hump CamelCase
  names with digits (a `Base64` + `Decode` or `X509` + `Certificate` style
  identifier written as one word), and 30+ runs inside a pasted base64 blob
  all look like passwords, because a 32-char base62 password is
  shape-identical to a base64 chunk. (This paragraph cannot even quote such
  a name — the pre-commit hook refused it.) Also flagged: hashed
  `known_hosts` lines, raw `strings` dumps of real binaries, tar archives of
  text files. Structural exemptions exist only for shapes the vault really
  pastes: SSH host-key fingerprints, public-key bodies, labelled hex and
  base64 digests, one-case hex ids, YouTube ids, mktemp names.
- `.nopublish` markers are working-tree state: a fresh clone has none until
  `session-guard.sh` restores the two hardcoded trees. A repo-root marker is
  not consulted. Unicode NFC/NFD path variants are not folded by the hooks
  (APFS folds the marker lookup, so on this Mac they are caught anyway; a
  normalization-sensitive filesystem would not).
- Tag signatures are not verified (the commits a tag reaches are). A forged
  `gpg.program` that fakes GOODSIG would defeat `%G?`; the session guard only
  checks that the program announces itself as GnuPG.
- `db1f05f` (2026-05-28) is unsigned and already public; a push that re-sends
  the full history to a new *named* remote is refused on it. A push to a bare
  URL treats every commit already on any known remote as published and does
  not re-inspect it. `pre-push --check HEAD` over the full history also
  reports the pre-v4.1 test fixture in `20c1577` (already public, a synthetic
  value); `--check origin/main..HEAD` is the command for "what would a push
  send".
- A conflicted merge resolved by hand skips pre-commit (git does not run it
  while `MERGE_HEAD` exists, and pre-merge-commit only covers clean merges);
  pre-push is the backstop for that commit.
- The no-python3 fallbacks in `bash-guard.sh` / `write-guard.sh` know only the
  v4.0 rules. `setup.ps1` (Windows) installs only pre-commit; the session
  guard installs the rest.
- Whether hooks see commands JY types with Claude Code's `!` prefix is
  unverified; treat those as his own terminal.

## [4] Audit record

2026-09-26 — live audit: nine read-only lanes (state layers, credential
detection, pre-push, write guard, parser false positives, permission
semantics, doc drift, usage evidence, context budget), three build lanes in
scratch clones, one adversarial verifier. Lane reports are kept privately
outside the repo (the operator's harness-audits directory), never committed.

## [5] v4.0 hook table and rationale (verbatim, relocated from CLAUDE.md §3 on 2026-09-26)

Kept as written on 2026-08-16 — a line that is wrong in hindsight is evidence
of what changed. The current table is [1].

### Harness enforcement layer (`.claude/settings.json`)

| Hook | Script | Effect | Fail mode |
|---|---|---|---|
| SessionStart | `session-guard.sh` | Reinstalls `.git/hooks/pre-commit` from source if missing or stale; verifies GPG config; one terse line | open |
| PreToolUse(Bash) | `bash-guard.sh` → `guard_bash.py` | Tokenizes the command and enforces §1.2/1.3/1.6/1.7/1.8 | **closed** on a match, open on crash or missing python3 (degraded regex fallback) |
| PostToolUse(Write\|Edit) | `write-guard.sh` → `guard_write.py` | Warns on unmasked credentials and on misplaced/misnamed files | open (advisory) |
| PostToolUse(Bash) | `guard_index.sh` | State-based backstop: inspects the git index and auto-unstages any no-publish path, whatever route staged it | open (self-healing) |
| git pre-commit | `scripts/pre-commit` | Scans every staged **text** file; blocks secrets, private keys, API keys, no-publish paths | **closed** |

The bash guard is layered on purpose: it blocks known command *forms* (`--no-verify`, `find … -exec` over a guard file, `git -c commit.gpgsign=false`, stdin path-smuggling, plumbing), while `guard_index.sh` catches by *result* anything a novel form still manages to stage. Four rounds of adversarial red-teaming (fresh agents, 2026-08-16) drove both — every bypass they found (`git update-index --stdin`, `rm .git/./hooks/pre-commit`, `find -exec truncate`, `commit-tree`, `eval`/`$VAR` indirection, foreign-interpreter file-ops, `git rm/mv/checkout` on a guard) is now one of the 290+ regression checks.

**Honest limit.** The §1.2/1.3/1.6 invariants — no unsigned commit, no scan bypass, no pwn.college publish — are enforced by the parser AND by `guard_index.sh` (state) AND by settings `deny`/`ask`; that layering is the real guarantee. *Guard self-protection* (blocking a shell command that rewrites a guard file) is inherently a denylist over an infinite command space and cannot be proven complete. Its true backstop is not the parser but: settings `ask` on `Edit`/`Write` to `scripts/**` and `.claude/**`, and `session-guard.sh` reinstalling `.git/hooks/pre-commit` from source every session. Change guards through that audited path — never the shell.

`permissions` in settings add a fast prefix gate (`deny`) and consent gates
(`ask`) on commits, pushes, and edits to `.claude/**` and `scripts/**`.

## [6] Changelog

**v4.1 — 2026-09-26.** A live audit found that the layers CLAUDE.md called
"the real guarantee" had fail-open paths, so they were rebuilt against probes:
one shared scanner (`secret_scan.py`) replaced three diverging rule copies and
now catches 10-char passwords, judges every whitelist clause on the token, and
decides "binary" by content (a NUL byte or a `.gitattributes` line used to
switch the scan off); pre-commit walks the index once and refuses case-folded
no-publish paths and any `.gitignore`d path; a new pre-push hook checks
signatures, no-publish trees, every new blob and every message at the
publication boundary, and pre-commit is also installed as pre-merge-commit;
the session guard verifies what it installs, reports a redirected
`core.hooksPath`, checks the actual signing key, and restores missing
markers; §1.5 became a mechanism (an operator-kept identifier list); the
parser gained comment-line, blank-line and crash fixes, audit-read relief and
key-store coverage, and was declared terminal. Docs gained drift checks, and
this file took over the harness internals from CLAUDE.md.

*Version 4.0 — 2026-08-16. Harness rebuilt against evidence rather than intent:
the bash guard became a tokenizing parser (21 of 44 adversarial bypasses had been
slipping through, and `-n` inside a quoted commit message was a false positive);
the pre-commit scan now covers every text file, not four extensions; no-publish
and "JY owns the commit" became mechanisms; skills were consolidated around what
the transcripts show actually fires; `_System/Vault_Structure.md` added. The
parser was then hardened across seven adversarial red-team rounds (three of them
multi-agent workflows) — the security invariants (no unsigned commit, no scan
bypass, no pwn.college publish) held under layered defense throughout; ~80
guard-self-protection, config/env-transport, and key-read edge vectors were found
and closed, each now one of 453 regression checks in `scripts/claude/tests/`.*

## [7] CLAUDE.md v4.0 lines superseded on 2026-09-26 (verbatim)

These lines were edited, not moved, in the v4.1 update. The originals are kept
here so nothing written before is lost.

```text
# Security Writeups Agent — System Prompt v4.0

| 1.1 | **Never write a real password.** `<password masked>` / `[REDACTED]`, including in drafts. Private keys are never read into context. | *Enforced*: `guard_write.py` warns on write, `pre-commit` blocks the commit, `guard_bash.py` blocks reads of `~/.ssh`, `~/.gnupg` |
| 1.2 | **The pre-commit secret scan is never bypassed.** On a confirmed false positive, JY runs the bypass himself — never the agent. | *Enforced*: `guard_bash.py` parses every form — `--no-verify`, `-n`, `-nm`, abbreviations, `git -C`, `git -c core.hooksPath=`, `sh -c`, `xargs`, env smuggling |
| 1.3 | **All commits GPG-signed** (key `E81313B5B651B0D9`). Signing is never disabled. | *Enforced*: same parser — `--no-gpg-sign`, `-c commit.gpgsign=false`, `config … {false,0,no,off}`, `--unset`, `GIT_CONFIG_*` |
| 1.5 | **No personal identifiers** beyond the GitHub handle in committed files. | *Enforced*: `pre-commit` filename check; identity is set by the operator, never hardcoded in `scripts/setup.*` |
| 1.6 | **No-publish trees never reach the index or the remote.** pwn.college prohibits public writeups; anything under a `.nopublish` marker is local-only. Only general theory, stripped of challenge specifics, may be atomised into public `Concepts/`. | *Enforced*: `guard_bash.py` blocks `git add -f` and any pwn.college path; `pre-commit` refuses to stage beneath a `.nopublish` marker; `.gitignore` |
| 1.8 | **The enforcement layer is not edited from the shell.** | *Enforced*: `guard_bash.py` blocks mutation of `.git/hooks/`, `scripts/claude/`, `scripts/pre-commit`, `.claude/settings.json`; settings gate edits behind `ask` |

bash scripts/claude/tests/run_tests.sh    # 142 checks, must be green

└── scripts/{setup,push}.{sh,ps1}, pre-commit, claude/{guards,tests}

| `/eol` | `/eol`, `<<EOL>>`, or Korean: 세션 종료 / 세션 마감 / 기록하고 / 메모리 업데이트 | Drain parking lot → notes → links → MOC → log → commit plan |
```
