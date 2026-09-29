---
date: 2026-09-29
domain: Binary
topic: Ret2Libc_Pattern
tags: [binary, exploitation, ret2libc, aslr, libc, leak, rop, nx, x86-64]
status: 🟡 developing
note_tier: lite
mastery: 50
first_encountered: "External: local-only wargame tree (no-publish) — NX 가 켜지고 win 도 없어서 목적지를 libc 에서 찾아야 했다"
reapplied_in: []
---

# Ret2Libc Pattern

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> [[Concepts/Binary/Ret2Win_Pattern]] 의 `/deep` 후보 **"ret2libc"** 슬롯을 소비한다.
> 핵심은 `system` 을 부르는 것이 아니라 **주소 하나로 매핑 전체를 역산하는 산수**다.

## Definition (Formal, EN)

**ret2libc** redirects a hijacked `ret` into a function that already exists in the loaded
**libc** image, with arguments supplied by ROP gadgets. Because libc is mapped at a
randomised base independent of the executable, the pattern requires **resolving that base at
runtime** from a single leaked libc address:

```
base   = leaked_addr − offset_of(leaked_symbol)
target = base + offset_of(target_symbol)
```

Every offset is a **per-build constant** read out of the *exact* libc image the target runs.

## Intuition (KR)

ASLR 은 libc 를 **통째로 한 덩어리로** 옮긴다. 내부 상대거리는 그대로다. 그래서 **아무 한
점의 주소만 알면 나머지 전부가 역산된다.** 지도 전체가 평행이동했을 때 랜드마크 하나로
원점을 되찾는 것과 같다.

## Key Points (무엇을 팠나)

### A. 왜 이 패턴으로 밀려나는가

| 상황 | 결과 |
|---|---|
| `win` 함수가 없다 | ret2win 불가 — 목적지를 직접 찾아야 한다 |
| **NX 켜짐** (`STACK flags rw-`) | ret2shellcode 불가 — 주입 코드는 실행되지 않는다 |
| 남는 것 | `r-x` 에 **이미 있는** 코드 = 바이너리의 `.text` + **libc** |

libc 는 압도적으로 크다. `system`, `execve`, `mprotect`, `open`/`read`/`write` 가 전부 있고
`"/bin/sh"` 문자열까지 들어 있다. **그래서 base 하나가 사실상 모든 것을 준다.**

→ 전제: [[Concepts/Binary/Memory_Protections]] §C(NX)·§G(ASLR), [[Concepts/Binary/ROP]](가젯)

### B. ⭐ 산수는 두 줄뿐이다

```
base   = leak − off(puts)          # leak 이 puts 주소일 때
target = base + off(target)
```

이것이 전부다. 어려운 것은 산수가 아니라 **off(...) 를 어디서 얻느냐**다.

### C. 오프셋은 빌드 상수 — "그" libc 에서만

⚠️ **버전·배포판·빌드 옵션이 다르면 오프셋이 전부 다르다.** 호스트의 libc, 컨테이너 기본
이미지의 libc, 인터넷에서 본 표 — 원격과 같은 파일이 아니면 **전부 틀린 주소**가 나온다.

| 필요한 값 | libc 안 어디 | 무엇으로 읽나 |
|---|---|---|
| 함수 오프셋 | **동적 심볼표** | `nm -D` / `readelf --dyn-syms` → [[Tools/nm]] |
| 문자열(`"/bin/sh"`) 오프셋 | `.rodata` **바이트** | `strings -a -t x` → [[Tools/strings]] |
| 가젯 오프셋 | `.text` 바이트 | `objdump -d` → [[Tools/objdump]] |

⭐ **문자열은 심볼이 아니다.** 심볼표에 없다. 그래서 함수와 문자열은 **찾는 방법이 다르고,
좌표계도 다르다** — 심볼표 값은 이미 가상 주소지만 `strings` 가 주는 것은 **파일 오프셋**이라
`PT_LOAD` 변환이 필요하다 → [[Concepts/Binary/ELF_Sections_And_Relocation]] §G

### D. ⭐ 왜 심볼표 값이 그대로 오프셋인가

`libc.so.6` 의 `e_type` 은 **`ET_DYN`(3)** 이다. 공유 객체는 적재 주소가 미정이므로 심볼의
`st_value` 가 **base 로부터의 거리**로 기록된다.

반대로 No PIE 실행 파일(`ET_EXEC`, 2)의 `st_value` 는 **절대 주소**다 — 그래서 바이너리 안의
가젯 주소는 base 를 더하지 않는다.

> ⭐ **같은 필드가 두 의미를 갖고, `e_type` 이 어느 의미인지 결정한다.**
> 한 payload 안에서 "base 를 더하는 주소"와 "안 더하는 주소"가 섞이는 이유가 이것이고,
> 초보가 가장 자주 틀리는 지점이다. → [[Concepts/Binary/ELF_Header_Fields]] §B

### E. ⭐ 공짜 검증 두 개 — 계산을 믿기 전에

**① 하위 12비트로 leak 을 검산한다.** 매핑은 **페이지 정렬**(4096 = `0x1000`)이므로
ASLR 은 하위 12비트를 **절대 바꾸지 않는다.**

```
off(puts) 의 하위 3자리 = 0x3a0   →   leak 은 반드시 0x…3a0 으로 끝난다
```

틀리면 그 libc 가 원격과 다른 것이다. base 계산까지 갈 필요도 없다.

**② base 의 하위 12비트가 0 이어야 한다.** `0x7f…000` 꼴.

```
[Cognitive Validation — Control Knob]
세 번 접속해 leak 3개로 base 3개를 구한다 → 값은 셋 다 다르고, 하위 12비트는 셋 다 0.
"매핑 전체가 평행이동한다"가 여기서 실측으로 확인된다.
```

