---
date: 2026-06-24
domain: Network
topic: SSH_Key_Authentication
tags: [ssh, authentication, asymmetric-crypto, public-key]
status: 🟡 developing
mastery: 0
first_encountered: [[Wargames/Bandit/Level_13]]
reapplied_in: []
last_reviewed: 2026-06-24
---

# SSH_Key_Authentication

## Core Idea (1-2 sentences, KR)

비밀번호라는 **공유 비밀(shared secret)**을 네트워크에 흘리는 대신, private key로 세션 고유 메시지에 **서명**해 "나는 이 키의 소유자다"를 증명하는 비대칭 인증. 비밀은 절대 선을 넘지 않는다.

---

## [Step 1] Concept Categorization

**Challenge-response 기반 entity authentication**의 비대칭 변종. 구조적 DNA 세 겹:
1. **Digital signature의 응용** — "소지 증명(proof of possession)": 비밀을 드러내지 않고 비밀을 안다는 사실만 증명.
2. **대칭 ↔ 비대칭의 분기점**: password/HMAC(공유 비밀)이 아니라 키쌍(공개/개인).
3. **SSH userauth layer의 한 method**(RFC 4252 §7) — transport layer(암호화·서버 인증)가 깔린 위에서 동작하는 *사용자* 인증.

## [Step 2] Definition

> [!definition] SSH Public-Key Authentication
> A challenge-response entity-authentication method (RFC 4252 §7). Let (e, d) be a keypair with public key e stored in the verifier's `authorized_keys`. The prover authenticates by sending σ = Sign_d(M) where
> M = ( session_id ‖ MSG_USERAUTH_REQUEST ‖ user ‖ service(="ssh-connection") ‖ "publickey" ‖ TRUE ‖ alg ‖ e ), where *service* is RFC 4252's variable service-name field (value here = "ssh-connection").
> Access is granted iff Verify_e(M, σ) = ⊤ ∧ e ∈ authorized_keys. The **session_id = H** (the exchange hash of the transport-layer key exchange) is bound into M, so σ is non-replayable across sessions.
^definition

**내 언어로 (KR)**: 서버가 가진 건 public key뿐이다. 클라이언트는 "이번 세션 고유값(session_id)"을 포함한 메시지에 private key로 서명해 보낸다. 서버는 public key로 그 서명을 검증한다. 서명이 맞고 그 key가 `authorized_keys`에 있으면 통과. private key는 네트워크를 건너지 않는다 — 그래서 도청해도 훔칠 게 없다.

## [Step 3] Intuition

> [!tip] Intuition
> 인감도장(private key)은 절대 우편으로 부치지 않는다. 매번 관공서가 주는 "**오늘자 고유번호가 찍힌 종이**(session_id)"에 도장을 찍어(서명) 돌려보낼 뿐. 번호가 매번 달라서 어제 찍은 종이를 재탕할 수 없다.
^intuition

## [Step 4] Theory

안전성은 **두 축**의 곱이다:
1. **서명 위조 불가능성(EUF-CMA)**: private key 없이는 유효한 σ를 만들 수 없다 — RSA-PKCS#1/PSS, ECDSA, Ed25519의 표준 가정.
2. **private key 기밀성**: 키가 새면 끝. 이건 수학이 아니라 운영(파일 권한·passphrase·agent)의 문제.

여기에 **session_id 바인딩**이 replay·MITM을 막는다. 공격자가 σ를 캡처해도 다음 세션의 session_id가 달라 M이 바뀌므로 재사용 불가. MITM은 그 전에 transport layer의 **host key 검증**에서 1차 차단된다(서버가 먼저 자기 신원을 증명). 결정적으로, 서버는 private key를 **모르므로**, `authorized_keys` DB가 통째로 유출돼도 사용자를 사칭할 수 없다 — password hash 유출과 정반대.

## [Step 5] When & Condition

