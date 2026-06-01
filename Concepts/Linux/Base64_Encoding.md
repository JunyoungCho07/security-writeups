---
date: 2026-06-01
domain: Linux
topic: Base64_Encoding
tags: [linux, encoding, base64, binary-to-text, information-theory]
status: 🟡 developing
mastery: 40
first_encountered: [[Wargames/Bandit/Level_10]]
reapplied_in: []
last_reviewed: 2026-06-01
---

# Base64_Encoding

## Core Idea (1-2 sentences, KR)

Base64 = 임의의 byte stream을 **7-bit-safe ASCII 64글자**로 1:1 가역 변환하는 binary-to-text encoding. 암호가 아니라 **포장지** — key 없이 누구나 풀 수 있고, 크기만 4/3로 늘어난다.

---

## [Step 1] Concept Categorization

**Binary-to-text encoding (radix-64 representation).** 구조적 DNA = "임의 byte를 제한된 안전 문자 집합으로 사영하는 radix 변환". 핵심은 *표현(representation)* 의 변경이지 *내용(information)* 의 은닉이 아니다. transport 계층(텍스트만 통과하는 채널)에서 binary를 실어 나르기 위한 어댑터.

`[[Concepts/Linux/Strings_Extraction]]`(binary 속 텍스트를 *발견*)의 정확한 dual — base64는 binary를 텍스트로 *위장 생성*한다.

## [Step 2] Definition

> [!definition] Base64 Encoding
> Base64는 사상 E: {0,1}\* → Σ\* (Σ = `[A-Za-z0-9+/]`, |Σ| = 64)로, 입력 byte stream을 24-bit 블록으로 분할하고 각 블록을 6-bit 4조각으로 나눠 각 조각(값 0–63)을 Σ의 한 글자에 매핑한다. 마지막 블록이 24-bit 미만이면 0-bit으로 우측 padding 후, 부족한 4글자 자리를 `=`로 채운다. E는 **전단사(bijective)** 이며 **key-less** — 복호 D = E⁻¹은 Σ에 대한 지식만으로 충분하다. 출력 길이 |E(m)| = 4·⌈|m|/3⌉ (byte 기준), 팽창률 → 4/3.
^definition

**내 언어로 (KR)**: 3 byte(24 bit)를 6 bit씩 4토막으로 잘라, 각 토막(0~63)을 "안전한 글자 64개"에 대응시킨다. 3으로 안 나눠떨어지면 0으로 채우고 `=`로 표시. 비밀이 없으니 그냥 글자만 알면 복원.

## [Step 3] Intuition

> [!tip] Intuition
> 8칸짜리 상자(byte)에 든 물건을 6칸짜리 상자(글자)로 옮겨 담는 것. 24개 물건이 8칸×3 = 6칸×4로 딱 맞아떨어진다. 옮기면 상자 수가 3→4로 늘어 부피 33%↑. 물건(정보) 자체는 그대로 — 포장만 바뀜.
^intuition

## [Step 4] Theory

**인코딩 메커니즘 (24-bit 정렬)**:

```
입력 3 byte:  [aaaaaaaa][bbbbbbbb][cccccccc]   (8+8+8 = 24 bit)
6-bit 재분할: [aaaaaa][aabbbb][bbbbcc][cccccc]   (6×4 = 24 bit)
각 6-bit(0–63) → Σ 인덱싱 → 4 ASCII 글자
```

**Padding 규칙 (입력 길이 mod 3)**:

| 마지막 블록 byte 수 | 유효 6-bit 조각 | 출력 | padding |
|---|---|---|---|
| 3 (24 bit) | 4 | 4글자 | 없음 |
| 2 (16 bit→18로 0채움) | 3 | 3글자 | `=` 1개 |
| 1 (8 bit→12로 0채움) | 2 | 2글자 | `==` 2개 |

**복호 (`base64 -d`)**: 각 글자를 6-bit로 역매핑 → 4글자를 24-bit로 재조립 → 3 byte 복원. `=` 개수만큼 끝 byte 폐기.

인과: data.txt가 valid Base64 텍스트(조건) → `base64 -d`가 6-bit 역매핑(B) → 24-bit 재조립으로 원본 byte 복원(C) → 그 byte가 printable ASCII면 평문 노출(D).

## [Step 5] When & Condition

성립 조건:
- 채널이 **텍스트(7-bit ASCII)만** 안전히 통과시킬 때 binary를 실어야 함 — email MIME, HTTP Basic Auth 헤더, data URI, JWT, XML/JSON 내 binary 첨부, PEM 인증서.
- 입력이 임의 byte여도 무방(전단사라 손실 0).
- 양측이 **동일 alphabet** 합의(standard `+/` vs URL-safe `-_`).

