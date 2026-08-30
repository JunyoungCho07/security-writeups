---
tool: xxd
category: binary-analysis
man_section: 1
related: [od, hexdump, grep, strings]
last_used: 2026-08-30
tags: [tool, linux, binary, hexdump]
---

# `xxd`

## Purpose
바이트열을 16진수 + ASCII로 표시하는 **돋보기**. 검색 도구가 아니라, 이미 지목된 좁은 구간을 눈으로 확인하는 도구다.

## Full Signature
```
xxd [OPTIONS] [infile [outfile]]
xxd -r [OPTIONS] [infile [outfile]]     # reverse: hex dump → binary
```

## Common Flags

| Flag | Long | Effect | 왜 필요한가 |
|---|---|---|---|
| `-s N` | `--seek` | N바이트부터 출력 시작 | 없으면 처음부터 전부 쏟아진다. **16진도 받는다** (`-s 0x1a`), 음수는 끝 기준 |
| `-l N` | `--len` | N바이트만 출력 | 뒤를 잘라낸다. `-s`와 짝 |
| `-g N` | `--groupsize` | N바이트씩 묶어 표시 | **필드 크기에 맞추면** 눈이 훨씬 편하다 (`-g 4`) |
| `-c N` | `--cols` | 한 줄에 N바이트 | `-c 4`면 **한 줄 = 한 필드**가 되어 왼쪽 주소가 곧 필드 오프셋 |
| `-b` | `--binary` | 2진수로 출력 | 비트 단위(플래그·property bit)를 볼 때 |
| `-r` | `--revert` | hex dump → 바이너리 | 손으로 고친 덤프를 파일로 되돌린다 |
| `-p` | `--plain` | 주소·ASCII 없이 연속 hex만 | 다른 도구로 파이프할 때 |

**주소 컬럼은 파일 절대 오프셋이다** — `-s`를 써도 0부터 다시 세지 않는다. 그래서 계산한 인덱스와 그대로 대조된다.

## Idiomatic Examples

### 지목된 구간만 보기
```bash
xxd -s 16 -l 13 file.bin
```

### 4바이트 필드에 맞춰 정렬
```bash
xxd -s 8 -l 32 -g 4 file.bin
00000008: 08090a0b 0c0d0e0f 10111213 14151617  ................
```

### 한 줄 = 한 필드 (주소가 곧 필드 오프셋)
```bash
xxd -s 16 -l 16 -c 4 file.bin
00000010: 0809 0a0b  ....
00000014: 0c0d 0e0f  ....
```

### 바이너리 패치 (hex 편집 왕복)
```bash
xxd file.bin > dump.hex     # 덤프
vi dump.hex                 # 16진 자리를 손으로 수정
xxd -r dump.hex > new.bin   # 되돌리기
```

## Pitfalls

> [!warning] Common Mistakes
> 1. **`xxd | grep`은 줄 경계에서 끊긴다.** `xxd`는 16바이트마다 **인위적 개행**을 넣는 표시용 포맷이다. 원본에 없는 경계가 생겨 패턴이 갈리고, **"못 찾음"이 조용히 "없음"으로 오해된다.** 원본 바이트를 직접 뒤져라 → [[Tools/grep]] `-abo`.
> 2. **`-s` 없이 큰 파일에 쓰면** 파일 크기 ÷ 16 줄이 쏟아진다. 400KB면 2만 5천 줄이다.
> 3. **`-r` 왕복 시 주소 컬럼이 어긋나면** 되돌린 결과가 밀린다. 편집할 땐 hex 자리만 건드리고 주소·길이를 유지해라.

## Edge Cases
- `-c` 값에 따라 ASCII 컬럼 폭이 바뀌므로 파이프로 후처리할 땐 `-p`가 안전하다.
- 표시용 ASCII 컬럼은 출력 불가 문자를 `.`으로 대체한다 — `.`이 실제 `0x2e`인지 아닌지는 hex 쪽을 봐야 한다.

## Related Tools

| Tool | Relationship |
|---|---|
| [[Tools/grep]] | complement — grep이 *어디*를 찾고, xxd가 *무엇*인지 본다 |
| `od -A x -t x1z` | alternative — POSIX 표준, 어디에나 있다 (xxd는 vim 패키지 소속) |
| `hexdump -C` | alternative — BSD 계열 기본 |
| [[Tools/strings]] | complement — 사람이 읽을 수 있는 조각만 뽑는다 |

## Encountered In
- External: local-only wargame tree (no-publish) — 컨테이너 헤더 필드 확인

## Concepts This Implements
- [[Concepts/Binary/Binary_Number_Encoding]] — 16진 표기가 바이트 경계와 맞아떨어지는 이유
- [[Concepts/Binary/Binary_Format_Forensics]] — 도구 역할 분담에서 "돋보기" 자리
- [[Concepts/Linux/File_Signatures]] — 시그니처 확인
- [[Concepts/Linux/Strings_Extraction]] — 읽을 수 있는 조각만 뽑는 짝 도구

## Quick Reference

```bash
xxd -s N -l M file            # N번지부터 M바이트
xxd -s N -l M -g 4 file       # 4바이트씩 묶어서
xxd -s N -l M -c 4 file       # 한 줄에 4바이트 = 한 필드
xxd -s N -l 4 -b file         # 비트로
xxd -p file | tr -d '\n'      # 연속 hex 한 줄
```

> [!flashcard]
> **Q**: `xxd` 출력을 `grep`하면 안 되는 이유는?
> **A**: `xxd`는 16바이트마다 인위적 개행을 넣는 **표시용** 포맷이다. 원본에 없는 줄 경계에서 패턴이 갈려 조용히 못 찾는다. 원본 바이트에 `grep -abo`를 써라.

---

## Background
vim 배포판에 딸려 오는 도구(Juergen Weigert 작성). `od`·`hexdump`와 달리 **`-r`로 되돌릴 수 있게** 설계된 것이 특징 — hex 덤프를 텍스트 편집기로 고쳐 다시 바이너리로 만드는 왕복 워크플로가 목적이었다.

## External Refs
- man page: `man 1 xxd`
