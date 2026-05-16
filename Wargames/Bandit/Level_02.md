---
date: 2026-05-16
wargame: Bandit
level: 2
title: "Bandit Level 2 → 3"
difficulty: ★☆☆
time_spent: 5min
tags: [bandit, linux, shell, special-filenames, shell-escaping]
status: 🟢 solid
tools_used: [cat, ls]
new_concepts: [Shell_Quoting, Option_Flag_Collision]
prerequisites: [Level_01]
---

# Bandit Level 2 → 3

## [Phase 1] Executive Summary

- **Goal**: `--spaces in this filename--`이라는 이름의 파일에서 password를 읽는다.
- **Key Skill**: (1) 파일명의 공백을 shell이 word split하지 않도록 quoting, (2) `--`로 시작하는 파일명을 프로그램이 option flag로 오해하지 않도록 path 명시
- **Tags**: `[Shell_Quoting]`, `[Option_Flag_Collision]`, `[Word_Split]`

[Cognitive Validation]
- **Limit Test**: 파일명에 공백만 있고 `--` 없다면 → quoting만으로 해결. 반대로 `--`만 있고 공백 없다면 → `./` prefix 또는 `--` option terminator만으로 해결. 두 문제가 동시 발생하기 때문에 두 기법을 함께 적용해야 한다.
- **Control Knob**: shell의 word splitting(IFS)과 프로그램의 option parsing — 두 레이어 모두가 독립적으로 지배 변수.
- **Nullity**: 파일명이 빈 문자열이면 POSIX가 허용하지 않음. 공백만 있는 파일명은 합법적이나, shell이 분리해 별개 인자로 전달 → 각각 "No such file" 오류.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**Shell Argument Parsing + Program Option Parsing** — 두 레이어의 파싱 충돌. 이 level은 하나가 아닌 두 개의 독립적 문제를 포함하며, 각각의 해결법이 다른 레이어에서 작동한다.

