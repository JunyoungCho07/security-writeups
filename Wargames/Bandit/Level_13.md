---
date: 2026-06-23
wargame: Bandit
level: 13
title: "Bandit Level 13 → 14"
difficulty: ★★☆
time_spent: 15min
tags: [bandit, linux, ssh, authentication, file-permissions]
status: 🟡 developing
tools_used: [ssh, scp, chmod, cat]
new_concepts: [SSH_Key_Authentication, File_Permissions]
prerequisites: [Level_12]
---

# Bandit Level 13 → 14

## [Phase 1] Executive Summary

- **Goal**: home의 `sshkey.private`(RSA private key)로 bandit14에 **공개키 인증** 로그인 → `/etc/bandit_pass/bandit14` 읽기. 단 level→level localhost SSH가 차단돼, 키를 **내 머신으로 반출**해 외부 IP로 우회해야 함
- **Key Skill**: `scp -P`로 키 반출 + `chmod 600`으로 권한 조임 + `ssh -i`로 키 지정 로그인
- **Tags**: `[SSH_Key_Authentication]`, `[File_Permissions]`, `[scp]`

[Cognitive Validation]
- **Limit Test**: 키 권한을 양 끝으로 보내면? 너무 닫으면(`0000`) ssh가 키 자체를 못 읽어 실패 — 이건 OpenSSH 정책이 아니라 `open()` EACCES(파일시스템 I/O). 너무 열면 OpenSSH **정책 게이트**가 `too open`으로 **무시**(`0640`은 group-read `& 077=0o040`, `0644`는 other-read `& 077=0o044` — 둘 다 트립). 작동 구간은 `owner-only`(0600/0400/0700)뿐 — 단 양 끝의 실패 **사유가 다르다**(I/O 불가 vs 정책 거부).
- **Control Knob**: 지배 변수는 **group/other 권한 비트**. 이 비트가 0이 아니면 OpenSSH 클라이언트가 키를 거부(보안 정책). owner는 read만 있으면 충분 — write/execute는 인증과 무관.
- **Nullity**: password 인증(Level 0~12)이 trivial 케이스. 거기선 네트워크에 **공유 비밀(shared secret)**을 흘린다. 공개키 인증은 그 비밀을 비대칭 키로 대체 — private key 소지 자체가 신원 증명이라 비밀이 선을 넘지 않는다.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**SSH 공개키 인증 + 자격증명 파일 위생(credential hygiene)**. 본질 명제 두 개가 맞물린다: ① 비밀번호 대신 **비대칭 키쌍**으로 신원을 증명한다, ② 그 private key 파일은 **owner만 접근 가능**해야 OpenSSH가 사용을 허락한다. 여기에 부수적으로 host 간 파일 전송(`scp`)과 OWTW의 **localhost 차단 토폴로지**가 얹힌다. Level 0~12에서 매번 쓰던 `ssh ... password` 흐름을, 처음으로 **키 기반(`ssh -i`)**으로 전환하는 분기점.

### 2. Definition (Formal, EN)

**SSH public-key authentication** lets a client prove possession of a private key *d* without transmitting it. Given a keypair (*e*, *d*) where the public key *e* is registered in the server's `~/.ssh/authorized_keys`, the server issues a random challenge; the client returns a signature σ = Sign_*d*(challenge); access is granted iff Verify_*e*(challenge, σ) = true. No shared secret crosses the wire — security reduces to the infeasibility of producing σ without *d*. The OpenSSH **client** additionally enforces a local gate: it loads an identity file *K* only if *K* is inaccessible to group/other, i.e. (mode(*K*) & 0o077) = 0.

### 3. Intuition (KR)

private key = **인감도장**(나만 가진 도장), public key = 관공서에 등록된 **인감증명**. 도장 자체를 보내지 않고 "도장 찍은 서류"(서명)만 보여 신원을 증명한다. 그리고 그 도장은 **금고(owner-only 권한)**에 보관해야 한다 — 남이 만질 수 있는 책상에 두면 위조 위험이라, OpenSSH는 아예 "이 도장은 못 믿겠다"며 사용 자체를 거부한다.

### 4. Theory (Mechanism)

네 가지 메커니즘이 맞물린다:

1. **Key pair / PEM**: `sshkey.private`은 `BEGIN/END RSA PRIVATE KEY` 블록의 PKCS#1 PEM(여기선 2048-bit RSA, ~1679 bytes). 대응 public key는 bandit14의 `authorized_keys`에 이미 등록돼 있어, 이 private key 소지자는 password 없이 로그인.
2. **Challenge-response**: 서버가 nonce를 던지면 클라이언트가 *d*로 서명. 서버는 *e*로 검증. private key가 네트워크를 건너지 않음 → 도청해도 무의미.
3. **Permission gate (client-side)**: scp로 받은 키의 모드(여기선 `0640` — 원본 모드와 로컬 umask에 따라 결정)가 group/other에 열려 있으면 OpenSSH가 `UNPROTECTED PRIVATE KEY FILE` 경고 후 **키를 무시**하고 password로 fallback. 멀티유저 시스템에서 키가 새면 신원 전체가 털리므로 클라이언트가 선제적으로 강제.
4. **localhost block (OWTW policy)**: 자원 절약 + 학습 의도로 level→level localhost SSH를 차단. 따라서 키를 **내 로컬 머신**으로 `scp`해 외부 IP(`bandit.labs.overthewire.org`)로 재접속.

인과 사슬: `sshkey.private`(조건) → `scp -P 2220`로 로컬 반출(B) → `chmod`로 권한 조임(C) → `ssh -i`로 키 인증 통과(D) → bandit14 쉘 → `cat /etc/bandit_pass/bandit14`(E).

### 5. Solution

```bash
# === bandit13 접속 (password 인증) ===
$ ssh -p 2220 bandit13@bandit.labs.overthewire.org
# Password: <password masked>
#   -p 2220: ssh의 포트 지정(소문자 p). OWTW 전용 포트 — 기본 22 아님

bandit13@bandit:~$ ls
HINT  sshkey.private
bandit13@bandit:~$ cat sshkey.private
# 출력: PEM 형식 RSA private key 블록 (~1679 bytes)
# → 본문은 credential이므로 writeup에 옮기지 않는다 (commit 금지)

# --- 삽질 1: 서버에서 곧장 다음 레벨로 SSH → localhost 차단 ---
bandit13@bandit:~$ ssh -i sshkey.private bandit14@bandit.labs.overthewire.org -p 2220
#   -i sshkey.private: identity file 지정 — 이 private key로 인증 시도
#   → "Could not create directory '/home/bandit13/.ssh'" (home read-only라 known_hosts 못 씀)
#   → "Connecting from localhost is blocked to conserve resources"
#   교훈: 키를 '내 머신'으로 가져와 외부에서 접속해야 한다
bandit13@bandit:~$ exit

# === 로컬 머신: 키 반출 ===
$ cd /tmp

# --- 삽질 2: scp에 포트 안 줌 → 기본 22로 가서 거부 ---
$ scp bandit13@bandit.labs.overthewire.org:~/sshkey.private .
#   → port 22로 접속 → "port 22, which is not intended" → Permission denied (publickey)
#   교훈: scp의 포트 플래그는 대문자 -P (ssh는 소문자 -p)

# --- 정상: 대문자 -P로 포트 지정해 반출 ---
$ scp -P 2220 bandit13@bandit.labs.overthewire.org:~/sshkey.private .
#   scp <source> <target> 형식
#     source = bandit13@host:~/sshkey.private  (원격 경로)
#     target = .                                (현재 디렉토리)
#   -P 2220: 원격 SSH 포트(대문자!). password 인증으로 파일만 끌어온다
# Password: <password masked>
# sshkey.private                       100% 1679 ...

# --- 삽질 3: 권한 too open → OpenSSH가 키 무시 ---
$ ssh -i sshkey.private bandit14@bandit.labs.overthewire.org -p 2220
#   → "Permissions 0640 for 'sshkey.private' are too open ... This private key will be ignored"
#   scp로 받은 파일 모드가 0640(group-read; 원본 모드+로컬 umask 결과) → too open → 거부 → password fallback
#   교훈: private key는 owner 외 접근이 0이어야 한다

# --- 정상: 권한 조이고 재접속 ---
$ chmod 700 sshkey.private
#   700 = rwx------ : group/other 비트가 0이라 OpenSSH 게이트 통과
#   (단 키 파일에 실행권 x는 불필요 → 정석은 600. Phase 4 참조)
$ ssh -i sshkey.private bandit14@bandit.labs.overthewire.org -p 2220
#   이번엔 키 권한 OK → 공개키 인증 성공 (password 입력 없이 로그인!)

# === bandit14 쉘 ===
# --- 삽질 4: pass 파일을 디렉토리로 착각 ---
bandit14@bandit:~$ cd /etc/bandit_pass/bandit14
# -bash: cd: /etc/bandit_pass/bandit14: Not a directory
#   bandit14는 '파일'이지 디렉토리가 아니다 → cd가 아니라 cat
bandit14@bandit:~$ cat /etc/bandit_pass/bandit14
<password masked>                    # ← bandit14 (Level 14) password
```

