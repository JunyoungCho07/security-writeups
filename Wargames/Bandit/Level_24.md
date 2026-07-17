---
date: 2026-07-17
wargame: Bandit
level: 24
title: "Bandit Level 24 → 25"
difficulty: ★★☆
time_spent: 20min
tags: [bandit, linux, brute-force, netcat, shell-loop, brace-expansion, connection-reuse]
status: 🟡 developing
tools_used: [nc, bash-loop, echo, sort, uniq]
new_concepts: [Brute_Force_Search, Connection_Batching]
prerequisites: [Level_23]
---

# Bandit Level 24 → 25

## [Phase 1] Executive Summary

- **Goal**: `localhost:30002`의 데몬이 `<bandit24 password> <4-digit PIN>` 한 줄을 받아 검증한다. PIN은 `0000`–`9999`(만 개). password는 이미 알고(Level 24), 모르는 건 **PIN 하나**뿐 → **전수(brute-force)** 로 만 개를 다 던진다.
- **Key Skill**: **exhaustive search + single-connection batching**. bash `for`로 만 개의 `<pw> <PIN>` 줄을 생성, **한 번의 TCP 연결**에 통째로 흘려보낸다(`nc … < file`). 매 추측마다 재연결(=만 번의 handshake)하는 순진한 방식과의 갈림이 이 레벨의 실질적 교훈.
- **Tags**: `[Brute_Force_Search]`, `[Connection_Batching]`, `[Netcat]`, `[Shell_Fundamentals]`(brace expansion)

[Cognitive Validation]
- **Limit Test**: PIN 자릿수를 4→8로 늘리면 공간이 10⁴→10⁸ = 1억. 단일연결 배칭은 여전히 유효하나 입력 파일이 ~GB로 부풀어 brute-force의 실용성이 붕괴 → **"작아서 뚫린다"**. 반대로 1자리(10개)면 손으로도 됨. 4자리는 "손으론 안 되지만 기계론 순식간"인 의도된 지점.
- **Control Knob**: 지배 변수 = **TCP 연결 횟수**. 추측당 새 연결(10000 handshake) → 수십 초~분 + rate-limit 위험. 단일 연결 재사용(handshake 1회) → 처리량 한계까지 거의 즉시. 속도를 가르는 건 crypto도 CPU도 아닌 **연결 setup 비용**.
- **Nullity**: 데몬이 **틀린 추측 1회마다 연결을 끊는** 설계였다면 배칭이 불가능 → 매번 재연결 강제. 실제 데몬은 **한 연결에서 줄 단위로 계속 읽으므로** 배칭이 성립한다. 이 "연결 유지" 속성이 전략의 전제.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**Online brute-force against a network oracle**. Level 23까지가 "권한/파일 트릭"이었다면 여기선 순수 **탐색(search)** 이다. 비밀 공간(10⁴)이 충분히 작아 전수 가능하고, 검증자가 네트워크 서비스(oracle)라 **online** 공격이다(offline crack과 대비 — 해시를 손에 쥐고 로컬에서 때리는 게 아니라 매 추측을 서버에 물어봐야 함). 실전 관점의 핵심은 "탐색을 어떻게 **빠르게** 전달하느냐" = 연결 재사용.

### 2. Definition (Formal, EN)

A daemon on `127.0.0.1:30002` implements a verification oracle `V(pw, pin) → {accept, reject}` and reads **newline-delimited guesses on a single persistent TCP connection**. The password `pw` is known; the pin ∈ `{0000,…,9999}` (|space| = 10⁴) is unknown. The attack enumerates the entire pin space, emitting one line `"<pw> <pin>"` per candidate, and pipes all 10⁴ lines into one connection. The daemon echoes `reject` for each wrong line and `accept` (revealing the next password) for the one correct line; the response set is scanned for the single non-`Wrong!` line.

### 3. Intuition (KR)

**만능열쇠 꾸러미를 문에 다 꽂아본다.** 자물쇠(데몬)가 "한 번 열려면 열쇠를 하나씩 넣어봐"라고 하는데, 그 자물쇠가 **열쇠를 넣을 때마다 문을 닫지 않고** 계속 받아준다. 그러면 만 개 열쇠를 **한 번에 주르륵** 밀어넣고, "찰칵" 소리 난 하나만 골라내면 된다. 열쇠 넣을 때마다 문을 새로 여닫으면(재연결) 느리지만, 문이 계속 열려 있으니(단일 연결) 순식간이다.

