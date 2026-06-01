---
date: 2026-06-01
wargame: Bandit
level: 9
title: "Bandit Level 9 → 10"
difficulty: ★☆☆
time_spent: 8min
tags: [bandit, linux, text-processing, binary-inspection]
status: 🟡 developing
tools_used: [strings, grep, xxd]
new_concepts: [Strings_Extraction]
prerequisites: [Level_08]
---

# Bandit Level 9 → 10

## [Phase 1] Executive Summary

- **Goal**: binary `data.txt`에서 여러 개의 `=`가 앞에 붙은 human-readable string 하나를 추출
- **Key Skill**: `strings data.txt | grep '='` — printable run 추출 후 marker 필터
- **Tags**: `[Binary_Inspection]`, `[Strings_Extraction]`, `[Text_Processing]`

[Cognitive Validation]
- **Limit Test**: `strings`의 최소 길이 `-n` → 1로 보내면 한두 글자 noise가 폭증해 신호가 묻힘; ∞로 보내면 진짜 password 줄까지 잘려 출력 0. 즉 `-n`은 SNR(signal-to-noise) 노브.
- **Control Knob**: 지배 변수는 "printable 판정 기준"(기본 ASCII 32–126) × "최소 run length 4". 이 둘이 무엇을 string으로 볼지 결정.
- **Nullity**: 파일에 길이 ≥4의 printable run이 하나도 없으면 `strings`는 빈 출력 → grep도 공집합. binary가 전부 control byte면 이 level은 풀리지 않음(주어진 조건상 불가).

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

Binary inspection — 비텍스트 파일에서 의미 있는 printable sequence를 분리해 내는 forensic primitive. Level 8의 "text stream 처리"에서 한 단계 내려가, 입력이 더 이상 line-oriented text가 아닌 **byte stream**임을 인지하는 것이 핵심 전환.

### 2. Definition (Formal, EN)

`strings` scans a binary for **maximal runs of printable characters** of length ≥ N (default N=4) and emits each run as a line. Formally: given byte sequence B, `strings` outputs every maximal substring s ⊆ B such that ∀ b ∈ s, `isprint(b)` ∧ |s| ≥ N, terminated at the first non-printable byte.

### 3. Intuition (KR)

binary는 대부분 "사람이 못 읽는 잡음(control byte)" 사이사이에 "읽을 수 있는 글자 섬"이 박혀 있는 구조다. `strings`는 그 **섬만 건져 올리는 그물**이다. password는 `=` 여러 개로 둘러싸인 섬 하나 → 그물질 후 `=`로 한 번 더 거른다.

### 4. Theory (Mechanism)

1. `strings`는 byte를 순차 스캔하며 printable(기본 0x20–0x7E) 여부를 판정.
2. printable이 연속 N(=4)회 이상이면 하나의 run으로 확정, 다음 non-printable byte에서 종료·flush.
3. 출력은 line 단위 텍스트 stream → 이제 `grep '='`로 marker 필터 가능.
4. password는 `========== <password>` 형태로 저장 → `=`가 run 안에 포함되므로 grep 매칭됨.

핵심 인과: `data.txt`는 binary → `grep`이 직접 보면 NUL 등 control byte 때문에 "binary file matches"로 매칭 줄을 숨김(B → C) → `strings`로 printable run만 text化하면(조건 D) grep이 정상 출력(유발).

### 5. Solution

```bash
# SSH connection
$ ssh -p 2220 bandit9@bandit.labs.overthewire.org
# Password: <password masked>

# 시도 1 — 오타: 'grep' 와 '=' 사이 공백 누락 → grep= 라는 명령으로 해석됨
bandit9@bandit:~$ more file | grep'='
more: cannot open file: No such file or directory
Command 'grep=' not found

# 시도 2 — 파일명 오류(file ≠ data.txt)
bandit9@bandit:~$ more file | grep '='
more: cannot open file: No such file or directory

# 시도 3 — 올바른 파일이지만 binary라 grep이 매칭 줄을 숨김
bandit9@bandit:~$ more data.txt | grep '='
grep: (standard input): binary file matches

# 시도 4 — xxd hex dump: '=' 매칭은 되나 노이즈 과다, password 식별 곤란
bandit9@bandit:~$ xxd data.txt | grep '='
... (수십 줄의 hex, 신호 대 잡음 비 최악) ...

# 해법 — strings로 printable run 추출 후 '=' 필터
bandit9@bandit:~$ strings data.txt | grep '='
,U=\[
========== the
...
========== password
========== is
========== <password masked>
# Next level(bandit10) password: <password masked>
```

> [!warning] Password Masking
> 실제 password는 절대 commit하지 마라. 위 `strings` 출력의 `========== FGUW...` 줄에서 password가 그대로 노출됨 → 반드시 `<password masked>`로 치환. 이 PUBLIC repo에 raw 값이 들어가면 OverTheWire ToS 위반 + spoiler 누설.

### 6. Why It Works

`grep`은 입력에 NUL 등 non-text byte가 있으면 기본적으로 binary로 판정하고, 보안·가독성상 매칭 줄 전체를 출력하지 않고 "binary file matches"만 보고한다(`grep -a`로 강제 출력 가능). 따라서 `more data.txt | grep '='`은 stdin이 여전히 binary이므로 실패. `strings`는 binary를 printable run의 **텍스트 stream**으로 변환하므로, 이후 grep은 정상적인 line 기반 매칭을 수행한다. `=` marker는 password run 내부에 포함되어 있어 grep 필터로 정확히 선별된다.