> [!warning] Password & Key Masking
> 최종 password는 `<password masked>`로 치환. **private key 본문은 절대 옮기지 않는다** — PEM 블록 자체가 credential이고, write-guard/pre-commit 훅이 고엔트로피 문자열로 잡는다. 학습엔 "PEM RSA 키 ~1679B" 같은 메타 기술로 충분.

> [!tip] ssh `-p` vs scp `-P` — 왜 대소문자가 갈리나
> `ssh -p 2220`, **`scp -P 2220`**. 같은 "포트"인데 케이스가 다른 건 일관성이 아니라 **flag namespace 충돌 회피**의 결과다. scp는 "cp over ssh"라 BSD `rcp`/POSIX `cp -p`에서 소문자 `-p` = *preserve*(원본 mode·mtime 보존)를 물려받았다 — `cp -p`는 ssh보다 수십 년 앞선다. 소문자가 선점돼 있어 port가 대문자 `-P`로 밀렸고, ssh는 'preserve' 개념이 없어 `-p`가 비어 port를 차지. 잘못 쓰면 flag 에러도 없이 port가 기본 22로 남아 **조용히** 거부된다(삽질 2).
> 회피책: 둘 다 `-o Port=2220`을 받는다(scp는 `-o`를 ssh로 패스) → 케이스 함정 자체를 우회.

### 6. Why It Works

bandit14의 `authorized_keys`에 대응 public key가 등록돼 있어, 그 private key 소지자는 challenge-response를 통과해 **비밀번호 없이** 로그인한다. localhost 차단은 네트워크 토폴로지 제약일 뿐 인증 메커니즘과 무관 — 동일 키를 외부 머신으로 옮기면 외부 IP에서 그대로 동작한다. `chmod`은 서버가 아니라 **클라이언트 측 보안 게이트**를 통과시키는 작업: OpenSSH가 "이 키는 남이 못 본다"고 확인해야 비로소 키를 로드한다. 마지막 `cat`은 bandit14 권한으로 `/etc/bandit_pass/bandit14`를 읽는 것 — 이 파일은 소유자 bandit14만 read 가능하도록 설정돼 있고, 우리는 방금 그 사용자가 됐다.

### 7. Edge Cases / Limitation

- **권한이 너무 닫혀도 실패 — 단 사유가 다름**: `0000`이면 ssh가 로드 불가하나, 이는 OpenSSH의 `(mode & 077)` 정책이 아니라 `open()`이 못 읽어서(EACCES)다. OpenSSH 정책은 "too **open**"만 거부 — 즉 정책 게이트(`& 077 == 0`)와 가독성(owner read)은 **별개 메커니즘**.
- **`known_hosts` 쓰기 불가**: home이 read-only면 host 검증 경고만 뜨고 진행은 가능(기본 `StrictHostKeyChecking=ask`). bandit13에서 `.ssh` 디렉토리 생성 실패 메시지가 그 증거.
- **passphrase 보호 키**: 만약 private key가 passphrase로 암호화돼 있으면 `chmod`만으론 부족 — passphrase도 필요. 이 키는 무암호라 권한만 맞추면 끝.
- **OpenSSH 9+ scp**: 최신 scp는 내부적으로 SFTP 프로토콜을 쓴다. 동작은 동일하나 일부 레거시 서버엔 `-O`로 옛 SCP 프로토콜 강제가 필요한 엣지가 있음.
- **localhost 차단은 OWTW 정책**: 환경마다 다르다. 차단이 없다면 서버에서 바로 `ssh -i`로도 풀린다 — 이 level의 우회는 정책 산물이지 키 인증의 본질이 아니다.

