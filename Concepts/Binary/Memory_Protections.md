---
date: 2026-09-28
domain: Binary
topic: Memory_Protections
tags: [binary, exploitation, mitigations, nx, aslr, canary, relro, pie, elf]
status: 🟡 developing
note_tier: lite
mastery: 50
first_encountered: "External: local-only wargame tree (no-publish) — checksec 없이 ELF에서 네 방어 기제를 직접 판독"
reapplied_in: []
---

# Memory Protections

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> `checksec` 이 요약해 주는 네 줄을 **ELF에서 손으로 읽은** 스레드. 핵심은 개별 기제가
> 아니라 **넷이 서로 다른 계층에서 구현되므로 서로 다른 구조에 드러난다**는 것.

## Definition (Formal, EN)

The four standard stack-exploitation mitigations are implemented by **four different
components** — the linker, the loader/CPU, the dynamic linker, and the compiler — and each
therefore leaves its evidence in a **different ELF structure**. Reading them is four separate
questions, not one.

## Intuition (KR)

"보호가 켜져 있나"는 한 질문이 아니라 **네 질문**이다. 그리고 각각 어디를 봐야 하는지가 다르다.

## Key Points (무엇을 팠나)

### A. ⭐ 대응표 — 넷이 네 곳에 있다

| 방어 | 어느 ELF 구조 | 명령 | 켜짐 | 구현 주체 |
|---|---|---|---|---|
| **PIE** | ELF 헤더 `e_type` (offset `0x10`) | `od -A d -t x1 -N 20` | `03 00` = ET_DYN | **링커** |
| **NX** | program header, `STACK` 세그먼트 flags | `objdump -p` | `rw-` (꺼짐이 `rwx`) | **로더 + CPU** |
| **RELRO** | program header `RELRO` 세그먼트 **+** dynamic section `FLAGS` | `objdump -p` | 둘 다 = Full | **동적 링커** |
| **Canary** | **심볼 테이블**, `U`(미정의) 쪽 | `nm -u` | `__stack_chk_fail` 존재 | **컴파일러** |

`e_type` 판독은 [[Concepts/Binary/ELF_Header_Fields]] §B 에, 두 헤더 표의 구분은
[[Concepts/Binary/ELF_Sections_And_Relocation]] §A 에 있다.

### B. 전제: 메모리는 구역이고 구역마다 권한 3비트가 있다

| 비트 | 뜻 |
|---|---|
| `r` | 값을 읽을 수 있다 |
| `w` | 값을 바꿀 수 있다 |
| `x` | **CPU가 그 바이트를 명령어로 실행해도 된다** |

⭐ **`x` 가 코드와 데이터를 구분하는 유일한 장치다.** 메모리에 "코드"라는 태그는 없다.
같은 바이트이고, `x` 권한이 있으면 코드로 쓸 수 있다.

| 구역 | 권한 |
|---|---|
| `.text` | `r-x` |
| `.rodata` | `r--` |
| `.data`/`.bss`, heap, **stack** | `rw-` |

### C. NX — 스택에서 `x` 를 뺀 것

`STACK`(표준명 `PT_GNU_STACK`) 세그먼트는 **파일의 어떤 바이트도 가리키지 않는다**
(`filesz 0`, `memsz 0`, 주소 전부 0). 존재 목적이 단 하나 — 로더에게 **"스택에 이 권한을
줘라"** 를 전달하는 것. **내용 없는 순수한 메시지다.**

측정한 대조 (같은 소스, 옵션만 다름):

| | `-z execstack` | `-z noexecstack` |
|---|---|---|
| `readelf -l` | `GNU_STACK … **RWE**` | `GNU_STACK … **RW**` |
| `objdump -p` | `flags **rwx**` | `flags **rw-**` |

NX가 꺼져 있으면 성립하는 공격: 버퍼에 **기계어를 써 넣고** 복귀 주소를 **버퍼 자신의
주소**로 덮는다 → [[Concepts/Binary/Shellcode]]

⚠️ **NX는 ret2win을 막지 못한다.** 목적지가 `.text`(`r-x`)의 기존 코드이므로 스택 실행이
아니다. NX가 금지하는 건 "스택을 코드 저장소로 쓰기"뿐이다 →
[[Concepts/Binary/Ret2Win_Pattern]]

### D. Canary — 버퍼와 복귀 주소 사이의 봉인

버퍼와 복귀 주소 **사이**에 무작위 8바이트를 깔고, 함수 종료 직전에 변했는지 본다.
통하는 이유: 버퍼에서 복귀 주소까지 가려면 **그 8바이트를 반드시 지나가며 써야 한다**
(연속 복사로는 건너뛸 수 없다) → [[Concepts/Binary/Stack_Frame_And_Call_Ret]]

