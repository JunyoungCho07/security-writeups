---
date: 2026-07-15
wargame: Bandit
level: 21
title: "Bandit Level 21 → 22"
difficulty: ★★☆
time_spent: 10min
tags: [bandit, linux, cron, scheduled-task, file-permissions, privilege-context]
status: 🟡 developing
tools_used: [cat, cron, chmod]
new_concepts: [Cron, Scheduled_Task_Privilege]
prerequisites: [Level_20]
---

# Bandit Level 21 → 22

## [Phase 1] Executive Summary

- **Goal**: `cron`이 **bandit22 권한**으로 `/usr/bin/cronjob_bandit22.sh`를 매분 실행 → 스크립트가 bandit22 password를 **world-readable(644) `/tmp` 파일**에 덤프. 나는 그 파일을 그냥 `cat`으로 읽는다.
- **Key Skill**: `/etc/cron.d/`의 스케줄 설정 → 실행되는 스크립트 → 스크립트가 **어디에 무엇을 쓰는지** 역추적. cron의 **USER 필드**가 권한 컨텍스트를 결정한다는 통찰.
- **Tags**: `[Cron]`, `[Scheduled_Task_Privilege]`, `[File_Permissions]`, `[Setuid]`(평행 개념)

[Cognitive Validation]
- **Limit Test**: 스케줄이 `* * * * *`(매분)라 파일은 사실상 항상 존재. 만약 `@reboot`만 있었다면 재부팅 전까지 파일 미생성 → 무한 대기. cron 최소 해상도는 **1분**(초 단위 트리거 불가).
- **Control Knob**: 지배 변수 ① 스크립트가 **누구 권한(bandit22)**으로 도나 ② 산출 파일 permission이 **644(others read 허용)**인가. 둘 다 참이어야 bandit21이 읽는다.
- **Nullity**: 스크립트를 내가(bandit21) **직접 실행**하면 → `/tmp` 파일이 bandit22 소유라 `chmod`에서 `Permission denied`, 새 password 안 나옴. **cron이 대신 돌려야만** 의미 있음(paste에서 실측).

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**Scheduled-task privilege leak**. 시간 기반 스케줄러(cron)가 **특권 계정(bandit22)**으로 스크립트를 돌리고, 그 산출물을 world-readable 위치에 남긴다. Level 19의 setuid와 평행하다 — "누가 프로세스를 소유하나"가 secret 접근권을 정하는데, 여기선 setuid 비트가 아니라 **cron 설정의 USER 필드**가 그 권한 컨텍스트를 부여한다.

### 2. Definition (Formal, EN)

**cron** is a time-based job scheduler daemon. System-wide crontab files under `/etc/cron.d/` use a **6-field** format:

```
minute  hour  day-of-month  month  day-of-week  USER  command
```

The extra **USER** field (absent in per-user `crontab -e` files, which are 5-field) makes the daemon `setuid()` to that account before running `command`. Here:

```
* * * * * bandit22 /usr/bin/cronjob_bandit22.sh &> /dev/null
```

runs the script **every minute as bandit22**. The script `chmod 644`s a fixed `/tmp` path, then redirects `/etc/bandit_pass/bandit22` (readable only by bandit22) into it — leaving bandit22's password in a world-readable file that any user, including bandit21, can `cat`.

### 3. Intuition (KR)

**자동 배달 사물함**이다. bandit22의 비서(cron)가 매분 bandit22의 금고(`/etc/bandit_pass/bandit22`)를 열어 password를 복사한 뒤 **공용 사물함(`/tmp`, 644)**에 넣어둔다. 나는 금고 자체는 못 열지만, 공용 사물함은 누구나 열 수 있다 → 그냥 꺼내 읽으면 끝. 내가 스크립트를 직접 돌려봐야 금고 열쇠(bandit22 권한)가 없어 소용없고, **cron이 대신 열어주는 것**이 핵심.

### 4. Theory (Mechanism)

1. cron 데몬이 `/etc/cron.d/*`를 읽어 스케줄을 등록. `* * * * *` = 분·시·일·월·요일 모두 와일드카드 → **매분** 실행.
2. 매분 cron이 USER 필드(**bandit22**)로 권한을 바꿔(`setuid`) `cronjob_bandit22.sh`를 실행 → 이 순간 프로세스 EUID = bandit22.
3. 스크립트 3줄:
   - `chmod 644 /tmp/<file>` → 산출 파일을 **rw-r--r--**(others read 허용)로.
   - `cat /etc/bandit_pass/bandit22 > /tmp/<file>` → bandit22만 읽을 수 있는 password를 **bandit22 권한으로 읽어** 그 파일에 덮어씀.
