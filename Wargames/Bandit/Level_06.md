---
date: 2026-05-28
wargame: Bandit
level: 6
title: "Bandit Level 6 → 7"
difficulty: ★☆☆
time_spent: 20min
tags: [bandit, linux, file-discovery, find, stderr-redirect]
status: 🔴 raw
tools_used: [find, cat]
new_concepts: [stderr-redirection, shell-history-expansion]
prerequisites: [Level_05]
---

# Bandit Level 6 → 7

## [Phase 1] Executive Summary

- **Goal**: **서버 어딘가(somewhere on the server)**에서 `owner=bandit7`, `group=bandit6`, `size=33 bytes` 조건을 만족하는 파일 찾기
- **Key Skill**: `find` + `-user`/`-group` predicates + `2>/dev/null` stderr suppression
- **Tags**: `[File_Discovery]`, `[Stderr_Redirection]`, `[Shell_History_Expansion]`

[Cognitive Validation]
- **Limit Test**: search root를 `/`(전체 fs)로 보내면 → Permission denied 노이즈 폭발. `2>/dev/null`이 없으면 실제 결과가 에러 메시지에 묻힘. `/dev/null`이 핵심 변수.
- **Control Knob**: `-user`+`-group` 조합이 지배 변수. 시스템 전체 33-byte 파일은 다수지만, 특정 소유자+그룹 조합을 만족하는 건 1개.
- **Nullity**: `2>/dev/null`에서 `2>`를 없애면 → stderr가 stdout에 섞여 결과 식별 불가. redirect 없음 = 정보 묻힘.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**System-wide file discovery with ownership predicates + noise suppression** — 단순 크기/권한이 아닌 소유권(UID/GID) 기준 탐색, 그리고 permission-denied 노이즈를 stderr redirect로 제거하는 기법.

### 2. Definition (Formal, EN)

**File descriptor streams**: Every Unix process has (at minimum) three open FDs:
- `0` — stdin
- `1` — stdout  
- `2` — stderr

Redirection `2>/dev/null` routes FD 2 (stderr) to `/dev/null`, the null device that discards all writes. The find predicates `-user` and `-group` match against the inode's `st_uid` and `st_gid` fields respectively (resolved via `/etc/passwd` and `/etc/group`).

**Shell history expansion**: `!!` expands to the previous command. `$(command)` is command substitution — output replaces the expression inline. Therefore `$(!!)` = `$(previous command output)`.

### 3. Intuition (KR)

`find /`는 집 전체를 뒤지는 것과 같다. 남의 방(Permission denied)에 들어가려 할 때마다 경보가 울린다 → `2>/dev/null`은 그 경보음을 소거기로 막는 것. 경보가 꺼지면 실제로 찾은 파일만 들린다.

`$(!!)` = "아까 찾은 경로를 cat의 인자로 바로 꽂아라." 경로를 손으로 복사/붙여넣기하지 않아도 됨.

### 4. Theory (Mechanism)

```
Process file descriptors:
  stdin  (0) ──► terminal input
  stdout (1) ──► terminal output  ← find result goes here
  stderr (2) ──► /dev/null        ← permission denied goes here (discarded)

find traversal:
  opendir() each directory
    → EACCES (Permission denied)? → prints to stderr (FD 2) → /dev/null
    → success? → check predicates → match: prints to stdout (FD 1) → terminal
```

`/dev/null`은 character device (`c` type). write syscall은 성공하지만 데이터가 커널 내부에서 즉시 버려진다. 파일 시스템에 아무것도 쓰이지 않음.

### 5. Solution

