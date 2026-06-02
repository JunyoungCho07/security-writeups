---
date: 2026-06-02
wargame: Bandit
level: 12
title: "Bandit Level 12 → 13"
difficulty: ★★☆
time_spent: 20min
tags: [bandit, linux, compression, forensics, file-signatures]
status: 🟡 developing
tools_used: [xxd, file, gzip, bzip2, tar, mktemp]
new_concepts: [File_Signatures, Hexdump_Reversal]
prerequisites: [Level_11]
---

# Bandit Level 12 → 13

## [Phase 1] Executive Summary

- **Goal**: `data.txt`(hexdump 형태)를 binary로 되돌린 뒤, **다중 압축 레이어**를 정체 식별→해제 반복으로 벗겨 password 추출
- **Key Skill**: `xxd -r`(hexdump→binary 역변환) + `file`(magic number로 포맷 식별) + gzip/bzip2/tar 반복 해제 루프
- **Tags**: `[File_Signatures]`, `[Hexdump_Reversal]`, `[Compression_Layers]`

[Cognitive Validation]
- **Limit Test**: 레이어 수 n → 0이면 data.txt가 곧 평문(해제 불필요); n → ∞면 무한 러시아 인형. 실제 n=9(hex 포함). 종료 조건은 `file`이 `ASCII text`를 뱉는 순간 = 고정점(fixed point).
- **Control Knob**: 지배 변수는 **각 레이어의 magic number**. 확장자가 아니라 첫 바이트가 다음 도구를 결정 — `file`이 control knob을 읽어주는 센서.
- **Nullity**: 압축이 아닌 layer(tar 아카이브)는 "압축률 0의 포장"일 뿐 — 크기를 줄이지 않고 구조만 감싼다. 그래도 한 겹으로 카운트.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**파일 포렌식 + 압축 식별**. 이 level은 단일 명령이 아니라 **루프 알고리즘**이다: `file로 정체 파악 → 알맞은 도구로 한 겹 해제 → 반복`. 본질은 "확장자는 거짓말이고, **magic number(파일 시그니처)가 진실**"이라는 명제. Level 04(`file`로 human-readable 탐지)의 확장판 — 거기선 1회, 여기선 N회 적용.

### 2. Definition (Formal, EN)

A **file signature** (magic number) is a fixed byte sequence at a known offset (usually offset 0) that identifies a file format independent of its name/extension. The `file(1)` utility classifies a file by matching its leading bytes against the libmagic database. This level requires composing the inverse operations of a stack of transforms T = Tₙ ∘ … ∘ T₁ applied to the plaintext p: recover p = T₁⁻¹ ∘ … ∘ Tₙ⁻¹ (data), where each Tᵢ⁻¹ is chosen by reading the signature exposed after peeling layer i+1.

### 3. Intuition (KR)

**러시아 마트료시카 인형**. 겉을 열면 또 인형, 또 인형… 단 인형마다 **재질이 달라서**(gzip이냐 bzip2냐 tar냐) 여는 손동작이 다르다. 그 재질을 알려주는 게 `file`. 손으로 더듬어 추측하지 말고 매번 라벨(magic byte)을 읽어라.

### 4. Theory (Mechanism)

세 가지 메커니즘이 맞물린다:

1. **Hexdump reversal**: 원본 `data.txt`는 binary가 아니라 그 binary의 **hexdump(ASCII 표현)**. `xxd -r`은 `xxd`의 역연산 — 왼쪽 offset/hex 칼럼을 읽어 raw byte를 재구성한다. (Level 09에서 `xxd`로 binary→hex를 봤다면, 여기선 hex→binary.)
2. **Magic number dispatch**: 각 해제 결과물의 첫 바이트가 다음 도구를 결정.
   - `1f 8b` → gzip
   - `42 5a 68`(`BZh`) → bzip2
   - tar는 offset 257에 `ustar` 시그니처
3. **확장자 무관**: gzip/bzip2는 파일명에 `.gz`/`.bz2`를 **요구**하지만(그래서 `mv`로 붙여줘야 함), 이는 도구의 편의 규칙일 뿐 내용과 무관. tar는 확장자 불요.

인과 사슬: data.txt = hexdump(조건) → `xxd -r`로 binary 복원(B) → `file`로 시그니처 판독(C) → 해당 해제기 적용(D) → 평문 도달까지 B′C′D′ 반복(E).

