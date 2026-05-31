---
tool: uniq
category: text-processing
man_section: 1
related: [sort, grep, awk]
last_used: 2026-05-30
tags: [tool, linux, text-processing, deduplication]
---

# `uniq`

## Purpose

**인접한** 중복 줄을 제거(또는 카운트)한다. 스트림에서 unique/duplicate 행을 필터링하는 Unix 핵심 도구.

## Full Signature

```
uniq [OPTIONS] [INPUT [OUTPUT]]
```

| Position | Name | Type | Description |
|---|---|---|---|
| `INPUT` | input file | path / stdin | 처리할 파일. 생략 시 stdin |
| `OUTPUT` | output file | path / stdout | 결과 저장. 생략 시 stdout |

## Common Flags (most-used)

| Flag | Long | Effect | Example |
|---|---|---|---|
| `-c` | `--count` | 각 줄 앞에 등장 횟수 출력 | `uniq -c file` |
| `-d` | `--repeated` | 중복된 줄만 출력 (1회) | `uniq -d file` |
| `-u` | `--unique` | 단 한 번만 등장한 줄만 출력 | `uniq -u file` |
| `-i` | `--ignore-case` | 대소문자 무시하고 비교 | `uniq -i file` |
| `-f N` | `--skip-fields=N` | 앞 N개 필드 무시하고 비교 | `uniq -f 1 file` |
| `-s N` | `--skip-chars=N` | 앞 N개 문자 무시하고 비교 | `uniq -s 3 file` |
| `-w N` | `--check-chars=N` | 앞 N개 문자만 비교 | `uniq -w 5 file` |

## Idiomatic Examples

### 기본 사용 — 중복 제거
```bash
$ printf "apple\napple\nbanana\napple\n" | uniq
apple
banana
apple
# 주의: 마지막 "apple"은 살아있음 — 인접하지 않으면 미제거
```

### 완전한 중복 제거 (sort 선행 필수)
```bash
$ printf "apple\napple\nbanana\napple\n" | sort | uniq
apple
banana
```

### 빈도수 카운트 후 정렬
```bash
$ cat file | sort | uniq -c | sort -rn
      5 error
      3 warning
      1 info
# sort | uniq -c | sort -rn → "top N 빈도" 패턴
```

### 중복된 줄만 추출
```bash
$ sort data.txt | uniq -d
# 두 번 이상 등장한 줄만 출력
```

### 한 번만 등장한 줄만 추출
```bash
$ sort data.txt | uniq -u
# 정확히 1번만 등장한 줄만 출력 — Bandit Level 8 핵심 패턴
```

### Power user pattern — 로그에서 에러 빈도 top 10
```bash
grep "ERROR" app.log | awk '{print $NF}' | sort | uniq -c | sort -rn | head -10
```

## Pitfalls

> [!warning] Common Mistakes
> 1. **sort 없이 uniq** — uniq는 *인접한* 중복만 제거. `sort` 선행 없으면 비연속 중복이 살아남음. 가장 흔한 실수.
> 2. **`-d`와 `-u` 혼동** — `-d`는 "중복 있는 것", `-u`는 "중복 없는 것". 반대 의미.
> 3. **`-c` 출력 파싱** — `uniq -c` 출력은 `"      5 apple"` 형태로 앞에 공백 포함. `awk '{print $1}'`로 카운트 추출 시 주의.

## Edge Cases

- 빈 파일 → 출력 없음, exit 0
- 줄 끝 개행 없는 마지막 줄 → GNU uniq는 처리함, 일부 구현은 무시
- `-f N`으로 필드 skip 시 필드 구분자는 공백/탭. CSV는 별도 처리 필요
- `uniq -c | sort -rn` 후 `head` — 파이프 broken pipe signal(141) 발생 가능, 무시해도 무방

## Related Tools

| Tool | Relationship |
|---|---|
| `sort` | **필수 전처리** — uniq는 인접 비교만 하므로 sort 선행이 사실상 표준 패턴 |
| `grep` | **Alternative** — 특정 패턴 줄 필터링 (단, 빈도 카운트 불가) |
| `awk` | **Superset** — `awk '!seen[$0]++'`로 sort 없이 전체 중복 제거 가능 |
| `comm` | **Complement** — 두 정렬된 파일의 공통/차이 줄 비교 |

## Encountered In (Wargame Levels)
- [[Wargames/Bandit/Level_08]] (first use — 한 번만 등장하는 줄 찾기)

## Concepts This Implements
- [[Concepts/Linux/Unix_Pipeline]]

## Quick Reference

```bash
sort file | uniq           # 중복 제거 (기본 패턴)
sort file | uniq -u        # 유일한 줄만
sort file | uniq -d        # 중복 줄만
sort file | uniq -c        # 빈도 카운트
sort file | uniq -c | sort -rn  # 빈도 내림차순
```

> [!flashcard]
> **Q**: `uniq`의 가장 흔한 trap은?
> **A**: sort 없이 사용하는 것. uniq는 인접(adjacent)한 줄만 비교하므로 `apple / banana / apple` 입력에서 두 번째 `apple`을 제거하지 않는다. 반드시 `sort | uniq` 패턴으로 사용.

---

## Background

`uniq`는 1970년대 초 Unix Version 1부터 존재한 원시 도구 중 하나. Ken Thompson과 Dennis Ritchie의 Unix 철학 "한 가지 일만 잘 하라"의 표본. `sort`와 파이프로 연결하는 패턴은 Unix 초창기부터 관용구로 정착 — 오늘날 빅데이터 MapReduce의 shuffle-sort-reduce 단계와 구조적으로 동일하다.

## External Refs

- man page: `man uniq`
- GNU coreutils: https://www.gnu.org/software/coreutils/manual/html_node/uniq-invocation.html
