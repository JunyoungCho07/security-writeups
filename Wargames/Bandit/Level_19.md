---
date: 2026-07-15
wargame: Bandit
level: 19
title: "Bandit Level 19 → 20"
difficulty: ★★☆
time_spent: 5min
tags: [bandit, linux, setuid, privilege-escalation, permissions]
status: 🟡 developing
tools_used: [whoami, cat, ls]
new_concepts: [Setuid]
prerequisites: [Level_18]
---

# Bandit Level 19 → 20

## [Phase 1] Executive Summary

- **Goal**: 홈의 **setuid 실행파일** `bandit20-do`(소유자 bandit20)를 이용해 bandit20 권한으로 명령 실행 → `/etc/bandit_pass/bandit20` 읽기
- **Key Skill**: setuid 바이너리로 **EUID 상승** → `./bandit20-do cat /etc/bandit_pass/bandit20`
- **Tags**: `[Setuid]`, `[Privilege_Escalation]`, `[File_Permissions]`

[Cognitive Validation]
- **Limit Test**: setuid 비트가 없으면 그냥 bandit19 권한으로 실행 → bandit20 전용 파일 못 읽음. **setuid 비트**가 EUID 상승의 on/off 스위치.
- **Control Knob**: 지배 변수는 **"실행 시 EUID를 누구로 세팅하나"** = 파일의 setuid 비트 × 소유자. 소유자 bandit20 + setuid → 실행자는 bandit20 권한 획득.
- **Nullity**: `bandit20-do`에 `whoami`를 주면 `bandit20` 출력 — EUID가 실제로 바뀐 증거. 인자가 없으면 usage만.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**setuid / privilege escalation**. Unix 권한 모델의 핵심 메커니즘 — 특정 실행파일이 **호출자가 아닌 소유자 권한**으로 동작하게 하는 것. `sudo`·`passwd`·`ping`이 이 토대 위에 있다. Level 13의 File_Permissions(rwx 비트)에서 한 단계 올라가, mode의 **특수 비트(setuid=4000)**를 다룬다.

### 2. Definition (Formal, EN)

The **setuid bit** (mode `04000`, shown as the `s` in owner-execute: `-rwsr-xr-x`) causes a program, when executed, to run with the **effective UID (EUID)** of the file's *owner* rather than the caller's real UID. Kernel permission checks (file access, etc.) use the EUID. `bandit20-do` is owned by bandit20 with setuid set and execs an arbitrary argument command; that command therefore runs with EUID = bandit20.

### 3. Intuition (KR)

보통 프로그램은 **실행한 사람의 권한**으로 돈다. setuid는 "이 프로그램은 **주인의 권한**으로 돈다"는 특수 표식. `bandit20-do`의 주인이 bandit20이라, bandit19가 실행해도 그 안에선 bandit20이 된다 — **주인의 열쇠를 잠깐 빌려 쓰는** 셈. 그 열쇠로 bandit20 전용 password 파일을 연다.

### 4. Theory (Mechanism)

1. **RUID vs EUID**: 프로세스는 real UID(누가 실행했나)와 effective UID(권한 검사 기준)를 따로 가진다. 보통 둘이 같지만, setuid 파일 실행 시 커널이 **EUID = 파일 소유자 UID**로 설정.
2. `ls -l bandit20-do` → `-rwsr-x---  bandit20 bandit19` : owner-exec 자리의 **`s`**가 setuid. 소유자 bandit20, 그룹 bandit19(그래서 bandit19가 실행 가능).
3. `./bandit20-do CMD` 실행 → EUID=bandit20으로 상승 → 래퍼가 `CMD`를 그 권한으로 exec → `cat`이 EUID=bandit20으로 `/etc/bandit_pass/bandit20`(bandit20만 read 가능) 접근 성공.

인과: `bandit20-do`가 setuid+소유자 bandit20(조건) → 실행 시 EUID 상승(B) → 래핑된 `cat`이 bandit20 권한 상속(C) → password 파일 read 성공(D).

### 5. Solution

