---
date: 2026-07-20
wargame: Bandit
level: 29
title: "Bandit Level 29 → 30"
difficulty: ★★☆
time_spent: 10min
tags: [bandit, linux, git, git-branch, remote-tracking, version-control, object-model, verify-pack, cat-file, secrets-in-vcs]
status: 🟡 developing
tools_used: [git, cat, tree, ls]
new_concepts: []
prerequisites: [Level_28]
---

# Bandit Level 29 → 30

## [Phase 1] Executive Summary

- **Goal**: `bandit29-git` repo를 clone하면 **master의 `README.md`는 `password: <no passwords in production!>`** — 껍데기 placeholder다. 진짜 bandit30 password는 **다른 branch**(비-master)에 커밋돼 있다. 그 branch의 blob을 찾아 읽는다. (L28은 같은 branch의 **과거**, L29는 **다른 branch**의 현재 — object model은 그대로, **비밀이 걸린 ref**만 바뀐다.)
- **Key Skill**: git **branch reachability**. 정공법은 `git branch -a`로 `remotes/origin/dev`를 발견 → `git show origin/dev:README.md`. 이번 세션은 L28의 **통합 수동법** 재사용 — `git verify-pack -v`로 pack 내 전 객체 열거 → `git cat-file -p d395d041`로 branch blob 덤프.
- **Tags**: `[Git_Object_Model]`(L28 reapply), `[Git_Over_SSH]`(L27), `[Secrets_In_VCS]`

[Cognitive Validation]
- **Limit Test**: master만 보면(`cat README.md`) 영원히 placeholder. 비밀은 **체크아웃 안 된 branch**에 있다. 그런데도 로컬에서 캐지는 이유 → clone이 **모든 advertised head를 remote-tracking ref로** 받아 pack에 도달가능 객체를 다 담기 때문.
- **Control Knob**: 지배 변수는 **어느 ref에서 도달가능한가**. `dev` branch tip → 진짜 password blob(`d395d041`). master tip → placeholder. 같은 pack, 다른 ref.
- **Nullity**: 순수 `git branch`(플래그 없음)는 **로컬 master만** 보여줘 아무 단서도 없다. `-a`/`-r`로 **remote-tracking ref**를 켜야 `dev`가 드러난다 — "안 보임"이 곧 "플래그가 부족함".

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**Git branch (remote-tracking) reachability.** L28에서 세운 object model·`verify-pack`/`cat-file` 방법론을 그대로 쓰되, 비밀이 **history**가 아니라 **다른 branch**에 있다는 점만 다르다. 핵심 오해 방지: `git clone`은 dev를 **체크아웃하지 않는다**. 대신 원격의 모든 head(`refs/heads/*`)를 **remote-tracking ref(`refs/remotes/origin/*`)**로 받아오고, packfile에 그 ref들에서 도달가능한 **모든 객체**를 담는다. 그래서 dev의 blob이 **체크아웃 없이도** 로컬에 존재한다. master의 placeholder는 git이 가린 게 **아니라** 저자가 master에 **일부러 커밋한 문자열** — 진짜 값은 처음부터 master에 없었다(L28과의 결정적 차이).

### 2. Definition (Formal, EN)

A `git clone` fetches every advertised head into **remote-tracking refs** `refs/remotes/origin/<branch>` and packs all objects reachable from them; it checks out **one** branch (master) into the working tree. Thus a secret committed on a non-default branch `dev` is present in the local pack — reachable via `origin/dev` — while `cat README.md` shows only master's committed placeholder `<no passwords in production!>`. `git branch -a` (`--all`) lists local + remote-tracking refs; plain `git branch` shows only local. The branch blob is dumpable without checkout via `git show origin/dev:README.md` or, storage-agnostically, `git verify-pack -v` + `git cat-file -p <blob>`.

### 3. Intuition (KR)

clone은 서랍(pack)에 **모든 branch의 사진**을 복사해 오지만, 벽에 걸어 보여주는 건(체크아웃) master 한 장뿐이다. master 사진엔 "여기 비밀 없음"이라 적혀 있다 — 그게 원본이라서가 아니라 **저자가 그렇게 걸어둔 것**. 진짜 사진은 서랍 속 `dev` 칸에 있다. `git branch -a`로 서랍 칸 목록을 켜거나, 아예 서랍의 **모든 사진을 훑으면**(`verify-pack`+`cat-file`) 나온다.

