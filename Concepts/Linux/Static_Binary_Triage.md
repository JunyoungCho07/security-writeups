---
date: 2026-07-23
domain: Linux
topic: Static_Binary_Triage
tags: [linux, reversing, elf, file, strings, static-analysis]
status: 🟡 developing
note_tier: lite
mastery: 35
first_encountered: [[Wargames/Bandit/Level_26]]
reapplied_in: [[[Wargames/Bandit/Level_32]]]
---

# Static Binary Triage

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> Bandit L26(26→27)에서 `bandit27-do`의 동작을 소스 없이 추론하며 판 개념. `file`+`strings` first-look. `/deep` 시 ELF 헤더/섹션, `objdump`/`readelf`/`nm`, gef/pwndbg 동적 분석까지.

## Definition (Formal, EN)

**Static binary triage** is inferring an executable's behavior *without source* from cheap first-look tools: **`file`** (type, architecture, setuid bit, strip state) and **`strings`** (embedded literals — paths, usage text, `libc` symbols, source-file stem). For a non-stripped binary this is often enough to reconstruct its control flow before any disassembly.

## Intuition (KR)

상자를 못 열어도 **겉면 라벨(`file`)과 새어나온 쪽지(`strings`)**만으로 내용물을 짐작한다. "setuid, 32-bit, 심볼 안 지움" + "`/usr/bin/env`를 부른다" → "권한만 소유자인, 명령 대신 실행해주는 배달부".

## Key Points (무엇을 팠나)

### A. `file` 이 알려주는 것
- 파일 종류(ELF/Mach-O), **아키텍처**(i386/x86-64/arm64), 링크(dynamic/static), **setuid 비트**(핵심), **strip 여부**(`not stripped`=심볼 남음=리버싱 쉬움).
- L26: `bandit27-do: setuid ELF 32-bit i386 … not stripped` → 권한 상승 래퍼임을 즉시 파악.

### B. `strings` 가 누설하는 로직
- 임베디드 문자열에서 `execv`, `/usr/bin/env`, usage 텍스트(`Run a command as another user`), 소스 stem(`bandit27.c`), `GLIBC_2.34` → 내부를 `execv("/usr/bin/env", argv)` 래퍼로 재구성.
- `-n <len>`로 짧은 노이즈 컷. **`cat`은 금지**: raw 제어문자가 터미널 파손(→ `reset`). 정찰은 `strings`/`xxd`/`objdump`.

### C. 확증 (필요 시)
- `objdump -d`(not stripped라 심볼 보임)/`readelf`/`nm`으로 라벨+문자열 추론을 코드로 검증. L32의 "왜 bash도 권한 유지"(=`setreuid` 호출) 확인도 이 방식.

## Encountered / Applied In
- [[Wargames/Bandit/Level_26]] — `bandit27-do`(env-wrapper setuid) 동작 추론.
- [[Wargames/Bandit/Level_32]] — `uppershell`이 real uid까지 고정(`setreuid`)했는지 `objdump`로 확인 가능(not stripped). [[Setuid]] 문맥.

## Expand Later (`/deep` candidates)
- **`/deep ELF_Format`** — 헤더/프로그램·섹션 헤더, `.text`/`.rodata`/`.symtab`, dynamic linking, PLT/GOT.
- **`/deep Reversing_Toolchain`** — `objdump`/`readelf`/`nm`/`strings`/`ltrace`/`strace`, gef·pwndbg·radare2.