### 5. Solution

```bash
# SSH connection
$ ssh -p 2220 bandit12@bandit.labs.overthewire.org
# Password: <password masked>

# /tmp는 sticky + read 제한: 디렉토리 'ls'는 막혀도 mktemp로 작업공간 생성 가능
bandit12@bandit:~$ mktemp -d        # -d: 임시 '파일'이 아니라 임시 '디렉토리'를 생성(기본은 파일)
/tmp/tmp.<random masked>
bandit12@bandit:~$ cd /tmp/tmp.<random masked>
bandit12@bandit:/tmp/...$ cp ~/data.txt data.txt

bandit12@bandit:/tmp/...$ file data.txt
data.txt: ASCII text                       # = hexdump를 ASCII로 저장한 것

# --- 삽질 로그(교훈) ---
# (1) 'xxr' 오타 → command not found. 의도한 건 xxd.
# (2) xxd -d data.txt  → '-d'는 decimal offset 표시일 뿐, 역변환 아님 → 또 ASCII
#     (역변환 플래그는 -r. -d와 헷갈리지 말 것)
# (3) gzip이 'unknown suffix' 거부 → gzip은 .gz 확장자를 요구 → mv로 붙여야 함
# ----------------------

# 핵심 1단계: hexdump → binary
bandit12@bandit:/tmp/...$ xxd -r data.txt > data2   # -r: reverse — hexdump를 다시 raw binary로 복원(xxd 정방향의 역연산)
bandit12@bandit:/tmp/...$ file data2
data2: gzip compressed data, was "data2.bin", ...

# 플래그 설명 (이하 체인에서 반복 사용)
#   gzip -d / bzip2 -d : -d = decompress(해제). 기본 동작이 압축이라 명시 필요
#   tar -xvf           : -x = eXtract(추출), -v = verbose(추출 파일명 출력), -f = file(다음 인자를 아카이브 파일로 지정)
#                        └ -f는 필수: 없으면 tar가 테이프 장치(stdin)를 읽으려 함

# 이후: file로 정체 확인 → 해제 → 반복 (9 레이어)
bandit12@bandit:/tmp/...$ mv data2 data2.gz && gzip -d data2.gz      # → bzip2
bandit12@bandit:/tmp/...$ mv data2 data2.bz2 && bzip2 -d data2.bz2   # → gzip
bandit12@bandit:/tmp/...$ mv data2 data2.gz && gzip -d data2.gz      # → POSIX tar
bandit12@bandit:/tmp/...$ tar -xvf data2                             # → data5.bin (tar)
bandit12@bandit:/tmp/...$ tar -xvf data5.bin                         # → data6.bin (bzip2)
bandit12@bandit:/tmp/...$ mv data6.bin data6.bz2 && bzip2 -d data6.bz2  # → tar
bandit12@bandit:/tmp/...$ tar -xvf data6                             # → data8.bin (gzip)
bandit12@bandit:/tmp/...$ mv data8.bin data8.gz && gzip -d data8.gz  # → ASCII text

bandit12@bandit:/tmp/...$ file data8
data8: ASCII text                          # 종료 조건 도달
bandit12@bandit:/tmp/...$ cat data8
The password is <password masked>
# Next level(bandit13) password: <password masked>
```

> [!warning] Password Masking
> 최종 평문 password만 마스킹하면 된다(중간 압축 레이어는 binary라 자체 노출 위험 없음). 단 `mktemp` 디렉토리명(`/tmp/tmp.xxxx`)도 마스킹 — ToS상 "쉽게 추측되는 이름 금지" 권고와 별개로, 세션 추적 가능 정보다.

> [!tip] 압축 레이어 순서 (이번 케이스)
> `hexdump → gzip → bzip2 → gzip → tar → tar → bzip2 → tar → gzip → ASCII` (9겹). 순서는 매 인스턴스 동일하나, **외워서 풀지 마라** — `file`로 매번 확인하는 습관이 본질.

### 6. Why It Works

확장자가 아니라 **내용의 첫 바이트**가 포맷을 정의하기 때문. `file`이 매 단계 magic number를 읽어 다음 도구를 지목하고, 각 해제기는 자기 시그니처의 데이터만 처리한다. tar는 압축이 아니라 묶음이라 `tar -xf`로 풀면 내부 파일이 튀어나오고, gzip/bzip2는 단일 stream 해제다. 종료는 `file`이 더 이상 압축 시그니처를 못 찾고 `ASCII text`를 반환할 때 — 이것이 루프 불변식의 종료 조건.

