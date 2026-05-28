---
date: 2026-05-28
wargame: Bandit
level: 5
title: "Bandit Level 5 → 6"
difficulty: ★☆☆
time_spent: 15min
tags: [bandit, linux, file-discovery, find]
status: 🔴 raw
tools_used: [find, cat, du]
new_concepts: [find-predicates]
prerequisites: [Level_04]
---

# Bandit Level 5 → 6

## [Phase 1] Executive Summary

- **Goal**: `inhere/` 하위 20개 디렉토리 중, **human-readable + size 1033 bytes + not executable** 조건을 만족하는 파일 1개 찾기
- **Key Skill**: `find` multi-predicate filtering (`-size`, `-readable`, `! -executable`)
- **Tags**: `[File_Discovery]`, `[Find_Predicates]`

[Cognitive Validation]
- **Limit Test**: predicate를 0개로 줄이면(`find .`) → 200개 이상 파일 전부 반환, 수동 탐색 불가. predicate를 ∞로 늘리면 → 검색 공간이 point로 수렴, 유일 파일 특정.
- **Control Knob**: `-size` 지배 변수. 1033c는 매우 구체적 크기라 단독으로도 유일 파일 특정 가능. `-readable`·`! -executable`은 noise 필터.
- **Nullity**: 조건을 만족하는 파일이 0개이면 → 출력 없음 (silent). 오답이 아니라 predicate 오류를 의심해야 함.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**Multi-predicate file discovery** — 단일 속성(이름·날짜)이 아닌 복수 속성(크기·권한·사람가독성)의 AND 조합으로 파일을 특정하는 기법.

### 2. Definition (Formal, EN)

`find(1)` evaluates a Boolean expression tree over each filesystem node under a root path. Predicates are implicitly AND-ed unless explicitly combined with `-o` (OR) or `!` (NOT). A predicate matches iff the node's metadata satisfies the test; matched nodes are printed (default action: `-print`).

Relevant predicates:

| Predicate       | Semantics                                 |
| --------------- | ----------------------------------------- |
| `-size Nc`      | file size == N bytes (c suffix = bytes)   |
| `-readable`     | process has read permission for this file |
| `! -executable` | process does NOT have execute permission  |

### 3. Intuition (KR)

`find`는 파일 시스템을 DFS로 순회하면서 각 노드에 "체크리스트"를 들이민다. 체크리스트 항목을 많이 추가할수록 통과하는 파일이 줄어든다 → **좁히기(narrowing)** 전략.

`-size 1033c`만으로도 20×9=180개 후보 중 1개로 좁힌 이유: 일반 파일들은 대부분 작은 임의 크기라 1033이라는 구체적 숫자에 딱 맞는 파일이 1개뿐.

### 4. Theory (Mechanism)

```
find DFS traversal:
  for each inode under root:
    test predicate_1 (size)  → false? prune
    test predicate_2 (readable) → false? prune
    test predicate_3 (!executable) → false? prune
    → all passed: emit path
```

`-size 1033c`에서 `c`(character/byte) suffix가 핵심. `find -size 1033`이면 512-byte block 단위로 계산 → 잘못된 결과. suffix 없으면 **512b blocks** 기준임을 항상 기억.

### 5. Solution

```bash
# SSH connection
$ ssh -p 2220 bandit5@bandit.labs.overthewire.org
# Password: <password masked>

bandit5@bandit:~$ ls
inhere

bandit5@bandit:~$ cd inhere/

bandit5@bandit:~/inhere$ ls
maybehere00  maybehere03  maybehere06  maybehere09  maybehere12  maybehere15  maybehere18
maybehere01  maybehere04  maybehere07  maybehere10  maybehere13  maybehere16  maybehere19
maybehere02  maybehere05  maybehere08  maybehere11  maybehere14  maybehere17

bandit5@bandit:~/inhere$ find ./** -size 1033c -readable ! -executable
./maybehere07/.file2

bandit5@bandit:~/inhere$ cat ./maybehere07/.file2
<password masked>
```

> [!warning] Password Masking
> 실제 password는 절대 commit하지 마라. `<password masked>` 또는 `[REDACTED]`로 치환.

### 6. Why It Works

1. **`find ./**`**: glob `./**`로 현재 디렉토리 하위 전체를 find의 starting point로 전달. (`.` 단독으로 써도 동일 결과, 아래 Phase 4 참조)
2. **`-size 1033c`**: inode의 `st_size` 필드를 1033 bytes와 비교. 파일 180개 중 딱 1개만 이 크기.
3. **`-readable`**: effective UID 기준 read bit 확인. 숨김 파일(`.file2`)이어도 권한만 있으면 통과.
4. **`! -executable`**: execute bit 없는 파일. 패스워드 파일은 텍스트라 실행 불가 → 이 조건 통과.
5. **`cat ./maybehere07/.file2`**: 파일 내용 출력. 1033 bytes이므로 마지막에 공백 패딩 존재 (비밀번호는 앞 32자).

### 7. Edge Cases / Limitation