holds 조건:
- public key가 서버 `~/.ssh/authorized_keys`에 **사전 등록**돼 있어야.
- 클라이언트가 대응 private key에 접근 가능 — 파일 + **올바른 권한**(`(mode & 077)==0`), 또는 ssh-agent.
- transport layer 성립: host key 검증 통과 + 키 교환(보통 curve25519 ECDH) 완료.
- 서명 알고리즘 협상 일치(`ssh-ed25519`, `rsa-sha2-256/512`, `ecdsa-sha2-*`).

## [Step 6] Limitation & Alternatives

- **한계**: private key *at rest* 보호가 사람 손에 달림 — 무passphrase 키는 파일 소지 = 전권. 키 폐기(revocation)가 password 변경보다 번거롭다(`authorized_keys` 수동 관리). 스케일에서 키 배포·회수가 골칫거리.
- **우월한 대안**:
  - **SSH certificates**: CA가 키에 서명 → `authorized_keys` 수동관리 제거, **만료·폐기 내장**. 대규모 인프라의 정답.
  - **FIDO2/U2F-backed keys**(`ed25519-sk`): 하드웨어 소지를 강제 — 파일 복사만으론 못 훔침.
  - **Kerberos/GSSAPI**: 중앙 티켓 인증. password+TOTP(2FA): 다른 trade-off.

> [!warning] "키가 password보다 항상 안전하다"는 과장이다
> 무passphrase private key + **agent forwarding**은 종종 password보다 **위험**하다. 키를 한 번 훔치면 그 키가 닿는 모든 서버가 뚫리고(횡적 이동), forwarding된 agent는 중간 서버 root에게 탈취당한다. 안전한 건 "키"가 아니라 "passphrase로 잠근 키 + agent 미forwarding + 짧은 수명 cert"라는 *운영*이다.

## [Step 7] Duality & Null Space

- **Dual**: 공개키 암호의 두 얼굴 — encryption(공개키로 봉인, 소유자만 개봉) ↔ **signature**(소유자만 서명, 누구나 검증). 인증은 *signature* 쪽이다. RSA는 같은 키쌍이 양쪽에 쓰이나 역할이 dual.
- **Null space**: private key 없이 σ를 위조할 확률 ≈ negligible. 단 session_id가 **상수(고정)**라면 M이 고정 → σ 재사용 가능 → null space가 열린다. 따라서 session_id의 **세션별 유일성**이 보안의 영점(zero)을 닫는 조건.

## [Step 8] Validation

- **Limit Test**: 키 길이 → ∞면 위조 불가하나 연산비↑; → 작으면(RSA-512) 인수분해로 붕괴. session_id 엔트로피 → 0(상수)이면 replay 천국.
- **Dimensional Check**: σ는 `(d, M)` 쌍에만 유효한 함수값. M의 1비트만 바뀌어도 검증 실패(avalanche) — 차원이 정확히 키쌍×메시지에 묶임.
- **Control Knob**: 지배 변수 = **private key 기밀성**. 0(유출)이면 알고리즘·키길이가 아무리 강해도 전체 붕괴. 나머지는 2차 변수.

## [Step 9] Advanced Perspective

서명 기반 인증은 **proof of knowledge(Σ-protocol)**의 비대화형 사례로 추상화된다: "나는 d를 안다"를 d를 노출하지 않고 증명. 대화형 challenge-response를 **Fiat-Shamir 변환**으로 비대화형 서명으로 접은 것 — 여기서 session_id가 challenge(검증자 신선도) 역할을 한다. 또한 **forward secrecy**는 transport layer의 ephemeral ECDH가 담당하고 auth layer와 분리돼 있다(관심사 분리): 인증과 기밀성은 독립적으로 깨지거나 유지된다.

## [Step 10] Link to Upper Concepts

PKI → Digital Signature → Asymmetric Cryptography → Entity Authentication → Zero-Knowledge Proof. SSH 공개키 인증은 이 추상 계층의 구체적 엔지니어링 인스턴스 하나다.