컴파일러가 넣는 코드: 진입 시 `mov rax, fs:0x28` → `mov [rbp-8], rax`, 종료 시 비교 →
불일치면 **`__stack_chk_fail` 호출** → abort.

⭐ **왜 `nm -u`(미정의)에서 보이나:** 그 함수의 코드는 libc에 있어 이 파일에 없다(`U`).
그런데 **이름이 목록에 있다는 것 자체가** "이 바이너리에 그것을 호출하는 코드가 있다"는
뜻이고, 그 호출을 만드는 것은 **canary 계측밖에 없다.** 없으면 이름이 등장조차 하지 않는다.

측정: `-fno-stack-protector` → 심볼 없음 / `-fstack-protector-all` →
`U __stack_chk_fail@GLIBC_2.4`. 교차검증은 `objdump -d` 에서 `fs:0x28`.

> [!warning] ⭐ [Nullity] "없음"을 증거로 쓰려면 먼저 그 방법이 "있음"을 보여줄 수 있는지
> 확인해라 (2026-09-29)
> 실제로 물린 사례: `nm` 에 **undefined 를 숨기는 플래그**를 쓴 채 목록을 훑고
> "`__stack_chk_fail` 없음 → canary 없음"이라고 결론냈다. 그 출력에는 `U` 로 시작하는 줄이
> **하나도** 없었다 — 동적 링크 바이너리가 `puts`/`read` 를 부르는데 그럴 수가 없다.
>
> **판별:** 반드시 보여야 하는 다른 `U` 심볼(호출하는 libc 함수)이 출력에 있는지 먼저 본다.
> 없으면 목록 자체가 `U` 를 안 보여주는 것이고, canary 판정은 **무효**다. 결론이 우연히 맞아도
> 증거는 깨져 있다. → [[Tools/nm]]

### E. RELRO — 함수 포인터 표를 읽기 전용으로

**GOT(Global Offset Table)** 는 함수 포인터 배열이다. libc 함수의 주소는 실행 시에
정해지므로 `call <절대주소>` 를 파일에 박을 수 없다 → 코드는 `call [GOT의 칸]` 을 하고,
**그 칸의 내용**을 동적 링커가 채운다. 그래서 **GOT는 쓰기 가능해야 한다.**

그게 공격면이다: GOT의 어떤 칸에 다른 주소를 써 넣으면 **다음 그 함수 호출이 거기로 간다.**
복귀 주소를 건드리지 않고 제어를 가져간다.

**RELRO = RELocation Read-Only** — 다 채운 뒤 그 영역을 읽기 전용으로. 정보가 둘 필요하다:

1. **어디를** → program header 의 `RELRO` 세그먼트 (주소 범위)
2. **언제 가능한가** → 기본은 **lazy binding**(첫 호출 때 채움)이라 도는 내내 쓰기 가능해야
   한다. 이걸 "시작할 때 전부 채워라"로 바꾸는 스위치가 **`BIND_NOW`** (dynamic `FLAGS`)

| 단계 | `RELRO` 세그먼트 | `BIND_NOW` | 결과 |
|---|---|---|---|
| **No RELRO** | 없음 | — | 전부 쓰기 가능 |
| **Partial** | 있음 | 없음 | `.got.plt`(함수 포인터)는 **계속 쓰기 가능** |
| **Full** | 있음 | 있음 | 시작 시 전부 해소 후 잠금 → GOT overwrite 사망 |

**측정 판독 (2026-09-29)** — No RELRO 는 **증거 두 개가 각각 없어야** 확정된다:

| 확인 | No RELRO 인 실행 파일 | 같은 시스템의 `libc.so.6` |
|---|---|---|
| program header 에 `RELRO` 항목 | **없음** | **있음** |
| dynamic section 에 `FLAGS` / `BIND_NOW` | **없음** | (있음) |
| 판정 | **No RELRO** | 최소 Partial |

⭐ **같은 판독 절차가 공유 라이브러리에도 그대로 적용된다** — 그리고 실행 파일과 라이브러리의
설정이 **다를 수 있다.** "이 시스템은 RELRO 를 쓴다/안 쓴다"는 문장은 성립하지 않는다.
객체마다 따로 읽어야 한다.

분류: 복귀 주소를 덮는 공격에서는 **무관**이다 (GOT 를 건드리지 않는다). 다만 No RELRO 는
`.got.plt` 가 쓰기 가능하다는 뜻이므로 **대안 경로가 열려 있다**는 정보다 — ④의 목적지를
GOT 항목으로 바꾸는 변종. 읽고 나서 "무관"으로 **분류하는 것**이 §H 의 요점이다.

### F. ⚠️ 판독 함정 — 도구가 이름과 값을 다르게 보여준다

