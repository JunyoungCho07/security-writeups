---
date: 2026-05-15
wargame: Bandit
level: 0
title: "Bandit Level 0 → 1"
difficulty: ★☆☆
time_spent: 5min
tags: [bandit, linux, ssh, networking]
status: 🟢 solid
tools_used: [ssh, cat, ls]
new_concepts: [SSH_Protocol, Public_Key_Auth]
prerequisites: []
---

# Bandit Level 0 → 1

## [Phase 1] Executive Summary

- **Goal**: SSH로 bandit.labs.overthewire.org에 접속해서 첫 password를 얻는다.
- **Key Skill**: SSH client 사용 + non-default port 명시
- **Tags**: `[SSH_Protocol]`, `[Remote_Shell]`, `[Linux_Basics]`

[Cognitive Validation]
- **Limit Test**: port 명시 안 하면 ssh는 default 22 사용 → 연결 실패 (overthewire는 2220). port = critical variable.
- **Control Knob**: `-p <port>` flag가 transport layer 연결을 결정. 잘못된 port = SYN 응답 없음 → timeout.
- **Nullity**: empty username → ssh가 현재 OS 사용자명으로 자동 fallback → 잘못된 account 시도 → auth 실패.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization
이 level은 **remote shell access 메커니즘**을 다룬다. 본질: 두 컴퓨터 간 암호화된 양방향 통신 채널을 수립하고, 그 위에서 명령을 실행한다. 카테고리: `Network Protocol` ∩ `Authentication`.

### 2. Definition (Formal, EN)

> [!definition] SSH (Secure Shell)
> A cryptographic network protocol (RFC 4251-4254) operating on TCP/22 by default, providing:
> 1. Server authentication via host key
> 2. User authentication via password / public key / GSS-API
> 3. Encrypted bidirectional channel (typically AES-CTR / ChaCha20-Poly1305)
> 4. Multiplexed sub-channels for shell, port-forwarding, X11, SFTP

### 3. Intuition (KR)
SSH는 *"공중에서 도청 불가능한 원격 터미널"*. 인터넷 → 적군 가득 → 그래도 두 끝점은 안전하게 대화 가능. 비유: 봉투에 봉인 + 수신자만 열 수 있는 자물쇠 + 발신자 신원 위조 불가.

### 4. Theory (Mechanism)
1. **TCP handshake**: client → server `SYN`, server → client `SYN-ACK`, client → server `ACK`
2. **Protocol version exchange**: 양쪽이 `SSH-2.0-OpenSSH_X.Y` 등 banner 교환
3. **Algorithm negotiation**: 양쪽이 지원하는 KEX(key exchange), cipher, MAC, compression 알고리즘 중 공통분모 선택
4. **Key exchange** (Diffie-Hellman or ECDH): shared secret 생성. 도청자는 secret 계산 불가 (discrete log problem).
5. **Host key verification**: server가 자신의 host key로 서명 → client는 `~/.ssh/known_hosts`와 대조
6. **User authentication**: password / public key / other
7. **Channel setup**: shell, exec, subsystem 등

### 5. Solution

```bash
# Local terminal (WSL or any SSH-capable shell)
$ ssh -p 2220 bandit0@bandit.labs.overthewire.org

# First-time connection prompt:
# The authenticity of host 'bandit.labs.overthewire.org' can't be established.
# Are you sure you want to continue connecting (yes/no/[fingerprint])? yes

# Password prompt:
# bandit0@bandit.labs.overthewire.org's password: <password masked>
# (For Level 0, the password is literally "bandit0" — published openly on overthewire.org)

# Once connected, find the password file:
bandit0@bandit:~$ ls
readme

bandit0@bandit:~$ cat readme
Congratulations on your first session!
The password you need for the next level is: <password masked>
```

> [!warning] Password Masking
> Bandit Level 1 password는 절대 commit에 포함시키지 마라. 실제 풀이 시 `<password masked>`로 치환 후 작성.

### 6. Why It Works
- `-p 2220`: overthewire는 ISP/network 정책 우회 + 일반 SSH 트래픽과 분리 위해 non-standard port 사용
- `bandit0@host`: SSH user 명시. 없으면 local username으로 시도 (예: WSL의 `jun`) → 서버에 그 계정 없음 → 인증 실패
- Level 0 password 공개: 진입 장벽 제거, 학습 시작점 제공
- `readme` 파일: ls로 즉시 노출됨 → 가장 단순한 file discovery 케이스

### 7. Edge Cases / Limitation
- **First-time fingerprint prompt**: 자동화 시 `-o StrictHostKeyChecking=accept-new` 또는 사전에 `ssh-keyscan`으로 등록 필요
- **NAT/Firewall에서 outbound 2220 차단**: 일부 학교/회사 네트워크에서 막힘. 우회: VPN 또는 다른 네트워크
- **Password 입력 자동화 비추**: `sshpass` 등 가능하나 보안 약화. 학습 목적상 수동 입력 권장

---

## [Phase 3] Formal Summary (EN)

> [!theorem] SSH Connection Establishment
> Given client $C$ with $(u, k_p^C)$ (username, public key) and server $S$ with port $p$ open and accepting protocol $v$:
> $$\text{ssh}(-p\ p,\ u@S) \implies \exists\ \text{TLS-like channel}\ \Pi: C \leftrightarrow S$$
> such that $\Pi$ is encrypted under negotiated cipher $E$, authenticated via host key $k^S$, and persists until either side issues `exit`.