```bash
# bandit19 접속 (Level 18에서 얻은 password)
bandit19@bandit:~$ ls
bandit20-do

bandit19@bandit:~$ ls -l bandit20-do
# -rwsr-x--- 1 bandit20 bandit19 ... bandit20-do
#        ↑ owner-exec 자리의 's' = setuid. 소유자 bandit20 → 실행 시 그 권한

# 래퍼 usage 확인
bandit19@bandit:~$ ./bandit20-do
# Run a command as another user.
#   Example: ./bandit20-do whoami

# EUID 확인: 이 바이너리 안에선 내가 누구인가?
bandit19@bandit:~$ ./bandit20-do whoami
bandit20                              # ← EUID가 bandit20으로 상승됨 (setuid 증거)

# bandit20 권한으로 password 파일 읽기
bandit19@bandit:~$ ./bandit20-do cat /etc/bandit_pass/bandit20
<password masked>                     # ← bandit20 (Level 20) password
```

> [!warning] Password Masking
> bandit19 password(로그인용)와 `bandit20-do`가 뽑아낸 bandit20 password 둘 다 마스킹. 로그인 헬퍼가 클립보드 password를 프롬프트에 붙여 화면 노출시킬 수 있으니 그 줄도 commit 금지.

### 6. Why It Works

`bandit20-do`는 **setuid 비트 + 소유자 bandit20**이라, 실행 순간 커널이 프로세스 EUID를 bandit20으로 올린다. 래퍼가 인자로 받은 명령을 그 EUID로 exec하므로, `cat`이 bandit20의 권한으로 동작해 `/etc/bandit_pass/bandit20`(소유자 bandit20만 read 가능)을 읽는다. setuid가 없었다면 bandit19의 EUID로는 그 파일에 접근 거부됐을 것. 핵심은 "**실행 파일의 소유권 + setuid**가 실행자에게 소유자 권한을 위임"한다는 것.

### 7. Edge Cases / Limitation

- **소유자까지만 상승**: setuid는 EUID를 **파일 소유자**로 만든다 — root가 아니라 bandit20. root 파일이었다면 root가 됐을 것(진짜 privesc).
- **setuid 스크립트는 무시됨**: 현대 커널은 `#!` 스크립트의 setuid를 무시(TOCTOU race 위험). setuid는 **컴파일된 바이너리**에만 유효 — `bandit20-do`는 그래서 바이너리.
- **의도된 래퍼 vs 취약점**: `bandit20-do`는 "소유자 권한으로 임의 명령 실행"을 **의도적으로** 허용하는 미니-`sudo`. 실전 privesc는 임의 명령을 의도치 않게 허용하는 **취약한** setuid 바이너리를 찾는 것.
- **`whoami` = EUID 기반**: `whoami`는 `geteuid()`를 보여줘 bandit20. `id`로 보면 real/effective 분리를 더 명확히 볼 수 있음(래퍼 구현에 따라 setreuid로 둘 다 bandit20일 수도).

---

## [Phase 3] Formal Summary (EN)

> [!definition] Setuid Bit
> Mode `04000` on an executable; upon `execve`, the kernel sets the process EUID to the file owner's UID (RUID unchanged). Access checks use EUID, so the program runs with the owner's privileges. Displayed as `s` in the owner-execute position (`-rwsr-xr-x`). Ignored on scripts and on filesystems mounted `nosuid`.

> [!theorem] Privilege delegation via file ownership
> If executable F is owned by user U with the setuid bit set and is executable by user V, then V running F obtains EUID=U for the duration — inheriting U's file-access rights. ∴ a setuid wrapper that execs arbitrary argv (like `bandit20-do`) grants V full read access to U's files. □

---

## [Phase 4] Better Methods

**Current approach** (used above): `./bandit20-do cat /etc/bandit_pass/bandit20`. 직접적.

**Alternative 1**: bandit20 대화형 셸 획득 (여러 명령이 필요할 때)
```bash
./bandit20-do bash        # 래퍼가 허용하면 EUID=bandit20 셸 진입 → 자유 탐색
```
Trade-off: bandit20으로 여러 작업 가능. 단 래퍼가 임의 명령을 허용해야 함(이 경우 허용).

