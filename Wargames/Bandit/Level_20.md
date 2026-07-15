---
date: 2026-07-15
wargame: Bandit
level: 20
title: "Bandit Level 20 → 21"
difficulty: ★★★
time_spent: 15min
tags: [bandit, linux, network, netcat, setuid, background-process]
status: 🟡 developing
tools_used: [nc, suconnect, printf, tmux]
new_concepts: [Client_Server_Model, Privileged_Ports]
prerequisites: [Level_19]
---

# Bandit Level 20 → 21

## [Phase 1] Executive Summary

- **Goal**: setuid 바이너리 `suconnect`가 `localhost:<port>`에 **클라이언트**로 붙어 현재(bandit20) password를 받으면 bandit21 password를 반환 → 내가 **리스너(서버)**를 띄워 bandit20 password를 흘려보내고 suconnect를 연결
- **Key Skill**: `nc -l -p <unprivileged-port>` 리스너 + `./suconnect <port>` 를 **동시 실행**(background/tmux). 반환된 password는 **리스너 출력**으로 돌아옴
- **Tags**: `[Client_Server_Model]`, `[Privileged_Ports]`, `[Netcat]`, `[Setuid]`

[Cognitive Validation]
- **Limit Test**: 포트를 <1024로 잡으면 bind에 root 필요 → `Permission denied`(523 실패). ≥1024면 OK(9999). **1024가 privileged/unprivileged 경계**.
- **Control Knob**: 지배 변수는 ① 포트가 unprivileged인가 ② 리스너가 suconnect 접속 순간 **살아있는가**. 둘 다 만족해야 handshake 성립.
- **Nullity**: 리스너 없이 suconnect만 → `connection refused`(붙을 서버 없음). 리스너만 있고 suconnect 안 돌리면 아무 일 없음. **두 프로세스 동시성**이 필수.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**Client-server 2-프로세스 협업 + setuid**. Level 14(넌 클라이언트, `nc → 서버`)의 **역할 반전** — 여기선 **네가 서버(daemon, `nc -l`)**이고 `suconnect`가 클라이언트로 붙는다. "누가 listen하고 누가 connect하나"를 뒤집는 것이 핵심 전환.

### 2. Definition (Formal, EN)

A **listening server** (`nc -l -p P`) binds a socket to port P and blocks on `accept()`, awaiting inbound connections. A **client** (`suconnect P`) initiates `connect()` to `localhost:P`. Ports **below 1024 are privileged** — binding requires `CAP_NET_BIND_SERVICE` (normally root); an unprivileged user gets `EACCES`. `suconnect` is a setuid-bandit21 binary: upon reading bandit20's password from the connection it writes bandit21's password **back over the same socket**.

### 3. Intuition (KR)

**전화 통화**다. 한쪽이 전화를 **받으려 대기**(`nc -l` = 서버), 다른 쪽이 **건다**(`suconnect` = 클라이언트). 받는 쪽(나)이 bandit20 password를 말하면, 거는 쪽(suconnect)이 확인하고 bandit21 password를 **되말해준다** → 그 답은 **받는 쪽(리스너) 수화기(=화면)**에 들린다. suconnect 창엔 "보냈다"는 확인만 뜬다.

### 4. Theory (Mechanism)

1. 리스너가 포트 P에 bind → `accept()`에서 블록. suconnect가 `connect()` → 연결 성립.
2. 리스너가 bandit20 password 한 줄 전송(`printf | nc` 또는 `nc < 파일`). suconnect가 그걸 read → 현재 레벨 password와 비교.
3. **일치 시** suconnect가 bandit21 password를 **같은 TCP 연결로 write** → 반대편 `nc`가 받아 **stdout에 출력**.
4. **Privileged port 제약**: P<1024 bind는 root 권한 필요 → bandit20(unprivileged)은 `Permission denied`. P≥1024(9999)면 성공.
5. **동시성 제약**: 리스너가 `accept` 대기 중일 때 suconnect가 붙어야 함 → background(`&`) / tmux / 두 터미널로 병행.

인과: 리스너가 bandit20 pw 서빙(조건) → suconnect가 connect·read·검증(B) → 일치 → bandit21 pw를 연결로 반송(C) → 리스너 stdout에 출력(D).

### 5. Solution