### 4. Theory (Mechanism)

1. **clone** → `Total 16 (delta 2)`, 5 commits. master 작업트리 README = `password: <no passwords in production!>`(placeholder).
2. **왜 로컬에 dev 비밀이 있나**: clone이 원격 head들을 `refs/remotes/origin/*`로 받아오고(그중 `origin/dev`), pack에 그 ref 도달 객체를 전부 담았다. **체크아웃과 무관** — reachability가 열쇠(L28 정리 재적용).
3. **수동 복원**: `git verify-pack -v …idx`로 16개 객체 열거 → 후보 blob들을 `git cat-file -p`로 덤프. `d395d041`(README 변형) → 진짜 bandit30 password.
4. **열거된 blob들의 정체**:
   - `d395d041` — 진짜 password를 담은 README(whole/base; **가장 큰** 변형이라 base).
   - `1af21d3f`, `2da2f39a` — placeholder 변형들(각각 `d395d041` 기준 **delta**, `(delta 2)`와 일치).
   - `8b137891` — **1바이트 blob = 단일 개행(`\n`)**. (빈 blob은 `e69de29`(0바이트)로 다름 — 헷갈리지 말 것.) git 어디서나 나오는 상수 객체.
5. **정직 고지(객체 분해)**: `Total 16` = commits(5) + trees + blobs 의 항등식은 참이나, **정확한 tree/blob 개수 분해는 이 세션 로그만으론 확정 불가**(4개 blob만 확인, 실제론 더 있을 가능성 큼). "16=5+11(비-commit)"과 확인된 blob 목록까지만 신뢰하고 세부 분해는 라이브 repo 기준으로.

인과: 저자가 진짜 값을 `dev`에만 커밋(B) → clone이 `origin/dev`를 remote-tracking으로 받아 pack에 도달객체 포함(C) → `verify-pack`+`cat-file`(또는 `show origin/dev:README.md`)로 dev blob 덤프(D) → password 복원.

### 5. Solution

```bash
# 0) clone (L27 방식)
$ git clone ssh://bandit29-git@bandit.labs.overthewire.org:2220/home/bandit29-git/repo repo29
$ cd repo29

# 1) master 작업트리는 껍데기
$ cat README.md
# ... password: <no passwords in production!>     ← master에 커밋된 placeholder(비밀 아님)

# 2) pack 내 모든 객체 열거 → 후보 blob 덤프  (L28 통합 수동법 재사용)
$ git verify-pack -v .git/objects/pack/pack-<hash>.idx
# … d395d041… blob 134 …   ← README 최대 변형(whole/base)
# … 1af21d3f… blob … 1 d395d041…   /  2da2f39a… blob … 2 …   ← placeholder delta들
# … 8b137891… blob 1 …     ← 단일 개행('\n') blob

$ git cat-file -p d395d041          # -p = pretty-print (delta 투명 재구성, 체크아웃 불필요)
# ... username: bandit30 ... password: <password masked>     ← Level 30 password

# ── 정리 ──
$ cd .. && rm -rf repo29
```

> [!warning] Password Masking
> bandit30 password는 `<password masked>`. master의 `<no passwords in production!>`는 **저자가 커밋한 리터럴 placeholder**라 그대로 둬도 secret이 아님(git이 가린 게 아님). 덤프한 dev blob의 실값만 마스킹.

### 6. Why It Works

`git clone`은 원격의 **모든 branch**를 `refs/remotes/origin/*`로 받아오고 pack에 그 도달 객체를 전부 담지만, 작업트리엔 **master 하나만** 체크아웃한다. 그래서 `dev`에만 있는 진짜 password blob(`d395d041`)이 **로컬 pack에 존재**하고, `git show origin/dev:README.md`나 `verify-pack`+`cat-file`로 **체크아웃 없이** 읽힌다. master의 placeholder는 git의 redaction이 아니라 **저자의 커밋** — 진짜 값은 애초에 master에 없었다. 핵심 등식: **로컬 존재 = (체크아웃이 아니라) advertised ref에서의 도달가능성**.

