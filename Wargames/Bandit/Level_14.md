---
date: 2026-07-14
wargame: Bandit
level: 14
title: "Bandit Level 14 → 15"
difficulty: ★☆☆
time_spent: 12min
tags: [bandit, linux, network, netcat, tcp]
status: 🟡 developing
tools_used: [nc, cat, echo]
new_concepts: [Netcat]
prerequisites: [Level_13]
---

# Bandit Level 14 → 15

## [Phase 1] Executive Summary

- **Goal**: 현재 레벨(bandit14)의 password를 **localhost:30000**에 열린 TCP 서비스에 제출 → 응답으로 bandit15 password 회수
- **Key Skill**: `nc`(netcat)로 TCP **클라이언트** 접속 + password를 **stdin**으로 전달
- **Tags**: `[Netcat]`, `[TCP_Client]`, `[Stdin_Redirection]`

[Cognitive Validation]
- **Limit Test**: 제출 bytes가 1 byte라도 틀리면(오타·trailing newline 결손) 서버는 "Correct!"를 안 주고 침묵/거부. 정확한 password stream만 통과 → 데이터 무결성이 지배.
- **Control Knob**: 지배 변수는 **"payload를 어디로 넣는가"**. `nc`는 소켓만 열고, 보낼 데이터는 command-line argument가 아니라 **stdin**에서 읽는다. 이 채널을 틀리면(=arg로 줌) 즉시 실패.
- **Nullity**: stdin에 아무것도 안 주면(빈 입력) 서버는 password 한 줄을 영원히 기다리며 hang → 제출 자체가 성립 안 함.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**Network service interaction** — 로컬에서 열린 TCP 서비스에 raw bytes를 보내고 응답을 받는 기초. Level 00~13의 "파일/텍스트/압축/SSH"에서 처음으로 **소켓 통신(socket I/O)**으로 넘어가는 분기점. 본질 명제: "네트워크 연결도 결국 **읽고 쓰는 stream**이며, `nc`가 그 stream을 stdin/stdout에 이어준다."

### 2. Definition (Formal, EN)

**netcat** (`nc`) reads and writes data across network connections over TCP or UDP. In **client mode**, `nc HOST PORT` establishes a socket *S* = connect(HOST, PORT) and bridges *S*'s bidirectional byte stream to the process's standard streams: bytes read from **stdin** are transmitted verbatim over *S* (outbound), and bytes received from *S* are written to **stdout** (inbound). `nc` adds **no protocol framing** of its own — it is a transparent pipe between a terminal (or pipeline) and a socket.

### 3. Intuition (KR)

`nc`는 **"네트워크용 `cat`"**이다. `cat`이 파일 ↔ 터미널을 잇듯, `nc`는 **소켓 ↔ 터미널**을 잇는 파이프. 키보드(stdin)로 친 게 그대로 서버로 날아가고, 서버가 보낸 게 화면(stdout)에 뜬다. password는 "손으로 쳐 넣는 편지"가 아니라 **파이프에 흘려 넣는 물** — 어느 구멍(stdin)에 붓느냐가 전부다.

### 4. Theory (Mechanism)

1. `nc localhost 30000`: TCP 3-way handshake로 30000 포트의 daemon에 연결. 이후 **stdin → 소켓**, **소켓 → stdout** 양방향 릴레이 시작.
2. 서버(bandit이 미리 띄운 서비스)는 연결되면 password 한 줄을 대기. `/etc/bandit_pass/bandit14`와 대조해 **일치하면** `Correct!` + 다음 레벨 password를 응답.
3. password를 **어떻게 stdin에 넣느냐**가 유일한 자유도: ① 인터랙티브 타이핑, ② `echo pw | nc`, ③ `nc < file`. 셋 다 결국 같은 stdin 채널.

인과 사슬: `nc`가 소켓 open(조건) → password가 stdin으로 유입(B) → 소켓으로 전송(C) → 서버 검증 통과(D) → 응답으로 다음 password(E).

### 5. Solution