---

## [Phase 3] Formal Summary (EN)

> [!definition] SSH Public-Key Authentication
> Authentication in which a client proves possession of a private key *d* without transmitting it. For keypair (*e*, *d*) with *e* ∈ server's `authorized_keys`: server sends challenge *c*; client returns σ = Sign_*d*(*c*); access granted iff Verify_*e*(*c*, σ) = ⊤. No shared secret traverses the network; ∴ eavesdropping yields nothing forgeable without *d*.

> [!theorem] OpenSSH Private-Key Permission Gate
> OpenSSH's *policy* check (StrictModes, file owned by the user) rejects identity file *K* iff (mode(*K*) & 0o077) ≠ 0 — any group/other bit set. So **0600, 0400, 0700 pass**; **0640 (group-read), 0644 (other-read), 0660 fail** ⇒ key ignored ⇒ auth falls back to password/keyboard-interactive. Distinct mechanism: if the owner lacks read (e.g. 0000) the key fails *earlier* at open()/EACCES, not via this policy. The policy is client-local, not a server-side authentication failure.

> [!proof] why a violation *ignores* the key rather than aborting
> Refusing the connection outright would deny the user every *other* legitimate method (password, agent). The conservative action is to drop only the untrusted credential and continue, so fallback to a remaining auth method is the strictly safer default. ∎

---

## [Phase 4] Better Methods

**Current approach** (used above): `scp -P` 반출 → `chmod 700` → `ssh -i`. 학습엔 명확하나 권한 값이 헐렁(700).

**Alternative 1**: 정석 권한 600
```bash
chmod 600 sshkey.private    # rw------- : owner read+write, group/other 전무
```
Trade-off: 기능은 700과 동일(둘 다 게이트 통과)하나, 키 파일은 **실행 대상이 아니므로** x 비트는 의미 없는 권한. 최소권한 원칙(least privilege)상 불필요한 비트 제거 → 600이 의도를 정확히 표현. `0400`(read-only)도 가능 — 한 번 받은 뒤 수정할 일 없으면 더 엄격.

**Alternative 2**: scp 없이 stdout 파이프로 키 직접 끌어오기
```bash
ssh -p 2220 bandit13@bandit.labs.overthewire.org 'cat ~/sshkey.private' > sshkey.private
#   'cat ~/sshkey.private': 원격에서 실행할 명령(인터랙티브 쉘 대신 명령 1개 실행 후 종료)
#   > sshkey.private: 원격 stdout을 로컬 파일로 리다이렉트
chmod 600 sshkey.private
```
Trade-off: scp의 `-P` 대소문자 함정(삽질 2)을 원천 회피. 단 password 1회 입력 필요하고, 파일 메타데이터(perm)는 안 따라오니 `chmod`은 여전히 필수.

**Most elegant** (반출→권한→인증→추출 한 줄):
```bash
ssh -p 2220 bandit13@bandit.labs.overthewire.org 'cat ~/sshkey.private' > k \
  && chmod 600 k \
  && ssh -i k -p 2220 bandit14@bandit.labs.overthewire.org 'cat /etc/bandit_pass/bandit14'
```
Why elegant: "키 반출 → 권한 → 키 인증 → password 추출"을 `&&` 체인 하나로. 각 단계의 **exit code 0**일 때만 다음으로 진행([[Concepts/Linux/Exit_Code]] 응용) — 중간 실패 시 즉시 멈춰 잘못된 상태로 진행하지 않음.
- `'cat ...'` (원격 명령): 마지막 ssh는 인터랙티브 쉘을 띄우지 않고 원격에서 `cat` 한 방 실행 → password가 로컬 stdout으로 즉시. 끝나면 연결 자동 종료.
- `-i k`: identity file로 방금 받은 키 `k` 지정.
- `-p 2220`: (양쪽 ssh 모두) OWTW 포트.
- `> k`: 첫 ssh의 원격 stdout(키 내용)을 로컬 파일 `k`로.

---

## [Phase 5] Lessons Learned

