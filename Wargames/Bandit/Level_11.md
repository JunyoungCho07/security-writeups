---
date: 2026-06-01
wargame: Bandit
level: 11
title: "Bandit Level 11 → 12"
difficulty: ★★☆
time_spent: 12min
tags: [bandit, linux, crypto, substitution-cipher, text-processing]
status: 🟡 developing
tools_used: [tr, cat]
new_concepts: [ROT13_Cipher]
prerequisites: [Level_10]
---

# Bandit Level 11 → 12

## [Phase 1] Executive Summary

- **Goal**: `data.txt`의 ROT13-인코딩 텍스트를 복호해 password 추출
- **Key Skill**: `tr 'A-Za-z' 'N-ZA-Mn-za-m'` — 알파벳 13칸 회전 치환
- **Tags**: `[ROT13_Cipher]`, `[Substitution_Cipher]`, `[Text_Processing]`

[Cognitive Validation]
- **Limit Test**: shift k → 0이면 identity(암호화 없음); k → 13이면 ROT13(self-inverse); k → 26이면 다시 identity. k는 mod 26으로 순환.
- **Control Knob**: 지배 변수는 shift 양 k. ROT13은 Caesar cipher의 k=13 특수해 — 26/2=13이라 **암·복호가 동일 연산**(involution).
- **Nullity**: 비알파벳 문자(숫자·공백·기호)는 mapping에 없으므로 **고정점(fixed point)** — 그대로 통과. password의 숫자 `7,1,6,5,9,4`가 안 바뀌는 이유.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

Monoalphabetic substitution cipher — 평문 알파벳을 고정 치환표로 1:1 대응. ROT13은 그중 "shift = 13" 케이스. 암호학적으론 **0의 보안**(key가 공개·고정), 그저 텍스트 난독화. Level 10의 Base64(encoding)와 같은 계열: "보안 아닌 위장".

### 2. Definition (Formal, EN)

For a letter with zero-based alphabet index x ∈ {0,…,25}, ROT13 is the map ρ(x) = (x + 13) mod 26, applied case-preserving and identity on non-letters. Since 13 + 13 = 26 ≡ 0 (mod 26), ρ(ρ(x)) = x — ROT13 is an **involution** (its own inverse). It is the Caesar cipher Cₖ(x) = (x+k) mod 26 at k = 13.

### 3. Intuition (KR)

알파벳을 26칸 원형 시계로 보면 ROT13은 **정확히 반 바퀴(13칸) 돌리기**. 반 바퀴 더 돌리면 제자리 → 같은 도구로 풀린다. 숫자·기호는 시계 밖이라 안 움직인다.

### 4. Theory (Mechanism)

`tr SET1 SET2`는 stdin의 각 문자 c에 대해, c가 SET1의 i번째면 SET2의 i번째로 치환한다(positional 1:1 mapping).

ROT13 매핑 구성:
- 소문자: SET1 `a-z` = `abcdefghijklmnopqrstuvwxyz`, SET2 `n-za-m` = `nopqrstuvwxyzabcdefghijklm`. → a↔n, b↔o, …
- 대문자: SET1 `A-Z`, SET2 `N-ZA-M`. → A↔N, …
- 합치면 한 번에: `tr 'A-Za-z' 'N-ZA-Mn-za-m'`.

인과: data.txt가 ROT13 ciphertext(조건) → tr이 각 글자를 +13 mod 26 치환(B) → involution이라 원문 복원(C) → 평문 password 노출(D).

### 5. Solution

```bash
# SSH connection
$ ssh -p 2220 bandit11@bandit.labs.overthewire.org
# Password: <password masked>

bandit11@bandit:~$ cat data.txt
Gur cnffjbeq vf <ciphertext masked>      # ROT13: "The password is ..."

# 시도 1 — tr에 파일명을 인자로 줌(치명적 오해). tr은 STDIN만 읽는다.
bandit11@bandit:~$ tr data.txt 'a-zA-z' 'n-za-nN-ZA-M'
tr: extra operand 'n-za-nN-ZA-M'
# data.txt가 SET1로, 'a-zA-z'가 SET2로 먹히고 3번째는 잉여 → 에러

# 시도 2 — SET 하나만 준 채 stdin을 직접 타이핑하게 됨(인터랙티브 오작동)
bandit11@bandit:~$ tr data.txt [n-za-nN-ZA-M]
... (사용자 키 입력을 실시간 치환한 잡음 출력) ...

# 시도 3 — 범위 오타 'a-zA-z' : 'A-z'는 ASCII상 Z..a 사이 기호([\]^_`)까지 포함 → 매핑 깨짐
bandit11@bandit:~$ cat data.txt | tr 'a-zA-z' 'n-za-nN-ZA-M'
SMM MMMMMMMM MM ...      # 망가진 출력

