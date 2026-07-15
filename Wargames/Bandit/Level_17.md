---
date: 2026-07-15
wargame: Bandit
level: 17
title: "Bandit Level 17 → 18"
difficulty: ★☆☆
time_spent: 10min
tags: [bandit, linux, text-processing, diff, file-comparison]
status: 🟡 developing
tools_used: [diff, sort, uniq, grep, cat, mktemp]
new_concepts: [File_Diff]
prerequisites: [Level_16]
---

# Bandit Level 17 → 18

## [Phase 1] Executive Summary

- **Goal**: 홈의 `passwords.old` ↔ `passwords.new`에서 **유일하게 바뀐 줄**을 찾아 → `passwords.new` 쪽 값 = bandit18 password
- **Key Skill**: `diff passwords.old passwords.new` — 두 파일의 줄 단위 차이. `>` 줄(둘째 파일=passwords.new)이 정답
- **Tags**: `[File_Diff]`, `[Text_Comparison]`, `[Stream_Deduplication]`

[Cognitive Validation]
- **Limit Test**: 두 파일이 동일하면 `diff` 출력 0(변경 없음); 전부 다르면 모든 줄이 hunk로. 여기선 정확히 **1줄** 차이 → hunk 1개.
- **Control Knob**: 지배 변수는 **"줄을 어떻게 비교하는가"** — `diff`는 순서 있는 line-by-line(편집거리), `sort|uniq`는 순서 무시 집합 연산. 접근 축이 다름.
- **Nullity**: 변경 줄이 0이면 답 없음. 이 문제는 "정확히 1줄만 변경"을 보장 → 반드시 답 존재.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**File comparison / line-level diff**. Level 08의 stream dedup(`sort|uniq`)과 **자매 개념** — 거기선 "한 파일에서 1번만 나온 줄", 여기선 "두 파일 사이에서 바뀐 줄". 둘 다 "줄을 빈도/집합으로 다룬다"는 공통 축 위에 있고, 차이는 **입력이 1개 stream이냐 2개 파일이냐**.

### 2. Definition (Formal, EN)

`diff A B` computes a **minimal edit script** (based on the longest common subsequence) that transforms file A into B, emitting hunks. Each hunk marks lines with `<` (present in A, i.e. removed) and `>` (present in B, i.e. added), prefixed by a `LcL` / `LaL` / `LdL` change command. For files differing in exactly one line, output is a single `NcN` hunk with one `<` (old) and one `>` (new).

### 3. Intuition (KR)

두 명단을 나란히 놓고 "**딱 한 줄만 다른 곳**"을 찾는 것. `diff`는 그 자리를 `< 옛것 / > 새것`으로 짚어준다. `<`는 왼쪽(첫째 파일=old), `>`는 오른쪽(둘째 파일=new) — password는 **new에 새로 생긴 줄**이니 `>`가 답.

### 4. Theory (Mechanism)

두 접근이 가능하고, 이번 세션엔 후자를 씀:

- **`diff A B`** (정도): LCS로 A→B 편집거리를 계산 → 바뀐 줄을 `<`(A)/`>`(B)로 직접 지목. 답이 `>` 한 줄로 바로 나옴.
- **`cat A B | sort | uniq -u`** (사용자 방식): 두 파일을 이어 붙여 **빈도 1인 줄만** 추출. 안 바뀐 줄은 각 파일에 1번씩 = **2회** → `uniq -u`가 제거. 바뀐 위치만 old값(1회) + new값(1회) → **둘 다 유니크** → 2줄 반환. 이후 "둘 중 `passwords.new`에 있는 것"을 `grep`으로 골라야 함.

