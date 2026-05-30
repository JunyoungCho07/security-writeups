---
date: 2026-05-30
wargame: Bandit
level: 7
title: "Bandit Level 7 → 8"
difficulty: ★☆☆
time_spent: 5min
tags: [bandit, linux, text-processing, grep]
status: 🔴 raw
tools_used: [grep]
new_concepts: [Grep_Pattern_Matching]
prerequisites: [Level_06]
---

# Bandit Level 7 → 8

## [Phase 1] Executive Summary

- **Goal**: `data.txt`에서 "millionth" 단어 옆에 저장된 password 찾기
- **Key Skill**: `grep` — line-by-line pattern matching으로 needle-in-haystack 탐색
- **Tags**: `[Text_Processing]`, `[Regex]`, `[Stdin_Pipeline]`

[Cognitive Validation]
- **Limit Test**: `data.txt`가 수백만 줄이면? → `grep`은 스트리밍 방식으로 처리하므로 메모리 O(line_length), 전체 파일 로드 불필요. `cat | grep`은 동일하지만 pipe overhead 추가.
- **Control Knob**: 검색 패턴의 구체성 ↑ → false positive ↓. `millionth`처럼 유일한 token이면 결과 1줄 보장.
- **Nullity**: 패턴이 없으면 exit code 1, 출력 없음 — silent failure. 항상 exit code 확인 습관.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**Text Filtering** — 구조화되지 않은 대용량 파일에서 패턴에 매칭하는 줄만 추출. Unix 철학 "do one thing well"의 핵심 예시.

### 2. Definition (Formal, EN)

`grep` (Global Regular Expression Print): Scans input line-by-line, printing lines that match a given BRE/ERE/PCRE pattern. Exits 0 if ≥1 match, 1 if no match, 2 on error.

### 3. Intuition (KR)

파일 전체를 눈으로 읽는 대신, 형광펜으로 "millionth"가 있는 줄만 골라내는 것. 나머지 수만 줄은 존재 자체를 무시.

### 4. Theory (Mechanism)

```
data.txt (수만 줄) → grep reads line N
  → regex engine: does "millionth" match anywhere in line N?
  → YES: write line N to stdout
  → NO: discard, advance to line N+1
→ match found → stdout에 1줄 출력 + exit 0
```

`cat data.txt | grep millionth` 에서 `cat`은 file → stdout으로 연결하는 중간 매개. 실제로는 불필요 (UUoC 참고).

### 5. Solution

```bash
# SSH
$ ssh -p 2220 bandit7@bandit.labs.overthewire.org
# Password: <password masked>

bandit7@bandit:~$ ls
data.txt

bandit7@bandit:~$ cat data.txt | grep millionth
millionth	<password masked>
```

> [!warning] Password Masking
> 실제 password는 절대 commit하지 마라. `<password masked>` 또는 `[REDACTED]`로 치환.

### 6. Why It Works

1. `data.txt`는 `word\tpassword` 형식의 tab-separated 쌍 수만 개를 포함
2. `grep millionth`는 "millionth" 문자열을 포함하는 줄 하나만 필터링
3. 해당 줄의 두 번째 필드(tab 이후)가 다음 레벨 password
4. stdout에 단 1줄 출력 → 육안으로 즉시 확인 가능

### 7. Edge Cases / Limitation

- "millionth"가 다른 단어의 substring으로 등장하면 false positive 가능 (`-w` flag로 word-boundary 강제)
- Tab-separated 구조가 깨지거나 다른 whitespace 사용 시 `awk`/`cut`으로 파싱 필요
- 대소문자 구분: 기본 grep은 case-sensitive. 대문자 포함 가능성 있으면 `-i` 사용

---

## [Phase 3] Formal Summary (EN)

> [!definition] grep Pattern Matching
> `grep PATTERN FILE` scans FILE line by line. For each line L, if `PATTERN ∈ L` (as a BRE match by default), L is written to stdout. Exit status: 0 (≥1 match), 1 (no match), 2 (I/O error).

> [!theorem] UUoC (Useless Use of Cat)
> `cat FILE | grep P` ≡ `grep P FILE`. The former spawns an extra process + pipe; the latter is direct file I/O. Functionally identical, but `grep P FILE` is strictly more efficient and idiomatic.

---

## [Phase 4] Better Methods

**Current approach** (used in session):
```bash
cat data.txt | grep millionth
```
문제 없이 작동하지만 `cat`이 불필요 — UUoC anti-pattern.

**Alternative 1**: Direct grep (권장)
```bash
grep millionth data.txt
```
Trade-off: 동일한 결과, pipe overhead 없음, 더 읽기 쉬움. **이것이 정답.**

**Alternative 2**: Word-boundary 강제
```bash
grep -w millionth data.txt
```
Trade-off: "millionth2" 같은 substring 오매칭 방지. 이 케이스엔 불필요하지만 습관적으로 유용.

**Alternative 3**: awk로 key-value 파싱
```bash
awk '$1 == "millionth" {print $2}' data.txt
```
Trade-off: password 필드만 깔끔하게 추출. 구조가 명확할 때 grep보다 정밀.

**Most elegant**:
```bash
grep -w millionth data.txt
```
Why elegant: UUoC 없음 + word-boundary 보호 + 단일 프로세스.

---

## [Phase 5] Lessons Learned

1. `cat FILE | grep` 대신 `grep PATTERN FILE` — 불필요한 프로세스 생성은 습관을 망친다.
2. `grep`의 exit code는 0/1/2로 명확하다 — 스크립트에서 `if grep ...` 조건문 직접 사용 가능.
3. Tab-separated 파일에서 특정 key로 value 추출 → `grep` + 눈으로 확인이 아니라 `awk '$1=="key"{print $2}'`가 더 강건하다.

### Quiz

**Q**: `data.txt`에 "millionth"가 1000번 등장하고 각 줄의 password가 다르다면, 정확히 첫 번째 매칭 결과만 추출하는 one-liner는? 그리고 그 경우 `grep`만으로 충분한가, 아니면 다른 도구가 필요한가?

> [!tip]- 풀이
> `grep -m 1 millionth data.txt` — `-m 1` (max-count=1) flag로 첫 매칭 후 즉시 종료.
> `grep`만으로 충분. 단, password 필드만 isolate하려면 `grep -m 1 millionth data.txt | cut -f2` 또는 `awk 'NR==1{exit} $1=="millionth"{print $2; exit}' data.txt` 조합 필요.
>
> 핵심: grep -m N은 성능 최적화 도구 — 매칭 즉시 early exit하여 나머지 파일 스캔 생략.

> [!flashcard]
> **Q**: `grep`이 매칭을 찾지 못했을 때 exit code는?
> **A**: Exit code 1. 0 = 매칭 있음, 1 = 매칭 없음, 2 = 에러 (파일 없음, 권한 없음 등). 이 구분이 shell script에서 `if grep -q pattern file; then ...` 패턴을 가능하게 한다.

---

## Links

### Tools Used
- [[Tools/grep]]

### Concepts Introduced (first encountered here)
- [[Concepts/Linux/Grep_Pattern_Matching]]
- [[Concepts/Linux/Regex_Flavors]]

### Concepts Applied (reused from earlier)
- [[Concepts/Linux/Unix_Pipeline]]

### Navigation
- **Prerequisite**: [[Level_06]]
- **Next**: [[Level_08]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit8.html
- GNU grep manual: https://www.gnu.org/software/grep/manual/grep.html