**Alternative 2** (일반화): 시스템의 setuid 바이너리 정찰 — privesc 표준
```bash
find / -perm -4000 -type f 2>/dev/null
#   -perm -4000 : setuid(4000) 비트가 '켜진' 파일 (- 접두사 = 해당 비트 포함 매칭)
#   -type f     : 일반 파일만
#   2>/dev/null : permission denied 노이즈 억제 (Level 06 기법 재적용)
```
Trade-off: 이 레벨은 홈에 대놓고 줬지만, 실전에선 이 명령으로 setuid 바이너리를 열거하고 [GTFOBins](https://gtfobins.github.io)로 악용 가능성을 조회.

**Most elegant**:
```bash
./bandit20-do cat /etc/bandit_pass/bandit20
```
Why elegant: 목표(bandit20 password 읽기)를 setuid 권한 위임 한 번으로 정확히 달성.

---

## [Phase 5] Lessons Learned

1. **setuid 비트(`-rwsr-xr-x`의 `s`)** → 실행 시 EUID = 파일 소유자. 그 권한으로 파일 접근. (Level 13 rwx의 상위 = 특수 비트.)
2. **`bandit20-do` = 소유자 권한으로 임의 명령 실행** 래퍼 → `cat /etc/bandit_pass/bandit20`.
3. **RUID ≠ EUID**: 권한 검사는 EUID 기준. setuid는 EUID만 소유자로 올린다.
4. **정찰 표준**: `find / -perm -4000 -type f 2>/dev/null`로 setuid 바이너리 열거 → privesc 벡터 탐색.

### Quiz

**Q**: (a) setuid 바이너리 실행 시 RUID/EUID가 각각 어떻게 되는가. (b) 왜 현대 커널은 setuid **스크립트**를 무시하는가. (c) 시스템에서 악용 가능한 setuid 바이너리를 어떻게 열거하는가.

> [!tip]- 풀이
> **(a)** RUID=호출자(bandit19) 유지, EUID=파일 소유자(bandit20)로 설정. 커널 권한 검사는 EUID 기준 → 소유자 권한으로 동작.
>
> **(b)** `#!` 스크립트는 커널이 인터프리터를 실행하는데, "setuid 판정 → 인터프리터 기동 → 스크립트 열기" 사이에 스크립트를 바꿔치기하는 **TOCTOU race**가 가능. 이 취약성 때문에 커널이 스크립트의 setuid를 무시하고 **바이너리에만** 적용.
>
> **(c)** `find / -perm -4000 -type f 2>/dev/null` — setuid 비트가 켜진 실행 파일 열거. 이후 [GTFOBins](https://gtfobins.github.io)로 각 바이너리의 privesc 악용법(예: `find`, `vim`, `less`의 setuid 시 셸 탈출) 조회.
>
> 핵심: setuid는 정당한 권한 위임(`sudo`/`passwd`)의 토대이자, 잘못 걸리면 privesc 벡터. **RUID/EUID 분리**를 이해하면 양쪽이 보인다.

> [!flashcard]
> **Q**: 실행 파일의 setuid 비트는 무슨 일을 하나?
> **A**: 실행 시 프로세스 EUID를 호출자가 아닌 **파일 소유자**로 설정 → 소유자 권한으로 동작. `-rwsr-xr-x`의 owner-exec 자리 `s`로 표시.

> [!flashcard]
> **Q**: 시스템의 setuid 바이너리를 모두 찾는 명령은?
> **A**: `find / -perm -4000 -type f 2>/dev/null` — setuid(4000) 비트가 켜진 일반 실행 파일 열거. privesc 정찰의 표준.

---

## Links

### Tools Used
- [[Tools/cat]]
- [[Tools/find]] (Better Methods — setuid 열거)

### Concepts Introduced (first encountered here)
- [[Concepts/Linux/Setuid]]

### Concepts Applied (reused from earlier)
- [[Concepts/Linux/File_Permissions]] (Level 13 — rwx 비트 → 여기선 특수 비트 setuid로 확장)

### Navigation
- **Prerequisite**: [[Level_18]]
- **Next**: [[Level_20]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit20.html
- `credentials(7)` / `execve(2)` — real vs effective UID, setuid semantics
- GTFOBins — https://gtfobins.github.io (setuid privesc reference)
