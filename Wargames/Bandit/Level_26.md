---
date: 2026-07-20
wargame: Bandit
level: 26
title: "Bandit Level 26 → 27"
difficulty: ★★☆
time_spent: 10min
tags: [bandit, linux, setuid, privilege-escalation, do-wrapper, env-wrapper, elf, static-analysis, file, strings]
status: 🟡 developing
tools_used: [file, cat, id, whoami, ls]
new_concepts: []
prerequisites: [Level_25, Level_19]
---

# Bandit Level 26 → 27

## [Phase 1] Executive Summary

- **Goal**: bandit26 홈의 **setuid 실행파일** `bandit27-do`(소유자 bandit27)로 bandit27 권한으로 임의 명령을 실행 → `/etc/bandit_pass/bandit27` 읽기. Level 19의 `bandit20-do`와 **완전히 같은 do-wrapper 패턴**의 재등장. 단, 여기 오려면 먼저 **L25의 restricted-shell 탈출**(`more`→`vi :set shell`→`:sh`)로 bandit26 셸을 얻어야 한다 — 위 붙여넣기 맨 위 `:sh` / `[No write since last change]`가 그 탈출의 꼬리.
- **Key Skill**: setuid 바이너리로 **EUID 상승** → `./bandit27-do cat /etc/bandit_pass/bandit27`. 부수 스킬: `file`+`strings`로 **소스 없이 바이너리 동작 추론**(이 빌드는 내부가 `execv("/usr/bin/env", …)` 래퍼임이 드러남).
- **Tags**: `[Setuid]`(reapply, L19), `[Restricted_Shell_Escape]`(prereq, L25), `[Static_Binary_Triage]`(file/strings), `[Privilege_Escalation]`

[Cognitive Validation]
- **Limit Test**: setuid 비트가 없으면 `bandit27-do`는 그냥 bandit26 EUID로 돌아 `/etc/bandit_pass/bandit27`(bandit27만 read) 접근 거부. **setuid 비트**(`04000`)가 EUID 상승의 on/off 스위치. 인자를 안 주면 usage만 뜨고 종료(argc 가드).
- **Control Knob**: 지배 변수는 "**실행 시 EUID를 누구로 세팅하나**" = 파일 setuid 비트 × **소유자(bandit27)**. 소유자가 bandit27이라 실행자는 bandit27 권한을 빌린다. `id`로 보면 `uid=bandit26` 유지, `euid=bandit27`만 상승 — 다이얼이 EUID 한 축만 돌렸다는 직접 증거.
- **Nullity**: `./bandit27-do whoami` → `bandit27`, `./bandit27-do id` → `euid=11027(bandit27)`. EUID가 실제로 바뀌었다는 관측 가능한 증거. 반대로 `./bandit27-do is`(오타) → `env: 'is': Permission denied` — 래퍼가 인자를 **셸이 아니라 `env`에게** 넘겨 프로그램으로 exec하려다 실패한 흔적(=내부 구현 누설).

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**setuid privilege delegation** — Level 19에서 만난 "소유자 권한으로 임의 명령을 실행해 주는 미니-`sudo`" 패턴의 재적용. 새로운 각도는 두 가지: (1) **정찰/리버싱** — 소스가 없는 setuid ELF의 동작을 `file`(파일 종류·아키텍처·setuid·strip 여부)과 `strings`(임베디드 문자열)로 **역추론**하는 static triage; (2) **wrapper 구현 디테일** — 이 빌드는 `system()`(셸 경유)이 아니라 `execv("/usr/bin/env", argv)`(셸 없이 `env`가 첫 인자를 프로그램으로 exec)로 구현되어, **셸 메타문자가 먹지 않는다**는 실전 함의.

### 2. Definition (Formal, EN)

The **setuid bit** (mode `04000`, shown as `s` in the owner-execute slot: `-rwsr-x---`) makes `execve` set the process **effective UID (EUID)** to the file *owner's* UID while leaving the **real UID (RUID)** as the caller's. Kernel access checks use EUID. `bandit27-do` is owned by bandit27 with setuid set; it forwards its arguments to `/usr/bin/env`, which then `execvp`s the first argument as a program — all under EUID=bandit27. Reading `/etc/bandit_pass/bandit27` (owner-read-only, owner=bandit27) therefore succeeds.

`file`/`strings` static triage confirms the shape without source: `file` reports `setuid ELF 32-bit LSB executable, Intel i386 … not stripped`; `strings` surfaces `execv`, `printf`, `/usr/bin/env`, the literal `env`, the usage text `Run a command as another user.` / `Example: %s id`, the source stem `bandit27.c`, and `GLIBC_2.34` — enough to reconstruct the wrapper's control flow.