# 시도 4 — 소문자만 회전(대문자 미처리) → 부분 복호
bandit11@bandit:~$ cat data.txt | tr 'a-z' 'n-za-mM'
Ghe password is ...     # 'T'(대문자)가 'G' 그대로 → 불완전

# 해법 — 2단계(소문자 회전 → 대문자 회전)
bandit11@bandit:~$ cat data.txt | tr 'a-z' 'n-za-m' | tr 'A-Z' 'N-ZA-M'
The password is <password masked>
# Next level(bandit12) password: <password masked>
```

> [!warning] Password Masking
> 평문 password뿐 아니라 **ROT13 ciphertext(`Gur cnffjbeq...`의 토큰)** 도 마스킹하라. ROT13은 key 없는 involution이라 손으로도 즉시 복호 가능 → ciphertext commit = password commit. Base64 때와 동일 원칙.

### 6. Why It Works

ROT13은 involution(ρ∘ρ = id)이므로 "암호화 도구"와 "복호화 도구"가 같다. tr로 +13 치환을 적용하면 ciphertext의 각 글자가 원래 자리로 돌아온다. 숫자·공백은 SET1에 없어 고정점으로 통과하므로 password 내 숫자가 보존된다. 2단계 파이프는 단지 소·대문자를 나눠 처리한 것이며, `tr 'A-Za-z' 'N-ZA-Mn-za-m'` 한 줄과 동치다.

### 7. Edge Cases / Limitation

- **`tr`은 파일 인자를 받지 않는다** — STDIN 전용. 반드시 `< data.txt` 또는 `cat data.txt |`. (시도 1·2 실패의 근본 원인)
- **`A-z` 범위 함정**: ASCII에서 `Z`(90)와 `a`(97) 사이에 `[ \ ] ^ _ \``(91–96)가 있어 `A-z`는 이 기호들까지 포함 → 의도치 않은 매핑. 대·소문자는 `A-Z`, `a-z`로 분리 지정.
- ROT13은 **알파벳 전용**. 키릴·한글·숫자엔 효과 없음. 일반 Caesar로 확장하려면 shift k를 매개변수화.

---

## [Phase 3] Formal Summary (EN)

> [!definition] ROT13 Cipher
> ROT13 = Caesar cipher C₁₃ over the 26-letter Latin alphabet: ρ(x) = (x + 13) mod 26, case-preserving, identity on non-letters. As an involution (ρ² = id), encryption and decryption coincide. Cryptographic strength = 0: the key is fixed and public.

> [!theorem] ROT13 Self-Inverse
> ∀ letter x: ρ(ρ(x)) = x. Proof: ρ(ρ(x)) = ((x+13 mod 26)+13) mod 26 = (x+26) mod 26 = x mod 26 = x. □ Hence a single `tr 'A-Za-z' 'N-ZA-Mn-za-m'` both encodes and decodes.

---

## [Phase 4] Better Methods

**Current approach** (used above, 2-stage):
```bash
cat data.txt | tr 'a-z' 'n-za-m' | tr 'A-Z' 'N-ZA-M'
```

**Alternative 1**: 단일 tr (가장 정석)
```bash
tr 'A-Za-z' 'N-ZA-Mn-za-m' < data.txt
```
Trade-off: 파이프 1개·프로세스 1개. `< data.txt`로 UUOC(`cat` 남용)도 제거. 가장 깔끔.

**Alternative 2**: 도구 비의존(언어 내장)
```bash
python3 -c "import codecs,sys; print(codecs.decode(open('data.txt').read(),'rot13'),end='')"
```
Trade-off: tr 문법 함정 회피, 가독성↑. 단 인터프리터 기동 오버헤드, one-liner치곤 장황.

