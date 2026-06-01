---
date: 2026-06-01
domain: Linux
topic: Strings_Extraction
tags: [linux, binary, forensics, signal-extraction, encoding]
status: 🟡 developing
mastery: 35
first_encountered: [[Wargames/Bandit/Level_09]]
reapplied_in: []
last_reviewed: 2026-06-01
---

# Strings_Extraction

## Core Idea (1-2 sentences, KR)

Strings extraction = byte stream에서 **길이 N 이상의 printable 문자 연속(run)** 만 건져 올리는 lossy projection. binary라는 잡음 바다에서 사람이 읽을 수 있는 "신호 섬"만 남기는 1차 정찰 primitive.

---

## [Step 1] Concept Categorization

**Signal-extraction primitive over a byte stream.** 구조적 DNA = (predicate filter) × (maximal-run segmentation). predicate = `isprint`, segmentation 단위 = "predicate를 연속 만족하는 최대 구간". 입력은 line-oriented text가 아니라 **무구조 byte sequence**라는 점에서 `grep`/`uniq` 같은 line tool과 층위가 다르다 — strings는 byte→line 경계 자체를 *생성*하는 도구다.

forensic·reverse-engineering 계열의 reconnaissance(정찰) 1단계. `file`(타입 판정) → `strings`(텍스트 정찰) → `xxd`/`objdump`(정밀 분석)의 워크플로 중 2번째.

## [Step 2] Definition

> [!definition] Strings Extraction
> 주어진 byte sequence B = (b₀, b₁, …, b_{m-1}), printable predicate `isprint`, 최소 길이 N에 대해, strings-extraction은 다음 조건을 만족하는 **maximal substring** s = (b_i, …, b_j) ⊆ B의 순서집합을 반환한다: (1) ∀ k ∈ [i, j]: `isprint(b_k)`, (2) |s| = j − i + 1 ≥ N, (3) maximality — b_{i−1} 미존재 또는 ¬`isprint(b_{i−1})`, 그리고 b_{j+1} 미존재 또는 ¬`isprint(b_{j+1})`. 이는 B를 그 printable subspace 위로 사영(projection)하는 **lossy, non-invertible** 연산이다.
^definition

**내 언어로 (KR)**: byte를 쭉 훑으면서 "읽을 수 있는 글자"가 N개 이상 끊김 없이 이어진 토막만 잘라 출력. 중간에 control byte(NUL 등) 하나라도 끼면 거기서 토막이 끊긴다. 원본 byte 분포는 버려지므로 되돌릴 수 없다.

## [Step 3] Intuition

> [!tip] Intuition
> binary = control byte라는 "잡음 바다" 위에 printable 글자라는 "섬"이 흩어진 지형. strings는 일정 크기(N) 이상의 섬만 건지는 **그물**이다. 잔모래(길이 < N)는 그물코로 빠진다.
^intuition

## [Step 4] Theory

**유한 상태 기계(FSM)로서의 strings**:

```
        non-print          print
   ┌──────────────┐   ┌──────────────┐
   ▼              │   ▼              │
[OUTSIDE] ──print──▶ [INSIDE(len++)] ─┘
   ▲                      │
   │   non-print/EOF      │  buf 길이 ≥ N?
   └──────────────────────┤   ├─ yes ▶ flush(buf)
                          └───┴─ no  ▶ discard(buf)
```

1. 상태는 OUTSIDE / INSIDE 두 개. 현재 run 버퍼 `buf` 유지.
2. printable byte → INSIDE, `buf`에 append.
3. non-printable byte 또는 EOF → run 종료: `|buf| ≥ N`이면 flush(출력), 아니면 폐기. OUTSIDE 복귀.
4. 시간 O(m), 공간 O(maxrunlen). single pass, streaming 가능.

**왜 grep이 binary에서 실패하는가 (인과 사슬)**: B에 NUL 등 ¬printable byte 존재 → GNU grep이 B를 binary로 분류 → 기본 정책상 매칭 줄 출력 억제("binary file matches") → 사용자에게 정보 0. strings는 이 사슬을 끊는다: B를 printable run의 **line stream**으로 변환 → 이제 grep이 정상 line tool로 동작.

## [Step 5] When & Condition

성립 조건:
- 찾는 정보가 **printable ASCII run**으로 binary 안에 평문 저장되어 있을 것 (version string, error message, URL, embedded credential, format marker 등).
- run 길이 ≥ N (기본 4). 짧은 토큰은 `-n` 하향 필요.
- single-byte encoding(ASCII/Latin-1)이 기본; multibyte는 `-e` 지정.

적용 시점: 알 수 없는 binary·firmware·core dump·packet capture·malware sample의 1차 정찰. CTF에서 "파일을 줬는데 뭔지 모를 때" 반사적으로 첫 타.

