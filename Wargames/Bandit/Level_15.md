---
date: 2026-07-15
wargame: Bandit
level: 15
title: "Bandit Level 15 → 16"
difficulty: ★★☆
time_spent: 8min
tags: [bandit, linux, network, ssl, tls, openssl]
status: 🟡 developing
tools_used: [openssl]
new_concepts: [SSL_TLS]
prerequisites: [Level_14]
---

# Bandit Level 15 → 16

## [Phase 1] Executive Summary

- **Goal**: 현재 레벨(bandit15)의 password를 **localhost:30001**에 **SSL/TLS 암호화**로 제출 → 응답으로 bandit16 password 회수 (Level 14 netcat의 **암호화 버전**)
- **Key Skill**: `openssl s_client -connect localhost:30001` — TLS handshake를 수행하는 클라이언트로 암호화 채널을 열고, password를 stdin으로 전달
- **Tags**: `[SSL_TLS]`, `[OpenSSL]`, `[Encrypted_Socket]`

[Cognitive Validation]
- **Limit Test**: 평문 `nc localhost 30001`로 붙으면? 서버가 TLS handshake를 기대하므로 평문 bytes는 **협상 실패**로 무시/끊김. 암호화 계층 유무가 지배 변수 — L14(평문)와의 유일한 차이.
- **Control Knob**: 지배 변수는 **"전송 계층에 TLS를 씌우는가"**. `openssl s_client`가 L14의 `nc` 자리에 들어가 handshake + 대칭키 암호화를 담당하고, 그 위에서 payload(stdin)는 동일하게 흐른다.
- **Nullity**: 인증서 검증 실패(self-signed `verify error`)는 **데이터 채널을 막지 않는다** — 이 레벨의 보안은 **기밀성(암호화)**이지 서버 신원 인증이 아님. 검증 경고는 무시 가능.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**Encrypted socket communication** — Level 14의 평문 TCP 소켓에 **TLS 계층**을 얹은 것. 본질 명제: "전송 계층 보안(TLS)은 애플리케이션 로직 아래에 **투명하게 끼워지는 wrapper**"다. 즉 password 제출 로직은 L14와 **완전히 동일**하고, 달라진 건 bytes가 소켓을 건널 때 암호화된다는 점뿐.

### 2. Definition (Formal, EN)

`openssl s_client` is a diagnostic TLS/SSL client. `-connect HOST:PORT` opens a TCP connection, performs the **TLS handshake** (negotiate protocol version + cipher suite, run key exchange, present/validate certificates), and then relays the application byte stream between the process's **stdin/stdout** and the **encrypted** channel. Crucially, **confidentiality** (the encrypted channel) and **authentication** (certificate trust) are *orthogonal*: a verification failure (self-signed ⇒ error 18) is reported but does **not** tear down the encrypted session.

### 3. Intuition (KR)

`openssl s_client` = **"TLS를 입은 `nc`"**. L14의 `nc`가 맨몸으로 소켓에 붙었다면, 여기선 그 위에 **암호화 봉투(TLS)**를 한 겹 씌운 것뿐. 봉투를 봉인한 도장(인증서)이 공인기관(CA)이 아니라 **자기가 찍은 도장(self-signed)**이라 "이 도장 못 믿겠다(verify error)"고 경고하지만, **봉투 안 내용은 여전히 암호화되어 잘 오간다**. 경고는 *신원* 문제지 *암호화* 문제가 아니다.

### 4. Theory (Mechanism)

실제 출력이 무슨 일을 한 건지 한 줄씩 풀면:

