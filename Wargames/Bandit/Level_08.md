---
date: 2026-05-31
wargame: Bandit
level: 8
title: "Bandit Level 8 → 9"
difficulty: ★☆☆
time_spent: 5min
tags: [bandit, linux, text-processing, stream-deduplication]
status: 🟢 solid
tools_used: [sort, uniq]
new_concepts: [Stream_Deduplication]
prerequisites: [Level_07]
---

# Bandit Level 8 → 9

## [Phase 1] Executive Summary

- **Goal**: `data.txt`에서 딱 한 번만 등장하는 줄 찾기
- **Key Skill**: `sort | uniq -u` — 정렬 후 unique line 필터링
- **Tags**: `[Text_Processing]`, `[Stream_Deduplication]`

[Cognitive Validation]
- **Limit Test**: 모든 줄이 중복이면 → `uniq -u` 출력 0줄. 모든 줄이 unique면 → 전체 출력. 이 level은 정확히 1줄만 unique.
- **Control Knob**: `uniq`의 `-u` flag가 지배 변수. `-c`로 바꾸면 count, `-d`로 바꾸면 중복 줄만.
- **Nullity**: 파일이 비어 있으면 → `sort`는 빈 스트림, `uniq -u`는 아무것도 출력 안 함.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

Stream deduplication via sort-then-filter — 파이프라인 기반 텍스트 처리의 전형.

### 2. Definition (Formal, EN)

`uniq` filters **adjacent** duplicate lines from sorted input. `uniq -u` retains only lines that appear **exactly once** in the entire input (non-adjacent duplicates are invisible to `uniq` without prior sort).

Formally: let L be a multiset of lines. `sort | uniq -u` computes {l ∈ L : count(l, L) = 1}.

### 3. Intuition (KR)

`uniq`은 **옆집이 같으면 제거**하는 필터다. 정렬 없이 쓰면 떨어진 중복을 못 잡는다. `sort`로 먼저 같은 값을 붙여놓고 `uniq -u`로 혼자인 것만 남기는 구조.

### 4. Theory (Mechanism)

1. `sort data.txt` — 알파벳 순 정렬. 동일 문자열이 연속 배치됨.
2. `uniq -u` — stdin을 한 줄씩 읽으며 이전 줄과 비교. 다르면 후보; 다음 줄도 다르면 출력. 같은 줄이 연속되면 해당 그룹 전체 억제.
3. 결과: 정렬 기준 1회만 등장하는 줄 하나 출력.

Time complexity: O(N log N) for sort, O(N) for uniq → dominated by sort.

### 5. Solution

```bash
# SSH connection
$ ssh -p 2220 bandit8@bandit.labs.overthewire.org
# Password: <password masked>

bandit8@bandit:~$ ls
data.txt

bandit8@bandit:~$ sort data.txt | uniq -u
<password masked>
```

> [!warning] Password Masking
> 실제 password는 절대 commit하지 마라. `<password masked>` 또는 `[REDACTED]`로 치환.

### 6. Why It Works

`uniq` requires **sorted** input to reliably detect all duplicates because it only compares consecutive lines. Without `sort`, two identical lines separated by a third line would both be emitted. The pipeline `sort | uniq -u` is therefore the canonical solution: sort collapses duplicates into contiguous groups, uniq -u discards any group of size > 1.

### 7. Edge Cases / Limitation

- `uniq` 비교는 기본적으로 전체 줄 대상. `-f N`으로 앞 N개 필드 skip, `-s N`으로 앞 N글자 skip 가능.
- 대소문자 구별함 — `-i` flag로 case-insensitive 처리 가능.
- 파일이 매우 크면 `sort`의 메모리 제한 (`-S`, temp dir) 고려.

---

## [Phase 3] Formal Summary (EN)

> [!definition] Stream Deduplication
> Given a sequence S of strings, stream deduplication produces the subsequence of elements with multiplicity exactly 1. Requires S to be sorted for O(N) single-pass detection; otherwise requires O(N) auxiliary space or O(N²) time.

> [!theorem] Correctness of sort | uniq -u
> For any finite multiset L of lines, `sort L | uniq -u` ≡ {l : count(l, L) = 1}. Proof: sort establishes total order → all copies of l are adjacent → uniq -u sees the run and suppresses iff run length > 1. □

---

## [Phase 4] Better Methods

**Current approach** (used above):
```bash
sort data.txt | uniq -u
```

**Alternative 1**: `awk` frequency map (no sort required)
```bash
awk '{ count[$0]++ } END { for (l in count) if (count[l]==1) print l }' data.txt
```
Trade-off: O(N) time, O(N) space — 정렬 불필요하지만 전체 파일을 메모리에 올림. 대용량에서 불리.

**Alternative 2**: `sort -u` 오해 주의
```bash
sort -u data.txt   # WRONG — 중복 제거해버림, "한 번만 등장"과 다름
```
`sort -u`는 중복을 제거한 집합을 반환. unique occurrence 필터가 아님.

**Most elegant**:
```bash
sort data.txt | uniq -u
```
Why elegant: two POSIX tools, one pipe, zero temp files. 의도가 command 구조에 그대로 드러남.

---

## [Phase 5] Lessons Learned

1. `uniq`은 반드시 정렬된 입력을 전제한다 — 독립 사용 시 함정.
2. `-u` / `-d` / `-c` flag의 차이를 명확히: unique / duplicate-only / count.
3. `awk` frequency map은 sort 없이 same task를 해결하지만, 메모리-시간 트레이드오프 존재.

### Quiz

**Q**: `sort | uniq -u`는 O(N log N)이지만, 하나의 패스로 unique line을 찾는 O(N) 알고리즘을 설계하라. 단, 줄 수 N이 가용 메모리 M보다 클 수 있다(N >> M). 어떤 자료구조 / 외부 알고리즘을 쓰겠는가?

> [!tip]- 풀이
> **Case 1 (N ≤ M)**: Hash map `{line → count}` — O(N) time, O(N) space.
>
> **Case 2 (N >> M)**: External sort (merge sort on disk) → O(N log N) I/O. 메모리 내 정렬 불가 시 sort 기반이 사실상 최선.  
> 또는 Count-Min Sketch로 근사 — false positive 가능하므로 정확도 보장 안 됨.
>
> 핵심: "정렬 없이 O(N)"은 O(N) 메모리를 전제. 메모리 제한 있으면 external sort로 후퇴.

> [!flashcard]
> **Q**: Why must input be sorted before piping to `uniq`?
> **A**: `uniq` compares only adjacent lines. Without sorting, non-contiguous duplicates are treated as distinct lines, producing false positives in the output.

---

## Links

### Tools Used
- [[Tools/sort]]
- [[Tools/uniq]]

### Concepts Introduced (first encountered here)
- [[Concepts/Linux/Stream_Deduplication]]

### Concepts Applied (reused from earlier)
- [[Concepts/Linux/Pipe_Composition]]

### Navigation
- **Prerequisite**: [[Level_07]]
- **Next**: [[Level_09]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit9.html
