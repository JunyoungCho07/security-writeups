---
tool: grep
category: text-processing
man_section: 1
related: [xxd, strings, sed, awk, find]
last_used: 2026-08-30
tags: [tool, linux, search, binary, regex]
---

# `grep`

## Purpose
입력에서 패턴에 맞는 부분을 찾는다. **바이너리에도 쓸 수 있다** — 그때는 "줄"이 아니라 **바이트 오프셋**을 얻는 도구가 된다.

## Full Signature
```
grep [OPTIONS] PATTERN [FILE...]
grep [OPTIONS] -e PATTERN -f PATTERNFILE [FILE...]
```

## Common Flags

### 바이너리 검색 3종 세트 — 이게 핵심이다

| Flag | Long | Effect | 왜 필요한가 |
|---|---|---|---|
| `-a` | `--text` | 이진 파일을 텍스트로 취급 | 없으면 `Binary file X matches` 한 줄만 나오고 끝난다 |
| `-b` | `--byte-offset` | 매치의 **바이트 오프셋** 출력 | **이게 핵심.** 위치를 숫자로 준다 |
| `-o` | `--only-matching` | 매치된 부분만 출력 | 없으면 "줄 전체"를 뱉는데, 바이너리는 개행이 없어 **파일 전체가 한 줄**일 수 있다 |

`grep -abo PATTERN file` — 이 조합이 바이너리에서 구조 마커의 위치를 뽑는 표준 형태다. **줄 경계와 완전히 무관**하게 동작한다.

### 그 밖에 자주 쓰는 것

| Flag | Effect |
|---|---|
| `-c` | 매치 **개수**만 |
| `-i` | 대소문자 무시 |
| `-v` | 매치 **안 되는** 줄 (역선택) |
| `-n` | 줄 번호 (텍스트용) |
| `-r` / `-R` | 디렉토리 재귀 |
| `-E` | 확장 정규식 (`egrep`) |
| `-P` | PCRE — **출력 불가 바이트를 `\xNN`으로 찾을 수 있다** (GNU 전용) |
| `-F` | 고정 문자열 (정규식 해석 안 함, 가장 빠름) |

## Idiomatic Examples

### 바이너리에서 구조 마커 위치 뽑기
```bash
grep -abo 'IDAT' file.png
87:IDAT
65544:IDAT
```
왼쪽 숫자가 **파일 시작에서의 바이트 오프셋**이다. 그대로 `xxd -s`나 파이썬 슬라이스에 넣을 수 있다.

### 출력 불가 바이트 패턴 찾기 (GNU grep)
```bash
grep -aboP "\xde\xad\xbe\xef" file.bin
```

### 개수만 세기
```bash
grep -c 'IDAT' file.png        # ← -a 없으면 바이너리에서 0/1만 나올 수 있다
grep -abo 'IDAT' file.png | wc -l
```

## Pitfalls

> [!warning] Common Mistakes
> 1. ⭐ **`xxd | grep`은 조용히 실패한다.** `xxd`가 16바이트마다 넣는 인위적 개행에서 패턴이 갈린다. **원본 파일을 직접 grep해라.** 이건 "운이 좋으면 되는" 방법이고, 가장 위험한 종류의 실패다 — 못 찾았다고 없는 게 아니다.
> 2. **`-a` 없이 바이너리를 grep하면** `Binary file … matches`만 나오고 위치를 못 얻는다.
> 3. **`-o` 없이 바이너리를 grep하면** 개행이 없어 파일 전체가 한 줄로 쏟아질 수 있다.
> 4. **`-P`는 GNU 전용.** macOS 기본 grep(BSD)에는 없다 — `ggrep`(coreutils) 또는 컨테이너 쪽을 써라.
> 5. **정규식 메타문자**(`.` `*` `[` `\`)가 든 리터럴을 찾을 땐 `-F`. 바이너리 마커에 자주 섞인다.

## Edge Cases
- 매치가 겹칠 때 `-o`는 **겹치지 않는 것만** 낸다 (`aaaa`에서 `aa`는 2개).
- `-b`의 오프셋은 `-o`와 함께 쓸 때 **매치 시작 위치**, 없이 쓰면 **줄 시작 위치**다. 바이너리에선 반드시 같이 써라.
- 매우 긴 "줄"(개행 없는 바이너리)은 메모리를 크게 먹을 수 있다.

## Related Tools

| Tool | Relationship |
|---|---|
| [[Tools/xxd]] | complement — grep이 *어디*인지 찾고, xxd가 그 자리를 *본다* |
| [[Tools/strings]] | alternative — 패턴을 모를 때 읽을 수 있는 조각을 전부 뽑는다 |
| `bgrep` / `binwalk` | alternative — 바이너리 전용 검색·시그니처 스캔 |

## Encountered In
- External: local-only wargame tree (no-publish) — 컨테이너 레코드 마커 오프셋 수집 (파서 결과의 독립 검증에 사용)

## Concepts This Implements
- [[Concepts/Binary/Binary_Format_Forensics]] — 독립된 두 방법의 교차검증 오라클
- [[Concepts/Binary/Chunked_Container_Formats]] — 레코드 마커 찾기
- [[Concepts/Linux/Regex_Flavors]] — `-E` / `-P` / 기본(BRE)의 차이
- [[Concepts/Linux/Strings_Extraction]] — 패턴을 모를 때의 대안 경로

## Quick Reference

```bash
grep -abo 'MARKER' file        # 바이너리에서 오프셋 뽑기 ← 기억할 하나
grep -aboP "\xNN\xNN" file     # 출력 불가 바이트 (GNU)
grep -c PATTERN file           # 개수
grep -rn PATTERN dir/          # 재귀 + 줄번호 (소스 검색)
grep -Fv PATTERN file          # 리터럴 + 역선택
```

> [!flashcard]
> **Q**: 바이너리에서 마커 위치를 찾는 grep 조합과 각 플래그의 이유는?
> **A**: `grep -abo`. `-a`=이진을 텍스트 취급(없으면 "matches"만), `-b`=바이트 오프셋 출력(핵심), `-o`=매치 부분만(없으면 개행 없는 파일 전체를 뱉는다).

---

## Background
이름은 `ed` 편집기의 명령 `g/re/p` (**g**lobally search for a **r**egular **e**xpression and **p**rint)에서 왔다. Ken Thompson이 1973년 그 기능을 독립 실행 파일로 떼어낸 것이 시초 — 유닉스 "한 가지를 잘하는 작은 도구" 철학의 대표 사례로 자주 인용된다.

## External Refs
- man page: `man 1 grep`
- GNU docs: https://www.gnu.org/software/grep/