- `-size 1033c`는 정확히 1033 bytes만 매치. `+1033c`(초과) / `-1033c`(미만) range 검색도 가능.
- `! -executable`은 **sticky bit**, **setuid** 등의 특수 권한을 고려하지 않는다. 엄밀한 "non-executable" 검사에는 `find -perm /111`의 NOT이 필요.
- `-readable`은 ACL(Access Control List)을 fully 반영하지 않는 시스템도 있음.
- `./**` glob이 매우 넓은 트리에서 ARG_MAX 초과 시 실패. `find . -size ...` 패턴이 더 안전.

---

## [Phase 3] Formal Summary (EN)

> [!definition] find Predicate Conjunction
> Given a file tree T and predicates P₁, P₂, ..., Pₙ, `find` returns the set S ⊆ T such that ∀f ∈ S: P₁(f) ∧ P₂(f) ∧ ... ∧ Pₙ(f) = true. Default logical connective between consecutive predicates is AND (implicit conjunction). Explicit operators: `-o` (disjunction), `!` (negation), `\( \)` (grouping).

> [!theorem] Size Predicate Specificity
> For a uniform-random file-size distribution over [1, M], the expected number of files matching `-size Nc` is |T| / M. As N becomes more specific (large M, unique size), E[matches] → 1/M × |T| → achieves unique identification when M >> |T|.

---

## [Phase 4] Better Methods

**Current approach** (used above):
```bash
find ./** -size 1033c -readable ! -executable
```
문제: glob `./**`는 ARG_MAX 제한에 걸릴 수 있음. 명시적 글로브 확장을 find에 넘기는 건 안티패턴.

**Alternative 1**: `find .` (preferred)
```bash
find . -size 1033c -readable ! -executable
```
Trade-off: 동일 결과. `.`은 find 자체가 재귀 탐색하므로 shell glob 불필요. **이게 표준.**

**Alternative 2**: `-type f` 추가 (더 엄밀)
```bash
find . -type f -size 1033c -readable ! -executable
```
`-type f`로 regular file만 필터. 디렉토리·symlink·device file 제외. Trade-off: 이 레벨에서는 불필요하지만 실전에서는 필수 습관.

**Alternative 3**: `du` + `find` 조합 (이미 시도함, 비효율)
```bash
du ./maybehere*  # disk usage 확인 → 디렉토리 크기지 파일 크기 아님
```
`du`는 디렉토리 블록 합계를 보여주므로 파일 단위 크기 확인 불가. 이 레벨에서 `du` 사용은 wrong tool.

**Most elegant**:
```bash
find . -type f -size 1033c ! -executable -readable
```
Why elegant: `-type f`로 inode 타입 먼저 필터(빠름) → 크기 → 권한 순서. predicate 평가 비용 순으로 정렬하면 short-circuit 효과로 약간 빠름. 실무 습관으로 고정하라.

---

## [Phase 5] Lessons Learned

1. `find`의 `-size Nc` suffix `c`는 bytes. 없으면 512-byte blocks — 헷갈리는 실수 1위.
2. 여러 조건의 AND 조합이 "1개 파일 특정"의 핵심. predicate를 쌓을수록 검색 공간이 수렴한다.
3. `du`는 디렉토리 크기 합계 도구이지 파일 크기 특정 도구가 아니다. wrong tool 탐지 능력 = 실전 효율.

### Quiz

**Q**: 다음 조건을 동시에 만족하는 파일을 찾는 `find` 명령을 작성하라. (1) 일반 파일(regular file), (2) 소유자가 `bandit7`, (3) 그룹이 `bandit6`, (4) 정확히 33 bytes. 단, 현재 유저가 해당 파일을 읽을 권한이 없어도 inode 메타데이터는 접근 가능하다는 점을 활용하라. (힌트: Bandit Level 6 미리보기)

> [!tip]- 풀이
> ```bash
> find / -type f -user bandit7 -group bandit6 -size 33c 2>/dev/null
> ```
> - `-user bandit7`: 파일 소유자 UID == bandit7
> - `-group bandit6`: 파일 그룹 GID == bandit6
> - `2>/dev/null`: Permission denied 에러 메시지를 버림 (읽기 권한 없는 디렉토리 탐색 시 발생)
> - `-readable` **생략**: 읽기 권한이 없어도 inode 메타데이터(`-user`, `-group`, `-size`)는 `stat(2)` syscall로 접근 가능. `-readable`을 추가하면 해당 파일이 필터링되어 못 찾는다.
>
> 핵심: `find` predicate는 inode metadata(stat) 접근과 file content 접근을 구분한다. `-readable`은 content 접근 가능 여부 테스트.

> [!flashcard]
> **Q**: `find -size 1033` vs `find -size 1033c` 차이는?
> **A**: suffix 없으면 512-byte blocks 단위 (1033 blocks = ~529KB). `c` suffix는 bytes. 정확한 byte 크기 매칭에는 반드시 `c` 필요.

---

## Links

### Tools Used
- [[Tools/find]]
- [[Tools/cat]]

### Concepts Introduced (first encountered here)
- [[Concepts/Linux/Find_Predicates]]

### Concepts Applied (reused from earlier)
- [[Concepts/Linux/Hidden_Files]]

### Navigation
- **Prerequisite**: [[Level_04]]
- **Next**: [[Level_06]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit6.html
