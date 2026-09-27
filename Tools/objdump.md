---
tool: objdump
category: binary-analysis
man_section: 1
related: [nm, xxd, strings]
last_used: 2026-09-27
tags: [tool, binary, elf, disassembly, static-analysis, llvm, binutils]
---

# `objdump`

## Purpose

오브젝트 파일을 **번역해서 보여준다** — 기계어 바이트 → 어셈블리 명령어, 섹션 내용,
헤더, 심볼. 실행하지 않는다. **번역기이자 계산기**다.

> [!tip] 이게 왜 중요한가
> 디스어셈블은 바이트를 읽어 mnemonic을 출력하는 순수 계산이다. 그 명령을 **실행하지
> 않으므로 호스트 CPU가 무엇이든 무관하다.** arm64 맥에서 x86-64 ELF를 읽는 데 아무 문제가
> 없다. "뜯기"(정적)와 "실행하기"(동적)는 요구 조건이 전혀 다른 작업이다.

---

## 🔴 두 개의 `objdump`가 있다 — 먼저 확인하라

이게 이 노트에서 가장 실무적인 부분이다. 이름이 같고 **플래그 문법과 지원 타깃이 다르다.**

```bash
objdump --version        # 반드시 먼저
```

| | **LLVM** (`Apple LLVM …`) | **GNU binutils** (`GNU objdump …`) |
|---|---|---|
| 지원 타깃 | **전부** — 한 바이너리에 모든 백엔드 | **빌드 시 지정한 하나만** |
| 어디에 | macOS `/usr/bin/objdump`, `llvm-objdump` | Linux 배포판 `binutils` 패키지 |
| 함수 하나만 | `--disassemble-symbols=NAME` | `--disassemble=NAME` |
| Intel 문법 | `--x86-asm-syntax=intel` | `-M intel` |

> [!warning] 직관과 반대되는 결과
> **arm64 리눅스 컨테이너의 `objdump`는 x86-64를 디스어셈블하지 못한다.**
> ```
> target: file format elf64-little
> objdump: can't disassemble for architecture UNKNOWN!
> ```
> Debian arm64의 GNU binutils는 aarch64 타깃으로만 빌드돼 있다. 반면 macOS의 LLVM판은
> 된다. **가능 여부는 OS도 CPU도 아니라 툴이 어떤 타깃으로 빌드됐는지가 정한다.**
> 컨테이너에서 굳이 하려면 `apt install binutils-x86-64-linux-gnu` →
> `x86_64-linux-gnu-objdump`. (같은 이유로 그 컨테이너의 `gdb`도 `gdb-multiarch`가 필요하다.)

`--version`의 `Registered Targets:` 목록에 `x86-64`가 있는지가 유일한 판정 기준이다.

---

## Common Flags

| Flag | Long | Effect |
|---|---|---|
| `-f` | `--file-headers` | 포맷·아키텍처·진입점 요약. **정찰 첫 명령** |
| `-h` | `--section-headers` | 섹션 목록 (이름/크기/주소) |
| `-d` | `--disassemble` | **실행 가능 섹션**만 디스어셈블 |
| `-D` | `--disassemble-all` | 모든 섹션 (데이터까지 — 보통 쓰레기) |
| | `--disassemble-symbols=N` | **함수 하나만** (LLVM 문법) |
| `-s` | `--full-contents` | 섹션 내용을 hex + ASCII로 덤프 |
| `-j` | `--section=NAME` | 그 섹션만 |
| `-t` | `--syms` | 심볼 테이블 (= [[Tools/nm]]) |
| `-T` | `--dynamic-syms` | 동적 심볼 |
| `-p` | `--private-headers` | **program header + dynamic section** |
| `-r` / `-R` | `--reloc` / `--dynamic-reloc` | 재배치 항목 |
| | `--x86-asm-syntax=intel` | Intel 문법 (LLVM) |
| `-l` | `--line-numbers` | 소스 줄 번호 (`-g`로 컴파일된 경우) |
| `-S` | `--source` | 소스와 어셈블리 나란히 |

---

## AT&T vs Intel — 피연산자 순서가 정반대다

```
AT&T  :  movq  %rsp, %rbp        # op src, dst   →  rbp ← rsp
Intel :  mov   rbp, rsp          # op dst, src   →  rbp ← rsp
```

