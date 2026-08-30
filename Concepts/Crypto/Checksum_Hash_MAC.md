---
date: 2026-08-30
domain: Crypto
topic: Checksum_Hash_MAC
tags: [crypto, integrity, crc, hash, mac, checksum]
status: 🟡 developing
note_tier: lite
mastery: 55
first_encountered: "External: local-only wargame tree (no-publish) — 레코드 체크섬 검증"
reapplied_in: []
---

# Checksum · Hash · MAC

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> "체크섬이 뭐냐" → "해시가 체크섬의 일부냐" → "그럼 왜 안 바꾸냐"로 이어진 스레드. `Concepts/Crypto/`의 첫 노트.

## Definition (Formal, EN)

A **checksum** is a *role*: a value stored alongside data and recomputed later to detect
change. A **hash function** is a *class*: any deterministic map from arbitrary-length
input to fixed-size output. Any hash can fill the checksum role. A **MAC** is a keyed
function `f(data, key)` — without the key the value cannot be produced at all.

## Intuition (KR)

"해시"는 **함수의 종류**를 묻는 말이고 "체크섬"은 **그 값을 어디에 쓰는가**를 묻는 말이다. 서로 다른 축이라 포함관계를 따질 수 없다 — 같은 SHA-256 값이 다운로드 검증에 쓰이면 checksum, 딕셔너리 버킷 결정에 쓰이면 hash다.

## Key Points (무엇을 팠나)

### A. 두 단어는 다른 축에 있다
```
해시 함수 (임의 길이 → 고정 길이, 결정적)
├── 비암호학적
│   ├── 오류 검출용 ── CRC-32, Adler-32, Fletcher, 패리티
│   │                   └ 이것들을 통칭할 때 "체크섬 알고리즘"이라 부른다
│   └── 자료구조용 ── xxHash, MurmurHash, FNV   ← 체크섬이 아니다
└── 암호학적 ── SHA-256, SHA-3, BLAKE3 (MD5·SHA-1은 파훼)
```
좁은 의미로 쓸 때조차 **`체크섬 ⊂ 해시`**이지 그 반대가 아니다. `sha256sum`의 `sum`, 배포판의 `SHA256SUMS` 파일이 그 흔적.

**MAC은 이 트리에 없다.** HMAC은 해시로 만들어졌지만 입력이 `(data, key)`라 애초에 다른 종류의 함수다.
```
해시          f(data)       → 누구나 계산 가능
암호학적 해시  f(data)       → 계산은 가능하되 역산·충돌 생성이 불가능
MAC          f(data, key)  → 키 없이는 값 자체를 만들 수 없다   ← 위조 방어는 여기서 시작
```

### B. 체크섬의 세 성질
- **결정적** — 재계산이 가능하다. 전부의 전제.
- **고정 크기** — 0바이트든 1MB든 같은 크기. 파일 안에 자리를 미리 잡아둘 수 있다.
- **눈사태(avalanche)** — 1비트 차이가 값 전체를 바꾼다. 이게 없으면 오류 두 개가 서로 상쇄해 못 잡는다.

### C. CRC의 실체와 그 보장
- **C**yclic **R**edundancy **C**heck. 데이터 비트열을 GF(2) 위의 다항식으로 보고 생성 다항식으로 나눈 **나머지**. GF(2)에서 덧·뺄셈이 전부 XOR이라 구현은 **시프트와 XOR뿐** — 1960년대에 몇 게이트로 만들어졌다.
- 그 구조 덕에 **수학적으로 보장되는** 검출 능력이 있다: 단일 비트 100%, (적절한 다항식이면) 2비트 100%, **CRC 폭 이하의 버스트 오류 100%**. "대충 섞는" 게 아니라 정리(theorem)다.
- ⚠️ **`CRC-32`는 하나의 알고리즘이 아니다.** width·poly·init·refin/refout·xorout 다섯이 전부 맞아야 같은 값이 나온다. 같은 이름의 변종끼리도 값이 전혀 다르다(예: `zlib.crc32` ≠ `cksum(1)`).
- **check value로 구현을 먼저 검증해라**: CRC 카탈로그는 변종마다 문자열 `123456789`에 대한 규정값을 준다. 진짜 데이터에 돌리기 전에 여기서 맞춰라 — 안 맞으면 전 레코드가 불일치로 나오고 "파일이 다 깨졌다"는 잘못된 결론에 도달한다.

