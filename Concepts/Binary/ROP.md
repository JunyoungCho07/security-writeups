---
date: 2026-09-29
domain: Binary
topic: ROP
tags: [binary, exploitation, rop, gadget, nx, stack, x86-64, control-flow-hijack]
status: 🟡 developing
note_tier: lite
mastery: 50
first_encountered: "External: local-only wargame tree (no-publish) — NX 가 켜져 주입한 코드를 실행할 수 없게 된 시점"
reapplied_in: []
---

# ROP — Return-Oriented Programming

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> [[Concepts/Binary/Ret2Win_Pattern]] 의 `/deep` 후보 **"ROP 전체 원자화"** 슬롯을 소비한다.
> NX 가 켜져 주입 코드가 죽은 자리에서, "이미 있는 코드를 빌려 쓴다"로 전환한 스레드.

## Definition (Formal, EN)

**ROP** composes a computation out of **gadgets** — short instruction sequences that already
exist in executable memory and **end in `ret`**. Because `ret` pops 8 bytes into RIP, a
contiguous run of addresses written onto the stack is executed in order: the stack stops
being a *frame* and becomes an **instruction stream of addresses**. No new code is
introduced, so `NX` (which forbids executing writable memory) does not apply.

## Intuition (KR)

NX 는 **새 코드를 못 넣게** 막는다. 새로 넣지 않고 **이미 `r-x` 에 있는 조각을 이어 붙이면**
그 금지를 건드리지 않는다. 남의 문장에서 단어를 잘라내 내 문장을 만드는 것과 같다.

## Key Points (무엇을 팠나)

### A. gadget = `ret` 로 끝나는 짧은 조각

한 조각이 **작은 일 하나**를 하고, 끝의 `ret` 가 다음 조각으로 넘긴다. 조각 하나로는
아무것도 못 하지만 이어 붙이면 임의 계산이 된다.

가젯의 출처 세 가지:

| 출처 | 특징 |
|---|---|
| **출제자가 심어둔 것** | `__attribute__((naked))` 함수 안에 `pop …; ret` 를 넣어둔다. 입문 문제의 친절 |
| 바이너리의 `.text` | 의도치 않게 만들어진 시퀀스. 실전의 본체 |
| **libc** | 압도적으로 많다. base 를 알면 전부 쓸 수 있다 → [[Concepts/Binary/Ret2Libc_Pattern]] |

⭐ `naked` attribute 가 붙은 함수는 **자백**이다 — 프롤로그/에필로그를 지워 본문 바이트가
정확히 그 두세 명령만 되게 만든 것이므로, "이걸 가젯으로 쓰라"는 뜻이다.
([[Concepts/Binary/Stack_Alignment]] 의 `force_align_arg_pointer` 와 같은 종류의 누설.)

### B. ⭐⭐ CPU 는 함수 경계를 모른다 — 주소는 **바이트 단위**다

이것이 ROP 가 성립하는 근본 이유다. 측정한 형태:

```
4005c2: 5f    pop  rdi
4005c3: c3    ret
```

| 어디서 시작하나 | CPU 가 보는 것 |
|---|---|
| `0x4005c2` | `pop rdi` 그리고 `ret` — **두 명령** |
| `0x4005c3` | `ret` — **한 명령** |

**두 바이트가 각자 주소를 갖는다.** 같은 코드 영역이 시작 지점에 따라 **다른 가젯**이 된다.
디스어셈블러가 그려주는 명령 경계는 *한 가지 해석*일 뿐이고, CPU 는 주어진 주소의 바이트를
그 자리에서 디코드한다.

→ 그래서 가젯은 **함수 목록에 없다.** `nm` 으로는 안 나오고, 바이트를 봐야 나온다.
그리고 이것이 x86 의 **가변 길이 명령**과 결합해 실전 바이너리에 수천 개의 의도치 않은
가젯을 만든다. (고정 길이 명령인 arm64 는 정렬 제약 때문에 이 자유도가 훨씬 낮다.)

### C. 스택이 프레임이 아니라 **소비되는 테이프**가 된다

`ret` 한 번 = 스택에서 8바이트를 꺼내 RIP 에 넣기. 그러므로:

```
낮은 주소 ──────────────────────────────▶ 높은 주소
[ 패딩 ][ 가젯A ][ A가 먹을 값 ][ 가젯B ][ … ]
         ↑ ret 가 여기서 시작
```

`rsp` 는 **한 방향으로만 전진**한다. 각 가젯은 자기가 필요한 만큼 스택을 먹고, 마지막 `ret`
가 커서를 다음 주소로 옮긴다. 프레임(`rbp` 기준 좌표)은 의미를 잃는다 —
[[Concepts/Binary/Stack_Frame_And_Call_Ret]] 의 좌표계가 여기서 폐기된다.

### D. `pop rdi; ret` 가 왜 첫 가젯인가

System V AMD64 에서 **함수의 1번째 인자는 `rdi`** 다
([[Concepts/Binary/Syscall_Convention]] §B 의 대조표 왼쪽 줄).

문제는 오버플로우로 쓸 수 있는 것이 **스택뿐**이라는 것이다. 레지스터에는 직접 쓸 수 없다.
`pop rdi` 가 정확히 그 간극을 잇는다: **스택의 값 → 레지스터.**