```bash
bandit20@bandit:~$ ls
suconnect

bandit20@bandit:~$ ./suconnect
# Usage: ./suconnect <portnumber>
# This program will connect to the given port on localhost using TCP.
# If it receives the correct password from the other side, the next password is transmitted back.

# --- 삽질: privileged port(523 < 1024) → bind에 root 필요 ---
bandit20@bandit:~$ printf "<password masked>\n" | nc -l -k -p 523
# nc: Permission denied          ← 523은 privileged port(<1024). unprivileged 계정 bind 불가
bandit20@bandit:~$ nc -lp 9999   # 9999(≥1024)는 bind 성공(테스트 후 ^C)

# --- 정상: unprivileged port + 2-프로세스 동시 (tmux 사용) ---
# (창 A) 리스너: bandit20 password를 서빙하며 대기
bandit20@bandit:~$ printf "<password masked>\n" | nc -l -k -p 9999
#   -l : listen(서버 모드) / -k : 연결 끊겨도 계속 listen / -p 9999 : 포트

# (창 B) suconnect를 클라이언트로 그 포트에 연결
bandit20@bandit:~$ ./suconnect 9999
Read: <password masked>                    # ← 리스너가 보낸 bandit20 password를 suconnect가 읽음
Password matches, sending next password    # ← 일치 → bandit21 password를 '창 A(리스너)'로 전송

# ★ bandit21 password는 '창 A(nc 리스너)의 출력'에 뜬다 (suconnect 창 아님!)
#   창 A: <password masked>   ← bandit21 (Level 21) password
```

> [!warning] Password Masking & Orphan Process
> bandit20/bandit21 password 마스킹. 또 **응답 password가 나타나는 곳은 `nc` 리스너 화면**(suconnect 창은 확인 메시지만) — tmux/background 세션이면 그 세션을 열어 확인. 그리고 `-k`로 띄운 `nc`는 계속 살아남으니(orphan) 확인 후 **종료**하라(배너의 "don't leave orphan processes").

### 6. Why It Works

Level 14에서 네가 **클라이언트**로 서버에 password를 던졌다면, 여기선 **네가 서버**가 되어 password를 서빙하고 `suconnect`(클라이언트)가 그걸 검증한다 — 역할이 뒤집혔을 뿐 소켓 통신 원리는 동일. suconnect가 setuid-bandit21이라 검증 통과 시 bandit21 password를 **연결 반대편(=네 리스너)으로** 되보내므로, 답은 리스너 stdout에 뜬다. 포트를 ≥1024로 잡아야 unprivileged 계정이 bind할 수 있고, 리스너와 suconnect가 **동시에** 살아있어야 handshake가 성립한다.

### 7. Edge Cases / Limitation

- **Privileged ports (<1024)**: bind에 root(`CAP_NET_BIND_SERVICE`) 필요 → 523·80·443 등은 unprivileged 계정 실패. 임의 포트는 ≥1024.
- **동시성**: 리스너를 background(`&`)로 먼저 띄우거나 tmux/두 터미널. 순서상 **리스너가 accept 대기 상태**여야 suconnect가 붙음.
- **응답 위치 착각**: bandit21 password는 suconnect가 아니라 **리스너 출력**에. (이번 세션에서 tmux `openport` 세션에 password가 남음.)
- **orphan process**: `-k`는 nc를 연결 후에도 유지 → `-k` 빼면 1회 연결 후 자동 종료(더 깔끔). 남은 nc는 `kill`로 정리.

---

## [Phase 3] Formal Summary (EN)

> [!definition] Privileged Ports
> TCP/UDP ports 0–1023 are "privileged" (a.k.a. well-known/system ports); binding a listening socket to one requires `CAP_NET_BIND_SERVICE` (held by root). Ports ≥1024 are unprivileged and bindable by any user. ∴ `nc -l -p 523` fails with `Permission denied` for bandit20 while `-p 9999` succeeds.

> [!theorem] Reply travels back to the listener
> In a bidirectional TCP session, data written by either peer is readable by the other. `suconnect` (client) writes the next password into the connection after verification; the peer at the other end is `nc -l` (server), which prints received bytes to stdout. ∴ the next password surfaces on the **listener's** output, not the client's. □

---

## [Phase 4] Better Methods

**Current approach** (used above): tmux 두 창 — 창 A `printf|nc -l`, 창 B `./suconnect`. 동작하나 창 전환 필요 + 응답 위치 헷갈림.

**Alternative 1**: 한 터미널 background 잡 (파일에서 password 서빙)
```bash
nc -l -p 9999 < /etc/bandit_pass/bandit20 &    # 리스너를 background로 (& = 백그라운드 실행)
./suconnect 9999                                # 즉시 트리거 → bandit21 password가 bg nc 출력으로 프린트
#   < /etc/bandit_pass/bandit20 : password를 파일에서 stdin으로 (spoiler-free, printf보다 안전)
#   -k 없음 : 1회 연결 후 nc 자동 종료 → orphan 방지
```
Trade-off: 단일 터미널, spoiler 없음, orphan 없음. 응답도 같은 화면. **가장 실용적.**

