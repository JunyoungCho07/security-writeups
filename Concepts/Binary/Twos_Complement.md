---
date: 2026-08-30
domain: Binary
topic: Twos_Complement
tags: [binary, integer-representation, arithmetic, cpu]
status: 🟢 solid
note_tier: lite
mastery: 70
first_encountered: "External: local-only wargame tree (no-publish) — signed/unsigned 필드 해석 중"
reapplied_in: []
---

# Two's Complement

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> "왜 반전+1이 2^N−x와 같은가"와 "왜 하필 그 정의인가"를 증명·필연성·역사 세 축으로 판 것.

## Definition (Formal, EN)

In an N-bit system, two's complement encodes `−x` as `2^N − x`. Equivalently: invert
every bit, then add 1. The N-bit register is exactly the ring **ℤ/2ᴺℤ**; signed and
unsigned differ only in which representatives are chosen — `[0, 2ᴺ)` versus
`[−2ᴺ⁻¹, 2ᴺ⁻¹)`.

## Intuition (KR)

비트에는 부호가 없다. "음수"는 **넘치면 버리는 성질(mod 2^N)을 이용해 덧셈만으로 뺄셈이 되게 만든 약속**이다. 시계에서 −3시간이 +9시간과 같은 것과 정확히 같은 산술.

## Key Points (무엇을 팠나)

### A. `~x + 1 = 2^N − x` 의 증명 — 세 줄이다
항등식 하나면 끝난다:

```
x + ~x = 2^N − 1          (모든 비트가 1)
```

**왜 성립하나**: 각 비트 자리마다 `x`와 `~x` 중 정확히 하나만 1이므로 합은 모든 자리가 1이고 **자리올림이 한 번도 없다**. 따라서

```
    x + ~x = 2^N − 1
        ~x = 2^N − 1 − x        (양변 − x)
    ~x + 1 = 2^N − x      ∎     (양변 + 1)
```

- `+1`은 마법이 아니다. 비트 반전이 주는 값이 `2^N−1−x`라 목표까지 **정확히 1이 모자란다**.
- 같은 식이 1의 보수의 실패도 설명한다: `2^N−1−0 = 2^N−1 ≠ 0` ⟹ **0이 두 개**.
- 2의 보수에서 `−0`은 `2^N`이 되어 N비트 밖으로 넘쳐 사라진다 ⟹ **0이 하나**.

### B. 밑(base)과 무관한 기법이다
10진수 3자리(mod 1000)에서 `−5 = 1000 − 5 = 995`, 구하는 법은 "각 자리를 9에서 뺀 뒤 +1". `123 + 995 = 1118` → 자리 넘침 버림 → `118 = 123 − 5`. **기계식 계산기 시대의 '보수법(method of complements)'을 2진법에 옮긴 것.** 파스칼 계산기부터 컴프토미터까지 뺄셈 기어 없이 뺄셈을 하던 그 방법.

### C. 필연성 — 고른 게 아니라 강제된 것이다
요구조건을 하나만 두자: **"부호를 몰라도 같은 덧셈 회로로 맞는 답이 나올 것."** 식으로 쓰면 인코딩 `f`가

```
f(a) + f(b) ≡ f(a+b)   (mod 2^N)
```

를 만족해야 한다. `b = −x`를 넣으면 `f(x) + f(−x) ≡ 0`, 즉 `f(−x) ≡ 2^N − x`. **선택의 여지가 없다.** 부호-크기와 1의 보수가 탈락한 건 취향 문제가 아니라 이 방정식을 애초에 만족하지 않기 때문이다.

### D. 그래서 공짜로 따라오는 것들
- **뺄셈 회로 불필요** — `a − b = a + (~b + 1)`
- **부호 판정** = 최상위 비트 하나
- **부호 확장** = 최상위 비트를 왼쪽으로 복사 (8→16비트 등)
- **곱셈 하위 절반**이 signed/unsigned 동일

### E. 환 구조가 ISA에 그대로 새겨져 있다 — 확인 가능한 증거
| 연산 | signed/unsigned 구분 | 이유 |
|---|---|---|
| `ADD` / `SUB` | **하나뿐** | 환 준동형이라 결과 비트가 동일 |
| 곱셈 하위 절반 | 하나 | 마찬가지 |
| `DIV` / `IDIV` | **둘로 갈림** | 나눗셈은 환 준동형이 아니다 |
| `JB`(below) / `JL`(less) | **둘로 갈림** | 크기 비교는 대표원 선택에 의존 |

### F. 범위 비대칭과 역사
- N=8이면 `−128 ~ 127`. 0이 양수 쪽 자리를 차지해 양수가 하나 적다. `−2ᴺ⁻¹`의 절댓값은 표현 불가 ⟹ `abs()` 오버플로라는 고전 버그.
- **1의 보수가 오래 버틴 이유**: 부호 반전이 NOT 게이트 하나(자리올림 전파 없음), 범위 대칭. 진공관·초기 트랜지스터 시대엔 자리올림 전파가 비쌌다. carry-lookahead 가산기가 보편화되며 그 이점이 사라졌고, 남은 건 `−0`이라는 영구 세금뿐이었다.
- 초기엔 셋이 공존: 부호-크기(IBM 704/7090), 1의 보수(CDC 6600·UNIVAC 1100·PDP-1), 2의 보수. **IBM System/360(1964)**이 2진 정수에 2의 보수를 채택하며 사실상 표준화, 마이크로프로세서 시대가 못을 박았다(트랜지스터 예산이 빠듯한 칩에서 "덧셈기 하나로 둘 다"는 포기 불가).
- **C는 C11까지 세 표현을 모두 허용**했다. **C++20이, 이어서 C23이 2의 보수를 의무화** — 사실상 표준이 된 지 50년 만에 공식화.

## Encountered / Applied In
- External: local-only wargame tree (no-publish) — 바이너리 필드를 `unsigned`로 읽어야 하는 근거를 따지다가

## Related
- [[Concepts/Binary/Binary_Number_Encoding]] — signed/unsigned 선택이 실제 파싱에 미치는 영향
- [[Concepts/Binary/Chunked_Container_Formats]] — 길이 필드가 `unsigned`인 이유(길이는 음수일 수 없다)

## Expand Later (`/deep` candidates)
- 부호 있는 오버플로가 C/C++에서 **정의되지 않은 동작(UB)**인 이유와, 2의 보수 의무화 이후에도 UB로 남은 이유
- 포화 산술(saturating arithmetic)과 SIMD — 넘침을 버리지 않고 상한에 붙이는 대안
- carry-lookahead 가산기의 구조: 왜 `+1`의 비용이 사라졌는가