## [Step 6] Limitation & Alternatives

### 한계
- **짧은 토큰 누락**: 기본 N=4. 길이 3 이하 의미 토큰은 안 보임 → `-n 1`로 내리면 noise 폭증(recall↑ precision↓).
- **암호화·압축 데이터엔 무력**: ciphertext/compressed byte는 거의 균등 분포라 길이 N의 printable run이 우연히만 생김 → 의미 있는 평문 추출 불가. (encoding ≠ encryption의 반대편: 암호화는 strings를 무력화)
- **난독화된 stack string**: 컴파일러가 문자열을 byte 단위로 쪼개 런타임에 조립하면 정적 strings로 안 잡힘.
- **잘못된 encoding 가정**: UTF-16 문자열은 글자 사이 NUL 때문에 run이 끊겨 단일 글자로 파편화 → `-e l`/`-e b` 필요.

### 우월한 대안
- **`grep -a` / `--text`**: 외부 도구 없이 grep이 binary를 text로 강제 처리. 단 control byte가 그대로 출력돼 터미널 오염.
- **FLOSS** (FireEye Labs Obfuscated String Solver): 정적 strings + emulation으로 stack/obfuscated/encoded string까지 복원. 일반 strings의 상위호환(악성코드 분석용).
- **`rabin2 -z`** (radare2): binary의 data section만 타겟해 strings 추출 → false positive 감소.

## [Step 7] Duality & Null Space

**Dual #1 — `xxd`/hexdump**: strings의 정확한 반대. xxd는 **모든** byte를 무손실 출력(저신호·고잡음), strings는 printable run만(고신호·정보손실). 둘은 lossless↔lossy projection의 쌍. Level 9 터미널에서 `xxd | grep '='`가 수십 줄 잡음을 낸 것 vs `strings | grep '='`가 깔끔했던 것이 이 duality의 실증.

**Dual #2 — Base64/encoding**: strings는 "binary 속 텍스트를 *발견*", encoding은 "binary를 텍스트로 *위장*". `[[Concepts/Linux/Base64_Encoding]]`은 strings가 잡아낼 printable run을 *인위적으로 생성*하는 역연산적 행위. (Confer: Step 12)

**Null space**: ¬printable byte로만 구성된 입력, 또는 모든 printable run이 길이 < N인 입력 → 출력 = ∅. 또한 projection이 lossy하므로 **kernel(역상)**: 동일 strings 출력을 내는 binary는 무한히 많다 → strings 출력만으로 원본 byte 복원 불가(non-invertible).

## [Step 8] Validation

- **Limit Test**: N → 1이면 printable byte 하나하나가 run으로 출력 → 잡음 폭증, 신호 매몰. N → ∞면 어떤 run도 임계 미달 → 출력 ∅. 즉 N은 recall↔precision을 가르는 SNR 노브.
- **Dimensional Check**: 입력 차원 = m bytes. 출력 차원 ≤ m (projection은 절대 데이터를 늘리지 않음). printable 비율 p에 대해 기대 출력량 ≈ O(p·m), N이 클수록 추가 감쇠.
- **Control Knob**: ① N (`-n`) = 길이 임계, ② predicate(encoding `-e`) = 무엇을 "printable"로 볼지, ③ scan 범위(`-a` 전체 vs section 한정). 이 셋이 추출 결과를 완전 규정.

## [Step 9] Advanced Perspective

strings의 본질은 **"weak classifier(`isprint`)로 신호를 거르는 1-bit filter"**. precision을 길이가 아닌 *내용*으로 높이려면:
- **엔트로피 필터**: run의 Shannon entropy로 무작위 문자열(키·해시) vs 자연어 분리.
- **언어모델 스코어링**: n-gram/LM perplexity로 "사람이 의도한 문자열"만 랭킹 (FLOSS, capa의 접근).
- **알파벳 제약**: base64/hex/UUID 같은 도메인 정규식으로 후보 토큰만 추출(Level 9 elegant 해법의 `grep -oP '={2,}\K\S+'`가 이 축소판).

이는 strings를 "maximal-run extraction with a *learnable* predicate"로 일반화하는 방향 — predicate가 고정 `isprint`에서 학습된 분류기로 진화.

## [Step 10] Link to Upper Concepts

- **Information theory / signal extraction**: strings = 잡음 채널에서 신호를 추출하는 matched filter의 가장 원시적 형태. printable=신호, control=잡음이라는 prior. (External: JY_KAIST/02_Concepts/Math/Entropy, Information_Theory)
- **Projection / lossy compression**: byte space → printable subspace 사영. non-invertible map의 전형.
- **Lexical analysis**: 컴파일러의 tokenizer가 문자 stream을 token으로 분절하는 것과 동형 — strings는 "printable run"이라는 단일 token class만 인식하는 degenerate lexer.

