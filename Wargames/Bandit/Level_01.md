---
date: 2026-05-16
wargame: Bandit
level: 1
title: "Bandit Level 1 → 2"
difficulty: ★☆☆
time_spent: 15min
tags: [bandit, linux, shell, special-filenames]
status: 🟢 solid
tools_used: [cat, ls]
new_concepts: [Dashed_Filename]
prerequisites: [Level_00]
---

# Bandit Level 1 → 2

## [Phase 1] Executive Summary

- **Goal**: 홈 디렉토리에 있는 `-`라는 이름의 파일에서 password를 읽는다.
- **Key Skill**: dash(`-`)가 파일명일 때 shell/프로그램이 stdin으로 오해하는 문제를 우회하는 path 명시법
- **Tags**: `[Dashed_Filename]`, `[Shell_Argument_Parsing]`, `[File_Path]`

[Cognitive Validation]
- **Limit Test**: 파일명이 완전히 숫자라면(`123`) → 아무 문제없이 `cat 123`으로 읽힘. 문제는 `-`가 *convention*으로 stdin을 의미하기 때문. 즉 파일 *내용*이 아닌 파일 *이름*이 지배 변수.
- **Control Knob**: path의 specificity. bare `-` → 프로그램이 convention 적용. `./` prefix → OS에게 "현재 디렉토리의 literal 파일 이름"으로 명확히 전달.
- **Nullity**: 파일명이 빈 문자열(`""`) → OS 자체가 허용하지 않음 (POSIX). 특수 케이스.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**Special Filename Handling** — 파일 시스템은 `-`를 완전히 합법적인 파일명으로 처리하지만, Unix convention에 따라 프로그램들은 `-`를 stdin/stdout 약어로 해석한다. 이 level의 본질: *파일 시스템의 네임스페이스*와 *프로그램의 argument convention* 사이의 충돌 해소.

### 2. Definition (Formal, EN)

> [!definition] Dashed Filename Problem
> A **dashed filename** (`-`) is a regular file whose name is the single character U+002D (HYPHEN-MINUS). POSIX requires filesystems to support it as a valid path component. However, by POSIX convention (and IEEE Std 1003.1), many utilities interpret a bare `-` argument as a request to read from `stdin` (fd 0) or write to `stdout` (fd 1), rather than opening a file named `-`. The disambiguation technique is to supply an **explicit path** containing at least one directory component, e.g., `./-`, which forces the OS to perform a `open(2)` call on the literal path.

**내 언어로 (KR)**: 파일 이름 `-`는 완전히 합법. 하지만 `cat`에게 `-`를 넘기면 cat은 "stdin에서 읽어라"로 해석. `./`를 붙이면 cat이 아닌 OS가 경로 해석 → literal 파일로 처리됨.

### 3. Intuition (KR)

> [!tip] Intuition
> `cat -`는 "stdin을 cat해라" / `cat ./-`는 "현재 디렉토리의 `-`라는 파일을 cat해라". `-`는 프로그램 수준의 convention, `./`는 OS 수준의 경로 — 레이어가 다르다.

### 4. Theory (Mechanism)

**왜 shell quoting이 통하지 않는가?**

```
cat '-'    →  shell은 따옴표 제거 후 cat에게 인자 '-' 전달
cat "-"    →  동일
cat \-     →  shell escape는 special chars 용 (backslash before non-special = noop in bash)
```