4. 결과 파일은 644 + bandit22 소유 → **others(=bandit21)도 read 가능** → `cat /tmp/<file>`로 password 획득.

인과: cron이 bandit22로 실행(조건) → 스크립트가 bandit22 secret을 읽어(B) 644 파일로 기록(C) → others가 그 파일을 read(D).

### 5. Solution

```bash
# SSH connection
$ ssh -p 2220 bandit21@bandit.labs.overthewire.org
# Password: <password masked>

# 1) 스케줄러 설정 디렉터리 확인
bandit21@bandit:~$ ls /etc/cron.d/
behemoth4_cleanup  cronjob_bandit23  leviathan5_cleanup
clean_tmp          cronjob_bandit24  manpage3_resetpw_job
cronjob_bandit22   e2scrub_all       otw-tmp-dir

# 2) bandit22 관련 cron 항목 → 실행 스크립트 경로 확보
bandit21@bandit:~$ cat /etc/cron.d/cronjob_bandit22
@reboot bandit22 /usr/bin/cronjob_bandit22.sh &> /dev/null
* * * * * bandit22 /usr/bin/cronjob_bandit22.sh &> /dev/null
#   필드: 분 시 일 월 요일  USER(bandit22)  command   → '매분' + '재부팅 시' bandit22 권한으로 실행

# 3) 스크립트가 '무엇을 어디에' 쓰는지 역추적
bandit21@bandit:~$ cat /usr/bin/cronjob_bandit22.sh
#!/bin/bash
chmod 644 /tmp/<tmp_target>        # 산출 파일을 world-readable(644)로  (실제론 32자 랜덤 파일명)
cat /etc/bandit_pass/bandit22 > /tmp/<tmp_target>   # bandit22 pw를 그 파일로 덤프

# 4) cron이 매분 갱신해 둔 world-readable 파일을 그냥 read
bandit21@bandit:~$ cat /tmp/<tmp_target>
<password masked>          # ← bandit22 (Level 22) password

# ────────────────────────────────────────────────────────────
# 삽질 로그 (이해를 돕는 dead-end)
# ────────────────────────────────────────────────────────────
# ✗ 데몬을 직접 띄우려 함 → 유저는 crond 못 올림
bandit21@bandit:~$ cron
cron: can't open or create /var/run/crond.pid: Permission denied

# ✗ 파일명을 디렉터리로 착각
bandit21@bandit:~$ cd /etc/cron.d/otw-tmp-dir
-bash: cd: /etc/cron.d/otw-tmp-dir: Not a directory   # 이건 파일(설정), 디렉터리 아님

# ✗ 스크립트를 '내가' 실행 → chmod가 bandit22 소유 파일에서 막힘
bandit21@bandit:~$ /usr/bin/cronjob_bandit22.sh
/usr/bin/cronjob_bandit22.sh: line 3: /tmp/t7O6...: Permission denied
#   파일이 이미 bandit22 소유 → bandit21의 chmod/write 불가. 'cron이 돌려야만' 갱신됨.
```

> [!warning] Password Masking & 권한 컨텍스트
> bandit22 password는 절대 commit 금지 — `<password masked>`. 그리고 **스크립트를 직접 실행하는 것은 답이 아니다**: `/tmp` 파일이 bandit22 소유라 내 실행은 `Permission denied`로 죽는다. 오직 **cron이 bandit22 권한으로 돌린 결과물**을 읽는 것이 정답. `/tmp` 경로 자체는 secret이 아니지만(설정에서 노출), **그 안의 값(password)**만이 답이므로 값만 마스킹한다.

### 6. Why It Works