### 4. Theory (Mechanism)

성공의 인과 사슬:

1. **후보 생성** — `{0000..9999}` brace expansion이 shell 레벨에서 만 개 토큰으로 전개. 시작값 `0000`의 leading zero 덕에 **자동 zero-pad**(전부 4자리 폭). 각 토큰 앞에 알려진 password를 붙여 `"<pw> <pin>"` 줄을 만든다.
2. **단일 연결 주입** — `nc localhost 30002 < all`: `nc`의 **stdin을 파일 `all`로 redirect**. `nc`는 그 스트림을 소켓으로 그대로 흘리고, 데몬은 한 연결에서 줄 단위로 읽어 각 줄을 `V`에 통과시킨다. TCP handshake는 **딱 한 번**.
3. **응답 분리** — 데몬은 틀린 줄마다 `Wrong! …`, 맞은 줄에 `Correct!` + 다음 password를 반환. 응답 만여 줄 중 **유일하게 다른** 한 블록을 골라낸다(`sort | uniq -u` 또는 `grep -v Wrong`).

### 5. Solution

```bash
# SSH connection
$ ssh -p 2220 bandit24@bandit.labs.overthewire.org
# Password: <password masked>

# 0) 작업 디렉터리 (추측하기 어려운 이름 — OTW 권고)
bandit24@bandit:~$ D=$(mktemp -d); cd "$D"

# 1) 만 개의 "<pw> <PIN>" 줄 생성 → 파일 all
bandit24@bandit:~$ for i in {0000..9999}; do
>     echo "<bandit24 password masked> $i" >> all
> done
#   {0000..9999} : brace expansion. 시작값 0000의 leading zero → 전 구간 4자리 zero-pad 자동
#   echo "... $i" : password + 공백 + PIN 한 줄. >> all : append (매 반복마다 끝에 덧붙임)
bandit24@bandit:~$ head -3 all
<bandit24 password masked> 0000
<bandit24 password masked> 0001
<bandit24 password masked> 0002
bandit24@bandit:~$ wc -l all
10000 all                              # 공간 전체가 정확히 만 줄

# 2) 단일 연결로 만 줄을 데몬에 흘림 → 응답을 log로 저장
bandit24@bandit:~$ nc localhost 30002 < all >> log
#   < all      : nc의 stdin을 파일 all로 → 소켓으로 전송 (연결 1회)
#   >> log     : 데몬 응답(만여 줄: 대부분 Wrong! + 하나 Correct!)을 파일로

# 3) 만 줄 응답에서 "유일하게 다른" 한 줄(=Correct!)만 추출
bandit24@bandit:~$ sort log | uniq -u
Correct!
I am the pincode checker for user bandit25. ...
The password of user bandit25 is <password masked>   # ← Level 25 password
#   sort       : uniq는 '인접' 중복만 지우므로 먼저 정렬해 같은 줄을 뭉침
#   uniq -u    : '정확히 1번만' 등장한 줄만 출력 → Wrong!(9999회 반복) 제거, Correct! 블록만 남음
```

> [!warning] Password Masking
> bandit24 password(생성 명령의 `echo` 안)와 bandit25 password(Correct! 응답) **둘 다** 마스킹. 생성 스크립트에 password가 리터럴로 박히므로, 노트에 옮길 땐 `echo` 인자까지 `<… masked>`로 치환해야 한다.

### 6. Why It Works

비밀 공간이 **10⁴로 유한하고 작다**. 검증자가 online oracle이라 매 추측을 서버에 물어야 하지만, 데몬이 **한 연결에서 무한정 줄을 받아주므로** "만 번 물어보기"의 비용이 "만 번 연결"이 아니라 "**한 번 연결 + 만 줄 스트리밍**"으로 접힌다. 병목은 crypto가 아니라 **왕복(round-trip)/연결 setup**이고, 배칭이 그 왕복을 제거한다. brace expansion은 후보 생성을, stdin redirect는 전달을, `uniq -u`는 신호 분리를 담당하는 3-단 파이프라인.

### 7. Edge Cases / Limitation (= 이번 세션 삽질 로그)

