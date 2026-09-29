---
date: 2026-09-29
domain: Binary
topic: Stack_Canary
tags: [binary, exploitation, canary, stack-protector, mitigations, tls, frame-layout, x86-64]
status: 🟡 developing
note_tier: lite
mastery: 50
first_encountered: "External: local-only wargame tree (no-publish) — canary 가 켜진 BOF 를 복원(restore)으로 통과"
reapplied_in: []
---

# Stack Canary

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> [[Concepts/Binary/Memory_Protections]] §D 가 "어디서 판독하나"를 다룬다면 이 노트는
> **좌표·설계·통과 경로**를 다룬다. 특히 canary 가 켜지면 **오프셋 공식이 깨진다.**

## Definition (Formal, EN)

A **stack canary** (stack-protector cookie) is a per-thread random word the compiler stores
between a function's local buffers and its saved frame pointer / return address, and re-checks
in the epilogue. A contiguous overflow that reaches the return address must cross it, so the
mismatch is detected before `ret` executes and `__stack_chk_fail` aborts the process.

## Intuition (KR)

복귀 주소 앞에 **봉인**을 붙여 둔 것이다. 연속으로 쓰면서 복귀 주소까지 가려면 봉인을
반드시 밟고 지나가야 하고, 함수는 나가기 직전에 봉인을 확인한다.

## Key Points (무엇을 팠나)

### A. 어디서 와서 어디에 놓이나

```
진입:  mov rax, fs:0x28      ← TLS(스레드 제어 블록)의 마스터 값을 읽는다
       mov [rbp-8], rax      ← 프레임에 복사
에필로그: [rbp-8] 과 fs:0x28 비교 → 불일치면 __stack_chk_fail → abort
```

⭐ **`fs:0x28` 은 스레드마다 하나**다. 프레임마다 새로 뽑는 것이 아니라 **한 값을 모든
프레임이 공유**한다. 이 사실이 §E 의 brute force 를 가능하게 한다.

### B. ⭐ 좌표는 고정이다 — 항상 `[rbp-8]`

| 칸 | 내용 |
|---|---|
| `[rbp+8]` | return address |
| `[rbp+0]` | saved `rbp` |
| **`[rbp-8]`** | **canary** ← 켜져 있으면 **항상 여기** |
| `[rbp-8]` 아래 | 지역 변수들 |

지역 변수가 canary **위로** 올라갈 수 없다. 컴파일러가 `[rbp-8]` 을 먼저 예약하고 나머지를
아래에 배치한다.

### C. ⭐⭐ 그래서 "배열 크기 + 8" 공식이 깨진다

canary 가 **없을** 때는 배열이 복귀 주소 칸에 붙어 있을 수 있다:

```
rbp-0x40 : buf[64]
rbp+0x00 : saved rbp        ← buf 시작에서 64
rbp+0x08 : return address   ← 64 + 8 = 72        ✅ 공식 성립
```

canary 가 **켜지면** 배열이 `[rbp-8]` 아래로 밀려나고, **정렬 때문에 구멍이 생긴다**:

```
rbp-0x50 : buf[64]          ← 16바이트 정렬 위치 (rbp-0x48 이 아니다)
rbp-0x10 : (빈 8바이트)      ← 정렬의 부산물. 아무도 안 쓴다
rbp-0x08 : canary           ← buf 시작에서 72
rbp+0x00 : saved rbp        ← 80
rbp+0x08 : return address   ← 88   ← 공식이 말하는 72 가 아니다
```

**왜 `rbp-0x48` 이 아닌가:** `rbp` 는 16의 배수이고 컴파일러는 큰 지역 배열을 **16바이트 정렬**
위치에 놓는다(벡터화된 복사를 위해). `rbp-0x48` 은 8정렬뿐이라 탈락하고 `rbp-0x50` 이 선택된다.
남는 8바이트는 **패딩 구멍**이다.

> [!warning] ⭐ 실무 규칙
> **배열 크기에서 오프셋을 계산하지 마라. `lea` 변위를 읽어라.**
> `sub rsp, N` 과 `lea rax, [rbp - M]` 두 숫자가 진실이고, 소스의 `[64]` 는 힌트일 뿐이다.
> canary 가 없을 때 두 값이 우연히 일치했기 때문에 공식이 통했던 것이다.

→ [[Concepts/Binary/Stack_Frame_And_Call_Ret]]

### D. ⭐ 최하위 바이트가 `00` 인 것은 설계다

관측된 canary 는 항상 `0x????????????????00` 꼴로 끝난다 (리틀엔디안이므로 **메모리상 첫
바이트가 NUL**).

이유: `strcpy`/`puts`/`printf("%s")` 같은 **문자열 함수가 그 NUL 에서 멈춘다.** 버퍼를 넘겨
읽으려는 시도가 canary 를 넘어가지 못한다. 유출 방어를 canary 자신이 들고 있는 셈이다.

