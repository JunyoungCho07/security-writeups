---
date: 2026-07-21
wargame: Bandit
level: 32
title: "Bandit Level 32 → 33"
difficulty: ★★☆
time_spent: 10min
tags: [bandit, linux, restricted-shell, shell-escape, uppercase-shell, positional-parameter, dollar-zero, setuid, filter-invariant]
status: 🟡 developing
tools_used: [file, cat]
new_concepts: []
prerequisites: [Level_31, Level_25, Level_19]
---

# Bandit Level 32 → 33

## [Phase 1] Executive Summary

- **Goal**: bandit32의 로그인 셸이 **"UPPERCASE SHELL"** — 입력을 **전부 대문자로 바꾼 뒤** `sh -c`로 실행한다. `ls`→`LS`, `whoami`→`WHOAMI`처럼 모든 소문자 명령이 존재하지 않는 명령이 돼 깨진다. 이 감옥을 탈출해 `/etc/bandit_pass/bandit33`을 읽어야 한다.
- **Key Skill**: **필터의 고정점(invariant) 입력** `$0`. `$0`은 (1) **소문자가 없어** 대문자화를 그대로 통과하고, (2) **"지금 이 셸이 불린 이름"**(=`sh`)으로 확장돼 **새 셸을 띄운다**. 그 새 셸은 대문자화를 안 하므로 탈출 완료. 그리고 `uppershell`이 **setuid(bandit33)**라 그 새 셸은 bandit33 권한 → password 읽기.
- **Tags**: `[Restricted_Shell_Escape]`(L25 reapply — 이번 필터는 pager가 아니라 case-transform), `[Setuid]`(L19 reapply), `[Shell_Fundamentals]`(`$0` positional parameter)

[Cognitive Validation]
- **Limit Test**: 입력에 소문자가 **하나라도** 있으면 대문자화가 이를 망가뜨린다. 소문자가 **0개**인 입력(`$0`)만이 필터를 무손상 통과 — 지배 변수는 "입력이 case-transform의 **고정점**인가".
- **Control Knob**: 필터가 건드리는 문자 집합(소문자 a–z). `$0`은 그 밖(`$`,`0`)이라 불변. 같은 원리로 `${0}`,`$SHELL`(값이 셸 경로면) 등 소문자 없는 표현이 후보.
- **Nullity**: `$0`이 **빈 값**이거나 셸이 아닌 걸 가리켰다면 탈출 불가. `sh -c`의 `$0`은 그 셸의 argv[0]=`sh`라 실행 시 셸이 재기동된다(고정점이 곧 탈출구가 되는 구조).

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**Restricted shell escape — case-transform 필터 우회 + setuid.** L25(pager `more`→vi)와 같은 "제한 셸 탈출" 계열이지만, 벽의 종류가 다르다. 여기 벽은 **입력을 대문자로 바꾸는 변환 필터**다. 이런 "입력을 변형해 무력화하는" 필터의 정석 우회는 **변환의 고정점(fixed point / invariant)을 찾는 것** — 변환해도 그대로인 입력. 소문자→대문자 변환의 고정점은 "소문자가 없는 문자열"이고, 그중 **셸을 재기동하는** 것이 `$0`이다. 탈출 후 권한은 `uppershell`의 **setuid**가 제공한다(L19의 do-wrapper와 같은 EUID 상승 토대).

### 2. Definition (Formal, EN)

bandit32's login shell is `uppershell`, a **setuid** ELF owned by bandit33. It reads a line, maps every character with `toupper()`, and executes the result via `sh -c` (Debian `dash`; hence the `sh: N:` error prefix). Thus user input `cmd` becomes `sh -c "CMD"`. The upper-casing is a **surjective, non-injective transform** on the input alphabet; to defeat it one supplies a **fixed point** — a string invariant under `toupper` — that is also useful. `$0` qualifies: it contains no lowercase letters (so `toupper($0)==$0`), and within `sh -c '$0'` the special parameter `$0` expands to the shell's own `argv[0]` (`sh`), so the command *is* `sh` → a fresh interactive shell that applies no upper-casing. Because `uppershell` is setuid (and makes the elevated uid sticky, see §7), the spawned shell runs as bandit33, granting read of `/etc/bandit_pass/bandit33`.

### 3. Intuition (KR)

간수가 "네가 말하는 모든 걸 대문자로 바꿔 실행한다"는 규칙을 걸었다. `ls`라 말하면 `LS`가 돼 아무 문도 안 열린다. 이길 방법은 **"대문자로 바꿔도 안 변하는 말"**을 찾는 것 — 소문자가 없는 말. 그중 `$0`은 특별하다: 셸에게 `$0`은 **"너 자신의 이름"**이라, 그걸 실행하라고 하면 셸이 **자기 복제(새 셸)**를 낳는다. 새 셸엔 대문자 규칙이 없다 → 탈출. 게다가 이 감옥(`uppershell`)은 **주인이 bandit33인 setuid** 프로그램이라, 낳은 새 셸도 bandit33의 권한을 물려받는다.