### 7. Edge Cases / Limitation

- **순수 `git branch`는 무력**: 로컬 master만 보인다. `dev` 발견엔 `git branch -a`(`--all`, 로컬+remote-tracking) 또는 `-r`(`--remotes`) 필요.
- **"체크아웃했다"는 오해 금지**: clone은 dev를 체크아웃하지 않는다. dev 객체가 로컬에 있는 건 **remote-tracking ref + pack reachability** 덕분이지 체크아웃 때문이 아니다.
- **placeholder ≠ redaction**: master의 `<no passwords in production!>`는 저자가 커밋한 문자열. git이 자동으로 비밀을 지우는 일은 없다(모든 blob을 그대로 저장).
- **delta base 방향은 크기 휴리스틱**: `d395d041`이 base인 건 **최대 변형**이라서. "진짜 비밀=delta base"를 일반 법칙으로 쓰면 안 됨(바이트 크기가 뒤집히면 역할도 뒤집힘). 의지할 불변량은 **reachability**이지 whole/delta 지위가 아니다.
- **객체 분해 과신 금지**: 세션 로그만으론 16개의 정확한 tree/blob 분해를 확정 못 함. `8b137891`=개행 blob은 확실(로컬 재현).

---

## [Phase 3] Formal Summary (EN)

> [!definition] Branch reachability via remote-tracking refs
> `git clone` writes every advertised head to `refs/remotes/origin/<branch>` and packs all reachable objects, but checks out only one branch. A secret committed on `dev` is therefore local (reachable via `origin/dev`) though the working tree shows master's placeholder. Read it without checkout: `git show origin/dev:README.md`, or storage-agnostically `git verify-pack -v` + `git cat-file -p <blob>`.

> [!theorem] `git branch` visibility ≠ object presence
> Object presence is decided by pack reachability from any fetched ref; branch *visibility* in `git branch` is decided by a display filter (`-a`/`-r` include remote-tracking, plain does not). ∴ a `dev`-only blob can be **present and dumpable** while `git branch` (no flag) shows nothing — the two are orthogonal, so "not listed" never implies "not local." □

---

## [Phase 4] Better Methods

**Current approach** (used above): L28의 통합 수동법 `verify-pack -v` → `cat-file -p d395d041`. storage-agnostic(어느 ref인지 몰라도 캠), 대신 노이즈.

**Alternative 1** (정공법 — branch 인지):
```bash
git branch -a                    # --all: 로컬 + remote-tracking → remotes/origin/dev 발견
git show origin/dev:README.md     # <rev>:<path> = dev tip 트리의 README blob 덤프 (체크아웃 불필요)
git log --all -p -- README.md     # --all: 모든 ref(remote-tracking+tag) 순회, -p: +password/-placeholder diff
git checkout dev                  # DWIM: origin/dev 추적하는 로컬 dev 자동 생성 후 cat README.md
```
Trade-off: "branch에 있다"를 알면 가장 의미론적·깔끔. `show origin/dev:README.md`가 최소.

**Most elegant**:
```bash
git show origin/dev:README.md
```
Why elegant: 브랜치 하나·경로 하나를 지목해 **체크아웃 없이** 정확히 그 blob만 꺼낸다.

---

## [Phase 5] Lessons Learned

1. **clone은 모든 branch를 받되 하나만 체크아웃**: 나머지는 `refs/remotes/origin/*` + pack에 산다. 비밀이 다른 branch면 거기 있다.
2. **로컬 존재 = reachability, 가시성 = 플래그**: 객체는 pack 도달성으로 존재; `git branch`는 `-a`/`-r` 없으면 remote-tracking을 안 보여줌. "안 보임 ≠ 없음".
3. **placeholder는 저자의 커밋**: `<no passwords in production!>`를 git redaction으로 오해 말 것. 진짜 값은 master에 애초에 없었다(≠ L28).
4. **통합 수동법 재사용**: `verify-pack -v` → `cat-file -p` 는 history든 branch든 동일하게 통한다.
5. **`8b137891` = 개행(`\n`) blob**(1바이트), 빈 blob `e69de29`(0바이트)와 구분.

