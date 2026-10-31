---
date: 2026-10-31
domain: Binary
topic: UTF8_Encoding
tags: [binary, encoding, utf8, unicode, strings]
status: 🟡 developing
note_tier: lite
mastery: 40
first_encountered: "External: local-only wargame tree (no-publish) — 바이너리 안의 데이터가 UTF-8 블록 문자로 이루어진 경우"
reapplied_in: []
---

# UTF-8 Encoding

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> Captures what was actually asked about / dug into. Promote to a full atom via `/deep` when it earns the deep treatment.

## Definition (Formal, EN)

UTF-8 is a variable-length encoding of Unicode code points into 1–4 bytes. The leading bits of the first byte give the length; every continuation byte starts with `10`.

| Code point range | Bytes | Bit pattern |
|---|---|---|
| U+0000 – U+007F | 1 | `0xxxxxxx` |
| U+0080 – U+07FF | 2 | `110xxxxx 10xxxxxx` |
| U+0800 – U+FFFF | 3 | `1110xxxx 10xxxxxx 10xxxxxx` |
| U+10000 – U+10FFFF | 4 | `11110xxx 10xxxxxx 10xxxxxx 10xxxxxx` |

## Intuition (KR)

"몇 바이트짜리 글자인지"를 **첫 바이트의 앞자리**가 미리 말해준다. 그래서 중간 바이트에서도 `10` 으로 시작하면 "여긴 글자 시작이 아니다"를 알 수 있다.

## Key Points (무엇을 팠나)

### A. 손으로 디코드하기 (합성 예시)
`E2 96 80` 을 디코드한다.
1. `E2` = `1110 0010` → 3바이트 글자, 데이터 비트 `0010`
2. `96` = `1001 0110` → `10` 제거, 데이터 `010110`
3. `80` = `1000 0000` → `10` 제거, 데이터 `000000`
4. 이어 붙이면 `0010 010110 000000` = `0x2580` → **U+2580** (▀, 블록 요소 영역)

`E2 96 xx` 로 시작하는 연속은 U+2580~U+25BF 영역의 문자들이고, 마지막 바이트 하나가 어느 블록 문자인지를 정한다.

### B. `strings` 가 왜 놓치나
- 기본 `strings` 는 **인쇄 가능한 ASCII 가 4자 이상 연속**인 구간만 찾는다.
- UTF-8 멀티바이트는 각 바이트가 `0x80` 이상이라 ASCII 가 아니다 → 매칭되지 않는다.
- `-e S`(8비트 문자 포함) 계열 옵션이나, 바이트를 직접 디코드하는 스크립트가 필요하다.

### C. 데이터가 `dd`(4바이트) 단위로 박혀 있을 때
- 문자 하나(3바이트)를 4바이트 정수로 담으면 **리틀엔디안**이라 바이트 순서가 뒤집혀 보인다. 디코드 전에 메모리 순서로 되돌린다.
- 판독은 "정수 → 메모리 순서 바이트 → UTF-8 규칙" 3단계이고 `Binary_Number_Encoding` §C 의 엔디언 규칙을 쓴다.

### D. 자기 동기화 (self-synchronizing)
- 임의 위치에서 시작해도 `10xxxxxx` 를 건너뛰면 다음 글자 경계를 찾는다. 파일 중간을 잘라도 최대 한 글자만 깨진다.
- 반대로 "바이트 N 개 = 글자 N 개"라고 가정하면 길이 계산이 틀린다. 길이는 **바이트 수와 글자 수가 다르다**.

## Encountered / Applied In

- External: local-only wargame tree (no-publish) — 코드가 아닌 데이터 영역에 UTF-8 블록 문자가 정수 배열로 저장되어 있었다.

## Related

- [[Concepts/Binary/Binary_Number_Encoding]] — 엔디언(§C), 텍스트≠바이트(§I).
- [[Tools/strings]] — ASCII 기준 추출이라 멀티바이트를 놓친다.
- [[Concepts/Binary/Control_Flow_Graph]] — 같은 바이너리에서 데이터와 코드를 구분하는 맥락.

## Expand Later (`/deep` candidates)

- **varint / LEB128** — "길이를 미리 정하지 않는" 다른 인코딩과의 공통 설계
- overlong encoding 과 보안 필터 우회
- UTF-16 surrogate pair, BOM
