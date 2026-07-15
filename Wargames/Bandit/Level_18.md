---
date: 2026-07-15
wargame: Bandit
level: 18
title: "Bandit Level 18 → 19"
difficulty: ★★☆
time_spent: 5min
tags: [bandit, linux, ssh, bash, shell-init]
status: 🟡 developing
tools_used: [ssh, cat]
new_concepts: [Shell_Initialization]
prerequisites: [Level_17]
---

# Bandit Level 18 → 19

## [Phase 1] Executive Summary

- **Goal**: bandit18의 `~/.bashrc`가 로그인 즉시 `Byebye !` 후 logout시킴 → 이를 우회해 홈의 `readme`를 읽어 bandit19 password 획득
- **Key Skill**: `ssh user@host "command"` — **원격 명령 실행(비인터랙티브 셸)**으로 `.bashrc` 미실행 → 트랩 회피
- **Tags**: `[Shell_Initialization]`, `[SSH_Remote_Command]`, `[Interactive_Vs_NonInteractive_Shell]`

[Cognitive Validation]
- **Limit Test**: 인터랙티브 로그인(`ssh host`) → `.bashrc` 실행 → 즉시 logout; 비인터랙티브(`ssh host "cmd"`) → `.bashrc` 스킵 → cmd 실행. 셸의 **interactive 여부**가 지배 변수.
- **Control Knob**: 지배 변수는 **"셸이 interactive인가"**. bash는 interactive(비로그인) 셸에만 `~/.bashrc`를 source. 명령을 인자로 주면 non-interactive → 트랩 우회.
- **Nullity**: `.bashrc`에 트랩이 없으면 일반 로그인도 성공 — 이 문제의 장벽은 오직 그 파일의 `exit`/logout 트랩 하나.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**Shell initialization + interactive vs non-interactive 구분**. 이 레벨의 전부는 "**어떤 종류의 셸이 어떤 시작 파일을 읽는가**". 공격 파일(`.bashrc`)이 특정 셸 종류(interactive)에서만 실행된다는 점을 이용해, 그 종류를 피하는 방식으로 접근한다.

### 2. Definition (Formal, EN)

`bash` reads different startup files by two axes — **login vs non-login** × **interactive vs non-interactive**:
- **interactive + login** → `/etc/profile`, then the first of `~/.bash_profile` / `~/.bash_login` / `~/.profile` (which commonly sources `~/.bashrc`).
- **interactive + non-login** → `~/.bashrc`.
- **non-interactive** (e.g. `bash -c "cmd"`, as spawned by `ssh host "cmd"`) → reads **neither** `~/.bashrc` nor profile files, unless `$BASH_ENV` names a file to source.

∴ a trap placed in `~/.bashrc` fires only for interactive shells; a remotely-executed command bypasses it.

### 3. Intuition (KR)

`.bashrc`는 "**대화형 셸이 켜질 때 자동 실행되는 시작 스크립트**". 악성 `.bashrc`가 "인사(`Byebye !`)하고 문 닫기(`exit`)"를 심어놨다. 그런데 명령을 들고 문 앞에서 "이것만 하고 갈게"(`ssh host "cat readme"`)라고 하면, **대화형 셸이 아예 안 켜지니** 그 시작 스크립트가 안 돌고 → 트랩을 밟지 않는다.

### 4. Theory (Mechanism)

`ssh`의 두 모드가 서로 다른 셸을 띄운다:

1. **`ssh host`** (명령 없음) → 원격에 **interactive login 셸** 부여 → bash가 profile + `.bashrc` 계열을 source → 악성 `.bashrc`의 `echo Byebye!; exit` 실행 → 즉시 연결 종료.
2. **`ssh host "cmd"`** → sshd가 `bash -c "cmd"`로 **non-interactive** 실행 → bash가 `$-`에 `i` 없음을 확인하고 `.bashrc`를 **source하지 않음** → 트랩 미발동 → `cmd` 결과만 반환하고 종료.

인과: `.bashrc`에 logout 트랩(조건) → 인터랙티브 로그인은 트랩 발동(B) → 명령 인자 부여로 non-interactive 실행(C) → `.bashrc` 스킵 → `readme` 출력(D).

