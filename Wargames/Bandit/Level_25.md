---
date: 2026-07-17
wargame: Bandit
level: 25
title: "Bandit Level 25 → 26"
difficulty: ★★★
time_spent: 40min
tags: [bandit, linux, restricted-shell, shell-escape, pager, more, vi, gtfobins, ssh, login-shell]
status: 🟡 developing
tools_used: [ssh, more, vi, cat]
new_concepts: [Restricted_Shell_Escape]
prerequisites: [Level_24]
---

# Bandit Level 25 → 26

## [Phase 1] Executive Summary

- **Goal**: bandit25 홈의 `bandit26.sshkey`로 bandit26에 SSH 접속한다. 그런데 bandit26의 **로그인 셸이 `/bin/bash`가 아니라 `/usr/bin/showtext`** — `more`로 파일 하나 보여주고 즉시 끝나는 제한 환경이다. 이 감옥을 **탈출**해 진짜 셸을 얻어 `/etc/bandit_pass/bandit26`을 읽어야 한다.
- **Key Skill**: **restricted shell escape** via pager→editor 체인. `more`가 페이징하도록 **접속 전에 터미널 창을 줄이고** → `more`에서 `v`로 editor(vi)를 띄우고 → vi에서 **`:set shell=/bin/bash`로 셸 옵션을 덮어쓴 뒤** `:sh`로 빠져나온다. 함정의 본질은 **`$SHELL` 상속**: 순진한 탈출구(more의 `!`, vi의 `:sh`)는 전부 오염된 `$SHELL=showtext`를 참조해 도로 감옥으로 튕긴다.
- **Tags**: `[Restricted_Shell_Escape]`, `[Shell_Fundamentals]`(login shell/`$SHELL`), `[SSH_Key_Authentication]`(reapply)

[Cognitive Validation]
- **Limit Test**: `text.txt`가 화면보다 **짧으면**(예: 큰 창) `more`가 페이징 없이 전량 출력 후 즉시 종료 → `exec`된 셸이라 세션까지 종료(탈출 지점 없음). 창을 **파일보다 작게** 하면 `--More--` 대기 진입 → 탈출구 확보. 지배 조건은 **창 세로줄 수 vs 파일 줄 수**.
- **Control Knob**: 탈출 명령이 참조하는 **셸의 출처**. `more`의 `!`·vi의 `:sh`는 환경변수 `$SHELL`(=showtext) → 실패. vi의 `shell`은 **재할당 가능한 옵션** → `/bin/bash`로 바꾸면 성공. 같은 "셸 띄우기"라도 **어디서 셸 경로를 읽느냐**가 성패를 가른다.
- **Nullity**: `more`/vi에 subprocess 실행 기능이 아예 없었다면 감옥은 완전(탈출 불가). pager/editor가 "다른 프로그램을 띄우는" 능력을 가진 순간, 그게 곧 탈출 벡터가 된다(**GTFOBins**의 전제).

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**Restricted shell escape** — 관리자가 사용자를 특정 프로그램(여기선 pager) 안에 가두려 했으나, 그 프로그램이 **서브프로세스를 spawn하는 기능**을 가져 탈출 통로가 열린 사례. `more`/`less`/`vi`/`man`/`awk`/`find` 등 "다른 프로그램을 띄울 수 있는" 바이너리는 전부 잠재적 탈출 벡터고, 이를 카탈로그화한 것이 **GTFOBins**. 이번 레벨의 특이점은 벽이 한 겹이 아니라 **`$SHELL` 환경변수를 통해 전파**된다는 것 — 로그인 셸의 오염이 하위 프로그램의 셸-탈출 기능까지 오염시킨다.

### 2. Definition (Formal, EN)

bandit26's login program (from `/etc/passwd`) is `/usr/bin/showtext`:

```sh
#!/bin/sh
export TERM=linux
exec more ~/text.txt
exit 0
```

`exec` **replaces the shell process image** with `more` (no fork, same PID), so there is never an interactive shell prompt and the session ends when `more` exits. `more` is a **pager**: if the file fits within the terminal's row count it prints everything and exits (like `cat`); if it overflows, it enters interactive paging (`--More--`) and reads keystroke commands. Two of those commands spawn other programs: `!cmd` (a subshell via `$SHELL`) and `v` (an editor via `$VISUAL`/`$EDITOR`, **defaulting to `vi`**). Because `$SHELL=/usr/bin/showtext`, any `$SHELL`-routed escape (`more`'s `!`, `vi`'s `:sh`/`:!`) re-executes `showtext`→`more`. `vi`'s `shell` **option** (distinct from the env var) is reassignable (`:set shell=/bin/bash`), decoupling the escape from the poisoned variable and yielding a real shell as bandit26.

