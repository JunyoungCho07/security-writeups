---
tool: find
category: file-discovery
man_section: 1
related: [ls, locate, fd, xargs, grep]
last_used: 2026-05-28
tags: [tool, linux, file-discovery, posix]
---

# `find`

## Purpose

Directory tree를 DFS traversal하며 **predicate expression**으로 inode를 필터링하고, 매칭된 경로에 임의 action을 실행하는 Unix toolbox의 최강 검색 engine. `SELECT FROM filesystem WHERE predicate1 AND predicate2 DO action`의 shell-native 구현.

## Full Signature

```
find [GLOBAL_OPTIONS] [PATH...] [EXPRESSION]
```

| Position | Name | Type | Description |
|---|---|---|---|
| `PATH...` | starting points | path list | 검색 시작 dir(s). 생략 시 `.` |
| `EXPRESSION` | predicates + actions | boolean expr | predicate (test) + action (side-effect) 조합 |

**평가 model**: expression은 boolean tree. 각 inode를 root부터 DFS로 방문하며 expression evaluate → `true` ↔ default action(`-print`) 실행 (또는 explicit `-exec`).

## Common Flags (most-used 7)

| Predicate | Long | Effect | Example |
|---|---|---|---|
| `-name PATTERN` | — | glob (case-sens) 이름 매칭 | `find . -name "*.txt"` |
| `-iname PATTERN` | — | case-insensitive name | `find . -iname "*.PDF"` |
| `-type T` | — | inode type: `f`(file)/`d`(dir)/`l`(symlink)/`s`(socket) | `find . -type f` |
| `-size N[cwbkMG]` | — | size: `c`=byte, `k`=KB, `M`=MB. `+N`/-N` = 초과/미만 | `find . -size 1033c` |
| `-user NAME` | — | owner UID 매칭 | `find / -user bandit7` |
| `-group NAME` | — | group GID 매칭 | `find / -group bandit6` |
| `-perm MODE` | — | permission: `0644` exact, `-0644` at-least, `/0644` any-of | `find / -perm -4000` (SUID) |
| `-mtime N` | — | modified N*24h ago. `-7`/`+30` 가능 | `find . -mtime -1` |
| `-readable` / `! -executable` | — | effective UID access test | `find . -readable ! -executable` |
| `-maxdepth N` / `-mindepth N` | — | traversal depth 제한 | `find . -maxdepth 1` |

**Action**:
- `-print` (default) — stdout으로 경로 출력 (newline-separated).
- `-print0` — null byte separator. `xargs -0`와 쌍.
- `-exec CMD {} \;` — match당 1회 `CMD` 실행. `{}` = 현재 경로.
- `-exec CMD {} +` — argument batching. **1번 fork**로 묶음 실행 (xargs와 동등).
- `-delete` — 매칭 inode 제거 (위험: dry-run으로 먼저 확인).

**Operators** (precedence: `( ) > ! > -a > -o`):
- 인접 predicate 사이 implicit `-a` (AND).
- `-o` — OR.
- `!` 또는 `-not` — unary NOT (다음 1개 predicate만 부정).
- `\( ... \)` — grouping (shell escape 필수).

## Idiomatic Examples

### 기본 — 이름 매칭

```bash
$ find /etc -name "*.conf"
/etc/resolv.conf
/etc/ssh/sshd_config
...
```

### Multi-predicate AND (Bandit Level 5 패턴)

```bash
$ find . -type f -size 1033c -readable ! -executable
./maybehere07/.file2
```

### Ownership 기반 (Bandit Level 6 패턴)

```bash
$ find / -type f -user bandit7 -group bandit6 -size 33c 2>/dev/null
./var/lib/dpkg/info/bandit7.password
```

`2>/dev/null`은 system-wide 검색 시 **permission denied** stderr 폭주 제거에 사실상 필수.

### Power user — null-safe pipeline

```bash
$ find / -type f -name "*.log" -print0 | xargs -0 grep -l "ERROR"
```

`-print0` + `xargs -0` 조합: 파일명에 공백/newline 있어도 안전. **production-grade 패턴.**

### Action — batched exec

```bash
$ find /tmp -type f -mtime +7 -exec rm {} +
```

`{} +`는 여러 결과를 한 번에 `rm`에 묶어 전달 → fork 횟수 최소화. `\;`로 쓰면 100배 느려질 수 있다.

### Grouping — NOT을 chain 전체에 적용

```bash
# Wrong: ! 는 -executable에만 적용됨
$ find . ! -executable -readable

