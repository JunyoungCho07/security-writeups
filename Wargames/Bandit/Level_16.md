---
date: 2026-07-15
wargame: Bandit
level: 16
title: "Bandit Level 16 → 17"
difficulty: ★★★
time_spent: 30min
tags: [bandit, linux, network, port-scanning, ssl, tls, ssh-key]
status: 🟡 developing
tools_used: [nmap, openssl, ssh, chmod, cat, vi]
new_concepts: [Port_Scanning]
prerequisites: [Level_15]
---

# Bandit Level 16 → 17

## [Phase 1] Executive Summary

- **Goal**: bandit16 password를 **localhost의 31000–32000 포트 범위** 중 (a)열려 있고 (b)SSL/TLS를 말하며 (c)echo가 아니라 **자격증명을 주는** 단 하나의 서버(=31790)에 제출 → 반환된 **bandit17 SSH private key**로 bandit17 로그인
- **Key Skill**: 포트 스캔(`nmap -sT`) → 서비스 판별(`-sV`) → SSL 제출(`openssl s_client -quiet`) → 반환 key로 `ssh -i` (L13+L14+L15 **종합**)
- **Tags**: `[Port_Scanning]`, `[Service_Enumeration]`, `[SSL_TLS]`, `[SSH_Key_Authentication]`

[Cognitive Validation]
- **Limit Test**: 스캔 범위를 1포트로 좁히면 정답을 놓치고, 0–65535 전체면 느리고 방화벽 노이즈. **31000–32000**이 주어진 탐색 공간 — 그 안에서 3중 필터.
- **Control Knob**: 지배 변수는 **3중 필터** — "열림(open) × SSL(TLS handshake) × credential(echo 아님)". 셋을 모두 만족하는 포트는 단 1개(31790).
- **Nullity**: echo 서버에 password를 제출하면? 보낸 걸 **그대로 되돌려줌** — key 없음. "내가 보낸 게 그대로 오면 오답 포트". 정답 서버만 password 검증 후 key 반환.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**Service enumeration 파이프라인** — 단일 명령이 아니라 4단 조사: ① 포트 스캔(무엇이 열렸나) → ② 프로토콜 판별(누가 SSL이냐) → ③ 행동 판별(echo냐 credential이냐) → ④ 자격증명 활용(반환 key로 로그인). 이번 세션에 배운 L13(key auth) + L14(소켓) + L15(TLS)를 **한 문제에 합성**한 종합 레벨.

### 2. Definition (Formal, EN)

**Port scanning** determines which TCP ports on a host accept connections. `nmap -sT` (TCP *connect* scan) uses the OS `connect()` syscall — no raw-socket privilege required — whereas `-sS` (SYN half-open) crafts raw packets and needs root. `-sV` then probes each open port to fingerprint the service (`echo`, `ssl/echo`, `ssl/unknown`). The target port is the unique one satisfying (open ∧ speaks-TLS ∧ ¬echo). Submitting the correct secret over that TLS channel returns a credential (here, an SSH private key).

### 3. Intuition (KR)

문 여러 개(포트) 중 (a)**열린 문**, (b)그중 **암호 잠금(SSL)** 문, (c)그중 "메아리(echo)만 돌려주는 가짜"가 아니라 "**암호를 물어보는 진짜**" 문 하나를 찾아, password를 대면 **열쇠(SSH key)**를 준다. 그 열쇠로 다음 방(bandit17)에 들어간다. `nmap`은 어느 문이 어떤 문인지 알려주는 **정찰병**.

### 4. Theory (Mechanism)

1. **스캔 권한**: `-sS`(SYN)/`-O`(OS detect)는 raw socket이 필요해 **root 전용**("requires root privileges"). unprivileged bandit 계정은 `-sT`(connect scan)로.
2. **서비스 판별**: `-sV`가 각 open 포트에 여러 probe를 던져 응답으로 서비스 식별 → `echo` vs `ssl/echo` vs `ssl/unknown`. (느림: probe를 순차 시도하느라 ~2분.)
3. **echo 판별**: echo 서버는 보낸 bytes를 그대로 반향. 정답 서버(31790)만 `Wrong! Please enter the correct current password`로 응답 → **password를 요구하는 유일한 SSL 서비스**.
4. **★ openssl 인터랙티브 command 파싱(이 레벨의 진짜 함정)**: `s_client`(비-`-quiet`)는 입력 라인의 **첫 글자를 명령으로 해석**한다 — `Q`=quit, `R`=renegotiate, **TLS 1.3에선 `k`/`K`=KeyUpdate**. bandit16 password가 **`k`로 시작**하므로 타이핑 순간 openssl이 그 `k`를 KeyUpdate 명령으로 가로채(화면의 `KEYUPDATE`) 서버로 안 보냄 → **첫 글자 빠진 password 전송** → `Wrong!`. `-quiet`(=`-ign_eof` 포함)는 이 파싱을 끄고 입력을 **리터럴 그대로** 전송 → 온전한 password → `Correct!`.