- **파이프라인 미연결 버그(핵심 실수)**: 첫 스크립트가 이랬다 —
  ```sh
  #!/bin/bash
  nc localhost 30002          # ← 루프 '위'에 단독으로
  for i in {0000..9999}; do echo "<pw> $i"; done
  ```
  `nc`가 **독립 명령**으로 먼저 떠서 자기 stdin(=터미널)을 기다리고, 루프의 `echo`는 nc가 죽은 **뒤에** 터미널로 출력됐다. 둘이 **파이프로 안 이어짐**(순차 실행된 별개 명령). → 교훈: 루프 출력을 nc에 먹이려면 `for …; done | nc …`(파이프라인) 또는 파일 경유 `nc < file`. **인접 배치 ≠ 연결.**
- **`uniq -u`의 취약성**: "1번만 등장한 줄"로 거르는 건 **운이 따른 필터**다. 정답 응답이 `Wrong!`과 한 글자만 달랐거나, 빈 줄이 우연히 1회 섞였다면 오검. 더 견고: `grep -v Wrong`(내용으로 배제) 또는 `grep -iA2 correct`.
- **zero-pad 누락**: `for ((i=0;i<10000;i++))`나 `seq 0 9999`는 `0`,`1`,…로 나와 4자리 포맷이 깨진다(`<pw> 1` ≠ `<pw> 0001`). `{0000..9999}`(brace) 또는 `seq -w`(equal width) 또는 `printf "%04d"`로 강제.
- **연결 유지 가정**: 데몬이 틀린 줄에서 끊는 설계였다면 배칭 불가 — 이 레벨은 유지형이라 성립. 실전 서비스는 rate-limit/lockout이 흔하므로 online brute-force는 대개 이렇게 쉽지 않다.

---

## [Phase 3] Formal Summary (EN)

> [!definition] Online brute-force with connection batching
> Given a verification oracle `V: (secret) → {accept, reject}` over a **persistent** channel and a secret drawn from a finite space `S` small enough to enumerate, an attacker recovers the secret by streaming all `|S|` candidates through **one** channel setup and selecting the unique `accept` response. Cost = O(1) connection + O(|S|) transmission, versus the naïve O(|S|) connections. Feasible **iff** |S| is small **and** the oracle neither closes the channel per attempt nor rate-limits.

> [!theorem] Batching validity depends on channel persistence
> Let `c` = per-connection setup cost, `t` = per-candidate transmit cost. Naïve = `|S|·(c+t)`; batched = `c + |S|·t`. The speedup `(|S|·(c+t))/(c+|S|·t) → (c+t)/t` as |S|→∞ — i.e. batching wins by the factor `c/t + 1`, which is large exactly when connection setup dominates transmission. Requires the oracle to read multiple guesses per connection. □

---

## [Phase 4] Better Methods

**Current approach** (used above): 파일 `all` 생성 → `nc < all` → `sort | uniq -u`. 명확하지만 임시 파일 2개(`all`,`log`)와 취약한 필터.

**Alternative 1**: 파일 없이 한 파이프라인으로
```bash
P='<bandit24 password>'
for i in {0000..9999}; do echo "$P $i"; done | nc localhost 30002 | grep -v Wrong
#   생성→전송→필터를 파일 없이 스트리밍. grep -v Wrong: 'Wrong!' 없는 줄만(=Correct! 블록)
```
Trade-off: 재현/디버깅용 로그가 안 남지만 가장 간결하고 필터가 견고(`uniq -u`보다 안전).

**Alternative 2**: `seq -w` 로 생성
```bash
seq -w 0 9999 | sed "s/^/$P /" | nc localhost 30002 | grep -v Wrong
#   seq -w: 최대값(9999) 폭에 맞춰 zero-pad. sed로 각 줄 앞에 'password ' 삽입
```
Trade-off: brace expansion을 못 쓰는 상황(변수 범위 `{1..$n}` 불가)에서 유용. 파이프 단계가 하나 늘어남.

**Most elegant**:
```bash
for i in {0000..9999}; do echo "$P $i"; done | nc localhost 30002 | grep Correct -A2
```
Why elegant: 생성·전송·추출이 한 줄. `grep Correct -A2`가 성공 줄 + 뒤 2줄(다음 password 포함)만 딱 집어 `sort`/`uniq` 불필요. 원리(작은 공간 + 유지 연결 + 내용 기반 필터)를 알면 이 한 줄이 전부.

---

## [Phase 5] Lessons Learned