| | 값 |
|---|---|
| 명목 크기 | 8바이트 |
| **실효 무작위성** | **7바이트 = 2⁵⁶** |
| 대가 | 문자열 함수로는 유출 불가 |

### E. 통과 경로 네 가지

| 경로 | 조건 | 비고 |
|---|---|---|
| **유출 후 복원** | canary 값을 읽을 수단 (출제자의 출력, format string, 인접 변수 유출) | 가장 흔하다. **우회가 아니라 통과** |
| **바이트 단위 brute force** | **fork 서버** — 크래시해도 프로세스가 살아 있고 자식이 같은 canary 를 쓴다 | 7바이트 × 256 = 최대 **1792회**. §A 의 "스레드당 하나"가 근거 |
| **건너뛰기** | 연속 복사가 아닌 쓰기 (인덱스 지정 쓰기, 배열 첨자 오버플로) | canary 를 밟지 않으므로 검사가 통과된다 |
| **다른 표적** | 복귀 주소가 아닌 것을 덮는다 (GOT, 함수 포인터, 인접 지역 변수) | 에필로그 검사 자체를 회피 |

⚠️ `fork` 는 canary 를 **상속**한다 (메모리 복사). `execve` 는 새로 뽑는다. 그래서 brute
force 가 되는 서버와 안 되는 서버가 갈린다.

### F. "우회"가 아니라 "통과"다

유출-복원 경로에서는 `__stack_chk_fail` 이 **애초에 불리지 않는다.** 방어를 뚫은 것이 아니라
**검사를 만족시킨** 것이다. 체인의 링크 ②는 끊기지 않고 그냥 지나간다 →
[[Concepts/Binary/Ret2Win_Pattern]]

그리고 payload 에 canary 를 넣어야 하므로 **링크 ⓪(런타임 비밀 확보)** 이 새로 필요해진다.
canary 는 주소가 아니지만 ⓪ 의 다른 인스턴스다.

### G. canary 가 막지 **못하는** 것

- 복귀 주소를 건드리지 않는 공격 (GOT overwrite, 함수 포인터, 데이터 조작)
- 힙 오버플로 (canary 는 스택 프레임 장치다)
- 같은 프레임 안 **지역 변수 간** 덮어쓰기 — canary 아래에서 일어난다
- 읽기 전용 유출 (format string 으로 스택을 읽는 것 자체)

⭐ **분류가 실력이다:** canary 는 링크 ② 하나만 끊는다. 그 링크를 쓰지 않는 공격에는 무관하다
→ [[Concepts/Binary/Memory_Protections]] §H

## Encountered / Applied In

- External: local-only wargame tree (no-publish) — 출제자가 `fs:0x28` 을 직접 읽어 출력해 주는
  함수를 넣어 두었다(⓪ 제공). 유출 → 같은 자리에 복원 → 나머지는 ret2win. 이 문제에서
  **§C 의 8바이트 정렬 구멍**에 실제로 물렸다: `배열 크기 + 8` 로 계산한 오프셋으로는
  canary 자리에 쓰레기가 들어가 `__stack_chk_fail` 이 떴다.

## Related

- [[Concepts/Binary/Memory_Protections]] — §D 가 **판독**(심볼 `__stack_chk_fail`)을 다룬다.
  이 노트는 좌표와 통과 경로.
- [[Concepts/Binary/Stack_Frame_And_Call_Ret]] — `rbp` 좌표계. **선수 개념**이고, §C 가 그
  노트의 오프셋 공식에 단서를 붙인다.
- [[Concepts/Binary/Ret2Win_Pattern]] — canary 가 끊는 링크 ②, 그리고 복원이 필요로 하는 ⓪.
- [[Concepts/Binary/Stack_Alignment]] — **다른 종류의 정렬이다.** 그쪽은 `rsp` 의 16정렬(ABI),
  이쪽은 프레임 **안** 객체의 정렬. 둘 다 16이라 혼동하기 쉽다.
- [[Concepts/Binary/Binary_Number_Encoding]] — canary 를 `p64` 로 되돌려 놓을 때.
- [[Tools/nm]] · [[Tools/objdump]] — 판독(`__stack_chk_fail`) 과 교차검증(`fs:0x28`).

## Expand Later (`/deep` candidates)

- **fork 서버 brute force 의 실제 구현** — 바이트 단위 탐색 루프, 성공/실패 판정 신호
- **format string 으로 canary 읽기** — `%N$p` 로 스택 N번째 칸을 직접 출력
- `-fstack-protector` vs `-strong` vs `-all` — 어떤 함수에 계측이 붙는지의 기준
- **TLS 구조** — `fs` 가 가리키는 TCB 의 레이아웃, `fs:0x28` 이외에 무엇이 있나
- SSP 이외의 프레임 보호 — shadow stack(CET), SafeStack