# Right: NOT(executable AND readable)
$ find . ! \( -executable -readable \)
# 또는 De Morgan
$ find . \( ! -executable -o ! -readable \)
```

## Pitfalls

> [!warning] Common Mistakes
> 1. **`-size 1033` ≠ `-size 1033c`**: suffix 없으면 **512-byte block** 단위. byte 단위는 `c` 필수.
> 2. **`!` precedence 함정**: unary로 다음 단일 predicate에만 적용. chain 전체에 negation 걸려면 `\( ... \)` grouping 필요.
> 3. **`-exec ... \;` vs `+`**: `\;`는 result당 fork — 큰 result set에서 100배+ 느림. 가능하면 `+` 사용.
> 4. **`/` 검색 시 stderr 폭주**: `2>/dev/null` 없으면 Permission denied 노이즈가 실제 결과 묻음.
> 5. **`./` glob vs `.` argument**: `find ./*`는 shell glob expansion → ARG_MAX 초과 위험. `find .` 단일 인자 권장.
> 6. **`-name`은 path 아닌 basename 매칭**: `find . -name "/etc/*"` 절대 안 됨. `-path` 사용.
> 7. **BSD vs GNU 차이**: macOS `find`는 `-printf` 없음. cross-platform script는 POSIX subset만.

## Edge Cases

- **Sparse file**: `-size`는 `st_size` (apparent) 기준. allocated block 기준 검색 불가.
- **Symlink 처리**: default는 symlink 자체를 inode로 봄 (follow 안 함). `-L` 글로벌 옵션으로 follow.
- **`-perm 0644` vs `-perm -0644` vs `-perm /0644`**: exact / at-least / any-of. 3개 mode 헷갈리면 SUID 검색 실패.
- **Race condition**: traversal 중 파일 삭제/이동 → `find` 자체는 silent skip. TOCTOU 측면 위험 가능.
- **Empty result**: silent. predicate가 모두 false면 0 lines 출력 — 결과 0과 predicate 오류 구별 불가. dry-run 시 predicate 하나씩 빼며 검증.

## Related Tools

| Tool | Relationship |
|---|---|
| [[Tools/ls]] | complement — small/shallow 단순 나열. `find`는 deep + filter |
| [[Tools/xargs]] | chained — `find -print0 \| xargs -0 CMD` 표준 |
| `locate` | alternative — pre-indexed DB (빠르나 stale). `updatedb` 의존 |
| `fd` | alternative — Rust 기반 modern. simpler syntax, default smart-case |
| [[Tools/grep]] | chained — `find ... | xargs grep`으로 content 검색 결합 |

## Encountered In (Wargame Levels)

- [[Wargames/Bandit/Level_05]] — `-size` + `-readable` + `! -executable` 조합 (first use)
- [[Wargames/Bandit/Level_06]] — `-user` + `-group` + `2>/dev/null` 조합

## Concepts This Implements

- [[Concepts/Linux/Find_Predicates]] (planned)
- [[Concepts/Linux/Stderr_Redirection]] (planned)
- [[Concepts/Linux/Exit_Code]] — `find`도 exit code로 partial failure 신호 (e.g., 일부 dir에 permission denied = exit 1)
- [[Concepts/Linux/Subshell]] — `-exec ... \;`은 매 result마다 subshell-like fork. `-exec ... +`는 batching으로 fork 최소화.

## Quick Reference

```bash
# Most common one-liners
find . -type f -name "*.txt"                         # 이름 + type 매칭
find . -type f -size 1033c                            # 정확 size (byte)
find / -user X -group Y 2>/dev/null                  # ownership + 노이즈 제거
find . -mtime -1 -type f                              # 24h 이내 수정
find / -perm -4000 -type f 2>/dev/null               # SUID binary 전부
find . -name "*.log" -print0 | xargs -0 grep "X"     # null-safe content search
find . -type f -mtime +7 -exec rm {} +               # 일주일 묵은 파일 삭제 (batched)
find . -type d -empty                                 # 빈 디렉토리
```

> [!flashcard]
> **Q**: `find`의 가장 흔한 trap 3개는?
> **A**: ① `-size N` (suffix 없음) → 512-byte block 단위 ② `!` operator는 unary, 다음 1개 predicate만 부정 ③ `-exec \;`는 매번 fork — `+`로 batching 권장.

> [!flashcard]
> **Q**: `find / ...`에서 `2>/dev/null`이 필수인 이유는?
> **A**: 권한 없는 dir에서 `opendir(2)` 호출 시 EACCES → stderr에 "Permission denied" 출력. system-wide 검색 시 노이즈가 수십~수백 줄 → 실제 결과(stdout) 식별 불가. stderr를 null device로 routing해 분리.

---

## Background

- 1971년 AT&T Unix V1에 처음 등장. Dick Haight가 작성한 PWB Unix의 일부로 표준화.
- GNU find은 1990년대 GNU coreutils와 별도로 **findutils** project로 관리 (`locate`, `xargs`와 함께).
- POSIX.1-2001에 핵심 predicate (`-name`, `-type`, `-mtime`, `-size`, `-perm`, `-print`, `-exec`)가 표준화. GNU extension (`-printf`, `-readable`, `-regex`)은 BSD/macOS에서 작동 안 할 수 있음.
- 가장 오래된 expression-based filter 도구. SQL이 generic database에 가져온 declarative paradigm을 file system에 30년 먼저 적용한 셈.

## External Refs

- man page: `man 1 find`
- GNU findutils manual: https://www.gnu.org/software/findutils/manual/html_mono/find.html
- POSIX spec: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/find.html
- Tutorial: https://www.gnu.org/software/findutils/manual/html_node/find_html/Searching-for-Files.html