→ ROP 체인의 일반형은 "**레지스터를 세팅하는 가젯들 + 목적지 함수**"다. 인자 개수만큼
`pop` 가젯이 필요하고, 그래서 인자가 적은 함수가 공격자에게 싸다.

### E. ⭐ 슬롯 회계 — 정렬이 여기서 결정된다

가젯마다 **8바이트 슬롯을 몇 개 먹는지** 세어야 한다:

| 사건 | 먹는 슬롯 |
|---|---|
| 취약 함수의 `ret` | 1 |
| `pop rdi` | 1 |
| 가젯의 `ret` | 1 |
| `ret` 가젯 (빈 것) | 1 |

정렬 규칙: **복귀 주소 칸부터 센 슬롯 개수가 짝수여야** 목적지 함수 진입 시 ABI 정렬이 맞다
(슬롯 2개 = 16바이트 = 정렬 한 주기). 홀수면 8 어긋나고 libc 내부 `movaps` 에서 SIGSEGV.

→ **빈 `ret` 가젯 하나를 끼워 개수의 홀짝을 바꾼다.** 이것이 실전 ROP 체인에 정체불명의
`ret` 가 하나 끼어 있는 이유다. 자세한 유도는 [[Concepts/Binary/Stack_Alignment]].

⭐ 이 회계는 **`p64` 개수를 세는 것**과 같다. payload 를 조립한 뒤 슬롯 수를 세는 습관이
정렬 버그를 사전에 잡는다.

### F. gadget 찾기 — 도구를 쓰기 전에

| 방법 | 언제 |
|---|---|
| `objdump -d` 로 눈으로 | 출제자가 심어둔 가젯. 함수 이름이 힌트다 |
| 심볼 목록(`nm`)에서 의심스러운 함수명 | `pop_rdi_gadget` 류의 이름이 곧 내용 |
| `ROPgadget` / `ropper` | 의도치 않은 가젯을 **전수 조사**해야 할 때 |

> [!warning] 자동 체인 생성은 이 저장소에서 제외한다
> `ropper --auto` / `ROP()` 자동 조립은 **무엇을 이어 붙일지 결정**해 준다. 가젯 열거는
> 기계가 해도 되지만 체인 설계는 학습 대상이다 → [[Tools/pwntools]] "의도적으로 쓰지 않는 것"

### G. ret2X 가족 안에서의 위치

ROP 는 **별개 기법이 아니라 일반형**이다. `ret2win` 은 가젯 0개(목적지 하나),
`ret2libc` 는 가젯 1~2개 + libc 함수, 완전한 ROP 는 syscall 을 직접 세팅하는 긴 체인.
네 링크 체인([[Concepts/Binary/Ret2Win_Pattern]])의 ④ 가 **한 지점이 아니라 순열**로
확장된 것이 ROP 다.

## Encountered / Applied In

- External: local-only wargame tree (no-publish) — NX 가 켜지고 `win` 도 없는 BOF 에서,
  출제자가 `naked` 함수로 심어둔 `pop rdi; ret` 한 개 + 정렬용 빈 `ret` 한 개로 libc 함수를
  호출. 빈 `ret` 의 주소가 **`pop rdi; ret` 가젯의 두 번째 바이트**였다 — §B 를 실물로 확인한
  지점.

## Related

- [[Concepts/Binary/Ret2Win_Pattern]] — 네 링크 체인. ROP 는 ④의 확장. **선수 개념.**
- [[Concepts/Binary/Ret2Libc_Pattern]] — 가젯으로 인자를 세팅해 libc 함수를 부르는 구체형.
- [[Concepts/Binary/Stack_Alignment]] — §E 슬롯 회계의 근거, 빈 `ret` 가젯의 정체.
- [[Concepts/Binary/Stack_Frame_And_Call_Ret]] — `ret` 의 정의. ROP 는 이 한 명령의 반복이다.
- [[Concepts/Binary/Memory_Protections]] — NX 가 ROP 를 강제하는 이유(§C), 가젯이 `r-x` 에
  있어야 하는 이유(§B).
- [[Concepts/Binary/Syscall_Convention]] — 인자 레지스터 순서. 어떤 `pop` 가젯이 필요한지 결정.
- [[Concepts/Binary/Shellcode]] — **대조**: 코드를 주입하는 길이 막혔을 때의 대안이 ROP다.
- [[Tools/objdump]] — 가젯을 바이트 수준에서 찾는 도구.
- [[Tools/pwntools]] — `p64` 로 체인을 조립한다.

## Expand Later (`/deep` candidates)

- **`syscall` 가젯으로 execve 직접 호출** (ret2syscall) — `pop rdx`/`pop rsi` 까지 필요,
  static 바이너리에서의 표준 경로
- **stack pivot** — `leave; ret` / `xchg rax, rsp` 로 스택 자체를 옮기기 (payload 공간이
  부족할 때)
- **SROP** — signal frame 을 위조해 레지스터 전체를 한 번에 세팅
- **JOP / COP** — `jmp`/`call` 로 끝나는 가젯, CET/shadow stack 이 `ret` 를 막을 때
- 의도치 않은 가젯의 통계 — 왜 x86 바이너리에는 그렇게 많고 arm64 에는 적은가
