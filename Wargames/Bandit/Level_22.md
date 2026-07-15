---
date: 2026-07-15
wargame: Bandit
level: 22
title: "Bandit Level 22 → 23"
difficulty: ★★☆
time_spent: 12min
tags: [bandit, linux, cron, scheduled-task, md5, hashing, whoami, privilege-context]
status: 🟡 developing
tools_used: [cat, cron, md5sum, cut, whoami, echo]
new_concepts: [Md5_Hashing, Deterministic_Filename]
prerequisites: [Level_21]
---

# Bandit Level 22 → 23

## [Phase 1] Executive Summary

- **Goal**: cron이 `cronjob_bandit23.sh`를 **bandit23 권한**으로 매분 실행 → 대상 파일명을 `md5("I am user $(whoami)")`로 **결정론적 계산**해 `/tmp/<md5 hash>`에 bandit23 password를 덤프. 나(bandit22)는 스크립트를 *실행*하지 않고 그 **파일명을 재현**해 read한다.
- **Key Skill**: 스크립트를 직접 돌리면 `whoami`가 bandit22가 되어 **자기 password** 위치만 나온다(함정). 대신 입력을 `I am user bandit23`으로 고정해 md5 파일명을 재현하고, cron이 이미 채워둔 파일을 `cat`.
- **Tags**: `[Cron]`, `[Md5_Hashing]`, `[Deterministic_Filename]`, `[whoami]`

[Cognitive Validation]
- **Limit Test**: `whoami`를 bandit22로 두면(=스크립트 직접 실행) 파일명이 `md5("I am user bandit22")` → 거기엔 **내 password**만. 정답은 whoami=bandit23일 때의 해시. 지배 입력은 "I am user X"의 **X**.
- **Control Knob**: 해시 입력 문자열의 username 한 조각. X=`bandit23`이라야 정답 파일. 한 글자만 달라도 md5는 완전히 다른 경로(avalanche) → 엉뚱한 곳.
- **Nullity**: cron이 아직 안 돌았다면 계산한 경로가 비어있음. 하지만 `* * * * *`(매분)라 사실상 상존.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**Deterministic filename prediction + identity-scoped secret**. Level 21의 "**고정** world-readable 경로 dump"에서 한 단계 진화 — 경로가 이제 **`whoami`로부터 md5로 파생**된다. cron이 bandit23으로 실행되므로 파일명·내용 둘 다 bandit23에 귀속. 공격자는 그 파생 규칙을 **재현**만 하면 위치를 안다. Level 21이 "읽을 곳을 안다"였다면, 여기는 "**읽을 곳을 계산한다**".

### 2. Definition (Formal, EN)

The cron entry `* * * * * bandit23 /usr/bin/cronjob_bandit23.sh` runs as **bandit23**. Inside:

```
myname=$(whoami)                                          # → bandit23 (executing identity)
mytarget=$(echo I am user $myname | md5sum | cut -d ' ' -f 1)   # MD5 hex of "I am user bandit23\n"
cat /etc/bandit_pass/$myname > /tmp/$mytarget            # deposit bandit23's password
```

Because **MD5 is deterministic** — same input bytes ⇒ same digest — any user who knows the input string `I am user bandit23` can recompute `mytarget` and read the file that cron (running as bandit23) refreshes every minute. The script has **no explicit `chmod`**, so the deposited file's mode is bandit23's umask default (022 ⇒ 644 ⇒ world-readable).

### 3. Intuition (KR)

**사물함 번호가 이름을 해시해서 정해진다.** bandit23의 비서(cron)가 "I am user bandit23"을 md5 돌려 나온 번호의 공용 사물함에 password를 넣는다. 나는 그 계산식을 알기에 **같은 번호를 직접 계산**해 사물함을 연다. 반대로 내가 스크립트를 그냥 실행하면 `whoami`가 "bandit22"라 **내 이름 사물함**(내 password)만 나온다 — 소용없다.

### 4. Theory (Mechanism)

1. cron이 매분 **bandit23** 권한으로 스크립트 실행.
2. `whoami` → `bandit23` (실행 계정 = EUID 소유자).
3. `echo I am user bandit23 | md5sum` → `<md5 hash>  -` (해시 + 두 칸 + `-`(stdin 표시)). `cut -d ' ' -f 1`이 **첫 공백 앞** = 해시만 추출.
4. `cat /etc/bandit_pass/bandit23 > /tmp/<md5 hash>` → bandit23 password를 그 파일로. chmod 없음 → umask 022 → **644**(others read).
5. bandit22는 **같은 입력**으로 md5를 재현해 파일명을 얻고 `cat`.