### 5. Solution

```bash
# --- 일반 로그인 → .bashrc 트랩에 걸림 ---
$ ssh -p 2220 bandit18@bandit.labs.overthewire.org
# Password: <password masked>
# ... 배너 ...
Byebye !
Connection to bandit.labs.overthewire.org closed.   # ← 로그인 즉시 강제 logout

# --- 해법: 원격 명령 실행(non-interactive) → .bashrc 우회 ---
$ ssh -p 2220 bandit18@bandit.labs.overthewire.org "ls"
# Password: <password masked>
readme                                              # ← 셸을 안 열고 ls만 실행

$ ssh -p 2220 bandit18@bandit.labs.overthewire.org "cat readme"
# Password: <password masked>
<password masked>                                   # ← bandit19 password
```

> [!warning] Password Masking
> bandit18 password(로그인용)와 `readme`가 담은 bandit19 password 둘 다 마스킹. 특히 사용자 로그인 헬퍼가 클립보드 password를 프롬프트에 붙여 **화면에 노출**시킬 수 있으니(paste artifact) 그 줄도 절대 commit 금지.

### 6. Why It Works

`~/.bashrc`는 **interactive 셸만** source하는 파일이다. `ssh host "cmd"`는 명령을 non-interactive bash로 실행하므로 `.bashrc`가 아예 로드되지 않아 logout 트랩이 발동하지 않는다. 그 결과 `cat readme`가 정상 실행돼 password를 stdout으로 반환하고 연결이 닫힌다. 핵심은 "**셸의 종류를 바꿔 트랩의 실행 조건을 회피**"한 것.

### 7. Edge Cases / Limitation

- **대화형 셸이 필요하면**: `ssh -t bandit18@host -p 2220 "bash --noprofile --norc"` — `-t`로 PTY 할당 + rc/profile를 스킵한 셸 → 트랩 없는 대화형 환경. (`--norc`=`.bashrc` 스킵, `--noprofile`=profile 스킵.)
- **트랩이 다른 파일에 있었다면**: `.bash_profile`/`.profile`은 login 셸만 읽으므로 `ssh host "cmd"`(비로그인·비인터랙티브)로 역시 우회됨. **`$BASH_ENV`**가 가리키는 파일은 non-interactive도 source하므로, 거기 있으면 명령 실행마저 트랩에 걸린다.
- **`readme` 접근**: 홈에 있고 bandit18이 read 가능 → 단일 명령으로 완결.
- **셸 자체를 바꿔도 됨**: `ssh -t host /bin/sh` — `sh`는 `.bashrc`를 안 읽음(bash 전용 파일).

---

## [Phase 3] Formal Summary (EN)

> [!definition] Bash Startup File Matrix
> Which files `bash` sources is determined by (login?) × (interactive?): interactive-login → profile chain; interactive-non-login → `~/.bashrc`; non-interactive → none (unless `$BASH_ENV`). A command run via `ssh host "cmd"` is non-interactive non-login ⇒ neither `.bashrc` nor profile is read.

> [!theorem] Trap-in-`.bashrc` is bypassed by remote command execution
> If a logout trap resides in `~/.bashrc`, it executes iff the spawned shell is interactive. `ssh host "cmd"` spawns `bash -c cmd` (non-interactive) ⇒ `.bashrc` is not sourced ⇒ trap does not fire ⇒ `cmd` runs to completion. □

---

## [Phase 4] Better Methods

**Current approach** (used above): `ssh host "cat readme"` — 원격 명령 실행. 가장 직접적.

**Alternative 1**: 트랩 없는 대화형 셸 (탐색이 더 필요할 때)
```bash
ssh -t bandit18@bandit.labs.overthewire.org -p 2220 "bash --noprofile --norc"
#   -t          : 원격에 PTY 할당(대화형 셸엔 필수)
#   --norc      : ~/.bashrc source 안 함 → 트랩 스킵
#   --noprofile : login profile도 스킵
```
Trade-off: 대화형 프롬프트 확보(여러 명령 탐색 가능). 단 `-t` 필요.

