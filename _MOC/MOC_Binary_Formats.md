---
moc: true
scope: Binary_Formats
last_updated: 2026-08-30
tags: [moc, binary, file-format, forensics, integrity]
---

# MOC — Binary Formats & Forensics

> Map of Content for **바이너리 포맷 분석**. 특정 워게임이 아니라 *주제* 단위 MOC다 — 이 개념군은 여러 게임·문제에 걸쳐 재사용되고, 일부 출처는 no-publish 트리라 공개 워게임 MOC에 걸 수 없다.
> Theme: **선언(declared) vs 실측(measured)**. 헤더는 데이터를 설명하고, 조작된 파일은 설명과 대상이 어긋난다.
> **Rule**: This file MUST contain ZERO `[[Wiki_Links]]` outside of mermaid code blocks (graph hygiene).

## Concept Dependency Graph

```mermaid
graph TD
    SIG[File_Signatures<br/>정체 · 채널 손상 검출]
    ENC[Binary_Number_Encoding<br/>bit·byte·hex·endian·struct]
    TWO[Twos_Complement<br/>signed 의 실체]
    CHK[Chunked_Container_Formats<br/>TLV · length-prefix]
    SUM[Checksum_Hash_MAC<br/>무결성의 3층위]
    FOR[Binary_Format_Forensics<br/>5개 검증 축 · 오라클 설계]
    IO[File_IO_And_Cursor<br/>fd·커서·모드·원자적 교체]

    T_XXD[Tools/xxd<br/>돋보기]
    T_GREP[Tools/grep -abo<br/>오프셋 검색]
    T_STR[Tools/strings<br/>미작성]

    ENC -->|Prerequisite| CHK
    TWO -->|Prerequisite| ENC
    ENC -->|Prerequisite| SUM
    SIG -->|Leads_To| CHK
    CHK -->|Leads_To| FOR
    SUM -->|Leads_To| FOR
    SIG -->|Leads_To| FOR
    IO -->|Prerequisite| FOR
    SIG -.->|같은 손상의 두 얼굴| IO

    FOR -.->|uses| T_XXD
    FOR -.->|uses| T_GREP
    FOR -.->|uses| T_STR
    ENC -.->|read by| T_XXD

    click SIG "Concepts/Linux/File_Signatures.md"
    click ENC "Concepts/Binary/Binary_Number_Encoding.md"
    click TWO "Concepts/Binary/Twos_Complement.md"
    click CHK "Concepts/Binary/Chunked_Container_Formats.md"
    click SUM "Concepts/Crypto/Checksum_Hash_MAC.md"
    click FOR "Concepts/Binary/Binary_Format_Forensics.md"
    click IO  "Concepts/Linux/File_IO_And_Cursor.md"
    click T_XXD "Tools/xxd.md"
    click T_GREP "Tools/grep.md"
```

> Legend: solid arrow = prerequisite/leads-to, dotted arrow = uses tool / cross-cutting relation.
> `Tools/strings` 는 아직 미작성 — 그래프에 남겨둔 것은 **미해결 to-do 를 지우지 않기 위해서**다.

## The Five Axes (핵심 프레임)

이 MOC 전체가 봉사하는 하나의 절차. 어떤 컨테이너 포맷에도 적용된다.

| # | 축 | 무엇을 대조하나 | 주로 쓰는 노트 |
|---|---|---|---|
| 1 | **정체** | 시그니처 vs 실제 내용 | File_Signatures |
| 2 | **길이** | 선언 길이 vs 레코드 체인 | Chunked_Container_Formats |
| 3 | **무결성** | 저장 체크섬 vs 재계산 | Checksum_Hash_MAC |
| 4 | **구성** | 필수/순서/개수 규칙 위반 | Chunked_Container_Formats |
| 5 | **정합성** | 선언값에서 계산한 양 vs 실측량 | Binary_Format_Forensics |

**축 1~4는 "규격 위반"을 잡고, 축 5는 규격을 통과한 조작까지 잡는다.**

## Concept Metadata Table

| Note | Domain | Tier | Status | Mastery | 핵심 |
|---|---|---|---|---|---|
| File_Signatures | Linux | **full atom** | 🟡 developing | 0 | magic number = 정체 선언 + 채널 무결성 카나리아 |
| Binary_Number_Encoding | Binary | lite | 🟡 developing | 55 | 바이트는 자기 폭·엔디언·부호를 말해주지 않는다 |
| Twos_Complement | Binary | lite | 🟢 solid | 70 | `~x+1 = 2^N−x`, 그리고 그게 유일한 해인 이유 |
| Chunked_Container_Formats | Binary | lite | 🟡 developing | 45 | TLV — 컨테이너 층과 레코드 층의 분리 |
| Checksum_Hash_MAC | Crypto | lite | 🟡 developing | 55 | 검출 ≠ 정정, 일치는 아무것도 증명 못 한다 |
| Binary_Format_Forensics | Binary | lite | 🟡 developing | 50 | 5개 축 · 오라클 설계 · 명세서 읽기 |
| File_IO_And_Cursor | Linux | lite | 🟡 developing | 55 | fd·커서·`O_TRUNC`·원자적 교체·`with` |

## Tool Metadata Table

| Tool | Status | 이 스코프에서의 역할 |
|---|---|---|
| xxd | 🟢 written | 코드가 지목한 좁은 구간을 눈으로 확인하는 **돋보기** |
| grep | 🟢 written | `-abo` 로 원본 바이트에서 마커 오프셋 수집 (독립 검증 오라클) |
| strings | 🔴 미작성 | 패턴을 모를 때의 정찰. `Concepts/Linux/Strings_Extraction` 은 이미 존재 |
| file | 🔴 미작성 | 시그니처 매칭. Bandit L04/L12/L26 에서 이미 다수 참조 중 |

## Status Legend
- 🔴 raw — 미작성 / 캡처만 됨
- 🟡 developing — lite 노트 존재, `/deep` 승격 여지 있음
- 🟢 solid — 내용 충분, 재사용 검증됨
- ⭐ mastered — flashcard 회상 검증 완료

## Update Protocol

이 스코프에 새 노트를 추가할 때:
1. mermaid 그래프에 노드 + `click` 경로 추가, 의존 화살표 연결
2. 위 두 메타데이터 테이블 갱신
3. 다섯 축 표에서 어느 축에 봉사하는지 명시
4. `last_updated` 갱신
5. 출처가 no-publish 트리면 **공개 노트에 그 경로를 링크하지 말 것** — `External:` 평문으로만 표기

## Links

- **선행**: External: `_MOC/MOC_Bandit` (L04 file / L09 strings / L12 압축 중첩에서 씨앗)
- **적용처**: External: 로컬 전용 워게임 트리 (no-publish)
- **다음 방향**: External: `Roadmap_Post_Bandit`