### 4. Theory (Mechanism)

파이프라인 확증(로컬 재현 포함):

1. **필터 구조**: `uppershell`은 `입력 → toupper → sh -c "<대문자>"`. 증거는 `$home` 줄 — `$home`이 `$HOME`으로 대문자화된 **뒤** sh가 그 변수를 확장해 `/home/bandit32`(디렉터리)를 실행하려다 실패("Permission denied"). 즉 **대문자화가 먼저, 변수확장·실행은 그 다음**. (로컬: `sh -c '$HOME'` → `is a directory`, exit 126.)
2. **왜 소문자 명령이 다 깨지나**: `ls`→`LS`, `whoami`→`WHOAMI`. Linux(대소문자 구분 fs)엔 그런 실행 파일이 없어 sh가 실행 실패.
3. **`$0`의 고정점 성질**: `$`,`0`은 대문자로 바꿔도 그대로 → 필터 무손상 통과.
4. **`$0`의 재기동 성질**: `sh -c '<str>'`에서 `$0` = 그 셸의 argv[0] = **`sh`** (로컬: `sh -c 'echo [$0]'` → `[sh]`). 따라서 `sh -c '$0'`의 실제 명령은 **`sh`** → **새 대화형 셸 기동**(로컬: `printf 'echo X\n' | sh -c '$0'` → 새 sh가 `X` 실행). 새 셸은 대문자화를 안 함 → `$ ` 프롬프트에서 소문자 명령 정상.
5. **권한(setuid)**: `file uppershell` → **setuid ELF**(소유자 bandit33). bandit32 로그인 시 uppershell이 **euid=bandit33**으로 실행 → 그 자식 셸(`$0`의 sh, 이후 bash)이 bandit33 권한 상속 → `cat /etc/bandit_pass/bandit33` 성공.

인과: 필터가 소문자를 파괴(조건) → 고정점 `$0`만 생존(B) → `$0`이 `sh`로 확장돼 새 셸 기동(C) → setuid로 그 셸이 bandit33(D) → password read(E).

### 5. Solution

```bash
# bandit32 접속 → "WELCOME TO THE UPPERCASE SHELL", 프롬프트 '>>'
>> ls                 # → sh -c 'LS' → 실패 (대문자 명령 없음)
>> $home              # → sh -c '$HOME' → /home/bandit32 (디렉터리) 실행 시도 → 실패
                      #    ↑ '대문자화 후 sh -c 변수확장·실행' 파이프라인의 증거

>> $0                 # 고정점: 대문자화 무손상 통과. $0 → 'sh' → 새 셸 기동
$ ls                  # ← 새 sh(대문자화 없음). 이미 탈출 완료!
uppershell
$ cat /etc/bandit_pass/bandit33
<password masked>     # ← Level 33 password  (여기서 이미 끝. bandit33 권한)

# (선택) 더 편한 셸로:
$ bash
bandit33@bandit:~$ file uppershell
uppershell: setuid ELF 32-bit LSB executable, Intel i386, ... not stripped
```

> [!warning] Password Masking & 최소 풀이
> bandit33 password는 `<password masked>`. **탈출은 `$0` 하나로 끝**이며, 이어 `bash`/`zsh`는 접근을 준 게 아니라 셸 교체일 뿐(그 서버에 `zsh`는 없어 "Permission denied"). 최소 풀이 2줄: `$0` → `cat /etc/bandit_pass/bandit33`.

### 6. Why It Works

감옥의 방어는 "입력을 대문자화해 임의 명령을 무력화"였다. 하지만 이 방어는 **입력을 파괴적으로 변형하는** 종류라, **변형의 고정점**을 남긴다: 소문자 없는 문자열. 그중 `$0`은 셸의 특수 파라미터로 **"자기 자신의 이름"**을 뜻해, 실행하면 셸이 재기동된다 — 즉 고정점이 곧 탈출구다. 새 셸엔 필터가 없으니 대문자화가 사라지고, `uppershell`의 **setuid**가 그 셸에 bandit33 권한을 실어 password를 읽게 한다. 요지: **"입력을 변형해 막는 필터는, 그 변형의 불변점을 통해 샌다."**

### 7. Edge Cases / Limitation

