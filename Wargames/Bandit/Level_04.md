---
date: 2026-05-22
wargame: Bandit
level: 4
title: "Bandit Level 4 → 5"
difficulty: ★☆☆
time_spent: 5min
tags: [bandit, linux, file-type, magic-bytes, dashed-filename]
status: 🟢 solid
tools_used: [file, ls, cat, cd]
new_concepts: [File_Type_Identification, Magic_Bytes]
prerequisites: [Level_03]
---

# Bandit Level 4 → 5

## [Phase 1] Executive Summary

- **Goal**: `~/inhere/` 내 10개의 dashed-name 파일(`-file00` ~ `-file09`) 중 유일한 ASCII text 파일을 식별하고 password를 읽는다.
- **Key Skill**: `file` 명령으로 magic bytes 기반 파일 타입 판별 + `./` prefix로 dash-leading 인자 우회.
- **Tags**: `[File_Type_Identification]`, `[Magic_Bytes]`, `[Dashed_Filename]`, `[Libmagic]`

[Cognitive Validation]
- **Limit Test**:
  - ASCII 파일 수 → 0: `file ./*` 출력에 `ASCII text` 라인 없음 → 다른 휴리스틱 필요 (e.g. entropy, printable ratio).
  - ASCII 파일 수 → ∞ (모두 ASCII): `file` 무력화. 대신 파일 내용/크기/엔트로피로 정답 후보 좁혀야 함.
  - 따라서 `file` 명령의 유효성은 **"target class의 희소성"**에 의존. Signal/Noise ratio가 핵심 control variable.
- **Control Knob**: `./` prefix. With → 인자가 path로 해석됨. Without → `-file00`이 `file` 명령의 unknown flag으로 파싱됨 → 오류. 단 1비트 차이가 success/failure 결정.
- **Nullity**: 빈 파일(`-rw-r----- 0 bytes`)에 `file` 적용 시 → `empty` 반환. ASCII text도 data도 아님. Edge case 별도 처리 필요.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**File Type Identification under Adversarial Naming.**

이 레벨은 두 개의 직교 문제를 동시에 푼다:
1. **Type discovery problem**: 확장자 없는 파일들의 진짜 타입 판별 → `file` 명령 (libmagic backend).
2. **Argument-parsing hostile filename**: 이름이 `-`로 시작 → POSIX getopt 관습상 flag로 오인됨 → path disambiguation 필요.

두 문제는 독립적이지만 결합하면 표준 도구 사용이 깨진다. Linux 환경에서 흔히 마주치는 패턴이다.

### 2. Definition (Formal, EN)

> [!definition] File Type Identification via Magic Bytes
> Let $f$ be a file. Its **magic bytes** are the first $k$ bytes ($k$ typically 2–32) at offset 0, used as a fingerprint to infer content type independently of filename or extension. The Unix utility `file(1)` consults `/usr/share/misc/magic` (compiled to `magic.mgc`) — a database of `(offset, pattern, type_label)` tuples maintained by **libmagic** — to classify $f$. Identification proceeds in three tiers:
> $$\text{classify}(f) = \begin{cases} \text{filesystem test} & \text{(device/socket/symlink etc.)} \\ \text{magic test} & \text{(byte-pattern match)} \\ \text{language test} & \text{(text encoding + structure)} \end{cases}$$
> Output examples: `ELF 64-bit LSB executable`, `PNG image data`, `ASCII text`, `data` (unclassified).

> [!definition] Dashed Filename Disambiguation
> A filename whose first byte is `0x2D` (`-`) collides with the POSIX option-argument convention. Most utilities parse arguments left-to-right, terminating option processing at `--` or at the first non-option token. Two canonical mitigations:
> 1. Path-relative prefix: `./-file00` — first byte is `.`, not `-`, so the token is unambiguously a path.
> 2. End-of-options sentinel: `cmd -- -file00` — `--` instructs the parser to treat remaining tokens as positional.

### 3. Intuition (KR)

> [!tip] Intuition — file 명령
> 파일은 자기 정체를 자기가 안다. 확장자(`.txt`, `.jpg`)는 거짓말일 수 있지만 첫 몇 바이트(`%PDF`, `PK\x03\x04`, `\x7fELF`)는 형식의 정의에 의해 고정돼 있다. `file`은 이걸 사전(libmagic DB)과 대조하는 검사관이다.