### 3. Intuition (KR)

보통 프로그램은 **실행한 사람의 권한**으로 돈다. setuid는 "이건 **주인 권한**으로 돈다"는 특수 표식 — `bandit27-do`의 주인이 bandit27이라, bandit26이 실행해도 그 안에선 bandit27이 된다. **주인 열쇠를 잠깐 빌려** bandit27 전용 password 파일을 여는 것.

리버싱 직관: 상자(바이너리)를 못 열어도 **겉면 라벨(`file`)과 상자 안에서 새어나온 쪽지(`strings`)**만으로 내용물을 짐작한다. 라벨엔 "setuid, 32-bit, 심볼 안 지움", 쪽지엔 "`/usr/bin/env` 를 부른다"라고 적혀 있으니 — 이건 "네 명령을 `env`한테 대신 실행시키는, 권한만 bandit27인 배달부"다.

### 4. Theory (Mechanism)

인과 사슬:

1. **선행 조건(L25)** — bandit26의 로그인 셸은 `more` 감옥. `more`→`v`(vi)→`:set shell=/bin/bash`→`:sh`로 탈출해 **bandit26 실셸** 확보(붙여넣기 최상단 `:sh`). 이 프롬프트가 있어야 `./bandit27-do`를 돌릴 수 있다.
2. **정찰** — `ls` → `bandit27-do`, `text.txt`. `file *`:
   - `bandit27-do: setuid ELF 32-bit LSB executable, Intel i386 … not stripped` → **setuid 켜짐**(핵심), i386, 심볼 미제거(리버싱 쉬움).
   - `text.txt: ASCII text` → 미끼/무관.
3. **동작 추론** — `cat bandit27-do`는 바이너리를 raw로 토해내 터미널을 깨뜨리지만(제어문자), 그 안에서 `execv`·`/usr/bin/env`·`Run a command as another user.`·`Example: %s id`·`bandit27.c` 같은 **문자열**이 보인다. 재구성한 구현:
   ```c
   // bandit27.c (추정)
   int main(int argc, char **argv) {
       if (argc < 2) { printf("Run a command as another user.\n  Example: %s id\n", argv[0]); return 1; }
       execv("/usr/bin/env", argv);   // 셸 없이 env에게 위임 → env가 argv[1]을 프로그램으로 exec
   }
   ```
4. **EUID 상승 검증** — `./bandit27-do whoami` → `bandit27`(=`geteuid()`), `./bandit27-do id` →
   `uid=11026(bandit26) gid=11026(bandit26) euid=11027(bandit27) groups=11026(bandit26)`.
   RUID=bandit26 그대로, **EUID만 bandit27**. egid는 안 올랐으니 setuid(04000)이지 setgid(02000)가 아님 — 정확히 필요한 만큼만 상승.
5. **회수** — `./bandit27-do cat /etc/bandit_pass/bandit27` → `cat`이 EUID=bandit27로 파일을 열어 password 획득.

### 5. Solution

```bash
# ── 선행(L25): more 감옥 탈출로 bandit26 실셸 확보 ──
:set shell=/bin/bash                   # vi(more→v로 진입) 안에서 shell 옵션을 진짜 셸로 덮어씀
:sh                                    # → /bin/bash 기동 (감옥 탈출)
[No write since last change]           # vi가 미저장 버퍼를 알리는 정상 메시지 (경고일 뿐, 셸은 뜸)
bandit26@bandit:~$                      # ← bandit26 실셸

# ── 1) 정찰 ──
bandit26@bandit:~$ ls
bandit27-do  text.txt

bandit26@bandit:~$ cat /etc/bandit_pass/bandit26
<password masked>                       # bandit26 password (이미 L25에서 획득한 값 재확인)

bandit26@bandit:~$ file *
bandit27-do: setuid ELF 32-bit LSB executable, Intel i386, ... not stripped
#            └ 'setuid' = 04000 비트 켜짐(핵심). i386=32bit. 'not stripped'=심볼 남음(리버싱 용이)
text.txt:    ASCII text                 # 미끼 — 무관

# ── 2) 바이너리 동작 추론 (cat은 지저분, strings가 정석 — Phase 4 참고) ──
#    cat bandit27-do 로 새어나온 문자열: execv, /usr/bin/env, "Run a command as another user.",
#    "Example: %s id", bandit27.c  →  내부는 execv("/usr/bin/env", argv) 래퍼

bandit26@bandit:~$ ./bandit27-do
Run a command as another user.
  Example: ./bandit27-do id            # argc<2 가드: 인자 없으면 usage

bandit26@bandit:~$ ./bandit27-do is    # 'id' 오타 → env가 'is'를 프로그램으로 exec 시도, 실패
env: 'is': Permission denied           # 'env:' 접두 = 실행 주체가 env임을 확증(=셸 아님)

# ── 3) EUID 상승 검증 ──
bandit26@bandit:~$ ./bandit27-do whoami
bandit27                               # whoami=geteuid() → 상승 확인

bandit26@bandit:~$ ./bandit27-do id
uid=11026(bandit26) gid=11026(bandit26) euid=11027(bandit27) groups=11026(bandit26)
#   RUID=bandit26 유지, EUID=bandit27 상승, egid 미상승 → 정확히 setuid(04000)만 동작

# ── 4) 회수 ──
bandit26@bandit:~$ ./bandit27-do cat /etc/bandit_pass/bandit27
<password masked>                       # ← Level 27 password (EUID=bandit27로 read 성공)
```

