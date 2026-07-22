---
date: 2026-07-21
wargame: Bandit
level: 31
title: "Bandit Level 31 → 32"
difficulty: ★★★
time_spent: 20min
tags: [bandit, linux, git, git-push, pre-receive-hook, server-side-hooks, gitignore, add-force, receive-pack, version-control, capstone]
status: 🟡 developing
tools_used: [git, vi, cat, tree, ls]
new_concepts: [Git_Server_Side_Hooks]
prerequisites: [Level_30, Level_27]
---

# Bandit Level 31 → 32

## [Phase 1] Executive Summary

- **Goal**: clone한 repo에 **파일을 push**하는 과제 — `key.txt`(내용 `May I come in?`)를 master로. 함정 둘: (1) repo의 **`.gitignore = *.txt`**가 `git add key.txt`를 막는다 → **`git add -f`** 필요. (2) 서버의 **pre-receive hook**이 파일을 검증해 **password를 출력한 뒤 push를 거부**한다 → 이기는 push조차 `! [remote rejected] master -> master (pre-receive hook declined)`로 끝나고, **password는 그 위 `remote:` 줄**에 있다. 이건 실패가 아니라 **설계된 성공 신호**.
- **Key Skill**: git **push**(첫 write 레벨) + `.gitignore` **force-add** 우회 + **server-side pre-receive hook** 이해. clean clone에서 정답은 **딱 3줄**: `git add -f key.txt` → `git commit -m <비지 않은 메시지>` → `git push`. (세션의 fetch/pull/merge/switch/checkout/reset 난동은 전부 불필요했다.)
- **Tags**: `[Git_Server_Side_Hooks]`(new), `[Git_Object_Model]`(L28 reapply), `[Git_Over_SSH]`(L27) — **git 아크(27–31)의 capstone: READ→WRITE**.

[Cognitive Validation]
- **Limit Test**: 여러 ref를 한 번에 push하면 pre-receive는 **딱 한 번** 실행되고 stdin으로 ref별 `old new refname` **N줄**을 받는다 — "push당 1회"(≠ ref당 1회, 그건 `update` hook)의 증거.
- **Control Knob**: **hook의 exit code**(0=수락 / non-zero=거부)가 **유일한** 수락/거부 다이얼. `git push --force`도, pull/merge도 이 다이얼을 못 돌린다(그건 fast-forward 검사만 건드림). hook을 `exit 0`으로 바꾸면 곧장 성공.
- **Nullity**: `.gitignore`가 비었다면 `add -f`가 불필요(평범한 add 성공); pre-receive hook이 없었다면 push가 성공해 **golden repo가 오염**됐을 것. 이 두 장치가 레벨을 만든다.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**Git push (write path) + server-side hook gatekeeping + `.gitignore`.** L27–30은 전부 **읽기**(clone/fetch = 서버의 `git-upload-pack`)였다. L31은 아크의 **capstone**으로 처음이자 유일한 **쓰기**(push = 클라이언트 send-pack → 서버 `git-receive-pack`)이고, 그 쓰기를 **서버 pre-receive hook**이 검문한다. 보안적으로 이건 L28–30의 "읽기-측 유출"(history/branch/tag)에 대한 **쓰기-측 방어 게이트** — 서버가 들어오는 push를 정책대로 검증·거부하는 자리다.

### 2. Definition (Formal, EN)

`git push` uploads the client's new objects: the client's **send-pack** side speaks to the server's **`git-receive-pack`** (the write counterpart of clone/fetch's `git-upload-pack`). The server unpacks the received objects into a **quarantine** object dir (`GIT_QUARANTINE_PATH`), then runs the **`pre-receive`** hook **once per push**, reading one `<old> <new> <refname>` line per ref-update from **stdin**, *after* objects are received but *before* any ref is updated. A **non-zero** exit **rejects the entire push** atomically: no ref advances and the quarantined objects are **discarded** (nothing is "committed then rolled back"). The hook's **stdout and stderr are both relayed to the client** as `remote:` lines regardless of exit status — so the hook can **print the password and still decline**. Separately, `.gitignore` `*.txt` makes a plain `git add key.txt` refuse (prints an ignore notice, stages nothing, exit 1); `git add -f` forces the add (needed only for the initial add of the untracked file).