### 3. Intuition (KR)

**간수가 준 열쇠고리가 전부 같은 가짜 열쇠다.** 감옥(showtext)은 "탈출 도구를 쓰면 그 도구가 다시 감옥으로 데려간다"는 규칙(`$SHELL`=감옥)을 심어놨다. `more`의 `!`도, vi의 `:sh`도 그 가짜 열쇠(`$SHELL`)를 꺼내 문을 열려 하니 도로 감옥. 그런데 vi에는 **"어떤 열쇠를 쓸지 내가 지정하는 손잡이"**(`shell` 옵션)가 따로 있다. 그걸 진짜 열쇠(`/bin/bash`)로 바꿔 끼우면 그제서야 문이 열린다.

### 4. Theory (Mechanism)

탈출의 인과 사슬:

1. **정찰** — bandit25에서 `cat /etc/passwd | grep bandit26` → 로그인 셸 `/usr/bin/showtext` 발견. 그 스크립트를 읽어 `exec more ~/text.txt` 구조 파악.
2. **페이징 유도** — `more`는 시작 시 pty의 세로 크기를 **한 번** 읽는다(`ioctl(TIOCGWINSZ)`). 접속 **전에** 터미널 창을 `text.txt` 줄 수보다 작게 만들면, `more`가 처음부터 "화면 초과" 판정 → `--More--` 대기(감옥 안이지만 상호작용 가능 상태).
3. **`!` 시도와 실패** — `more`의 `!cmd`는 `$SHELL -c "cmd"` 실행. `$SHELL=/usr/bin/showtext`라 `showtext -c "cmd"`가 되는데, showtext는 인자를 무시하고 `exec more`. → 명령은 실행조차 안 되고 `more`가 재출력(ASCII 아트 재등장 = "명령 씹힘"의 증거).
4. **`v`로 editor 진입** — `more`의 `v`는 `$VISUAL`/`$EDITOR`(없으면 `vi`)로 editor를 띄운다. **`$SHELL`을 안 거치므로** showtext 함정을 우회, vi가 `text.txt`를 연다. (`export TERM=linux`는 이 순간 vi가 화면을 제대로 그리게 하는 저자의 breadcrumb.)
5. **`:sh` 시도와 실패** — vi의 `:sh`/`:!`도 `$SHELL` 실행 → 또 showtext → more로 복귀. 함정이 editor까지 따라옴.
6. **셸 옵션 덮어쓰기** — vi의 `shell`은 환경변수가 아닌 **내부 옵션**. `:set shell?`로 `shell=/usr/bin/showtext` 확인 → `:set shell=/bin/bash`로 재할당 → `:sh` → 이번엔 `/bin/bash` 실행 → **bandit26 셸 획득**.
7. **회수** — `cat /etc/bandit_pass/bandit26` → Level 26 password.

### 5. Solution

```bash
# bandit25 세션에서 시작 (bandit25 password로 접속)
bandit25@bandit:~$ ls
bandit26.sshkey                        # bandit26 private key 제공됨

# 1) 정찰 — bandit26의 로그인 셸 확인 (왜 접속하자마자 끊기는지의 답)
bandit25@bandit:~$ grep bandit26 /etc/passwd
bandit26:x:11026:11026:bandit level 26:/home/bandit26:/usr/bin/showtext
#   마지막 필드 = 로그인 셸 = /usr/bin/showtext (bash 아님)
bandit25@bandit:~$ cat /usr/bin/showtext
#!/bin/sh
export TERM=linux
exec more ~/text.txt                   # exec = 셸 프로세스를 more로 교체 → 돌아갈 셸 없음
exit 0                                 # dead code (exec 성공 시 도달 못 함)

# 2) 터미널 창을 text.txt보다 '작게' 만든 뒤(← 접속 전!) SSH 접속
#    more가 페이징하도록 강제 — 큰 창이면 전량 출력 후 즉시 종료(=세션 종료)
bandit25@bandit:~$ ssh -i bandit26.sshkey bandit26@localhost -p 2220
#   (작은 창) more가 --More-- 로 대기 진입 → 여기서부터 탈출 시도

# 3) more 안에서: !command 는 막힌다 ($SHELL=showtext 트랩) — 시도만, 실패 확인
#    !cat /etc/bandit_pass/bandit26   →  showtext -c "..." → exec more → 아트 재출력(명령 씹힘)

# 4) more 안에서 v 입력 → editor(vi) 기동 ($EDITOR/$VISUAL 경유, $SHELL 우회)
#    vi가 열리면 ex 명령 모드로:
:set shell?                            # → shell=/usr/bin/showtext  (오염 확인)
:set shell=/bin/bash                   # vi의 shell '옵션'을 진짜 셸로 덮어씀
:sh                                    # 이제 /bin/bash 기동 → 감옥 탈출
[No write since last change]
bandit26@bandit:~$                     # ← bandit26 셸 획득!

# 5) 회수
bandit26@bandit:~$ cat /etc/bandit_pass/bandit26
<password masked>                      # ← Level 26 password
```

