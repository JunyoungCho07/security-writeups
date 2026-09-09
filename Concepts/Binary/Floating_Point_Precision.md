---
date: 2026-09-08
domain: Binary
topic: Floating_Point_Precision
tags: [binary, ieee754, float, precision, type-confusion, trust-boundary]
status: 🟡 developing
mastery: 50
note_tier: lite
first_encountered: "External: local-only wargame tree (no-publish) — 웹 서비스의 정수 ID 처리에서 float64 vs uint64 불일치"
reapplied_in: []
---

# Floating Point Precision

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> "float이 정수를 왜 못 담나 / 큰 값에서 왜 인접 정수가 뭉개지나"를 밑바닥부터 쌓고, 작은 숫자로 직접 `pow`/비트 분해를 돌려 확인한 스레드.

## Definition (Formal, EN)

An IEEE-754 **double** (`float64`) is a 64-bit number stored as
`(−1)^s · (1 + f/2^52) · 2^(E−1023)`, split into 1 sign bit + 11 exponent bits
(bias 1023) + 52 fraction bits. It carries a **fixed ~53 significant bits**, so
above `2^53` **not every integer is representable** — representable values sit on
a grid whose spacing grows with magnitude.

## Intuition (KR)

넓은 범위와 소수를 사는 대가로 **유효숫자를 유한하게 고정**한 표현이다. 그래서 값이
커질수록 표현 가능한 수 사이 간격이 벌어지고, 큰 정수는 격자점으로 반올림된다 —
정수형(`uint64`)이 `2^64`까지 모든 정수를 간격 1로 정확히 담는 것과 정반대의 trade-off.

## Key Points (무엇을 팠나)

- **비트 구성** — sign(1)+exponent(11)+fraction(52). `1.`이 암묵적(hidden bit)이라
  저장은 52비트여도 **유효 정밀도는 53비트**. `struct`로 double을 분해해 눈으로 확인.
- **`2^53` 경계** — 여기까지는 모든 정수가 정확. `2^53 + 1`은 표현 못 해 `+1`이 사라진다
  (53비트로 둘을 구분 못 함). 이 경계가 정수-안전 상한.
- **ULP 규칙 (control knob)** — 크기 `2^k` 근방의 간격 = `2^(k−52)`. `2^54`→2,
  `2^60`→256. 지수가 간격을 정한다. 그래서 `2^60`쯤에선 **256 배수 격자**에만 값이 있고,
  차이 1인 두 정수가 **같은 double로 붕괴**한다.
- **소수도 부정확** — `0.1`은 2진 순환소수라 53비트에서 잘린다. `0.1 + 0.2 ≠ 0.3`.
  큰-정수 간격과 같은 뿌리(유효숫자 유한).
- **보안적 귀결 — type/parser differential across a trust boundary.**
  같은 정수를 한 코드 경로는 `float64`로, 다른 경로는 `uint64`로 읽으면 **`2^53` 위에서
  두 해석이 불일치**한다. 인가(authorization)를 `float64` 비교로 하고 실제 조회를
  `uint64`로 하면, 서명/인가는 통과시키되 다른 리소스를 꺼내는 우회가 생긴다. 서명(HMAC)은
  **바이트를 인증하지 의미를 인증하지 않으므로**, 서명하는 주체가 스스로 틀린 타입으로
  판단하면 위조 없이도 경계가 뚫린다. 교훈: 인가와 실행은 **같은 canonical 타입**으로 결정을
  내려야 한다.

## Related

- [[Concepts/Binary/Binary_Number_Encoding]] — 정수의 정확 표현(간격 1, `2^64`까지). float의 직접적 대조군.
- [[Concepts/Binary/Twos_Complement]] — 부호 있는 정수 표현. 정수형이 "격자 없이" 담는 쪽 이야기.
- [[Concepts/Crypto/Checksum_Hash_MAC]] — MAC이 "바이트"를 인증한다는 점이 위 보안 귀결의 핵심 전제.

## Encountered / Applied In

- External: local-only wargame tree (no-publish) — 웹 서비스가 정수 리소스 ID를
  인가 단계에서 `float64`로 비교해 인접 ID가 붕괴한 사례.

## Expand Later (`/deep` candidates)

- IEEE-754 전체 원자화 — subnormals, rounding modes(round-to-nearest-even),
  `NaN`/`Inf`, 지수 bias의 필연성.
- **Type/parser differential across a trust boundary** — 같은 입력을 두 파서가 다르게
  읽는 취약점 계열(숫자 타입, 직렬화 포맷, 아카이브 파서)을 독립 개념으로.