1. `-connect localhost:30001` → TCP 연결(`CONNECTED`) + TLS handshake 개시.
2. 서버가 인증서(`CN=SnakeOil`, RSA 4096, self-signed) 제시 → 클라이언트가 CA 체인 검증 시도 → 신뢰 앵커 없음 → `verify error:num=18:self-signed certificate`. **`s_client`는 경고만 하고 진행**(기본 동작).
3. `SSL handshake has read … bytes` + `TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384` → handshake 완료, **양방향 암호화 채널 확립**. 이 순간부터 도청 불가.
4. 이후 `nc`처럼 **stdin →(암호화)→ 소켓, 소켓 →(복호)→ stdout** 릴레이. 화면의 `read R BLOCK` = openssl이 읽을 데이터 대기(`SSL_ERROR_WANT_READ`) — 정상. `Post-Handshake New Session Ticket` = TLS 1.3의 세션 재개용 티켓 도착 — 정상 노이즈.
5. password 타이핑 → 암호화되어 전송 → 서버가 `/etc/bandit_pass/bandit15`와 대조 → `Correct!` + bandit16 password 반환 → `closed`.

인과 사슬: openssl이 TLS handshake로 암호화 채널 확립(조건) → password가 stdin으로 유입(B) → **암호화되어** 전송(C) → 서버 검증 통과(D) → 응답으로 다음 password(E). **L14와 유일한 차이는 (C)에 암호화가 낀 것.**

### 5. Solution

```bash
# SSH connection
$ ssh -p 2220 bandit15@bandit.labs.overthewire.org
# Password: <password masked>   (= Level 14에서 얻은 bandit15 password)

# 문제: bandit15 password를 localhost:30001에 SSL/TLS로 제출

bandit15@bandit:~$ openssl s_client -connect localhost:30001
#   s_client     : TLS/SSL 진단용 클라이언트 (여기선 "TLS 버전 nc"로 사용)
#   -connect H:P : host:port로 TCP 연결 + TLS handshake 수행
CONNECTED(00000003)
depth=0 CN=SnakeOil
verify error:num=18:self-signed certificate        # ← 신원 검증 실패(자체서명). 무시 가능
---
# [Certificate chain / Server certificate PEM 생략 — 공개값이나 노이즈. SnakeOil, RSA 4096]
---
SSL handshake has read 3191 bytes and written 1613 bytes   # ← handshake 완료 = 암호화 채널 UP
New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384
Verify return code: 18 (self-signed certificate)           # ← cert 불신(무시), 채널은 정상
---
read R BLOCK                                                # ← openssl이 입력 대기(WANT_READ). 정상
# [Post-Handshake Session Ticket / Resumption PSK / Session-ID 생략 — 세션 비밀·노이즈]

<password masked>          # ← bandit15 password를 타이핑 후 Enter (암호화되어 전송)
Correct!
<password masked>          # ← bandit16 (Level 16) password

closed
```

> [!warning] Password & TLS-artifact Masking
> 제출한 bandit15 password + 응답 bandit16 password 마스킹. 추가로 openssl 출력의 **Resumption PSK / TLS session ticket / Session-ID**는 세션 비밀 성격이고 pre-commit 스캐너가 고엔트로피로 잡을 수 있어 노트에 옮기지 않는다. **서버 인증서 PEM**은 공개값이지만 노이즈라 요약(SnakeOil self-signed, RSA 4096)으로 대체.

### 6. Why It Works

"뽀록으로 풀린 느낌"의 정체 = openssl이 **handshake 진단을 한 화면 쏟아내** 정작 단순한 본질을 가렸을 뿐. 실제로 일어난 건 딱 이거: **openssl이 TLS handshake로 암호화 채널을 만들고, 그 위에서 `nc`처럼 stdin의 password를 서버로 보냈고, 서버가 맞다고 다음 password를 돌려줬다.** `verify error`는 "이 서버가 진짜 그 서버가 맞는지"를 못 믿겠다는 **신원 경고**일 뿐, 암호화(기밀성)와는 독립이라 무시해도 password 교환은 정상 작동한다. **우연이 아니라 설계대로** 풀린 것 — `-quiet`로 노이즈만 걷어내면 그 사실이 바로 보인다(Phase 4).

### 7. Edge Cases / Limitation