> [!warning] Password Masking & private key
> bandit26 password 마스킹. `bandit26.sshkey`(OpenSSH private key)는 **본문에 절대 포함 금지** — pre-commit hook이 PEM private-key 헤더 블록을 차단한다(헤더 리터럴도 스캐너 오탐 방지차 미기재). 파일명으로만 참조. (키는 bandit25 홈에 제공된 것이라 "secret 획득"이 목표가 아니라 "제한 셸 탈출"이 목표임에 유의.)

### 6. Why It Works

감옥의 설계 의도는 "사용자를 pager에 가둬 임의 명령 실행을 막는다"였다. 두 겹의 방어가 있었다: ① 로그인 셸을 `more`로 교체(`exec`) — 셸 프롬프트 자체를 제거, ② `$SHELL`을 showtext로 오염 — 하위 프로그램의 셸-탈출 기능(`!`, `:sh`)을 무력화. 하지만 `more`는 **editor를 띄우는 `v`** 를 가졌고, editor는 실행 프로그램을 `$SHELL`이 아닌 **`$EDITOR`/`$VISUAL`** 로 고른다 → 첫 겹 우회. 그리고 vi의 `shell`은 **런타임에 바꿀 수 있는 옵션** → 둘째 겹(`$SHELL` 오염) 우회. 즉 "프로그램에 다른 프로그램을 띄우는 기능이 남아 있고, 그 선택 경로가 관리자 통제 밖(사용자 재설정 가능)"이면 감옥은 샌다.

### 7. Edge Cases / Limitation (= 이번 세션 삽질 로그)

- **resize 타이밍**: `more`는 시작 시점의 pty 크기를 읽는다. **큰 창으로 접속한 뒤** 줄이면 이미 늦음(more가 "다 들어감" 판정 후 종료). 반드시 **접속 전** 창 축소. (JY가 "작게 해도 close된다" 막힌 지점 — 원인은 순서였다.)
- **"text.txt 1줄" 착각**: 접속 시 뜨는 OTW 로고/Welcome은 **SSH MOTD**지 `text.txt`가 아니다. text.txt는 여러 줄 아트라 창을 충분히 줄이면 넘친다. (만약 진짜 1줄이면 터미널 최소 높이 때문에 어떤 창으로도 페이징 불가 → 레벨이 안 풀림 = 모순.)
- **`!command` 전면 실패**: more의 `!`는 `$SHELL`(=showtext) 경유라 `cat`/`pwd` 등 **아무것도 실행 안 됨**, 아트만 재출력. 이게 "명령이 씹혔다"는 신호. → `$SHELL` 안 거치는 `v`로 전환이 정답.
- **vi `:sh`도 실패**: 같은 `$SHELL` 트랩. `:set shell?`로 오염값 확인 후 `:set shell=/bin/bash` 선행 필수.
- **클립보드 / 마우스 선택 안 됨**: 원격 vim의 `y`(yank)는 vim register지 OS(⌘) 클립보드가 아님(+clipboard·$DISPLAY 필요, SSH 너머라 서버 클립보드일 뿐). 터미널 드래그+⌘C도 vim(또는 tmux)이 `mouse=a`로 가로채면 실패 → `:set mouse=` 또는 **Option-드래그**(iTerm2/Terminal.app)로 터미널에 선택권 반환.
- **`ssh host "cmd"` 도 무력**: bandit26에 원격 명령을 붙여도 `$SHELL`(showtext)이 `showtext -c "cmd"`로 받아 인자 무시·`exec more`. 로그인 셸이 정상 셸이 아니면 원격-명령 실행 자체가 안 된다(Level 18의 `.bashrc` 우회와는 다른 벽).