**Most elegant**:
```bash
tr 'A-Za-z' 'N-ZA-Mn-za-m' < data.txt
```
Why elegant: 의미가 곧 구조 — "알파벳을 13칸 민다"가 두 SET의 회전 배열로 그대로 드러난다. involution이라 같은 명령이 암·복호 양용.

---

## [Phase 5] Lessons Learned

1. **`tr`은 STDIN만 읽는다** — 파일명을 인자로 주면 SET으로 오인. `< file` 또는 파이프 필수. (이 level 삽질의 90%가 여기서 발생)
2. **`A-z`는 함정**: 대·소문자 경계의 ASCII 기호 6개가 끼어든다. 항상 `A-Z`·`a-z`를 분리.
3. ROT13 = Caesar(k=13) = involution → 같은 도구로 암·복호. encoding/약한 cipher는 보안이 아니라 위장.

### Quiz

**Q**: ROT13은 k=13이라 self-inverse다. 일반 Caesar cipher Cₖ를 `tr` **한 번**으로 복호하려 한다. 임의의 k(0<k<26)에 대해 SET2를 어떻게 구성하며, k=13이 특별한 이유를 군론(group theory) 언어로 설명하라. 또한 `tr`만으로 *임의 k* 복호 스크립트를 작성할 때 본질적 한계는?

> [!tip]- 풀이
> **복호 SET 구성**: 암호화가 Cₖ면 복호는 C₋ₖ = C₍₂₆₋ₖ₎. SET1=`a-z`, SET2 = 알파벳을 왼쪽으로 k칸(=오른쪽 26−k칸) 회전한 문자열. 예 k=3 복호: SET2 = `d-za-c`를 역으로 `x-za-w`… 실무적으론 SET1·SET2를 바꿔 `tr '<enc>' 'a-z'`로 풀거나 SET2를 `chr((i-k)%26)`로 생성.
>
> **군론**: 알파벳 회전은 순환군 ℤ/26ℤ. Cₖ는 원소 k. 복호는 역원 −k. ROT13의 k=13은 **위수 2의 원소**(13+13≡0) → 자기 자신이 역원 ⟺ involution. 26이 짝수라 위수 2 원소가 정확히 13 하나 존재(13은 26의 유일한 비자명 절반).
>
> **한계**: `tr`은 mapping이 **정적**이라 k를 런타임 변수로 못 받는다. 임의 k는 shell이 SET2 문자열을 매번 생성해 넘겨야 함(`tr "a-z" "$(rotated_set $k)"`). 즉 tr 자체는 parametric cipher가 아니라 fixed substitution table 실행기.
>
> 핵심: ROT13의 우아함은 **26 = 2×13**이라는 수론적 우연 — 짝수 알파벳의 절반 회전만이 involution.

> [!flashcard]
> **Q**: Why does `tr data.txt 'a-z' 'n-za-m'` fail, and what's the fix?
> **A**: `tr` reads only STDIN, never a file argument — `data.txt` is misparsed as SET1. Fix: `tr 'a-z' 'n-za-m' < data.txt` or `cat data.txt | tr ...`.

> [!flashcard]
> **Q**: Why is ROT13 its own inverse, but ROT5 (k=5) is not?
> **A**: ROT13 applies +13 twice = +26 ≡ 0 (mod 26) → identity. ROT5 applied twice = +10 ≠ 0 (mod 26); its inverse is ROT21 (k=26−5). Only k=13 is a self-inverse over a 26-letter alphabet.

---

## Links

### Tools Used
- [[Tools/tr]]
- [[Tools/cat]]

### Concepts Introduced (first encountered here)
- [[Concepts/Crypto/ROT13_Cipher]]

### Concepts Applied (reused from earlier)
- (none directly — Base64는 encoding, ROT13은 substitution cipher. 같은 "위장 ≠ 보안" 교훈을 공유하나 메커니즘 독립)

### Navigation
- **Prerequisite**: [[Level_10]]
- **Next**: [[Level_12]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit12.html
- coreutils `tr(1)` man page — SET ranges, classes
- ROT13 / Caesar cipher (substitution cipher family)