### 3. Intuition (KR)

push는 처음으로 서버에 **쓰는** 작업이다(읽기=`upload-pack` ↔ 쓰기=`receive-pack`). 서버 **문지기(pre-receive)**는 들어온 짐(objects)을 곧장 창고 선반(ref)에 올리지 않고 **격리 창고(quarantine)**에 받아 검사한다. 규칙(`key.txt` == `May I come in?`)을 만족하면 문틈으로 **password를 알려주고**, 그러고도 **선반엔 안 올린 채 격리 짐을 버린다**(`exit 1`). 그래서 password를 받고도 화면 끝은 `remote rejected` — golden repo가 그대로 유지돼 **다음 사람도 같은 출발선**에 서게 하는 설계다. `.gitignore *.txt`는 `key.txt`를 "안 보이게" 해서 `-f`로 억지로 담아야 문 앞까지 갈 수 있다.

### 4. Theory (Mechanism)

1. **정찰**: clone(`Total 4` = 1 commit + 1 tree + 2 blobs: `.gitignore`=`*.txt`, `README.md`=과제). README가 `key.txt`/`May I come in?`/`master`를 지시.
2. **`.gitignore` 우회**: `git add key.txt`는 무시 안내(`The following paths are ignored ... Use -f if you really want to add them.`)를 내고 **exit 1**·무스테이징. **`git add -f key.txt`**로 강제(`-f`=`--force`). `.gitignore`는 **untracked만** 관장하므로 `-f`는 **최초 1회**만 필요(이후 tracked라 무관). 진단: `git check-ignore -v key.txt` → `.gitignore:1:*.txt⇥key.txt`(source:line:pattern⇥path; **exit 0 = 무시됨**, 직관과 반대), `git status --ignored` → `!! key.txt`.
3. **커밋**: `git commit`(빈 메시지)은 `Aborting commit due to empty commit message`로 중단(HEAD 불변). `git commit -m ","`로 커밋 — **쉼표는 비지 않은 정상 메시지**(git은 공백/빈 메시지만 거부, 내용은 검증과 무관).
4. **push = write**: `git push` → send-pack→receive-pack. 출력 `Total 3 (delta 0)` = **보낸 새 객체 3개**(새 commit + 새 tree + `key.txt` blob; delta 0 = 통째). (`Enumerating/Counting: 4`는 공유 base까지 세는 넓은 walk — 실제 전송은 `Writing/Total = 3`.)
5. **서버 pre-receive 게이트**: 서버가 objects를 **quarantine**(`GIT_QUARANTINE_PATH=…/tmp_objdir-incoming-XXXX`)에 받고, stdin으로 `old new refname`을 읽어 `key.txt`를 검증 → 통과 시 **password를 출력**(hook의 stdout/stderr는 `remote:`로 중계) → **`exit 1`로 push 거부** → **ref 불변·quarantine 폐기**. 그래서 이긴 push도 `! [remote rejected] master -> master (pre-receive hook declined)`.
6. **hook 지도**: **pre-receive**(서버·push당 1회·stdin·전체 거부/수락) ↔ **update**(서버·ref당 1회·argv) ↔ **post-receive**(서버·성공 후) ↔ **pre-commit/commit-msg**(클라이언트·commit 시). clone의 `.git/hooks/*.sample`은 **실행 안 되는 템플릿**이고, 서버의 진짜 pre-receive는 **클라이언트에 전송되지 않는다** → `pre-receive.sample`을 열어보거나 고쳐도 **아무 효과 없음**(red herring).