## [Step 11] Generalization

- **n-party**: 같은 public key를 N개 서버 `authorized_keys`에 등록 → 1 key로 N 서버 SSO. CA로 일반화하면 1 CA가 M 키를 보증 → `authorized_keys` 폭발 제거.
- **일반 구조**: (Prover가 secret 소지) × (Verifier가 public commitment 보유) × (fresh challenge) → **non-transferable proof**. TLS client cert, JWT 서명, WebAuthn/passkey, 블록체인 트랜잭션 서명이 전부 이 구조의 동형(isomorphic) 사례.

## [Step 12] Confer (Comparison)

- **vs. Password Auth**: 공유 비밀 전송(O→네트워크 노출) vs 미전송(X); 서버가 비밀 저장(hash) vs **public만**; phishable vs 상대적 내성; brute-force 표적 vs 키공간 무한. 서버 침해 시 password는 사칭 가능(hash crack), 키는 불가.
- **vs. Symmetric challenge-response(HMAC)**: 양측이 같은 비밀 공유 vs 비대칭. 대칭은 검증자도 위조 가능 → **부인방지(non-repudiation) 없음**. 비대칭은 서명자만 생성 가능 → 부인방지 성립.
- **vs. TLS mutual auth(client cert)**: 본질 동일(소지 증명), 신뢰 모델만 다름 — SSH는 TOFU/`authorized_keys`, TLS는 **CA chain**.

## [Step 13] Implication

서버 침해가 클라이언트 사칭으로 **직결되지 않는다**(서버엔 public만 존재) — 대규모 인프라 인증의 표준이 된 핵심 이유. 자동화(무인 배포·CI·Git)에서 사람이 password를 칠 수 없는 영역을 키가 메운다. 대가: 무passphrase 키의 "소지 = 전권" 속성이 새로운 attack surface를 연다.

## [Step 14] Application

- **보안**: SSH 원격 로그인([[Wargames/Bandit/Level_13]]), Git over SSH, Ansible/CI 배포, SFTP, port forwarding 인증. ssh-agent / agent forwarding(편의 vs 탈취 위험).
- **일반**: 동일 원리가 TLS client certificate, code signing, WebAuthn/passkey(생체+하드웨어), 암호화폐 지갑(서명으로 UTXO 소유 증명)에 그대로.

## [Step 15] Background Knowledge

- **SSH**: 1995년 Tatu Ylönen(헬싱키 공대)이 캠퍼스 password-sniffing 공격을 겪고 SSH-1 개발. SSH-1의 보안 결함 → **SSH-2**(1996년경 설계·배포, 2006년 IETF 표준화 RFC 4251–4254). **OpenSSH**(OpenBSD, 1999~)가 사실상 표준 구현.
- **공개키 암호의 뿌리**: Diffie–Hellman 1976, RSA 1977. **Ed25519**(D. J. Bernstein, 2011)가 현재 권장 — 작고 빠르고 nonce 오용에 강함.
- Level 13의 키는 PKCS#1 PEM(헤더 `-----BEGIN/END RSA PRIVATE KEY-----`, 2048-bit); 요즘 OpenSSH 기본 생성 포맷은 `-----BEGIN/END OPENSSH PRIVATE KEY-----`(bcrypt-KDF로 passphrase 보호).

---

## Formal Summary (EN)

> [!theorem] Non-Replayability of SSH Public-Key Authentication
> If the signature scheme is EUF-CMA secure and session_id is unique per session (the exchange hash H over fresh ephemeral DH publics is collision-resistant), then a captured signature σ from session S₁ authenticates in session S₂ ≠ S₁ only with negligible probability.