### 7. Edge Cases / Limitation

- **gzip/bzip2의 확장자 강제**: `.gz`/`.bz2`가 없으면 `unknown suffix -- ignored`로 거부. `mv`로 붙이거나 `-c`/stdin 우회(`gzip -dc < f`) 필요. tar·`file`은 확장자 무관.
- **`xxd -r` vs `-d`**: `-r`만 역변환. `-d`는 offset을 decimal로 표시하는 무관한 플래그(삽질 지점).
- **`/tmp` 디렉토리 list 차단**: sticky+restricted라 `ls /tmp` 불가하나 파일 생성·접근은 가능. 그래서 `mktemp -d`로 고유 작업 디렉토리 확보가 정석.
- **무한 루프 위험**: `file`이 `data`(unknown)를 반환하면 magic DB에 없는 포맷 — 수동 분석 필요. 이 level엔 해당 없음.

---

## [Phase 3] Formal Summary (EN)

> [!definition] File Signature (Magic Number)
> A magic number is a constant byte pattern at a fixed offset (commonly 0) that uniquely identifies a container/format. Formally, format F is recognized iff bytes[off : off+len] = magic_F. Detection is name-independent: ∀ file f, type(f) = match(prefix(f), libmagic_DB), not ext(f).

> [!theorem] Layered Decompression Termination
> Given a finite transform stack p ↦ Tₙ∘…∘T₁(p) where each Tᵢ ∈ {gzip, bzip2, tar} is invertible and strictly increases "wrapping depth", the peel loop `while file(x) ≠ plaintext: x ← Tᵢ⁻¹(x)` terminates in exactly n steps, since depth is a well-founded decreasing measure bounded below by 0 (plaintext).

---

## [Phase 4] Better Methods

**Current approach** (used above): 수동 `file` → `mv` → 해제, 9회 반복. 학습엔 최적(매 레이어 시그니처를 눈으로 확인).

**Alternative 1**: 확장자 무관 강제 해제 (mv 제거)
```bash
gzip  -dc < data2 > data2.out    # -d: decompress(해제), -c: 결과를 stdout으로(원본 미수정·.gz 확장자 검사 우회)
bzip2 -dc < data2 > data2.out    # 동일 — -d 해제, -c stdout
```
Trade-off: `mv` 왕복 제거로 깔끔. tar는 여전히 `-xf`(`-x` 추출, `-f` 파일 지정) 별도.

**Alternative 2**: 만능 해제기
```bash
binwalk -e data2     # -e: --extract — 알려진 시그니처를 스캔해 자동 추출(known formats를 DB대로 떼어냄)
binwalk -Me data2    # -M: --matryoshka — 추출 결과에 재귀 적용(중첩 압축까지 자동); -e와 합쳐 묶음 플래그
7z x data2           # x: eXtract with full paths — 디렉토리 구조 보존하며 추출
                     #    (소문자 e는 경로 무시·평면 추출이라 중첩 구조가 깨짐 → x를 쓰는 이유)
```
Trade-off: 손맛(=학습) 없음. 실무·CTF에선 압도적으로 빠름. 단 단순 `binwalk -e`는 한 겹만 — 9중첩엔 `-M`(matryoshka)로 재귀를 켜야 한다.

**Most elegant** (루프 자동화):
```bash
f=data2
while file "$f" | grep -qE 'gzip|bzip2|POSIX tar'; do   # grep -q: quiet(매칭 출력 없이 종료코드만), -E: 확장정규식(| 대안 사용 위해)
  case $(file -b "$f") in                               # file -b: brief — 파일명 접두사 없이 타입 문자열만 출력(case 매칭용)
    gzip*)  mv "$f" "$f.gz";  gzip  -d "$f.gz" ;;        # -d: decompress
    bzip2*) mv "$f" "$f.bz2"; bzip2 -d "$f.bz2" ;;       # -d: decompress
    *tar*)  tar -xf "$f"; f=$(tar -tf "$f" | head -1) ;; # -x 추출·-f 파일 / -t: list(추출 않고 목록만)·-f 파일; head -1: 첫 줄(=내부 파일명)만
  esac
done; cat "$f"
```
Why elegant: "정체 식별→해제"라는 루프 불변식을 코드 구조로 그대로 표현. magic number dispatch가 `case`로 1:1 대응.
- `grep -q`: 출력 억제, 종료코드(0=매칭)만으로 while 조건 판정 → 화면 오염 없음
- `grep -E`: `gzip|bzip2|...`의 `|`(OR)를 정규식으로 해석시키기 위함(기본 BRE는 `\|` 필요)
- `file -b`: 접두사 `filename:` 제거 → `case` 패턴이 타입 문자열에 바로 매칭
- `tar -t`: 추출 없이 목록만 뽑아 내부 파일명을 얻고, `head -1`로 첫 항목만 취해 다음 루프 대상 `f`로 지정

