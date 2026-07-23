---
date: 2026-07-23
wargame: Leviathan
level: 0
title: "Leviathan Level 0 → 1"
difficulty: ★☆☆
time_spent: 00min
tags: [leviathan, linux, binary-analysis]
status: 🔴 raw
tools_used: []
new_concepts: []
prerequisites: []
---

# Leviathan Level 0 → 1

## [Phase 1] Executive Summary

- **Goal**: `leviathan0`으로 접속해 홈 디렉터리를 탐색, `leviathan1`의 password를 찾는다. **Leviathan은 레벨 지시문이 없다** — 무엇을 찾을지/어떻게 접근할지 **추론하는 것 자체가 훈련**(Bandit에서 "셸 쓰기"였다면 여기부턴 "상자 열어 뜯어보기").
- **Key Skill**: <풀이 후 채움 — 예상: 숨김 파일/디렉터리 탐색, 파일 내용·권한 조사>
- **Tags**: <풀이 후 채움>

[Cognitive Validation]
- **Limit Test**: <변수를 0 또는 ∞로>
- **Control Knob**: <지배 변수와 효과>
- **Nullity**: <kernel/trivial 케이스>

---

## [Phase 2] Deep Dive

### 1. Concept Categorization
<이 level이 다루는 본질 카테고리>

### 2. Definition (Formal, EN)
<핵심 개념 정밀 정의>

### 3. Intuition (KR)
<한 줄 비유 + 직관>

### 4. Theory (Mechanism)
<왜 작동하는가>

### 5. Solution

```bash
# 접속 (Leviathan 포트 = 2223, Bandit의 2220 아님)
$ ssh leviathan0@leviathan.labs.overthewire.org -p 2223
# 초기 pw: OTW 공개 (= 계정명 leviathan0). 이후 레벨 pw는 <password masked>.

# 쓰기 가능한 작업 디렉터리 (홈은 write 불가일 수 있음)
$ mktemp -d                              # /tmp 아래 하드-투-게스 폴더

# ── 풀이 단계 (터미널 출력 paste 시 자동 채움) ──
leviathan0@leviathan:~$ <command_1>
<output_1>

# 다음 레벨 password: <password masked>
```

> [!warning] Password Masking & ToS
> `leviathan1` password는 **반드시** `<password masked>`. OTW ToS: 기법만 기록, 답은 넘기지 않는다. (초기 leviathan0 pw는 OTW가 공개하는 값이라 별개.)

### 6. Why It Works
<단계별 mechanism>

### 7. Edge Cases / Limitation
<실패 조건 / 대안>

---

## [Phase 3] Formal Summary (EN)

> [!definition] {{Concept}}
> <formal definition>

---

## [Phase 4] Better Methods

**Current approach**:
```bash
<original>
```

**Alternative**:
```bash
<alternative>
```
Trade-off: <pros vs cons>

---

## [Phase 5] Lessons Learned

1. <교훈>

### Quiz

**Q**: <grad-level question>

> [!tip]- 풀이
> <answer>

> [!flashcard]
> **Q**: <core question>
> **A**: <1-2 sentence answer>

---

## Links

### Tools Used
- <풀이 후: [[Tools/ltrace]] / [[Tools/strace]] / [[Tools/gdb]] / [[Tools/objdump]] 등>

### Concepts Introduced / Applied
- <재적용 예상: [[Concepts/Linux/Static_Binary_Triage]], [[Concepts/Linux/Setuid]], [[Concepts/Linux/Process_Creation]]>

### Navigation
- **Prerequisite**: Bandit 졸업 (External: `_MOC/MOC_Bandit`)
- **Next**: [[Level_01]]
- **MOC**: [[_MOC/MOC_Leviathan]]

### External References
- Leviathan Official: https://overthewire.org/wargames/leviathan/
- 방향 근거: External: `Roadmap_Post_Bandit`