## [Step 11] Generalization

predicate를 일반화하면 strings는 **"predicate P를 연속 만족하는 길이 ≥ N의 maximal run 추출기"**의 특수해:

| 차원 | Predicate P | 결과물 | 대표 도구 |
|---|---|---|---|
| 1 | `isprint` | 텍스트 섬 | `strings` |
| 2 | `isascii ∧ isprint`, run≥N | ASCII만 | `strings -a` |
| 3 | 정규식 매칭 token | 구조화 토큰(URL/IP) | `grep -oP` |
| 4 | 학습된 분류기(LM score > τ) | "의미 있는" 문자열 | FLOSS, capa |
| 5 | 임의 feature predicate | 신호 구간 | 일반 signal segmentation |

Pattern: **(noisy stream) → (predicate filter) → (maximal-run segmentation) → (length threshold)**. 모든 "잡음 속 신호 토막 찾기"가 같은 골격.

## [Step 12] Confer (Comparison)

- **vs. `xxd`/hexdump**: 무손실(전 byte) vs 손실(printable run). 정밀 분석 vs 빠른 정찰. (Step 7 Dual #1)
- **vs. `grep -a`**: 동일 목적(binary에서 텍스트 보기)의 다른 경로. `grep -a`는 매칭 줄을 control byte째 출력, strings는 미리 정제 후 깨끗한 line 공급. strings + grep 파이프가 가독성 우위.
- **vs. `[[Concepts/Linux/Base64_Encoding]]`**: 발견 vs 위장. strings는 평문 run을 *읽고*, base64는 binary를 printable run으로 *바꾼다*. 이중 인코딩된 secret은 strings로 보이지만 의미 없음 → 추가 디코딩 필요.
- **vs. `file`**: `file`은 magic number로 **타입 1개** 판정(메타), strings는 **내용** 추출(데이터). 정찰 순서상 file → strings.

## [Step 13] Implication

1. **평문 secret을 binary에 넣어도 보안 0**: API key·password·hidden flag를 실행파일에 박으면 strings 한 줄로 노출. → secret은 코드/바이너리에 하드코딩 금지(secret management의 근거).
2. **악성코드 분석의 진입점**: C2 도메인, 뮤텍스 이름, 에러 메시지가 strings로 새어나와 IOC(indicator of compromise) 추출.
3. **반대로, 방어자 관점**: 의미 있는 strings를 줄이려 문자열 암호화·stack string·packing을 씀 → strings 출력의 빈약함 자체가 "난독화됨"의 신호.
4. **CTF 첫 수**: 출처 불명 파일의 80%는 strings에서 단서(flag 조각, 힌트, 포맷)가 나온다.

## [Step 14] Application

**보안**:
- 펌웨어 덤프에서 하드코딩 telnet 비번·부트 인자 추출.
- malware의 C2 URL/IP, registry key, 뮤텍스명 IOC 수집: `strings sample.bin | grep -Ei 'http|\.exe|HKEY'`.
- core dump에서 메모리 잔류 평문 secret 스캔(post-exploitation/forensics).

**일반**:
- 알 수 없는 파일 타입 정찰: `file x; strings x | head`.
- 컴파일된 바이너리의 빌드 정보·버전·컴파일러 흔적 확인: `strings -n 8 a.out | grep -i gcc`.

**Bandit 맥락 (Level 9)**: `strings data.txt | grep '='` — binary `data.txt`를 printable run으로 정제 후 `=` marker로 password run 선별. grep 단독이 "binary file matches"로 막힌 지점을 strings가 우회.

## [Step 15] Background Knowledge

- **`strings(1)`의 기원**: AT&T Unix에서 object/executable에 박힌 식별 문자열(버전·copyright)을 보려고 등장. 현재는 GNU **binutils**(`libbfd` 기반)와 BSD 양 계열 구현이 공존 — 그래서 기본 동작(특히 `-a` 없이 어느 section을 스캔하는지)이 플랫폼마다 미묘하게 다르다.
- **`isprint`의 로캘 의존**: C 표준 `isprint`는 locale에 따라 printable 집합이 달라질 수 있음. GNU strings는 이식성을 위해 자체 ASCII 판정을 주로 사용.
- **FLOSS (2016, FireEye/Mandiant)**: 단순 strings가 못 잡는 난독화·스택·인코딩 문자열을 코드 에뮬레이션으로 복원하는 오픈소스. "strings의 지능형 후계자"로 악성코드 분석 표준 도구화.
- **정보이론적 뿌리**: "잡음 속 의미 신호 분리"는 Shannon(1948) 이래 통신/압축의 중심 문제. strings는 그 가장 소박한 휴리스틱(printable=신호) 구현체.

---

## Formal Summary (EN)

> [!theorem] Strings Extraction as Lossy Projection
> Let Σ_print ⊆ {0,…,255} be the printable byte set and π_N: B ↦ {maximal runs s ⊆ B : symbols(s) ⊆ Σ_print ∧ |s| ≥ N}. Then π_N is (1) idempotent on its image up to run-boundary insertion, (2) **non-invertible**: |π_N⁻¹(y)| = ∞ for any nonempty output y, since arbitrary non-printable bytes may be interleaved between runs without changing the output. Hence π_N discards information; the original B is unrecoverable from π_N(B).

> [!proof] Sketch
> (Non-invertibility) Take output y = (s₁, …, s_k). Construct B' = c·s₁·c·s₂·…·c·s_k·c for any non-printable filler c. Every such B' yields π_N(B') = y (fillers break runs but are themselves non-printable, hence dropped; each s_i has |s_i| ≥ N so survives). The choice of c and its multiplicities is unbounded ⟹ infinitely many preimages ⟹ π_N not injective ⟹ no inverse. ∎

---

## Cross-References

### Encountered In
- [[Wargames/Bandit/Level_09]] ← first (binary `data.txt`, `strings | grep '='`)

### Tools That Implement This
- [[Tools/strings]] — primary implementation (binutils)
- [[Tools/grep]] — `-a` forces text mode; downstream filter on strings output
- [[Tools/xxd]] — dual (lossless hexdump)

### Related Concepts
- [[Concepts/Linux/Base64_Encoding]] (Confer — 위장 vs 발견의 dual)
- [[Concepts/Linux/Regex_Flavors]] (Related — strings 출력에 grep/PCRE 필터 적용)

### Cross-Domain
- External: JY_KAIST/02_Concepts/Math/Information_Theory (signal vs noise, entropy)
- External: JY_KAIST/02_Concepts/CS/Lexical_Analysis (tokenizer as generalized run-extractor)

---

## Quiz

**Q1** (Graduate-level): 어떤 64 KB 파일을 `strings -n 4`로 돌렸더니 출력이 거의 없다(printable run 몇 개 안 됨). 반면 `strings -n 1`로는 균등하게 흩뿌려진 단문자/이중문자 run이 잔뜩 나온다. 이 파일의 정체에 대한 가설 두 개를 세우고, **추가 디코딩 없이** 가설을 검증/기각할 정량 지표를 각각 제시하라.

> [!tip]- 풀이
> **가설 A — 암호화/압축 데이터**: byte가 거의 균등 분포 → 길이 ≥4 printable run이 확률적으로 희소(P(연속 4 printable) ≈ (95/256)⁴ ≈ 1.9%). 검증: 전체 byte의 **Shannon entropy 측정** → ≈ 8 bits/byte면 암호화/압축 강력 시사.
>
> **가설 B — 특정 binary 구조(코드 섹션 위주)**: 명령어 opcode가 printable 영역(0x20–0x7E)과 겹치지만 4개 연속은 드묾. 검증: **byte 히스토그램** → opcode·주소 패턴으로 특정 값(0x00, 0xFF, 특정 prefix)에 **편중**이 보이면 코드/구조 데이터, 균등하면 가설 A 쪽.
>
> 판별자: entropy ≈ 8 + 균등 히스토그램 ⟹ 암호화/압축. entropy < 8 + 편중 ⟹ 구조적 binary.
>
> 핵심: strings 출력의 빈약함은 **byte 분포의 균등성**을 간접 측정한다 — printable run 희소성 = 고엔트로피의 약한 추정량.

---

> [!flashcard]
> **Q**: `cat binary | grep 'foo'`가 "binary file matches"만 출력하는 이유와, strings가 이를 해결하는 메커니즘은?
> **A**: grep이 입력 stream에서 non-printable byte를 보고 binary로 분류해 매칭 줄을 억제하기 때문. `strings`는 입력을 printable run의 line stream으로 사영해 grep을 정상 line tool로 동작시킨다 (또는 `grep -a`로 text 모드 강제).

> [!flashcard]
> **Q**: strings의 기본 최소 길이 N은? N을 낮출 때의 trade-off는?
> **A**: 기본 N=4. 낮추면 짧은 의미 토큰을 잡을 recall은 오르지만 무의미한 printable run(noise)이 폭증해 precision이 급락한다. precision은 길이 대신 엔트로피·알파벳 제약으로 회복한다.

> [!flashcard]
> **Q**: strings는 왜 non-invertible(역연산 불가)인가?
> **A**: byte stream을 printable subspace로 사영하며 non-printable byte와 그 배치 정보를 폐기하기 때문. 동일 출력을 내는 원본 binary가 무한히 많아 역상이 유일하지 않다.
