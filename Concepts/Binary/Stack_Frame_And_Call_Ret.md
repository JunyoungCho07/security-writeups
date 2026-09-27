---
date: 2026-09-27
domain: Binary
topic: Stack_Frame_And_Call_Ret
tags: [binary, stack, x86-64, aarch64, abi, calling-convention, disassembly, memory-layout]
status: 🟡 developing
mastery: 55
note_tier: lite
first_encountered: "External: local-only wargame tree (no-publish) — 버퍼 뒤에 무엇이 있는지를 C 소스가 알려주지 않는다는 데서 출발"
reapplied_in: []
---

# Stack Frame And Call / Ret

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> "지역 배열의 마지막 원소 **다음** 바이트에는 무엇이 있는가"에서 시작해, C 소스에 적혀
> 있지 않은 층위(프레임 레이아웃)를 `call`/`ret`의 정의부터 쌓고, 주소를 직접 찍어
> 성장 방향을 실측한 스레드. C·어셈블리 무경험 상태에서 시작.

## Definition (Formal, EN)

A **stack frame** is the region of the call stack a single function invocation owns:
its saved caller state, its local variables, and the **return address** pushed by the
`call` that created it. On x86-64 the frame is addressed relative to a fixed base
pointer `rbp`, established by a **prologue** and unwound by an **epilogue**.

`call f` ≡ *push the address of the next instruction*, then `rip ← f`.
`ret` ≡ *pop 8 bytes*, then `rip ← that value`. **`ret` performs no validation
whatsoever** — it transfers control to whatever 8 bytes sit at the top of the stack.

## Intuition (KR)

함수 호출은 "돌아올 주소를 메모리에 적어두고 점프"이고, 리턴은 "메모리에 적힌 주소를
읽어 점프"다. **적어두는 곳이 메모리라는 것**이 전부다 — 메모리는 쓸 수 있으므로,
그 기록을 바꾸면 리턴이 다른 곳으로 간다. RIP는 레지스터라 직접 쓸 수 없고, 언제나
`ret`이 중개한다.

## Key Points (무엇을 팠나)

### 스택은 주소가 **감소하는** 방향으로 자란다

관례가 아니라 **ISA의 정의**다:

```
push rax   ≡   sub rsp, 8        ← sub 로 시작한다
               mov [rsp], rax
pop  rax   ≡   mov rax, [rsp]
               add rsp, 8
```

재귀로 깊어지며 지역 변수 주소를 찍어 실측 (arm64 macOS, `%p`):

```
frame 1 : 0x16bd36608
frame 2 : 0x16bd365d8      ← 0x30 감소
frame 3 : 0x16bd365a8
frame 4 : 0x16bd36578
malloc #1 : 0x104801c70    ← 힙은 증가, 그리고 스택보다 훨씬 낮은 주소
malloc #2 : 0x104801cb0
```

> [!warning] "위/아래"는 그림의 속성이다
> 메모리 지도를 **낮은 주소를 위에** 그리는 관례(한국 강의자료에 흔하다)에서는 같은 사실이
> "스택은 아래→위로 자란다"로 표현된다. 두 문장은 **동일한 사실**이고, 화살표 방향은 종이를
> 뒤집었기 때문이다. 주소는 숫자이므로 뒤집히지 않는다 — **"낮은 주소 / 높은 주소"로만 말하라.**
>
> 용어 함정: `rsp`가 가리키는 "stack **top**"은 프레임에서 **주소가 가장 낮다.** "top"은
> 자료구조(LIFO)의 이름이고 주소 공간과 무관하다.
>
> 힙은 확실성 등급이 다르다: `brk` 기반은 주소 증가, 큰 `malloc`의 `mmap` 영역은 Linux에서
> 보통 감소. **힙 방향은 allocator 구현, 스택 방향은 ISA.**

### 프롤로그 / 에필로그

```
push rbp              ① 부른 쪽의 rbp 저장
mov  rbp, rsp         ② 내 프레임의 기준점 = 좌표계 원점
sub  rsp, N           ③ 지역 변수용 N 바이트 확보
…
leave                 = mov rsp, rbp ; pop rbp   (②③을 한 명령으로 되돌림)
ret
```

`rsp`는 `push`/`pop`마다 움직이지만 **`rbp`는 함수 실행 중 고정**이다. 그래서 컴파일러는
모든 지역 변수를 `rbp` 상대 좌표로 표현한다. 에필로그는 `add rsp, N` + `pop rbp`이거나
`leave` 하나 — `leave`는 프레임 크기를 몰라도 되니 1바이트로 끝난다.

### `rbp` 좌표계 — ABI가 고정한 두 칸

| 좌표 | 내용 | 누가 놓았나 |
|---|---|---|
| `[rbp + 8]` | **return address** | `call` |
| `[rbp + 0]` | saved `rbp` | 프롤로그 ① |
| `[rbp − X]` | 지역 변수 | 프롤로그 ③이 확보한 공간 안 |

위 두 줄은 컴파일러·최적화 옵션과 **무관하게** 고정이다. 미지수는 `X` 하나다.

### 왜 버퍼 넘침이 복귀 주소에 닿는가 — 방향이 반대다

- 스택은 **낮은 주소로** 자란다 → 부른 쪽의 기록이 **높은 주소**에 남는다
- 배열은 `buf[0]`(낮은 주소)에서 `buf[n-1]`(높은 주소)로 채워진다

