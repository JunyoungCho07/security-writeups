---
date: 2026-05-16
wargame: Bandit
level: 3
title: "Bandit Level 3 → 4"
difficulty: ★☆☆
time_spent: 5min
tags: [bandit, linux, hidden-files, filesystem]
status: 🟢 solid
tools_used: [ls, cat, cd]
new_concepts: [Hidden_Files]
prerequisites: [Level_02]
---

# Bandit Level 3 → 4

## [Phase 1] Executive Summary

- **Goal**: `inhere/` 디렉토리 안의 숨겨진 파일 `...Hiding-From-You`에서 password를 읽는다.
- **Key Skill**: `ls -a` 플래그로 dot-prefix 파일을 노출시키는 기법
- **Tags**: `[Hidden_Files]`, `[Dot_Files]`, `[Filesystem_Convention]`

[Cognitive Validation]
- **Limit Test**: `.`로 시작하는 파일이 0개 → `ls`와 `ls -a`의 결과가 `.`과 `..`만 차이남. `.`로 시작하는 파일이 ∞개 → `ls -a`로 모두 노출. 즉 숨김 여부는 파일 내용이 아닌 *이름의 첫 글자*가 결정한다.
- **Control Knob**: `ls`의 `-a` flag. 없으면 dot-files 필터링. 있으면 전체 출력. 단일 비트 제어.
- **Nullity**: `.`(현재 디렉토리)와 `..`(부모 디렉토리)는 항상 `ls -a`에 표시됨. 진짜 숨김 파일과 구분 필요.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**Filesystem Naming Convention** — "숨김"은 파일시스템의 기능이 아니라 *convention*이다. Kernel은 `.`으로 시작하는 파일과 그렇지 않은 파일을 동일하게 처리한다. `ls`가 소프트웨어 레벨에서 필터링할 뿐.

### 2. Definition (Formal, EN)

> [!definition] Hidden File (Dot File)
> A **dot file** is any filesystem entry whose name begins with U+002E (FULL STOP, `.`). By POSIX convention, directory listing utilities omit such entries from default output. The kernel treats dot files identically to other files — no special permission, attribute, or inode flag distinguishes them. Visibility is purely a userspace convention enforced by `ls`, file managers, and shell glob expansion (`*` excludes dot files by default, `.*` matches them).

**내 언어로**: 커널은 모른다. `ls` 프로그램이 "이름이 `.`으로 시작하면 출력 안 함"이라는 규칙을 스스로 적용할 뿐. 파일 자체에 "숨김 비트" 같은 건 없다.

### 3. Intuition (KR)

> [!tip] Intuition
> Windows의 "숨김 파일 속성"은 파일 메타데이터(attribute bit)에 저장됨. Linux의 "숨김"은 이름 첫 글자가 `.`인가 아닌가 — 파일 *이름 규칙*이지 파일 *속성*이 아니다.

### 4. Theory (Mechanism)

**왜 `ls`는 dot-files를 기본으로 숨기는가?**

역사적 이유: Unix 초창기, `.`(현재 디렉토리)와 `..`(부모 디렉토리)를 `ls` 출력에서 숨기기 위해 "이름이 `.`으로 시작하면 스킵" 규칙 도입. 부수 효과로 `.bashrc`, `.ssh/` 등 설정 파일들도 평소 출력에서 숨겨지게 됨 → 이후 convention으로 정착.

**이번 레벨의 파일명 `...Hiding-From-You`**:
- 세 개의 점으로 시작 → `.`으로 시작 → dot-file → `ls` 기본 출력에서 숨겨짐
- `..`(부모 디렉토리)와 다름: `...`는 세 글자이므로 regular file
- `ls -a` 또는 `ls -al`로 노출

**`ls` flag 동작**:
```
ls         →  dot-files 제외 출력
ls -a      →  모든 파일 (. 및 .. 포함)
ls -A      →  . 및 .. 제외한 모든 파일 (숨김 파일만 보고 싶을 때 더 깔끔)
ls -al     →  -a + -l (long format: permissions, owner, size, date)
```

### 5. Solution

