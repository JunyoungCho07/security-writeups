---
date: 2026-07-23
domain: Linux
topic: Tty_And_Terminals
tags: [linux, tty, terminal, pty, stdin, foreground, interactive, isatty]
status: 🟡 developing
note_tier: lite
mastery: 36
first_encountered: [[Wargames/Bandit/Level_32]]
reapplied_in: []
---

# TTY & Terminals

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> L32 세션의 "`$0`만 쳤는데 왜 무출력?" 질문에서 **interactive vs non-interactive · foreground · isatty**를 판 노트. `/deep` 시 termios(cooked/raw), 세션/프로세스 그룹, job control, pty master/slave까지.

## Definition (Formal, EN)

A **tty** ("teletypewriter", from the 1960s–70s electromechanical terminals Unix was born on) is a **terminal device** — a special file (`/dev/tty`, `/dev/pts/N`) wiring a keyboard+screen to a process's stdin/stdout/stderr. Beyond a plain pipe it provides line editing, control-key→signal translation, echo, and a **foreground process group** that owns the keyboard.

## Intuition (KR)

내 터미널 = **파일 하나**. 그 파일이 "살아있는 키보드 연결 + 터미널 기능(시그널·편집·포커스)"을 준다. 키보드는 하나뿐이라 **한 번에 한 프로세스(foreground)**만 읽는다.

## Key Points (무엇을 팠나)

### A. tty가 '파이프'와 다른 점
- **줄 편집**(cooked) ↔ 글자단위(raw, vim/게임). **제어키→시그널**: Ctrl-C=SIGINT, Ctrl-Z=SIGTSTP, Ctrl-D=EOF, Ctrl-\=SIGQUIT. **에코**(친 글자 표시). 장치 파일(`/dev/tty`, pty는 `/dev/pts/N`·`/dev/ttysNNN`).

### B. foreground process group = 키보드 소유권
- 키보드는 하나 → tty가 **foreground 프로세스 하나에게만** 입력·Ctrl-C를 준다. 셸이 자식을 띄우면 자식이 foreground가 되고 부모는 [[Process_Creation|waitpid로 블록]].
- **직관 강화 (VirtualBox)**: VM 창을 클릭하면 마우스/키보드가 게스트에 **capture**, Host키로 반환 — "공유 불가 입력장치 + 여러 소비자 → OS가 배타 focus를 한 번에 하나에게". 터미널 foreground = VM capture = 창 focus, **같은 원리**.

### C. isatty → 프로그램이 행동을 바꾼다
- `[ -t 0 ]`/`[ -t 1 ]`로 stdin/stdout이 tty인지 검사. **`ls`**: tty면 색·컬럼, 파이프면 밋밋(`ls|cat` 무색). **셸**: tty면 프롬프트+대기, 아니면 실행 후 종료.

### D. interactive vs non-interactive (L32의 "무출력" 정체)
- 진짜 터미널(bandit SSH=**pty**)에선 `$0` 자식 셸이 대화형으로 떠 프롬프트+키 대기. **tty 없는 곳**(Claude `!`, 파이프, cron)에선 자식 셸이 읽을 입력·키보드가 없어 **즉시 EOF→종료**(exit 0) → 무출력.
- ∴ **"셸이 뜨느냐(fork+execve)"와 "화면에 머무느냐(tty 유무=대화형)"는 별개.**

## Encountered / Applied In
- [[Wargames/Bandit/Level_32]] — `$0`이 bandit SSH(pty)에선 `$` 프롬프트를 띄웠지만 비대화형 실행기에선 조용히 종료. [[Process_Creation]](fork/exec/wait) 문맥.

## Expand Later (`/deep` candidates)
- **`/deep Termios`** — cooked/raw, `stty`, line discipline, VMIN/VTIME.
- **`/deep Job_Control`** — 세션/프로세스 그룹, `SIGTTIN`/`SIGTTOU`, fg/bg, controlling terminal.