Shell은 `-`를 special character로 간주하지 않는다 (특수문자: `! " # $ & ' ( ) * + , ; < = > ? @ [ \ ] ^ ` { | } ~`). 따라서 quoting/escaping이 아무 효과가 없다. `-`를 stdin으로 해석하는 것은 **shell이 아닌 cat 자신**이다.

**cat의 내부 동작 (GNU coreutils 소스 기반)**:
```
for each argument:
    if argument == "-":
        fd = STDIN_FILENO  ← convention
    else:
        fd = open(argument, O_RDONLY)  ← file
```

**`./` prefix의 작동 원리**:
- `./- ` → shell이 cat에게 literal 문자열 `./-` 전달
- cat: `./- ` ≠ `-` → `open("./-", O_RDONLY)` 호출
- OS: `openat(CWD, "./-")` → 현재 디렉토리에서 `-`라는 이름의 파일 → 정상 open

### 5. Solution

```bash
$ ssh -p 2220 bandit1@bandit.labs.overthewire.org
# Password: <password masked>

bandit1@bandit:~$ ls
-

# 시도 1: 실패 케이스들
bandit1@bandit:~$ cat -
^C                          # stdin 대기 → Ctrl+C로 종료
bandit1@bandit:~$ cat '-'
^C                          # quoting 무효 — shell 문제가 아니라 cat 문제
bandit1@bandit:~$ cat "-"
^C
bandit1@bandit:~$ cat \-
^C                          # backslash escape도 무효

# 시도 2: 올바른 해결
bandit1@bandit:~$ cat ./-
<password masked>
```

> [!warning] Password Masking
> 실제 password는 절대 commit하지 마라. `<password masked>`로 치환.

### 6. Why It Works

`cat ./-`의 성공 이유:
1. Shell은 `./-`를 그대로 cat에 전달 (shell special char 없음)
2. cat: 인자가 `"-"` literal과 다름 → stdin convention 미적용
3. cat: `open("./-", O_RDONLY)` syscall 실행
4. Kernel: `.` = CWD, `/` = separator, `-` = 파일명 → inode lookup 성공
5. cat이 파일 내용을 stdout으로 출력

### 7. Edge Cases / Limitation

- **`cat -- -`**: GNU cat에서 `--`는 옵션 종료 signifier이나, cat은 여전히 `-`를 stdin으로 처리한다 (GNU coreutils 특성상 `-` is always stdin even after `--`). 따라서 이 방법은 통하지 않는다.
- **다른 프로그램은?**: `grep -r . ./-`처럼 `-`를 파일명으로 넘기는 모든 유틸리티에서 동일 문제 발생. 해결법은 동일: `./` prefix.
- **스크립트에서 변수 처리**: `FILE="-"; cat "$FILE"` → 여전히 stdin. `cat "./$FILE"`로 처리해야 함.

---

## [Phase 3] Formal Summary (EN)

> [!definition] Path Disambiguation for Dashed Filenames
> Let $f$ be a filename in CWD such that $f = \text{"-"}$. For any utility $U$ that implements the POSIX stdin convention:
> $$U(f) \implies U(\text{stdin})$$
> The disambiguation is achieved by constructing an explicit path $p = \text{"./"} \| f$:
> $$U(p) \implies U\!\left(\text{open}(p, \text{O\_RDONLY})\right) \implies U(\text{file content})$$
> because $p \neq \text{"-"}$ and thus the stdin convention is never triggered.

> [!theorem] Sufficient Condition for Filename Disambiguation
> Any path component addition that makes the argument non-equal to `"-"` forces filesystem-level resolution: `./`, absolute path, or symlink to the file all satisfy this condition.

---

## [Phase 4] Better Methods

**Current approach** (used above):
```bash
cat ./-
```

**Alternative 1**: Input redirection (shell-level, bypasses cat entirely)
```bash
cat < -
```
Shell opens `-` as a file for stdin redirection *before* passing to cat → cat reads its own stdin which is the file. 동작 원리가 다르다: shell의 `open(2)`이 발생하는 시점에는 이미 path context가 있어 파일로 열림.
Trade-off: 작동하지만 직관적이지 않음. 다른 context (파이프 안 등)에서는 적용 불가.

**Alternative 2**: Absolute path
```bash
cat /home/bandit1/-
```
Trade-off: 작동하나 verbose. 절대경로는 이식성이 낮음 (level마다 home dir 다름).

**Most elegant**:
```bash
cat ./-
```
이유: 최소한의 변경으로 의도를 명확히 전달. `./` prefix는 "현재 디렉토리의 literal 파일"이라는 의미를 인간과 컴퓨터 모두에게 즉각 전달함. 표준 관용구(idiom)로 정착되어 있음.

---

## [Phase 5] Lessons Learned

1. **Shell과 프로그램의 argument 해석 레이어를 분리해서 생각하라**: quoting은 shell 레벨, stdin convention은 프로그램 레벨. 레이어 오진단 → 엉뚱한 해결 시도.
2. **`./` prefix는 특수 파일명의 universal 해결법**: `-`, 공백으로 시작하는 파일명 등 다수의 특수 케이스를 커버.
3. **실패 시도의 체계화**: `cat -` → `cat '-'` → `cat \-` → `cat ./-`의 시퀀스가 보여주는 것은 무작위 시도가 아니라 레이어별 가설 검증. 이 방법론이 핵심.
4. **`cat < -`도 작동**한다는 사실: redirection은 shell이 file을 열어 fd로 연결하므로, convention conflict 없음.

### Quiz

**Q** (Graduate-level): `cat < -`가 작동하는 이유를 syscall 수준에서 설명하라. 구체적으로, shell이 `<` redirection을 처리할 때 어떤 syscall 시퀀스가 발생하며, 이 과정에서 `-` string이 cat에게 전달되는가 아닌가?

<details>
<summary>풀이</summary>

`cat < -`를 bash가 처리하는 과정:

1. bash가 명령어 파싱: `cat` (cmd), `< -` (input redirection)
2. bash: redirection 처리를 위해 `open("-", O_RDONLY)` syscall 실행 — *현재 CWD에서*
3. 반환된 fd (예: fd=5)를 `dup2(5, STDIN_FILENO=0)` 로 stdin에 연결
4. `fork()` + `exec("cat")` — 이때 cat의 argv = `["cat"]`, **즉 `-` argument 없음**
5. cat은 argv[1]이 없으므로 default로 stdin을 읽음 (이미 파일이 연결된 fd=0)

따라서 `-` string은 cat에게 전달되지 않는다. Shell이 file open까지 완료하고 exec 전에 argv를 구성하므로, cat은 stdin convention을 적용할 기회 자체가 없다.

핵심: `cat ./-`는 *cat이 path를 받아 open*, `cat < -`는 *shell이 먼저 open하고 cat은 fd만 상속*.

</details>

> [!flashcard]
> **Q**: `cat -`이 stdin을 읽는 이유와, 이를 우회하는 가장 간결한 방법은?
> **A**: `-`는 POSIX convention상 stdin을 의미하며, cat이 인자 레벨에서 해석한다. 우회: `cat ./-` — `./` prefix로 cat이 path로 인식하게 강제.

> [!flashcard]
> **Q**: shell quoting(`cat '-'`)이 dashed filename 문제를 해결하지 못하는 이유는?
> **A**: `-`는 shell special character가 아님. Quoting은 shell 해석 방지용이고, stdin convention은 cat 내부 로직 — 레이어가 다르다.

---

## Links

### Tools Used
- [[Tools/cat]] *(planned)*
- [[Tools/ls]] *(planned)*

### Concepts Introduced (first encountered here)
- [[Concepts/Linux/Dashed_Filename]]

### Concepts Applied (reused from earlier)
- *(none)*

### Navigation
- **Prerequisite**: [[Level_00]]
- **Next**: [[Level_02]]

- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Level 1 Official: https://overthewire.org/wargames/bandit/bandit2.html
- POSIX stdin convention (`-`): https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap12.html