1. **작은 공간은 전수로 무너진다**: 10⁴는 기계에 순간. 보안 파라미터의 크기가 곧 방어력 — PIN 자릿수 하나가 실용성의 경계.
2. **online brute-force의 병목은 연결, 아니라 계산**: 매 추측을 새 연결로 보내면 handshake 비용이 지배. **한 연결 재사용(배칭)** 이 진짜 속도.
3. **"인접 배치"는 "파이프 연결"이 아니다**: `nc`를 루프 위에 그냥 써두면 둘이 안 이어진다. 데이터를 넘기려면 `|` 또는 `< file`로 **명시적 연결**.
4. **zero-pad는 생성기의 책임**: brace `{0000..}`/`seq -w`/`printf %04d` — 포맷을 처음부터 맞춰라. 뒤늦게 못 고친다.
5. **필터는 개수 아닌 내용으로**: `uniq -u`(1회 등장)는 운. `grep -v Wrong`/`grep Correct`(의미)가 견고.

### Quiz

**Q**: (a) `nc localhost 30002 < all`이 만 번 재연결하는 방식보다 빠른 근본 이유는? (b) 첫 스크립트에서 `nc`를 루프 위에 단독으로 뒀을 때 왜 아무 추측도 전송되지 않았나? (c) `uniq -u`로 정답을 고른 게 왜 견고하지 못한 필터인가?

> [!tip]- 풀이
> **(a)** TCP **연결 setup(handshake) 비용**을 만 번이 아니라 한 번만 치르기 때문. 데몬이 한 연결에서 줄 단위로 계속 읽으므로, 만 개 추측이 "만 번 연결"이 아니라 "한 연결 + 만 줄 스트리밍"으로 접힌다. 병목이 왕복이라 배칭이 그걸 제거.
>
> **(b)** `nc`가 루프와 **파이프로 안 이어진 별개 명령**이라서. `nc`가 먼저 떠서 자기 stdin(터미널)을 기다렸고, 루프의 `echo`는 nc 종료 후 터미널로 나갔다. 데이터가 nc의 stdin으로 흐르려면 `for…done | nc` 또는 `nc < file`로 명시적 연결이 필요.
>
> **(c)** `uniq -u`는 "정확히 1회 등장한 줄"을 고를 뿐 **"정답"의 의미를 모른다**. 정답 응답이 다른 줄과 우연히 겹치거나, 빈 줄·부분문자열이 1회 섞이면 오검. 내용 기반(`grep -v Wrong` / `grep Correct`)이 의도를 정확히 표현.
>
> 핵심: **작은 공간 × 유지 연결 = online brute-force가 성립하는 조건**, 그리고 신호 분리는 개수가 아니라 내용으로.

> [!flashcard]
> **Q**: online brute-force에서 추측당 새 TCP 연결 대신 단일 연결에 전부 흘려보내는 이유는?
> **A**: handshake(연결 setup) 비용을 |S|번이 아니라 1번만 치르려고. 데몬이 한 연결에서 줄 단위로 계속 읽어주면 |S|개 추측이 `연결1 + 전송|S|`로 접혀 왕복 병목이 사라진다.

> [!flashcard]
> **Q**: bash에서 `0000`–`9999`를 4자리 zero-pad로 생성하는 세 방법은?
> **A**: `{0000..9999}`(brace expansion, 시작값 leading zero로 폭 통일), `seq -w 0 9999`(equal width), 루프 안 `printf "%04d"`. `for ((i=0;…))`/`seq 0 9999`는 pad 안 됨.

---

## Links

### Tools Used
- [[Tools/nc]]
- [[Tools/sort]]
- [[Tools/uniq]]

### Concepts Introduced (first encountered here)
- [[Concepts/Security/Brute_Force_Search]]
- [[Concepts/Network/Connection_Batching]]

### Concepts Applied (reused from earlier)
- [[Concepts/Network/Netcat]] (L14 — 여기선 stdin redirect로 파일→소켓 스트리밍)
- [[Concepts/Linux/Shell_Fundamentals]] (brace expansion, `>>` append, `$()` — lite note)

### Navigation
- **Prerequisite**: [[Level_23]]
- **Next**: [[Level_25]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit25.html
- `nc(1)` — stdin→socket; `bash(1)` Brace Expansion; `seq(1)` `-w`; `uniq(1)` `-u`