- **평문 `nc` 불가**: `nc localhost 30001`은 handshake 없이 평문 전송 → 서버가 TLS record로 파싱 실패. 반드시 TLS-aware 클라이언트(`openssl s_client` / `ncat --ssl`).
- **`verify error`는 무시가 정답(여기선)**: self-signed는 이 게임 설계. **단 실무에선** verify 무시가 MITM 노출 — localhost + 학습 목적이라 무해할 뿐(Quiz 참조).
- **출력 노이즈 / 종료**: TLS 1.3의 session ticket·`read R BLOCK`이 화면을 채워도 정상. 자동화하려면 `-quiet` + stdin redirect가 깔끔.
- **openssl 버전차**: 최신 `-quiet`는 `-ign_eof`를 함의(EOF에 조기 종료 안 함). 구버전은 파이프 시 `-ign_eof`를 별도로 줘야 응답 전에 안 끊긴다.

---

## [Phase 3] Formal Summary (EN)

> [!definition] TLS via `openssl s_client`
> TLS wraps a TCP byte stream in a handshake-negotiated encrypted channel: peers agree on version + cipher suite, perform key exchange, and optionally validate certificates. `openssl s_client -connect H:P` runs this handshake, then relays stdin ↔ encrypted-socket ↔ stdout. Confidentiality (encryption) and authentication (certificate trust) are orthogonal: verify error 18 (self-signed) leaves the encrypted channel fully functional.

> [!theorem] Encryption ⟂ Identity Verification
> A completed TLS handshake yields a confidential channel **regardless** of whether the peer's certificate chains to a trusted CA. ∴ a self-signed cert produces `verify error` yet transmits application data unimpaired; rejecting on verify failure is a **client-enforced policy** choice, not a protocol necessity. □

---

## [Phase 4] Better Methods

**Current approach** (used above):
```bash
openssl s_client -connect localhost:30001
# 이후 password 인터랙티브 타이핑
```
Trade-off: 동작하나 handshake 진단이 화면을 폭격 → 본질 흐림("뽀록" 착시의 원인).

**Alternative 1**: `-quiet`로 노이즈 제거
```bash
openssl s_client -connect localhost:30001 -quiet
#   -quiet : handshake/cert 진단 출력 억제 (+ 최신 버전은 -ign_eof 함의 → EOF에 조기종료 안 함)
```
Trade-off: 화면이 깔끔해져 password 교환만 보임 → "무슨 일이 벌어졌나"가 명확. 학습·재현 모두 유리.

**Alternative 2**: 파일 redirect (spoiler-free, L14 패턴 계승)
```bash
openssl s_client -connect localhost:30001 -quiet < /etc/bandit_pass/bandit15
#   < file : password 파일을 stdin으로 → password 문자열을 화면·셸히스토리에 안 남기고 제출
```
Trade-off: password 값을 몰라도 제출 가능 → 가장 위생적. (`-quiet` 없이 쓰면 응답이 노이즈에 묻히거나 조기 종료로 잘릴 수 있음.)

**Alternative 3**: `ncat --ssl` (netcat 계열의 TLS 지원)
```bash
ncat --ssl localhost 30001
#   ncat(nmap 제공) : --ssl 플래그로 TLS wrapping → L14의 nc 문법을 그대로 TLS로 확장
```
Trade-off: nc의 단순 문법 유지 + TLS 획득. 단 `ncat`(nmap)이 깔려 있어야 함 — 기본 `nc`엔 없음.

**Most elegant**:
```bash
openssl s_client -connect localhost:30001 -quiet < /etc/bandit_pass/bandit15
```
Why elegant: L14의 "파일 경유 제출"에 **TLS만 얹은** 형태 — password 비노출 + 노이즈 제거 + 단일 명령. L14 → L15의 연속성(평문 → 암호화)이 명령 구조에 그대로 드러난다.

---

## [Phase 5] Lessons Learned

