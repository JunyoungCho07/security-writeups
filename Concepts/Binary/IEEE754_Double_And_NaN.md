---
date: 2026-10-31
domain: Binary
topic: IEEE754_Double_And_NaN
tags: [binary, floating-point, ieee754, nan, encoding]
status: 🟡 developing
note_tier: lite
mastery: 45
first_encountered: "External: local-only wargame tree (no-publish) — 임의의 8바이트를 double 의 텍스트 표기로 운반해야 했던 문제"
reapplied_in: []
---

# IEEE-754 Double Layout and NaN

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> Captures what was actually asked about / dug into. Promote to a full atom via `/deep` when it earns the deep treatment.

## Definition (Formal, EN)

A binary64 value is 64 bits: `[sign:1][exponent:11][fraction:52]`. For exponent field `e` in `1..2046` the value is

`(-1)^s × (1 + f/2^52) × 2^(e − 1023)`.

`e = 0` is the subnormal/zero regime (no implicit leading 1), and `e = 2047` is **reserved**: `f = 0` encodes ±∞, `f ≠ 0` encodes **NaN** (Not a Number). The formula is *not* applied at `e = 2047`.

## Intuition (KR)

과학적 표기법 `유효숫자 × 밑^거듭제곱` 의 이진수 버전이다. **가수부(fraction)** = 유효숫자의 소수점 아래, **지수부(exponent)** = 소수점을 옮기는 횟수. 지수부 맨 끝 값 하나는 "보통 수 바깥"을 표시하려고 통째로 예약돼 있다.

## Key Points (무엇을 팠나)

### A. 필드 읽기 — 직접 쪼갠 예 (합성값)

| 값 | 전체 비트 | 부호 | 지수부 | 가수부 |
|---|---|---|---|---|
| `6.5` | `0x401a000000000000` | 0 | `0x401` (1025) | `0xa000000000000` |
| `1.0` | `0x3ff0000000000000` | 0 | `0x3ff` (1023) | 0 |
| `2.0` | `0x4000000000000000` | 0 | `0x400` (1024) | 0 |

- `6.5` 검산: 가수부 `0xa000000000000` 은 52비트 중 맨 앞이 `1010` → 0.625. `(1 + 0.625) × 2^(1025−1023) = 1.625 × 4 = 6.5`.
- **1023 은 bias 다.** 음수 지수를 부호 없는 필드에 저장하려고 더한 값이지, 거듭제곱 횟수가 아니다. "가수부 0 → 값 1" 이 아니라 `(1 + 0) = 1` 이 곱해지는 앞 숫자일 뿐, 밑은 2 다.
- `(1 +)` 의 1 은 저장하지 않는 **암묵적 선행 1**이다.

### B. 지수부 값에 따른 네 영역

| 지수부 | 가수부 | 의미 |
|---|---|---|
| 전부 0 | 0 | ±0 |
| 전부 0 | ≠ 0 | **subnormal** — 공식의 `1 +` 가 없다. 아주 작은 수 |
| 1..2046 | 임의 | 보통 수 |
| **전부 1 (2047)** | **0** | **±무한대** |
| **전부 1 (2047)** | **≠ 0** | **NaN** |

- 합성 주소 `0x00007f1234567890` 은 부호·지수부가 전부 0 → subnormal. 값은 `6.90289569103456e-310` 이고 `repr` 왕복이 **정확히** 된다 (주소 바이트가 가수부에 그대로 들어 있다).
- 사용자 공간 주소는 상위 2바이트가 `00 00` 이라 NaN 영역(`7ff`/`fff` 시작)과 겹칠 수 없다.

