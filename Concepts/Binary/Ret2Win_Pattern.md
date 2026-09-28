---
date: 2026-09-27
domain: Binary
topic: Ret2Win_Pattern
tags: [binary, exploitation, bof, ret2win, rop, control-flow-hijack, mitigations]
status: 🟡 developing
mastery: 50
note_tier: lite
first_encountered: "External: local-only wargame tree (no-publish) — 호출되지 않는 함수가 바이너리에 남아 있는 것을 보고 의도를 역추론"
reapplied_in: []
---

# Ret2Win Pattern

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> "아무도 부르지 않는 함수가 왜 바이너리에 있나"에서 시작해, 스택 BOF가 실행 흐름을
> 탈취하는 최소 체인을 세우고, 세 가지 방어(canary/PIE/NX)가 각각 그 체인의 **어느 링크**를
> 끊는지까지 정리한 스레드. 입문용 패턴이지만 체인 자체는 모든 ROP의 골격이다.

## Definition (Formal, EN)

**ret2win** is the minimal stack-buffer-overflow exploitation pattern: overwrite the
**saved return address** in a function's frame with the address of a function already
present in the binary that satisfies the win condition, so that the function's `ret`
transfers control there. It is the degenerate case of the `ret2X` family, degenerate
because the destination is **supplied by the challenge author** rather than discovered.

`win` is a **naming convention, not a technical requirement** — nothing in the ABI, the
loader, or the CPU treats it specially. Common variants: `flag`, `get_flag`, `print_flag`,
`shell`, `give_shell`, `backdoor`, `secret`, `not_called`.

## Intuition (KR)

"복귀 주소를 덮으면 실행 흐름을 가져온다"만 증명하면 되게 만든 **보조 바퀴**다. 목적지를
찾는 어려움(실전의 본체)을 출제자가 미리 제거해 준 형태이므로, 배우는 것은 *목적지 선택*이
아니라 **체인의 존재 자체**다.

## Key Points (무엇을 팠나)

### 최소 체인 — 네 개의 링크

```
① 메모리 쓰기      버퍼를 넘쳐 [rbp+8]의 저장된 복귀 주소를 덮는다
② ret 실행         에필로그의 ret 이 그 8바이트를 pop 한다
③ RIP 적재         ret 이 그 값을 rip 에 넣는다 (무검증)
④ 목적지 실행      그 주소의 코드가 실행된다
```

> [!warning] "RIP를 오버플로한다"는 틀린 문장이다
> RIP는 **레지스터**다. 메모리 주소가 없으므로 버퍼 오버플로로 덮을 수 없다. 덮는 것은
> **메모리에 저장된 복귀 주소**이고, `ret`이 그것을 RIP로 **옮긴다.** 중개자 `ret`을
> 문장에서 빼면 아래 방어 대조표를 만들 수 없다 — 각 방어가 **서로 다른 링크**를 끊기 때문이다.

### 방어 기제는 서로 다른 링크를 끊는다

| 방어 | 끊는 링크 | 왜 | ret2win에 치명적인가 |
|---|---|---|---|
| **Stack canary** | **② `ret`까지 도달하기** | `[rbp+0]` 아래 난수를 에필로그에서 검사 → 덮으면 `__stack_chk_fail` | **예** — `ret`이 실행조차 안 된다 |
| **PIE / ASLR** | **④ 목적지 주소를 알아내기** | 함수 주소가 매 실행마다 바뀜 → payload에 미리 박을 수 없다 | **예** — leak이 필요해진다 |
| **NX / DEP** | **④ 목적지를 실행하기** | 스택을 실행 불가로 만든다 | **아니오** — 목적지가 `.text`(실행 가능)이므로 무관. NX는 ret2shellcode만 막는다 |
| **RELRO** | (①의 변종 — GOT 덮어쓰기) | GOT를 읽기 전용으로 | ret2win과 직접 무관 |

**NX가 무해하다는 것이 핵심 통찰이다.** "방어가 켜졌으니 못 한다"가 아니라, 어느 링크를
끊는지 보고 판정해야 한다.

### `ret2X` 가족 — 분류 기준은 "어디로 복귀하는가"