---

## [Phase 3] Formal Summary (EN)

> [!definition] Restricted shell escape via `$SHELL` inheritance
> A restricted login program confines a user to a subprocess-spawning binary `B` (here `more`). It hardens escape by (i) `exec`-ing `B` so no shell prompt exists, and (ii) setting `$SHELL` to itself so any `$SHELL`-routed escape re-enters the jail. The jail leaks **iff** `B` can launch a program `E` whose executable path is resolved from a source **other than** `$SHELL` **and** reconfigurable by the user. `more`'s `v` launches `E=$EDITOR` (bypassing (ii)); `vi`'s `shell` is a user-settable option (`:set shell=/bin/bash`), so `E` spawns an unrestricted shell.

> [!theorem] The poison propagates by variable, the break is by option
> Every `$SHELL`-consulting escape (`more:!`, `vi::sh`, `vi::!`) evaluates `exec($SHELL,-c,cmd)` = `exec(showtext,…)` = `exec(more,…)` — a fixed point returning to the jail. The escape succeeds only along a path where the spawned program's identity is **not** a function of `$SHELL`. `vi`'s `shell` option is such a path: it is initialized from `$SHELL` but is **mutable state**, so reassigning it severs the dependency. ∴ jail-persistence requires *both* env poisoning *and* the absence of any user-mutable program-selection knob. □

---

## [Phase 4] Better Methods

**Current approach** (used above): 창 축소 → `more` `v` → vi `:set shell=/bin/bash` → `:sh` → `cat`. 진짜 셸을 얻는 정공법.

**Alternative 1**: vi에서 셸 없이 **파일을 직접 읽기**
```vim
:e /etc/bandit_pass/bandit26
"   vi로 password 파일을 바로 연다 — 셸 spawn 불필요. 읽기만 목적이면 최소 권한
:r /etc/bandit_pass/bandit26
"   현재 버퍼에 파일 내용을 삽입해서 보기
```
Trade-off: 셸을 안 얻으니 이후 탐색(bandit27-do 등)은 불가. "이번 password만" 목적이면 가장 간결·안전. 지속 접근이 필요하면 `:sh` 방식.

**Alternative 2**: `less`가 페이저였다면 `!`가 아니라 `v`/`:!` 대신 `less`의 `v`도 동일. 페이저 무관하게 **GTFOBins** 항목대로:
```
# more/less/man 공통: v → 편집기 → 편집기의 셸 탈출
# awk/find/vim 등 SUID·제한환경에서 자주 재사용되는 패턴
```
Trade-off: 원리는 동일(subprocess spawn), 바이너리별 키/명령만 다름. GTFOBins가 그 사전.

**Most elegant**:
```vim
" more에서 v 진입 후, vi 한 줄:
:e /etc/bandit_pass/bandit26
```
Why elegant: 목표가 "password 읽기"뿐이면 셸조차 필요 없다. 감옥이 준 editor로 **읽기 권한 그대로** 목표 파일을 열면 끝 — 최소 도구, 최소 흔적.

---

## [Phase 5] Lessons Learned

1. **로그인 셸은 신뢰 경계다**: `/etc/passwd` 마지막 필드가 정상 셸이 아니면 접속 즉시 종료·원격명령 무력 등 온갖 이상 현상의 원인. 막히면 **거기부터** 본다.
2. **`exec`는 돌아갈 곳을 없앤다**: 셸이 자신을 `more`로 교체 → 프롬프트 부재·`more` 종료 시 세션 종료·`exit 0` dead code. 즉시-종료 현상의 정체.
3. **pager/editor = 탈출 벡터**: subprocess를 띄우는 능력이 남으면 감옥은 샌다. `more`,`less`,`vi`,`man`,`awk`,`find`… → **GTFOBins**.
4. **오염은 변수로 전파, 돌파는 옵션으로**: `$SHELL` 오염이 `!`·`:sh`를 다 막아도, vi의 **재설정 가능한 `shell` 옵션**이 그 사슬을 끊는다. "셸 경로를 어디서 읽나"를 항상 물어라.
5. **페이저는 파일≤화면이면 `cat`처럼 즉시 끝난다**: 페이징을 유도하려면 **접속 전** 창을 파일보다 작게. more는 시작 시 크기를 한 번 읽는다(나중 resize 무효).

### Quiz

