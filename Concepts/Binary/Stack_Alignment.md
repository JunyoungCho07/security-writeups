---
date: 2026-09-27
domain: Binary
topic: Stack_Alignment
tags: [binary, x86-64, abi, alignment, sse, movaps, compiler-attributes, exploitation]
status: 🟡 developing
mastery: 45
note_tier: lite
first_encountered: "External: local-only wargame tree (no-publish) — 한 함수에만 붙은 컴파일러 attribute의 의미를 역추론"
reapplied_in: []
---

# Stack Alignment x86-64

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> "왜 이 함수에만 정렬 강제 attribute가 붙어 있나"에서 출발해, ABI의 16바이트 규칙 →
> `call`이 push하는 8바이트 → `ret`으로 진입하면 그 8이 없다 → SSE 명령이 하드웨어로
> 정렬을 강제해 SIGSEGV 로 이어지는 사슬을 정리한 스레드.

## Definition (Formal, EN)

The System V AMD64 ABI requires that **immediately before a `call`, `rsp` be a multiple
of 16**. Because `call` pushes an 8-byte return address, a callee therefore begins
execution with `rsp ≡ 8 (mod 16)`, and every compiler lays out its frame on that
premise. Violating it is not a style error: SSE/AVX **aligned** move instructions
(`movaps`, `movdqa`, …) enforce 16-byte alignment *in hardware*, raising `#GP`
(delivered as `SIGSEGV`) on a misaligned operand.

## Intuition (KR)

컴파일러는 "내가 시작할 때 `rsp`의 하위 4비트는 `8`이다"를 **전제로** 프레임을 짠다.
그 전제가 깨지면 프레임 안의 모든 것이 8바이트 밀리고, 그 중 하나가 "정렬을 요구하는"
명령의 대상이 되는 순간 CPU가 거부한다. 소프트웨어 규약이 아니라 **하드웨어가 강제하는
규약**이라는 점이 핵심이다.

## Key Points (무엇을 팠나)

### 규칙의 정확한 형태

| 시점 | `rsp mod 16` |
|---|---|
| `call` **직전** | **0** ← ABI가 요구하는 지점 |
| 함수 **진입 직후** | **8** (`call`이 8바이트 push했으므로) |
| `push rbp` 후 | 0 |

"진입 시 16의 배수"가 아니라 **"`call` 직전에 16의 배수"**다. 이 한 칸 차이가 아래 전체를
결정한다.

### `ret`으로 진입하면 정확히 8바이트 어긋난다

| 진입 경로 | 8바이트 push? | 진입 시 `rsp mod 16` |
|---|---|---|
| `call f` (정상) | ✅ push | **8** ← 컴파일러의 가정 |
| `ret`으로 점프 | ❌ **pop한다** | **0** ← 8만큼 어긋남 |

`ret`은 push하지 않는다. 오히려 8바이트를 **꺼낸다.** 그래서 복귀 주소를 덮어 함수에
진입하면 정렬이 어긋난 상태로 시작한다.

### 증상 — "주소는 맞는데 죽는다"

어긋난 채로 실행되면 지역 변수 전체가 8바이트 밀리고, glibc 내부가 SSE를 쓰는 지점에서
터진다:

```
movaps xmm0, [rsp+0x30]     ← "aligned" move. 16의 배수가 아니면 #GP → SIGSEGV
```

`printf`, `puts`, `memcpy`, `strlen` 등이 최적화로 SSE를 쓴다. 그래서 **점프는 성공했는데
목적지 함수 안쪽의 libc 호출에서 SIGSEGV**가 나는 현상이 생긴다. 초보가 "주소가 틀렸나"를
며칠 의심하는 지점이고, 실제 원인은 정렬이다.

> [!warning] 판별법
> 크래시 지점이 **내가 지정한 주소가 아니라 libc 안**이면 정렬을 의심하라. 주소 문제면
> 점프 직후에 죽고, 정렬 문제면 목적지 함수가 몇 줄 실행된 뒤 죽는다.

### `__attribute__((force_align_arg_pointer))`

x86 전용 GCC/Clang 확장. 함수 진입 시 `rsp`를 **강제로 16의 배수로 재정렬**하는 코드를
프롤로그 앞에 삽입한다.

정상적으로 `call`로만 불리는 함수에는 필요가 없다 — 정렬이 이미 보장되므로. **따라서 이
attribute가 붙어 있다는 것은 작성자가 그 함수가 `call`이 아닌 경로로 진입될 것을
예상했다는 자백이다.** CTF에서는 출제자가 정렬 문제를 미리 제거해 주는 친절이고, 동시에
의도를 누설하는 힌트다.

같은 이유로 `__attribute__((noinline))`도 신호다 — inline되면 함수가 독립적으로 존재하지
않게 되고, 아무도 부르지 않는 함수는 최적화로 삭제될 수 있다.

### 공격자 측 해결 — 8바이트를 소모한다

attribute가 **없는** 경우, 정렬을 스스로 맞춘다: 목적지 주소 앞에 **`ret` 하나의 주소**를
끼워 넣는다. 그 `ret`이 8바이트를 pop해 정렬을 원복하고, 그 다음 8바이트(진짜 목적지)로
간다. 이것이 ROP chain에서 흔히 보이는 "빈 `ret` gadget"의 정체다.

### 왜 ABI가 16을 요구하나

1. SSE/AVX 레지스터가 16바이트(이상)이고, **aligned load/store가 unaligned보다 빠르다**
2. 규약으로 고정해 두면 컴파일러가 **정렬 검사 없이** aligned 명령을 쓸 수 있다
3. `long double`(x87, 16바이트 정렬) 등 타입 요구사항

### i386에서는 이 문제가 없다

32비트 x86 ABI는 스택 정렬을 **4바이트**만 요구했다. 그래서 오래된 32비트 exploit 자료에는
정렬 이야기가 없고, 그 자료를 x86-64에 그대로 적용하면 이 함정을 만난다.
(gcc는 i386에서도 기본 16바이트로 맞추지만 ABI 강제는 아니다.)

## Related

- [[Concepts/Binary/Stack_Frame_And_Call_Ret]] — `call`/`ret`이 스택에 하는 일. **선수 개념.**
- [[Concepts/Binary/Ret2Win_Pattern]] — `ret`으로 함수에 진입하는 기법. 이 노트가 그
  부작용을 설명한다.
- [[Tools/objdump]] — attribute의 흔적(프롤로그의 `and rsp, -0x10` 류)을 확인.

## Encountered / Applied In

- External: local-only wargame tree (no-publish) — 출제자가 한 함수에만 정렬 강제
  attribute를 붙여 둔 것을 보고, 그 함수가 `ret`으로 진입될 것을 전제했다는 결론을 도출.
  결과적으로 정렬을 공격자가 맞출 필요가 없었다.

## Expand Later (`/deep` candidates)

- **`ret` gadget을 이용한 정렬 보정**을 ROP chain 설계의 일부로 원자화.
- SSE 명령 계열 정리 — aligned(`movaps`/`movdqa`) vs unaligned(`movups`/`movdqu`),
  왜 컴파일러가 전자를 고르는가, AVX-512의 64바이트 정렬.
- **red zone** (`rsp` 아래 128바이트) — leaf function이 `sub rsp` 없이 쓰는 영역.
  프레임 좌표 추론과 signal handler에 미치는 영향.
- `#GP` 예외가 `SIGSEGV`로 전달되는 경로 (커널의 trap → signal 사상).