> [!warning] Password Masking
> bandit26 password(`cat /etc/bandit_pass/bandit26`)와 `bandit27-do`가 뽑아낸 bandit27 password **둘 다** `<password masked>`로. pre-commit hook이 고엔트로피 문자열을 스캔하니, 커밋 전 `git diff`로 두 줄 모두 마스킹됐는지 확인.

### 6. Why It Works

`bandit27-do`는 **setuid 비트 + 소유자 bandit27**이라, `execve` 순간 커널이 프로세스 EUID를 bandit27로 올린다(RUID는 bandit26 유지). 래퍼는 인자를 `/usr/bin/env`에 넘기고, `env`는 첫 인자를 **프로그램 이름**으로 보고 `$PATH`에서 찾아 exec — 이 모든 게 EUID=bandit27 아래서 일어난다. 그래서 `cat`이 bandit27 권한으로 `/etc/bandit_pass/bandit27`(소유자 bandit27만 read)을 연다. setuid가 없었다면 bandit26 EUID로는 접근 거부. 핵심은 L19와 동일한 "**파일 소유권 + setuid = 실행자에게 소유자 권한 위임**", 여기에 "위임 통로가 `env` 경유(셸 없음)"라는 구현 디테일이 얹혔다.

### 7. Edge Cases / Limitation

- **셸이 없다 → 메타문자 무력**: 래퍼가 `system()`이 아니라 `execv("/usr/bin/env", …)`라 **셸을 거치지 않는다**. `./bandit27-do cat /etc/bandit_pass/*`의 `*` 글롭, `;`·`|`·`>` 리다이렉트, `$VAR` 확장이 **전부 리터럴**로 `env`에 전달돼 안 먹힌다. 여러 명령·파이프가 필요하면 `./bandit27-do bash`로 EUID=bandit27 셸을 하나 띄운 뒤 그 안에서.
- **`env: 'is': Permission denied` 의 정체**: `env`는 첫 인자(`is`)를 `$PATH`에서 찾아 exec하려다 실패했다는 뜻(오타 `id`). `env:` 접두가 "실패를 보고한 주체가 `env`"임을 증명 → 래퍼가 정말 `env` 경유임을 확인시켜 줌. (없는 명령이면 보통 "No such file or directory", 찾았으나 실행 불가면 "Permission denied" — 어느 쪽이든 "그 이름의 실행 프로그램을 못 돌렸다"는 신호.)
- **`cat`으로 바이너리 보기 = 터미널 파손**: raw 바이트의 제어문자가 터미널 상태를 망가뜨린다(커서·색·인코딩). 깨졌으면 `reset` 또는 `stty sane`. 정찰은 `strings`/`xxd`/`objdump`가 정석(Phase 4).
- **소유자까지만 상승**: EUID=bandit27이지 root 아님. root 소유 setuid였다면 진짜 root privesc. 여기선 의도된 위임(레벨 설계).
- **setuid 스크립트는 무시됨**: 현대 커널은 `#!` 스크립트의 setuid를 TOCTOU 위험으로 무시 → `bandit27-do`가 **컴파일된 ELF**인 이유. `file`의 "ELF … executable"이 그 조건 충족을 확인해 준다.

---

## [Phase 3] Formal Summary (EN)