1. **`openssl s_client` = "TLS 입은 `nc`"** — `-connect H:P`로 암호화 채널을 열면 그 위 password 제출은 L14와 동일(stdin 경유).
2. **암호화 ⟂ 신원검증**: `verify error:18 self-signed`는 인증서 신뢰 문제지 암호화 실패가 아니다. 채널은 멀쩡 → 무시하고 진행.
3. **평문 `nc`는 TLS 포트에 안 통한다** — handshake가 없어서. 도구를 TLS-aware로 바꿔야 한다(`s_client` / `ncat --ssl`).
4. **노이즈에 속지 마라**: handshake 진단·session ticket·`read R BLOCK`은 전부 정상 산물. `-quiet`로 걷어내면 본질(= `nc` + 암호화)이 드러난다 → **"뽀록"이 아니라 설계대로 풀린 것.**

### Quiz

**Q**: 이 레벨은 `verify error:18`(self-signed)을 무시하고도 풀린다. (a) 암호화는 되는데 왜 "신원 검증"은 실패하는가 — 둘의 관계를 설명하라. (b) 실무에서 self-signed verify error를 무시하면 어떤 공격에 노출되나? (c) `localhost:30001`에서는 왜 그 공격이 사실상 무의미한가?

> [!tip]- 풀이
> **(a)** TLS handshake는 두 가지를 동시에 한다 — (i) 키 교환으로 대칭키를 세워 **기밀성** 확보, (ii) 인증서 체인으로 상대 **신원** 검증. 두 목표는 **독립**이다. self-signed는 (ii)의 신뢰 앵커(CA)가 없어 실패하지만 (i)의 키 교환은 정상 → 암호화는 성립.
>
> **(b)** **MITM(중간자)**: 공격자가 가짜 인증서로 서버인 척 끼어들어도, verify error를 무시하면 클라이언트가 *공격자*와 암호화 채널을 맺는다 → 공격자가 평문을 열람·변조. "암호화됐지만 상대가 누군지 모르는" 채널은 **도청엔 강하나 사칭엔 약하다.**
>
> **(c)** `localhost`(127.0.0.1)는 loopback — 트래픽이 물리/네트워크를 거치지 않고 커널 내부에서만 순환하므로 중간자가 끼어들 경로가 없다. 따라서 신원 검증 생략의 위험이 사실상 0.
>
> 핵심: TLS = 기밀성 + 무결성 + (선택적)인증. **"암호화됐다 ≠ 상대가 진짜다"** — 셋을 분리해서 사고하라.

> [!flashcard]
> **Q**: Bandit 15가 `verify error:18 self-signed certificate`에도 불구하고 풀리는 이유는?
> **A**: TLS는 암호화(키 교환 → 기밀 채널)와 인증(인증서 체인 → 신원)을 분리한다. self-signed는 신원 검증만 실패시키고 암호화 채널은 온전하므로 password 교환이 성공한다. `s_client`는 경고 후 기본적으로 계속 진행한다.

> [!flashcard]
> **Q**: 왜 평문 `nc localhost 30001`로는 password를 제출할 수 없나?
> **A**: 포트 30001은 application 데이터 전에 **TLS handshake**를 요구한다. `nc`는 handshake 없이 raw bytes를 보내 프로토콜 오류. `openssl s_client -connect`(또는 `ncat --ssl`)를 써야 한다.

---

## Links

### Tools Used
- [[Tools/openssl]]

### Concepts Introduced (first encountered here)
- [[Concepts/Network/SSL_TLS]]

### Concepts Applied (reused from earlier)
- [[Concepts/Network/Netcat]] (Level 14 — 평문 소켓 → 여기선 TLS로 암호화)
- [[Concepts/Linux/Stdin_Vs_Argument]] (payload는 여전히 stdin 경유)

### Navigation
- **Prerequisite**: [[Level_14]]
- **Next**: [[Level_16]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit16.html
- `openssl-s_client(1)` — `-connect`, `-quiet`, `-ign_eof`, `-crlf` flags
- TLS 1.3 — RFC 8446 (handshake, session tickets)