### C. 왜 NaN 비트가 "더 큰 수"가 아닌가
- 수식 `1.1 × 2^1024 > 1.0 × 2^1024` 는 산술로는 맞지만 지수부 2047 에는 **공식을 적용하지 않는다.** 최대 보통 수는 지수부 2046(약 `1.8e308`).
- 무한대와 NaN 은 지수부가 같고, 가수부는 **크기가 아니라 구분 스위치**다: 0 = "경계에서 넘쳤다"(오버플로, `1/0`), ≠0 = "수가 아니다"(`0/0`, `inf − inf`).
- NaN 과의 `<`, `>`, `==` 는 전부 **거짓** (unordered). 그래서 `nan > inf` 도 거짓이고 `x != x` 가 NaN 검사다.

### D. NaN 이 존재하는 이유
- 정의할 수 없는 연산 결과의 선택지는 둘뿐이다: ① 예외로 멈춘다(병렬 계산에서 원소 하나가 전체를 죽인다) ② 아무 수나 낸다(틀린 값이 조용히 섞인다). NaN 은 ③ **계산을 계속하되 값 자체에 "무효" 표시를 남긴다.**
- **전염**: `nan + 1` = NaN. 마지막에 한 번만 검사해도 놓치지 않는다.
- 언어 선택이 다르다: C 는 `0.0/0.0` 이 NaN, Python 은 `ZeroDivisionError` (단 `inf − inf` 는 NaN).

### E. NaN 가수부 — quiet 비트와 payload
- 맨 위 가수부 비트: 1 = **quiet NaN**, 0 = **signaling NaN**. 나머지 51비트는 **payload** (규격은 "진단 정보를 실을 수 있다"고만 정함).
- 측정 (arm64 Mac): `float('nan')`, `inf − inf`, `inf × 0` 모두 `0x7ff8000000000000` — **연산이 새로 만든 NaN 은 payload 0.** 입력 NaN 의 payload 는 전달된다 (`0x…0abc` + 1.0 → `0x7ff8…0abc`). signaling NaN 은 연산 후 quiet 비트가 켜진다.
- **기본 NaN 의 부호는 CPU 마다 다르다** (x86 SSE 는 부호 1 인 `0xfff8…`, arm64 는 `0x7ff8…`).
- payload 의 실제 용도는 드물다 — 대표적으로 **NaN boxing** (JS 엔진, LuaJIT 이 포인터·정수를 51비트에 숨김).

### F. 텍스트로 운반할 때의 두 함정
- `'%f'` 는 소수점 아래 **6자리** 가 기본이다 (C 표준 `printf` 에 "정밀도 생략 시 6"). 이 기본값은 사람이 읽기 좋은 길이로 정한 역사적 선택이다. `e-310` 크기는 `0.000000` 이 돼서 비트가 사라진다. `repr(float)` 는 **왕복 가능한 최단 표기**(유효숫자 기준)라 안전하다.
- NaN 은 many-to-one: 비트 패턴은 수없이 많은데 글자 `nan` 은 하나 → 파싱하면 기본 quiet NaN 하나로 합쳐진다. 원하는 payload 를 글자로 지정할 방법이 없다.

## Encountered / Applied In

- External: local-only wargame tree (no-publish) — `scanf("%lf")` 로 주소 8바이트를 보내려고 `repr(unpack('<d'))` 를 쓰고, `%f` 가 안 되는 이유와 NaN 이 왕복 불가인 이유를 복습 퀴즈에서 짚었다.

## Related

- [[Concepts/Binary/Floating_Point_Precision]] — 같은 형식의 *정밀도* 측면 (큰 값에서 격자가 벌어진다).
- [[Concepts/Binary/Binary_Number_Encoding]] — §K 같은 8바이트의 두 해석, §D signed/unsigned.
- [[Concepts/Binary/Twos_Complement]] — 정수 쪽의 부호 표현 (대조: 부호 비트 + bias).

## Expand Later (`/deep` candidates)

- rounding modes (round-to-nearest-even), 비트 하나를 올리는 `nextafter`
- FP 예외 플래그 (invalid, overflow, divide-by-zero) 와 trap 설정
- x87 80-bit extended 와 binary32/binary16/bfloat16 대조
- NaN boxing 을 실제 엔진 구조로