### D. 자기참조 문제와 덮는 범위
- 체크섬 필드는 **자기 자신을 덮을 수 없다** — 값을 쓰는 순간 범위가 바뀌어 순환이 된다. 그래서 명세서가 덮는 범위를 반드시 명시한다.
- 배치는 둘뿐: 레코드 **뒤에 붙이기**(쓰는 쪽이 편하다 — 흘려보내며 누적 계산하고 끝에 덧붙임) 또는 헤더의 고정 필드.
- ⚠️ **범위를 틀리면 "손상"과 구분이 안 된다.** 1바이트 더/덜 포함해도 결과는 똑같이 "불일치"다.
  - 구별법: **모든 레코드에 대해 돌려라.** 전부 불일치면 내 코드가 틀렸고, 하나만 불일치면 그게 진짜다. 단일 레코드만 계산하면 아무 판단도 못 한다.

### E. 검출(detection) ≠ 정정(correction)
N바이트의 변화를 4바이트로 요약한 값이다. **"달라졌다"는 담을 수 있어도 "어느 비트가"는 원리적으로 담을 공간이 없다.**

| | 알려주는 것 | 대가 |
|---|---|---|
| CRC / 체크섬 | 달라졌다는 **사실** | 여분 비트 적음 |
| Hamming / Reed-Solomon | **위치**, 나아가 복원 | 여분 비트 훨씬 많이 |

### F. ⭐ 체크섬은 보안 장치가 아니다 — 판정의 비대칭
CRC는 공개된 결정적 함수다. 데이터를 고친 사람이 체크섬도 다시 계산해 덮어쓰면 완벽히 일치한다. CRC는 선형이라 **원하는 값이 나오도록 4바이트를 역산하는 것**까지 가능하다.

```
불일치  →  강한 증거. 뭔가 어긋났다 (내 실수이거나, 진짜 조작)
일치    →  아무것도 증명 못 함. 조작자가 같이 고쳤을 수도 있다
```

**전부 일치했다는 건 "다른 축으로 넘어가라"는 뜻이지 사건 종결이 아니다.**

| | 방어 대상 | 비고 |
|---|---|---|
| 체크섬 (CRC, Adler) | 우발적 손상 — 비트 썩음, 전송 오류 | 빠르고 하드웨어 친화적 |
| 암호학적 해시 | 같은 값을 내는 다른 데이터를 못 만들게 | 값이 파일과 같은 곳에 있으면 여전히 무력 |
| MAC / 서명 | **의도적 위조** | 배포판이 `SHA256SUMS`에 GPG 서명을 붙이는 이유 |

### G. 왜 전부 SHA-256으로 안 바꾸나 — 두 번째 이유가 반직관적
- **비용**: 같은 입력에 대해 CRC-32가 SHA-256보다 한 자릿수 빠르다. CRC는 몇 게이트짜리 회로라 디스크 컨트롤러·이더넷 칩·메모리 버스가 *모든* 바이트에 건다. 그 자리에 SHA-256은 물리적으로 못 들어간다.
  - (덤: 특정 칩에서 MD5가 SHA-256보다 **느릴 수** 있다 — SHA 전용 명령어가 있고 MD5는 없어서. "오래된 것이 빠르다"는 성립하지 않는다.)
- **보장**: 우발적 손상 검출에서는 **CRC가 더 강하다.** CRC는 특정 오류 부류에 대해 100% 검출을 *증명*하지만, SHA-256은 어떤 부류에도 보장이 없고 2⁻²⁵⁶의 확률만 있다. 목적에 맞게 설계된 도구가 범용 도구를 이기는 사례.

## Encountered / Applied In
- External: local-only wargame tree (no-publish) — 레코드별 CRC 검증으로 조작 레코드를 특정

## Related
- [[Concepts/Binary/Chunked_Container_Formats]] — 체크섬이 붙는 자리
- [[Concepts/Binary/Binary_Format_Forensics]] — 축 3의 운용법, "판정자를 매수하지 마라"
- [[Concepts/Linux/Base64_Encoding]] — 인코딩 ≠ 무결성 ≠ 암호화의 구분

## Expand Later (`/deep` candidates)
- CRC를 §부록 레퍼런스 구현대로 직접 구현해 라이브러리와 대조 (진짜 독립 검증)
- CRC의 선형성과 그것을 이용한 의도적 충돌 구성
- HMAC의 구조 — 왜 `hash(key || msg)`가 아니라 이중 해시인가 (length-extension 공격)
- SHA-1 충돌(SHAttered)이 실무에 준 충격과 마이그레이션 경로