- **`bash`가 권한을 유지한 이유(미묘)**: 보통 `bash`는 시작 시 `euid≠ruid`(setuid 상황)면 **euid를 ruid로 떨어뜨린다**(`-p` 없으면). 그런데 plain `bash`에서도 bandit33이 유지·`cat` 성공했다 → `uppershell`이 euid뿐 아니라 **real uid까지 bandit33으로 고정**(`setreuid`/`setresuid`)했다는 뜻(그래야 bash가 "ruid==euid"라 안 떨군다). *not stripped*이니 `objdump -d uppershell`/gef로 `system` 직전 `setre/uid` 호출 확인 가능. euid만 올렸다면 `bash -p`가 필요했을 것.
- **필터 이전 vs 이후**: 변수확장은 **대문자화 뒤** sh가 한다. 그래서 `$home`은 `$HOME`으로 바뀐 뒤 확장돼 디렉터리를 실행 시도. `$0`도 대문자화 뒤 sh가 확장 → `sh`.
- **다른 고정점 후보**: `${0}`, 값이 셸 경로인 소문자-없는 변수 등. 소문자를 하나라도 포함하면 실패.
- **`sh: N:` 프리픽스**: Debian `dash`가 `sh -c`로 실행 중이라는 표시(그래서 `$0`=`sh`, `$ ` 프롬프트도 dash).
- **case-insensitive fs면 다르다**: 만약 fs가 대소문자 무시라면 `LS`가 `ls`에 매칭돼 필터가 무력화됐을 것(bandit 서버는 Linux ext4=대소문자 구분이라 필터가 유효).

---

## [Phase 3] Formal Summary (EN)

> [!definition] Filter-invariant escape of a case-transforming shell
> A restricted shell that applies a destructive input transform `T` (here `toupper`) before executing via `sh -c` leaks through any **fixed point** of `T` (`T(x)==x`) that also yields code execution. `$0` is such a fixed point (no lowercase) and, under `sh -c`, expands to the shell's own name (`sh`), so executing it respawns an unfiltered shell.

> [!theorem] Fixed point + self-reference = escape; setuid = privilege
> If a jail runs `sh -c "T(input)"`, then for any `x` with `T(x)=x` the jail effectively runs `sh -c "x"`; choosing `x=$0` (whose `sh -c` expansion is `sh`) spawns a fresh shell free of `T`. If the jail binary is setuid to `U` and makes the elevated uid **real** (setreuid), the spawned shell — and even a subsequently exec'd `bash` (which would otherwise drop effective-only privileges) — runs as `U`. ∴ escape (fixed point) and privilege (sticky setuid) are independent, and both hold here. □

---

## [Phase 4] Better Methods

**Current approach** (used above): `$0` → 새 셸 → `cat`. 고정점 한 토큰으로 탈출.

**Most elegant** (최소 2줄):
```bash
>> $0
$ cat /etc/bandit_pass/bandit33
```
Why elegant: 탈출(고정점 `$0`)과 목표(password read)만. `bash`/`zsh` 불필요.

**Alternative** (탈출 후 도구 확인 — 리버싱 검증):
```bash
$ objdump -d uppershell | grep -iE 'setre|setres|setuid|system'   # 권한 sticky 여부 확인 (not stripped)
# 또는 gef/pwndbg (서버에 설치돼 있음)로 system() 직전 uid 세팅 관찰
```
Trade-off: password엔 불필요하나, "왜 bash도 bandit33인가"를 **증거로** 확인. (Better Methods는 항상 "다른 각도"를 남긴다.)

**Counter-opinion**: "`$0` 다음 `bash`가 접근을 준다"는 흔한 오해 — 아니다. **탈출은 `$0`에서 끝**났고 그 시점에 이미 bandit33 셸이다. `bash`는 편의상 셸 교체일 뿐.

---

## [Phase 5] Lessons Learned

1. **변형 필터는 고정점으로 샌다**: 입력을 `toupper`로 파괴하는 감옥은 "소문자 없는 입력"(그 변환의 불변점)에 뚫린다. 필터를 만나면 **"이 변환이 안 바꾸는 입력"**을 물어라.
2. **`$0` = "이 셸의 이름"**: `sh -c`에선 `$0`=`sh` → 실행 시 **새 셸 기동**. 고정점이면서 동시에 탈출구(자기참조).
3. **탈출 ≠ 셸 종류**: `$0` 직후 이미 bandit33 셸. `bash`/`zsh`는 접근이 아니라 교체(zsh는 그 서버에 부재).
4. **setuid + sticky uid**: `uppershell`이 real uid까지 bandit33으로 고정했기에 plain `bash`도 권한 유지(아니면 `bash -p` 필요). *not stripped* → 디스어셈블로 확인.
5. **파이프라인 순서**: 대문자화 → `sh -c` 변수확장·실행. `$home`→`$HOME`→디렉터리 실행이 그 증거.