| 문제 | 발생 레이어 | 해결 레이어 |
|---|---|---|
| 공백 → word split | Shell (bash IFS) | Shell (quoting / escaping) |
| `--` → option flag | Program (cat's getopt) | Program (`--` terminator) or Path (`./-`) |

### 2. Definition (Formal, EN)

> [!definition] Shell Word Splitting
> When the shell expands an unquoted token containing **IFS characters** (default: space, tab, newline), it splits the token into multiple **words**, each becoming a separate argument. Quoting (single `'...'` or double `"..."`) or backslash-escaping each IFS character prevents this split.

> [!definition] Option Flag Collision
> POSIX utilities use **leading hyphen** as the syntactic marker for options (`-x` short, `--flag` long). When a filename begins with `-` or `--`, programs attempting to parse it as an option will fail with an "unrecognized option" error. Resolution: supply the argument as a **non-option** either via an explicit path (`./<name>`) or via the option terminator `--`.

### 3. Intuition (KR)

> [!tip] Intuition
> Shell은 공백을 "단어 경계"로 보고, cat은 `--`를 "option 시작"으로 본다. 공백 → 따옴표로 묶어 한 덩어리로 만들고, `--` → `./`로 "이건 경로야"라고 명시. 두 레이어의 오해를 각각 그 레이어에서 교정.

### 4. Theory (Mechanism)

**Shell word splitting (IFS)**:
```bash
# IFS=" \t\n" (default)
cat --spaces in this filename--
# shell splits into: ["cat", "--spaces", "in", "this", "filename--"]
# cat receives 4 separate arguments
```

**`cat "--spaces in this filename--"`의 실패**:
```bash
cat "--spaces in this filename--"
# shell: 따옴표 → word split 방지 → cat이 받는 인자: "--spaces in this filename--" (한 덩어리)
# cat: 인자가 "--"로 시작 → long option 파싱 시도 → "--spaces" 옵션 없음 → 오류
# cat: unrecognized option '--spaces in this filename--'
```

따옴표가 shell 문제(word split)는 해결했지만, cat의 option parsing 문제는 남아있다.

**`cat ./"--spaces in this filename--"`의 성공**:
```bash
cat ./"--spaces in this filename--"
# shell: ./ (literal) + "--spaces in this filename--" (quoted) → 연결 → "./ --spaces in this filename--"
# 정확히는: shell concatenation → "./--spaces in this filename--"
# cat: 인자가 "./"로 시작 → option이 아님 → open("./--spaces in this filename--") → 성공
```

### 5. Solution

```bash
$ ssh -p 2220 bandit2@bandit.labs.overthewire.org
# Password: <password masked>

bandit2@bandit:~$ ls
--spaces in this filename--

# 실패 시도: cat이 option으로 해석
bandit2@bandit:~$ cat "--spaces in this filename--"
cat: unrecognized option '--spaces in this filename--'
Try 'cat --help' for more information.

# 성공: ./ prefix로 path임을 명시 + quoting으로 word split 방지
bandit2@bandit:~$ cat ./"--spaces in this filename--"
<password masked>
```

> [!warning] Password Masking
> 실제 password는 절대 commit하지 마라. `<password masked>`로 치환.

### 6. Why It Works

`cat ./"--spaces in this filename--"`의 성공 메커니즘:

1. Shell parsing: `./` (bare) + `"--spaces in this filename--"` (quoted) → concatenation → `./--spaces in this filename--`
2. cat이 인자 `./--spaces in this filename--` 수신
3. cat의 option parser: `./`로 시작 → `-` 또는 `--`로 시작하지 않음 → option이 아님
4. cat: `open("./--spaces in this filename--", O_RDONLY)` syscall
5. Kernel: 현재 디렉토리에서 `--spaces in this filename--` inode 탐색 → 성공

### 7. Edge Cases / Limitation

- **Tab completion**: shell에서 `cat ` 후 Tab → bash가 자동으로 `cat '--spaces in this filename--'`으로 완성. 실수 없이 처리 가능한 최선의 방법.
- **파일명이 `-` 단독**: Level 01에서 다뤘음. `./`만으로 해결.
- **파일명이 `--` 단독**: `cat --` → option terminator → 이후 인자 없으므로 stdin 대기. `cat ./--`로 해결.
- **newline이 포함된 파일명**: POSIX 허용. `find`로 탐색 후 `-exec` 사용, 또는 `-print0 | xargs -0`.

---

## [Phase 3] Formal Summary (EN)

> [!definition] Two-Layer Filename Disambiguation
> For a file $f$ with name $n$ where $n$ contains IFS characters $\subseteq \{\text{space, tab, newline}\}$ AND $n$ begins with `"--"`:
> $$\text{Resolution} = \text{Quote}(n) \land \text{PathPrefix}(n, \text{"./"})$$
> Quoting resolves the shell-layer word split; path prefix resolves the program-layer option collision. Neither alone is sufficient.

> [!theorem] Sufficiency of `./` + Quoting
> `cat ./"<name>"` is sufficient for any filename $f$ satisfying:
> 1. $f$ contains spaces → quoting prevents word split
> 2. $f$ begins with any sequence of hyphens → `./` prevents option parsing
> 3. $f$ exists in CWD → `open` succeeds

---

## [Phase 4] Better Methods

**Current approach**:
```bash
cat ./"--spaces in this filename--"
```

**Alternative 1**: Option terminator `--`
```bash
cat -- "--spaces in this filename--"
```
`--` 이후 인자는 option으로 파싱되지 않음. 공백은 quoting으로 처리.
Trade-off: `--`의 의미를 알아야 함. `./` 방식보다 덜 직관적이나, 절대경로 인자에서도 작동 (`./ `가 불필요한 경우).

**Alternative 2**: Tab completion (권장 — 실전)
```bash
cat <Tab>  # bash가 '--spaces in this filename--' 자동 완성 + escape 처리
```
가장 실수 없는 방법. 복잡한 파일명은 항상 Tab completion 사용.

**Alternative 3**: Wildcard (파일이 하나뿐일 때)
```bash
cat *
```
CWD에 파일이 하나라면 glob이 해당 파일로 expand됨. 파일이 여러 개면 부적절.

**Most elegant**:
```bash
cat -- "--spaces in this filename--"
```
이유: `--` option terminator는 *이 인자가 option이 아님*을 프로그램에게 명시적으로 선언하는 공식 메커니즘. `./`는 우회적(경로로 만들기)이지만 `--`는 의도를 직접 전달함. POSIX 표준 관용구.

---

## [Phase 5] Lessons Learned

1. **하나의 오류에 하나의 원인을 가정하지 마라**: `cat "--spaces..."` 실패는 공백 때문이 아니라 `--` option collision 때문이었다. 진단을 레이어별로 분리해야 한다.
2. **Shell 레이어와 프로그램 레이어를 항상 분리**: quoting = shell 레이어, `--` 또는 `./` = 프로그램 레이어.
3. **`--` option terminator는 POSIX 표준**: 대부분의 Unix utility가 지원. 파일명이 `-`로 시작하는 모든 경우에 적용 가능한 보편적 해결법.
4. **실전에서는 Tab completion**: 복잡한 파일명을 수동으로 타이핑하는 것 자체가 실수의 근원.

### Quiz

**Q** (Graduate-level): `cat -- "--spaces in this filename--"` 에서 `--`는 어떤 표준에 의해 정의되며, 이 표준을 따르지 않는 프로그램의 예시를 하나 들고, 그 경우 대안적 해결 전략은 무엇인가?

<details>
<summary>풀이</summary>

**표준**: POSIX IEEE Std 1003.1, Guideline 10 — *"The first `--` argument that is not an option-argument should be accepted as a delimiter indicating the end of options. Any following arguments should be treated as operands, even if they begin with the `-` character."*

**따르지 않는 예**: `find` — `find -- -name foo`는 일부 구현에서 비정상 동작. `find`의 경우 `-name`, `-type` 등의 expression이 positional이므로 `--`의 역할이 다름.

**대안 전략**: 
1. `./` prefix → 경로로 만들기 (universally works at syscall level)
2. `find . -name '*pattern*' -print0 | xargs -0 cat` → find로 탐색 후 xargs 파이프라인 (파일명 특수문자 완전 우회)
3. `python3 -c "open('--filename').read()"` → option parsing이 없는 도구 사용

핵심: POSIX Guideline은 권고사항이지 강제가 아님. `./` prefix는 프로그램 구현과 무관하게 OS 레벨에서 작동하므로 더 범용적.

</details>

> [!flashcard]
> **Q**: 파일명 `--foo`를 cat에게 넘길 때 두 가지 해결법과 각각의 작동 레이어는?
> **A**: (1) `cat ./--foo` — 경로 prefix로 프로그램의 option parser를 우회 (프로그램 레이어). (2) `cat -- --foo` — POSIX `--` option terminator로 이후 인자를 비-option으로 선언 (프로그램 레이어). 둘 다 프로그램 레이어에서 작동.

> [!flashcard]
> **Q**: `cat "spaces in name"` (공백 포함, `--` 없음)과 `cat "--foo"` (`--` 있음, 공백 없음)의 실패 원인의 레이어 차이는?
> **A**: 전자는 shell word split 미발생 (quoting 성공), cat 레벨에서 option 문제 없음 → 성공. 후자는 shell word split 없지만 cat이 `--foo`를 long option으로 파싱 → 오류. 전자는 shell 레이어, 후자는 프로그램 레이어 문제.

---

## Links

### Tools Used
- [[Tools/cat]] *(planned)*
- [[Tools/ls]] *(planned)*

### Concepts Introduced (first encountered here)
- [[Concepts/Linux/Shell_Quoting]]
- [[Concepts/Linux/Option_Flag_Collision]]

### Concepts Applied (reused from earlier)
- [[Concepts/Linux/Dashed_Filename]] — `./` prefix 기법 재적용

### Navigation
- **Prerequisite**: [[Level_01]]
- **Next**: [[Level_03]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Level 2 Official: https://overthewire.org/wargames/bandit/bandit3.html
- POSIX Guideline 10 (option terminator): https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap12.html
- Bash word splitting: https://www.gnu.org/software/bash/manual/bash.html#Word-Splitting
