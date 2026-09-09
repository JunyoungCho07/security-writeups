---
date: 2026-08-30
domain: Binary
topic: Binary_Number_Encoding
tags: [binary, endianness, struct, hex, offset]
status: 🟡 developing
mastery: 55
note_tier: lite
first_encountered: "External: local-only wargame tree (no-publish) — 바이너리 파서 작성"
reapplied_in: []
---

# Binary Number Encoding

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> "바이트가 뭐냐 / 인덱스는 0부터냐 / MSB first가 뭐냐"를 밑바닥부터 다시 쌓은 스레드.

## Definition (Formal, EN)

A byte is the smallest **addressable** unit: 8 bits, 256 states. A multi-byte integer
field is defined by three independent parameters — **width**, **byte order**, and
**signedness** — none of which is recoverable from the bytes themselves. The bytes carry
no self-description; the specification supplies all three.

## Intuition (KR)

`00 00 01 2c`는 "숫자"가 아니라 **정수 4개**다. 이걸 하나의 수로 조립하는 규칙은 바이트 안에 없고 명세서에만 있다. 그래서 같은 4바이트가 규칙에 따라 `300`도 되고 `738263040`도 된다.

## Key Points (무엇을 팠나)

### A. 비트 → 바이트 → 주소
- **비트**: binary digit. 2진인 이유는 전자회로가 "전압 있음/없음" 두 상태만 안정적으로 구별하기 때문 — 10단계는 노이즈에 무너진다.
- **바이트 = 8비트 = 256가지**. 8인 것은 역사적 우연에 가깝다(6·7·9비트 기계가 공존했다). ASCII 7비트 + 여유 1, 2³이라 반으로 계속 쪼개짐, 16진 정확히 2자리와 대응 — IBM System/360이 굳혔다.
- ⭐ **바이트는 "주소를 가진 최소 단위"다. 비트에는 번지수가 없다.** 그래서 파일 오프셋·`seek`·`grep -b`·슬라이스가 전부 바이트 단위이고, 비트를 보려면 바이트를 꺼낸 뒤 `>> n & 1`로 뽑아야 한다.
- **16진을 쓰는 이유**: 1바이트 = 16진 **정확히 2자리**(2⁸ = 16²). 2진은 8자리라 길고, 10진은 자릿수가 들쭉날쭉해 바이트 경계가 안 보인다.

### B. 인덱스는 0부터 — 그리고 그게 계산을 공짜로 만든다
- 인덱스는 "몇 번째"가 아니라 **"시작점에서 얼마나 떨어졌는가"** = offset. 첫 원소는 0만큼 떨어져 있다.
- 슬라이스 `d[a:b]`는 앞 포함·뒤 제외 ⟹ **길이 = b − a**. 뺄셈이 딱 떨어진다.
- ⭐ 그래서 **"앞 N바이트가 머리말" ⟹ "본문은 인덱스 N"**. `+1`도 `−1`도 필요 없다.
- **혼동 주의**: 파일 오프셋·배열은 0부터, 편집기 줄 번호·사람의 "첫 번째"는 1부터. 에러 메시지의 숫자가 어느 체계인지 항상 확인.

### C. 엔디언 = 자릿값이 큰 바이트를 어디에 두는가
- MSB = Most Significant **Byte**(가장 자릿값이 큰 바이트). 바이트는 256진법의 한 자리다.
- **"MSB first" = big-endian**. 사람이 `1234`를 쓰는 순서와 같다. 명세서는 흔히 **network byte order**라 부르고, 이는 big-endian과 동일어다.
- ⚠️ MSB는 Most Significant **Bit**를 뜻하기도 한다. 문맥으로 구분 — "저장 순서" 얘기면 바이트, "bit 7 = value 128" 얘기면 비트.
- 파일 포맷은 big-endian이 흔하고 x86 계열 구조체는 little-endian이 흔하다. **추측 금지.**

### D. signed / unsigned — 비트 패턴은 같고 해석만 다르다
- 같은 `ff ff ff f4`가 `>I`로 `4,294,967,284`, `>i`로 `−12`.
- 가짓수는 둘 다 2³²로 동일. 같은 원소를 수직선 어디에 배치하느냐만 다르다 ([[Concepts/Binary/Twos_Complement]]).
- 길이·크기 필드는 음수가 무의미하므로 명세서가 `unsigned`를 못 박는다. **소문자 타입 코드를 쓰면 최상위 비트가 켜진 값이 음수 길이로 읽힌다.**

### E. `struct` — 바이트와 값 사이의 유일한 통로
- `struct.unpack(fmt, buf)` : bytes → **튜플**. 값이 1개여도 튜플이라 `[0]`이 필요하다. 타입 코드를 여러 개 쓰면(`">II"`) 원소가 그만큼 나오고 다중 대입으로 바로 풀린다.
- `struct.pack(fmt, *vals)` : 값 → bytes. **파이썬 int는 크기가 없다(무한 정밀도) — `pack`이 크기를 부여하는 단계다.** `len(pack(">I", x))`는 x가 뭐든 항상 4.
- 포맷 = `[바이트순서][타입코드…]`. 첫 글자를 **반드시** 명시(`>` `<` `!`) — 생략하면 `@`(네이티브 순서 + 정렬 패딩)가 되어 플랫폼마다 결과가 달라진다.
- 슬라이스 길이 ≠ 포맷 크기면 `struct.error`로 **시끄럽게** 죽는다. 조용히 틀리지 않는다는 점에서 선물.
- ⚠️ 숫자 접두사의 뜻이 타입마다 다르다: `4B` = 1바이트 정수 **4개**, `4s` = 4바이트 bytes **1개**. `s`만 예외.

### F. 진법은 표기일 뿐 값은 하나
- 소스코드의 `0xcbf43926`은 "16진수 텍스트"가 아니라 **16진법으로 적은 정수 리터럴**이다. 파싱 시점에 값으로 변환된다. `0xcbf43926 == 3421780262`.
- 따옴표를 씌우면 **타입이 바뀐다** — `int == str`은 에러 없이 그냥 `False`. (부등호는 `TypeError`를 내지만 `==`만 관대하다.)
- `f"{v:#010x}"` — `#`=`0x` 접두, `0`=0으로 채움, `10`=전체 폭. 4바이트 값이 항상 같은 폭으로 나와 **세로 대조가 가능**해진다.

## Encountered / Applied In
- External: local-only wargame tree (no-publish) — 컨테이너 포맷 필드 파싱

## Related
- [[Concepts/Binary/Twos_Complement]] — signed 해석의 실체
- [[Concepts/Binary/Chunked_Container_Formats]] — 이 규칙들이 적용되는 대상
- [[Tools/xxd]] — 바이트를 눈으로 보는 도구
- [[Concepts/Linux/File_IO_And_Cursor]] — 이 바이트를 파일에서 안전하게 꺼내오는 단계
- [[Concepts/Binary/Floating_Point_Precision]] — 정수는 간격 1로 정확, float은 큰 값에서 격자로 벌어짐 (대조)

## Expand Later (`/deep` candidates)
- 정렬(alignment)과 구조체 패딩 — `@` 포맷이 왜 파일 파싱에 위험한가
- varint / LEB128 / UTF-8 — "크기를 미리 안 정하는" 인코딩들의 공통 설계
- 부동소수점 IEEE 754의 바이트 레이아웃
