---
date: 2026-07-20
wargame: Bandit
level: 30
title: "Bandit Level 30 → 31"
difficulty: ★★★
time_spent: 12min
tags: [bandit, linux, git, git-tag, lightweight-tag, version-control, object-model, verify-pack, cat-file, secrets-in-vcs]
status: 🟡 developing
tools_used: [git, cat, tree, ls]
new_concepts: []
prerequisites: [Level_29]
---

# Bandit Level 30 → 31

## [Phase 1] Executive Summary

- **Goal**: `bandit30-git` repo를 clone하면 `README.md`는 `just an epmty file... muahaha` — 커밋에도 branch에도 비밀이 없다. 진짜 bandit31 password는 **git tag `secret`이 직접 가리키는 blob**에 있다. 커밋 트리에서 **도달 불가**, 오직 tag를 통해서만 닿는다. (L28=history, L29=branch, **L30=tag** — 같은 object model, 세 번째 reachability 경로.)
- **Key Skill**: git **tag reachability** + **lightweight tag** 판별. 정공법은 `git tag`로 `secret` 발견 → `git show secret`. 이번 세션은 L28의 **통합 수동법** 재사용 — `git verify-pack -v`로 pack 내 전 객체 열거 → **커밋 트리에 없는 떠 있는 blob** `6a76bc87`을 `git cat-file -p`로 덤프.
- **Tags**: `[Git_Object_Model]`(L28 reapply), `[Git_Over_SSH]`(L27), `[Secrets_In_VCS]`

[Cognitive Validation]
- **Limit Test**: `git log -p`·`git show HEAD`·`git diff`·어느 branch로도 안 나온다 — commit DAG 어디에도 비밀이 없기 때문. 유일한 손잡이는 **tag ref**. (L28/L29와 결정적으로 다른 점.)
- **Control Knob**: **tag의 종류** — `secret`이 **lightweight**(blob 직결)면 pack에 tag object가 없어 `Total 4`(1 commit+1 tree+2 blob); **annotated**였다면 5번째 `tag` object가 생긴다. 객체 개수가 tag 종류를 폭로한다.
- **Nullity**: `git fsck`는 이 blob을 **dangling으로 신고하지 않는다** — tag ref가 뿌리로 잡아주기 때문. `git tag -d secret`로 tag를 지워야 비로소 `dangling blob`으로 뜬다. "commit DAG에선 떠 있지만 ref로는 도달가능"이 정확한 표현.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**Git tag reachability + lightweight vs annotated tag.** L28의 object model·방법론을 재사용하되, 비밀이 **커밋 트리에 없는 blob**에 있고 그 blob에 닿는 유일한 경로가 **tag**라는 점이 핵심. git tag는 두 종류: **lightweight**(단순 ref → 임의 객체 직결, 별도 object 없음)와 **annotated**(`tag` object를 하나 더 만들어 메시지·태거를 담음). 이 레벨의 `secret`은 **blob에 직결된 lightweight tag** — 그 증거가 바로 **4-object pack에 `tag` object가 없다**는 것. 커밋 트리(`bd85592e`)는 placeholder README(`029ba421`)만 가리키고, password blob(`6a76bc87`)은 그 트리에 **없다**.

### 2. Definition (Formal, EN)

A **lightweight tag** is a ref under `refs/tags/` pointing **directly** at any object (here a **blob**), with no separate tag object; an **annotated tag** additionally stores a `tag` object (message + tagger). For `secret` pointing at a blob: `git cat-file -t secret` → `blob`, `git rev-parse secret` → the blob SHA **without** `^{}` deref, and `git show secret` / `git cat-file -p secret` print the blob. A default `git clone` fetches **all tags** and packs each tag's **target object**, so a commit-unreachable, tag-only blob lands locally with no checkout. The blob is reachable **only via the tag ref**, not from the commit's tree — so `git log`/`git show HEAD`/`git diff` never reveal it, and `git fsck` reports it dangling **only after** the tag is deleted.

### 3. Intuition (KR)

커밋이라는 **앨범**엔 placeholder 사진 한 장뿐이다. 진짜 사진은 앨범에 안 붙어 있고, **`secret`이라는 포스트잇**이 서랍 속 낱장 사진(blob)에 직접 붙어 있다(=lightweight tag). clone은 포스트잇(tag)과 그게 가리키는 낱장까지 서랍(pack)에 담아 오므로, 포스트잇을 보거나(`git tag`) 서랍을 통째 훑으면(`verify-pack`) 그 낱장이 나온다. 앨범(커밋 history)을 아무리 뒤져도 안 나오는 이유는 사진이 **앨범 밖 포스트잇에만** 걸려 있어서다.

### 4. Theory (Mechanism)