> [!tip] Intuition — dashed filename
> Linux 명령어는 사람이 아니라 lexer다. 토큰의 **첫 글자**만 보고 "flag냐 path냐" 결정한다. `-file00`은 `f`라는 이름의 flag로 해석되고, 알려지지 않은 flag이므로 거부. `./` 두 글자를 붙이는 순간 정체성이 바뀐다 — 같은 파일을 가리키지만 lexer에게는 완전히 다른 토큰.

### 4. Theory (Mechanism)

**`file` 명령의 동작 단계** (man file(1), libmagic 5.x 기준):

```
입력 path → open(path) →
  [Tier 1] stat() → 파일시스템 타입 (regular, dir, symlink, fifo, ...)
  [Tier 2] read(first 4096 bytes) → magic.mgc DB와 패턴 매칭
           → ELF, PNG, ZIP, gzip, tar, JPEG, ... 수천 종 시그니처
  [Tier 3] 매칭 실패 시 텍스트 분석:
           - 인코딩 추정 (ASCII / UTF-8 / UTF-16 / ISO-8859 / EBCDIC ...)
           - printable ratio가 임계값 초과 → "<encoding> text"
           - 그 외 → "data" (= 모든 분류 실패)
```

이번 레벨에서 `-file07`만 `ASCII text`인 이유:
- 9개 파일은 random binary 또는 high-entropy data → Tier 2 시그니처 매칭 실패 + Tier 3 printable threshold 미달 → `data`.
- `-file07`은 32바이트 ASCII password + LF → 전부 printable → Tier 3 통과 → `ASCII text`.

**Dashed filename 처리 원리** (POSIX Utility Syntax Guideline 10):

```
argv 파싱 의사코드:
for tok in argv[1:]:
    if tok == "--":           # end-of-options sentinel
        treat rest as positional; break
    elif tok[0] == "-":       # option
        parse as flag
    else:                     # positional
        treat as file/path
```

`-file00`은 `tok[0] == "-"` 분기로 → flag 파싱 → `f`, `i`, `l`, `e`, `0`, `0` 중 하나가 unknown → 에러. `./-file00`은 `tok[0] == "."` → 즉시 positional로 분기. **단 1글자 lookahead로 결정되는 lexer 동작**이라 prefix 트릭이 보편적으로 통한다.

### 5. Solution

```bash
$ ssh -p 2220 bandit4@bandit.labs.overthewire.org
# Password: <password masked>

bandit4@bandit:~$ ls
inhere

bandit4@bandit:~$ cd inhere

# 1. 파일 목록 확인 — 10개 모두 dash-leading
bandit4@bandit:~/inhere$ ls
-file00  -file01  -file02  -file03  -file04  -file05  -file06  -file07  -file08  -file09

# 2. long listing으로 permission/size 확인
bandit4@bandit:~/inhere$ ls -al
total 48
drwxr-xr-x 2 root    root    4096 Apr  3 15:17 .
drwxr-xr-x 3 root    root    4096 Apr  3 15:17 ..
-rw-r----- 1 bandit5 bandit4   33 Apr  3 15:17 -file00
-rw-r----- 1 bandit5 bandit4   33 Apr  3 15:17 -file01
-rw-r----- 1 bandit5 bandit4   33 Apr  3 15:17 -file02
...
-rw-r----- 1 bandit5 bandit4   33 Apr  3 15:17 -file09

# 3. file 명령으로 타입 일괄 판별 — ./* 로 dash 회피
bandit4@bandit:~/inhere$ file ./*
./-file00: data
./-file01: data
./-file02: data
./-file03: data
./-file04: data
./-file05: data
./-file06: data
./-file07: ASCII text       ← 유일한 텍스트
./-file08: data
./-file09: data

# 4. 정답 파일 cat — 동일하게 ./ prefix 필수
bandit4@bandit:~/inhere$ cat ./-file07
<password masked>
# Next level password: <password masked>
```

