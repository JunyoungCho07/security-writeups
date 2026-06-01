---
date: 2026-06-01
wargame: Bandit
level: 10
title: "Bandit Level 10 → 11"
difficulty: ★☆☆
time_spent: 3min
tags: [bandit, linux, encoding, base64]
status: 🟡 developing
tools_used: [base64]
new_concepts: [Base64_Encoding]
prerequisites: [Level_09]
---

# Bandit Level 10 → 11

## [Phase 1] Executive Summary

- **Goal**: `data.txt`에 담긴 Base64 텍스트를 디코딩해 password 추출
- **Key Skill**: `base64 -d data.txt` — radix-64 텍스트 → 원본 byte 복원
- **Tags**: `[Encoding]`, `[Base64_Encoding]`

[Cognitive Validation]
- **Limit Test**: 입력 byte 수가 3의 배수면 padding 없음; (3k+1)→`==`, (3k+2)→`=` 하나. 입력 길이 → 0이면 출력 0. 즉 padding 개수는 `len mod 3`이 지배.
- **Control Knob**: 지배 변수는 "alphabet 선택"(standard `+/` vs URL-safe `-_`)과 "padding 처리". alphabet이 어긋나면 디코딩이 깨지거나 다른 byte가 나옴.
- **Nullity**: 입력이 순수 Base64 alphabet+padding이 아니면(개행 제외) `base64 -d`는 invalid input 에러 또는 무시 — encoding이 아니라 ciphertext였다면 이 도구로는 불가.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

Encoding(인코딩) — 암호화가 아니라 **표현 변환**. binary를 7-bit-safe ASCII 텍스트로 옮기는 transport 계층 기법. Level 9의 "binary 안의 텍스트 추출"과 짝을 이루는 역방향 개념(텍스트로 위장된 binary).

### 2. Definition (Formal, EN)

Base64 maps every 3 bytes (24 bits) of input to 4 ASCII characters (6 bits each) drawn from a 64-symbol alphabet `[A-Za-z0-9+/]`, padding the final group with `=` to a multiple of 4. It is a **bijective, key-less** encoding: decoding requires no secret, only the alphabet.

### 3. Intuition (KR)

Base64는 "암호"가 아니라 **포장지**다. 누구나 뜯을 수 있다(key 없음). 24비트를 6비트씩 4조각으로 잘라 읽기 좋은 글자에 1:1 대응시킨 것뿐. `-d`는 그 포장을 푸는 동작.

### 4. Theory (Mechanism)

1. 인코더: 입력 byte stream을 24-bit 블록으로 묶고 6-bit씩 4개로 분할 → 각 6-bit 값(0–63)을 alphabet에 매핑.
2. 마지막 블록이 24-bit 미만이면 0-bit으로 채운 뒤 부족분을 `=`로 표시(padding).
3. 디코더(`-d`): 역연산 — 각 글자를 6-bit로 환원, 4글자→3byte 재조립, `=` 개수만큼 끝 byte 폐기.
4. 결과 byte stream이 마침 ASCII 문장(`The password is ...`)이라 그대로 출력됨.

인과: data.txt가 base64 텍스트(조건) → `base64 -d`로 6-bit 역매핑(B) → 원본 byte 복원(C) → 그 byte가 printable ASCII라 password 노출(D).

### 5. Solution

```bash
# SSH connection
$ ssh -p 2220 bandit10@bandit.labs.overthewire.org
# Password: <password masked>

bandit10@bandit:~$ cat data.txt
<Base64 string — e.g. VGhlIHBhc3N3b3JkIGlz...>

bandit10@bandit:~$ base64 -d data.txt
The password is <password masked>
# Next level(bandit11) password: <password masked>
```

> [!warning] Password Masking
> `base64 -d` 출력의 `The password is ...` 줄에 bandit11 password가 평문 노출됨 → 반드시 `<password masked>`로 치환 후 commit. encoding은 암호가 아니므로, 인코딩된 원본 문자열을 commit하는 것도 password를 그대로 올리는 것과 동일 — 디코딩 가능하므로 절대 금지.

### 6. Why It Works

Base64는 key가 없는 reversible encoding이다. 따라서 `data.txt`가 valid Base64이기만 하면 `base64 -d`는 결정론적으로 원본을 복원한다. 이 level의 "보안"은 단지 사람이 눈으로 못 읽게 한 obfuscation에 불과하며, 도구 한 줄로 무력화된다. 이것이 **encoding ≠ encryption**의 실전 증명이다.

### 7. Edge Cases / Limitation