인과: `.gitignore`가 add를 막음 → `-f`로 담아 commit → push가 send-pack으로 객체 전송 → 서버 pre-receive가 quarantine에서 검증·password 출력·`exit 1` → ref 불변, password는 `remote:` 줄에.

### 5. Solution

```bash
# 0) clone (L27 방식; 쓰기 가능한 임시 디렉터리에서)
$ git clone ssh://bandit31-git@bandit.labs.overthewire.org:2220/home/bandit31-git/repo repo31
$ cd repo31
$ cat README.md          # 과제: key.txt = 'May I come in?' → master   /   cat .gitignore → *.txt

# 1) key.txt 생성 후 .gitignore(*.txt) 넘어 강제 스테이징
$ printf 'May I come in?\n' > key.txt      # (세션에선 vi key.txt)
$ git add key.txt                          # → 무시 안내 + exit 1 (staged 없음)
$ git add -f key.txt                        # -f/--force: ignore 규칙 무시하고 강제 add (최초 1회만)

# 2) 커밋 (메시지는 '비지 않기만' 하면 됨 — 내용 무관)
$ git commit -m ","                         # 빈 메시지는 'Aborting commit due to empty commit message'로 거부됨

# 3) push → 서버 pre-receive가 검증·출력·거부
$ git push
# remote: ### Attempting to validate files... ####
# remote: Well done! Here is the password for the next level:
# remote: <password masked>                 ← Level 32 password (이 remote: 줄에 있다)
# To ssh://bandit.labs.overthewire.org:2220/home/bandit31-git/repo
#  ! [remote rejected] master -> master (pre-receive hook declined)   ← 정상! (설계된 거부)

# ── 정리(로컬만; 서버엔 아무것도 안 남음) ──
$ cd .. && rm -rf repo31
```

> [!warning] "remote rejected"는 성공 신호 & Password Masking
> 이 레벨은 **성공해도** `pre-receive hook declined`로 끝난다 — password는 그 **위 `remote:` 줄**에 있다. 이를 실패로 오인해 retry/force/pull하지 말 것. bandit32 password는 `<password masked>`로(OTW ToS + CLAUDE.md [1]); 커밋 전 leak-scan + pre-commit dry-run, `--no-verify` 금지(하네스 하드블록).

### 6. Why It Works

push는 클라이언트가 새 객체를 서버 `receive-pack`에 올리는 **쓰기**다. 서버는 그 객체를 **quarantine**에 받아 **pre-receive** hook으로 검문하는데, 이 hook은 `key.txt` 내용을 확인해 password를 `remote:`로 흘려주고 **`exit 1`로 push를 거부**한다. 거부(non-zero)면 **어떤 ref도 갱신되지 않고** quarantine 객체는 폐기되므로 golden repo는 불변 — 그래서 password를 받고도 "rejected"이고, 다음 플레이어도 동일한 초기 상태를 clone한다. `.gitignore *.txt`는 `key.txt`를 add에서 숨겨 `-f`를 강제하는 관문일 뿐. 핵심 등식: **수락/거부는 오직 hook의 exit code** — `--force`도 pull/merge도 그 결정을 못 바꾼다.

### 7. Edge Cases / Limitation (= 이번 세션 삽질 로그)

이 레벨의 긴 삽질은 **"push 거부 = git 동기화 문제"라는 오인**에서 비롯됐다. 실제 원인을 하나의 모델로:

- **`--force`는 pre-receive를 못 뚫는다**: `--force`는 **fast-forward 검사만** 완화한다. 서버 hook의 `exit 1`은 별개라 force로도 항상 거부(git semantics; 이번 세션 force도 declined).
- **`fetch first` vs `non-fast-forward`는 한 규칙**: push는 원격 ref의 **fast-forward**여야 한다. `fetch first` = 로컬 `origin/master`가 **낡음**(원격이 안 보이게 이동). `non-fast-forward` = 이미 fetch해서 **갈라짐(ahead/behind)**을 아는 상태. 같은 규칙, 다른 앎의 시점 — 별개 버그 아님. 둘 다 hook 이전의 **읽기용 거부**.
- **`git pull → "Already up to date"`인데 push는 여전히 거부**: pull은 병합할 게 없었을 뿐(`origin/master`가 로컬의 조상). push 거부의 원인(hook)은 **독립적** → pull은 애초에 틀린 도구.
- **`refusing to merge unrelated histories`(+`(forced update)`)**: 원격 ref가 **공통 조상 없는 root로 force-update**됨(`+ d8580d6...03653d5`). `--allow-unrelated-histories`로 병합은 가능하나 **레벨엔 병합 자체가 불필요**. ⚠️ 이 force-update는 **서버측**(동시 플레이어/공유 repo) — 내 잘못 아님. 내가 만든 건 **`.gitignore`를 먼저 커밋한 것 + 그 뒤 반응성 난동**뿐.
- **`checkout` vs `switch`**: `git checkout remotes/origin/master` → **detached HEAD**(remote-tracking ref를 체크아웃; DWIM 추적브랜치 생성은 **맨이름**(`git checkout master`)에만 발동). `git switch remotes/origin/master` → **거부**(`a branch is expected, got remote branch`) — switch는 더 엄격해 local branch/`-c`/`--detach`/맨이름 DWIM만 받는다.
- **`reset` 모드**: `--soft`(HEAD만) / `--mixed`(기본; HEAD+index, 작업트리 보존 → 수정이 unstaged로 남음) / `--hard`(HEAD+index+작업트리, **파괴적**). `HEAD~1` = 첫 부모 1세대 전. 세션의 `reset HEAD~1`(mixed) → `reset --hard HEAD`가 clone을 초기 커밋으로 되돌렸다.
- **`.gitignore` 편집은 불필요·해로움**: 정답은 `add -f`뿐. `.gitignore`(이미 tracked)를 고쳐 커밋한 게 **divergence의 씨앗**이었다.
- **`.git/hooks/*.sample` red herring**: 클라이언트의 비활성 템플릿. 서버 실hook은 클라에 안 온다.
- **`git branch -a`가 빈 출력**은 이상(paste/pager artifact). 정상 clone은 `* master`, `remotes/origin/HEAD -> origin/master`, `remotes/origin/master`를 나열.
- **더 나은 복구**: 갈라진 상태는 `git reset --hard origin/master`(또는 **재clone**) 한 줄이면 clean base로. pull/merge/switch 난동 불필요.

---

## [Phase 3] Formal Summary (EN)

> [!definition] Push as a server-gated write
> `git push` sends new objects via send-pack to the server's `git-receive-pack`, which quarantines them and runs the server-side **`pre-receive`** hook once per push (ref-updates on stdin) **before** any ref moves. A non-zero exit rejects the whole push atomically (no ref advances; quarantined objects discarded), yet the hook's stdout/stderr are relayed to the client as `remote:` lines — so it can reveal a secret and still decline.

> [!theorem] The hook's exit code is the sole gate; output is orthogonal to it
> Accept/reject is a pure function of the pre-receive exit status; `git push --force`, `pull`, and merge only affect fast-forward/divergence checks that run *before* the hook, never the hook's verdict. Because output relay is independent of exit status, the winning push necessarily prints the password **and** ends in `(pre-receive hook declined)`. ∴ the golden repo is immutable to any client (ref never moves, objects quarantined-and-dropped), and "remote rejected" is the designed success terminal state — not a failure to retry or force. □

---

## [Phase 4] Better Methods

**Current approach** (correct solve, minimal): from a clean clone, exactly three commands.
```bash
git add -f key.txt        # -f/--force: stage the '*.txt'-ignored file (one-time; only untracked paths are ignored)
git commit -m ","          # any non-empty message; blank/whitespace-only is refused
git push                    # read the password in the remote: lines; the (declined) rejection is expected
```
Trade-off: 없음 — 이게 정공법. 나머지 fetch/pull/merge/switch/checkout/reset은 **게이트와 무관**한 헛수고였다.