두 방향이 반대이므로, 버퍼를 넘쳐 쓰면 **자기를 부른 쪽의 기록 방향으로 전진한다.**
64바이트 버퍼가 `[rbp-0x40]`에 있으면 `buf[0]`에서 복귀 주소까지 거리는 `0x40 + 8 = 72`.

> 이 방향이 반대가 아니었다면 스택 BOF에서 복귀 주소를 덮는 기법 자체가 성립하지 않는다.

### 정적 분석이 답할 수 있는 것과 없는 것

`X`는 **C 소스에 적혀 있지 않다.** 컴파일러가 정렬을 위해 padding을 넣을 수도, 지역 변수
순서를 바꿀 수도 있다. 하지만 디스어셈블리에는 **반드시** 있다 — 버퍼를 함수에 인수로
넘기려면 주소를 계산해야 하므로:

```
sub  rsp, 0x40                 ← 프레임 전체 크기 (버퍼 크기와 다를 수 있다)
lea  rax, [rbp - 0x40]         ← 주소 계산. 이 변위가 X
```

`lea` (Load Effective Address)는 **주소를 계산만** 하고 메모리를 읽지 않는다 — C의 `&`.
`mov rax, [rbp-0x40]`은 그 자리의 **내용**을 가져온다. 완전히 다르다.

`objdump`의 `#` 주석은 **정적으로 계산 가능한 것만** 붙는다: `[rip + 0x...]`에는 붙고
`[rbp - 0x...]`에는 붙지 않는다 (`rbp`는 런타임 값). **주석의 부재가 정보다.**

인수 레지스터 순서 (System V AMD64, 정수/포인터): `rdi, rsi, rdx, rcx, r8, r9`.
32비트 이름(`edi`)에 쓰면 **상위 32비트가 자동으로 0**이 되므로 `xor edi, edi`나
`mov edi, 0x0`이 `rdi` 전체를 0으로 만든다 (인코딩이 짧아 컴파일러가 선호).

### arm64는 복귀 주소를 스택에 push하지 않는다

| | x86-64 | arm64 (AArch64) |
|---|---|---|
| 호출 | `call f` | `bl f` (branch with **link**) |
| 복귀 주소 저장 위치 | **스택** (자동 push) | **`x30` 레지스터** (= LR) |
| 복귀 | `ret` = 스택에서 pop → rip | `ret` = `x30`으로 점프 |
| 스택에 있나 | **항상** | 함수가 **직접 저장했을 때만** |

다른 함수를 부르지 않는 함수(leaf function)는 `x30`을 스택에 저장할 이유가 없다 →
**스택에 복귀 주소가 아예 없다.** 비-leaf는 프롤로그에서
`stp x29, x30, [sp, #-16]!`로 저장한다 (`#-16`이 음수 = 여기도 감소 방향).

**실무적 귀결:** 이 노트의 x86-64 프레임 구조는 arm64에서 그대로 성립하지 않는다.
arm64 호스트에서 컴파일해 재면 다른 답이 나오거나 재지지 않는다. 정적 분석은 호스트와
무관하지만 **측정 대상의 아키텍처는 무관하지 않다.**

## Related

- [[Concepts/Binary/Ret2Win_Pattern]] — 이 구조를 이용해 실행 흐름을 탈취하는 기법. `ret`의
  무검증이 전제.
- [[Concepts/Binary/Stack_Alignment]] — `call`이 push하는 8바이트가 정렬에 미치는 영향.
  `ret`으로 진입하면 그 8바이트가 없어 어긋난다.
- [[Concepts/Binary/ELF_Header_Fields]] — `e_machine`이 위 표의 어느 열을 적용할지 정한다.
- [[Concepts/Linux/Process_Creation]] — 프로세스 메모리 구획(text/data/heap/stack)의 상위 맥락.
- [[Tools/objdump]] — 프레임 좌표를 읽는 도구. `--x86-asm-syntax=intel` 필수.
- [[Tools/nm]] — 함수 이름 → 주소.

## Encountered / Applied In

- External: local-only wargame tree (no-publish) — 지역 버퍼를 넘겨 쓰는 코드에서
  버퍼 시작점부터 저장된 복귀 주소까지의 거리를 디스어셈블리로 확정한 사례. 소스만으로는
  결정되지 않고, 프롤로그의 `sub`와 `lea`의 변위에서 나왔다.

## Expand Later (`/deep` candidates)

- **Stack canary** — `[rbp+0]` 아래에 난수를 두고 에필로그에서 검사. 이 좌표계에
  한 칸이 추가되는 것이고, `__stack_chk_fail` 심볼로 존재를 판정한다.
- **Frame pointer omission** (`-fomit-frame-pointer`) — `rbp`를 범용 레지스터로 쓰고
  모든 좌표를 `rsp` 상대로 표현하는 최적화. 그러면 이 노트의 좌표계가 무효가 되고
  DWARF CFI로 프레임을 복원해야 한다.
- **Calling convention 전체 원자화** — 반환값(`rax`/`rdx`), caller/callee-saved 구분,
  red zone(128바이트), 가변 인수(`al`에 벡터 레지스터 개수), Microsoft x64와의 차이.
- **Stack unwinding / backtrace** — 디버거가 `rbp` 체인 또는 CFI로 콜 스택을 복원하는 원리.