```bash
# SSH connection
$ ssh -p 2220 bandit6@bandit.labs.overthewire.org
# Password: <password masked>

bandit6@bandit:~$ ls -al
# Home directory: only dotfiles (.bash_logout, .bashrc, .profile) — no password here

bandit6@bandit:~$ cd /

# WRONG: file is not find
bandit6@bandit:/$ file -user bandit7 -group bandit6 -size 33c
# file: invalid option -- 'u' ...

# Without stderr suppression: noise flood
bandit6@bandit:/$ find . -user bandit7 -group bandit6 -size 33c
# find: './tmp': Permission denied
# ... (50+ permission denied lines)
# ./var/lib/dpkg/info/bandit7.password   ← result buried in noise

# WRONG: typo — /devnull does not exist
bandit6@bandit:/$ find . -user bandit7 -group bandit6 -size 33c 2>/devnull
# -bash: /devnull: Permission denied

# CORRECT: stderr to /dev/null
bandit6@bandit:/$ find . -user bandit7 -group bandit6 -size 33c 2>/dev/null
./var/lib/dpkg/info/bandit7.password

# Elegant: $(!!) = cat $(find . ...)
bandit6@bandit:/$ cat $(!!)
# cat $(find . -user bandit7 -group bandit6 -size 33c 2>/dev/null)
<password masked>
```

> [!warning] Password Masking
> 실제 password는 절대 commit하지 마라. `<password masked>` 또는 `[REDACTED]`로 치환.

### 6. Why It Works

1. **홈 디렉토리 비어있음**: `ls -al`로 확인 → 검색 범위가 전체 서버임을 확정. `cd /` 후 탐색.
2. **`-user bandit7 -group bandit6`**: inode의 UID/GID가 각각 bandit7/bandit6인 파일만 통과. 시스템 전체 수백만 파일 → 1개로 수렴.
3. **`-size 33c`**: 33 bytes 정확히 매치.
4. **`2>/dev/null`**: stderr(FD 2)를 null device로 redirect. Permission denied 에러가 stdout을 오염시키지 않음.
5. **`$(!!)` oneshot**: `!!` = bash history expansion, 직전 명령어 전체로 치환. `$()` = command substitution, 출력을 인라인 인자로. 두 기법 조합으로 경로를 직접 입력하지 않고 cat에 전달.

### 7. Error Analysis (이 세션에서 실수한 것들)

| 실수 | 원인 | 교훈 |
|---|---|---|
| `file -user bandit7 ...` | `file` vs `find` 혼동 | `file`: 파일 타입 판별 / `find`: 파일 탐색. 완전히 다른 도구. |
| `2>/devnull/` | 경로 오타 (`/devnull`은 존재 안 함) | null device 경로는 `/dev/null` (슬래시 포함, `dev` 디렉토리 하위) |
| `2 > /dev/null` (공백) | 리다이렉션 파싱 오해 | `2>`는 붙여서 써야 함. `2 > /dev/null`은 `2`라는 인자 + stdout redirect로 파싱됨. |

### 8. Edge Cases / Limitation

- `/dev/null`은 **쓰기 전용**이 아님 — 읽기도 가능하지만 항상 0 bytes를 반환. `cat /dev/null` = empty.
- `$(!!)` 는 결과가 여러 줄이면 **공백 분리 인자**로 전달됨. 경로에 공백이 있으면 깨짐. 실전에서는 `find ... -exec cat {} \;` 또는 `xargs`가 더 안전.
- `-user`/`-group`은 심볼릭 이름으로 전달 가능하지만, 해당 UID/GID가 `/etc/passwd`·`/etc/group`에 없으면 숫자로 써야 함.

---

## [Phase 3] Formal Summary (EN)

> [!definition] File Descriptor Redirection
> In Unix, a process's I/O streams are indexed file descriptors. Redirection operator `n>path` duplicates FD `n` to a new open file at `path`. `2>/dev/null` ≡ `dup2(open("/dev/null", O_WRONLY), 2)` — all writes to FD 2 are discarded by the kernel's null device driver without buffering or storage.

> [!theorem] Signal-to-Noise Separation
> Given a find traversal over tree T with |T| nodes, let E = set of permission-denied errors, R = set of matching results. Without redirection: output = E ∪ R on mixed streams. With `2>/dev/null`: output(stdout) = R exclusively. Separation is exact iff find never writes results to stderr.