> [!proof] Sketch
> σ = Sign_d(M₁) with M₁ ∋ session_id₁. In S₂ the verifier recomputes M₂ ∋ session_id₂. H mixes fresh ephemeral DH publics ⟹ session_id₁ ≠ session_id₂ w.h.p. ⟹ M₁ ≠ M₂. Then Verify_e(M₂, σ) = ⊥ unless the adversary produced Sign_d(M₂) without d — contradicting EUF-CMA. ∴ replay fails except with negligible probability. ∎

---

## Cross-References

### Encountered In
- [[Wargames/Bandit/Level_13]] ← first

### Tools That Implement This
- [[Tools/ssh]] (`-i` identity file; client side)
- [[Tools/ssh-keygen]] (keypair generation, `authorized_keys` 관리)

### Related Concepts
- [[Concepts/Linux/File_Permissions]] (Prerequisite — private key는 owner-only가 강제)
- [[Concepts/Crypto/Asymmetric_Cryptography]] (Prerequisite — 키쌍의 수학적 토대)
- [[Concepts/Crypto/Digital_Signature]] (Related — 인증의 실제 primitive)

### Cross-Domain
- [[Concepts/Crypto/Digital_Signature]] (same structure: TLS client cert·code signing·passkey 모두 동형)

---

## Quiz

**Q1** (Graduate-level): SSH 공개키 인증에서 클라이언트가 서명하는 메시지 M에 **session_id가 반드시 포함**되어야 하는 이유를 공격 시나리오로 설명하라. 만약 M = (user ‖ "publickey" ‖ e)로만 서명한다면(session_id 누락) 어떤 공격이 가능한가? 그리고 이 보호가 transport layer의 host key 검증과 **어떻게 역할이 다른가**?

> [!tip]- 풀이
> **session_id 누락 시 공격**: M이 세션과 무관해져 σ가 **세션-독립**이 된다. 악성 서버/MITM이 받은 σ를, **클라이언트의 같은 public key가 authorized된 다른 서버 S**로 relay하면 다른 세션에서 그대로 통과 → S에 클라이언트로 로그인된다. (서명엔 *서버 신원*이 안 묶여 있어 — session_id만이 σ를 "이 세션"에 못박는 유일한 끈이다.) session_id가 H(이번 세션 ephemeral DH 결과)를 묶으면 M이 세션마다 달라 relay가 깨진다. **단** 이 공격은 같은 키가 S에 authorized돼 있어야 성립 — "아무 서버나 사칭"이 아니다.
>
> **host key 검증과의 차이(관심사 분리)**: host key 검증은 transport layer에서 **서버 → 클라이언트** 방향 인증("내가 접속한 서버가 진짜냐")이고 채널 암호화의 신뢰 기반이다. session_id 바인딩은 auth layer에서 **클라이언트 서명의 신선도**를 보장한다. 둘은 독립 — host key를 통과해도 session_id 없으면 replay가 남고, session_id가 있어도 host key 미검증이면 MITM 채널 위에서 인증하는 셈. 그래서 **둘 다** 필요하다.
>
> 핵심: session_id는 서명을 "이 세션"에 못박는 nonce — replay의 null space를 닫는다.

---

> [!flashcard]
> **Q**: SSH 공개키 인증에서 서버 `authorized_keys` 파일이 통째로 유출되면 공격자는 사용자를 사칭할 수 있는가?
> **A**: 불가. `authorized_keys`엔 **public key**만 있다. 사칭엔 private key 서명이 필요한데 서버는 그걸 모른다. (← password hash 유출이 crack→사칭으로 이어지는 것과 정반대. 그래서 위협 축이 다르다: private key=기밀성, authorized_keys=무결성.)

> [!flashcard]
> **Q**: 공개키 인증이 password보다 무조건 안전하다 — 맞나?
> **A**: 아니다. 무passphrase 키 + agent forwarding은 "키 1개 탈취 → 전 서버 횡적 이동"으로 password보다 위험할 수 있다. 안전한 건 키 자체가 아니라 passphrase·짧은 수명 cert·agent 비forwarding이라는 *운영*이다.