**모르고 읽으면 모든 대입의 방향을 착각한다.** pwn 자료는 거의 전부 Intel이다.

| | AT&T | Intel |
|---|---|---|
| 순서 | `op src, dst` | `op dst, src` |
| 레지스터 | `%rbp` | `rbp` |
| 즉시값 | `$0x40` | `0x40` |
| 메모리 | `-0x40(%rbp)` | `[rbp - 0x40]` |
| 크기 접미사 | `movq`, `subq` | 없음 (피연산자로 추론) |

LLVM의 기본은 **AT&T**다. 항상 `--x86-asm-syntax=intel`을 붙여라.

---

## Idiomatic Examples

### 정찰 순서

```bash
objdump --version                              # 어느 판인가, x86-64 되나
objdump -f ./binary                            # 포맷·아키텍처·진입점
objdump -h ./binary                            # 섹션 지도
objdump -t ./binary | sort                     # 심볼 (또는 nm)
```

`-f`의 `start address`는 PIE 판별에 쓰인다 — `0x401050`처럼 `0x400000` 대역이면 No PIE,
`0x1050`처럼 작으면 PIE. → [[Concepts/Binary/ELF_Header_Fields]]

### 함수 하나 읽기

```bash
objdump -d --disassemble-symbols=main --x86-asm-syntax=intel ./binary
```

전체를 뽑으면 수백 줄이라 눈이 미끄러진다. 심볼이 살아 있으면 반드시 하나만 뽑아라.

### 문자열 상수 확인

```bash
objdump -s -j .rodata ./binary
```

`-s`는 **가상 주소와 함께** 덤프하므로, `lea rax, [rip + 0x...]`이 가리키는 곳에 무엇이
있는지 바로 대조된다. (`strings -t x`는 **파일 offset**을 주므로 주소 대조에 부적합하다.)

### 방어 기제 판독 (checksec 없이)

```bash
objdump -p ./binary | grep -A2 STACK          # PT_GNU_STACK 의 플래그 → NX
objdump -p ./binary | grep -E 'RELRO|BIND_NOW' # RELRO
objdump -t ./binary | grep stack_chk          # __stack_chk_fail → canary
od -A d -t x1 -N 20 ./binary                  # e_type → PIE
```

네 가지가 **서로 다른 구조**에 드러난다: program header / dynamic section / 심볼 테이블 /
ELF 헤더. `checksec`은 이 넷을 한 줄로 요약해 주는 래퍼다.

---

## 읽는 법 — 출력 해부

```
주소     기계어 바이트              Intel 문법
40123a: 48 83 ec 40               sub    rsp, 0x40
40124d: 48 8d 45 c0               lea    rax, [rbp - 0x40]
                     ^^
                     c0 = 192 = 부호 있는 8비트로 −64 = -0x40
```

**변위(displacement)가 명령 인코딩 안에 들어 있다.** 디스어셈블러가 만들어낸 숫자가 아니라
파일의 바이트다 — 정적 분석을 신뢰할 수 있는 이유.

### `#` 주석은 계산해 준 것만 붙는다

| 형태 | `#` 주석 | 왜 |
|---|---|---|
| `lea rax, [rip + 0xe12]` | ✅ `# 0x402008 <...>` | `rip`는 그 명령의 주소 — **정적으로 확정** |
| `lea rax, [rbp - 0x40]` | ❌ 없다 | `rbp`는 **런타임 값** — 계산 불가 |

**주석의 부재가 정보다.** 프레임 상대 좌표에는 `#`이 붙지 않는다.
RIP-relative 계산식: **`다음 명령의 주소` + `변위`**.

---

## Pitfalls

> [!warning] Common Mistakes
> 1. **플래그 문법을 확인하지 않는다.** GNU `--disassemble=NAME`을 macOS에서 쓰면
>    `unknown argument`다. 반대도 마찬가지. **`--version`을 먼저 보는 습관.**
> 2. **AT&T를 Intel로 착각해 읽는다.** 대입 방향이 반대라 모든 추론이 뒤집힌다.
> 3. **컨테이너가 더 낫다고 가정한다.** "리눅스 바이너리는 리눅스에서"가 틀릴 수 있다 —
>    타깃 지원은 빌드 구성의 문제다.
> 4. **`-D`를 `-d` 대신 쓴다.** 데이터 섹션을 명령어로 "번역"한 쓰레기가 수천 줄 나온다.
> 5. **stripped 바이너리에 `--disassemble-symbols`를 쓴다.** 이름이 없으니 실패한다.
>    `-d` 전체 + `-f`의 진입점에서 손으로 따라가야 한다.
> 6. **`strings -t x`의 offset을 가상 주소로 착각한다.** 파일 offset ≠ vaddr.
>    주소 대조는 `objdump -s -j .rodata`.