인과: cron이 bandit23으로 실행(조건) → `whoami=bandit23` → md5로 파일명 결정(B) → bandit23 pw 기록(C) → 입력 재현으로 위치 파악(D) → read.

> **echo의 trailing newline이 결정적.** `echo I am user bandit23`은 끝에 `\n`을 붙여, md5 입력이 정확히 `I am user bandit23\n`이다. `echo -n`이나 `printf "I am user bandit23"`(no `\n`)은 **다른 바이트열 → 다른 해시 → 존재하지 않는 파일**. 그래서 스크립트의 파이프라인을 **그대로** 재현하는 것이 안전하다.

### 5. Solution

```bash
# SSH connection
$ ssh -p 2220 bandit22@bandit.labs.overthewire.org
# Password: <password masked>

# 1) cron 설정 → 실행 스크립트 + 실행 계정 확인
bandit22@bandit:~$ cd /etc/cron.d/
bandit22@bandit:/etc/cron.d$ cat cronjob_bandit23
@reboot bandit23 /usr/bin/cronjob_bandit23.sh  &> /dev/null
* * * * * bandit23 /usr/bin/cronjob_bandit23.sh  &> /dev/null   # USER=bandit23, 매분

# 2) 스크립트: 파일명이 md5(whoami)로 파생됨
bandit22@bandit:/etc/cron.d$ cat /usr/bin/cronjob_bandit23.sh
#!/bin/bash
myname=$(whoami)
mytarget=$(echo I am user $myname | md5sum | cut -d ' ' -f 1)
echo "Copying passwordfile /etc/bandit_pass/$myname to /tmp/$mytarget"
cat /etc/bandit_pass/$myname > /tmp/$mytarget

# 스크립트 권한: group=bandit22 가 r-x → 나는 읽기/실행 가능 (단, 실행은 함정)
bandit22@bandit:/etc/cron.d$ ls -al /usr/bin/cronjob_bandit23.sh
-rwxr-x--- 1 bandit23 bandit22 211 Jun 24 14:58 /usr/bin/cronjob_bandit23.sh

# ── 삽질: 스크립트를 '내가' 실행 → whoami=bandit22 → 자기 password 위치만 ──
bandit22@bandit:/etc/cron.d$ /usr/bin/cronjob_bandit23.sh
Copying passwordfile /etc/bandit_pass/bandit22 to /tmp/8169b67bd894ddbb4412f91573b38db3   # md5 hash of "I am user bandit22"
bandit22@bandit:/etc/cron.d$ cat /tmp/8169b67bd894ddbb4412f91573b38db3   # md5 hash path
<password masked>   # ← 이건 bandit22(나) 자신의 password. 정답 아님!

# ── 정답: whoami를 bandit23으로 고정해 파일명 재현 → cron이 채워둔 파일 read ──
bandit22@bandit:/etc/cron.d$ myname=bandit23
bandit22@bandit:/etc/cron.d$ mytarget=$(echo I am user $myname | md5sum | cut -d ' ' -f 1)
bandit22@bandit:/etc/cron.d$ echo "$mytarget"
8ca319486bfbbc3663ea0fbe81326349   # md5 hash of "I am user bandit23"
bandit22@bandit:/etc/cron.d$ cat /tmp/$mytarget          # = /tmp/<md5 hash>
<password masked>   # ← bandit23 (Level 23) password
```

> [!warning] Password Masking & 실행 vs 예측
> bandit22/bandit23 password 모두 마스킹. 핵심 함정: **스크립트를 실행하지 마라.** 실행하면 `whoami=bandit22` → md5가 자기 이름으로 계산돼 **자기 password 파일**(`8169…`)만 나온다. 특권 쓰기는 **cron이 bandit23으로** 하게 두고, 나는 파일명만 재현해 read. (md5 해시 값 자체는 공개 입력의 함수라 secret이 아니지만, `/tmp` 안의 **password 값**만이 답 → 값만 마스킹.)

### 6. Why It Works