```bash
$ ssh -p 2220 bandit3@bandit.labs.overthewire.org
# Password: <password masked>

bandit3@bandit:~$ ls
inhere

bandit3@bandit:~$ cd inhere

# ls 기본 → 아무것도 안 보임 (dot-file 필터링)
bandit3@bandit:~/inhere$ ls

# ls -al → 숨김 파일 노출
bandit3@bandit:~/inhere$ ls -al
total 12
drwxr-xr-x 2 root    root    4096 Apr  3 15:18 .
drwxr-xr-x 3 root    root    4096 Apr  3 15:18 ..
-rw-r----- 1 bandit4 bandit3   33 Apr  3 15:18 ...Hiding-From-You

bandit3@bandit:~/inhere$ cat ...Hiding-From-You
<password masked>
```

> [!warning] Password Masking
> 실제 password는 절대 commit하지 마라. `<password masked>`로 치환.

### 6. Why It Works

- `ls -al`: `-a`(all, dot-files 포함) + `-l`(long format)
- `...Hiding-From-You`는 `.`으로 시작 → dot-file convention에 의해 평소 숨겨짐
- `cat ...Hiding-From-You`: shell에서 `...`는 special char가 아님 → 그대로 파일명으로 전달 → 정상 open

**Permission 확인** (`ls -al` 출력에서):
```
-rw-r----- 1 bandit4 bandit3 33 ...Hiding-From-You
```
- owner: `bandit4` (read/write)
- group: `bandit3` (read only) ← 현재 유저가 `bandit3`이므로 읽기 가능
- others: no permission

### 7. Edge Cases / Limitation

- **`ls -A` vs `ls -a`**: `-A`는 `.`과 `..`를 제외한 dot-files만 출력. 실전에서 더 유용.
- **Shell glob `*` vs `.*`**: `cat *`은 dot-files 미매칭. `cat .*`은 `.`과 `..`도 매칭 시도 → 오류. `cat .??*`으로 길이 2 이상 dot-files만 매칭 가능.
- **find로 탐색**: `find . -name ".*"` → 재귀적으로 모든 dot-files 탐색. 중첩 디렉토리에서 유용.
- **Windows와의 차이**: Windows 숨김 파일은 파일 attribute bit (`FILE_ATTRIBUTE_HIDDEN`)으로 저장. 이름 무관. Linux와 메커니즘 완전히 다름.

---

## [Phase 3] Formal Summary (EN)

> [!definition] Dot File Convention
> Let $F$ be a filename in a POSIX filesystem. $F$ is a **dot file** iff $F[0] = \text{'.'}$. The kernel applies no special semantics; visibility filtering is implemented at the userspace level:
> $$\text{ls\_default}(d) = \{f \in d \mid f[0] \neq \text{'.'}\}$$
> $$\text{ls\_all}(d) = \{f \in d\} \quad \text{(includes . and ..)}$$
> $$\text{ls\_almost\_all}(d) = \{f \in d \mid f \notin \{\text{"."}, \text{".."}\}\}$$

> [!theorem] Dot File Is Not Hidden at Kernel Level
> No inode field, extended attribute, or permission bit distinguishes a dot file from a regular file. `stat("./...Hiding-From-You")` returns identical structure to `stat("./readme")`. Hiddenness is a property of the naming convention, not the filesystem object.

---

## [Phase 4] Better Methods

**Current approach**:
```bash
ls -al
cat ...Hiding-From-You
```

**Alternative 1**: `ls -A` (cleaner)
```bash
ls -A
```
`.`과 `..` 없이 숨김 파일만 표시. 실전에서 더 많이 씀.

**Alternative 2**: `find`로 탐색 (중첩 구조에서 강력)
```bash
find . -name ".*" -type f
```
현재 디렉토리 아래 모든 dot-files 재귀 탐색. 단일 레벨은 overkill이지만 구조가 복잡할 때 유효.

**Alternative 3**: glob 활용
```bash
cat .??*
```
`.` 포함 3글자 이상인 dot-files만 매칭. `.`과 `..`를 제외하고 싶을 때.

