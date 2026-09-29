---
date: 2026-09-28
domain: Binary
topic: Syscall_Convention
tags: [binary, syscall, abi, x86-64, kernel, registers]
status: 🟡 developing
note_tier: lite
mastery: 50
first_encountered: "External: local-only wargame tree (no-publish) — shellcode에서 libc 없이 커널을 직접 불러야 했다"
reapplied_in: []
---

# Syscall Convention

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> libc 없이 커널에 일을 시키는 규약. **함수 호출 규약과 다르다**는 것이 핵심이고,
> 왜 다른지가 하드웨어 동작에서 나온다.

## Definition (Formal, EN)

The system call ABI is the contract between user code and the kernel: which register holds
the call number, which hold the arguments, which the return value, and which the CPU itself
destroys. On x86-64 Linux the `syscall` instruction transfers control; the convention is
**distinct from** the System V function-call convention used by `call`.

## Intuition (KR)

`write()` 를 부르는 건 **libc 함수 호출**이고, `syscall` 은 **커널에 직접 요청**이다.
shellcode는 libc가 없으니 후자만 쓸 수 있다.

## Key Points (무엇을 팠나)

### A. 레지스터 배치

| 역할 | 레지스터 |
|---|---|
| **syscall 번호** | `rax` |
| 1번째 인자 | `rdi` |
| 2번째 | `rsi` |
| 3번째 | `rdx` |
| 4번째 | **`r10`** |
| 5번째 | `r8` |
| 6번째 | `r9` |
| 반환값 | `rax` |
| 진입 | `syscall` |

### B. ⭐ 함수 호출 규약과 4번째가 다르다 — 이유가 하드웨어다

| | 1 | 2 | 3 | **4** | 5 | 6 |
|---|---|---|---|---|---|---|
| **함수 호출** (System V) | `rdi` | `rsi` | `rdx` | **`rcx`** | `r8` | `r9` |
| **syscall** | `rdi` | `rsi` | `rdx` | **`r10`** | `r8` | `r9` |

⭐ **`syscall` 명령 자체가 `rcx` 에 복귀 주소(RIP)를, `r11` 에 RFLAGS를 덮어쓴다.**
하드웨어가 쓰는 레지스터를 인자로 쓸 수 없으니 커널 ABI가 `r10` 으로 비켜났다.

→ **`rcx` 와 `r11` 은 `syscall` 이후 값이 파괴된다.** 인라인 어셈블리에서 이 둘을
clobber 목록에 넣어야 하는 이유다. 함수 호출 규약은
[[Concepts/Binary/Stack_Frame_And_Call_Ret]] 에 있다.

### C. 번호는 외우지 말고 헤더를 봐라

```bash
grep -E '__NR_(execve|exit|read|write) ' /usr/include/x86_64-linux-gnu/asm/unistd_64.h
```
```
#define __NR_read 0
#define __NR_write 1
#define __NR_execve 59
#define __NR_exit 60
```

⚠️ **아키텍처마다 번호가 완전히 다르다.** i386의 `execve` 는 11, arm64는 221.
파일명이 `unistd_64.h` 인 것이 그 경고다. 32비트 바이너리를 다룰 때 64비트 번호를 쓰면
엉뚱한 syscall이 불린다.

### D. C에서 syscall을 직접 내기 — 인라인 어셈블리 문법

```c
asm volatile ( "명령어" : 출력 : 입력 : 파괴목록 );
```

| 조각 | 뜻 | 왜 필요한가 |
|---|---|---|
| `asm` | 이 어셈블리를 그대로 끼워 넣어라 | 함수를 부르면 PLT relocation이 생긴다 → [[Concepts/Binary/Shellcode]] |
| `volatile` | 최적화로 지우거나 옮기지 마라 | 반환값을 안 쓰면 삭제될 수 있다. syscall은 **부작용**이 목적 |
| `"=a"(r)` | 출력: `rax` → `r` | `=` 는 쓰기 전용 |
| `"a"(n)` `"D"(a)` `"S"(b)` `"d"(c)` | 입력을 `rax`/`rdi`/`rsi`/`rdx` 에 | 위 배치 그대로 |
| `"rcx","r11"` | 파괴목록 | §B의 하드웨어 동작. 안 알려주면 컴파일러가 캐시한 값이 깨진다 |
| `"memory"` | 메모리를 건드릴 수 있음 | 캐시한 메모리 값을 다시 읽게 만든다 |

제약 문자(x86): `a`=`rax`, `b`=`rbx`, `c`=`rcx`, `d`=`rdx`, `S`=`rsi`, `D`=`rdi`.
⚠️ 대문자 `S`/`D` 가 `rsi`/`rdi` 인 것은 옛 문자열 명령의 **S**ource/**D**estination Index
에서 온 관례다 — 규칙이 아니라 외워야 하는 약속이다.

### E. 레지스터 크기 창(窓)

물리적으로 하나인 레지스터에 이름이 4개다:

| 64 | 32 | 16 | 8 |
|---|---|---|---|
| `rax` | `eax` | `ax` | `al` |
| `rdi` | `edi` | `di` | `dil` |
| `rsi` | `esi` | `si` | `sil` |
| `rdx` | `edx` | `dx` | `dl` |

⭐ **32비트 이름에 쓰면 상위 32비트가 자동으로 0이 된다.** 그래서 `mov edx, 0x40` 과
`mov rdx, 0x40` 의 결과가 같고, 컴파일러는 **더 짧은** 쪽을 고른다 (5바이트 vs 7바이트).
디스어셈블리에서 `mov edx, …` 가 보이는 건 최적화의 흔적이고 의미는 64비트 값이다.

## Related

- [[Concepts/Binary/ROP]] — §A·§B 의 인자 레지스터 순서가 **어떤 `pop` 가젯이 필요한지** 정한다.
  인자가 적은 함수가 공격자에게 싼 이유.
- [[Concepts/Binary/Stack_Frame_And_Call_Ret]] — 함수 호출 규약 쪽 (§B 대조표의 왼쪽 줄).
- [[Concepts/Binary/Shellcode]] — 이 규약을 직접 쓰는 코드.
- [[Concepts/Binary/Stack_Alignment]] — 커널 진입 경로는 정렬을 요구하지 않는다.

## Encountered / Applied In

- External: local-only wargame tree (no-publish) — libc 없이 `execve("/bin/sh", NULL, NULL)`
  를 내기 위해. `exit(N)` 을 먼저 만들어 종료 코드로 파이프라인을 검증한 뒤 `write` →
  `execve` 로 올라갔다.

## Expand Later (`/deep` candidates)

- `syscall` vs `int 0x80` vs `sysenter` — 32비트/구형 경로
- vDSO — 커널 진입 없이 처리되는 syscall (`gettimeofday` 등)
- seccomp — syscall 번호 단위 필터링, 그리고 그것을 우회하는 syscall 선택
- 반환값이 음수일 때의 errno 규약