권한 원천은 Level 21과 동일 — cron이 **bandit23 권한**으로 스크립트를 돌려 bandit23만 읽을 수 있는 password를 대신 읽어준다. 새로운 wrinkle은 **덤프 위치가 `whoami`에서 md5로 파생**된다는 점. 스크립트를 내가 실행하면 `whoami`가 bandit22가 되어 파일명·내용 둘 다 **내 정체성**에 묶인다(내 password → 무의미). 따라서 exploit은 "실행"이 아니라 ① cron이 bandit23으로 privileged write를 하도록 두고 ② 알려진 입력 `I am user bandit23`으로 **결정론적 파일명을 독립 재계산**하는 것. **MD5의 결정성**이 bandit23 권한 없이도 경로를 예측하게 해준다.

### 7. Edge Cases / Limitation

- **echo newline**: 입력이 `I am user bandit23\n`. `echo -n`/`printf`(no `\n`)면 다른 해시 → 틀린 파일. 스크립트 파이프라인 그대로 재현.
- **umask 의존**: Level 21과 달리 `chmod 644`가 **없다** → 생성 파일 권한은 bandit23의 umask(022→644)에 의존. umask 077이었다면 600 → 못 읽음.
- **직접 실행 함정**: `whoami=bandit22`라 자기 password 파일만. 실행이 아니라 **위치 예측**이 답.
- **clean_tmp**: `find /tmp -amin +60 … -delete`가 오래된 tmp를 지우지만 매분 재생성 → 상존.
- **다음 레벨 예고**: `/usr/bin/cronjob_bandit24.sh`는 bandit22가 **read/exec 불가**(`Permission denied`) → Level 23→24는 스크립트를 **못 읽는** 상태에서 풀어야 함(난이도 상승).

---

## [Phase 3] Formal Summary (EN)

> [!definition] Deterministic filename via hash
> A path derived as `p = /tmp/ ‖ MD5(s)` for a known string `s` is **predictable**: MD5 is a pure function, so identical input bytes yield an identical digest. Knowledge of `s` (here `"I am user bandit23\n"`) suffices to recompute `p` — the filename carries no secrecy, only the file's *contents* do.

> [!theorem] Identity-scoped deposit
> The job computes `mytarget = MD5("I am user " ‖ whoami)` and writes `content = pass(whoami)`. Thus the pair `(path, secret)` is bound to the **executing** identity U: running as U yields `pass(U)`. ∴ to obtain `pass(bandit23)` one must let the job run **as bandit23** (cron does) and merely recompute the path for U = bandit23 — never execute it oneself as bandit22. □

---

## [Phase 4] Better Methods

**Current approach** (used above): `myname=bandit23` 변수 세팅 → `mytarget=$(… md5sum …)` → `cat /tmp/$mytarget`. 3단계, 스크립트의 파생을 손으로 재현.

**Alternative 1**: 한 줄 명령 치환
```bash
cat /tmp/$(echo I am user bandit23 | md5sum | cut -d ' ' -f 1)
#   echo I am user bandit23 : 스크립트와 동일(끝 \n 포함)  → 같은 해시 보장
#   md5sum                  : 표준입력을 MD5 → '<hash>  -' 출력
#   cut -d ' ' -f 1         : 첫 공백 앞(=해시)만; '  -' 꼬리 제거
#   $(...)                  : 명령 치환 → 파일명을 cat 인자로 인라인
```
Trade-off: 변수 없이 한 줄. 스크립트 파이프라인을 그대로 옮겨 오타 위험 최소.

**Alternative 2**: `awk`로 필드 추출 (이중 공백에 견고)
```bash
cat "/tmp/$(echo 'I am user bandit23' | md5sum | awk '{print $1}')"
#   awk '{print $1}' : 공백(연속 포함)으로 나눈 첫 필드 = 해시. md5sum의 '  '(2칸)에 자연 대응
#   "…" 인용        : 경로에 공백이 생겨도 안전(여기선 불필요하나 습관)
```
Trade-off: `cut -d ' '`은 구분자 1칸 기준이라 필드 계산이 포맷 민감. `awk`는 연속 공백을 하나로 취급해 더 견고.

**Most elegant**:
```bash
cat /tmp/$(echo I am user bandit23 | md5sum | cut -d ' ' -f 1)
```
Why elegant: 스크립트의 파생을 **정확히 그대로** 재현(같은 `echo`·같은 파이프)해 한 번의 read로 끝. privileged 실행 0회, 변수 0개 — "cron이 만든 것을 예측해 읽는다"는 본질만 남김.