| 패턴 | 목적지 | 필요 조건 | 언제 |
|---|---|---|---|
| **ret2win** | 바이너리 안의 **선물 함수** | 출제자가 넣어줘야 함 | 입문용 CTF만 |
| ret2shellcode | 주입한 기계어 | 스택이 **실행 가능** (NX 없음) | 구형/특수 환경 |
| ret2libc | libc의 `system` 등 | libc base 주소를 알아야 함 | NX 있고 PIE 없거나 leak 확보 |
| ret2syscall | `syscall` 명령 | 레지스터를 미리 세팅 (gadget 필요) | static 바이너리 |
| **ROP** | gadget **연쇄** | `ret`로 끝나는 코드 조각들 | 위가 전부 막혔을 때 |

> 실전 취약점에는 `win`이 없다. 이 표의 아래쪽이 존재하는 이유가 그것이고, ret2win에서
> 배운 ①~④ 체인은 아래쪽 전부의 **골격**이다. "BOF = win으로 점프"로 외우면 두 번째
> 문제에서 막힌다.

### ⭐ ret2win → ret2shellcode: 달라지는 것은 ④ 하나뿐 (2026-09-28 추가)

두 패턴을 나란히 두면 체인 분해가 왜 필요했는지가 드러난다:

| 링크 | ret2win | ret2shellcode |
|---|---|---|
| ① 메모리 쓰기 | 입력 한도 > 버퍼 | **같다** |
| ② `ret` 도달 | canary 없음 | **같다** |
| ③ RIP 로드 | `ret` | **같다** |
| ④ **목적지 실행** | `.text` 의 **기존** 코드 (`r-x`, 주소 고정) | **내가 방금 쓴 스택 바이트** |

④ 하나가 바뀌면서 **새 전제 두 개**가 붙는다:

1. **스택에 `x` 권한이 있어야 한다** — NX 꺼짐. `objdump -p` 의 `STACK` flags 가 `rwx`
2. **스택 주소를 알아야 한다** — ⚠️ **No PIE 여도 스택은 매 실행 움직인다.** `e_type` 은
   실행 파일 본체만 고정하고 스택에 대해 아무 말도 하지 않는다. 주소 유출이나 NOP sled가
   필요해지는 지점이 여기다

→ [[Concepts/Binary/Memory_Protections]] §C·§G, [[Concepts/Binary/Shellcode]]

**NOP sled 와 패딩은 다른 일을 한다** — 자주 혼동된다:

| | 목적 | 실행되나 |
|---|---|---|
| **패딩** | 쓰기 커서를 복귀 주소 칸까지 **밀어내기** | 아니다 |
| **NOP sled** (`0x90`) | **착지 지점의 오차**를 흡수 | 그렇다 — 미끄러져 내려간다 |

sled는 **점프 목적지의 오차**만 흡수하고 **쓰기 위치의 오차**는 흡수하지 못한다. 그래서
sled를 깔아도 오프셋 측정은 여전히 정확해야 한다. 그리고 sled가 shellcode **뒤**에 있으면
실행이 그쪽으로 가지 않으므로 sled가 아니라 그냥 채움이다.

**shellcode 배치 시 감당할 것:** `push` 는 `rsp` 보다 **낮은** 주소에 쓴다. `ret` 직후
`rsp` 는 복귀 주소 칸 **바로 위**(= payload 전체보다 높은 주소)에 있으므로, shellcode를
버퍼 앞쪽에 두면 `push` 가 내려와 닿기까지 여유가 크다. 복귀 주소 칸 뒤에 두면 여유가
거의 없어 `push`/`call` 이 자기 몸을 덮을 수 있다.

### payload의 물리적 형태

```
[ 채움 X + 8 바이트 ][ 목적지 주소 8바이트 리틀엔디안 ]
   버퍼 + saved rbp
```

- `saved rbp` 구간을 쓰레기로 덮어도 **보통 무해하다** — `leave`가 rbp를 망가뜨리지만
  `ret`은 그 다음이고, 목적지 함수가 자기 프롤로그에서 `push rbp; mov rbp, rsp`로
  새로 세운다. (목적지가 상속된 rbp를 쓰기 전에 다시 세우는 경우에 한해서다.)