1. **clone** → `Total 4 (delta 0)`. 4 objects = **1 commit + 1 tree + 2 blobs**. 작업트리 README = `just an epmty file... muahaha`.
2. **객체 walk**:
   - `git cat-file -p <commit 8f2cf5b7>` → `tree bd85592e`, author `Ben Dover`, msg `initial commit of README.md`.
   - `git cat-file -p <tree bd85592e>` → `100644 blob 029ba421 README.md` (placeholder 30바이트).
   - `git cat-file -p 029ba421` → `just an epmty file... muahaha`.
   - `git cat-file -p 6a76bc87` → **진짜 bandit31 password**(33바이트 = 32자 토큰 + 개행). 이 blob은 **커밋 트리에 없다**.
3. **오직 tag로만 도달**: `6a76bc87`은 어느 커밋 트리에도 없고, `refs/tags/secret`이 **직접** 가리킨다. 그래서 커밋/branch/history로는 절대 안 나온다.
4. **lightweight의 지문 — 4 vs 5**: `secret`이 lightweight라 pack에 **`tag` object가 없다** → `Total 4`. annotated였다면 `tag` object가 5번째로 생겨 `Total 5`, 그리고 `cat-file -t secret`=`tag`, `rev-parse secret`은 tag object SHA(→ blob엔 `secret^{}`로 peel). **객체 개수가 tag 종류를 폭로**한다(핵심 통찰).
5. **수동 복원**: `git verify-pack -v …idx`가 4객체를 열거하며 **트리에 안 걸린 낱장 blob** `6a76bc87`을 그대로 보여줌 → `git cat-file -p 6a76bc87`로 덤프. tag의 존재를 몰라도 캠(통합 수동법의 힘).
6. **"dangling" 정밀화**: tag가 있는 동안 `git fsck`는 **아무것도 dangling으로 신고하지 않는다**(tag ref가 뿌리). `git tag -d secret` 후에야 `dangling blob 6a76bc87`. 그러니 "clone하고 `git fsck` 돌리면 dangling blob이 나온다"는 **틀린 설명** — 정확히는 "**commit DAG에선 떠 있으나 tag ref로 도달가능**".

인과: 저자가 password blob을 만들고 `secret` lightweight tag로 직결(B) → clone이 모든 tag+대상 객체를 pack에 포함(C) → `git tag`/`git show secret` 또는 `verify-pack`+`cat-file`로 그 blob 덤프(D) → password 복원.

### 5. Solution

```bash
# 0) clone (L27 방식)
$ git clone ssh://bandit30-git@bandit.labs.overthewire.org:2220/home/bandit30-git/repo repo30
$ cd repo30

# 1) 작업트리/커밋엔 미끼뿐
$ cat README.md
just an epmty file... muahaha        # 커밋 트리의 placeholder blob(029ba421)

# 2) 통합 수동법: pack 내 전 객체 열거 → 트리에 없는 blob 덤프
$ git verify-pack -v .git/objects/pack/pack-<hash>.idx
# 8f2cf5b7… commit … / bd85592e… tree … / 029ba421… blob 30 … (README)
# 6a76bc87… blob 33 …                   ← 커밋 트리에 없는 '떠 있는' blob (tag가 가리킴)
# non delta: 4 objects                   ← tag object 없음 = lightweight tag의 지문

$ git cat-file -p 6a76bc87              # -p pretty-print → 진짜 password
# <password masked>                      ← Level 31 password

# ── 정리 ──
$ cd .. && rm -rf repo30
```

> [!warning] Password Masking
> bandit31 password는 `<password masked>`. `just an epmty file... muahaha`는 저자가 커밋한 미끼 README라 그대로 둬도 무방(비밀 아님). 덤프한 tag blob의 실값만 마스킹.

### 6. Why It Works

`secret`은 **blob에 직결된 lightweight tag**다. `git clone`은 기본적으로 **모든 tag를 받고 각 tag의 대상 객체를 pack에 포함**하므로, 커밋 트리에서 도달 불가한 password blob(`6a76bc87`)도 **로컬 pack에 들어온다**. 그래서 `git show secret`(정공)이나, tag를 몰라도 `verify-pack`이 열거한 **트리 밖 blob**을 `cat-file`로 덤프(수동)하면 비밀이 나온다. commit DAG를 아무리 뒤져도(`git log`) 안 나오는 이유는 blob이 **ref(tag)로만** 도달가능하기 때문. 핵심: **ref(branch·tag)에서 도달가능하면 pack에 오고 읽힌다 — 커밋 트리 소속 여부와 무관**.

### 7. Edge Cases / Limitation