> [!definition] Setuid do-wrapper via `env` indirection
> A setuid ELF `W` (mode `04000`, owner `U`) forwards its argv to `execv("/usr/bin/env", argv)`. On `execve`, the kernel sets EUID=`U` (RUID unchanged); `env` then `execvp`s `argv[1]` as a program under EUID=`U`. Thus any caller with execute permission on `W` runs an arbitrary program with `U`'s file-access rights. Because `env` is not a shell, shell metacharacters in the arguments are passed literally and are **not** interpreted.

> [!theorem] Static triage recovers wrapper semantics without source
> For a non-stripped ELF, `file` yields {type, arch, setuid-bit, strip-state} and `strings` yields the embedded literals {`/usr/bin/env`, usage text, `execv`, `bandit27.c`}. The union {setuid} ∪ {`execv("/usr/bin/env", …)`} is sufficient to conclude: "run argv[1] as program `U`." ∴ behavior is inferable from labels + leaked strings alone; opening the box (disassembly) is optional. □

---

## [Phase 4] Better Methods

**Current approach** (used above): `./bandit27-do cat /etc/bandit_pass/bandit27`. L19과 동일한 직공법.

**Alternative 1**: EUID=bandit27 대화형 셸 (여러 작업이 필요할 때)
```bash
./bandit27-do bash        # env가 bash를 exec → EUID=bandit27 셸. 이 안에선 글롭/파이프/리다이렉트 정상 동작
```
Trade-off: 셸이 없어 막혔던 메타문자 문제를 우회. 단 한 password만 목적이면 과함.

**Alternative 2**: 정찰을 `cat` 대신 정석 도구로
```bash
strings bandit27-do       # 임베디드 문자열만 추출 — 터미널 안 깨짐. /usr/bin/env, usage, bandit27.c 확인
strings -n 6 bandit27-do  # -n 6: 6자 이상 문자열만 (노이즈 컷)
file bandit27-do          # setuid 여부·아키텍처·strip 상태 한 줄 요약
ls -l bandit27-do         # -rwsr-x--- 로 's'(setuid) + 소유자 bandit27 직접 확인
objdump -d bandit27-do | grep -A3 env   # 진짜로 확인하려면 디스어셈블 (not stripped라 심볼 보임)
```
Trade-off: `cat`보다 한두 타 더 치지만 터미널 안전 + 정보 정확. static analysis의 기본 셋.

**Alternative 3** (정찰 표준): 시스템의 setuid 바이너리 열거
```bash
find / -perm -4000 -type f 2>/dev/null
#   -perm -4000 : setuid 비트가 '포함'된 파일('-' 접두 = 해당 비트 매칭)
#   -type f     : 일반 파일만 / 2>/dev/null : permission-denied 노이즈 억제(L06 기법)
```
Trade-off: 이번엔 홈에 대놓고 줬지만, 실전 privesc는 이 열거 → GTFOBins 조회가 표준.

**Most elegant**:
```bash
./bandit27-do cat /etc/bandit_pass/bandit27
```
Why elegant: 목표(bandit27 password read)를 setuid 권한 위임 한 번으로 정확히 달성. 셸 없이도 인자 두 개면 충분.

---

## [Phase 5] Lessons Learned

1. **do-wrapper 재등장**: `bandit27-do` = `bandit20-do`(L19)와 같은 "소유자 권한으로 임의 명령" setuid 래퍼. 패턴을 알아보면 즉시 `./wrapper cat <secret>`.
2. **`file`+`strings` = 소스 없는 동작 추론**: `file`로 setuid/arch/strip, `strings`로 `/usr/bin/env`·usage·`bandit27.c`를 읽어 내부 로직 재구성. `cat`은 터미널만 깨뜨린다.
3. **`id`로 RUID/EUID 분리 관측**: `uid=bandit26 … euid=bandit27` — setuid는 EUID 한 축만 올린다(egid 미상승 = setgid 아님).
4. **env-wrapper엔 셸이 없다**: 글롭·파이프·리다이렉트·`$VAR`가 리터럴. 필요하면 `./bandit27-do bash`로 실셸 확보.
5. **두 단계 레벨**: L25 restricted-shell 탈출로 프롬프트를 얻고 → L26에서 setuid 래퍼로 상승. 감옥 탈출과 권한 위임은 별개 스킬의 연쇄.

### Quiz

**Q**: (a) `./bandit27-do cat /etc/bandit_pass/*` 로 글롭을 써서 읽으려 하면 실패한다. 왜인가? (b) `./bandit27-do id` 출력에서 `uid`와 `euid`가 다른데, 어느 쪽이 password 파일 접근을 통과시키며 그 이유는? (c) 소스 없이 이 바이너리가 "env로 명령을 위임한다"는 걸 어떻게 알아냈는가?