Level 19에서 **setuid 비트**가 프로세스에 파일 소유자 권한을 줬다면, 여기선 **cron의 USER 필드**가 같은 역할을 한다 — bandit22로 실행되는 스크립트가 bandit22만 읽을 수 있는 password를 대신 읽어 world-readable 파일로 흘려준다. 내가 스크립트를 직접 실행하면 `/tmp` 파일이 **bandit22 소유**라 `chmod`/write가 거부된다(오직 소유자 bandit22 = cron만 갱신 가능). 따라서 "실행"이 아니라 "cron이 매분 남겨두는 **산출물을 read**"하는 것이 핵심. 644 permission(others read)이 others인 bandit21에게 열쇠를 준다.

### 7. Edge Cases / Limitation

- **Permission 의존**: 스크립트가 644가 아니라 600(owner-only)으로 만들었다면 bandit21은 읽을 수 없다. world-readable이 이 취약점의 전부.
- **타이밍**: 파일은 첫 cron tick(≤1분) 후 존재. `clean_tmp` cron(`find /tmp -amin +60 -type f,l -delete`)이 오래된 tmp를 지우지만, `cronjob_bandit22`가 매분 재생성 → 사실상 항상 존재.
- **직접 실행 함정**: `/usr/bin/cronjob_bandit22.sh`를 내가 돌려도 `Permission denied`(파일 owner=bandit22). "실행 권한 있음 ≠ 도움 됨".
- **`@reboot` 전용이었다면**: 재부팅이 없으면 파일 미생성 → 이 레벨은 `* * * * *`(매분)이 있어 성립.
- **cron 해상도**: 최소 1분. 초 단위 트리거 필요하면 cron으로는 불가(systemd timer/`sleep` 루프 필요).

---

## [Phase 3] Formal Summary (EN)

> [!definition] cron / system crontab
> `cron` is a time-based job scheduler. A **system crontab** (`/etc/crontab`, `/etc/cron.d/*`) has 6 fields: `min hour dom month dow USER command`. The daemon runs `command` with the UID/GID of `USER`. A **user crontab** (`crontab -e`) omits `USER` (5 fields) and always runs as its owner. `@reboot` is a special schedule string firing once at daemon startup.

> [!theorem] Privilege context of a cron job = its USER field
> Let job J = `⟨schedule, U, cmd⟩` in `/etc/cron.d/`. cron executes `cmd` with EUID = uid(U). ∴ any secret readable by U becomes accessible to `cmd`; if `cmd` writes that secret to a path with mode `o+r`, it is readable by **every** user — independent of who scheduled or who reads it. Here U = bandit22, cmd deposits `bandit_pass/bandit22` at mode 644 ⇒ bandit21 ∈ *others* reads it. □

---

## [Phase 4] Better Methods

**Current approach** (used above): `ls /etc/cron.d/` → `cat` 설정 → `cat` 스크립트 → `cat` 산출 파일. 4단계 수동 역추적. 명확하지만 손이 많이 감.

**Alternative 1**: 스크립트에서 대상 경로를 자동 추출해 바로 read
```bash
cat "$(grep -oE '/tmp/\S+' /usr/bin/cronjob_bandit22.sh | head -1)"
#   grep -oE '/tmp/\S+' : -o=매치 부분만, -E=확장정규식, '/tmp/뒤 공백아닌문자들' → tmp 경로만 뽑음
#   head -1             : 두 줄(chmod/cat) 중 첫 경로 하나만 (둘은 동일 경로)
#   $(...)              : 명령 치환 → 뽑은 경로를 cat의 인자로
```
Trade-off: 경로를 눈으로 안 옮겨도 됨(오타 방지). grep 패턴 이해 필요.

**Alternative 2**: 읽기 전에 권한/신선도 검증
```bash
ls -l /tmp/<tmp_target>    # -rw-r--r-- + owner=bandit22 확인 (왜 읽히는지 근거)
# 파일이 아직 없다면 한 tick 대기:
while [ ! -s /tmp/<tmp_target> ]; do sleep 5; done; cat /tmp/<tmp_target>
#   -s : 파일이 존재 && 크기>0 일 때 참 → 아직 안 만들어졌으면 5초씩 대기
```
Trade-off: 왜 접근 가능한지(644, others=r) 근거를 눈으로 확인 + `@reboot` 직후 등 파일 부재 상황에 견고. 장황함.