### Quiz

**Q**: (a) `cat README.md`엔 placeholder뿐인데 dev의 진짜 password가 로컬에서 캐지는 이유는? "체크아웃"으로 설명하면 왜 틀리나? (b) 순수 `git branch`로는 왜 dev가 안 보이고, 무엇을 바꿔야 하나? (c) master의 `<no passwords in production!>`는 git이 비밀을 가린 흔적인가?

> [!tip]- 풀이
> **(a)** clone이 원격의 모든 head를 `refs/remotes/origin/*`(remote-tracking ref)로 받아오고 pack에 그 도달 객체를 전부 담았기 때문. 그래서 `origin/dev`의 blob이 로컬에 존재해 `git show origin/dev:README.md` 또는 `cat-file`로 읽힌다. "체크아웃"으로 설명하면 틀림 — clone은 **master만** 체크아웃하고 dev는 작업트리에 없다. 존재는 **reachability**의 결과지 체크아웃의 결과가 아니다.
>
> **(b)** 순수 `git branch`는 **로컬 branch만**(=master) 보여주는 표시 필터. `dev`는 remote-tracking ref라 `git branch -a`(로컬+원격) 또는 `-r`(원격만)로 켜야 보인다. 가시성은 존재와 직교.
>
> **(c)** 아니다. git은 blob을 그대로 저장할 뿐 자동 redaction이 없다. 그 문자열은 **저자가 master에 직접 커밋한 placeholder**이고, 진짜 값은 처음부터 dev에만 있었다(L28처럼 "커밋 후 삭제"된 게 아님).
>
> 핵심: **모든 branch를 clone이 pack에 담지만 하나만 체크아웃**한다 — 존재는 reachability, 가시성은 플래그.

> [!flashcard]
> **Q**: master README가 placeholder인데 진짜 password가 다른 branch에 있을 때 캐는 두 경로는?
> **A**: (정공) `git branch -a`로 `remotes/origin/dev` 발견 → `git show origin/dev:README.md`(또는 `git log --all -p`, `git checkout dev`). (수동) `git verify-pack -v` → `git cat-file -p <branch blob>`. 둘 다 clone이 remote-tracking ref로 dev 객체를 pack에 담았기에 가능.

> [!flashcard]
> **Q**: `git clone` 후 dev branch 객체가 로컬에 있는 진짜 이유는? (체크아웃 아님)
> **A**: clone이 원격 head를 `refs/remotes/origin/*`로 받아오고 pack에 그 도달 객체를 전부 담기 때문. 작업트리엔 master만 체크아웃되지만, dev blob은 `origin/dev`로 도달가능해 존재·덤프 가능.

---

## Links

### Tools Used
- [[Tools/git]] (`clone`, `verify-pack -v`, `cat-file -p`, `branch -a/-r`, `show <rev>:<path>`, `log --all -p`, `checkout`)
- [[Tools/cat]] / [[Tools/tree]] / [[Tools/ls]]

### Concepts Introduced (first encountered here)
- (없음 — L28의 [[Concepts/Linux/Git_Object_Model]] 재적용; branch/remote-tracking ref 측면 추가)

### Concepts Applied (reused from earlier)
- [[Concepts/Linux/Git_Object_Model]] (L28 — object model·`verify-pack`/`cat-file`; 여기선 branch reachability)
- [[Concepts/Network/Git_Over_SSH]] (L27 — clone over ssh:2220)

### Navigation
- **Prerequisite**: [[Level_28]] (object model + 통합 수동법)
- **Next**: [[Level_30]] (같은 model, 비밀이 **tag**에)
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit30.html
- `git-branch(1)` (`-a/--all`, `-r/--remotes`), `git-show(1)` (`<rev>:<path>`), `git-log(1)` (`--all`, `-p`), `git-clone(1)` (remote-tracking refs)
- `gitrevisions(7)` — `origin/dev`, `<rev>:<path>` selectors