> [!tip]- 풀이
> **(a)** 래퍼가 `execv("/usr/bin/env", argv)` — **셸을 안 거친다**. 글롭 `*`은 셸이 확장하는데, 여기선 셸이 없어 `*`이 리터럴 파일명으로 `env`→`cat`에 전달되고 그런 파일은 없으므로 실패. 셸이 필요하면 `./bandit27-do bash` 후 그 안에서.
>
> **(b)** **EUID**(=bandit27)가 통과시킨다. 커널의 파일 접근 검사는 real UID가 아니라 **effective UID** 기준이고, `/etc/bandit_pass/bandit27`은 소유자 bandit27만 read 가능. setuid 비트가 EUID를 bandit27로 올려 그 read를 허가. RUID(bandit26)는 "누가 실행했나"의 기록일 뿐 접근 판정에 안 쓰임.
>
> **(c)** `file bandit27-do` → `setuid ELF … not stripped`(setuid 확인, 심볼 남음). 이어 임베디드 문자열(`strings`, 급하면 `cat`으로도 새어 나옴)에서 `/usr/bin/env`, `execv`, `Run a command as another user.`, `bandit27.c`를 확인 → "argv를 env에 넘겨 exec"라는 로직을 역추론. 디스어셈블(`objdump -d`) 없이 라벨+문자열만으로 충분.
>
> 핵심: setuid는 **EUID**를 소유자로 올려 접근을 위임하고, wrapper의 **실행 경로(env vs shell)**가 무엇이 먹고 안 먹는지를 결정한다. 정찰은 `file`+`strings`부터.

> [!flashcard]
> **Q**: setuid `bandit27-do`로 bandit27 password를 읽는 한 줄은?
> **A**: `./bandit27-do cat /etc/bandit_pass/bandit27`. setuid가 EUID를 bandit27로 올려 `cat`이 소유자-전용 파일을 read. (셸 미경유라 글롭·파이프는 안 먹음.)

> [!flashcard]
> **Q**: 소스 없는 setuid ELF의 동작을 파악하는 first-look 도구 2개와 각각 알려주는 것은?
> **A**: `file`(파일종류·아키텍처·**setuid 비트**·strip 여부) + `strings`(임베디드 문자열: `/usr/bin/env`, usage text, `bandit27.c` → 내부 로직). `cat`은 터미널만 깨뜨린다.

> [!flashcard]
> **Q**: `id` 출력 `uid=11026(bandit26) … euid=11027(bandit27)`에서 파일 접근을 결정하는 UID는?
> **A**: **euid**(effective UID). 커널 접근 검사 기준. setuid가 EUID만 소유자로 올리고 RUID는 호출자 유지 → 여기선 egid도 안 올라 setuid(04000)이지 setgid 아님.

---

## Links

### Tools Used
- [[Tools/file]] (정찰 — setuid/arch/strip 판정)
- [[Tools/cat]] (읽기; 바이너리엔 부적합 → strings 권장)
- [[Tools/strings]] (Better Methods — 임베디드 문자열 추출)
- [[Tools/id]] / [[Tools/whoami]] (EUID 상승 검증)

### Concepts Introduced (first encountered here)
- (없음 — 새 atom 없이 기존 개념 재적용. EOL 시 `env`-wrapper/셸-미경유 위임과 `file`+`strings` static triage는 lite 노트로 승격 후보: [[Concepts/Linux/Static_Binary_Triage]])

### Concepts Applied (reused from earlier)
- [[Concepts/Linux/Setuid]] (L19 — do-wrapper EUID 상승; 여기선 env 경유 구현)
- [[Concepts/Linux/Restricted_Shell_Escape]] (L25 — 이 프롬프트를 얻기 위한 선행 탈출)
- [[Concepts/Linux/Strings_Extraction]] (L09 — 거기선 password 사냥, 여기선 바이너리 동작 추론)
- [[Concepts/Linux/File_Permissions]] (L13 — rwx/특수 비트; setuid의 토대)

### Navigation
- **Prerequisite**: [[Level_25]] (셸 탈출), [[Level_19]] (동일 do-wrapper 패턴)
- **Next**: [[Level_27]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit27.html
- `credentials(7)` / `execve(2)` — real vs effective UID, setuid semantics
- `env(1)` — first operand is the program to exec (no shell); `file(1)`, `strings(1)` — static triage
- GTFOBins — https://gtfobins.github.io (setuid privesc reference)
