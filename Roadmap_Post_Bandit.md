---
date: 2026-07-23
doc_type: roadmap
scope: post-bandit-direction
tags: [roadmap, wargame, planning, pwn, web, reversing, crypto]
status: 🟢 active
research: "overnight workflow — 5 tracks · 15 agents · 9 decision-critical claims adversarially CONFIRMED (free/online/maintained/difficulty/prereqs)"
---

# Roadmap — Post-Bandit (다음 워게임 방향)

> OverTheWire **Bandit 0→34 졸업**(2026-07-23) 후 다음 행선지. 밤샘 리서치 워크플로 결과를 개인화 정리.
> **한 줄:** 이번 주 **Leviathan**(Bandit 직속 후계) → 몇 달짜리 척추 **pwn.college**. **웹(Natas)**은 무-C 병렬 companion.

## 왜 이 조합인가 (프로필 앵커)

- **가장 큰 신호 = 시스템/바이너리.** 세션에서 `fork`/`execve`·tty/pty·setuid/RUID·ELF·git 내부를 *가장 깊게* 팜 → 목적지는 **pwn/reversing**, web 아님.
- **C 갭은 규칙으로 해결.** "C 먼저 따로" 금지(동기 킬러). pwn.college가 asm/C를 **익스플로잇 맥락에서** 가르쳐 → 프리퀴짓이 곧 커리큘럼.
- **자력풀이·노스포일러 스타일** → 전부 attempt-first / hint-not-spoiler(OTW·pwn.college·picoGym·crackmes·CryptoHack). 가이드형 TryHackMe/HTB-main은 후순위.
- **웹(정정 반영):** 진짜 좋아함 — Bandit에 웹이 없어 안 보였을 뿐. 마찰 0의 **병렬 트랙**으로 편입(단 시스템 신호가 더 커 spine 아닌 companion).

## 🏃 이번 주 (지금 바로): OverTheWire Leviathan

```bash
ssh leviathan0@leviathan.labs.overthewire.org -p 2223
```

- Bandit과 **똑같은** SSH→상자-쑤시기 루프, 단 대상이 텍스트파일 → **setuid 바이너리**. `ltrace`/`strace`/`gdb`/`strings`/`objdump`가 게임 전체.
- 8레벨 · 1/10 · 무료·온라인 확인. **지시문 없음** → 목표 추론 훈련(체감 Bandit보다 살짝 ↑).
- ⚠️ **규율**: `ltrace` 속풀이 금지. 최소 3레벨은 `objdump`/`gdb`로 바이너리를 **직접 읽어라** — 안 그러면 Narnia가 절벽.
- 이건 **다리(bridge)**지 목적지가 아니다.

## 🧗 척추 (0~2개월): pwn.college

`Start Here` → `Linux Luminarium`(Bandit 겹침 — 플랫폼 익히고 벨트 win) → **`Computing 101`**(레지스터/메모리/**스택**/어셈블리 0부터 = "기계 밑바닥" 그 자체) → `Playing With Programs`.
- 무료 · ASU 유지(2026 갱신 확인) · 벨트제(white→…→blue) · hint-not-spoiler.
- **"C 몰라"를 커리큘럼으로 녹임** — 스택 스매싱 전에 substrate 먼저.
- https://pwn.college/

## 🧭 방향별 최선책

