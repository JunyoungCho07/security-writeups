---
tool: strings
category: binary-analysis
man_section: 1
related: [nm, objdump, xxd, grep]
last_used: 2026-09-29
tags: [tool, binary, elf, static-analysis, recon]
---

# `strings`

## Purpose

바이너리에서 **연속된 출력 가능 문자**를 뽑아낸다. 한 줄로: **바이트 더미에서 사람이 읽을 수
있는 조각만 걸러 보여준다.**

용도가 두 층으로 나뉘고, 두 번째가 실무에서 더 중요하다:

| 층 | 무엇을 얻나 |
|---|---|
| 정찰 | 경로·URL·에러 메시지·포맷 문자열 — 프로그램이 무엇을 하는지의 단서 |
| **좌표** | **그 문자열이 파일 안 몇 번째 바이트인지** (`-t`) — 주소 계산의 입력값 |

## Full Signature

```
strings [-a] [-n LEN] [-t RADIX] [-e ENCODING] <file>...
```

## Common Flags

| Flag | Long | Effect | 왜 쓰나 |
|---|---|---|---|
| `-a` | `--all` | **파일 전체**를 스캔 | ⭐ 아래 §Pitfalls 1 — 기본값은 전체가 아니다 |
| `-t x` | `--radix=x` | 각 문자열 앞에 **오프셋**을 16진수로 | ⭐ 좌표를 얻는 유일한 방법. `d`=10진, `o`=8진 |
| `-n N` | `--bytes=N` | 최소 길이 N (기본 4) | `-n 8` 로 노이즈 줄이기, `-n 2` 로 짧은 것까지 |
| `-e l` | `--encoding=` | 16/32비트 인코딩 | UTF-16 문자열 (윈도우 바이너리, 일부 리소스) |
| `-f` | `--print-file-name` | 각 줄에 파일명 | 여러 파일을 한 번에 |

## Idiomatic Examples

### 정찰 — 무엇을 하는 프로그램인가

```bash
$ strings -n 8 ./binary | less
```

`-n 8` 로 4글자 우연 일치를 줄인다. 찾을 것: 경로(`/etc/`, `/tmp/`), 포맷 문자열(`%s`, `%p`),
에러 메시지, 환경변수 이름, 명령 문자열.

### ⭐ 좌표 얻기 — 라이브러리 안의 문자열 주소

```bash
$ strings -a -t x libc.so.6 | grep '/bin/sh'
 1b45cf /bin/sh
```

`-a` 로 전체를 보고 `-t x` 로 오프셋을 함께 찍는다. 이 값이 ret2libc 의 입력이 된다 →
[[Concepts/Binary/Ret2Libc_Pattern]] §C

> [!warning] ⭐ 이 숫자는 **파일 오프셋**이다 — 가상 주소가 아니다
> `strings` 는 파일을 바이트 배열로 훑을 뿐 `PT_LOAD` 세그먼트를 모른다. 적재된 뒤의 주소는
> ```
> vaddr = 파일오프셋 − seg.off + seg.vaddr
> ```
> 로 변환해야 한다 (그 오프셋을 **포함하는** `LOAD` 세그먼트의 두 값). 변환식과 측정된
> 반례는 [[Concepts/Binary/ELF_Sections_And_Relocation]] §G.
>
> 공유 라이브러리의 코드/rodata 세그먼트는 보통 `off == vaddr` 여서 **값이 그대로 통과한다** —
> "libc 는 strings 오프셋 그대로 쓰면 된다"는 통설의 정체다. **규칙이 아니라 우연이므로
> 확인해야 한다.** 같은 파일의 `rw-` 세그먼트는 `0x1000` 어긋나 있다.

### 심볼과 대조

```bash
$ nm -D libc.so.6 | grep ' system'     # 함수는 심볼표에 (이미 vaddr)
$ strings -a -t x libc.so.6 | grep sh  # 문자열은 바이트에 (파일 오프셋)
```

⭐ **함수와 문자열은 찾는 곳도 좌표계도 다르다.** 문자열은 심볼이 아니라서 `nm` 에 없다.

## Pitfalls

