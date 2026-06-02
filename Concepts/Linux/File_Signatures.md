---
date: 2026-06-02
domain: Linux
topic: File_Signatures
tags: [forensics, file-format, magic-number, file-detection]
status: 🟡 developing
mastery: 0
first_encountered: [[Wargames/Bandit/Level_12]]
reapplied_in: []
last_reviewed: 2026-06-02
---

# File_Signatures

## Core Idea (1-2 sentences, KR)

파일의 **정체는 확장자가 아니라 내용의 첫 바이트(magic number)**가 결정한다. `file`은 이 시그니처를 libmagic DB와 매칭해 이름과 무관하게 포맷을 식별한다.

---

## [Step 1] Concept Categorization

데이터 포렌식의 기초 식별 메커니즘. "self-describing format"의 한 형태 — 파일이 자기 헤더에 "나는 X 포맷"이라는 라벨을 박아둔다. 확장자(name-level metadata)와 시그니처(content-level metadata)의 분리.

## [Step 2] Definition

> [!definition] File Signature (Magic Number)
> A file signature is a constant byte sequence `magic_F` at a fixed offset `off_F` that identifies format F. Recognition: a file `f` is of type F ⟺ `bytes(f)[off_F : off_F + len(magic_F)] = magic_F`. Detection is name-independent: `type(f) = match(content(f), libmagic_DB)`, never `ext(f)`.
^definition

**내 언어로 (KR)**: 파일 맨 앞(보통)에 박힌 고정 바이트 지문. 확장자를 지우거나 위조해도 이 지문은 내용 안에 있어 그대로 남는다. `file`은 지문 대조기.

## [Step 3] Intuition

> [!tip] Intuition
> 여권 표지의 국장(國章) — 표지에 뭐라 적든, 안쪽 칩의 코드가 진짜 국적이다. 확장자는 표지 글씨, magic number는 내장 칩.
^intuition

## [Step 4] Theory

`file(1)`은 libmagic DB(`/usr/share/misc/magic`)의 규칙 `(offset, type, value, name)`을 위에서부터 매칭한다. 대표 시그니처:

| Format | Offset | Magic (hex / ascii) |
|---|---|---|
| gzip | 0 | `1f 8b` |
| bzip2 | 0 | `42 5a 68` (`BZh`) |
| PNG | 0 | `89 50 4e 47` (`.PNG`) |
| ELF | 0 | `7f 45 4c 46` (`.ELF`) |
| PDF | 0 | `25 50 44 46` (`%PDF`) |
| tar | **257** | `75 73 74 61 72` (`ustar`) |
| ZIP | 0 | `50 4b 03 04` (`PK..`) |

offset이 포맷마다 다른 이유: 헤더 레이아웃에 종속. tar는 512B 블록 구조라 식별자가 메타데이터 뒤(257)에 온다.

## [Step 5] When & Condition

- 확장자가 없거나·거짓이거나·신뢰 불가할 때 (다운로드, 압축 중첩, CTF artifact).
- 포맷이 **헤더에 시그니처를 박는** self-describing format일 때 holds. 헤더 없는 raw stream엔 적용 불가.

## [Step 6] Limitation & Alternatives

- **한계**: magic은 휴리스틱. (1) 임의 데이터가 우연히 시그니처와 일치 → 오탐. (2) 의도적 위조(polyglot/매직 스푸핑). (3) 헤더 없는 raw 포맷·암호화 데이터는 `data`(unknown)로만 분류.
- **대안**: 구조 검증(파서로 끝까지 파싱), 엔트로피 분석(암호화/압축 구분), 다중 시그니처(EOF의 ZIP central directory 등) 교차 확인.

## [Step 7] Duality & Null Space

- **Dual**: 확장자(name-based) ↔ magic number(content-based). 둘이 불일치하면 위조·오명명 신호.
- **Null space**: magic이 없는 파일(평문 텍스트, raw stream). `file`이 `ASCII text`/`data`로 떨어지는 영역 — Level 12 루프의 **종료 조건**이 바로 이 null space 진입.

## [Step 8] Validation

- **Limit Test**: 파일 크기 → magic 길이 미만이면 식별 불가(truncated). 크기 → ∞라도 식별은 prefix만 보므로 O(1).
- **Dimensional Check**: 시그니처는 (offset, bytes) 쌍 — 위치 차원과 값 차원이 함께여야 의미. offset 무시하면 tar 오인.
- **Control Knob**: 첫 N바이트. 이걸 바꾸면 `file`의 판정이 바뀐다.

## [Step 9] Advanced Perspective

Polyglot 파일 — 여러 포맷의 시그니처 제약을 동시 만족시켜 한 바이트열이 GIF이면서 동시에 유효 JS/PDF인 구성. magic number가 **충분조건이 아님**을 보이는 공격적 사례(보안: MIME confusion, 필터 우회).

## [Step 10] Link to Upper Concepts

