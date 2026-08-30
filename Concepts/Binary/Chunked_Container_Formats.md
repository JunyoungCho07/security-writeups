---
date: 2026-08-30
domain: Binary
topic: Chunked_Container_Formats
tags: [binary, file-format, tlv, length-prefix, parsing]
status: 🟡 developing
note_tier: lite
mastery: 45
first_encountered: "External: local-only wargame tree (no-publish) — binary format forensics"
reapplied_in: []
---

# Chunked Container Formats

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> 컨테이너 포맷을 직접 순회하는 파서를 손으로 짜면서 판 것. `/deep` 승격 후보는 §Expand Later.

## Definition (Formal, EN)

A **chunked container format** stores a stream of self-delimiting records, each of the
form `[Length][Type][Data][Checksum]`. The container layer parses only `Length` and
`Type`; the meaning of `Data` is a function of `Type`, defined by a separate per-record
layer. This is the **TLV** (Type-Length-Value) pattern.

## Intuition (KR)

봉투(컨테이너)와 편지(내용)가 분리되어 있다. 봉투 규격은 하나뿐이라 **내용을 하나도 몰라도 우편물을 끝까지 분류할 수 있고**, 모르는 편지는 길이만큼 건너뛰면 된다.

## Key Points (무엇을 팠나)

### A. 레코드의 끝을 표시하는 방법은 셋뿐이다
- **구분자(delimiter)** — 텍스트 방식. 사람이 읽기 쉽고 길이를 미리 몰라도 쓸 수 있다. **바이너리에는 못 쓴다**: 데이터가 0~255 전 범위를 취하므로 *안전한 구분자가 존재하지 않는다*. 이스케이프를 넣으면 크기·복잡도가 늘어난다.
- **고정 크기** — 계산이 가장 단순하고 임의 접근이 O(1). 가변 길이 데이터에는 낭비가 크다.
- **길이 접두(length-prefix)** — 바이너리 포맷이 거의 예외 없이 쓴다. 이유는 첫 번째 항목: **데이터 내용에 전혀 영향받지 않는다.** 부수 효과로 "내용을 해석하지 않고 다음 레코드로 점프"가 공짜가 된다.

### B. 두 개의 층으로 나뉜다 — 이게 설계의 핵심
- **컨테이너 층**: 모든 레코드가 동일 형식. `Length`만 읽으면 걸어갈 수 있고 `Data` 안을 들여다보지 않는다.
- **레코드별 층**: `Type` 값이 열쇠가 되어 `Data`의 해석 규칙을 고른다. 같은 8바이트가 Type에 따라 전혀 다른 필드로 쪼개진다.
- **확장성이 여기서 나온다**: 새 Type을 추가해도 옛 파서가 안 깨진다. 모르는 Type을 만나면 길이만큼 건너뛰면 되기 때문. PNG가 20년 뒤에 새 청크 타입(HDR 메타데이터 등)을 추가하고도 옛 뷰어와 호환되는 이유.
- Type 필드는 **이름표지 값이 아니다**. PNG는 Type 4바이트를 `A-Z`/`a-z`(0x41–0x5A, 0x61–0x7A)로 제한한다 — 숫자 필드가 물리적으로 못 들어간다.

### C. 길이 필드를 읽으려면 명세서에서 3개를 확정해야 한다
- **크기** (1/2/4/8바이트, 또는 varint)
- **엔디언** — 파일 포맷은 big-endian(network byte order)이 흔하다. 추측 금지, 명세서에 반드시 있다.
- **무엇을 세는가** ← 가장 자주 틀리는 곳. 데이터만 / 레코드 전체 / 타입+데이터 / 데이터+체크섬 — 포맷마다 다르다. 여기서 틀리면 체인이 두 번째 레코드부터 어긋나고 **파일이 손상된 것처럼 보인다**.
- 체크섬이 **덮는 범위**도 같은 종류의 함정이다. "including A and B, but not including C" 형태의 문장을 정확히 슬라이스로 옮겨야 한다.

### D. 순회 파서의 구조와 자기검증
- 위치 변수 `p` 하나가 세 가지 일을 한다: 읽기 기준(`d[p:p+n]`), 종료 조건(`while p < len(d)`), 전진(`p += 전진량`).
- 전진량은 **명세서에 직접 없다** — 구성 요소 크기의 합으로 유도하는 값이다.
- **결정적 오라클**: 모든 필드가 맞으면 순회 종료 시 `p == len(파일 크기)`가 **정확히** 성립한다. 어긋나면 그 차이의 형태(상수 오차/오버슛)가 어느 항을 빠뜨렸는지 알려준다.
- 보조 오라클: Type 태그가 규격이 강제한 문자 범위 안인가 — 오프셋이 1바이트만 어긋나도 즉시 쓰레기 바이트가 나온다. 오프셋 오류의 대부분을 여기서 잡는다.

### E. 반복되는 레코드를 볼 때 던질 질문
- 개수가 많다는 사실 **자체는 정보가 아니다**. 인코더가 버퍼 크기마다 스트림을 쪼개 담는 것이 정상 동작이고, 그래서 같은 데이터도 저장 프로그램에 따라 조각 수가 달라진다.
- 봐야 할 것은 **패턴**: 간격이 일정한가 / 마지막만 작은가(정상) / 규격이 요구하는 순서를 지키는가 / 선언한 길이대로 갔을 때 다음 레코드 시작에 정확히 도착하는가.
- **첫 번째와 마지막이 중간과 다른 것은 거의 모든 포맷에서 정상**이다. 준비 단계 직후와 잔여 처리 조각이기 때문. 가장 약한 이상 신호다.

## Encountered / Applied In
- External: local-only wargame tree (no-publish) — 컨테이너 포맷 구조 검증기를 직접 작성
- 공개 예시 포맷: PNG(청크), ZIP(로컬 헤더 + central directory), ELF(섹션 헤더), TIFF(IFD)

## Related
- [[Concepts/Binary/Binary_Number_Encoding]] — 길이 필드를 실제로 읽는 방법(엔디언·폭)
- [[Concepts/Binary/Binary_Format_Forensics]] — 이 구조를 이용해 조작을 찾는 방법론
- [[Concepts/Crypto/Checksum_Hash_MAC]] — 레코드마다 붙는 체크섬의 의미와 한계
- [[Concepts/Linux/File_Signatures]] — 컨테이너 앞에 붙는 시그니처
- [[Concepts/Binary/Twos_Complement]] — 길이 필드가 `unsigned`여야 하는 이유
- [[Tools/grep]] — 레코드 마커 오프셋을 독립적으로 뽑는 방법

## Expand Later (`/deep` candidates)
- varint(가변 길이 정수) 인코딩 — Protocol Buffers / LEB128 / UTF-8이 같은 문제를 푸는 방식
- ZIP의 이중 구조(로컬 헤더 + 끝의 central directory)가 왜 append-friendly한가, 그리고 그 구조가 낳는 파싱 모호성 공격
- PNG의 property bits — Type 이름의 대소문자 4비트로 "모르는 청크를 무시해도 되는가"를 인코딩하는 설계