**Diagnostics** (왜 add가 막히나 / 뭐가 무시되나):
```bash
git check-ignore -v key.txt   # '.gitignore:1:*.txt⇥key.txt' — 매칭 규칙 위치. exit 0 = 무시됨(직관 반대)
git status --ignored          # 무시된 파일(!! key.txt)까지 표시; 기본 status는 침묵
```

**Recovery from the divergence mess** (세션이 놓친 한 줄):
```bash
git reset --hard origin/master   # 갈라진 로컬을 원격 tip으로 강제 정렬(작업트리째) — pull/merge 난동 대체
# 또는 그냥 재clone. (--allow-unrelated-histories 는 존재하나 이 레벨엔 불필요.)
```

**Counter-opinion**: `.gitignore`를 편집해 `*.txt` 규칙을 없애는 접근은 **오답** — 검증은 `key.txt` **내용**을 보지 `.gitignore`를 보지 않고, 그 편집이 divergence를 촉발했다. 최소 개입(`add -f`)이 정답.

---

## [Phase 5] Lessons Learned

1. **push는 write, clone/fetch는 read**: send-pack→`receive-pack` ↔ `upload-pack`. `Total 3` = 보낸 새 객체(commit+tree+blob). L27–30(read)의 **capstone**이 L31(write).
2. **수락/거부는 오직 pre-receive의 exit code**: `--force`·pull·merge 무력. 이긴 push도 `remote rejected`로 끝나고 **password는 `remote:` 줄에** — 설계된 성공.
3. **거부 = quarantine 폐기, not rollback**: 서버는 objects를 격리해 검사하고 실패 시 ref 불변·격리 폐기 → golden repo 불변. 클라이언트는 서버 hook을 못 보고 못 바꾼다(`*.sample`은 무력).
4. **`.gitignore`는 untracked만 관장**: `git add -f`는 **최초 1회**. 진단은 `git check-ignore -v`(exit 0=무시). `.gitignore` 편집은 불필요·해로움.
5. **삽질의 교훈**: 3줄이면 될 걸 "동기화" 오인이 spiral을 낳았다. `fetch first`=`non-fast-forward`(한 규칙), `unrelated histories`는 **서버측 force-update**(내 탓 아님), 복구는 `reset --hard origin/master` 한 줄.

### Quiz

**Q**: (a) `key.txt`를 올바로 push했는데도 화면 끝이 `! [remote rejected] ... (pre-receive hook declined)`다. 이게 왜 **성공**이고 password는 어디 있나? (b) `git push --force`·`git pull`·merge 중 무엇이 이 push를 **수락**시킬 수 있나? (c) `git add key.txt`가 왜 실패하며, `git checkout remotes/origin/master`와 `git switch remotes/origin/master`는 왜 다르게 동작하나?

> [!tip]- 풀이
> **(a)** 서버 **pre-receive hook**이 `key.txt`를 검증해 password를 `remote:`로 출력한 **뒤 `exit 1`로 push를 거부**하도록 설계됐다. non-zero exit는 push 전체를 거부(ref 불변, quarantine 객체 폐기)하지만, hook의 출력은 exit와 무관하게 클라에 중계된다. 그래서 password는 **거부 줄 위의 `remote:` 줄**에 있고, 거부는 golden repo를 다음 사람 위해 보존하려는 **의도된 종착점**.
>
> **(b)** **아무것도 못 시킨다.** 수락/거부는 오직 pre-receive의 exit code. `--force`는 fast-forward 검사만 완화하고, pull/merge는 divergence만 다룬다 — 셋 다 hook의 판정을 못 건드린다. (hook을 `exit 0`으로 바꿀 수 있어야 수락되는데, 그건 서버측이라 불가.)
>
> **(c)** `.gitignore`의 `*.txt`가 `key.txt`를 무시해 `git add key.txt`가 안내만 내고 exit 1(무스테이징) → `git add -f`로 강제. `git checkout remotes/origin/master`는 remote-tracking ref를 체크아웃해 **detached HEAD**가 되고(추적브랜치 DWIM은 맨이름에만), `git switch`는 더 엄격해 **local branch가 아니면 거부**(`a branch is expected, got remote branch`)한다.
>
> 핵심: **push는 서버가 검문하는 쓰기이고, 문지기의 exit code만이 문을 연다. 클라이언트의 어떤 조작도 그 결정을 못 바꾼다.**