상위 개념 = **self-describing data** / type tagging. 네트워크의 프로토콜 magic(예: TLS record type), 실행 포맷의 ELF/Mach-O 헤더, 직렬화 포맷의 버전 바이트 모두 같은 원리의 변주.

## [Step 11] Generalization

일반화하면 "tagged union의 런타임 디스패치" — 데이터 첫 필드(tag)로 해석기를 고른다. magic number = 디스크 위 데이터의 type tag. Level 12의 해제 루프 = tag 기반 dispatch loop.

## [Step 12] Confer (Comparison)

- **vs. File extension**: 확장자는 OS/유저 편의용 name metadata, 변조 자유·신뢰 불가. magic은 content-embedded, 상대적으로 견고.
- **vs. MIME type**: MIME은 전송 계층의 선언적 타입(`Content-Type` 헤더), 역시 위조 가능. magic은 실제 바이트 증거. 웹 보안의 "MIME sniffing"이 바로 magic으로 선언을 검증/무시하는 동작.

## [Step 13] Implication

"확장자를 믿지 마라"는 포렌식·보안의 1원칙. 업로드 필터를 확장자로만 하면 우회됨(magic 검사 필요), 반대로 magic만 믿으면 polyglot에 당함. 신뢰의 근거를 content로 옮기되 다층 검증.

## [Step 14] Application

- **보안**: 악성 파일 분석(확장자 위장 탐지), 업로드 필터 우회/방어, CTF artifact 식별, 카빙(carving — 디스크 이미지에서 시그니처로 파일 복원).
- **일반**: 압축 중첩 해제(Level 12), 알 수 없는 다운로드 식별, 데이터 복구.

## [Step 15] Background Knowledge

"Magic number"란 용어는 Unix `file` 명령(7th Edition, 1970s)에서 대중화. 초기 a.out 실행 포맷의 헤더 첫 워드를 "magic"이라 부른 데서 유래 — 커널이 이 값으로 실행 가능 여부를 판별했다. libmagic은 이 magic DB를 라이브러리화한 현대 구현.

---

## Formal Summary (EN)

> [!theorem] Signature-Based Identification
> For self-describing formats, `type(f)` is decidable from a bounded prefix: ∃ N such that reading `f[0:N]` suffices to classify f via `libmagic`. Complexity O(1) in file size. Soundness is heuristic, not guaranteed — collisions and forgeries exist.

> [!proof] Sketch
> Each magic rule fixes `(off, value)`. Since `off + len(value) ≤ N` for catalogued formats, the matcher inspects only `f[0:N]` ⟹ constant-time. Forgery: construct `f` with `f[off:off+len] = magic_F` while content is arbitrary ⟹ false positive ⟹ detection is necessary but not sufficient. □

---

## Cross-References

### Encountered In
- [[Wargames/Bandit/Level_12]] ← first (multi-layer 압축 해제 루프)
- [[Wargames/Bandit/Level_04]] (file type detection, 1회 적용 — 동일 개념의 씨앗)

### Tools That Implement This
- [[Tools/file]]
- [[Tools/xxd]] (raw 바이트/시그니처 hex 확인)

### Related Concepts
- [[Concepts/Linux/Hexdump_Reversal]] (Related — Level 12에서 짝으로 사용)
- [[Concepts/Linux/Strings_Extraction]] (Related — 둘 다 binary 내용 분석)

### Cross-Domain
- Web: MIME sniffing / `Content-Type` 검증 (same idea — content vs declared type)

---

## Quiz

**Q1** (Graduate-level): 업로드 필터가 (a) 확장자만 검사, (b) magic number만 검사, (c) 둘 다 검사할 때 각각의 우회 시나리오를 제시하라. magic 검사조차 안전하지 않은 이유를 polyglot으로 설명하라.

> [!tip]- 풀이
> (a) 확장자만: `shell.php`를 `shell.jpg`로 rename → 통과 후 서버가 php로 실행하면 RCE. (b) magic만: 진짜 JPEG 헤더(`ff d8 ff`)를 앞에 붙이고 뒤에 php 페이로드 → magic은 JPEG 통과, 파서가 뒷부분을 실행하면 우회. (c) 둘 다: 확장자+magic 일치 요구해도 **polyglot**(유효 JPEG이면서 유효 php인 파일)이면 양쪽 만족 → 여전히 우회 가능.
>
> 핵심: magic number는 **필요조건이지 충분조건이 아니다**. 진짜 방어는 재인코딩(이미지 재저장)·실행 컨텍스트 분리·content 정규화.

---

> [!flashcard]
> **Q**: Why can `file` identify a format with a wrong/missing extension?
> **A**: It matches a fixed byte signature (magic number) in the content against libmagic, e.g. gzip = `1f 8b` at offset 0 — extension is irrelevant.

> [!flashcard]
> **Q**: Why is tar's signature at offset 257, not 0?
> **A**: tar is a 512-byte block archive; its header begins with file metadata, and the `ustar` identifier sits at offset 257 within that fixed layout.