- 채움 값은 **무관하다.** `'A'`(`0x41`)가 관습인 이유는 크래시 시 레지스터에
  `0x4141414141414141`이 보이면 "내 입력이 여기까지 도달했다"가 즉시 확인되기 때문. 0으로
  채우면 그 구분이 안 된다.
- **뒤를 다 채울 필요가 없다.** 입력 함수의 반환값을 프로그램이 확인하지 않으면 필요한
  길이만 보내도 된다. 뒤를 더 덮어도(호출자 프레임 파괴) **먼저 실행되는 `ret`이 목적지로
  가므로** 결과는 같다.

### 성공 판정 — 플래그 없이도 된다

목적지 함수가 플래그 파일을 열지 **못했을 때 구분 가능한 메시지**를 내면, 그것이 플래그를
갖지 않은 사람도 쓸 수 있는 **oracle**이 된다: "exploit이 작동했는가"와 "플래그를 얻었는가"를
분리해 준다.

반대로 목적지가 `fopen` 실패를 검사하지 않으면 그 자리에서 SIGSEGV가 나고, **"도달했으나
파일이 없음"과 "엉뚱한 주소로 점프"가 화면상 구분되지 않는다.** 판정에는
`echo $?`(종료 코드)까지 봐야 한다 — `exit(1)`은 `1`, SIGSEGV는 `139`(= 128 + 11).

### 컴파일러 힌트가 의도를 누설한다

`__attribute__((noinline))` / `force_align_arg_pointer` 같은 attribute는 출제자가 무엇을
예상했는지 알려준다. inline되면 `call`이 사라져 **덮을 복귀 주소가 없어지고**, 아무도 부르지
않는 함수는 최적화로 삭제될 수 있다. 즉 이 attribute들은 "이 함수는 `ret`으로 진입될
것이다"라는 **자백**이다. → [[Concepts/Binary/Stack_Alignment]]

## Related

- [[Concepts/Binary/Stack_Frame_And_Call_Ret]] — ①~③의 메커니즘. **선수 개념.**
- [[Concepts/Binary/Stack_Alignment]] — `ret`으로 진입할 때 깨지는 정렬. "주소는
  맞는데 죽는" 현상의 원인.
- [[Concepts/Binary/ELF_Header_Fields]] — `e_type`으로 PIE 여부 = ④의 난이도 판정.
- [[Concepts/Linux/C_Input_Functions]] — ①이 가능한지, payload에 `0x00`을 넣을 수 있는지.
- [[Concepts/Linux/Exit_Code]] — 성공 판정에 쓰는 종료 코드.
- [[Tools/nm]] — 목적지 주소를 얻는 도구 (호출되지 않는 함수는 심볼 테이블에만 있다).
- [[Concepts/Binary/Shellcode]] — ④의 목적지를 **직접 만들어 넣는** 변종(ret2shellcode).
- [[Concepts/Binary/Memory_Protections]] — 네 방어 기제가 각각 어느 링크를 끊는지, 그리고
  각각을 ELF의 어느 구조에서 읽는지.
- [[Tools/pwntools]] — payload 조립·전송을 대신하는 도구 (손으로 한 뒤에 쓴다).

## Encountered / Applied In

- External: local-only wargame tree (no-publish) — 소스가 함께 주어진 입문 BOF에서,
  호출되지 않는 함수의 존재 자체가 의도를 드러낸 사례. 리버싱 툴 없이 정적 분석만으로
  체인 전체를 구성했다.

## Expand Later (`/deep` candidates)

- **ROP 전체 원자화** — gadget의 정의, `ret`로 끝나는 조각 연쇄, 스택을 "프로그램"으로
  쓰는 관점, `pop rdi; ret`으로 인수를 세팅하는 방법.
- **ret2libc** — libc base leak, `system("/bin/sh")`, one-gadget의 개념(도구는 쓰지 않되
  원리는 알아야 한다).
- **Stack canary 우회** — 부분 덮어쓰기, brute force(fork 서버), leak, 그리고 canary가
  `[rbp+0]` 아래에 있다는 좌표적 사실.
- **PIE 우회** — 부분 덮어쓰기(하위 1.5바이트는 base와 무관), leak을 통한 base 복원.