> [!flashcard]
> **Q**: Bandit31에서 올바른 push가 `pre-receive hook declined`로 끝나는 이유와 password 위치는?
> **A**: 서버 pre-receive hook이 파일 검증 후 password를 `remote:`로 출력하고 **`exit 1`로 push를 거부**(ref 불변·quarantine 폐기 → golden repo 보존). password는 **거부 줄 위의 `remote:` 줄**. 거부는 설계된 성공 신호.

> [!flashcard]
> **Q**: `.gitignore`가 `*.txt`인 repo에 `key.txt`를 커밋에 넣는 법과 `-f`의 범위는?
> **A**: `git add -f key.txt`(`-f`=`--force`, ignore 무시). `.gitignore`는 **untracked만** 관장하므로 `-f`는 **최초 add 1회**만 필요(이후 tracked라 무관). 진단: `git check-ignore -v key.txt`(exit 0=무시).

> [!flashcard]
> **Q**: git push(write)와 clone/fetch(read)의 서버측 프로그램·hook 차이는?
> **A**: push = 클라 send-pack → 서버 **`receive-pack`** + **pre-receive**(서버·push당 1회·stdin·전체 거부) / update(ref당 1회) / post-receive(성공 후). clone/fetch = 서버 **`upload-pack`**. pre-commit/commit-msg는 **클라이언트** hook(무관).

> [!flashcard]
> **Q**: 서버가 push를 거부하면 보낸 객체는 어떻게 되나?
> **A**: receive-pack이 객체를 **quarantine**(`GIT_QUARANTINE_PATH`)에 받아 검사하고, pre-receive가 non-zero면 **ref 불변 + quarantine 폐기**. "커밋 후 롤백"이 아니라 **애초에 반영 안 됨** → golden repo 불변.

---

## Links

### Tools Used
- [[Tools/git]] (`clone`, `add -f`, `commit -m`, `push`, `check-ignore -v`, `status --ignored`, `reset --hard/--mixed`, `switch`/`checkout`, `branch -a`)
- [[Tools/vi]] (`key.txt` 생성) / [[Tools/cat]] / [[Tools/tree]] / [[Tools/ls]]

### Concepts Introduced (first encountered here)
- [[Concepts/Linux/Git_Server_Side_Hooks]] (lite-note 후보 @EOL — push write-path(send-pack/receive-pack), pre-receive 게이트·quarantine, hook taxonomy; `.gitignore`/`add -f`도 함께)

### Concepts Applied (reused from earlier)
- [[Concepts/Linux/Git_Object_Model]] (L28 — objects/refs; push가 보내는 commit+tree+blob)
- [[Concepts/Network/Git_Over_SSH]] (L27 — 같은 ssh:2220 transport, 이번엔 write)

### Navigation
- **Prerequisite**: [[Level_30]] (git tag; 아크의 read 파트 마지막), [[Level_27]] (git-over-SSH transport)
- **Next**: [[Level_32]] (UPPERCASE shell 탈출 — git 아크 종료)
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit32.html
- `githooks(5)` (pre-receive/update/post-receive vs client pre-commit), `git-receive-pack(1)`, `git-send-pack(1)`
- `gitignore(5)`, `git-check-ignore(1)` (`-v`, exit codes), `git-add(1)` (`-f/--force`), `git-reset(1)` (`--soft/--mixed/--hard`), `git-switch(1)`/`git-checkout(1)` (remote branch, `--detach`)