> [!proof] Sketch
> 1. TCP three-way handshake on $(C_{ip}:*, S_{ip}:p)$
> 2. SSH version + KEX algorithm negotiation
> 3. Diffie-Hellman: $g^{ab} \mod q$ as shared secret, with $a, b$ private to each party
> 4. Host key signature verification: $\text{Verify}(k^S_{pub}, \sigma, m) \stackrel{?}{=} \text{true}$
> 5. User auth: $\text{Auth}(u, \text{credential})$
> 6. Channel multiplexing per RFC 4254

---

## [Phase 4] Better Methods

**Current approach**:
```bash
ssh -p 2220 bandit0@bandit.labs.overthewire.org
```

**Alternative 1**: `~/.ssh/config` alias
```
# ~/.ssh/config
Host bandit
    HostName bandit.labs.overthewire.org
    Port 2220
    User bandit0
```
Then: `ssh bandit`
Trade-off: 1회 setup, 매번 짧음. 하지만 level별로 user가 바뀌므로 (`bandit1`, `bandit2`...) — 매번 config 수정 필요. 한계 명확.

**Alternative 2**: Bash function
```bash
bandit() { ssh -p 2220 "bandit$1@bandit.labs.overthewire.org"; }
# Usage: bandit 0, bandit 1, ...
```
가장 elegant. Level number만 인자로. `.bashrc`에 영구 등록.

**Most elegant**:
```bash
# .bashrc
bandit() { ssh -p 2220 "bandit${1:-0}@bandit.labs.overthewire.org"; }
```
default 인자 `0`까지 처리. `bandit` 만 쳐도 Level 0 진입.

---

## [Phase 5] Lessons Learned

1. **Non-default port는 항상 명시**: ssh는 22가 default이지만 실세계 서버는 보안상 변경하는 경우 多.
2. **First-time fingerprint는 critical**: MITM 방어의 1단계. 자동 yes로 무시하지 말 것 — 실세계에선 fingerprint 사전 검증 필수.
3. **OverTheWire의 의도**: SSH는 모든 후속 level의 진입 메커니즘. 익숙해져야 마찰 없음.

### Quiz

**Q** (Graduate-level): SSH key exchange에서 client와 server 모두 *private key를 노출하지 않고* shared secret을 합의할 수 있는 수학적 기반은 무엇인가? 그리고 이 기반이 깨질 수 있는 두 가지 시나리오(현재 알려진/이론적)를 제시하라.

> [!tip]- 풀이
> **기반**: Discrete Logarithm Problem (DLP) — 또는 Elliptic Curve Discrete Logarithm Problem (ECDLP).
>
> DH의 경우: $g, p$ 공개, $a, b$ 비밀. $A = g^a \mod p$, $B = g^b \mod p$ 교환. Shared secret = $g^{ab} \mod p$. 도청자가 $g^{ab}$를 계산하려면 $g^a$로부터 $a$를 역산해야 하나, DLP는 sub-exponential time 이상 소요 (현재 알려진 best: General Number Field Sieve, $L_p[1/3, ...]$).
>
> **깨질 시나리오:**
> 1. **Quantum computing**: Shor's algorithm이 DLP를 polynomial time에 해결. RSA-2048 / DH-2048급 키는 충분히 큰 양자컴퓨터에서 즉시 깨짐. → 현재 NIST의 post-quantum cryptography 표준화 (CRYSTALS-Kyber 등) 진행 중.
> 2. **Weak parameter selection**: 작은 $p$ (≤ 768 bit) 또는 weak prime 사용 시 sub-exponential attack (NFS) 실현 가능. Logjam attack (2015) 사례: export-grade DH (512 bit)는 학술용 클러스터에서 시간 내 해결됨.

> [!flashcard]
> **Q**: SSH가 client에 server를 인증시키는 메커니즘은?
> **A**: Server의 host key 서명 → client의 `known_hosts` 파일과 fingerprint 대조. 일치하면 신뢰, 불일치면 MITM 의심 (warning 발생).

> [!flashcard]
> **Q**: `-p 2220`을 빼면 어떻게 되는가?
> **A**: SSH client는 default port 22로 연결 시도. OverTheWire 서버의 22번은 닫혀있거나 응답 없음 → connection timeout 또는 connection refused.

---

## Links

### Tools Used
- [[Tools/ssh]] *(planned)*
- [[Tools/ls]] *(planned)*
- [[Tools/cat]] *(planned)*

### Concepts Introduced (first encountered here)
- [[Concepts/Network/SSH_Protocol]] *(planned)*
- [[Concepts/Crypto/Public_Key_Authentication]] *(planned)*
- [[Concepts/Crypto/Diffie_Hellman_Key_Exchange]] *(planned)*

### Concepts Applied
- *(none — entry level)*

### Navigation
- **Prerequisite**: *(none — first level)*
- **Next**: [[Level_01]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Level 0 Official: https://overthewire.org/wargames/bandit/bandit0.html
- Bandit Level 1 Goal: https://overthewire.org/wargames/bandit/bandit1.html
- RFC 4251 (SSH Architecture): https://datatracker.ietf.org/doc/html/rfc4251
- RFC 4253 (SSH Transport): https://datatracker.ietf.org/doc/html/rfc4253