## Edge Cases

- `--start-address` / `--stop-address`로 주소 구간만 자를 수 있다 (stripped 바이너리에 유용)
- `-M intel`은 LLVM에서도 **부분적으로** 먹지만, 확실한 쪽은 `--x86-asm-syntax=intel`
- Mach-O·PE도 읽는다 (LLVM판은 특히 폭넓다)
- `objdump -d`는 명령 경계를 **선형 스윕**으로 추정한다 — 데이터가 코드 사이에 끼면 이후
  전체가 어긋난다. 재동기화는 사람이 판단해야 한다

## Related Tools

| Tool | Relationship |
|---|---|
| [[Tools/nm]] | **보완.** `nm`으로 이름→주소, `objdump -d`로 그 주소의 코드. `objdump -t`가 `nm`을 대체 가능 |
| [[Tools/xxd]] | 하위 수준 — 번역 없이 바이트만. 헤더 직접 판독 |
| [[Tools/strings]] | 보완 — 데이터 쪽 |
| `readelf` | 대안 (헤더 전문). **macOS에 없다** → `objdump -p`/`-h`로 대체 |
| `gdb` | **동적** 대응물. `objdump`는 컴파일러의 *의도*, `gdb`는 런타임의 *사실* |

## Encountered / Applied In

- External: local-only wargame tree (no-publish) — 함수 프롤로그에서 프레임 크기와 버퍼의
  `rbp` 상대 좌표를 읽어, 소스에 적혀 있지 않은 값을 확정하는 데 사용. 호스트가 타깃과
  다른 아키텍처였으나 정적 분석에는 영향이 없었다.

## Concepts This Implements

- [[Concepts/Binary/Stack_Frame_And_Call_Ret]]
- [[Concepts/Binary/ELF_Header_Fields]]
- [[Concepts/Linux/Static_Binary_Triage]]

## Quick Reference

```bash
objdump --version                                          # 어느 판? x86-64 되나?
objdump -f  f                                              # 아키텍처 + 진입점 (PIE 판별)
objdump -h  f                                              # 섹션 지도
objdump -t  f                                              # 심볼
objdump -p  f                                              # program header + dynamic (NX/RELRO)
objdump -d --disassemble-symbols=NAME --x86-asm-syntax=intel f    # 함수 하나, Intel
objdump -s -j .rodata f                                    # 문자열 (가상 주소 포함)
```

> [!flashcard]
> **Q**: arm64 맥에서 x86-64 ELF를 디스어셈블할 수 있는가? 판정 기준은 무엇인가?
> **A**: **가능하다.** 디스어셈블은 바이트→mnemonic 번역이고 실행이 아니므로 호스트 CPU와
> 무관하다. 판정 기준은 **툴이 그 타깃으로 빌드됐는지** — `objdump --version`의
> `Registered Targets:`에 `x86-64`가 있으면 된다. LLVM판은 전 타깃을 담고, GNU binutils는
> 하나만 담는다. 그래서 arm64 리눅스 컨테이너보다 macOS가 유리할 수 있다.

---

## Background

GNU binutils의 일부로 1990년대부터 있었고, `./configure --target=`으로 정한 **단일 타깃**용
바이너리를 만든다 (크로스 툴체인마다 `<triple>-objdump`가 따로 깔리는 이유). LLVM이
`llvm-objdump`를 같은 CLI로 내놓으면서 **모든 백엔드가 한 실행파일에** 들어갔고, Apple은
그것을 `/usr/bin/objdump`로 깔았다. 이름이 같아 혼동이 생기는 원인이 이 역사다.

## External Refs

- man page: `man 1 objdump`
- GNU binutils: https://sourceware.org/binutils/docs/binutils/objdump.html
- LLVM: https://llvm.org/docs/CommandGuide/llvm-objdump.html
