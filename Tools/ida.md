---
tool: ida
category: reverse-engineering
man_section: 0
related: [objdump, nm, strings]
last_used: 2026-10-31
tags: [tool, macos, disassembler, decompiler]
---

# `ida` (IDA Free)

## Purpose
GUI 디스어셈블러 + (제한된) 디컴파일러. 함수 단위로 코드를 graph 로 보여주고, 변수 이름·주석을 달 수 있다.

## Full Signature
GUI 도구라 명령줄 인자가 아니라 **파일 로드 → 분석 대기 → 뷰 선택**의 흐름이다.

| 단계 | 하는 일 |
|---|---|
| 1. 로드 | ELF 를 열면 포맷·프로세서를 자동 감지한다 (x86-64 / i386 구분) |
| 2. 분석 | 자동 분석이 끝날 때까지 기다린다 (아래쪽 상태 표시줄) |
| 3. 뷰 | 함수를 고르고 graph / text / pseudocode 를 전환한다 |

## Common Flags (most-used keys)

macOS 에서 **Alt = ⌥ (Option)** 이다.

| 키 | 효과 | 쓸 때 |
|---|---|---|
| `Space` | graph ↔ text 뷰 전환 | 블록 구조 ↔ 주소 순서 |
| `F5` | 현재 함수를 pseudocode 로 디컴파일 | 함수 의도 파악 |
| `X` | 선택한 심볼의 cross-reference 목록 | "누가 이걸 부르나/쓰나" |
| `N` | 이름 바꾸기 | 읽기 쉬운 변수명 |
| `G` | 주소로 이동 | 특정 주소 확인 |
| `Shift+F12` | Strings 창 | 문자열 목록 (ASCII 위주) |

## Idiomatic Examples

### 기본 사용
1. `main` 을 찾아 graph 뷰로 연다.
2. `F5` 로 의사 코드를 본다.
3. 호출되는 함수에서 `X` 로 호출 지점을 역추적한다.

### 자주 쓰는 조합
- **Options → General → Graph → Max number of nodes**: graph 의 노드 상한. 거대한 함수에서 "graph is too big" 이 나올 때 올린다.

## Pitfalls

> [!warning] Common Mistakes
> 1. **한글 입력기가 켜져 있으면 한 글자 단축키가 안 먹는다.** 영어 입력으로 바꾼다.
> 2. **Hex-Rays 디컴파일러에도 한도가 있다.** 함수가 너무 크면 "too big function" 으로 실패한다 — 이때는 디컴파일 대신 graph / text 로 본다.
> 3. **graph 한도(기본 1000 노드)** 를 넘으면 graph 모드가 거부된다. 한도를 올리면 되고, 노이즈가 일부러 만든 것일 수 있어 올리기 전에 이유를 따져본다.
> 4. 헤더의 `Source File` 같은 **메타 정보**가 단서가 되는 경우가 있다. 코드만 보지 말고 상단 요약을 읽는다.

## Edge Cases
- 자동 분석이 점프 테이블 항목 전부를 분기로 그린다 (`E_static ⊇ E_runtime`) → [[Concepts/Binary/Control_Flow_Graph]].
- 세그먼트 크기가 0인 `LOAD` 는 `?` 로 표시된다 (`p_filesz` = `p_memsz` = 0, 빈 segment) → [[Concepts/Binary/ELF_Sections_And_Relocation]].

## Related Tools

| Tool | Relationship |
|---|---|
| [[Tools/objdump]] | 터미널에서 선형 스윕 disassembly. 가볍고 스크립트 가능 |
| [[Tools/nm]] | 심볼 표만 빠르게 |
| [[Tools/strings]] | 문자열만 빠르게 (ASCII 기준) |

## Encountered In (Wargame Levels)
- External: local-only wargame tree (no-publish) — IDA 로 처음 ELF 를 열고 graph 한도·디컴파일 한도·`Source File` 헤더를 만난 곳.

## Concepts This Implements
- [[Concepts/Binary/Control_Flow_Graph]]

## Quick Reference

```text
Space      graph <-> text
F5         pseudocode
X          xrefs
Options -> General -> Graph -> Max number of nodes   (graph 한도)
```

> [!flashcard]
> **Q**: IDA 에서 "graph is too big" 이 나왔다. 무엇을 하나?
> **A**: Max number of nodes 한도를 올린다. 단 노이즈를 일부러 키운 바이너리일 수 있으니, 왜 큰지(junk, 점프 테이블)를 같이 본다.

---

## Background
Hex-Rays 사의 상용 도구이고 Free 판은 기능이 제한된다. 디컴파일러(Hex-Rays)는 별도 구성요소다.

## External Refs
- Hex-Rays IDA 공식 문서