**Most elegant**:
```bash
ls -A && cat ...Hiding-From-You
```
또는 파일명 모를 때:
```bash
cat $(ls -A)
```
`ls -A` 결과를 command substitution으로 cat에 전달. 파일이 하나인 경우 탐색과 읽기를 한 줄로.

---

## [Phase 5] Lessons Learned

1. **Linux의 "숨김"은 이름 convention이지 속성이 아니다**: 파일 삭제/이동 없이 이름 앞에 `.` 추가만으로 숨길 수 있음. 반대도 가능 (`mv .bashrc bashrc`).
2. **`ls -A`를 default로 사용하는 습관**: `.`과 `..`는 항상 있으므로 대부분 노이즈. `-A`가 더 실용적.
3. **Permission 읽기**: `ls -l`의 9자리 permission string (`rw-r-----`)에서 owner/group/others 권한을 즉시 읽을 수 있어야 함. 이 레벨에서 group read가 없었다면 접근 불가.
4. **`...` (triple dot)은 regular file**: `.`(CWD)과 `..`(parent)만 special. 점 3개 이상은 평범한 dot-file.

### Quiz

**Q** (Graduate-level): Shell에서 `cat .*`을 실행했을 때 `.`과 `..`가 매칭되어 오류가 발생하는 이유와, 정확히 2개 이상의 추가 문자를 가진 dot-files만 glob으로 안전하게 매칭하는 패턴은 무엇인가? 그리고 이 패턴이 동작하는 shell glob의 규칙을 설명하라.

> [!tip]- 풀이
> **`cat .*` 문제**:
> - `.*` glob은 `.`으로 시작하는 모든 이름 매칭 → `.`과 `..` 포함
> - `cat .` → 디렉토리를 cat → `Is a directory` 오류
> - `cat ..` → 동일
>
> **안전한 패턴**: `cat .??*`
> - `.` → literal dot
> - `?` → 정확히 1개의 임의 문자
> - `?` → 정확히 1개의 임의 문자
> - `*` → 0개 이상의 임의 문자
> - 결합: `.` + 최소 2글자 + 0개 이상 = 총 3글자 이상인 dot-files
> - `.`은 1글자, `..`는 2글자 → 둘 다 제외
>
> **Bash glob 규칙**:
> - `?`는 정확히 1개의 문자와 매칭 (`.`과 `/` 제외)
> - `*`는 0개 이상의 문자와 매칭
> - Glob은 shell이 expand하기 전에 파일 시스템과 대조하여 매칭 목록 생성
> - 매칭 결과가 없으면 (기본값) literal string으로 남기거나 오류 (`nullglob` 옵션에 따라)
>
> 더 robust한 방법: `find . -maxdepth 1 -name ".*" ! -name "." ! -name ".."` — `.`과 `..`를 명시적으로 제외.

> [!flashcard]
> **Q**: Linux에서 파일을 숨기는 메커니즘과, Windows의 숨김 파일 메커니즘의 근본적 차이는?
> **A**: Linux: 파일명 첫 글자를 `.`으로 설정 — userspace convention, kernel 무관. Windows: inode/MFT의 `FILE_ATTRIBUTE_HIDDEN` attribute bit — filesystem 레벨 메타데이터. Linux는 rename만으로 숨김 토글 가능.

> [!flashcard]
> **Q**: `ls -a`와 `ls -A`의 차이는?
> **A**: `-a`는 `.`(현재 디렉토리)과 `..`(부모 디렉토리)를 포함한 모든 항목 출력. `-A`는 이 둘을 제외하고 dot-files만 출력. 실전에서 `-A`가 더 유용.

---

## Links

### Tools Used
- [[Tools/ls]] *(planned)*
- [[Tools/cat]] *(planned)*

### Concepts Introduced (first encountered here)
- [[Concepts/Linux/Hidden_Files]]

### Concepts Applied (reused from earlier)
- [[Concepts/Linux/Dashed_Filename]] — 특수 파일명 처리 패턴의 연장

### Navigation
- **Prerequisite**: [[Level_02]]
- **Next**: [[Level_04]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Level 3 Official: https://overthewire.org/wargames/bandit/bandit4.html
- POSIX `ls` specification: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/ls.html