---

## [Phase 5] Lessons Learned

1. **확장자는 거짓말, magic number가 진실**. 매 단계 `file`로 확인 — 순서를 외우는 건 학습이 아니라 암기.
2. **`xxd -r`**은 hexdump의 역연산. `-d`(decimal offset)와 혼동 금지. Level 09의 `xxd`(정방향)와 대칭.
3. **gzip/bzip2는 확장자를 강제**, tar는 무관. 우회는 `-dc < file`(stdin+stdout).
4. **`/tmp`는 list 차단·생성 허용** — `mktemp -d`로 고유 작업공간. write-restricted home의 표준 우회.

### Quiz

**Q**: `file`은 어떻게 확장자 없이 포맷을 아는가? gzip(`1f 8b`)과 tar를 비교해 magic number의 **offset 위치**가 다른 이유를 설명하고, magic-number 기반 탐지가 **실패하는** 두 가지 케이스를 제시하라.

> [!tip]- 풀이
> **메커니즘**: `file`은 libmagic DB(`/usr/share/misc/magic`)의 규칙 `(offset, type, value, name)`을 순차 매칭. gzip은 offset 0의 2바이트 `1f 8b`로 즉시 식별. tar는 헤더가 파일명·권한 등 메타데이터로 시작하고 포맷 식별자 `ustar`는 **offset 257**에 위치 — tar가 "압축 컨테이너"가 아니라 "블록 단위 아카이브 포맷"이라 헤더 레이아웃이 고정 512B 블록 구조이기 때문. 즉 magic의 offset은 포맷의 헤더 설계에 종속.
>
> **실패 케이스**: (1) **Magic 충돌/위조** — 임의 데이터가 우연히 또는 의도적으로 `1f 8b`로 시작하면 gzip으로 오판(polyglot/매직 스푸핑). (2) **헤더 없는 raw 포맷** — magic이 없는 평문·raw stream(예: 헤더 제거된 deflate raw)은 `data`로만 분류되어 식별 불가. 추가로 (3) 시그니처가 파일 **끝**에 있는 포맷(ZIP의 central directory는 EOF 부근)은 truncate되면 오탐.
>
> 핵심: magic number는 **휴리스틱**이지 증명이 아니다 — 신뢰하되 검증하라.

> [!flashcard]
> **Q**: Why does `xxd -r data.txt` matter before any decompression?
> **A**: `data.txt` is the **hexdump** (ASCII) of a binary, not the binary itself. `xxd -r` reverts hex→binary; only then do `file`/gzip see real magic bytes.

> [!flashcard]
> **Q**: gzip refuses a file with `unknown suffix -- ignored`. Why, and two fixes?
> **A**: gzip requires a `.gz` extension. Fix: `mv f f.gz; gzip -d f.gz`, or bypass via stdin/stdout `gzip -dc < f > out`.

---

## Links

### Tools Used
- [[Tools/xxd]]
- [[Tools/file]]
- [[Tools/gzip]]
- [[Tools/bzip2]]
- [[Tools/tar]]
- [[Tools/mktemp]]

### Concepts Introduced (first encountered here)
- [[Concepts/Linux/File_Signatures]]
- [[Concepts/Linux/Hexdump_Reversal]]

### Concepts Applied (reused from earlier)
- [[Concepts/Linux/Strings_Extraction]] (Level 09 — 같은 `xxd`/binary 분석 계열)
- File_Type_Detection (Level 04 `file` 1회 사용 → 여기선 루프로 N회 확장)

### Navigation
- **Prerequisite**: [[Level_11]]
- **Next**: [[Level_13]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit13.html
- `file(1)`, libmagic — magic number database
- `xxd(1)` — `-r` reverse mode; gzip(1) / bzip2(1) / tar(1)