```bash
# SSH connection
$ ssh -p 2220 bandit14@bandit.labs.overthewire.org
# Password: <password masked>   (= Level 13에서 얻은 bandit14 password)

# 문제: "현재 레벨 password를 localhost:30000에 제출하라"

# --- 삽질 로그: stdin vs argument (Level 06의 재현!) ---
# (1) password를 '인자'로 넘김 → nc는 세 번째 토큰을 또 다른 '포트'로 파싱
bandit14@bandit:~$ nc 127.0.0.1 30000 <lv14-pw>
# nc: port number invalid: <lv14-pw>
#   nc 문법은 [destination] [port]. 뒤에 붙인 토큰 = 포트로 해석 → invalid

# (2) '< <lv14-pw>' → password를 '파일명'으로 오해 (redirect는 파일에서 읽음)
bandit14@bandit:~$ nc localhost 30000 < <lv14-pw>
# -bash: <lv14-pw>: No such file or directory
#   '<'는 그 이름의 '파일'을 stdin으로 여는 것. password 문자열은 파일이 아님

# (3) 그럼 파일을 만들어 redirect하자 → home이 read-only라 저장 불가
bandit14@bandit:~$ nano test
# Unable to create directory /home/bandit14/.local/share/nano/: No such file or directory
#   home write-access 차단 (배너에도 명시). 임시파일 전략이 여기서 막힘

# (4) nc -l 30000 → listen(서버) 모드. 서비스가 이미 30000 점유 중
bandit14@bandit:~$ nc -l 30000
# nc: Address already in use
#   -l = 내가 서버가 되어 대기하겠다는 뜻 → 방향이 반대. 클라이언트로 붙어야 함

# --- 해법: 연결 후 stdin으로 password 전달 (인터랙티브) ---
bandit14@bandit:~$ nc localhost 30000
<password masked>          # ← bandit14 password를 타이핑 후 Enter (stdin으로 전송)
Correct!
<password masked>          # ← bandit15 (Level 15) password
```

> [!warning] Password Masking
> 제출한 bandit14 password와 응답으로 받은 bandit15 password **둘 다** 마스킹. 특히 `echo '<pw>' | nc`처럼 password를 **셸 히스토리·노트에 문자열로 남기는 형태를 피하라** — Phase 4의 `< /etc/bandit_pass/bandit14` 방식이 spoiler-free.

### 6. Why It Works

`nc`는 소켓의 duplex stream을 stdin/stdout에 연결하는 **투명 relay**다. password를 stdin으로 넣으면 `nc`가 그 bytes를 **그대로**(no framing) 30000 서비스에 전송하고, 서비스는 `/etc/bandit_pass/bandit14`와 대조해 일치 시 다음 password를 stdout(← 소켓)으로 되돌린다. 핵심은 payload가 **command-line argument가 아니라 stdin**을 통해 흐른다는 것 — Level 06의 `find | cat` 혼동과 **정확히 같은 축**이다. "명령에 데이터를 주는 채널"을 arg로 착각하면 도구는 그 데이터를 엉뚱하게(포트·파일명으로) 해석한다.

### 7. Edge Cases / Limitation

- **home read-only**: "임시 파일 만들어 redirect" 전략이 막힘(삽질 3). 대신 **이미 존재하고 읽을 수 있는** `/etc/bandit_pass/bandit14`를 redirect source로 쓰거나 `echo`/here-string 사용.
- **trailing newline**: 서버가 줄 단위(line-buffered)로 읽으면 password 뒤 `\n`이 필요. 기본 `echo`는 `\n`을 붙이지만 `echo -n`은 제거 → 서버가 줄 끝을 못 봐 **hang**할 수 있음.
- **nc가 EOF 후 안 끊음**: OpenBSD `nc`는 stdin EOF 후에도 소켓 수신측을 열어둬 응답을 기다리다 교착할 수 있음 → `-N`(EOF 시 half-close) 또는 `-q 0`(EOF 후 0초에 종료)로 해소.
- **`-l`은 방향 반대**: listen(서버) 모드. 이미 점유된 포트엔 `Address already in use`. 이 레벨은 클라이언트 접속(`nc HOST PORT`)이 정답.

---

## [Phase 3] Formal Summary (EN)

> [!definition] Netcat (TCP Client Mode)
> `nc HOST PORT` opens a TCP socket *S* = connect(HOST, PORT) and relays *S*'s duplex byte stream to the process's standard streams: send = read(stdin) → *S*, recv = *S* → write(stdout). Bytes are transmitted verbatim with no added framing; `nc` is protocol-agnostic.

> [!theorem] Payload travels via stdin, not argv
> For `nc HOST PORT [token…]`, trailing tokens are parsed as **connection parameters** (an extra token is taken as a port ⇒ "port number invalid"), never as payload. ∴ data to transmit must enter through **stdin** (interactive, pipe, or `<` redirect) — the identical stdin-vs-argument distinction seen in Level 06 (`find | cat`). □

---

## [Phase 4] Better Methods

**Current approach** (used above): 연결 후 password 인터랙티브 타이핑.
```bash
nc localhost 30000
# 이후 password + Enter
```
Trade-off: 즉석엔 쉬우나 **재현 불가**하고 password를 눈으로 봐야 함.

**Alternative 1**: `echo` 파이프 (non-interactive)
```bash
echo '<password>' | nc localhost 30000
#   echo '<pw>' : password + 자동 trailing newline을 stdout으로 출력
#   |           : echo의 stdout을 nc의 stdin으로 연결 (pipe)
#   nc          : 받은 bytes를 소켓으로 전송
```
Trade-off: 재현 가능. **단 password가 셸 히스토리에 평문으로 남는다** → 노트/공개 repo에 부적합.