### F. 목적지 함수 선택 — 인자 개수가 비용이다

| 함수 | 인자 | 필요한 `pop` 가젯 |
|---|---|---|
| **`system("/bin/sh")`** | **1** | `pop rdi` 하나 |
| `execve("/bin/sh", NULL, NULL)` | 3 | `pop rdi`, `pop rsi`, `pop rdx` |
| `one_gadget` 류 | 0 (제약 조건 있음) | 없음 — 대신 레지스터 상태 조건을 맞춰야 |

→ **인자 1개로 쉘을 여는 함수가 있으므로 `system` 이 표준 선택이다.** 가젯이 하나면 되고,
문자열도 libc 안에 이미 있으니 스택에 쓸 필요가 없다 (= 스택 주소를 몰라도 된다).

### G. ⭐⭐ 진단법 — **주소가 확실한 함수로 갈아 끼운다**

원격은 시그널을 알려주지 않는다. "점프는 했는데 죽었다"에서 원인이 둘로 갈린다:

1. 주소가 틀렸다 (오프셋/체인/오프셋 계산)
2. 주소는 맞는데 **목적지 함수 안에서** 죽었다 (정렬)

**구분 실험:** 목적지를 **leak 으로 받은 그 함수**(= 주소가 서버가 직접 알려준 값)로 바꾼다.
`puts` 처럼 문자열 포인터 하나를 받는 함수면 인자 세팅도 그대로 재사용된다.

| 결과 | 결론 |
|---|---|
| 문자열이 출력된다 | 오프셋·가젯·인자 전달·base 산수·슬롯 순서 **전부 정상**. 원인은 목적지 함수 내부 |
| 아무것도 안 나온다 | 체인 자체가 틀렸다 — 위로 올라가서 다시 |

⭐ **이것이 "한 번에 하나만 틀리게 만들기"의 ret2libc 판이다.** 그리고 `puts` 는 정렬이
어긋나도 살아남지만(내부에서 unaligned 로드를 쓴다) `system` 은 `movaps` 로 스택에 xmm 을
쏟으므로 죽는다 — 그래서 `puts` 는 **정렬 테스트로는 쓸 수 없고 체인 테스트로는 완벽하다.**
→ [[Concepts/Binary/Stack_Alignment]]

### H. libc 를 안 줬을 때 — 지문으로 식별

배포물에 `libc.so.6` 이 있으면 그것만 쓴다. 없으면:

- leak 의 **하위 12비트는 ASLR 불변**(§E) → 그 12비트가 해당 심볼 오프셋의 지문이다
- 심볼 2~3개의 지문을 모으면 빌드가 거의 유일하게 특정된다 (`libc-database` 가 하는 일)

⚠️ 순서: **배포물 확인이 먼저다.** 식별은 없을 때의 대비책이고, 있는데 식별하려 들면
틀린 libc 를 고를 위험만 추가한다.

## Encountered / Applied In

- External: local-only wargame tree (no-publish) — NX 켜짐 + No PIE + `win` 없음. 프로그램이
  libc 함수 하나의 주소를 스스로 찍어 주고, `naked` 함수에 `pop rdi; ret` 가젯이 심겨
  있었다. base 역산 → `"/bin/sh"` 의 `PT_LOAD` 변환 → 슬롯 홀짝 때문에 빈 `ret` 하나 추가 →
  shell. §G 의 갈아 끼우기 실험이 정렬 문제를 격리하는 데 결정적이었다.

## Related

- [[Concepts/Binary/Ret2Win_Pattern]] — 네 링크 체인과 ret2X 가족표. **선수 개념.**
- [[Concepts/Binary/ROP]] — 인자를 세팅하는 가젯 메커니즘. **선수 개념.**
- [[Concepts/Binary/Stack_Alignment]] — `system` 이 죽는 이유와 빈 `ret` 가젯.
- [[Concepts/Binary/Memory_Protections]] — NX 가 이 패턴을 강제하고, ASLR 이 leak 을 강제한다.
- [[Concepts/Binary/ELF_Header_Fields]] — `e_type` 이 `st_value` 의 의미를 정한다 (§D).
- [[Concepts/Binary/ELF_Sections_And_Relocation]] — 파일 오프셋 → 가상 주소 변환 (§C).
- [[Concepts/Binary/Binary_Number_Encoding]] — leak 파싱과 주소 패킹 (`int(s,16)` / `p64`).
- [[Concepts/Binary/Shellcode]] — **대조**: 코드를 넣는 대신 있는 코드를 부른다.
- [[Tools/nm]] · [[Tools/strings]] · [[Tools/objdump]] — 세 종류의 오프셋을 읽는 도구.
- [[Tools/pwntools]] — `ELF().address` 가 §B 의 덧셈을 대신한다.

## Expand Later (`/deep` candidates)

- **leak 이 없을 때** — PLT 의 `puts@plt` 로 GOT 를 출력시키는 **ret2plt leak** 2단계 체인
  (1차 payload 로 주소를 유출하고 같은 함수로 되돌아와 2차 payload 를 보낸다)
- **`one_gadget`** — libc 안의 "레지스터 조건만 맞으면 쉘이 뜨는" 단일 주소. 원리는 알아야
  하고 도구는 쓰지 않는다
- **Full RELRO 아래에서의 선택지** — GOT overwrite 가 막혔을 때 남는 경로
- **`__libc_csu_init` 가젯** — glibc 2.34 이후 사라진 만능 가젯과 그 대체
- **런타임 심볼 해석기가 공격면에 노출된 바이너리** — 프로그램 자신이 주소를 알려주는 경로