> [!warning] Password Masking
> 실제 password는 절대 commit 금지. 평문 노출 시 OverTheWire ToS 위반 + public repo 신뢰성 손상. 모든 라인을 `<password masked>` 또는 `[REDACTED]`로 치환한다.

> [!warning] Dash Disambiguation
> `file -file07` (prefix 없음) → `file: invalid option -- 'i'` 류 에러. `cat -file07`도 동일. `./` 두 글자 또는 `--` sentinel 둘 중 하나는 반드시 필요.

### 6. Why It Works

**단계별 mechanism**:

1. `ls`로 디렉토리 구조 파악 → 모든 파일이 `-`로 시작함을 인지 → dashed-filename 패턴 발동.
2. `ls -al`로 permission 확인 → `bandit5:bandit4 rw-r-----` → group(bandit4) read 권한 보유 → 접근 가능.
3. `file ./*`:
   - `./*` glob은 shell이 `./-file00 ./-file01 ... ./-file09`로 expand.
   - 각 인자의 첫 글자가 `.`이므로 `file` 명령은 모두 positional path로 인식.
   - libmagic이 9개 binary는 `data`로, 1개 ASCII는 `ASCII text`로 분류.
4. `cat ./-file07` → 동일한 dash-회피 패턴 → 33 bytes (32 char password + LF) 출력.

**왜 정확히 `./` 인가**:
- `.` = current directory 의미.
- `./-file07`은 path semantically identical to `-file07`이지만 syntactically 다른 토큰 → POSIX argv parser에 unambiguous.
- Alternative: `cat -- -file07` (sentinel 방식) 또는 `cat "$(pwd)/-file07"` (absolute path) 도 동작.

### 7. Edge Cases / Limitation

- **`file` 명령의 약점**:
  - Magic DB에 없는 custom binary format → `data`로 분류 (false negative). 신뢰성 < 100%.
  - 적대적 input: 공격자가 PNG 헤더(`\x89PNG`)를 prefix로 붙인 PHP 웹쉘 → `file`은 `PNG image`로 보고 → MIME-based filter 우회 가능 (실제 web upload 취약점).
  - `file --mime-type ./*` 형태로 MIME 출력 가능 → 자동화 스크립트에 유용.
- **`./` 트릭의 한계**:
  - 일부 GNU 도구는 `--` sentinel만 인식하고 `./` prefix 무시 안 함 (드물지만 존재). 양쪽 다 알아두는 것이 안전.
  - Symlink chasing 옵션과 결합 시 의도와 다른 경로 해석 가능.
- **`-file07`의 위치가 매번 같다는 보장 없음**: Bandit Level 4는 고정이지만, 실전에서는 `file ./* | grep "ASCII text"`처럼 grep으로 추출하는 것이 robust.

---

## [Phase 3] Formal Summary (EN)

> [!definition] Magic-Byte Classification Function
> Let $\Sigma = \{0,1\}^8$ and $f \in \Sigma^*$ be a file. Let $\mathcal{M} = \{(p_i, \tau_i)\}_{i=1}^N$ be the libmagic pattern set, where $p_i \in \Sigma^*$ is a byte pattern and $\tau_i$ is the associated type label. Define
> $$\text{type}(f) = \begin{cases} \tau_i & \text{if } \exists i : f[0..|p_i|] \text{ matches } p_i \text{ (first match by DB priority)} \\ \text{"<enc> text"} & \text{else if } \rho(f) > \theta \text{ for encoding } \langle\text{enc}\rangle \\ \text{"data"} & \text{otherwise} \end{cases}$$
> where $\rho(f)$ is the printable-character ratio under the candidate encoding and $\theta \approx 0.95$ is the libmagic textness threshold.