**Alternative 2**: password 파일을 stdin으로 redirect (spoiler-free, 권장)
```bash
nc localhost 30000 < /etc/bandit_pass/bandit14
#   < file  : nc의 stdin을 지정 파일에 연결 (파일 내용이 stdin으로 유입)
#   /etc/bandit_pass/bandit14 : bandit14로 로그인 중이라 read 가능
#   → password 문자열을 화면·히스토리에 노출하지 않고 제출
```
Trade-off: 파일 경로만 알면 password 값을 **몰라도** 제출 가능 → 가장 안전. 재현성·위생 모두 우수.

**Alternative 3**: `cat` 파이프 (동일 효과, 명시적)
```bash
cat /etc/bandit_pass/bandit14 | nc localhost 30000
```
Trade-off: UUOC(`cat` 남용) — `< file`이 프로세스 하나 적다. 가독성 선호 시에만.

**Most elegant**:
```bash
nc -N localhost 30000 < /etc/bandit_pass/bandit14
#   -N : stdin EOF 시 소켓 write측을 half-close(shutdown) → 서버에 "전송 끝" 통지
#        (없으면 nc가 안 끊고 대기하는 구현이 있음 → -q 0 도 대안)
```
Why elegant: password를 코드·노트·셸히스토리 어디에도 남기지 않으면서(파일 경유) 단일 명령으로 완결. `-N`으로 종료 교착까지 예방.

---

## [Phase 5] Lessons Learned

1. **`nc` = "네트워크용 `cat`"** — payload는 반드시 **stdin**으로 넣는다. argument로 주면 `nc`가 port로 오해(`port number invalid`). ([[Level_06]]의 stdin-vs-argument가 네트워크 맥락에서 재등장.)
2. **`-l`은 listen(서버) 모드** — 방향이 반대. 클라이언트로 붙을 땐 그냥 `nc HOST PORT`.
3. **home이 read-only인 환경**에선 "임시 파일 만들어 redirect" 전략이 막힌다 → 이미 존재하는 파일(`/etc/bandit_pass/banditN`)을 redirect source로.
4. **password를 노트/히스토리에 안 남기려면** `nc PORT < /etc/bandit_pass/banditN` — 파일 경유 제출이 spoiler-free.

### Quiz

**Q**: `echo -n <pw> | nc localhost 30000`이 응답 없이 멈추는(hang) 경우가 있다. (a) trailing newline 유무가 서버 동작에 미치는 영향, (b) `nc`가 stdin EOF 후에도 소켓을 안 닫는 이유, (c) 이를 해결하는 두 플래그를 설명하라.

> [!tip]- 풀이
> **(a)** 서버가 line-buffered로 `\n`까지 한 줄을 읽는 설계라면, `echo -n`(newline 제거)은 줄 끝을 못 만들어 서버가 password 라인을 "미완성"으로 보고 계속 대기 → hang. 기본 `echo`(newline 포함)면 정상 종료.
>
> **(b)** TCP는 **half-close**(한 방향만 종료)를 지원한다. stdin이 EOF여도 `nc`는 소켓의 **수신 방향**을 열어둬 서버 응답을 계속 받으려 한다(대개 바람직). 그러나 서버가 "클라이언트가 보낼 것을 다 보냄(=EOF/shutdown)"을 응답 트리거로 삼으면, `nc`가 write측을 안 닫아 서로 대기하는 교착이 생긴다.
>
> **(c)** `-N`(stdin EOF 시 소켓 write측 `shutdown(SHUT_WR)`) 또는 `-q 0`(EOF 후 0초 뒤 종료). 둘 다 서버에 "전송 종료"를 통지해 응답을 받게 한다.
>
> 핵심: `nc`는 **protocol을 모른다** — framing(줄바꿈)과 종료(half-close)는 애플리케이션 계층의 계약이므로 **사용자가 맞춰줘야** 한다.

> [!flashcard]
> **Q**: Why does `nc HOST PORT password` fail to submit "password"?
> **A**: `nc` parses trailing tokens as connection parameters — the 3rd token is read as a port (⇒ "port number invalid"), not as data. Payload must arrive via **stdin**: `echo password | nc HOST PORT` or `nc HOST PORT < file`.

---

## Links

### Tools Used
- [[Tools/nc]]
- [[Tools/cat]]
- [[Tools/echo]]

### Concepts Introduced (first encountered here)
- [[Concepts/Network/Netcat]]

### Concepts Applied (reused from earlier)
- [[Concepts/Linux/Stdin_Vs_Argument]] (Level 06 `find | cat`, Level 10 recon → 여기선 nc payload 채널로 재적용)
- [[Concepts/Linux/Pipe_Composition]]

### Navigation
- **Prerequisite**: [[Level_13]]
- **Next**: [[Level_15]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit15.html
- `nc(1)` — OpenBSD netcat; `-l`, `-N`, `-q` flags
- TCP half-close / `shutdown(2)` — stream termination semantics