| 방향 | 픽 | 왜 | 링크 |
|---|---|---|---|
| **Web** 🌐 (선호) | Natas → PortSwigger Academy | Natas=브라우저+curl·**무-C**·vault가 `<<Natas N>>` 이미 라우팅(오늘 시작·writeup 그대로). 단 topic pivot·구식 PHP. 진짜 깊이는 PortSwigger(200+ 무료랩, Burp Community 무료, 업계 최고 무료 교육). | [Natas](https://overthewire.org/wargames/natas/) · [PortSwigger](https://portswigger.net/web-security) |
| **Pwn** 💥 | pwn.college `Program Security` (Computing101 후) / OTW Narnia→Behemoth | 초심자 최적: substrate 먼저. Narnia는 소스 제공(2/10)이라 첫 진짜-pwn 적합(단 Computing 101 후). | [pwn.college](https://pwn.college/) · [Narnia](https://overthewire.org/wargames/narnia/) |
| **Crypto** 🔐 | CryptoHack (Krypton 워밍업) | Bandit식 선형 스캐폴딩 + **Python**(C보다 가벼운 리프트). | [CryptoHack](https://cryptohack.org/) · [Krypton](https://overthewire.org/wargames/krypton/) |
| **Reversing** 🔬 | microcorruption | 브라우저 디버거(설치 0)·**무-C**·어셈 0부터. 레지스터/스택 호기심 직결. | [microcorruption](https://microcorruption.com/) |

## 🗺 멀티-먼스 로드맵

| 시기 | 할 것 | 목적 |
|---|---|---|
| **0주** | Leviathan (port 2223) | 무프리퀴짓 모멘텀 · asm 읽기 근육 착수 |
| **0~2달** | **pwn.college** (`Computing 101` 핵심) | C/asm 갭 소멸 지점 · 척추 |
| **0~3달 (병렬)** | picoGym *또는* Natas | 무거운 spine 하는 동안 **안 멈추게** |
| **1~3달** | C는 **항상 in-context** (+ OTW `Manpage` C footgun) | C *읽기* 유창(프로그래머 될 필요 X) |
| **2~4달** | 첫 진짜 익스플로잇 (Program Security / Narnia→Behemoth) → ROP Emporium | 메모리 커럽션 실전 |
| **3~6달** | microcorruption/crackmes(rev) + CryptoHack(crypto) | rev·crypto 다리 |
| **6달+** | pwn.college green/blue · OTW Utumno→Maze · pwnable.tw · Flare-On | 지평선 — 조준하되 콜드로 시작 금지 |

## Honorable Mentions

- **OTW Krypton** — Bandit식 SSH 클래식-crypto 워밍업(~7레벨, 무코딩). CryptoHack 전 애피타이저.
- **OTW Manpage** — 저평가된 C-footgun 트레이너(manpage 감사). C-읽기 갭을 보안 렌즈로 메움.
- **picoGym (picoCTF)** — CMU 연중 무료 아카이브, 6카테고리, 방대한 writeup. General Skills=Bandit 근육 재사용, RE/Binexp=가장 부드러운 pwn 맛.
- **ROP Emporium** — 집중 ROP-체인 트레이너(ret2win→pivot→ret2csu). *overflow+asm 이미 알아야* → 몇 주 뒤 마일스톤.
- **exploit.education Nebula→Phoenix** — 로컬 랩. ⚠️ 2019 이후 코드 동결(안정 but 미유지), 여전히 C+asm+gdb 필요.
- **crackmes.one** — 오픈엔드 rev 반복(x86/x64). **difficulty-1만** 필터, **VM에서 실행**. 커리큘럼 아닌 연습장.
- **Nightmare (guyinatuxedo)** — 최고 **무료** heap 익스플로잇 문서 레퍼런스(~90). ⚠️ python2-era, *읽기 companion*이지 라이브 플랫폼 아님.
- **OWASP Juice Shop / PortSwigger** — 웹 레그가 끌리면 모던 웹 깊이 경로(PortSwigger가 best-in-class 무료).
- **pwnable.kr** — 측면사고 시스템 퍼즐(fd/collision/bof toddler = Bandit fd/setuid 연결). 노후·불안정 인프라 → 여가 companion.
- **pwnable.tw / Flare-On** — 지평선 보스전(pwnable.tw=고급 pwn·강 C/heap, Flare-On=연례 RE 벤치, Win/malware, 매 가을 ~4주 + 아카이브). *조준용, 콜드 시작 금지.*
- **TryHackMe / HTB Academy** — 강하지만 가이드형 pentest/AD breadth 편향(freemium/유료). 자력·시스템 성향엔 부적합(pentest 피벗 생기면 재고).

## 핵심 한 줄

**관심**(→ pwn/rev 척추: pwn.college + Leviathan + microcorruption) · **갭**(→ in-context C 램프) · **스타일**(→ 전부 자력풀이) · **모멘텀**(→ 무-C 병렬 Natas/picoGym) — 네 개가 다 맞물리는 유일 조합.

## Links

- **완료**: [[_MOC/MOC_Bandit]] (Bandit 0→34, 졸업)
- **다음 vault 준비**: `<<Natas N>>` 라우팅 이미 존재(`/bandit` 스킬) → Natas 시작 시 Level_NN 파이프라인 그대로.
- **참고 메모리**: post-bandit-direction(내부 memory).

---

*Research provenance: overnight workflow `wf_7d05cb9a` — 5 tracks (OTW-native / pwn / web / crypto-rev / guided-platforms) fan-out → 9 decision-critical claims adversarially verified (ALL CONFIRMED: free / online / maintained / difficulty / prereqs) → personalized synthesis. Facts as of 2026-07-23; verify uptime/pricing before relying.*