- **`git log`/`show HEAD`/`diff`/branch 전부 무력**: 비밀이 commit DAG 밖(tag 직결 blob)이라 history 기반 접근은 안 통한다. L28(history)·L29(branch)와 결정적 차이.
- **lightweight tag는 커밋처럼 다루면 실패**: `git checkout secret`(`fatal: unable to read tree`), `git show secret:README.md`(`path … exists on disk, but not in secret`)는 **에러**. 반면 `git show secret`(경로 없이)는 **blob을 덤프**하고, `git log secret`은 **에러가 아니라 조용한 no-op**(exit 0, 빈 출력 — blob엔 순회할 커밋 이력이 없음). 경로 유무·명령별로 다르다.
- **lightweight vs annotated**: `secret`이 annotated였다면 pack에 `tag` object가 5번째로 생기고(`Total 5`), `cat-file -t secret`=`tag`, blob엔 `git rev-parse secret^{}`로 peel해야 닿는다. 여기선 `cat-file -t secret`=`blob`, `rev-parse secret`=blob SHA(peel 불필요). **`Total 4`가 lightweight의 증거**.
- **`git fsck` ≠ dangling(지금은)**: tag가 살아 있는 한 fsck는 조용하다. `git tag -d secret` 후에야 dangling. "commit DAG에선 떠 있지만 tag로 도달가능"이 정확.
- **blob 역할 혼동 금지**: 33바이트 `6a76bc87`(32자 password+개행) = 비밀; 30바이트 `029ba421`(`just an epmty file... muahaha`) = 커밋 트리의 placeholder README. 바꿔 읽지 말 것.
- **clone이 왜 가져오나**: `git clone`은 기본 **모든 tag** fetch(`--no-tags`면 제외). tag가 blob을 가리키니 그 blob이 pack에 실린다 — "HEAD/branch에서 도달불가라 안 온다"는 오해.

---

## [Phase 3] Formal Summary (EN)

> [!definition] Lightweight tag → blob reachability
> A lightweight tag is a `refs/tags/<name>` ref pointing directly at an object with no tag object. For `secret` → blob: `cat-file -t secret` = `blob`, `rev-parse secret` = blob SHA (no `^{}`), `git show secret` / `git cat-file -p secret` print it. A default clone fetches all tags and packs each tag's target, so a commit-unreachable, tag-only blob is present locally; the commit's tree never references it.

> [!theorem] The pack's object count discriminates lightweight from annotated
> A repo with one single-file commit and a secret hidden by a tag has |objects| = 1 commit + 1 tree + 1 README blob + 1 secret blob + (1 if the tag is **annotated** else 0). ∴ `Total 4` ⟺ lightweight (ref→blob, no tag object); `Total 5` ⟺ annotated (an extra `tag` object, and the blob is reached by `secret^{}`). The transferred object count is thus a decidable fingerprint of the tag's kind. □

---

## [Phase 4] Better Methods

**Current approach** (used above): 통합 수동법 `verify-pack -v` → 트리 밖 blob을 `cat-file -p 6a76bc87`. tag 개념을 몰라도 캠 (storage-/ref-agnostic).

**Alternative 1** (정공법 — tag 인지):
```bash
git tag                     # tag '목록' 출력 → 'secret' 발견  (주의: git tag <name> 은 tag를 '생성')
git show secret             # lightweight tag가 가리키는 blob 덤프 → password
git cat-file -p secret      # 동일 (blob 내용 pretty-print)
git rev-parse secret        # blob SHA 확인 (annotated였다면 secret^{} 로 peel 필요)
```
Trade-off: "tag에 있다"를 알면 가장 짧고 의미론적. `git tag` 한 줄로 손잡이가 드러난다.

**Most elegant**:
```bash
git show secret
```
Why elegant: tag 이름 하나로 커밋·트리·history를 우회해 목표 blob을 **직접** 연다.

---

## [Phase 5] Lessons Learned

1. **tag도 reachability 경로**: 비밀이 commit/branch가 아니라 **tag 직결 blob**에 있을 수 있다. `git tag` → `git show secret`.
2. **clone은 모든 tag+대상 객체를 pack에 담는다**: 그래서 커밋 트리 밖 blob도 로컬에서 읽힌다. history 접근(`git log`)은 안 통함.
3. **객체 개수 = tag 종류의 지문**: `Total 4`(tag object 없음)=lightweight; `Total 5`=annotated. lightweight면 `cat-file -t secret`=blob, `rev-parse secret`=blob SHA.
4. **"dangling" 정밀화**: tag가 있으면 `git fsck`는 조용. `git tag -d` 후에야 dangling. "commit DAG 밖·tag로 도달가능"이 정확한 표현.
5. **통합 수동법은 세 레벨 공통 만능키**: `verify-pack -v`(전 객체 열거) → `cat-file -p`. history(L28)/branch(L29)/tag(L30)를 몰라도 훑어서 캔다.