인과: 스캔으로 31790 특정(조건) → `-quiet`로 password를 리터럴 제출(B) → 서버 검증 통과(C) → **bandit17 private key** 반환(D) → key를 로컬 저장·`chmod 600`·`ssh -i`로 bandit17 로그인(E).

### 5. Solution

```bash
# SSH connection
$ ssh -p 2220 bandit16@bandit.labs.overthewire.org
# Password: <password masked>   (= Level 15에서 얻은 bandit16 password, 'k'로 시작)

# --- ① 포트 스캔 (삽질: nmap -s -O → 스캔타입 인자 누락 usage / -sS → "requires root privileges") ---
bandit16@bandit:~$ nmap -sT -p 31000-32000 localhost
#   -sT : TCP connect scan — connect() 사용, raw socket 불요 → unprivileged 계정 OK
#   -p  : 포트 범위
# 31046 open / 31518 open / 31691 open / 31790 open / 31960 open

# --- ② 서비스 판별: 누가 SSL이고 누가 echo인가 (느림 ~2분) ---
bandit16@bandit:~$ nmap -sT -sV -p 31000-32000 localhost
#   -sV : service/version 탐지 — 각 포트에 probe 던져 응답으로 서비스 식별
# 31046  echo
# 31518  ssl/echo          # TLS echo (보낸 걸 암호화해 되돌림)
# 31691  echo
# 31790  ssl/unknown       # TLS + "Wrong! Please enter the correct current password" ★ 타깃
# 31960  echo
#   → (open ∧ SSL ∧ ¬echo) 만족 유일 포트 = 31790

# --- ③ 제출: 삽질 — 첫 글자 'k'가 KEYUPDATE 명령으로 먹힘 ---
bandit16@bandit:~$ openssl s_client -connect localhost:31790
# ... handshake / cert / session-ticket 노이즈 ...
<password masked>          # bandit16 password 타이핑 ('k'로 시작)
KEYUPDATE                  # ← ★ openssl이 맨 앞 'k'를 TLS KeyUpdate 명령으로 해석!
Wrong! Please enter the correct current password.   # → 첫 글자 잘려 오답. 여러 번 반복 실패

# --- ③' 해법: -quiet 로 command 파싱 비활성화 ---
bandit16@bandit:~$ openssl s_client -connect localhost:31790 -quiet
#   -quiet : 진단 출력 억제 + 입력을 '명령'이 아닌 '리터럴'로 전송 (+ -ign_eof 함의)
<password masked>          # 이번엔 'k' 포함 전체 password가 그대로 전송됨
Correct!
# → 서버가 bandit17 OpenSSH private key를 반환 ("BEGIN/END OPENSSH PRIVATE KEY" PEM 블록)
#   [key 본문 전체 MASKED — 절대 commit 금지. PEM 헤더 리터럴은 스캐너 오탐 방지차 미기재]

# --- ④ 반환 key로 bandit17 로그인 (L13 교훈: 내부 hop 막힘 → 로컬에서 외부 IP로) ---
# [로컬 머신에서]
$ vi /tmp/bandit17ssh          # openssl 출력의 PEM 키 블록을 붙여넣기
$ chmod 600 /tmp/bandit17ssh   # OpenSSH 권한 게이트 통과 (group/other 비트 0)
# 삽질: bandit14로 오타 → 키 불일치 → password 요구창
$ ssh -i /tmp/bandit17ssh bandit17@bandit.labs.overthewire.org -p 2220
# → bandit17 쉘! (password 없이 키 인증)
bandit17@bandit:~$ ls
passwords.new  passwords.old   # ← Level 17 과제 (두 파일 diff)
```

> [!warning] 🔴 Private Key & Password Masking (최고 등급)
> 이 레벨은 **반환값이 SSH private key**다 — password보다 강한 크리덴셜. PEM 블록은 **한 줄도 노트에 옮기지 않는다**(write-guard/pre-commit이 고엔트로피로 차단). "PEM OpenSSH key" 메타로만. 추가 마스킹: bandit16/bandit17 password, `.bandit15.password` 파일 내용, 서버 인증서 PEM·TLS session ticket·Resumption PSK.
> **로컬 위생**: 로컬 `/tmp/bandit17ssh`에 key가 남아 있으니 `rm -f /tmp/bandit17ssh`.