**Alternative 2**: 서브셸 그룹으로 순서 보장
```bash
( nc -l -p 9999 < /etc/bandit_pass/bandit20 & sleep 1; ./suconnect 9999; wait )
#   sleep 1 : 리스너가 bind·accept 대기에 들어갈 시간을 줌(race 방지)
```
Trade-off: 리스너 준비 타이밍을 명시적으로. 스크립트화에 유리.

**Most elegant**:
```bash
nc -l -p 9999 < /etc/bandit_pass/bandit20 & ./suconnect 9999
```
Why elegant: 리스너(파일 서빙, background) + 클라이언트를 한 줄로. password 비노출 + 단일 화면 + `-k` 없어 자동 정리.

---

## [Phase 5] Lessons Learned

1. **Client/server 역할 반전**: Level 14는 클라이언트, Level 20은 **서버(`nc -l`)**. suconnect가 클라이언트로 붙는다.
2. **Privileged ports (<1024)**: bind에 root 필요 → `Permission denied`(523). unprivileged 계정은 **≥1024**(9999 등).
3. **두 프로세스 동시성**: 리스너가 살아있을 때 suconnect가 붙어야 → background(`&`)/tmux/두 터미널.
4. **응답은 리스너 화면에**: suconnect가 password를 연결 너머로 되보내니 bandit21 password는 `nc` 리스너 출력에 뜬다(suconnect 창 아님).
5. **orphan process 정리**: `-k` 빼서 1회 종료 or `kill`. 배너 규칙 준수.

### Quiz

**Q**: (a) `nc -l -p 523`은 `Permission denied`인데 9999는 되는 이유. (b) 리스너와 suconnect를 **한 터미널**에서 돌리려면? (c) bandit21 password는 **어느 프로세스** 출력에 나타나며 그 이유는?

> [!tip]- 풀이
> **(a)** 523<1024는 **privileged port** — bind에 `CAP_NET_BIND_SERVICE`(보통 root) 필요. bandit20은 unprivileged → `EACCES`. 9999≥1024는 누구나 bind 가능.
>
> **(b)** 리스너를 background(`&`)로 먼저 띄우고 suconnect 실행: `nc -l -p 9999 < /etc/bandit_pass/bandit20 & ./suconnect 9999`. (리스너가 accept 대기 상태여야 suconnect가 붙음 — 필요 시 `sleep 1`.)
>
> **(c)** **리스너(`nc`) 출력**. suconnect는 받은 password가 맞으면 bandit21 password를 **같은 TCP 연결로 되돌려** write하고, 그 반대편이 `nc`라 nc가 stdout에 출력. suconnect 창엔 `sending next password`만.
>
> 핵심: 양방향 소켓에서 **"누가 마지막에 write하고 누가 read하나"**를 따라가면 데이터가 어느 화면에 뜨는지 안다.

> [!flashcard]
> **Q**: `nc -l -p 523`이 `Permission denied`인 이유는?
> **A**: 1024 미만은 privileged port — bind에 root(`CAP_NET_BIND_SERVICE`) 필요. unprivileged 계정은 ≥1024 포트를 써야 한다.

> [!flashcard]
> **Q**: Level 20에서 bandit21 password는 어느 프로세스 출력에 뜨나?
> **A**: `nc` **리스너(서버)** 출력. suconnect가 검증 후 password를 연결 너머로 되보내고, 그 반대편 nc가 받아 출력. suconnect 창엔 확인 메시지만.

---

## Links

### Tools Used
- [[Tools/nc]]
- [[Tools/tmux]]
- [[Tools/printf]]

### Concepts Introduced (first encountered here)
- [[Concepts/Network/Client_Server_Model]]
- [[Concepts/Network/Privileged_Ports]]

### Concepts Applied (reused from earlier)
- [[Concepts/Network/Netcat]] (Level 14 — 클라이언트 → 여기선 서버로 역할 반전)
- [[Concepts/Linux/Setuid]] (Level 19 — suconnect도 setuid 바이너리)

### Navigation
- **Prerequisite**: [[Level_19]]
- **Next**: [[Level_21]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit21.html
- `nc(1)` — `-l`/`-k`/`-p`; privileged ports (IANA well-known 0–1023)
- job control — background `&`, `wait`
