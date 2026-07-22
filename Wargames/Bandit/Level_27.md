---
date: 2026-07-20
wargame: Bandit
level: 27
title: "Bandit Level 27 → 28"
difficulty: ★★☆
time_spent: 15min
tags: [bandit, linux, git, git-over-ssh, ssh, url-parsing, non-standard-port, version-control, clone]
status: 🟡 developing
tools_used: [git, ssh, cat, tree, ls]
new_concepts: [Git_Over_SSH]
prerequisites: [Level_26, Level_00]
---

# Bandit Level 27 → 28

## [Phase 1] Executive Summary

- **Goal**: bandit28의 password가 **git 저장소** `ssh://bandit27-git@bandit.labs.overthewire.org:2220/home/bandit27-git/repo`에 들어 있다. 이 repo를 clone해 `repo/README`를 읽으면 된다. Bandit **첫 git 레벨**(27–31 git 아크의 입문편). 인증 credential은 `bandit27-git` 계정의 SSH **password = bandit27의 password**(직전 26→27에서 얻은 값), 키가 아님 — 공식 OTW 문구 "The password for the user bandit27-git is the same as for the user bandit27."
- **Key Skill**: **비표준 포트(2220)로 git-over-SSH clone**. 이번 삽질의 전부가 URL 문법이었다. 두 규칙으로 요약: **(1) `git clone`엔 `-p`(포트) 옵션이 없다** — 포트는 git이 아니라 **ssh 계층**의 관심사라 **URL authority** `ssh://host:PORT/path`에 넣거나 `GIT_SSH_COMMAND="ssh -p 2220"`로 준다. **(2) `:PORT`는 host 뒤·첫 `/` 앞**에 와야 한다 — path 끝에 붙이면 포트가 아니라 리터럴 경로 문자가 된다.
- **Tags**: `[Git_Over_SSH]`, `[SSH_Fundamentals]`(non-default port, L00 재적용), `[Previous_Password_As_Credential]`(OTW 관례)

[Cognitive Validation]
- **Limit Test**: `:2220`을 **path 끝**(`.../repo:2220`)에 두면 → git은 **기본 포트 22**로 접속(transport parser에겐 콜론이 리터럴 경로 문자)하고, 동시에 local dir 이름을 **`2220`**으로 짓는다(dir-name parser에겐 콜론이 경로 구분자). `:2220`을 **host 뒤**로 옮기면 그제서야 2220으로 접속. **콜론의 위치**가 지배 변수.
- **Control Knob**: URL에서 **`:PORT`가 놓인 자리**가 접속 포트와 로컬 디렉터리 이름을 **둘 다** 결정한다. 같은 문자 `:`를 **두 파서가 정반대로** 해석 — 이게 이 레벨의 핵심 통찰.
- **Nullity**: `ssh://` URL에 포트를 **아예 안 주면** 기본 22 → OTW의 "you're on port 22, which is not intended" 벽. 포트는 URL authority든 ssh 설정이든 **어딘가엔 반드시** 공급돼야 게임 sshd(2220)에 닿는다.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**git-over-SSH transport + URL grammar + secrets-in-VCS.** git은 원격 전송을 자체 구현하지 않고 **`ssh`에 위임**한다 — clone은 서버에서 `git-upload-pack`을 실행시켜 객체를 받아오는 것. 여기 걸린 함정은 익스플로잇이 아니라 **URL 문법**: `git clone`엔 포트 옵션이 없고, `ssh://` URL의 포트는 RFC-3986 authority 규칙을 따른다. 넓게 보면 이 레벨은 "**비밀을 버전관리에 넣으면 어떻게 새는가**"의 입문 — 여기선 README에 그냥 놓였지만, 다음 레벨들(28 history / 29 branch / 30 tag / 31 push)은 같은 전제를 점점 깊게 판다.

### 2. Definition (Formal, EN)

`git clone` over an `ssh://` URL delegates transport to the `ssh` binary. git first probes `ssh -G <host>` to detect the OpenSSH variant, then execs a **single** remote command:

```
ssh -o SendEnv=GIT_PROTOCOL -p 2220 bandit27-git@host git-upload-pack '/home/bandit27-git/repo'
```

`git clone` itself has **no** `-p`/`--port` option (its short options are `-b -c -j -l -n -o -q -s -u -v`); the port is an **ssh** concern, carried in the URL **authority** per the grammar `ssh://[user@]host[:port]/path`. Download-side of the wire protocol is **`git-upload-pack`**; the server serves objects for the repo path. Authentication for `bandit27-git` is SSH **password** auth using **bandit27's password** (official OTW spec), *not* a key and *not* a git-specific secret.

