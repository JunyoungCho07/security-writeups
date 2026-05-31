---
tool: sort
category: text-processing
man_section: 1
related: [uniq, awk, cut]
last_used: 2026-05-30
tags: [tool, linux, text-processing, sorting]
---

# `sort`

## Purpose

텍스트 줄을 정렬한다. `uniq`의 필수 전처리 도구이자, 파이프라인에서 데이터를 순서화하는 Unix 핵심 유틸.

## Full Signature

```
sort [OPTIONS] [FILE...]
```

| Position | Name | Type | Description |
|---|---|---|---|
| `FILE` | input file(s) | path / stdin | 정렬할 파일. 여러 개 지정 시 merge 정렬. 생략 시 stdin |

## Common Flags (most-used)

| Flag | Long | Effect | Example |
|---|---|---|---|
| `-r` | `--reverse` | 역순 정렬 | `sort -r file` |
| `-n` | `--numeric-sort` | 숫자로 비교 (lexicographic 아님) | `sort -n file` |
| `-k N` | `--key=N` | N번째 필드 기준 정렬 | `sort -k 2 file` |
| `-t SEP` | `--field-separator=SEP` | 필드 구분자 지정 | `sort -t: -k3 /etc/passwd` |
| `-u` | `--unique` | 정렬 + 중복 제거 (`sort \| uniq` 축약) | `sort -u file` |
| `-f` | `--ignore-case` | 대소문자 무시 | `sort -f file` |
| `-h` | `--human-numeric-sort` | 1K, 2M, 3G 등 human-readable 숫자 비교 | `du -sh * \| sort -h` |
| `-R` | `--random-sort` | 무작위 섞기 | `sort -R file` |

## Idiomatic Examples

### 기본 — 알파벳 정렬
```bash
$ printf "banana\napple\ncherry\n" | sort
apple
banana
cherry
```

### 숫자 정렬 (-n 필수)
```bash
$ printf "10\n9\n100\n2\n" | sort       # 잘못된 사용 (lexicographic)
10
100
2
9

$ printf "10\n9\n100\n2\n" | sort -n    # 올바른 숫자 정렬
2
9
10
100
```

### 빈도 카운트 후 내림차순 (핵심 패턴)
```bash
$ sort file | uniq -c | sort -rn
      8 error
      3 warning
      1 info
```

### 특정 필드 기준 정렬
```bash
# /etc/passwd의 3번째 필드(UID) 숫자 정렬
$ sort -t: -k3 -n /etc/passwd

# TSV에서 2번째 컬럼 기준 역순
$ sort -k2 -r data.tsv
```

### human-readable 사이즈 정렬
```bash
$ du -sh * | sort -h
4.0K    file.txt
128K    image.png
3.2M    video.mp4
1.1G    dump.sql
```

### Power user — 복합 키 정렬
```bash
# 1번째 필드 알파벳 오름차순, 동점 시 2번째 필드 숫자 내림차순
$ sort -k1,1 -k2,2nr data.txt
```

## Pitfalls

> [!warning] Common Mistakes
> 1. **`-n` 없이 숫자 정렬** — 기본은 lexicographic. `10 < 9` 가 됨 (`"1" < "9"`). 숫자면 항상 `-n`.
> 2. **`-k N` 범위 미지정** — `-k2`는 "2번째 필드부터 줄 끝까지" 비교. 정확히 2번째 필드만 비교하려면 `-k2,2`.
> 3. **`sort -u` vs `sort | uniq`** — `sort -u`는 중복 제거만. `uniq -c`(빈도 카운트)가 필요하면 반드시 파이프 분리.

## Edge Cases

- 빈 파일 → 출력 없음, exit 0
- 줄 수 수억 개 → GNU sort는 자동으로 임시파일 merge sort 사용 (`--temporary-directory` 로 경로 지정 가능)
- `-k` 지정 시 필드 구분자 기본값은 공백/탭 연속. `-t` 없이 CSV 처리 불가
- locale(`LC_ALL`)에 따라 알파벳 정렬 순서 달라짐 — 재현성 필요하면 `LC_ALL=C sort`

## Related Tools

| Tool | Relationship |
|---|---|
| `uniq` | **필수 후처리** — `sort \| uniq` 패턴의 짝 |
| `awk` | **Superset** — 다중 조건 정렬은 awk가 더 유연 |
| `cut` | **전처리** — 특정 필드만 추출 후 sort에 넘기는 패턴 |
| `comm` | **Complement** — 두 정렬 파일 비교 (sort 선행 필요) |

## Encountered In (Wargame Levels)
- [[Wargames/Bandit/Level_08]] (first use — `sort | uniq -u` 패턴)

## Concepts This Implements
- [[Concepts/Linux/Unix_Pipeline]]

## Quick Reference

```bash
sort file                    # 알파벳 정렬
sort -r file                 # 역순
sort -n file                 # 숫자 정렬
sort -rn file                # 숫자 내림차순
sort -u file                 # 정렬 + 중복 제거
sort -t: -k3 -n /etc/passwd  # 구분자 지정 + 3번째 필드 숫자 정렬
sort | uniq -c | sort -rn    # 빈도 카운트 + 내림차순 (핵심 3단 파이프)
LC_ALL=C sort file           # locale 무시, 순수 바이트 정렬
```

> [!flashcard]
> **Q**: `sort`의 가장 흔한 trap은?
> **A**: `-n` 없이 숫자 정렬. 기본은 lexicographic이므로 `"10" < "9"`. 숫자 데이터엔 반드시 `-n` 명시.

---

## Background

`sort`도 Unix Version 1(1971) 원시 도구. 초기 구현은 메모리에 전부 올리는 방식이었으나, GNU coreutils의 현재 `sort`는 **external merge sort** 구현 — RAM을 초과하는 파일도 임시 디스크 파일로 분할 후 merge. 알고리즘 수업의 merge sort가 실제 Unix 유틸에 그대로 적용된 사례.

## External Refs

- man page: `man sort`
- GNU coreutils: https://www.gnu.org/software/coreutils/manual/html_node/sort-invocation.html