1. **SSH 포트 플래그 대소문자**: `ssh -p`(소문자), `scp -P`(대문자). scp의 `-p`는 *preserve*라 의미가 다르다 — 틀리면 기본 22로 가서 거부.
2. **private key 권한은 owner-only**: group/other 비트가 하나라도 서면 OpenSSH가 키를 **무시**하고 password로 fallback. `(mode & 077)==0`이 게이트. 700도 통과하나 x 불필요 → **600이 정석**.
3. **localhost→localhost SSH 차단(OWTW 정책)**: 자격증명/키를 **내 머신으로 반출**해 외부 IP로 우회. 이 level의 진짜 함정.
4. **공개키 인증 = private key 소지 증명**: 비밀번호(공유 비밀)를 네트워크에 흘리지 않는 비대칭 인증. 도청 내성의 근원.
5. **`/etc/bandit_pass/banditN`은 파일이지 디렉토리 아님** — `cd` 아니라 `cat`. `Not a directory` 에러가 그 신호.

### Quiz

**Q**: OpenSSH는 private key가 group-readable일 때 왜 인증 자체를 막지 않고 단지 "키만 무시"하는가? `chmod 700`이 통과하는데도 `600`을 권장하는 보안 원칙은? 그리고 `authorized_keys`(public key 쪽) 권한이 너무 열려 있을 때의 위협은 private key의 경우와 어떻게 **비대칭**인가?

> [!tip]- 풀이
> **키 무시 vs 차단**: 권한 위반은 *클라이언트 로컬 정책*("이 키는 위험하니 안 쓴다")이지 서버 인증 실패가 아니다. 그래서 위험한 키 하나만 배제하고 password·agent 등 **남은 정당한 수단으로 자연 fallback**. 연결 자체를 끊으면 사용자가 다른 합법적 방법조차 못 쓰게 되니, 보수적 동작은 "문제 자격증명만 드롭"이다.
>
> **700 vs 600**: 둘 다 `(mode & 077)==0`이라 게이트 통과. 그러나 키 파일은 실행 객체가 아니므로 x 비트는 *무의미한 권한*. 최소권한 원칙상 불필요한 비트는 제거 — 600(또는 read-only 400)이 의도를 정확히 표현.
>
> **비대칭 위협 모델**: private key는 **기밀성(confidentiality)**이 생명 — read 노출이 치명적. authorized_keys는 **무결성(integrity)**이 생명 — read는 무방(public key는 공개여도 됨)하나 *write* 노출이 치명적(공격자가 자기 public key를 주입해 백도어). 그래서 sshd는 `StrictModes=yes`일 때 `~/.ssh`·`authorized_keys`가 group/other-**writable**이면 거부한다.
>
> 핵심: private key는 기밀성, authorized_keys는 무결성이 위협 축. 같은 SSH 인증이라도 보호 대상이 정반대.

> [!flashcard]
> **Q**: ssh uses `-p` for port; what does scp use, and what does scp's lowercase `-p` mean?
> **A**: scp uses capital **`-P`** for port. Lowercase `-p` in scp means *preserve* (copy mtime/mode). Wrong case ⇒ port stays default 22 ⇒ rejected.

> [!flashcard]
> **Q**: OpenSSH prints "Permissions 0640 ... too open". Exact rule and two fixes?
> **A**: Client refuses the identity file when (mode & 0o077) ≠ 0 (any group/other bit). Fix: `chmod 600 key` (or `chmod 400 key`); then the key loads and key-auth proceeds.

---

## Links

### Tools Used
- [[Tools/ssh]]
- [[Tools/scp]]
- [[Tools/chmod]]
- [[Tools/cat]]

### Concepts Introduced (first encountered here)
- [[Concepts/Network/SSH_Key_Authentication]]
- [[Concepts/Linux/File_Permissions]]

### Concepts Applied (reused from earlier)
- [[Concepts/Linux/Exit_Code]] (Better Methods의 `&&` 체인 — 단계별 exit 0 의존)
- Password-based SSH auth (Level 00~12의 접속 방식 → 여기서 키 기반으로 전환)

### Navigation
- **Prerequisite**: [[Level_12]]
- **Next**: [[Level_14]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit14.html
- `ssh(1)` (`-i`, `-p`), `scp(1)` (`-P` vs `-p`), `chmod(1)`
- OpenSSH `authfile.c` permission check — `(st.st_mode & 077) != 0`