**Most elegant**:
```bash
cat "$(awk 'END{print $NF}' /usr/bin/cronjob_bandit22.sh)"
#   awk 'END{print $NF}' : 마지막 줄(cat ... > /tmp/xxx)의 마지막 필드($NF)=리다이렉트 대상 경로
#   → 스크립트가 '무엇에 쓰는지'를 스크립트 스스로에게 물어 그대로 read
```
Why elegant: 스크립트가 곧 "레시피"이므로 하드코딩 경로 없이 **산출 대상**을 자동 도출해 한 줄로 read. 경로가 바뀌어도(cron rotate) 그대로 동작.

---

## [Phase 5] Lessons Learned

1. **cron USER 필드 = 권한 컨텍스트**: `/etc/cron.d/`의 6번째 필드가 실행 계정을 정한다(5-field user crontab엔 없음). 그 계정의 secret이 스크립트로 새어나올 수 있다.
2. **취약점의 본질은 permission**: 특권 스크립트가 결과를 **644(world-readable)**로 남기면 setuid 없이도 secret 유출. 600이었다면 못 읽는다.
3. **"실행 가능 ≠ 도움 됨"**: 스크립트를 직접 돌려도 `/tmp` 파일 owner가 bandit22라 막힘. cron이 **대신** 돌린 산출물을 read해야 한다.
4. **역추적 순서**: 설정(`/etc/cron.d/`) → 실행 대상(스크립트) → 스크립트가 쓰는 경로 → 그 파일. 각 단계가 다음 단계의 위치를 알려준다.
5. **스케줄 해상도**: `* * * * *`=매분, `@reboot`=부팅 시 1회. cron 최소 단위는 1분.

### Quiz

**Q**: (a) `/etc/cron.d/cronjob_bandit22`의 `* * * * * bandit22 ...`에서 스크립트는 **어느 권한**으로 실행되며 그 근거 필드는? (b) 그 스크립트를 bandit21이 **직접** 실행하면 왜 실패하나? (c) 이 취약점을 **막으려면** 스크립트에서 무엇을 바꿔야 하나?

> [!tip]- 풀이
> **(a)** **bandit22** 권한. system crontab(`/etc/cron.d/*`)은 6-field이고 5번째 시간필드 뒤의 **USER 필드**(=`bandit22`)가 실행 계정을 지정, cron이 그 UID로 `setuid` 후 실행.
>
> **(b)** 산출 파일 `/tmp/…`이 (직전 cron 실행으로) **bandit22 소유**라, bandit21의 `chmod 644`(스크립트 2번째 줄)가 `Permission denied`로 죽는다. 소유자(bandit22=cron)만 chmod/overwrite 가능.
>
> **(c)** password를 world-readable로 남기지 말 것: `chmod 644`를 **`chmod 600`**으로(others read 제거) 바꾸거나, 애초에 `/tmp` 같은 공용 위치에 secret을 덤프하지 않기. 644가 유출의 근본 원인.
>
> 핵심: **"누가 실행하나(USER 필드) × 결과 파일 permission"** 두 축이 secret 접근권을 결정한다.

> [!flashcard]
> **Q**: `/etc/cron.d/` 파일이 per-user `crontab -e`와 다른 **필드**는?
> **A**: 시간 5필드 뒤에 **USER 필드**가 추가된 6-field. 그 계정 권한으로 command가 실행된다(user crontab은 5-field, 항상 소유자 권한).

> [!flashcard]
> **Q**: Level 21에서 secret이 유출되는 근본 원인은?
> **A**: 특권(bandit22) cron 스크립트가 password를 **644(world-readable) `/tmp` 파일**로 덤프 → others인 bandit21이 read. `chmod 600`이면 막힌다.

---

## Links

### Tools Used
- [[Tools/cat]]
- [[Tools/crontab]]

### Concepts Introduced (first encountered here)
- [[Concepts/Linux/Cron]]
- [[Concepts/Linux/Scheduled_Task_Privilege]]

### Concepts Applied (reused from earlier)
- [[Concepts/Linux/Setuid]] (Level 19 — setuid 비트 대신 여기선 cron USER 필드가 권한 컨텍스트 부여)
- [[Concepts/Linux/File_Permissions]] (644 world-readable = 유출의 근본)

### Navigation
- **Prerequisite**: [[Level_20]]
- **Next**: [[Level_22]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit22.html
- `crontab(5)` — system crontab 6-field 포맷 + `USER` 필드; `@reboot` 등 nickname
- `cron(8)` — 데몬 동작, `/etc/cron.d/` 스캔
