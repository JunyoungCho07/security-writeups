---
date: 2026-07-23
domain: Linux
topic: Setuid
tags: [linux, setuid, privilege, ruid, euid, setreuid, permissions]
status: 🟡 developing
note_tier: lite
mastery: 48
first_encountered: [[Wargames/Bandit/Level_19]]
reapplied_in: [[[Wargames/Bandit/Level_20]], [[Wargames/Bandit/Level_21]], [[Wargames/Bandit/Level_23]], [[Wargames/Bandit/Level_26]], [[Wargames/Bandit/Level_32]]]
---

# Setuid (RUID / EUID)

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> L19에서 처음, L26(env-wrapper)·L32(uppershell)에서 재적용하며 **RUID/EUID/`setreuid`/`bash -p`**까지 깊게 판 개념. `/deep` 시 saved-uid 토글, capabilities, no_new_privs, TOCTOU까지.

## Definition (Formal, EN)

A process carries **RUID** (real UID — *who launched it*, used for signals/accounting) and **EUID** (effective UID — *whose permissions the kernel checks*). Normally RUID==EUID. The **setuid bit** (mode `04000`, `s` in owner-exec) makes `execve` set **EUID = the file's owner UID** (RUID unchanged), per the kernel rule (`execve(2)`: "effective user ID … set to the owner ID of the … file").

## Intuition (KR)

setuid = "이 프로그램은 **주인 권한**으로 돈다"는 표식. 주인이 root면 EUID=root, bandit33이면 EUID=bandit33. **접근 판정은 EUID**로 하니, 실행자는 잠깐 주인의 열쇠를 빌린다.

## Key Points (무엇을 팠나)

### A. RUID vs EUID vs saved-UID
- **RUID**=호출자(불변), **EUID**=권한검사 기준(setuid가 올림), **saved-UID**=특권을 내렸다 되찾는 보관값.
- `id` 출력: 평소 uid만; 다르면 `euid=` 별도 표시(L26 `./bandit27-do id` → `uid=bandit26 euid=bandit27`).
- **소유자가 핵심**: EUID ← **파일 소유자**(root라서가 아니라 소유자가 root라서). setgid=02000(EGID), sticky=01000(디렉터리 삭제 제한)는 **다른** 특수비트.

### B. do-wrapper 패턴 (L19/L26)
- setuid + 소유자 = 미니-`sudo`: `./wrapper cat <secret>` → EUID=소유자로 파일 read. L26은 `execv("/usr/bin/env", …)` 경유(셸 없음 → 글롭/파이프 안 먹음).
- 정찰: `find / -perm -4000 -type f 2>/dev/null` → GTFOBins.

### C. sticky 상승 & `bash -p` (L32의 핵심)
- 보통 setuid는 **EUID만** 올림. 그런데 `bash`는 시작 시 **`euid≠ruid`면 euid를 ruid로 떨어뜨린다**(privileged 방어; `-p` 없으면). → plain bash에서 권한 소실.
- L32 `uppershell`은 **`setreuid`/`setresuid`로 real uid까지** bandit33 고정 → `euid==ruid`라 bash가 안 떨굼 → plain bash도 bandit33 유지. `bash -p`는 그 방어를 끄는 명시적 opt-out.

### D. 한계
- **setuid 스크립트는 커널이 무시**(TOCTOU) → 컴파일 바이너리에만 유효. 상승은 **소유자까지만**(root 파일이라야 root).

## Encountered / Applied In
- [[Wargames/Bandit/Level_19]] — `bandit20-do` do-wrapper(첫 등장).
- [[Wargames/Bandit/Level_26]] — `bandit27-do` env-wrapper; [[Static_Binary_Triage]]로 구현 추론.
- [[Wargames/Bandit/Level_32]] — `uppershell` setuid + real-uid 고정 → bash까지 권한 전파. [[Restricted_Shell_Escape]] · [[Process_Creation]].

## Expand Later (`/deep` candidates)
- **`/deep Process_Credentials`** — ruid/euid/suid/fsuid, `setuid`/`setreuid`/`setresuid` 규칙, `credentials(7)`, capabilities, `no_new_privs`.
- **`/deep Privilege_Escalation`** — SUID 사냥, GTFOBins, PATH/LD_PRELOAD 하이재킹, sudo 오설정.