### 3. Intuition (KR)

git clone over ssh는 **git이 뒤에서 `ssh`를 불러** 서버의 `git-upload-pack`을 돌리는 것. 포트는 git이 아니라 **ssh의 소관**이라, `-p`를 git에 주면 "그런 스위치 없다"고 문전박대한다. 포트를 전하는 정문은 **URL의 host 뒤**(`host:2220`)이고, 뒷문은 **ssh 계층**(`GIT_SSH_COMMAND="ssh -p 2220"` 또는 `~/.ssh/config`). 콜론을 엉뚱한 자리(path 끝)에 놓으면 git의 **두 파서가 서로 다른 결론**을 내려 — 접속은 22번(콜론=경로 문자), 폴더 이름은 `2220`(콜론=구분자) — 동시에 두 가지가 어긋난다.

### 4. Theory (Mechanism) — 삽질 로그를 인과로 재구성

6번의 시도가 그대로 교보재다.

1. **`… /repo -p 2220`** (scheme 없음) → **이중 실패**. (i) `-p`는 git clone 옵션이 아님 → git이 URL 뒤에 와도 **옵션을 재정렬해** 파싱하다 `error: unknown switch 'p'` + usage 덤프. (ii) 설령 `-p`를 빼도, 이 인자는 `ssh://` scheme도 없고 `/` 앞 콜론도 없어 git이 **로컬 경로**로 간주 → `fatal: repository not found` (transcript엔 (i)에서 먼저 죽어 (ii)는 안 보였지만, 형식 자체가 이중으로 틀림).
2. **`ssh://… /repo -p 2220`** → scheme는 고쳤지만 `-p`는 **여전히** 거절. git엔 포트 플래그가 **아예 없다**(URL이 맞든 틀리든 무관).
3. **`ssh://…/repo:2220`** (`:2220`을 **path 끝**에) → **한 콜론, 두 파서**:
   - **transport parser**: 포트는 authority(첫 `/` 이전)에서만 읽는다. path 안의 콜론은 리터럴 → **기본 포트 22**로 접속 → OTW "port 22, not intended" 배너 + `Permission denied (publickey)`. (원격 명령은 `git-upload-pack '/home/bandit27-git/repo:2220'` — 콜론이 경로에 그대로 박힘.)
   - **dir-name parser**(`git_url_basename`, 옛 이름 `guess_dir_name`): 콜론을 **경로 구분자**로 취급(scp식 `foo:bar.git`→`bar` 하위호환) → 마지막 콜론 뒤 `2220`을 폴더명으로 → `Cloning into '2220'`. **버그가 아니라 의도된 하위호환.** (이 "콜론=리터럴" 성질은 ssh:// 전용이 아니라 `git://`·`https://` 등 **모든 scheme:// 전송에 공통**인 RFC-3986 authority/path 파싱이다.)
4. **`ssh://…:2220/…/repo:2220`** (port는 host 뒤로 옮겼으나 path 끝 `:2220` 잔존) → **거의 정답**: 포트가 제대로 파싱돼 **2220 접속 성공**("backend: gibson-1" + 진짜 password 프롬프트) — port **위치**가 맞다는 증거. 다만 잔여 `:2220`이 repo 경로를 오염시키고 폴더명이 또 `2220`.
5. **`ssh://…:2220/…/repo`** (clean) → **문법은 완벽**. 실패 원인은 **password 오타**뿐: `Permission denied, please try again` **3회** 후 `Permission denied (publickey,password)`. 3회는 **클라이언트** 측 `NumberOfPasswordPrompts`(ssh_config 기본 **3**) 한도이고, 마지막 줄은 **ssh 클라이언트 자신의** "모든 방법 소진" 메시지다(서버 `MaxAuthTries`=6가 끊었다면 "Too many authentication failures" 라는 **다른** 메시지가 떴을 것 → lockout·rate-limit·wrong-user·key 문제 **아님**).
6. **동일 명령 재실행 + 올바른 password** → clone 성공: `Enumerating objects: 3 … Total 3 (delta 0), reused 0, pack-reused 0`.
7. **`cat repo/README`** → bandit28 password 획득.

**인증의 정체 — `(publickey)` vs `(publickey,password)`**: OpenSSH의 `Permission denied (methods)` 괄호는 **서버가 광고한 인증 방법 목록**이다. 포트 **22**는 `(publickey)`뿐 — password를 애초에 제시하지 않는 잠긴 정문(그래서 프롬프트조차 없이 즉시 거절). 포트 **2220**은 `(publickey,password)` — password를 제공하므로 프롬프트가 뜬다. 즉 괄호 내용이 **네가 실제로 닿은 포트**를 알려주는 tell. 필요한 credential은 **bandit27의 password**.

**clone 출력 읽기 — 3 objects의 정체**: repo에 파일 하나(README)·커밋 하나면 객체는 정확히 **커밋→트리→블롭 = 3개**(`Enumerating/Counting/Total 3`). `Compressing objects: 100% (2/2)`가 **3이 아니라 2**인 이유: pack-objects의 delta 탐색은 **≥50바이트** 객체만 후보로 삼는데, 단일 파일 트리(~34B)가 문턱 아래라 **제외** → 후보 = 커밋+블롭 = 2(카운터는 "총 객체 수"가 아니라 **delta 후보 수**). `Total 3 (delta 0)` = 3개 모두 delta 없이 통째로 기록(단일 리비전 → 델타 기준이 될 유사 객체 없음). `reused 0 / pack-reused 0` = **서버측** pack 재사용 최적화(기존 pack의 표현 재활용 / bitmap 대량복사)가 신선한 repo라 발동 안 함 — "내 로컬에서 재사용"이 아니라 **서버 pack 생성** 통계.

### 5. Solution

```bash
# bandit26 셸에서(또는 로컬 머신에서) — 쓰기 가능한 곳으로 이동
bandit26@bandit:~$ cd /tmp/$(whoami)_git 2>/dev/null || cd /tmp   # 임의 작업 디렉터리

# ── 정답 형태: 포트를 URL authority(host 뒤·첫 '/' 앞)에 ──
$ git clone ssh://bandit27-git@bandit.labs.overthewire.org:2220/home/bandit27-git/repo
#            └scheme┘ └──user──┘ └──────────host──────────┘└port┘└────────path────────┘
#   git 이 뒤에서: ssh -p 2220 bandit27-git@host git-upload-pack '/home/bandit27-git/repo'
bandit27-git@...'s password:                # ← bandit27 의 password 입력(키 아님)
# remote: Enumerating objects: 3, done.
# remote: Total 3 (delta 0), reused 0 (delta 0), pack-reused 0
# 오브젝트를 받는 중: 100% (3/3), 완료.

$ cd repo && tree
# .
# └── README

$ cat README
The password to the next level is: <password masked>   # ← Level 28 password

# ── 뒷정리(홈/작업디렉터리 청소) ──
$ cd .. && rm -rf repo        # -r 재귀, -f 무확인 강제 → .git 트리째 삭제
# (잘못된 URL이 남긴 stray '2220' 폴더가 있으면) rm -rf 2220
```

> [!warning] Password Masking & ToS
> `README`의 bandit28 password는 **반드시** `<password masked>`로. clone된 `repo/README`엔 평문 password가 남으니 커밋 전 삭제(`rm -rf repo`)하고, `git diff`로 마스킹 확인. (OTW ToS: 기법만 기록, 답은 넘기지 않는다.)

### 6. Why It Works

git은 원격 전송을 **ssh에 위임**하고, ssh는 URL authority의 `:2220`을 `ssh -p 2220`으로 번역해 게임 sshd에 접속한다. 그 sshd가 **password 인증**을 제공(포트 22의 정문은 publickey만)하고, `bandit27-git`의 password가 **bandit27의 password와 같게** 세팅돼 있어(OTW 설계) 직전 레벨의 성과로 곧장 로그인된다. 인증되면 git이 서버의 `git-upload-pack`으로 객체 3개를 받아오고, 비밀은 default 브랜치 README에 **평문**으로 놓여 있다(입문 레벨이라 숨기지 않음). 핵심은 "**포트는 git이 아니라 ssh의 것**"과 "**URL authority ≠ path**"라는 두 경계.

### 7. Edge Cases / Limitation (= 삽질 로그 & 정직한 불확실성)

- **`-p`는 git clone에 없다**: 포트 플래그 자체가 부재. git은 옵션을 재정렬하므로 `-p`를 URL 뒤에 둬도 소용없다. `-p`는 `ssh(1)`의 옵션.
- **scp식 단축형은 포트를 못 싣는다**: `user@host:path`에서 **첫 콜론=host/path 구분자**라 포트 자리가 없다. `host:2220/path`라 쓰면 `2220/path`가 **상대 원격경로**가 되고 접속은 22번. 포트가 필요하면 `ssh://` 정식 URL 또는 `GIT_SSH_COMMAND`/ssh config.
- **콜론 이중 해석**: `.../repo:2220` → 접속 22 + 폴더명 `2220`. git이 포트를 "떼어내는" 게 **아니라** 오히려 경로 구분자로 취급(정반대). git은 URL이 **host-only(경로 `/` 없음)**일 때만 끝의 `:PORT`를 dir명에서 제거한다 — 경로가 있으면 안 한다.
- **`fatal: ssh variant 'simple' does not support setting port`**: `GIT_SSH_COMMAND`가 가리키는 래퍼를 git이 `ssh -G` 프로브로 **OpenSSH로 인식하지 못하면** 포트 설정을 포기하며 뜨는 별개 메시지(← git 자신의 `unknown switch`와 혼동 금지). 래퍼 basename을 `ssh`로 두면 해결.
- **버전 의존 디테일(정직 고지)**: 원격 argv의 `-o SendEnv=GIT_PROTOCOL` 토큰은 protocol v2(기본 ~git 2.26)·SendEnv(~2.18) 이상에서만 **존재**(v0/구버전엔 없음); 순서는 안정(있을 땐 SendEnv가 `-p`보다 앞). dir-name 로직 함수명도 신버전 `git_url_basename`(dir.c) ↔ 구버전 `guess_dir_name`(builtin/clone.c)으로 다름 — **동작(바이트 단위 동일)**만 신뢰하고 파일/함수명은 버전 의존으로 취급.
- **서버 repo가 bare인지 clone으로는 못 밝힌다**: OTW repo는 관례상 bare이지만, `git clone`은 bare/non-bare에 **동일하게** 동작·출력하므로 클라이언트에서 증명 불가(확인하려면 서버측 `git rev-parse --is-bare-repository`). `.git` 없는 경로명은 bareness 증거가 아니다(오히려 bare는 관례상 `.git` 접미사).
- **로컬 vs 게임서버**: 공식 문구는 `ssh://bandit27-git@localhost:2220/...`(게임서버 안에서)지만, 포트 2220이 외부 공개라 **자기 머신에서 `bandit.labs.overthewire.org:2220`으로 직접 clone**해도 동일 sshd에 닿아 성공(password가 같기 때문). 둘 다 유효.

---

## [Phase 3] Formal Summary (EN)

> [!definition] git clone over `ssh://` — port lives in the authority
> `git clone ssh://[user@]host[:port]/path` makes git exec `ssh [-p port] user@host git-upload-pack '<path>'` (after an `ssh -G` OpenSSH-variant probe). `git clone` has **no** `--port`; the port is delivered to ssh via the URL authority, `GIT_SSH_COMMAND="ssh -p N"`, `git -c core.sshCommand="ssh -p N"`, or an `~/.ssh/config` `Port` directive. The download-side wire command is `git-upload-pack`; the secret is served from the server-side repo.

> [!theorem] The trailing colon is parsed two ways at once
> In `ssh://host/path/repo:PORT` the same `:` is read by two independent parsers with opposite meaning. The **transport** parser (generic RFC-3986, identical across `ssh://`/`git://`/`https://`) reads `:port` **only** in the authority (before the first `/`); a colon later in the path is literal ⇒ connect on the default port. The **directory-naming** parser (`git_url_basename`/`guess_dir_name`) treats `:` as a component separator for scp-like backward compatibility ⇒ the last-colon suffix becomes the local dir name. ∴ `.../repo:2220` connects on 22 **and** clones into `2220` — intended behavior, not a bug. □

---

## [Phase 4] Better Methods

**Current approach** (used above): 포트를 URL authority에 박은 `ssh://user@host:2220/path`. 상태(환경변수/설정) 없이 한 줄로 끝나 가장 깔끔.

**Alternative 1**: ssh 계층에 포트를 위임 (URL을 단순하게 유지)
```bash
GIT_SSH_COMMAND="ssh -p 2220" git clone ssh://bandit27-git@host/home/bandit27-git/repo
#   포트를 git이 아니라 ssh에게 전달 → git은 그대로 ssh -p 2220 … 실행
git -c core.sshCommand="ssh -p 2220" clone ssh://bandit27-git@host/home/bandit27-git/repo
#   동일 효과의 config 형태(-c 로 1회성 config 주입); 둘 다 argv 에 -p 2220 을 emit
```
Trade-off: URL에서 포트를 뺄 수 있어 scp식 단축형과도 조합 가능. 대신 환경변수/설정을 신경 써야 함.

**Alternative 2**: `~/.ssh/config` Host alias (재사용성 최고)
```
Host bandit-otw
    HostName bandit.labs.overthewire.org
    Port 2220
    User bandit27-git
```
```bash
git clone bandit-otw:/home/bandit27-git/repo   # scp식; user/port는 alias가 공급
```
Trade-off: 반복 접속에 최적(오프라인 `ssh -G bandit-otw`로 Port/User 적용 검증 가능). 단 scp식은 `user@`를 안 실으므로 **alias가 User를 반드시 지정**해야 함.

**Most elegant**:
```bash
git clone ssh://bandit27-git@bandit.labs.overthewire.org:2220/home/bandit27-git/repo
```
Why elegant: 포트·유저·경로가 **한 문자열**에 자기완결. 환경 상태 없이 어디서든 재현.

*(세 방법 모두 결국 **bandit27의 password**를 요구한다 — 인증 채널은 동일.)*

---

## [Phase 5] Lessons Learned

1. **포트는 git이 아니라 ssh의 것**: `git clone`엔 `-p`가 없다(`unknown switch 'p'`). 포트는 URL authority(`host:2220`)나 ssh 계층(`GIT_SSH_COMMAND`/config)으로.
2. **`:PORT`는 host 뒤·첫 `/` 앞**: path 끝에 붙이면 (a) 접속은 기본 22, (b) 폴더명이 그 숫자가 된다 — 한 콜론, 두 파서, 정반대 해석(모든 `scheme://`에 공통인 URL 파싱).
3. **`(publickey)` vs `(publickey,password)`** = **서버가 광고한 인증 방법**. 어느 포트에 닿았는지의 tell. 필요한 건 bandit27 password(= bandit27-git, OTW 관례).
4. **3회 실패 후 성공 = 오타**: 클라이언트 `NumberOfPasswordPrompts`(기본 3) 한도. 마지막 줄이 **클라이언트**의 "방법 소진" 메시지라 lockout/rate-limit이 아니라 credential 문제.
5. **clone 출력도 정보다**: 파일1·커밋1 = 객체 3(커밋·트리·블롭). `Compressing 2/2`는 트리(~34B)가 50B delta 문턱 아래라 제외된 결과. 그리고 **버전관리는 이력을 남긴다** → 다음 레벨(L28)은 "지웠지만 history에 남은" 비밀을 캔다.

### Quiz

**Q**: (a) `git clone ssh://host/home/x/repo:2220`이 **포트 22로 접속**하면서 동시에 **`2220`이라는 폴더로 clone**되는 이유를 한 콜론·두 파서로 설명하라. (b) 포트 2220에선 `Permission denied (publickey,password)`, 포트 22에선 `(publickey)`가 뜬다 — 이 괄호가 알려주는 것과, 실제로 필요한 credential은? (c) clone이 `Compressing objects: 100% (2/2)`인데 `Total 3`이다. 왜 2와 3이 갈리는가?

> [!tip]- 풀이
> **(a)** 접속(transport) 파서는 RFC-3986대로 **authority(첫 `/` 이전)에서만** `:port`를 읽는다. `repo:2220`의 콜론은 path 안이라 **리터럴 경로 문자** → 포트 미지정 → 기본 22. 반면 dir-name 파서(`git_url_basename`)는 scp식 하위호환으로 콜론을 **경로 구분자**로 취급 → 마지막 콜론 뒤 `2220`을 폴더명으로. 같은 `:`를 두 코드가 반대로 읽는 **의도된** 동작(버그 아님).
>
> **(b)** 괄호는 **서버가 그 접속에 광고한 인증 방법 목록**(OpenSSH `authlist`). 22번은 password를 아예 제시 안 하는 publickey-only 잠긴 정문(프롬프트조차 없음), 2220번은 password 제공. 필요한 credential은 **bandit27의 password**(bandit27-git = bandit27, 공식 문구). 괄호가 `(publickey,password)`란 건 **2220에 제대로 닿았고 실패는 credential 때문**이란 신호.
>
> **(c)** 객체는 커밋·트리·블롭 = **3**(`Total 3`). 그러나 `Compressing`은 **delta 후보 수**를 센다. pack-objects는 **≥50B** 객체만 delta 탐색 후보로 삼는데, 단일 파일 트리(~34B)가 문턱 아래라 제외 → 후보 = 커밋+블롭 = **2**. 즉 "블롭/커밋을 건너뛴 게 아니라 **트리**가 크기 때문에 빠진" 것. `Total 3 (delta 0)`은 3개 모두 델타 없이 기록됐다는 별개 통계.
>
> 핵심: **포트는 URL authority(=ssh), 콜론 위치가 접속·폴더명을 동시에 좌우**하고, **인증 괄호는 서버가 연 문**을 드러낸다.

> [!flashcard]
> **Q**: 비표준 SSH 포트(2220)의 git repo를 clone하는 세 가지 정답 형태는?
> **A**: (1) URL authority에 포트: `git clone ssh://user@host:2220/path`. (2) ssh 계층: `GIT_SSH_COMMAND="ssh -p 2220" git clone ssh://user@host/path` (또는 `git -c core.sshCommand="ssh -p 2220" clone …`). (3) `~/.ssh/config` Host alias(`Port 2220`+`User`) 후 `git clone alias:/path`. `git clone`엔 `-p`가 없다.

> [!flashcard]
> **Q**: `git clone ssh://host/a/b/repo:2220`의 두 증상과 원인은?
> **A**: (i) **포트 22로 접속**(콜론이 path 안 → transport 파서엔 리터럴), (ii) **폴더명 `2220`**(dir-name 파서엔 콜론=구분자, scp식 하위호환). 한 콜론을 두 파서가 반대로 해석 — 의도된 동작. 포트는 host 뒤·첫 `/` 앞에 둬야 한다.

> [!flashcard]
> **Q**: SSH 실패 시 `Permission denied (publickey,password)`의 괄호는 무엇을 뜻하나?
> **A**: **서버가 그 연결에 제공한 인증 방법 목록**. `(publickey)`만이면 password 미제공(예: OTW 포트 22), `(publickey,password)`면 password도 제공(포트 2220). 어느 포트/문에 닿았는지의 진단 신호.

> [!flashcard]
> **Q**: 비밀을 git repo에 넣었다가 나중 커밋에서 지우면 안전한가?
> **A**: 아니다. content-addressable history가 옛 blob을 계속 보관 → `git log -p`/`git show`/reflog로 복원 가능(= Bandit L28의 원리). 진짜 제거는 history 재작성(`git filter-repo`/BFG) + force-push + **credential 회전**.

---

## Links

### Tools Used
- [[Tools/git]] (clone over ssh:// — 새 tool, dangling)
- [[Tools/ssh]] (전송 위임 대상; `-p` 포트는 여기 소속)
- [[Tools/cat]] (README 읽기)
- [[Tools/tree]] / [[Tools/ls]] (repo 구조 확인)

### Concepts Introduced (first encountered here)
- [[Concepts/Network/Git_Over_SSH]] (lite-note 후보 @EOL — git 전송의 ssh 위임 + `ssh://` URL authority/port 문법 + secrets-in-VCS 입문)

### Concepts Applied (reused from earlier)
- [[Concepts/Network/SSH_Key_Authentication]] (L13 — 여기선 key가 아닌 **password** 인증, 같은 ssh 전송 위 non-default 포트 2220은 L00의 `-p 2220` 재적용)
- [[Concepts/Linux/Shell_Fundamentals]] (URL/인자 파싱, quoting — `git-upload-pack '<path>'`의 single-quote)

### Navigation
- **Prerequisite**: [[Level_26]] (bandit27 password = 이 레벨의 clone credential), [[Level_00]] (SSH `-p 2220` 최초 등장)
- **Next**: [[Level_28]] (git **history**에서 지워진 비밀 복원 — 이 레벨의 secrets-in-VCS 후속)
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit28.html ("The password for the user bandit27-git is the same as for the user bandit27.")
- `git-clone(1)` — GIT URLS 절(`ssh://[user@]host[:port]/path`, scp식 `host:path`); `git help environment` (`GIT_SSH_COMMAND`), `git help config` (`core.sshCommand`)
- `gitprotocol-pack(5)` / `git-upload-pack(1)` — clone/fetch download side
- `ssh_config(5)` — `Port`/`User`/`HostName`, `NumberOfPasswordPrompts`(기본 3); `sshd_config(5)` — `MaxAuthTries`(기본 6), `Match LocalPort`