**Q**: (a) bandit26에 `ssh … "id"`로 원격 명령을 붙여도 `id`가 실행되지 않는 이유는? (b) `more`의 `!cat …`와 vi의 `:sh`가 **둘 다** 실패하는 공통 원인은 무엇이며, vi에서만 탈출이 가능했던 이유는? (c) 접속 후 창을 줄였는데 `more`가 여전히 즉시 종료된다면 원인은?

> [!tip]- 풀이
> **(a)** bandit26의 로그인 셸 = `$SHELL` = `/usr/bin/showtext`. `ssh host "id"`는 원격에서 `$SHELL -c "id"` = `showtext -c "id"`를 돌리는데, showtext는 인자를 무시하고 `exec more ~/text.txt`. 그래서 `id`는 실행조차 안 되고 more가 뜬다. 문법이 아니라 **로그인 셸이 정상 셸이 아니라서**.
>
> **(b)** 공통 원인: 둘 다 **환경변수 `$SHELL`(=showtext)** 을 실행한다 → showtext가 `exec more` → 감옥 복귀. vi에서 뚫린 이유: vi의 `shell`은 **환경변수가 아닌 재할당 가능한 내부 옵션**이라 `:set shell=/bin/bash`로 `$SHELL` 의존을 끊고 진짜 셸을 지정할 수 있었다. (more의 `!`엔 그런 옵션이 없어 못 뚫는다.)
>
> **(c)** `more`는 **시작 시점**에 pty 세로 크기를 한 번 읽는다. 큰 창으로 접속한 뒤 줄이면 more는 이미 "파일이 다 들어감" 판정 후 종료한 상태. **접속 전에** 창을 줄여 more가 처음부터 작은 크기로 시작하게 해야 한다.
>
> 핵심: **감옥의 벽은 `$SHELL`로 전파되고, 문은 "셸을 $SHELL이 아닌 다른 데서 고르는" 경로(vi의 v + shell 옵션)로 열린다.**

> [!flashcard]
> **Q**: 로그인 셸이 `exec more ~/text.txt`인 restricted 환경에서 진짜 셸을 얻는 표준 경로는?
> **A**: 창을 파일보다 작게 해 more를 페이징시킨 뒤 `v`(→ `$EDITOR`=vi, `$SHELL` 우회) → vi에서 `:set shell=/bin/bash` → `:sh`. pager→editor→shell 체인(GTFOBins).

> [!flashcard]
> **Q**: more의 `!cmd`와 vi의 `:sh`가 restricted 환경에서 실패하는 이유는?
> **A**: 둘 다 `$SHELL`을 실행하는데 그 값이 오염된 `/usr/bin/showtext`라, 명령 대신 `exec more`로 감옥에 복귀. 돌파는 `$SHELL`을 안 쓰는 경로(vi `v` 진입 + `:set shell` 재설정).

> [!flashcard]
> **Q**: `more`가 파일을 페이징하지 않고 즉시 종료하는 조건은?
> **A**: 파일 줄 수 ≤ 터미널 세로줄 수(한 화면에 다 들어감) → `cat`처럼 전량 출력 후 종료. more는 시작 시 크기를 한 번 읽으므로 페이징 유도는 **접속/실행 전** 창 축소로.

---

## Links

### Tools Used
- [[Tools/ssh]]
- [[Tools/more]]
- [[Tools/vi]]
- [[Tools/cat]]

### Concepts Introduced (first encountered here)
- [[Concepts/Linux/Restricted_Shell_Escape]] (lite note — GTFOBins pager/editor escape + `$SHELL` 상속 트랩)

### Concepts Applied (reused from earlier)
- [[Concepts/Network/SSH_Key_Authentication]] (L13 — `-i` private key로 bandit26 접속)
- [[Concepts/Linux/Shell_Fundamentals]] (login shell, `$SHELL`, `exec`, `$EDITOR` — lite note)
- [[Concepts/Linux/Shell_Initialization]] (L18 — 거기선 `.bashrc` 트랩, 여기선 login-shell 자체가 트랩)

### Navigation
- **Prerequisite**: [[Level_24]]
- **Next**: [[Level_26]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit26.html
- GTFOBins — https://gtfobins.github.io/ (`more`, `vi`, `less` 항목: shell escape)
- `more(1)` (`!`,`v` commands); `vi(1)`/`vim(1)` (`:set shell`, `:sh`, `:e`); `passwd(5)` (login-shell 필드)