| | GNU `readelf` | macOS LLVM `objdump -p` |
|---|---|---|
| 세그먼트 이름 | `GNU_STACK` / `GNU_RELRO` | `STACK` / `RELRO` (접두사 생략) |
| 권한 표기 | `RWE` / `RW` | `rwx` / `rw-` |
| dynamic `FLAGS` | **`BIND_NOW`** 로 디코드 | **`0x0000000000000008`** 생 비트마스크 |

LLVM 쪽은 비트를 직접 읽어야 한다:

| 태그 | 비트 | 이름 |
|---|---|---|
| `FLAGS` | `0x8` | `DF_BIND_NOW` |
| `FLAGS_1` | `0x1` | `DF_1_NOW` |
| `FLAGS_1` | `0x08000000` | **`DF_1_PIE`** |

⭐ `DF_1_PIE` 는 보너스다 — `e_type = ET_DYN` 은 PIE와 공유 라이브러리를 구별하지 못하는데
([[Concepts/Binary/ELF_Header_Fields]] §B), 이 비트가 그 모호함을 해소한다. 측정값
`FLAGS_1 = 0x08000001` = `DF_1_PIE | DF_1_NOW`.

### G. ASLR 은 ELF 안에 없다 — 그리고 손잡이가 여러 개다

| 무작위화되는 것 | 무엇이 끄나 |
|---|---|
| 실행 파일 본체 (`.text`, 고정 심볼 주소) | **PIE 여부** — `e_type` |
| **스택** | 커널 전역 ASLR (`kernel.randomize_va_space`) |
| heap (`brk`) | 같음 |
| libc / `mmap` 영역 | 같음 |

⭐ **No PIE 여도 스택 주소는 매 실행 바뀐다.** 측정: 같은 프로그램 3회 실행에서
`[stack]` 베이스가 전부 달랐다. `e_type` 은 스택에 대해 아무 말도 하지 않는다.

→ 그래서 "스택에 코드를 놓고 점프"는 NX가 꺼져 있어도 **주소를 모르는 상태에서 시작한다.**
주소 유출이나 NOP sled 같은 보조 수단이 필요해지는 지점이 여기다.

### H. 분류가 실력이다

넷을 다 읽고 나서 **이 공격에 걸리는 것과 무관한 것을 나누는 것**이 판독의 목적이다.
GOT를 건드리지 않는 공격에서는 RELRO가 무관하고, 스택을 실행하지 않는 공격에서는 NX가
무관하다. 어느 고리를 끊는지로 따져야 한다 → [[Concepts/Binary/Ret2Win_Pattern]]

## Related

- [[Concepts/Binary/Ret2Win_Pattern]] — 네 기제가 각각 어느 링크를 끊는지의 대조표.
- [[Concepts/Binary/ROP]] — **NX 가 켜졌을 때 남는 길.** §C 의 금지를 우회하지 않고 피한다.
- [[Concepts/Binary/Ret2Libc_Pattern]] — NX(§C) + ASLR(§G) 이 동시에 걸린 상태의 표준 해법.
- [[Concepts/Binary/ELF_Header_Fields]] · [[Concepts/Binary/ELF_Sections_And_Relocation]] —
  네 기제를 읽는 두 구조.
- [[Tools/objdump]] · [[Tools/nm]] — 판독 도구.

## Encountered / Applied In

- External: local-only wargame tree (no-publish) — `checksec` 없이 네 기제를 각각의 구조에서
  읽고, 그중 어느 것이 해당 공격을 무력화하는지 분류했다. `-z execstack` / `-fstack-protector`
  / `-Wl,-z,relro,-z,now` / `-no-pie` 를 끄고 켠 합성 바이너리로 각 표시를 대조했다.
- External: local-only wargame tree (no-publish) — 두 번째 사례에서 **NX 가 켜져 있어** §C 의
  공격이 불가능했고, 대신 §E 의 RELRO 를 실제로 판독(둘 다 없음 = No RELRO)한 뒤 "무관"으로
  분류했다. canary 판정에서 §D 의 [Nullity] 함정에 실제로 걸렸다.

## Expand Later (`/deep` candidates)

- ~~**ROP** — NX가 켜졌을 때 `.text` 조각(gadget)을 이어 붙이는 방법~~
  → **2026-09-29 소비됨**: [[Concepts/Binary/ROP]], [[Concepts/Binary/Ret2Libc_Pattern]]
- **Canary leak** — 같은 프로세스에서 canary를 읽어내는 경로 (format string, partial overwrite)
- **FORTIFY_SOURCE / `_FORTIFY_LEVEL`** — 다섯 번째 기제, 심볼(`__memcpy_chk`)에 드러난다
- CET / shadow stack — `.note.gnu.property` 에 드러나는 최신 기제
- `checksec` 이 실제로 무엇을 읽는지 소스 대조