언제 쓰면 안 되나: **기밀성**이 필요할 때. Base64는 confidentiality = 0. 비밀은 별도 암호화 후 base64로 *전송 포장*만.

## [Step 6] Limitation & Alternatives

### 한계
- **보안 0**: key 없는 가역 변환. 인코딩된 secret = 평문 secret(디코딩 자명).
- **33% 팽창**: 대용량엔 대역폭·저장 낭비.
- **alphabet 충돌**: 표준 `+/`는 URL/파일명에서 문제(`/`=경로, `+`=공백) → URL-safe variant 필요.
- **줄바꿈 변형**: MIME base64는 76자마다 개행 삽입 — 디코더가 무시해야 함.

### 우월한 대안
- **base85 / Ascii85**: 팽창 25%로 더 효율적(4 byte→5 char). 단 사용 문자가 많아 JSON/URL에서 깨짐 → 이식성↓.
- **base32**: 대소문자 구분 없는 채널(DNS, 사람이 받아적는 토큰)에서 견고. 팽창 60%로 비효율.
- **순수 hex(base16)**: 디버깅·가독성 최고, 팽창 100%. (`xxd`, `od`)
- **압축 후 인코딩**: gzip → base64 순으로 팽창 상쇄.

## [Step 7] Duality & Null Space

**Dual #1 — 복호 D = E⁻¹**: base64는 전단사라 완전 가역. `[[Concepts/Linux/Strings_Extraction]]`(비가역 lossy projection)과 정반대 성질.

**Dual #2 — Strings_Extraction**: 의미론적 dual. strings = "binary 속 평문 *발견*"(우연히 존재하는 printable run 추출), base64 = "binary를 printable run으로 *인공 생성*". 즉 base64 출력은 strings가 100% 건져 올리는, 설계상 완전 printable한 텍스트.

**Null space**: 빈 입력 → 빈 출력(E(∅)=∅). 또한 **고정점 없음**(의미 있는): 어떤 비공백 입력도 E를 거치면 길이가 4/3배로 늘어 자기 자신일 수 없다.

## [Step 8] Validation

- **Limit Test**: 입력 길이 → 0이면 출력 0. 길이 mod 3 → 0이면 padding 없음, 1이면 `==`, 2이면 `=`. 입력 → ∞면 출력/입력 비가 정확히 4/3로 수렴(padding 효과 소멸).
- **Dimensional Check**: 정보량 보존 검증. 입력 24 bit = 출력 4글자 × 6 bit = 24 bit. 단 각 6-bit 글자가 8-bit byte로 저장 → 저장 차원 32 bit. 즉 *정보* 차원은 보존(24), *저장* 차원은 4/3배(24→32). 이 둘의 구분이 핵심.
- **Control Knob**: ① alphabet(standard `+/` vs URL-safe `-_`)이 출력 문자 집합을 규정, ② padding on/off, ③ line-wrap 폭(MIME 76). 이 셋이 같은 입력의 출력 형태를 완전 결정.

## [Step 9] Advanced Perspective

**정보이론 관점**: encoding은 **entropy를 보존**한다. H(E(m)) ≈ H(m) (변환은 정보를 더하거나 빼지 않음). 반면 *글자당 측정* 엔트로피는 다르다 — 평문을 인코딩한 base64는 글자당 엔트로피가 낮고(원문 구조 반영), ciphertext를 인코딩한 base64는 글자당 ≈ 6 bit(균등)에 근접. → **decode 후 byte 엔트로피**가 "단순 인코딩 vs 암호문 포장"의 판별자(Level 10 quiz, Strings_Extraction Step 9와 연결).

**Radix economy**: base-N 인코딩의 byte당 출력 글자 수 = 8 / log₂(N). base64 = 8/6 = 1.333, base85 = 8/log₂85 ≈ 1.248, base16 = 8/4 = 2. N이 클수록 효율적이나, **안전 문자 집합 크기**가 채널 제약으로 N 상한을 정한다.

## [Step 10] Link to Upper Concepts

- **Radix / positional number system**: base64는 64진법 표현. 일반 진법 변환의 특수 케이스.
- **Channel coding / transport encoding**: "제약 있는 채널에 데이터를 맞추는 변환"의 한 사례(line coding, MIME, percent-encoding과 동류).
- **Information theory**: 표현 변경 ≠ 정보량 변경 (External: JY_KAIST/02_Concepts/Math/Entropy).
- **encoding ↔ encryption 구분**: 보안의 first principle — Kerckhoffs 원칙(키만 비밀)과 대비해, base64는 *키 자체가 없음*.

## [Step 11] Generalization

byte stream을 alphabet 크기 N으로 인코딩하는 **base-N family**:

| N | bits/symbol | byte당 출력 char | 팽창 | 안전성 | 용도 |
|---|---|---|---|---|---|
| 16 | 4 | 2.00 | 100% | 최고(0-9a-f) | hex dump, 디버깅 |
| 32 | 5 | 1.60 | 60% | 대소문자 무관 | DNS, TOTP secret |
| 64 | 6 | 1.333 | 33% | 표준 텍스트 안전 | MIME, JWT, PEM |
| 85 | ~6.41 | 1.248 | 25% | 낮음(특수문자多) | PostScript, git binary diff |

Pattern: **(byte stream) → (radix-N 재해석) → (alphabet Σ_N 매핑) → (padding)**. N 선택은 *효율(↑N)* 과 *채널 안전성(↓N)* 의 trade-off.

## [Step 12] Confer (Comparison)

- **vs. `[[Concepts/Linux/Strings_Extraction]]`**: 가역 인공 생성(위장) vs 비가역 발견. base64 출력은 strings가 완전히 잡아내는 printable run. (Step 7 Dual #2)
- **vs. 암호화(encryption)**: 둘 다 데이터를 "다르게 보이게" 하나, 암호화는 *키 없이 복원 불가*, base64는 *키 자체가 없음*. confidentiality: 암호화 > 0, base64 = 0.
- **vs. 압축(compression)**: 압축은 크기↓(엔트로피 밀도↑), base64는 크기↑(33%). 정반대 방향. 실무선 compress→encode 순.
- **vs. hex(base16)**: hex는 사람이 읽기 쉽고 byte 경계 자명(2글자=1byte), 팽창 100%. base64는 빽빽하지만 byte 경계가 6/8 비정렬.
- **vs. percent-encoding(URL encoding)**: 둘 다 안전 문자만 사용하나, percent-encoding은 안전 문자는 그대로 두고 위험 문자만 `%XX`로 — *선택적*. base64는 *전체* 변환.

## [Step 13] Implication

1. **"인코딩 = 보안"이라는 흔한 오해의 근절**: API 응답·쿠키·JWT payload가 base64라고 안전한 게 아니다. JWT의 payload는 base64url일 뿐 **암호화 아님** — 누구나 디코딩해 claim을 읽는다(서명만 위변조 방지).
2. **secret을 base64로 "숨기면" 안 됨**: 코드/설정의 base64 문자열은 grep+decode로 즉시 노출 → secret manager 사용 근거.
3. **악성코드 난독화 벡터**: PowerShell `-EncodedCommand`, 매크로 payload가 base64로 포장 → 탐지 우회. 방어: base64 디코딩 후 재검사(`base64 -d | grep`).
4. **데이터 exfiltration**: DNS/HTTP로 base64 인코딩해 binary 유출. IDS가 긴 base64 문자열을 이상 신호로 탐지.

## [Step 14] Application

**보안**:
- JWT 디코딩: `cut -d. -f2 token | base64 -d` — payload claim 즉시 확인(서명 검증은 별개).
- malware payload 복원: `strings sample | grep -E '^[A-Za-z0-9+/]{40,}={0,2}$' | base64 -d`.
- HTTP Basic Auth: `Authorization: Basic $(echo -n user:pass | base64)` — **평문과 동등**, HTTPS 없이는 노출.

**일반**:
- binary 첨부 email(MIME), data URI(`data:image/png;base64,...`), PEM 인증서/키 포맷.
- 바이너리를 텍스트 설정파일·JSON에 임베드.

**Bandit 맥락 (Level 10)**: `base64 -d data.txt` — data.txt가 base64 텍스트로 위장된 평문 password. 가역이라 한 줄로 복원. "encoding ≠ encryption"의 실증.

## [Step 15] Background Knowledge

- **기원 — PEM & MIME**: Base64는 1987년 Privacy-Enhanced Mail(PEM) 초안에서 binary를 7-bit SMTP로 보내려 도입. 1996년 **MIME(RFC 2045)** 가 표준화해 email 첨부의 사실상 기반이 됨.
- **RFC 4648 (2006)**: Base16/32/64를 단일 문서로 정리. URL-safe alphabet(`-` `_`)을 별도 정의 — `+/`가 URL·파일명에서 충돌하기 때문.
- **왜 하필 64?**: 인쇄 가능 ASCII 중 "거의 모든 시스템·문자셋에서 동일하게 해석되는" 안전 문자가 대략 64개. 6 = log₂64이 byte(8)와 24-bit(=lcm)에서 깔끔히 정렬되는 것도 결정적. base85는 더 효율적이나 안전 문자 가정이 약해 범용성↓.
- **이름의 함정**: "encode/decode"라는 단어가 암호의 뉘앙스를 줘 보안 오해를 낳음. 실제론 Morse code·ASCII와 같은 *표현 약속*일 뿐.

---

## Formal Summary (EN)

> [!theorem] Base64 Bijectivity & Expansion
> The Base64 map E: B\* → Σ\* (with padding) is injective; its left inverse D satisfies D(E(m)) = m for all byte strings m, requiring only knowledge of Σ (no key). The output length is |E(m)| = 4⌈|m|/3⌉ symbols, giving an asymptotic expansion factor lim_{|m|→∞} |E(m)|/|m| = 4/3.

> [!proof] Sketch
> (Recoverability) Each output quartet encodes exactly 24 input bits (or fewer, marked by `=` count k ∈ {0,1,2}); decoding maps 4 symbols → 24 bits and drops the final k bytes signaled by padding ⟹ D∘E = id, key-free. (Expansion) Partition m into ⌈|m|/3⌉ blocks; each emits 4 symbols ⟹ |E(m)| = 4⌈|m|/3⌉. As |m|→∞ the ceiling's correction is O(1) ⟹ ratio → 4/3. ∎

---

## Cross-References

### Encountered In
- [[Wargames/Bandit/Level_10]] ← first (`base64 -d data.txt`)

### Tools That Implement This
- [[Tools/base64]] — coreutils encoder/decoder (`-d`, `-w`, `--ignore-garbage`)

### Related Concepts
- [[Concepts/Linux/Strings_Extraction]] (Confer — 위장 생성 vs 발견의 dual)
- [[Concepts/Crypto/ROT13_Cipher]] (Related — 같은 "위장 ≠ 보안" 계열, key-less reversible)

### Cross-Domain
- External: JY_KAIST/02_Concepts/Math/Information_Theory (entropy 보존, radix economy)
- External: JY_KAIST/02_Concepts/Math/Positional_Notation (base-N 진법 일반론)

---

## Quiz

**Q1** (Graduate-level): Base64는 33% 팽창하지만 Ascii85는 25%로 더 효율적이다. (a) byte stream을 alphabet 크기 N으로 인코딩할 때 byte당 출력 글자 수를 N의 함수로 유도하고, (b) 그럼에도 base64가 web/email의 사실상 표준이 된 이유를 "채널 제약 × 안전 문자 집합" 관점에서 논하라. (c) N을 무한히 키우면 팽창이 1에 수렴하는가? 그 물리적/공학적 상한은?

> [!tip]- 풀이
> **(a)** 글자 하나가 log₂N bit를 표현 → byte(8 bit)당 출력 글자 = 8 / log₂N. base16: 8/4=2, base32: 8/5=1.6, base64: 8/6≈1.333, base85: 8/log₂85≈1.248.
>
> **(b)** N↑ = 효율↑이지만, alphabet에 특수문자(`~!#$%^&*` 등)가 포함될수록 JSON·URL·XML·email 헤더 등에서 escape/충돌 발생. base64의 `[A-Za-z0-9+/]`는 거의 모든 텍스트 채널에서 무탈 통과하는 "최대 안전 부분집합"에 가깝다. 즉 **이식성(robustness) > 공간 효율**. Ascii85는 PostScript·git 내부처럼 채널을 통제할 수 있는 곳에서만 산다.
>
> **(c)** 8/log₂N → 1은 log₂N → 8, 즉 N → 256일 때. 그러나 N=256이면 alphabet = 전체 byte = "인코딩 안 함(identity)" = binary 그대로 → 텍스트 안전성 0. 따라서 팽창 1은 "변환 안 함"과 동치인 degenerate 극한. 공학적 상한은 **채널이 허용하는 안전 문자 수**가 정한다(텍스트 채널 ≈ 64~95).
>
> 핵심: 인코딩 효율과 채널 안전성은 trade-off. base64는 그 파레토 최적점 부근.

---

> [!flashcard]
> **Q**: Base64가 데이터 크기를 약 33% 늘리는 이유는?
> **A**: 입력 3 byte(24 bit)를 4글자로 재그룹하는데, 각 글자는 6 bit만 담지만 8-bit byte로 저장되기 때문. 출력/입력 = 4/3 ≈ 1.33배(+padding).

> [!flashcard]
> **Q**: JWT의 payload가 base64url인데 왜 "암호화되지 않았다"고 하는가?
> **A**: base64는 key 없는 가역 인코딩이라 누구나 디코딩해 claim을 읽을 수 있다. JWT의 서명은 *위변조 방지(integrity)* 용이지 *기밀성(confidentiality)* 을 제공하지 않는다.

> [!flashcard]
> **Q**: 입력 끝의 `=`, `==`는 무엇을 의미하는가?
> **A**: 마지막 블록의 입력 byte 부족을 표시하는 padding. `=` 1개 = 마지막 블록 2 byte(16 bit), `==` 2개 = 1 byte(8 bit). 디코더는 `=` 개수만큼 끝 byte를 폐기한다.