**Alternative 2**: 다른 셸로 우회
```bash
ssh -t bandit18@bandit.labs.overthewire.org -p 2220 /bin/sh
#   /bin/sh는 bash 전용 ~/.bashrc를 읽지 않음 → 트랩 무관한 셸
```
Trade-off: POSIX sh 환경(bash 기능 없음). 트랩이 bash rc에 한정될 때 유효.

**Most elegant**:
```bash
ssh bandit18@bandit.labs.overthewire.org -p 2220 "cat readme"
```
Why elegant: 목표(readme 읽기)만 정확히 수행. 셸을 열지 않으니 트랩과 마주칠 일 자체가 없음.

---

## [Phase 5] Lessons Learned

1. **`~/.bashrc`는 interactive 셸만 source** → `ssh host "cmd"`(non-interactive)로 트랩 우회.
2. **bash 시작 파일 매트릭스**: (login/non-login)×(interactive/non-interactive)가 무엇을 읽는지 결정 — 우회·방어 지점이 여기서 보인다.
3. **대화형이 필요하면** `ssh -t host "bash --norc --noprofile"` 또는 `ssh -t host /bin/sh`.
4. **비대칭 방어**: 트랩을 `.bashrc`에 두면 명령 실행으로 뚫린다. `$BASH_ENV` 경로여야 non-interactive까지 잡힌다.

### Quiz

**Q**: bandit18 `.bashrc`가 즉시 logout시킨다. (a) `ssh host "cmd"`가 이를 우회하는 이유를 셸 초기화 관점에서, (b) 트랩이 `.bash_profile`에 있었다면 같은 명령으로 우회되는지, (c) `ssh host "cmd"`로도 못 뚫게 하려면 트랩을 어디 둬야 하는지 설명하라.

> [!tip]- 풀이
> **(a)** `.bashrc`는 interactive 비로그인 셸만 source. `ssh host "cmd"`는 `bash -c`로 **non-interactive** 실행 → `.bashrc` 스킵 → 트랩 미발동.
>
> **(b)** 우회됨. `.bash_profile`은 **login 셸**만 읽는데, `ssh host "cmd"`는 login도 interactive도 아니라 그것도 스킵.
>
> **(c)** `$BASH_ENV`가 가리키는 파일에 두면 됨 — bash는 non-interactive 시작 시 `$BASH_ENV`의 파일을 source하므로 명령 실행도 트랩에 걸린다. (또는 로그인 셸 바이너리 자체를 악성으로 교체.)
>
> 핵심: **"어떤 셸이 어떤 파일을 읽는가"**를 알면 우회 지점과 방어 지점이 동시에 보인다. interactive→`.bashrc`, login→profile, non-interactive→`$BASH_ENV`.

> [!flashcard]
> **Q**: bandit18의 `.bashrc` 즉시-logout 트랩을 우회하는 명령은?
> **A**: `ssh bandit18@host -p 2220 "cat readme"` — 원격 명령은 non-interactive bash로 실행돼 `.bashrc`를 source하지 않음 → 트랩 미발동.

> [!flashcard]
> **Q**: bash는 `~/.bashrc`를 언제 읽나?
> **A**: **interactive 비로그인** 셸일 때. login 셸은 profile 계열(`.bash_profile`/`.profile`), non-interactive(명령 실행)는 둘 다 안 읽음(`$BASH_ENV` 예외).

---

## Links

### Tools Used
- [[Tools/ssh]]
- [[Tools/cat]]

### Concepts Introduced (first encountered here)
- [[Concepts/Linux/Shell_Initialization]]

### Concepts Applied (reused from earlier)
- SSH 접속(Level 00~16) — 여기선 **원격 명령 실행 모드**(`ssh host "cmd"`)로 재조명

### Navigation
- **Prerequisite**: [[Level_17]]
- **Next**: [[Level_19]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit19.html
- `bash(1)` — INVOCATION section (startup files: `.bashrc`, `.bash_profile`, `BASH_ENV`)
- `ssh(1)` — remote command execution, `-t` (force pseudo-terminal)