### 6. Why It Works

네가 "반복 실패하다 갑자기 됐다"고 느낀 정체 = **password 첫 글자 `k`**다. openssl `s_client` 인터랙티브 모드는 입력 라인 첫 글자를 명령으로 해석하는데, TLS 1.3에서 `k`/`K`는 **KeyUpdate**다. password가 `k…`라 openssl이 첫 `k`를 명령으로 가로채(그래서 `KEYUPDATE` 출력) 전송에서 누락 → 서버는 첫 글자 빠진 password 수신 → `Wrong!`. `-quiet`이 command 파싱을 꺼 입력을 **리터럴**로 흘려보내면서 `k` 포함 전체가 전달 → `Correct!` → private key 반환. **뽀록이 아니라, `-quiet`이 정확히 그 버그를 없앤 것**이다. 나머지(스캔으로 31790 특정, echo 배제, key로 로그인)는 L13~15 조합의 결정론적 절차.

### 7. Edge Cases / Limitation

- **nmap 권한**: `-sS`(SYN)·`-O`(OS detect)는 root 필요 → unprivileged는 `-sT`(connect scan). `--open`으로 열린 포트만 필터, `-sV --version-light`로 탐지 가속 가능.
- **`-sV` 비용**: probe 순차 시도로 느림(~2분). 열린 포트만 알면 `openssl s_client`로 직접 SSL 여부 판별해도 됨.
- **openssl command 문자 충돌**: password/데이터가 `R`/`Q`/`k`/`K`로 시작하면 인터랙티브에서 명령으로 오인. **리터럴 제출**(`-quiet`) 또는 **비인터랙티브 입력**(`< file` / `printf | `)이 안전.
- **내부 hop 차단(L13)**: 반환 key로 `ssh bandit17@localhost`는 막힘 → 로컬 저장 후 **외부 IP** `bandit.labs.overthewire.org:2220`으로. (사용자가 이미 로컬에서 접속해 회피.)

---

## [Phase 3] Formal Summary (EN)

> [!definition] TCP Connect Scan (`nmap -sT`)
> A port scan that completes the full TCP 3-way handshake via the OS `connect()` syscall for each target port; open ⟺ handshake succeeds, closed ⟺ RST. Requires no elevated privilege (unlike `-sS` SYN scan, which forges raw packets and needs root). Noisier/slower than SYN scan but works from an unprivileged shell.

> [!theorem] Interactive-client command chars collide with data
> An interactive client that reserves leading line characters as control commands (openssl `s_client`: `Q`/`R`/`k`/`K`) will **misinterpret** payload whose first byte equals a command char, silently dropping/altering it. ∴ transmitting arbitrary data requires a literal mode (`-quiet` ⇒ no command parsing) or non-interactive input. Here a password starting with `k` triggered TLS KeyUpdate instead of being sent. □

---

## [Phase 4] Better Methods

**Current approach** (used above): `nmap -sT -sV` → 눈으로 31790 식별 → `openssl s_client -connect ... -quiet` 인터랙티브 제출 → key 복붙 → `ssh -i`.

**Alternative 1**: `-quiet`은 **필수**, 그리고 파일 redirect로 비인터랙티브 제출 (k-충돌·spoiler 동시 회피)
```bash
openssl s_client -connect localhost:31790 -quiet < /etc/bandit_pass/bandit16
#   -quiet    : command 파싱 off + 노이즈 억제
#   < file    : password 파일을 stdin으로 → 인터랙티브 명령 파싱 경로 자체를 안 탐 + password 비노출
```
Trade-off: 가장 안전. password 값 몰라도, `k`로 시작해도 무사.

**Alternative 2**: 스캔 결과 필터링 가속
```bash
nmap -sT --open -p 31000-32000 localhost          # --open: 열린 포트만 출력
nmap -sT -sV --version-light --open -p 31000-32000 localhost   # --version-light: probe 최소화 → 빠름
```
Trade-off: 노이즈↓ 속도↑. version-light는 정밀도 약간 손해.

**Alternative 3**: key를 스크립트로 바로 저장 (복붙 실수 방지)
```bash
D=$(mktemp -d); K="$D/id"
openssl s_client -connect localhost:31790 -quiet < /etc/bandit_pass/bandit16 \
  | sed -n '/BEGIN OPENSSH/,/END OPENSSH/p' > "$K"    # PEM 블록만 추출 저장
chmod 600 "$K"
#   sed -n '/A/,/B/p' : A행~B행 범위만 출력 → "Correct!" 등 잡음 제거하고 키만
```
Trade-off: 복붙/편집 실수 제거, 자동화 친화. (이후 `ssh -i "$K"`는 L13대로 외부 IP로.)

