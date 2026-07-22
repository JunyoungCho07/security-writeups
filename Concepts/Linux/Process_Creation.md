---
date: 2026-07-23
domain: Linux
topic: Process_Creation
tags: [linux, process, fork, execve, waitpid, system, argv0, syscall, shell]
status: 🟡 developing
note_tier: lite
mastery: 42
first_encountered: [[Wargames/Bandit/Level_32]]
reapplied_in: []
---

# Process Creation (fork / execve / $0)

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> L32의 `$0` 탈출을 계기로 **"프로그램이 다른 프로그램을 어떻게 실행하나"**를 장시간 Q&A로 판 세션 노트. `/deep` 시 process 상태머신, fd 상속·CoW fork, 신호, 세션/프로세스 그룹까지.

## Definition (Formal, EN)

A program becomes a running **process** via two syscalls: **`fork`** (duplicate the current process → child) and **`execve`** (replace the process image with another program's binary). A shell runs a command as: `fork` → child `execve`s the target → parent **`waitpid`** (blocks until child exits). `system("cmd")` is just a wrapper: `execl("/bin/sh","sh","-c","cmd",NULL)` — spawn a shell and hand it the string.

## Intuition (KR)

`fork`=분신(복제), `execve`=변신(다른 프로그램으로 몸 교체), `waitpid`=부모가 자식 끝날 때까지 잠듦. 셸은 이 셋으로 "다른 프로그램을 실행"한다. `system`은 그걸 "sh 하나 불러 통째로 맡김"으로 감싼 것.

## Key Points (무엇을 팠나)

### A. 소스 → 바이너리 → 프로세스
- **소스**(사람이 읽는 텍스트, C 등) → 컴파일 → **바이너리**(CPU가 읽는 기계어 파일, `/bin/ls`) → 실행 → **프로세스**(메모리에서 도는 것).
- **셸도 그냥 프로그램**: `/bin/sh`·`/bin/bash`는 `/bin/ls`와 똑같은 바이너리. 단지 "다른 프로그램을 fork+execve로 호출하는 능력"에 특화.

### B. fork / execve / waitpid
- `fork`+`execve` = 자식으로 **겹침**(nesting, `exit`하면 복귀). **`exec cmd`** = fork 없이 execve만 → 현재 프로세스가 **교체**(돌아올 곳 없음).
- 부모는 `waitpid`에서 **블록**(커널이 sleep). 자식이 **터미널(키보드)을 foreground로 독점** → 자식이 죽어야 부모가 깸. (∴ 자식 셸이 부모 필터를 "건너뛰고" 입력과 직결 — 부모는 자는 중.) → [[Tty_And_Terminals]].

### C. `$0` = argv[0] 이름표
- `$0` = 그 셸이 **호출될 때 받은 이름표(argv[0])** 문자열. 값은 **호출 방식에 달림**: `system()`→`"sh"`, 경로 실행→`/bin/zsh`, 로그인→`-bash`.
- `$0`을 명령자리에 놓으면 → 그 이름 문자열이 확장돼 → 그 프로그램(셸)이 자식으로 실행. **필터가 걸린 제한 셸에선 `$0`이 대문자화 등 변형의 고정점이라 탈출 열쇠**(L32). `exec -a`로 argv[0] 위조 가능(멀티콜 busybox, ps 은닉).

### D. syscall / ABI / userland (커널 경계)
- **syscall** = 프로그램이 커널에 일 시키는 통로(*무엇*: open/fork/execve). **ABI** = 그걸 기계 수준에서 *어떻게*(레지스터·syscall번호·명령) — 바이너리↔커널 이진 규약, **아키텍처(x86-64/ARM64)마다 다름**.
- **userland**(셸·`ls`·라이브러리) vs **kernel space**(하드웨어·프로세스 관리). "리눅스"=커널만; 배포판=커널+GNU userland. 셸은 특권 없는 보통 유저공간 프로그램.

### E. builtin vs 외부 & PATH
- **builtin**(`cd`·`echo`·`pwd`)=셸 안에 박힌 코드(fork 안 함). `cd`가 builtin이어야 하는 이유: 자식이 바꾸면 자식만 바뀌고 사라짐 → 셸 자신의 cwd를 바꿔야 하므로.
- 외부(`ls`)=별도 파일 → 셸이 `$PATH`를 뒤져 찾고 `execve("/bin/ls", ["ls","-l"])`로 인자와 함께 실행. (alias→함수→builtin→외부 순 해석.)

## Encountered / Applied In
- [[Wargames/Bandit/Level_32]] — `input → uppershell(C, toupper→system) → sh → syscall → kernel`; `$0`이 sh로 확장돼 자식 셸 재기동. [[Setuid]](권한 전파) · [[Restricted_Shell_Escape]].

## Expand Later (`/deep` candidates)
- **`/deep Fork_Exec_Model`** — CoW fork, fd 상속/close-on-exec, `posix_spawn`, zombie/orphan, `wait` 상태코드.
- **`/deep Syscall_ABI`** — 아키텍처별 호출규약, `strace`, vDSO, libc wrapper.
