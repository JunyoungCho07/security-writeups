---
tool: nm
category: binary-analysis
man_section: 1
related: [objdump, strings, xxd, readelf]
last_used: 2026-09-29
tags: [tool, binary, elf, symbols, static-analysis]
---

# `nm`

## Purpose

오브젝트 파일·실행파일·라이브러리의 **심볼 테이블**을 덤프한다. 한 줄로: **이름 → 주소** 표를 보여준다.

> [!definition] Symbol
> 파일에 기록된 **이름 ↔ 주소** 짝. `handler`라는 이름이 `0x401345`에 해당한다는 사실이
> 파일 안의 표(symbol table)에 저장돼 있다. 링커가 이름을 주소로 치환하기 위해 만든 것이고,
> 링크가 끝나면 **실행에는 필요 없다** — 그래서 `strip`으로 지울 수 있다.

심볼 테이블은 **디버거와 사람을 위한 선물**이다. 남아 있으면 함수 주소를 한 줄로 얻는다.

## Full Signature

```
nm [OPTIONS] <objfile>...
```

인수를 안 주면 `a.out`을 본다.

## Output Format

```
0000000000401345 T handler
^^^^^^^^^^^^^^^^ ^ ^^^^^^^
     주소       타입 이름
```

주소 칸이 **빈** 줄은 정의가 없는 심볼이다 (`U`, `w`).

## 타입 글자 — 대문자 = 전역, 소문자 = 지역(`static`)

| 글자 | 뜻 | 어디에 |
|---|---|---|
| `T` / `t` | **Text** — 실행 코드 | 함수 |
| `D` / `d` | Data — 초기값 있는 전역 변수 | `.data` |
| `B` / `b` | **BSS** — 초기값 0인 전역 변수 | `.bss` |
| `R` / `r` | Read-only data | 문자열 상수, 상수 배열 |
| `U` | **Undefined** — 이 파일에 없다, 외부에서 와야 한다 | libc 함수 |
| `W` / `w` | Weak — 다른 정의가 있으면 양보 | |
| `A` | Absolute — 재배치되지 않는 절대값 | |
| `N` | 디버깅 심볼 | |
| `?` | 미분류 | |

`U`가 실무상 가장 유용하다 — **이 바이너리가 어떤 외부 함수에 의존하는지**의 목록이다.

⚠️ **`W`(weak)를 "쓸 수 없는 주소"로 오해하지 마라.** glibc 는 `system`·`puts` 같은 함수를
**weak alias** 로 내놓으므로 라이브러리 심볼표에서 `W` 로 보이는 것이 정상이다. 주소 값은
`T` 와 똑같이 유효하다. `W` 가 말하는 것은 "다른 정의가 있으면 양보한다"는 **링크 시점의 규칙**
이고, 이미 링크된 라이브러리를 읽을 때는 무관하다.

## Common Flags

| Flag | Long | Effect | 왜 쓰나 |
|---|---|---|---|
| | `--defined-only` | `U` 심볼 숨김 | 이 파일이 **제공**하는 것만 보고 싶을 때 |
| `-u` | `--undefined-only` | `U`만 | 의존성 목록 |
| `-n` | `--numeric-sort` | 주소 순 정렬 | **함수들의 메모리 배치 순서**가 보인다 |
| `-S` | `--print-size` | 심볼 크기도 출력 | 함수 길이 |
| `-C` | `--demangle` | C++ 맹글링 복원 | C++ 바이너리 |
| `-D` | `--dynamic` | 동적 심볼 테이블 | stripped 바이너리에도 남는다 |
| `-A` | `--print-file-name` | 각 줄에 파일명 | 여러 `.o`를 한 번에 |

## Idiomatic Examples

### 정찰 — 전체를 본다

```bash
$ nm --defined-only -n ./binary
```

`-n`으로 주소 정렬하면 배치 순서가 드러나고, `--defined-only`로 libc 노이즈를 뺀다.

> [!warning] `grep`으로 먼저 걸러내지 마라
> `nm b | grep -E 'handler|main'`은 **네가 이름을 아는 것만** 보여준다. 처음 보는 바이너리에서는
> 작성자가 남긴 예상 밖의 함수·전역 변수가 정보다. 필터는 **무엇을 찾는지 이미 알 때**의 도구다.

### 의존성만

```bash
$ nm -u ./binary
                 U puts@GLIBC_2.2.5
                 U read@GLIBC_2.2.5
```

`@GLIBC_2.2.5`는 **symbol versioning** — "glibc 2.2.5 이후 버전의 그것으로 링크"라는 표시다.
같은 함수가 ABI를 바꿨을 때 구버전 바이너리가 깨지지 않게 하는 장치. 주소 계산과는 무관하다.
단 **가장 높은 버전 요구치가 실행 환경의 최소 glibc 버전**이 된다 (`__libc_start_main@GLIBC_2.34`
가 있으면 glibc 2.34 미만에서는 실행 불가).

### 함수 크기와 배치

```bash
$ nm -nS --defined-only ./binary
```

### ⭐ 공유 라이브러리에서 오프셋 뽑기 (ret2libc)

```bash
$ nm -D libc.so.6 | grep -E ' (system|puts)$'
000000000004f4e0 W system@@GLIBC_2.2.5
00000000000823a0 W puts@@GLIBC_2.2.5
```

`-D`(동적 심볼표)가 `.so` 의 실질적 심볼 목록이다. 값의 의미가 중요하다:

> `libc.so.6` 은 `ET_DYN` 이므로 이 숫자들은 **절대 주소가 아니라 적재 base 로부터의
> 오프셋**이다. 실행 중 주소는 `base + 이 값`. → [[Concepts/Binary/ELF_Header_Fields]] §F