**Most elegant**: 위 Alternative 3 파이프라인 — 스캔으로 포트 특정 후, "제출 → 키 추출 → 권한" 을 한 흐름으로.

---

## [Phase 5] Lessons Learned

1. **unprivileged nmap = `-sT`** (connect scan). `-sS`(SYN)·`-O`(OS)는 root 필요 → "requires root privileges".
2. **`-sV`로 echo/ssl 판별** → (open ∧ SSL ∧ ¬echo) 3중 필터로 타깃 1개 특정. "보낸 게 그대로 오면 echo(오답)".
3. **★ openssl 인터랙티브는 라인 첫 글자를 명령으로 먹는다** (`R`/`Q`/`k`/`K`). password가 `k`로 시작하면 KeyUpdate로 잘림 → **`-quiet`(리터럴) 또는 `< file`(비인터랙티브)**. 반복 "Wrong!"의 숨은 원인.
4. **반환 key 로그인 = L13 재적용**: 내부 localhost hop 막힘 → 로컬 저장·`chmod 600`·외부 IP로 `ssh -i`.
5. **private key는 노트/commit 금외**. write-guard가 막지만 습관적으로 마스킹.

### Quiz

**Q**: bandit16 password를 `openssl s_client`(비-`-quiet`)로 제출하니 반복 `Wrong!`이 났고 화면에 `KEYUPDATE`가 떴다. (a) openssl 입력 처리 관점에서 원인을, (b) `-quiet`이 고치는 원리를, (c) `-quiet` 없이 피하는 제출법 하나를 설명하라.

> [!tip]- 풀이
> **(a)** `s_client` 인터랙티브 모드는 입력 라인 첫 글자를 명령으로 해석한다: `R`=renegotiate, `Q`=quit, TLS 1.3에서 `k`/`K`=KeyUpdate. password가 `k…`라 openssl이 첫 `k`를 KeyUpdate로 가로채(→`KEYUPDATE` 출력) 전송하지 않음 → 서버는 첫 글자 빠진 password 수신 → `Wrong!`.
>
> **(b)** `-quiet`은 `-ign_eof`를 함의하며 입력 command 파싱을 끈다 → 입력을 **리터럴 그대로** 소켓에 전송 → `k` 포함 전체 password 전달.
>
> **(c)** 비인터랙티브 입력: `openssl s_client -connect ... -quiet < /etc/bandit_pass/bandit16` 또는 `printf '%s\n' "$pw" | openssl …`. 인터랙티브 터미널 입력이 아니면 명령 파싱 경로를 안 탐.
>
> 핵심: **대화형 클라이언트의 command/escape 문자는 데이터와 충돌할 수 있다.** 임의 데이터 제출 시 리터럴 모드나 비대화형 입력을 써라.

> [!flashcard]
> **Q**: 비-root 계정에서 `nmap -sS`가 실패하는 이유와 대안은?
> **A**: `-sS`(SYN half-open)는 raw socket 생성이 필요해 root 권한을 요구("requires root privileges"). 대안: `-sT`(TCP connect scan) — `connect()` syscall만 써서 unprivileged로 동작.

> [!flashcard]
> **Q**: openssl s_client 제출 시 password가 `k`로 시작하면 왜 실패하나?
> **A**: 인터랙티브 모드가 라인 첫 글자를 명령으로 해석 — TLS 1.3에서 `k`=KeyUpdate. 첫 `k`가 명령으로 먹혀 전송 누락 → 서버 거부. `-quiet`(리터럴) 또는 stdin redirect로 회피.

---

## Links

### Tools Used
- [[Tools/nmap]]
- [[Tools/openssl]]
- [[Tools/ssh]]
- [[Tools/chmod]]

### Concepts Introduced (first encountered here)
- [[Concepts/Network/Port_Scanning]]

### Concepts Applied (reused from earlier)
- [[Concepts/Network/SSL_TLS]] (Level 15 — SSL 소켓 제출)
- [[Concepts/Network/SSH_Key_Authentication]] (Level 13 — 반환 key로 로그인, 내부 hop 회피)
- [[Concepts/Network/Netcat]] (Level 14 — 소켓 통신 원형)

### Navigation
- **Prerequisite**: [[Level_15]]
- **Next**: [[Level_17]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit17.html
- `nmap(1)` — `-sT`, `-sS`, `-sV`, `--open`, `--version-light`
- `openssl-s_client(1)` — `-connect`, `-quiet`, `-ign_eof`; interactive command chars (R/Q/k/K)