### 7. Edge Cases / Limitation

- `more | grep '='`이 실패한 본질은 `more`가 아니라 **grep의 binary 판정**이다. `grep -a '=' data.txt` 한 줄로도 동작하지만, 출력에 control byte가 섞여 터미널이 깨질 수 있다.
- `strings` 기본 인코딩은 single-byte(ASCII). UTF-16/multibyte로 인코딩된 문자열은 `-e l`/`-e b` 등으로 인코딩을 지정해야 잡힌다.
- 기본 `-n 4` 때문에 길이 3 이하의 의미 있는 토큰은 누락된다 — 짧은 flag를 찾을 땐 `-n 1`로 낮춰야 한다(noise 급증 trade-off).

---

## [Phase 3] Formal Summary (EN)

> [!definition] Strings Extraction
> Given a byte stream B and minimum length N, strings-extraction returns the ordered set of maximal substrings s ⊆ B with ∀b∈s: isprint(b) and |s| ≥ N. It is a lossy projection of B onto its human-readable subspace, discarding all control/non-printable bytes.

> [!theorem] Why grep alone fails on binary
> If a file F contains any byte b with ¬isprint(b) (notably NUL), GNU grep classifies F as binary and, by default, suppresses per-line output, emitting only "binary file matches". Hence text-matching on F requires either forcing text mode (`grep -a`) or first projecting F to printable runs (`strings`). □

---

## [Phase 4] Better Methods

**Current approach** (used above):
```bash
strings data.txt | grep '='
```

**Alternative 1**: grep을 binary에 강제 적용 (`-a` = treat as text)
```bash
grep -a '=' data.txt
```
Trade-off: 외부 도구 없이 한 줄. 단, control byte가 그대로 출력돼 터미널 깨짐 위험, password 줄 식별이 strings보다 지저분.

**Alternative 2**: marker가 여러 `=`임을 활용해 정확도 상향
```bash
strings data.txt | grep '======'
```
Trade-off: 우연히 한두 개 `=`를 포함한 noise run을 배제 → password 후보를 더 좁힘. 일반화엔 marker 길이 가정이 들어감.

**Most elegant**:
```bash
strings data.txt | grep -oP '={2,}\s*\K\S+'
```
Why elegant: `=` 접두부를 lookbehind(`\K`)로 버리고 password 토큰만 추출 → 사람이 출력을 눈으로 스캔할 필요 제거. 단 GNU grep `-P`(PCRE) 의존.

---

## [Phase 5] Lessons Learned

1. `grep`이 "binary file matches"를 뱉으면 입력이 binary라는 신호 — `strings`로 텍스트化하거나 `grep -a`로 강제하라.
2. `strings`는 forensic·CTF의 1차 정찰 도구: 알 수 없는 파일을 만나면 `file` → `strings` → `xxd` 순으로 본다.
3. 도구 선택 전에 **입력의 자료형(text vs binary)** 을 먼저 판별하는 습관이 시간을 절약한다 (시도 1–4의 삽질은 이 판별을 건너뛴 결과).

### Quiz

**Q**: `strings`는 기본 length threshold N=4를 쓴다. 어떤 binary에 길이 3짜리 의미 있는 토큰(예: 짧은 key 조각)이 있을 때 단순히 `-n 1`로 낮추면 false positive(무의미한 printable run)가 폭증한다. N을 낮추지 않고도 "짧지만 의미 있는" run을 선별할 통계적/구조적 기준 두 가지를 제시하고, 각각의 실패 모드를 논하라.

> [!tip]- 풀이
> **(a) 엔트로피 필터**: 추출된 run의 Shannon entropy가 임계값 이상인 것만 남긴다. 무작위·고엔트로피 run(key, hash)을 선별. 실패 모드: 자연어 단어는 엔트로피가 낮아 함께 탈락.
>
> **(b) 문자 클래스/정규식 제약**: `[A-Za-z0-9+/=]{3,}` 같이 base64 alphabet 등 도메인 사전지식으로 제약. 실패 모드: 인코딩 가정이 틀리면 진짜 토큰을 놓침(예: 토큰이 hex가 아닌데 hex로 가정).
>
> 핵심: N을 낮추는 것은 recall↑·precision↓. precision은 길이가 아니라 **run의 내용적 특성**(엔트로피·alphabet)으로 회복한다.

> [!flashcard]
> **Q**: Why does `cat`/`more` piped into `grep` still report "binary file matches" on a binary file?
> **A**: grep inspects its **input stream** for non-printable bytes regardless of source; the upstream `cat`/`more` passes the raw bytes through unchanged, so grep still sees NUL/control bytes and defaults to suppressing matched lines.

---

## Links

### Tools Used
- [[Tools/strings]]
- [[Tools/grep]]
- [[Tools/xxd]]

### Concepts Introduced (first encountered here)
- [[Concepts/Linux/Strings_Extraction]]

### Concepts Applied (reused from earlier)
- [[Concepts/Linux/Pipe_Composition]]

### Navigation
- **Prerequisite**: [[Level_08]]
- **Next**: [[Level_10]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit10.html
- GNU grep manual — binary file handling (`--binary-files`, `-a`)
- binutils `strings(1)` man page
