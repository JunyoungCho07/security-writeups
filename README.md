# security-writeups

> Personal writeups for security wargames, CTF challenges, and HTB machines.
> Built as a structured knowledge graph with atomic concept notes and tool references.

## Author
**Junyoung Cho** — KAIST CS, Class of 2026
GitHub: [@JunyoungCho07](https://github.com/JunyoungCho07)

## Philosophy

This repository follows three principles:

1. **First-principles documentation.** Every writeup starts from the formal definition of the underlying concept, not from "type this command." Solutions are explained as instances of general techniques.

2. **Atomic concept linking.** Wargame levels link to atomic concept notes (`Concepts/`) and tool references (`Tools/`). The graph compounds: a concept learned in Bandit Level 3 can be reapplied 30 levels later, and the link is explicit.

3. **No password disclosure.** All wargame passwords are masked (`<password masked>` or `[REDACTED]`). The goal is to teach the technique, not to spoil the challenge. Solving the wargame yourself remains valuable.

## Structure

```
security-writeups/
├── Wargames/
│   ├── Bandit/         ← OverTheWire Bandit (Linux basics)
│   ├── Natas/          ← OverTheWire Natas (web exploitation)
│   └── Leviathan/      ← (planned)
├── CTF/                ← Capture-the-flag event writeups (planned)
├── HTB/                ← HackTheBox machines (planned)
├── BugBounty/          ← Responsible disclosure writeups (planned)
│
├── Concepts/           ← Atomic concept notes
│   ├── Linux/          ← Filesystem, processes, glob, permissions
│   ├── Crypto/         ← Encryption, hashing, key exchange
│   ├── Network/        ← TCP/IP, DNS, services
│   └── Web/            ← HTTP, sessions, injection vectors
│
├── Tools/              ← Single-page command references
├── _MOC/               ← Maps of Content (mermaid graphs)
└── scripts/            ← Vault automation (push helper, hooks)
```

## Navigation

- **Start here**: [Bandit MOC](_MOC/MOC_Bandit.md) — wargame level dependency graph
- **Tool index**: [Linux Commands MOC](_MOC/MOC_Linux_Commands.md)
- **Concept index**: [All Concepts MOC](_MOC/MOC_Concepts.md) *(planned)*

## How writeups are structured

Each level note follows a 5-phase template:

1. **Executive Summary** — goal, key skill, cognitive validation (Limit Test, Control Knob)
2. **Deep Dive** — categorization, formal definition, intuition, mechanism, solution
3. **Formal Summary (EN)** — theorem-style statement of the underlying principle
4. **Better Methods** — alternative approaches, with trade-off analysis
5. **Lessons Learned & Quiz** — generalization + graduate-level extension question

Atomic concepts (in `Concepts/`) use a 15-step structure adapted from graduate-level pedagogy.

## Security Disclaimer

- This repository contains **explanations of solution techniques**, not raw passwords or credentials.
- All commit history is **GPG-signed** for impersonation prevention.
- A pre-commit hook scans for high-entropy strings and blocks accidental credential leaks.
- For OverTheWire wargames specifically: the actual level passwords are intentionally masked. Solve the challenges yourself.

## Verification

All commits in this repository are signed with PGP key `E81313B5B651B0D9`.
- Fingerprint: `55DF1D03939E807157D42293E81313B5B651B0D9`
- Public key: published on GitHub profile

To verify a commit locally:
```bash
git verify-commit <commit-hash>
```

## License

Educational content. Citations welcome with link back. Code snippets and scripts: MIT.

---

*This vault is managed with Obsidian + Cowork agent. Build system documented in `CLAUDE.md` (project-internal).*

<!-- ssh fix verification -->
