---
date: 2026-07-23
domain: Network
topic: Git_Over_SSH
tags: [network, git, ssh, transport, url-parsing, upload-pack, receive-pack]
status: 🟡 developing
note_tier: lite
mastery: 40
first_encountered: [[Wargames/Bandit/Level_27]]
reapplied_in: [[[Wargames/Bandit/Level_28]], [[Wargames/Bandit/Level_29]], [[Wargames/Bandit/Level_30]], [[Wargames/Bandit/Level_31]]]
---

# Git Over SSH

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> Bandit L27(27→28)에서 비표준 포트로 clone하며 판 개념. git이 전송을 ssh에 위임하는 구조 + URL authority 문법이 핵심. `/deep` 시 smart/dumb protocol, protocol v2, pkt-line 프레이밍까지.

## Definition (Formal, EN)

`git` does not implement network transport itself: for an `ssh://` remote it **execs the `ssh` binary** and runs one remote command — `git-upload-pack '<path>'` for read (clone/fetch) or `git-receive-pack '<path>'` for write (push). The SSH port lives in the URL **authority** (`ssh://[user@]host[:port]/path`), never as a git flag.

## Intuition (KR)

git은 "우편배달"을 직접 안 한다 — **`ssh`라는 우체국에 맡긴다.** 그래서 포트·키·인증은 전부 ssh의 소관이고, git은 서버에서 `upload-pack`(읽기)/`receive-pack`(쓰기)만 돌린다.

## Key Points (무엇을 팠나)

### A. URL 문법 & 포트
- `git clone`엔 **`-p` 옵션이 없다**(그건 ssh의 것) → `error: unknown switch 'p'`. 포트는 **URL authority**(`host:2220`, host 뒤·첫 `/` 앞)에.
- `:port`를 **path 끝**에 붙이면 → 접속은 기본 22(콜론이 transport엔 리터럴), 동시에 local dir 이름이 그 숫자가 됨(`git_url_basename`이 콜론을 경로 구분자로) — **한 콜론, 두 파서, 정반대 해석**. 모든 `scheme://`(ssh/git/https)에 공통인 RFC-3986 파싱.
- 포트를 ssh 계층에 위임: `GIT_SSH_COMMAND="ssh -p 2220"`, `git -c core.sshCommand=...`, `~/.ssh/config`의 `Port`.

### B. 전송 방향 (read vs write)
- clone/fetch = 서버 **`upload-pack`**(내려받기). push = 클라 send-pack → 서버 **`receive-pack`**(올리기). 같은 ssh transport, 방향만 다름.
- 원격 명령 예: `ssh -p 2220 user@host git-upload-pack '/home/../repo'`.

### C. 인증 (OTW 관례)
- `banditNN-git` 계정의 password = **banditNN의 password**(직전 레벨 성과). 키 아님. 공식 문구 "same as for the user banditNN".
- `Permission denied (methods)`의 괄호 = **서버가 광고한 인증 방법 목록** — 어느 포트/문에 닿았는지의 tell.

## Encountered / Applied In
- [[Wargames/Bandit/Level_27]] — 비표준 포트 clone; URL authority/포트 문법, 콜론 이중 파싱.
- [[Wargames/Bandit/Level_28]] · [[Wargames/Bandit/Level_29]] · [[Wargames/Bandit/Level_30]] — 같은 transport로 clone해 [[Git_Object_Model]] 탐색.
- [[Wargames/Bandit/Level_31]] — 같은 transport의 **write**(push) + [[Git_Server_Side_Hooks]].

## Expand Later (`/deep` candidates)
- **`/deep Git_Wire_Protocol`** — smart vs dumb HTTP, protocol v0/v2, pkt-line, want/have 협상, thin pack.
- **`/deep Ssh_Config`** — Host alias, `-G` 프로브, `GIT_SSH`/`GIT_SSH_COMMAND` vs `core.sshCommand`.