---

## [Phase 5] Lessons Learned

1. **cron USER 필드 = 실행 계정 = `whoami`**: 스크립트를 직접 실행하면 whoami가 바뀌어 결과가 달라진다. 특권 산출물은 cron이 만들게 두고 나는 **읽기만**.
2. **결정론적 파일명은 secret이 아니다**: md5 같은 순수함수로 파생된 경로는 입력만 알면 예측 가능. 비밀은 **내용**뿐.
3. **입력 바이트 정확도**: `echo`의 trailing `\n`까지 포함해야 해시가 일치. 1바이트 차이 → 완전히 다른 경로(avalanche).
4. **실행 vs 예측**: L21은 "고정 경로 read", L22는 "**파생 경로 계산** 후 read". 진화의 축은 '위치를 어떻게 아느냐'.
5. **정찰로 다음 난이도 예측**: `ls -al`/`file`로 `cronjob_bandit24.sh`가 **접근 불가**임을 확인 → 다음 레벨은 스크립트 없이 추론해야 함.

### Quiz

**Q**: (a) `/usr/bin/cronjob_bandit23.sh`를 bandit22가 **직접 실행**하면 어떤 파일에 무엇이 담기나? (b) 정답 파일명을 bandit22가 알아내는 방법과 그것을 가능케 하는 성질은? (c) `echo`를 `printf "I am user bandit23"`로 바꾸면 왜 실패하나?

> [!tip]- 풀이
> **(a)** `whoami=bandit22` → `/tmp/md5("I am user bandit22")`(=`8169…`)에 **bandit22 자기 password**. 정답(bandit23)과 무관.
>
> **(b)** 동일 입력 `I am user bandit23`을 `md5sum | cut`으로 재현해 같은 해시(`8ca3…`)를 얻고 `cat`. 가능 근거: **MD5 결정성**(같은 입력=같은 출력). 파일명은 비밀이 아니라 공개 입력의 함수.
>
> **(c)** `echo`는 끝에 `\n`을 붙여 입력이 `I am user bandit23\n`. `printf "…"`(no `\n`)는 `\n` 없는 다른 바이트열 → 다른 md5 → 존재하지 않는 파일. 해시는 1바이트만 달라도 완전히 바뀐다(avalanche effect).
>
> 핵심: **"누가 실행하나(whoami) × 파일명 파생 규칙(md5 입력)"**을 알면 어느 `/tmp` 파일을 읽어야 하는지 계산된다.

> [!flashcard]
> **Q**: Level 22에서 `cronjob_bandit23.sh`를 직접 실행하면 왜 답이 안 나오나?
> **A**: `whoami`가 bandit22가 되어 파일명·내용이 자기 자신에 귀속 → 자기 password만 나옴. cron이 **bandit23으로** 실행해야 bandit23 password가 놓인다.

> [!flashcard]
> **Q**: cron이 만든 `/tmp/<md5 hash>` 파일을 bandit22가 어떻게 찾나?
> **A**: 스크립트의 `echo I am user bandit23 | md5sum | cut -d ' ' -f 1`을 그대로 재현해 결정론적 파일명을 계산. MD5 결정성 덕분에 bandit23 권한 없이 위치 예측 가능.

---

## Links

### Tools Used
- [[Tools/md5sum]]
- [[Tools/cut]]
- [[Tools/cat]]

### Concepts Introduced (first encountered here)
- [[Concepts/Crypto/Md5_Hashing]]
- [[Concepts/Linux/Deterministic_Filename]]

### Concepts Applied (reused from earlier)
- [[Concepts/Linux/Cron]] (Level 21 — 거기선 고정 경로, 여기선 파일명이 md5로 파생)
- [[Concepts/Linux/Setuid]] (Level 19 — 권한 컨텍스트 계열; 여기선 cron USER 필드)
- [[Concepts/Linux/File_Permissions]] (chmod 없음 → umask 022 → 644 world-readable)

### Navigation
- **Prerequisite**: [[Level_21]]
- **Next**: [[Level_23]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit23.html
- `md5sum(1)` — 출력 포맷 `<digest>␠␠<name>`; stdin은 name이 `-`
- `whoami(1)`, `crontab(5)` — system crontab의 USER 필드
- umask — 신규 파일 기본 permission(022 → 644)