---

## [Phase 4] Better Methods

**Current approach** (used above):
```bash
find / -user bandit7 -group bandit6 -size 33c 2>/dev/null
cat $(!!)
```

**Alternative 1**: `-exec` inline (no shell history trick needed)
```bash
find / -user bandit7 -group bandit6 -size 33c -exec cat {} \; 2>/dev/null
```
Trade-off: 한 줄 완결. 하지만 매칭 파일이 여러 개면 전부 cat함. `$(!!)` 패턴은 경로를 먼저 확인 후 cat 가능.

**Alternative 2**: `xargs` (공백 있는 경로에도 안전)
```bash
find / -user bandit7 -group bandit6 -size 33c 2>/dev/null | xargs cat
```
Trade-off: 파이프라인. 공백 경로에는 `xargs -d '\n'` 추가 필요.

**Alternative 3**: `-type f` 추가 (directory 제외)
```bash
find / -type f -user bandit7 -group bandit6 -size 33c 2>/dev/null
```
Trade-off: 실전 필수 습관. 이 레벨에서도 명시하는 게 더 엄밀.

**Most elegant**:
```bash
find / -type f -user bandit7 -group bandit6 -size 33c 2>/dev/null | xargs cat
```
Why elegant: 단일 파이프라인, `xargs`가 공백 경로 처리, `-type f`로 타입 명시. `$(!!)` 없이 완결.

---

## [Phase 5] Lessons Learned

1. `file`(파일 타입 판별)과 `find`(파일 탐색)는 이름이 비슷하지만 완전히 다른 도구다. 혼동 = 즉시 error.
2. `2>/dev/null`에서 `2>`는 공백 없이 붙여 써야 한다. `2 > /dev/null`은 다른 문장 구조.
3. `$(!!)` 은 강력하지만 경로에 공백이 있으면 깨진다. `xargs` 또는 `-exec`가 production-safe.

### Quiz

**Q**: `find / -type f -user bandit7 2>/dev/null` 명령이 결과를 출력했다. 이를 `xargs`로 파이프하여 `file` 명령으로 각 파일의 타입을 확인하려 한다. 단, 파일 경로에 공백이 포함될 수 있다. 안전한 명령을 작성하라. (힌트: `find`의 `-print0` 옵션과 `xargs -0` 옵션의 관계를 생각하라)

> [!tip]- 풀이
> ```bash
> find / -type f -user bandit7 2>/dev/null -print0 | xargs -0 file
> ```
> - `-print0`: 파일 경로를 null byte(`\0`)로 구분하여 출력. 공백·줄바꿈 포함 경로도 안전.
> - `xargs -0`: stdin을 null byte 기준으로 분리. `-print0`과 쌍으로 사용.
> - 공백 경로에 `|xargs` (기본값 공백 구분)을 쓰면 `"my file"` → `my` + `file` 두 개의 잘못된 인자로 분리됨.
>
> 핵심: `-print0 | xargs -0`는 Unix 파일명의 유일한 불가능 문자(null byte)를 구분자로 쓰는 관례. 항상 이 쌍으로 사용하라.

> [!flashcard]
> **Q**: `2>/dev/null`에서 `2`의 의미와 `/dev/null`의 역할은?
> **A**: `2`는 stderr(FD 2). `/dev/null`은 모든 write를 discarding하는 null character device. 조합하면 stderr 출력이 커널 수준에서 즉시 버려짐.

---

## Links

### Tools Used
- [[Tools/find]]
- [[Tools/cat]]

### Concepts Introduced (first encountered here)
- [[Concepts/Linux/Stderr_Redirection]]
- [[Concepts/Linux/Shell_History_Expansion]]

### Concepts Applied (reused from earlier)
- [[Concepts/Linux/Find_Predicates]]

### Navigation
- **Prerequisite**: [[Level_05]]
- **Next**: [[Level_07]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit7.html
