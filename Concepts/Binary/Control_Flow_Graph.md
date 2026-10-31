---
date: 2026-10-31
domain: Binary
topic: Control_Flow_Graph
tags: [binary, reverse-engineering, disassembly, cfg, obfuscation]
status: 🟡 developing
note_tier: lite
mastery: 40
first_encountered: "External: local-only wargame tree (no-publish) — 디스어셈블러의 graph 뷰 자체가 그림이 되도록 설계된 바이너리"
reapplied_in: []
---

# Control Flow Graph (CFG)

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> Captures what was actually asked about / dug into. Promote to a full atom via `/deep` when it earns the deep treatment.

## Definition (Formal, EN)

A **basic block** is a maximal straight-line instruction sequence with one entry (its first instruction) and one exit (its last). A **CFG** is a directed graph `G = (B, E)` whose nodes are basic blocks and whose edges are possible control transfers. A disassembler builds `E_static` by *analysing code*, not by running it, so `E_static ⊇ E_runtime`: it must include every edge it cannot prove impossible.

## Intuition (KR)

실행 경로의 **지도**다. 디스어셈블러는 프로그램을 돌려 보지 않고 지도를 그리므로, "갈 수도 있는 길"은 전부 그린다. 실제로 지나는 길은 그중 일부다.

## Key Points (무엇을 팠나)

### A. 블록 경계는 점프가 만든다
- 블록은 **분기 명령으로 끝나고**, **분기 대상이 되는 주소에서 시작한다**. 한 블록 안에는 분기 대상이 없다.
- 그래서 점프가 많을수록 블록이 잘게 쪼개져 노드 수가 늘어난다.

### B. 과대근사 (over-approximation) — 왜 지도가 실제보다 크다
- 정적 분석이 "이 분기는 절대 안 간다"를 **증명하지 못하면** edge 를 남긴다. 안전한 쪽(없는 길을 그리는 쪽)으로 틀리는 것이다.
- 반대로 `E_static ⊆ E_runtime` (있는 길을 빠뜨림)이면 도구가 신뢰를 잃는다.

### C. Jump table switch idiom
- 컴파일러는 조밀한 `switch` 를 **주소 배열**로 컴파일한다: `jmp [T + idx*8]` (64비트) 또는 `idx*4` (32비트).
- 디스어셈블러는 `idx` 가 무슨 값인지 모르면 **테이블 항목 전부**를 분기 대상으로 등록한다 → 케이스 수만큼 edge 가 생긴다.
- 실제 실행에서 `idx` 가 상수(예: 0)이면 한 케이스만 도는데, **정적 그래프는 전부 그린다.** 이것이 "실행 불가 코드가 그래프에 대량으로 나타나는" 대표적 원인이다.

### D. Junk code 와 def-use
- 난독화는 **결과에 영향이 없는 명령**을 끼워 넣는다: 쓰고 안 읽는 값(dead store), 다음 명령으로 가는 `jmp $+5`.
- "무의미하다"의 판정 기준은 **def-use**다 — 어떤 값을 정의(def)했는데 이후 사용(use)이 없는가.
- `lea` 는 주소만 계산하고 **메모리를 읽지 않는다**. 그래서 `lea` 는 메모리 부작용이 없다.
- 반복 패턴이 **깨지는 곳**이 진짜 코드일 확률이 높다 (패턴 매칭으로 노이즈를 걸러낸다).

### E. 그래프 자체가 데이터일 수 있다
- 노드 배치가 그림을 이루도록 블록과 edge 를 설계한 바이너리가 있다. 코드는 한 줄도 안 읽고 **graph overview 로 보는 것**이 답이다.
- 도구 한계(노드 수 상한)에 걸리면 한도를 올려야 한다. "한도를 올리는 건 권장되지 않는다"는 일반론이 이 경우에는 틀렸다.

## Encountered / Applied In

- External: local-only wargame tree (no-publish) — 대량의 junk 블록과 큰 switch 로 그래프가 거대해진 바이너리. 실행 경로는 한 케이스뿐이었다.

## Related

- [[Concepts/Binary/Stack_Frame_And_Call_Ret]] — 함수 하나의 프레임. CFG 는 그 함수 안의 **분기 구조**다.
- [[Concepts/Binary/ELF_Sections_And_Relocation]] — 점프 테이블이 놓이는 `.rodata` 와 섹션 구조.
- [[Tools/ida]] — graph 뷰와 노드 상한.
- [[Tools/objdump]] — 선형 스윕 disassembly (CFG 가 아니라 주소 순서).
- [[Concepts/Binary/UTF8_Encoding]] — 같은 바이너리에서 **데이터** 영역을 읽는 쪽 (코드 노이즈 vs 데이터 인코딩).

## Expand Later (`/deep` candidates)

- **선형 스윕 vs 재귀 하강** disassembly — 어느 쪽이 junk 에 속는가
- **Opaque predicate** — 항상 참/거짓인데 도구가 증명 못 하는 조건
- **Control flow flattening** — 모든 블록을 dispatcher 하나로 묶는 난독화
- 동적 분석(trace)으로 `E_runtime` 만 뽑는 법
