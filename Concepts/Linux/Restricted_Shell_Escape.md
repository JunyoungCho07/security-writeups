---
date: 2026-07-17
domain: Linux
topic: Restricted_Shell_Escape
tags: [linux, restricted-shell, shell-escape, gtfobins, privilege, pager, editor]
status: 🟡 developing
note_tier: lite
mastery: 35
first_encountered: [[Wargames/Bandit/Level_25]]
reapplied_in: []
---

# Restricted Shell Escape

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> Bandit L25(25→26)에서 `showtext`(=`exec more`) 감옥을 뚫으며 판 개념. `$SHELL` 상속 트랩과 pager→editor→shell 체인이 핵심. `/deep` 승격 시 GTFOBins 일반화·rbash·SUID 문맥까지 확장.

## Definition (Formal, EN)

A **restricted shell escape** is the act of breaking out of an environment intended to confine a user to a limited command set (a restricted shell like `rbash`, or a single subprocess-spawning program set as the login shell) into an **unrestricted** shell. It succeeds whenever the confining program can launch another program whose executable is resolved from a source **outside the confiner's control** (an env var it doesn't pin, or a user-settable option), and that program in turn spawns a shell.

## Intuition (KR)

**감옥이 준 도구에 "다른 도구를 부르는 버튼"이 남아 있으면 그 버튼이 곧 출구다.** 페이저·에디터·`awk`·`find`처럼 서브프로세스를 띄우는 프로그램은 전부 사다리가 된다. 관리자가 사다리 하나(`$SHELL`)를 잘라도, 프로그램이 **다른 경로로 프로그램을 고를 수 있으면**(에디터의 `$EDITOR`, vi의 `shell` 옵션) 사다리가 하나 더 있는 셈.

## Key Points (무엇을 팠나)

### A. 감옥의 구성 (bandit26 사례)
- **login shell = 제한 프로그램**: `/etc/passwd`의 마지막 필드가 `/usr/bin/showtext`(=`#!/bin/sh … exec more ~/text.txt`). 정상 셸이 아니라 페이저 하나.
- **`exec`의 효과**: 셸 프로세스를 `more`로 **교체**(fork 없음, 같은 PID). → 셸 프롬프트 부재, `more` 종료 시 **세션 종료**, `exit 0`은 dead code. 접속 즉시 끊기는 현상의 정체.
- **왜 원격 명령도 무력한가**: `ssh host "cmd"` = `$SHELL -c "cmd"` = `showtext -c "cmd"` → 인자 무시·`exec more`. 로그인 셸이 정상 셸이 아니면 원격-명령 실행 자체가 안 된다.

### B. `$SHELL` 상속 트랩 (이 레벨의 핵심)
- 관리자는 `$SHELL=showtext`로 환경을 오염시켜 **하위 프로그램의 셸-탈출 기능까지** 무력화. `more`의 `!cmd`, vi의 `:sh`/`:!`는 전부 `$SHELL -c`를 실행 → showtext → `exec more` → **감옥 복귀**(fixed point).
- 증거: `more`에서 `!cat …`을 쳐도 명령이 실행 안 되고 아트만 재출력 = "명령이 씹혔다"는 신호.
- **벽은 환경변수를 통해 전파**된다 — pager를 벗어나 editor로 갈아타도 `$SHELL`은 따라온다.

### C. 돌파: `$SHELL`을 안 거치는 경로
- **`more`의 `v`**: editor를 띄우되 실행 프로그램을 `$VISUAL`→`$EDITOR`→(default)`vi`로 고른다. **`$SHELL`을 안 본다** → 트랩 1차 우회. vi가 열림.
- **vi의 `shell` 옵션**: `$SHELL`(환경변수)과 별개인 **재할당 가능한 내부 옵션**. `:set shell?`로 오염값(`/usr/bin/showtext`) 확인 → `:set shell=/bin/bash` → `:sh`(또는 `:!`)가 이제 진짜 셸 기동. **오염은 변수로 전파되지만, 돌파는 사용자-가변 옵션으로.**
- **셸 없이 목표만**: 읽기가 목적이면 vi `:e /etc/bandit_pass/bandit26`로 파일을 직접 열어도 됨(셸 spawn 불필요, 최소 권한).

### D. 일반화 — GTFOBins
- "제한 환경/SUID에서 이 바이너리로 어떻게 셸/파일접근을 따나"를 카탈로그화한 사전(<https://gtfobins.github.io/>).
- pager(`more`,`less`), editor(`vi`,`vim`,`nano`), `man`(내부적으로 pager), `awk`,`find -exec`,`env`,`python -c` 등 **subprocess spawn 능력**이 있으면 후보. restricted shell·sudo 화이트리스트·SUID 세 문맥에서 반복 재사용.

### E. 페이저 역학 (탈출의 전제조건)
- `more`/`less`는 **파일 ≤ 화면 줄 수면 페이징 없이 즉시 종료**(`cat`처럼). 상호작용(`--More--`) 진입이 있어야 `!`/`v`를 칠 수 있다.
- 페이저는 **시작 시점**에 pty 크기를 한 번 읽는다(`ioctl(TIOCGWINSZ)`) → 페이징 유도는 **실행/접속 전** 터미널 창 축소. 나중 resize는 무효.

## Encountered / Applied In

- [[Wargames/Bandit/Level_25]] — `showtext`(`exec more`) 감옥을 `v`→vi→`:set shell=/bin/bash`→`:sh`로 탈출. `$SHELL` 상속 트랩 규명.
- (관련) [[Wargames/Bandit/Level_18]] — `.bashrc` 트랩(다른 종류의 셸 환경 함정: interactive-only source vs login-shell 자체).
- (관련) [[Wargames/Bandit/Level_19]] — Setuid(제한/권한 문맥의 평행; GTFOBins가 SUID에도 적용).

## Expand Later (`/deep` candidates)

- **`/deep Restricted_Shell_Escape`** — 전체 15-step: rbash(`PATH`/`cd`/redirect 제약)와 그 우회, sudo 화이트리스트 탈출, SUID+GTFOBins, `$SHELL`/`$PAGER`/`$EDITOR` 신뢰 사슬 일반론.
- **`/deep Login_Shell`** — `/etc/passwd` 셸 필드, `chsh`, `/etc/shells`, nologin, login vs non-login vs interactive 셸 분류.
- **`/deep Exec_Family`** — `exec` 빌트인 + `execve(2)` 프로세스 이미지 교체 의미론(PID 유지, fd 상속, `exec`된 셸의 세션 수명).