- `data.txt`에 trailing newline이나 줄바꿈이 섞여도 `base64 -d`는 대부분 무시(`-i`로 invalid 문자 ignore 강제 가능).
- alphabet이 URL-safe(`-_`)면 표준 `base64 -d`가 깨질 수 있음 → `tr '_-' '/+'` 선치환 또는 전용 디코더 필요.
- 이중/삼중 인코딩이면 한 번 디코딩 후 결과가 또 Base64일 수 있음 → 반복 디코딩 필요.

---

## [Phase 3] Formal Summary (EN)

> [!definition] Base64 Encoding
> A binary-to-text encoding E: {0,1}* → Σ* where Σ = [A-Za-z0-9+/], mapping each 6-bit group to one symbol, expanding data by a factor of 4/3 (plus padding). E is bijective and key-less; D = E⁻¹ requires only knowledge of Σ.

> [!theorem] Encoding is not encryption
> For any key-less encoding E, possession of the codec suffices to recover plaintext: ∀m, D(E(m)) = m with no secret. Therefore Base64 provides confidentiality = 0; it only changes representation. □

---

## [Phase 4] Better Methods

**Current approach** (used above):
```bash
base64 -d data.txt
```

**Alternative 1**: 명시적 stdin 파이프 (출처가 stdin일 때)
```bash
cat data.txt | base64 --decode
```
Trade-off: 동일 결과. 파일이 아니라 다른 명령의 출력에서 받을 때 유용하나, 파일 대상이면 불필요한 `cat`(UUOC).

**Alternative 2**: 인코딩 종류 불확실 시 정찰 우선
```bash
file data.txt; head -c 80 data.txt; echo
```
Trade-off: 디코딩 전에 자료형/alphabet 확인 → 잘못된 디코더 적용 방지. 한 단계 더 걸리지만 robust.

**Most elegant**:
```bash
base64 -d data.txt
```
Why elegant: 단일 도구·단일 인자. 입력이 표준 Base64임이 자명할 때 가장 직접적.

---

## [Phase 5] Lessons Learned

1. **Encoding ≠ Encryption**: Base64/hex/URL-encoding은 key 없는 변환 — 보안 기능 0, 그저 표현 변경.
2. 알 수 없는 텍스트가 `[A-Za-z0-9+/]`로만 구성되고 길이가 4의 배수면 Base64를 의심하라.
3. 디코딩 결과가 또 인코딩일 수 있다 — 한 번에 안 풀리면 재귀적으로 시도.

### Quiz

**Q**: 어떤 토큰이 `[A-Za-z0-9+/=]`만으로 구성되고 길이가 4의 배수다. 이것이 (a) 단순 Base64 평문 인코딩인지, (b) 암호화 후 Base64로 감싼 ciphertext인지를, **디코딩을 시도하지 않고** 통계적으로 구별할 방법을 설계하라.

> [!tip]- 풀이
> 디코딩한 byte stream의 **Shannon entropy**를 측정한다.
> - 자연어/구조적 평문을 인코딩한 것이면 디코딩 후 엔트로피가 낮고(영어 ≈ 4.0~4.5 bits/byte 이하), printable 비율이 높다.
> - 암호화된 ciphertext를 Base64로 감싼 것이면 디코딩 후 엔트로피가 ≈ 8 bits/byte(균등 분포)에 근접하고 printable 비율이 무작위.
>
> 엄밀히는 "디코딩 안 하고"는 불가능에 가깝다(Base64 자체가 거의 균등해 보임). 현실적 답: 1회 디코딩 후 엔트로피·printable 비율로 판별.
>
> 핵심: encoding은 분포를 보존하지 않게 섞지 않는다 — **decode 후 엔트로피**가 plaintext vs ciphertext의 판별자.

> [!flashcard]
> **Q**: Why does Base64 expand data size by ~33%?
> **A**: It re-groups 3 input bytes (24 bits) into 4 output characters (4 × 6 = 24 bits, but each stored as a full 8-bit ASCII char) → 4/3 ≈ 1.33× size, plus up to 2 padding chars.

---

## Links

### Tools Used
- [[Tools/base64]]

### Concepts Introduced (first encountered here)
- [[Concepts/Linux/Base64_Encoding]]

### Concepts Applied (reused from earlier)
- (none — Base64 디코딩은 Level 9의 strings extraction과 독립적 메커니즘. 억지 링크 배제)

### Navigation
- **Prerequisite**: [[Level_09]]
- **Next**: [[Level_11]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit11.html
- RFC 4648 — The Base16, Base32, and Base64 Data Encodings
- coreutils `base64(1)` man page