> [!warning] Common Mistakes
> 1. **기본값은 "파일 전체"가 아니다.** GNU `strings` 는 기본적으로 **적재되는 섹션만**
>    스캔한다 (`--data` 가 기본). 디버그 섹션이나 헤더 안의 문자열은 `-a` 없이는 안 보인다.
>    구현마다 기본값이 다르므로 **정찰에는 항상 `-a`** 를 붙이는 게 안전하다.
> 2. **`-t` 없이 얻은 문자열은 좌표가 없다.** 나중에 위치를 다시 찾으려면 처음부터 `-t x`
>    를 붙였어야 한다. 습관화할 것.
> 3. **파일 오프셋 ≠ 가상 주소** — 위 경고 블록. 이 혼동으로 주소가 정확히 페이지 크기만큼
>    틀어지는 사고가 난다.
> 4. **없다고 없는 게 아니다.** 압축·암호화·난독화된 데이터, UTF-16 문자열(`-e l` 필요),
>    런타임에 조립되는 문자열은 안 나온다. `strings` 가 비었다는 것은 **정보가 아니라
>    방법의 한계**다.
> 5. **우연한 일치가 많다.** 기계어 바이트가 우연히 ASCII 범위에 들어가면 쓰레기 문자열이
>    나온다. `-n` 을 올려 걸러라. → [[Tools/objdump]] 의 `-s` 출력 ASCII 칸과 같은 문제다.

## Edge Cases

- 아카이브(`.a`)·코어 덤프·디스크 이미지에도 그대로 동작한다 — 포맷을 몰라도 되는 것이 장점
- **stripped 바이너리에서 가치가 올라간다.** 심볼이 지워져도 문자열은 남는다
  ([[Tools/nm]] 이 무력해지는 지점)
- macOS `/usr/bin/strings` 는 LLVM 판. 기본 동작이 GNU 판과 미묘하게 다르므로 `-a` 를 명시
- 바이너리가 아닌 텍스트 파일에 쓰면 그냥 원본이 나온다 (무해하지만 의미 없음)

## Related Tools

| Tool | Relationship |
|---|---|
| [[Tools/nm]] | **보완.** 심볼(이름↔주소)은 `nm`, 데이터 문자열은 `strings`. 찾는 대상이 다르다 |
| [[Tools/objdump]] | **보완.** `objdump -s -j .rodata` 는 같은 문자열을 **섹션 맥락과 함께** 보여준다. `strings` 는 맥락 없이 전체를 훑는다 |
| [[Tools/xxd]] | 하위 수준 — 오프셋을 알아낸 뒤 그 주변 생바이트를 확인 |
| [[Tools/grep]] | 거의 항상 파이프로 이어진다. `-a` 옵션의 역할이 두 도구에서 비슷하다(바이너리 취급 안 함) |
| `file` | 선행 — 무슨 파일인지 먼저 안 뒤에 문자열을 본다 |

## Encountered / Applied In

- External: local-only wargame tree (no-publish) — 공유 라이브러리 안 `"/bin/sh"` 의 위치를
  얻기 위해. 심볼표에 없는 값이라 `strings -a -t x` 가 유일한 경로였고, 그 결과가 **파일
  오프셋**이라 `PT_LOAD` 변환 단계가 필요하다는 것을 여기서 배웠다.

## Concepts This Implements

- [[Concepts/Linux/Strings_Extraction]] — 이 도구가 구현하는 개념 (그쪽이 primary)
- [[Concepts/Linux/Static_Binary_Triage]]
- [[Concepts/Binary/ELF_Sections_And_Relocation]]
- [[Concepts/Binary/Ret2Libc_Pattern]]

## Quick Reference

```bash
strings -n 8 f | less             # 정찰: 노이즈 줄여서 훑기
strings -a -t x f | grep PATTERN  # ⭐ 좌표까지 — 주소 계산용
strings -a -n 2 f                 # 짧은 것까지 전부
strings -e l f                    # UTF-16
```

> [!flashcard]
> **Q**: `strings -t x` 가 출력하는 숫자를 그대로 런타임 주소로 쓰면 안 되는 이유는?
> **A**: 그것은 **파일 오프셋**이다. 적재 주소는 `PT_LOAD` 세그먼트의 `off`/`vaddr` 쌍으로
> 변환해야 한다. 공유 라이브러리의 코드·rodata 세그먼트는 대개 둘이 같아서 우연히
> 맞아떨어지지만, `rw-` 세그먼트에서는 어긋난다.

---

## Background

`strings` 는 원래 **실행 파일에 어떤 버전 문자열이 박혀 있나**를 보려고 만든 Unix 도구다
(V7 Unix). 지금은 리버싱·포렌식의 첫 명령으로 훨씬 많이 쓰인다. GNU binutils 판과 LLVM 판이
있고 기본 스캔 범위가 다르다.

## External Refs

- man page: `man 1 strings`
- GNU binutils docs: https://sourceware.org/binutils/docs/binutils/strings.html