### Quiz

**Q**: (a) 왜 하필 `$0`인가 — 이 감옥이 걸어둔 변환의 관점에서 두 성질로 답하라. (b) `$0` 다음의 `bash`가 "접근을 준다"는 이해가 왜 틀렸나? (c) 보통 setuid 프로그램에서 spawn한 `bash`는 권한을 잃는데, 여기선 왜 유지됐는가?

> [!tip]- 풀이
> **(a)** ① **고정점**: 감옥은 입력을 `toupper`로 변형하는데 `$0`은 소문자가 없어 `toupper($0)=$0`, 무손상 통과. ② **자기참조 실행**: `sh -c '$0'`에서 `$0`은 그 셸의 argv[0]=`sh`로 확장 → 명령이 `sh` 자체가 돼 **새(비필터) 셸 기동**. 두 성질이 겹쳐 "필터를 통과하면서 동시에 탈출"이 된다.
>
> **(b)** 탈출은 `$0`에서 이미 완료다 — 직후 `$ ` 프롬프트에서 `ls`가 먹혔고 거기서 바로 `cat /etc/bandit_pass/bandit33` 하면 끝. `bash`는 접근을 준 게 아니라 dash를 bash로 **교체**했을 뿐(그 서버에 `zsh`는 없어 실패). 접근을 준 건 setuid이고, 탈출을 준 건 `$0`이다.
>
> **(c)** `uppershell`이 setuid로 euid=bandit33을 얻은 뒤 **real uid까지 bandit33으로 세팅**(`setreuid`/`setresuid`)했기 때문. `bash`는 `euid≠ruid`일 때만 euid를 떨구는데, ruid==euid==bandit33이면 떨굴 게 없다. euid만 올렸다면 `bash -p`가 필요했을 것.
>
> 핵심: **파괴적 입력필터는 그 변환의 고정점(+자기참조)으로 뚫리고, 권한은 setuid의 real-uid 고정으로 유지된다.**

> [!flashcard]
> **Q**: 입력을 대문자화해 `sh -c`로 실행하는 제한 셸을 탈출하는 한 토큰과 그 두 성질은?
> **A**: `$0`. (1) 소문자가 없어 `toupper` 고정점(필터 무손상 통과), (2) `sh -c`에서 `$0`=`sh`로 확장돼 **새 셸 기동**. 자기참조 고정점이 곧 탈출구.

> [!flashcard]
> **Q**: setuid 프로그램이 spawn한 `bash`가 권한을 유지하려면 무엇이 필요한가?
> **A**: real uid도 elevated uid로 세팅돼야 함(`setreuid`/`setresuid`). 아니면 bash가 시작 시 `euid→ruid`로 떨어뜨림(`-p` 없을 때). uppershell은 real uid까지 bandit33으로 고정 → plain bash도 bandit33.

---

## Links

### Tools Used
- [[Tools/file]] (`uppershell`이 setuid ELF·not stripped임을 확인)
- [[Tools/cat]] (`/etc/bandit_pass/bandit33` 읽기)
- (`$0` 셸 트릭; 탈출 후 `bash`)

### Concepts Introduced (first encountered here)
- [[Concepts/Linux/Process_Creation]] (EOL Q&A 파생 — `$0`/argv0, fork/execve/waitpid, `system()`=`sh -c`, syscall/ABI/userland/architecture)
- [[Concepts/Linux/Tty_And_Terminals]] (EOL Q&A 파생 — interactive vs non-interactive, foreground/isatty; "`$0`만 쳐도 무출력"의 정체)

### Concepts Applied (reused from earlier)
- [[Concepts/Linux/Restricted_Shell_Escape]] (L25 — 거기선 pager/editor 필터, 여기선 case-transform 필터; 공통 원리 "필터의 탈출 벡터")
- [[Concepts/Linux/Setuid]] (L19 — EUID 상승; 여기선 real uid까지 고정해 bash 통과)
- [[Concepts/Linux/Shell_Fundamentals]] (`$0` positional parameter, `sh -c` 변수확장 순서)

### Navigation
- **Prerequisite**: [[Level_31]] (직전 레벨), [[Level_25]] (restricted shell escape 원형), [[Level_19]] (setuid)
- **Next**: [[Level_33]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit33.html
- `dash(1)` / POSIX `sh` — special parameter `$0` (name of shell), `sh -c` operand semantics
- `bash(1)` — "privileged mode": dropping effective uid when `euid != uid` unless `-p`; `setreuid(2)`/`setresuid(2)`
- GTFOBins / restricted-shell escape references (case-filter bypass는 일반 패턴)