### Quiz

**Q**: (a) `git log -p`·`git show HEAD`로는 password가 안 나오는데 왜 `git show secret`으로는 나오나? (b) pack이 정확히 **4개** 객체(1 commit+1 tree+2 blob)라는 사실이 tag에 대해 무엇을 확정하며, annotated였다면 무엇이 달라지나? (c) clone 직후 `git fsck`를 돌리면 이 password blob이 dangling으로 뜨는가?

> [!tip]- 풀이
> **(a)** password blob(`6a76bc87`)은 **어느 커밋 트리에도 없다**. `git log`/`git show HEAD`/`git diff`는 **commit DAG**를 훑으므로 절대 못 닿는다. 반면 그 blob은 `refs/tags/secret`이 **직접** 가리키고, clone이 tag와 대상 객체를 pack에 담아 왔다. `git show secret`은 그 tag ref를 따라 **blob을 직접** 덤프한다.
>
> **(b)** `secret`이 **lightweight tag**(ref→blob 직결, 별도 tag object 없음)임을 확정한다 — tag object가 있었다면 5번째 객체로 잡혔을 것. annotated였다면 pack에 `tag` object가 추가돼 `Total 5`가 되고, `cat-file -t secret`=`tag`, blob엔 `git rev-parse secret^{}`로 **peel**해야 닿는다. 즉 **객체 개수(4 vs 5)가 tag 종류의 지문**.
>
> **(c)** 아니다. `secret` tag가 살아 있는 동안 `git fsck`는 그 blob을 **뿌리에서 도달가능**으로 보아 조용하다. `git tag -d secret`로 tag를 지운 **뒤에야** `dangling blob`으로 신고한다. 정확한 표현은 "commit DAG에선 떠 있으나 tag ref로 도달가능".
>
> 핵심: **ref(tag 포함)에서 도달가능하면 pack에 오고 읽힌다**. tag 종류는 pack의 객체 개수가 폭로한다.

> [!flashcard]
> **Q**: 커밋/branch엔 없고 tag가 가리키는 blob에 password가 있을 때 캐는 두 경로는?
> **A**: (정공) `git tag`로 `secret` 발견 → `git show secret` / `git cat-file -p secret`. (수동) `git verify-pack -v`로 **커밋 트리에 없는 떠 있는 blob** 열거 → `git cat-file -p <hash>`. 둘 다 clone이 tag+대상 객체를 pack에 담았기에 가능.

> [!flashcard]
> **Q**: lightweight tag와 annotated tag를 pack만 보고 구별하는 법은?
> **A**: pack에 **`tag` object가 있으면 annotated**(객체 1개 추가), 없으면 **lightweight**(ref→객체 직결). lightweight면 `git cat-file -t secret`=대상 타입(blob), `git rev-parse secret`=대상 SHA(peel 불필요); annotated면 `-t`=`tag`, blob엔 `secret^{}` peel 필요.

> [!flashcard]
> **Q**: tag가 가리키는 blob에 대해 `git checkout secret`·`git show secret:README.md`·`git log secret`·`git show secret`은 각각?
> **A**: `checkout secret`·`show secret:README.md` = **에러**(blob은 트리/커밋이 아님). `log secret` = **조용한 no-op**(exit 0, 커밋 이력 없음). `show secret`(경로 없이) = **blob 덤프**(성공). 경로 유무가 성패를 가른다.

---

## Links

### Tools Used
- [[Tools/git]] (`clone`, `verify-pack -v`, `cat-file -p/-t`, `tag`, `show`, `rev-parse`, `fsck`)
- [[Tools/cat]] / [[Tools/tree]] / [[Tools/ls]]

### Concepts Introduced (first encountered here)
- (없음 — L28의 [[Concepts/Linux/Git_Object_Model]] 재적용; tag/lightweight-annotated 측면 추가)

### Concepts Applied (reused from earlier)
- [[Concepts/Linux/Git_Object_Model]] (L28 — object model·`verify-pack`/`cat-file`; 여기선 tag reachability)
- [[Concepts/Network/Git_Over_SSH]] (L27 — clone over ssh:2220)

### Navigation
- **Prerequisite**: [[Level_29]] (branch reachability + 통합 수동법)
- **Next**: [[Level_31]] (git **push** — 이번엔 쓰기)
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit31.html
- `git-tag(1)` (lightweight vs annotated), `git-show(1)`, `git-cat-file(1)` (`-t/-p`), `git-rev-parse(1)` (`^{}` peel), `git-fsck(1)` (dangling)
- `gitglossary(7)` — "tag", "dangling object", "reachable"; `git-clone(1)` — default tag fetching