⚠️ **문자열은 이 목록에 없다.** `"/bin/sh"` 는 심볼이 아니라 `.rodata` 의 바이트다 →
[[Tools/strings]]. 그리고 그쪽은 좌표계가 달라서(파일 오프셋) 변환이 필요하다 →
[[Concepts/Binary/ELF_Sections_And_Relocation]] §G

## Pitfalls

> [!warning] Common Mistakes
> 1. **stripped 바이너리에는 아무것도 없다.** `nm: no symbols`가 나오면 `strip`된 것이다.
>    `-D`(동적 심볼)은 남아 있을 수 있으니 먼저 시도해라. 그래도 없으면 `objdump -d`로
>    코드를 읽어 함수 경계를 직접 찾아야 한다.
> 2. **PIE 바이너리의 주소는 최종 주소가 아니다.** `e_type`이 `ET_DYN`이면 `nm`의 값은
>    **base로부터의 offset**이고, 실행 시 base가 더해진다. `ET_EXEC`(No PIE)일 때만 그
>    숫자가 실행 중 주소와 같다. → [[Concepts/Binary/ELF_Header_Fields]]
> 3. **`nm`은 정렬하지 않는다** (기본은 이름 순). 배치를 보려면 `-n`을 명시해라.
> 4. **`U` 심볼의 빈 주소 칸을 0으로 착각하지 마라.** 주소가 없는 것이지 0이 아니다.
> 5. ⭐ **"없음"을 증거로 쓸 때는 그 출력이 "있음"을 보여줄 수 있는지 먼저 확인해라.**
>    실제로 물린 사례: `--defined-only`(또는 그에 준하는 필터)로 목록을 뽑아 놓고
>    "`__stack_chk_fail` 이 없다 → canary 없다"라고 결론냈다. 그 출력에는 `U` 줄이 **하나도**
>    없었다 — 동적 링크 바이너리인데 그럴 수가 없다. **판별법:** 반드시 있어야 하는 다른 `U`
>    심볼(`puts` 등 호출하는 libc 함수)이 보이는지 본다. 안 보이면 판정 자체가 무효다.
>    → [[Concepts/Binary/Memory_Protections]] §D

## Edge Cases

- 아카이브(`.a`)에 쓰면 멤버별로 나온다 — `-A`로 어느 `.o`인지 표시
- 공유 라이브러리(`.so`)는 `-D`가 실질적인 심볼 목록
- macOS Mach-O에도 동작하지만 타입 글자 집합이 약간 다르다 (`T`/`U`는 동일)

## Related Tools

| Tool | Relationship |
|---|---|
| [[Tools/objdump]] | **보완.** `nm`은 이름→주소, `objdump -d`는 그 주소의 코드. 보통 `nm`으로 좌표를 잡고 `objdump`로 읽는다 |
| [[Tools/objdump]] (`-t`) | **대안.** `objdump -t`도 심볼 테이블을 낸다 (출력 형식만 다름) |
| [[Tools/strings]] | **보완 — 좌표계가 다르다.** `nm` 값은 가상 주소(또는 base 상대), `strings -t` 값은 **파일 오프셋**. 섞으면 세그먼트 차이만큼 틀린다 |
| [[Tools/xxd]] | 하위 수준 — 헤더 바이트를 직접 볼 때 |
| `readelf -s` | 대안. **macOS에는 없다** (`readelf` 미설치) — `nm` / `objdump -t`로 대체 |

## Encountered / Applied In

- External: local-only wargame tree (no-publish) — 호출되지 않는 함수의 주소를 얻기 위해.
  아무도 부르지 않는 함수는 디스어셈블리 어디에도 등장하지 않으므로, **심볼 테이블만이
  그 주소를 알려준다.**

## Concepts This Implements

- [[Concepts/Binary/ELF_Header_Fields]]
- [[Concepts/Linux/Static_Binary_Triage]]
- [[Concepts/Binary/Ret2Libc_Pattern]] — `-D` 로 뽑은 오프셋이 쓰이는 곳
- [[Concepts/Binary/Memory_Protections]] — canary 판독이 심볼표에 의존한다

## Quick Reference

```bash
nm --defined-only -n f       # 이 파일이 제공하는 심볼, 주소 순   ← 정찰 기본
nm -u f                      # 외부 의존성 (+ 최소 glibc 요구치)
nm -nS --defined-only f      # 주소 + 크기
nm -D f                      # 동적 심볼표 — .so 의 실질 목록 / stripped 일 때 마지막 희망
nm -D libc.so.6 | grep ' system$'   # ret2libc 오프셋 (값 = base 상대)
nm -C f                      # C++ 이름 복원
```

> [!flashcard]
> **Q**: `nm`의 출력에서 `T`와 `U`의 차이는 무엇이고, 왜 그 구분이 중요한가?
> **A**: `T`는 **이 파일에 코드가 있고 주소가 정해진** 심볼, `U`는 **외부에서 와야 하는**
> 미정의 심볼(주소 칸이 비어 있다). `T`의 주소는 쓸 수 있는 값이고 `U`는 아니다 —
> 단, `T`의 주소가 실행 중 주소와 같은 것은 **No PIE(`ET_EXEC`)일 때만**이다.

---

## Background

`nm` = **n**a**m**e list. 이름은 초기 Unix의 `a.out` 포맷 시절부터 왔고, 1970년대부터
거의 같은 이름·같은 역할로 남아 있다. GNU binutils 판과 LLVM 판(`llvm-nm`)이 있고,
macOS의 `/usr/bin/nm`은 LLVM 쪽이다.

## External Refs

- man page: `man 1 nm`
- GNU binutils docs: https://sourceware.org/binutils/docs/binutils/nm.html