인과: 두 파일이 1줄 차이(조건) → `diff`는 `>`로 new줄 직접 지목(B), `sort|uniq -u`는 {제거된 old, 추가된 new} 2줄 반환(B') → new줄이 bandit18 password(C).

### 5. Solution

```bash
# bandit17 접속 (Level 16에서 얻은 key로 — 아래 [Phase 4]/재접속 참고)
bandit17@bandit:~$ ls
passwords.new  passwords.old

# --- 삽질: 작업파일 만들려다 home read-only + mktemp 오해 ---
bandit17@bandit:~$ touch plus            # Permission denied — home write-access 차단
bandit17@bandit:~$ mktemp plus           # "too few X's" — mktemp 템플릿엔 XXXXXX 필요
bandit17@bandit:~$ mktemp                 # /tmp/tmp.xxxxx (임시 '파일' 생성)
bandit17@bandit:~$ cd /tmp/tmp.xxxxx      # "Not a directory" — mktemp는 파일, 디렉토리는 mktemp -d

# --- 접근: 두 파일 합쳐 sort | uniq -u (Level 08 기법 재적용) ---
bandit17@bandit:~$ cat passwords.new >> /tmp/tmp.xxxxx
bandit17@bandit:~$ cat passwords.old >> /tmp/tmp.xxxxx
bandit17@bandit:~$ sort /tmp/tmp.xxxxx | uniq -u
<password masked>        # ← passwords.new에만 있는 줄 (= bandit18 password 후보)
<old line masked>        # ← passwords.old에만 있던 줄 (제거된 옛값)
#   uniq -u = '딱 1번' 나온 줄만 → 바뀐 줄의 old/new 둘 다 유니크 → 2줄

# --- disambiguation: 둘 중 passwords.new에 있는 게 정답 ---
bandit17@bandit:~$ grep "<candidate>" passwords.new
<password masked>        # ← passwords.new에 존재 → 이게 bandit18 password
```

> [!warning] Password & File-List Masking
> `passwords.old`/`passwords.new`는 각 ~100줄의 32자 토큰 목록이고 그중 한 줄이 실 password다 → **파일 내용을 노트에 옮기지 않는다**. 정답 줄 + `sort|uniq -u`가 뱉은 나머지 한 줄(제거된 옛값)도 모두 마스킹. 목록 자체가 credential 덩어리라 통째로 배제.

### 6. Why It Works

두 파일이 정확히 1줄 다르므로, 이어 붙이면 **바뀐 위치만 빈도 1**이 된다(나머지는 전부 2회). `uniq -u`가 빈도 1만 남기니 old·new 두 줄이 나오고, 그중 `passwords.new`에 있는 게 새 password. `diff`를 썼다면 `>` 접두 한 줄로 **바로** 나왔을 것 — 둘째 파일(new) 쪽 변경을 diff가 명시하기 때문. 두 방법 모두 "안 바뀐 줄은 상쇄, 바뀐 줄만 남는다"는 동일 원리의 다른 표현.

### 7. Edge Cases / Limitation

- **`mktemp` vs `mktemp -d`**: `mktemp`은 임시 **파일**, `-d`가 임시 **디렉토리**. `cd`가 `Not a directory`면 파일에 cd한 것. (Level 12에서 `mktemp -d`를 썼던 것과 대비.)
- **home read-only**: `touch`/`vi`로 홈에 파일 못 만듦 → `/tmp` 작업공간 필수(반복 확인된 제약).
- **`sort|uniq -u`의 순서 의존성 없음 vs `diff`의 순서 의존성**: 두 파일이 **순서만 뒤바뀐 동일 내용**이면 `diff`는 대량 변경으로 오인하지만 `sort|uniq -u`는 차이 0. "순서가 의미 있나"가 도구 선택 기준.
- **bandit17 재접속**: 이 레벨은 key로 들어왔으나 bandit17 password도 `/etc/bandit_pass/bandit17`에 존재 → 저장하면 다음부턴 password 로그인 가능(아래 질문 답 참조).

---

## [Phase 3] Formal Summary (EN)

> [!definition] Line-level Diff
> `diff A B` emits a minimal LCS-based edit script transforming A→B. Hunks mark `<` lines (in A, removed) and `>` lines (in B, added). One-line difference ⇒ a single `NcN` hunk: one `<` (old), one `>` (new).

> [!theorem] Why `sort | uniq -u` on A∥B yields two lines
> Let A, B be equal-cardinality line sets differing in exactly one position. In the concatenation A∥B, every unchanged line occurs **twice** ⇒ `uniq -u` drops it. The changed position contributes A's old value (×1) and B's new value (×1), both frequency-1 ⇒ both retained. ∴ result = {removed_old, added_new}; the answer is the member also ∈ B (`passwords.new`). □

---

## [Phase 4] Better Methods

**Current approach** (used above): `cat new old >> tmp; sort tmp | uniq -u` → 2줄 → `grep`으로 new쪽 선택. 동작하나 우회적.

**Alternative 1**: `diff` (정도 — 한 방)
```bash
diff passwords.old passwords.new
#   → 예: 42c42
#     < <옛 줄>              # '<' = 첫째 파일(passwords.old), 제거됨
#     > <password masked>    # '>' = 둘째 파일(passwords.new) = 정답
```
Trade-off: 임시파일·정렬·grep 불요. `>` 줄이 바로 답 + 줄번호까지. **두 파일 비교의 표준.**

**Alternative 2**: `diff`에서 새 줄만 뽑기 (스크립트 친화)
```bash
diff passwords.old passwords.new | grep '^>' | cut -c3-
#   grep '^>' : 둘째 파일(new) 쪽 추가 줄만
#   cut -c3-  : 앞의 "> " 2글자 제거 → 순수 password
```
Trade-off: 파이프로 password만 즉시 추출. 자동화·재현 우수.

**Alternative 3**: `comm` (정렬된 두 파일의 집합 비교)
```bash
comm -13 <(sort passwords.old) <(sort passwords.new)
#   comm은 정렬된 두 입력을 3열(A만/B만/공통)로 비교
#   -13 : 1열(A만)·3열(공통) 억제 → 'B에만 있는 줄'만 = 새 password
#   <(sort ...) : process substitution으로 정렬본을 즉석 입력
```
Trade-off: 집합 관점에서 "new에만 있는 줄"을 정확히. 단 정렬 선행 필요.

**Most elegant**:
```bash
diff passwords.old passwords.new | grep '^>' | cut -c3-
```
Why elegant: 비교→선별→정제를 단일 파이프로. `>`가 new쪽임을 알면 disambiguation 자체가 사라진다.

---

## [Phase 5] Lessons Learned

1. **두 파일 비교는 `diff`가 정도**: `>` 줄(둘째 파일=passwords.new)이 바로 새 password. `sort|uniq -u`도 되지만 old+new 2줄이라 `grep` 재확인이 붙는다.
2. **`mktemp`은 파일, `mktemp -d`는 디렉토리**: `cd`가 `Not a directory`면 파일에 cd 시도한 것.
3. **home read-only** → `/tmp` 작업공간(반복 확인).
4. **`diff`(순서 민감, 편집거리) vs `sort|uniq`(순서 무시, 집합)** — 데이터의 순서가 의미 있는지로 도구를 고른다.

### Quiz

**Q**: `passwords.old`/`passwords.new`가 정확히 1줄 다르다. (a) `diff`가 `sort|uniq -u`보다 나은 실용적 이유, (b) `sort|uniq -u`가 2줄을 뱉는 이유를 집합론적으로, (c) 두 파일이 **순서만 뒤섞인 동일 내용(순열)**일 때 각 도구의 결과가 어떻게 갈리는지 설명하라.

> [!tip]- 풀이
> **(a)** `diff`는 `>`로 passwords.new 쪽 변경 줄을 **직접 지목**(disambiguation 불요) + 줄번호 제공.
>
> **(b)** concat 후 안 바뀐 줄은 각 2회 → `uniq -u` 제거; 바뀐 위치는 old값 1회 + new값 1회 → 둘 다 frequency-1 → 둘 다 남음. 결과 = {제거된 old, 추가된 new}.
>
> **(c)** `diff`는 **순서 민감**(LCS/편집거리) → 순열이면 다수 줄이 어긋나 대량 변경으로 오인. `sort|uniq -u`는 **순서 무시**(집합 대칭차) → 순열이어도 내용 같으면 차이 0.
>
> 핵심: `diff` = 순서 있는 편집거리, `sort|uniq` = 순서 없는 집합 대칭차. **데이터의 순서 의미**에 맞춰 골라라.

> [!flashcard]
> **Q**: `passwords.old`/`new`에서 바뀐 줄 하나를 찾는 가장 직접적 명령은?
> **A**: `diff passwords.old passwords.new` → `>` 줄(둘째 파일=passwords.new)이 새 password. `sort|uniq -u`도 가능하나 old+new 2줄 반환 → grep 재확인 필요.

> [!flashcard]
> **Q**: `mktemp`과 `mktemp -d`의 차이는?
> **A**: `mktemp`은 임시 **파일**, `mktemp -d`는 임시 **디렉토리**를 생성. `cd`가 `Not a directory`를 뱉으면 파일에 `cd`한 것 → `-d` 필요.

---

## Links

### Tools Used
- [[Tools/diff]]
- [[Tools/sort]]
- [[Tools/uniq]]
- [[Tools/grep]]
- [[Tools/mktemp]]

### Concepts Introduced (first encountered here)
- [[Concepts/Linux/File_Diff]]

### Concepts Applied (reused from earlier)
- [[Concepts/Linux/Stream_Deduplication]] (Level 08 `sort|uniq` — 여기선 두 파일 대칭차로 재적용)

### Navigation
- **Prerequisite**: [[Level_16]]
- **Next**: [[Level_18]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit18.html
- `diff(1)` — normal/unified format, `<`/`>` markers; `comm(1)`