> [!theorem] Dash-Prefix Path Disambiguation
> For any utility $U$ obeying POSIX Utility Syntax Guideline 10 and any filename $F$ with $F[0] = \text{`-'}$:
> $$U \; \text{./}F \; \equiv \; U \; \text{--} \; F \; \equiv \; U \; \text{\$(pwd)/}F$$
> in semantic effect on $F$, while $U \; F$ triggers option parsing and almost surely fails or misbehaves.

> [!proof]
> Both `./F` and `$(pwd)/F` produce tokens whose first byte $\neq$ `-`, bypassing the option-parsing branch of $U$'s argv loop. The `--` sentinel explicitly terminates option processing per Guideline 10. All three are equivalent in the resulting file-resolution call (`open(2)` receives a path that resolves to the same inode). The unprefixed form $U \; F$ enters the option-parsing branch and is rejected unless $F$ happens to be a valid option string for $U$. ∎

---

## [Phase 4] Better Methods

**Current approach** (used above):
```bash
file ./*
cat ./-file07
```

**Alternative 1**: `--` sentinel 방식
```bash
file -- *
cat -- -file07
```
Trade-off: `--`는 POSIX 표준이라 portability 우수. 단 `*` glob이 dash-files만 매칭한다는 보장은 환경 의존. `./` prefix가 더 self-documenting.

**Alternative 2**: absolute path
```bash
file "$PWD"/*
cat "$PWD/-file07"
```
Trade-off: 가장 명시적이지만 verbose. 스크립트에서 `cd`가 섞일 때 안전.

**Alternative 3**: `find` + `-exec`
```bash
find . -maxdepth 1 -type f -exec file {} \;
```
Trade-off: `find`는 기본적으로 `./` prefix를 붙여 출력 → dash 문제 자동 회피. 다만 한 줄 호출로는 over-engineering.

**Most elegant** (정답 한 줄 추출):
```bash
cat -- "$(file ./* | awk -F: '/ASCII text/{print $1; exit}')"
```
- `file ./*` → 타입 판별
- `awk -F: '/ASCII text/{print $1; exit}'` → "ASCII text" 라인의 path 추출, 첫 매칭에서 종료
- `cat -- "$..."`로 안전하게 출력

Why elegant: 파일명을 사람이 읽지 않고 pipeline으로 directly route. Bandit-style 자동화 스크립트의 표준 패턴. Adversarial naming + type discovery를 한 번에 해결.

**더 elegant한 대안** (grep 활용):
```bash
file ./* | grep -oP '^\S+(?=: ASCII text$)' | xargs cat
```
PCRE lookahead로 path만 추출 → `xargs cat`. 단 `xargs`는 dash-leading 인자에 약하므로 `xargs -I{} cat -- {}`가 더 안전.

---

## [Phase 5] Lessons Learned

1. **확장자는 거짓말이고 magic bytes는 진실이다**: 보안 분석/포렌식에서 file header 검증은 기본기. 업로드된 `.jpg`가 실제로 PHP일 수 있다.
2. **`-` 시작 파일명은 모든 CLI 도구의 잠재적 적**: `./` 또는 `--` 습관화. 스크립트 작성 시 `"$file"` quoting + path-prefix 둘 다 필수.
3. **`file` 명령은 휴리스틱이지 oracle이 아니다**: false positive/negative 존재. 적대적 환경에서는 magic 검사 + 추가 validation (e.g. parse 시도) 결합 필요.
4. **POSIX Utility Guideline 10을 외워라**: argv 파싱 규칙은 모든 Linux CLI의 공통 ABI. 이걸 모르면 sysadmin/security 어디서든 시간 낭비.
5. **glob expansion은 shell이, argument 해석은 명령이 담당**: 두 레이어 분리 인식이 디버깅 핵심. `echo ./*`로 expand 결과 미리 확인하는 습관.

### Quiz

**Q** (Graduate-level): 공격자가 `magic_bytes_only`로 동작하는 파일 업로드 검증을 우회하기 위해 `<?php system($_GET['c']); ?>`가 포함된 PHP 코드를 PNG로 위장하려 한다. (a) 어떤 magic byte sequence를 prefix로 붙여야 `file` 명령이 `PNG image data`로 분류하는가? (b) 이 우회가 성공한 후 서버에서 PHP 인터프리터가 실제 코드를 실행하게 되는 조건은 무엇인가? (c) 방어 측 관점에서 이 공격을 막을 수 있는 최소 두 가지 검증 추가는?

> [!tip]- 풀이
> **(a) PNG magic bytes**:
> - PNG signature는 `89 50 4E 47 0D 0A 1A 0A` (8 bytes). ASCII로 `\x89PNG\r\n\x1a\n`.
> - 공격 파일 구조:
>   ```
>   [\x89PNG\r\n\x1a\n][IHDR chunk... (선택적)][<?php system($_GET['c']); ?>]
>   ```
> - libmagic은 첫 8바이트만 검사하면 `PNG image data, ...`로 분류 → 검증 통과.
>
> **(b) 실행 조건**:
> - 서버가 업로드 파일을 PHP로 해석해야 함:
>   - 파일 확장자가 `.php`, `.phtml`, `.phar` 등이거나
>   - Apache가 `AddHandler application/x-httpd-php .png` 같은 misconfiguration 보유 (드물지만 존재) 또는
>   - LFI(Local File Inclusion) 취약점이 있어서 `include($_GET['file'])` 같은 패턴에서 업로드 경로를 include 가능.
> - "Polyglot file" 공격 — 한 파일이 PNG로도 PHP로도 동시에 유효.
>
> **(c) 방어**:
> 1. **MIME magic 검증 + 확장자 화이트리스트 동시 적용**: 확장자가 `.png/.jpg/.gif`인지 명시적으로 확인. 둘 중 하나만으로 부족.
> 2. **이미지 라이브러리로 re-encode**: GD/ImageMagick으로 업로드된 이미지를 로드 후 새 파일로 저장. PHP payload는 파싱 과정에서 손실됨. (단 ImageMagick 자체 취약점 — ImageTragick 류 — 주의.)
> 3. **업로드 디렉토리에서 PHP 실행 비활성화**: `.htaccess`에 `php_flag engine off` 또는 `<FilesMatch>` 블록으로 .php 핸들러 제거. 가장 강력한 방어.
> 4. **컨텐츠 stripping**: PNG는 IHDR 이후 chunk 단위로 파싱 가능. 알려진 chunk 외 모두 제거하면 payload 영역 삭제됨.
>
> 핵심: magic bytes 검증은 **필요조건일 뿐 충분조건이 아니다**. Defense-in-depth.

> [!flashcard]
> **Q**: `file -file07` 명령이 실패하는 이유와, 최소 변경으로 동작하게 만드는 두 가지 방법은?
> **A**: `-file07`이 POSIX option parser에 의해 flag로 해석되어 unknown option 에러. 해결: ① `./-file07` (path prefix) ② `file -- -file07` (end-of-options sentinel). 둘 다 첫 토큰이 `-`로 시작하지 않게 만들거나 명시적으로 option parsing 종료.

> [!flashcard]
> **Q**: `file` 명령이 의존하는 데이터베이스 이름과, "data"라는 출력이 의미하는 바는?
> **A**: libmagic의 `/usr/share/misc/magic` (compiled: `magic.mgc`). 수천 개 file format signature를 보유. "data" 출력 = magic 시그니처 매칭 실패 + 텍스트 인코딩 분석에서도 printable threshold 미달 = "분류 불가". 파일이 비어있지 않은 binary일 가능성 높음.

---

## Links

### Tools Used
- [[Tools/file]] *(planned — `<<Tool file>>`로 생성 권장)*
- [[Tools/ls]] *(planned)*
- [[Tools/cat]] *(planned)*

### Concepts Introduced (first encountered here)
- [[Concepts/Linux/File_Type_Identification]] *(planned — `<<Deep File_Type_Identification>>`)*
- [[Concepts/Linux/Magic_Bytes]] *(planned — `<<Deep Magic_Bytes>>`)*

### Concepts Applied (reused from earlier)
- [[Concepts/Linux/Dashed_Filename]] — Level_02에서 첫 등장한 dash-leading 파일명 처리 패턴의 재적용. 이번엔 `./` prefix를 10개 파일에 일괄 적용 (glob과 결합).

### Navigation
- **Prerequisite**: [[Level_03]]
- **Next**: [[Level_05]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Level 4 Official: https://overthewire.org/wargames/bandit/bandit5.html
- `file(1)` man page: https://man7.org/linux/man-pages/man1/file.1.html
- libmagic source / magic DB: https://github.com/file/file
- POSIX Utility Syntax Guidelines: https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap12.html
