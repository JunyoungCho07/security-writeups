---
date: 2026-07-20
wargame: Bandit
level: 28
title: "Bandit Level 28 → 29"
difficulty: ★★☆
time_spent: 12min
tags: [bandit, linux, git, git-history, version-control, object-model, verify-pack, cat-file, secrets-in-vcs]
status: 🟡 developing
tools_used: [git, cat, tree, ls]
new_concepts: [Git_Object_Model]
prerequisites: [Level_27]
---

# Bandit Level 28 → 29

## [Phase 1] Executive Summary

- **Goal**: `bandit28-git` repo를 clone하면 현재 `README.md`의 password 필드가 **`xxxxxxxxxx`로 가려져** 있다. 진짜 bandit29 password는 **git history**(이전 커밋의 blob)에 그대로 남아 있으니 이를 복원한다. (L27이 "git repo에서 clone"이었다면, 여기부턴 "git **내부 구조**에서 캐낸다".)
- **Key Skill**: git **object model** 이해 + **history 복원**. 정공법은 `git log -p` / `git show <commit>:README.md`. 이번 세션은 **통합 수동법** — `git verify-pack -v`(pack 안 **모든 객체** 열거) → `git cat-file -p <blob>`(임의 blob 덤프)로 캤다. 이 수동법이 L28/29/30 **셋 다** 통하는 이유: clone이 **모든 advertised ref**(모든 branch + 기본적으로 모든 tag)에서 도달가능한 객체를 **한 packfile**에 담기 때문.
- **Tags**: `[Git_Object_Model]`(new), `[Git_Over_SSH]`(L27 reapply — clone over ssh:2220), `[Secrets_In_VCS]`

[Cognitive Validation]
- **Limit Test**: **shallow clone**(`git clone --depth 1`)이면 'add missing data' 커밋의 옛 blob이 **안 딸려와** history 복원이 불가능해진다. 전량 history clone일 때만 옛 blob이 로컬 pack에 존재. 지배 조건은 **clone의 history 깊이**.
- **Control Knob**: **reachability**(어느 ref/commit에서 도달가능한가). password blob은 HEAD tree엔 없지만 **HEAD~1에서 도달가능** → full clone에 포함. "체크아웃 여부"가 아니라 "도달가능 여부"가 로컬 존재를 결정.
- **Nullity**: `cat README.md`(작업트리)만 보면 영원히 `xxxxxxxxxx`. 비밀은 **체크아웃된 상태**가 아니라 **pack 안의 객체**에 있다 — git을 "파일 시스템"이 아니라 "객체 저장소"로 봐야 보인다.

---

## [Phase 2] Deep Dive

### 1. Concept Categorization

**Git object model + history recovery.** git은 파일을 커밋마다 **통째 스냅샷(blob)**으로 저장하고, 내용의 해시로 주소를 매기는 **content-addressable** 저장소다. 나중에 password를 지운 커밋을 얹어도 **옛 blob은 삭제되지 않는다** — "지움"이 아니라 "새 버전을 덧댐". 이 레벨(28)은 그 옛 blob을 꺼내는 **history 복원**이고, 이어지는 L29(branch)·L30(tag)은 같은 object model 위에서 **비밀이 놓인 ref만** 달라진다. 그래서 여기서 object model과 `verify-pack`+`cat-file` 방법론을 **깊게** 세워 두면 다음 둘은 twist만 본다.

### 2. Definition (Formal, EN)

Git stores four **object types**: **blob** (file bytes), **tree** (a directory listing of `mode blob/tree <sha>\tname`), **commit** (points to one tree + parent(s) + metadata), and **tag** (annotated only). Each object's identity is `SHA-1("<type> <size>\0<content>")` — **content-addressable**, so identical content deduplicates and a blob persists as long as *any* ref reaches it. The DAG is `commit → tree → blob`. A `git clone` transfers a **packfile** containing every object reachable from all advertised refs. `git verify-pack -v <pack>.idx` enumerates every packed object (type, size, delta chain, base); `git cat-file -p <sha>` reconstructs and pretty-prints **any** object — deltas transparently inflated — with **no checkout required**. Here the HEAD tree references the *placeholder* README blob, while the real bandit29 password lives only in the blob committed at `HEAD~1`.

### 3. Intuition (KR)

git은 매 커밋을 **폴라로이드 한 장(blob)**으로 찍어 서랍(pack)에 쌓는다. password를 가린 새 사진을 위에 얹어도 **밑장은 그대로 남는다**. 서랍을 통째로 복사(clone)해 왔으니, 목록을 뽑아(`verify-pack`) 옛 사진을 꺼내면(`cat-file`) 가려지기 전 원본이 나온다. "지웠다"는 건 착각 — git에서 지움은 **덧댐**일 뿐, 도달 경로(ref)만 있으면 옛 객체는 살아 있다.

### 4. Theory (Mechanism)

1. **clone** → `Total 9 (delta 2)`. 9 objects = **3 commits + 3 trees + 3 blobs**. 세 커밋의 서사:
   - (1) `initial commit of README.md`
   - (2) `add missing data` — **진짜 password를 삽입**
   - (3) `fix info leak` = **HEAD** — password를 `xxxxxxxxxx`로 **가림**
   각 커밋이 서로 다른 README 스냅샷 → 각자 tree·blob을 가짐(그래서 3·3·3).
2. **현재 vs 과거 blob**: `git cat-file -p <HEAD tree e275285b>` → `100644 blob 5c6457b1 README.md`(placeholder). 진짜 password는 **blob 42331d94**(=`add missing data` 커밋의 README).
3. **수동 복원**: `git verify-pack -v …idx`로 9개 객체 열거 → `git cat-file -p 42331d94` → 가려지기 전 README(진짜 bandit29 password).
4. **whole vs delta 뉘앙스(중요)**: `42331d94`는 **non-delta(whole)**, `5c6457b1`·`7ba2d2f7`은 **delta**. 이유는 **크기**다 — git의 packer는 유사 blob 중 **가장 큰 것을 base(whole)**로 두고 짧은 것들을 그 위에 delta로 얹는다. 진짜 password(32자 토큰)가 placeholder(`xxxxxxxxxx`, 10자)보다 길어 **옛 blob이 base**가 된 것. 즉 **"최신/HEAD가 whole"이 아니다**(recency 무관, 크기 기준).
5. **size 컬럼 함정**: `verify-pack -v`의 size 컬럼은 **whole 行=실제 객체 크기**, **delta 行=delta payload 크기**(파일 길이 아님). 그래서 `5c6457b1 (18)`·`7ba2d2f7 (12)`은 README 길이가 **아니다**(placeholder README도 실제론 133바이트 언저리, 32자 필드만 짧게 교체됐을 뿐). 진짜 파일 크기는 `git cat-file -s <sha>`.
6. **정합성**: `(delta 2)` = deltafied 객체 2개(두 placeholder README) = 요약행 `non delta: 7 objects` + `chain length = 1/2`.

인과: 비밀이 커밋됨(B) → 이후 커밋이 가림(C, 하지만 옛 blob 존속) → full clone이 옛 blob까지 전송(D) → `verify-pack`+`cat-file`로 그 blob 덤프(E) → password 복원.

### 5. Solution

```bash
# 0) L27 방식으로 clone (포트는 URL authority에)
$ git clone ssh://bandit28-git@bandit.labs.overthewire.org:2220/home/bandit28-git/repo repo28
$ cd repo28

# 1) 작업트리는 가려진 상태만 보여줌
$ cat README.md
# ... password: xxxxxxxxxx        ← 저자가 나중 커밋에서 가린 placeholder

# 2) pack 안 모든 객체 열거  (-v = verbose: sha·type·size·packed-size·offset·[delta depth+base])
$ git verify-pack -v .git/objects/pack/pack-<hash>.idx
# 83d7740… commit … / 13bbc4d… commit … / f3334fb… commit …   ← 커밋 3
# e275285b… tree … / …                                        ← 트리 3
# 42331d94… blob   133 129 512                                ← whole(=base), 진짜 password
# 5c6457b1… blob    18  22 641 1 42331d94…                    ← delta(depth1) off 42331d94
# 7ba2d2f7… blob    12  22 759 2 5c6457b1…                    ← delta(depth2)
# non delta: 7 objects  /  chain length = 1: … / = 2: …

# 3) 임의 blob 덤프  (-p = pretty-print, 타입 자동감지; delta도 투명하게 재구성)
$ git cat-file -p 42331d94
# ... credentials ... password: <password masked>             ← Level 29 password

# ── 정리 ──
$ cd .. && rm -rf repo28        # -r 재귀 · -f 무확인 강제 → .git 트리째 삭제
```

> [!warning] Password Masking & git hashes
> bandit29 password는 `<password masked>`로. 커밋된 `repo28/README.md`엔 placeholder(`xxxxxxxxxx`)만 있어 안전하나, **덤프한 blob 내용**엔 실값이 있으니 노트엔 절대 미기재. (참고: 40-hex git object 해시는 secret이 아니지만, pre-commit 엔트로피 스캐너가 오탐할 수 있음 — false positive.)

### 6. Why It Works

`fix info leak` 커밋은 password를 **삭제한 게 아니라** README의 새 버전을 스냅샷했을 뿐이다. git은 content-addressable이라 옛 blob(`42331d94`)이 해시로 그대로 존속하고, **full clone**이 그 blob까지 packfile에 실어 온다. `verify-pack`은 pack 안 **모든** 객체를 열거하고, `cat-file`은 그중 아무 blob이나(=delta여도 투명 재구성) 덤프한다 — 그래서 작업트리가 가려져 있어도 옛 password가 복원된다. 핵심 등식: **git에서 "지움"은 도달 경로 제거가 아니라 새 커밋 덧대기**이므로, history가 살아 있는 한 비밀도 살아 있다.

### 7. Edge Cases / Limitation

- **shallow clone은 못 캔다**: `git clone --depth 1`은 HEAD 스냅샷만 받아 `add missing data` 커밋의 blob이 로컬에 없다 → 복원 불가. 반드시 full-history clone.
- **size 컬럼 ≠ 파일 길이**: delta 行의 size는 delta payload 바이트. 실제 길이는 `git cat-file -s`. "현재 README가 18바이트뿐"이라 말하면 오류.
- **delta 체인은 pack마다 다름**: `7ba2d2f7→5c6457b1→42331d94`(depth 2)는 **이 pack의 배치**일 뿐, 결정론적 법칙 아님(테스트에선 대개 depth 1만 생성). 서술은 "이 pack에선"으로.
- **whole=base는 크기 기준**: 가장 큰 유사 blob이 base. 최신/HEAD가 whole이라는 보장 없음(여기선 오히려 옛 blob이 base).
- **`verify-pack` 인자**: `.idx` 문서 표기지만 `.pack`·확장자 없는 `pack-<hash>`도 허용(git이 확장자 정규화). 세션에서 repo29/30에 **repo28의 pack 해시**를 쓴 실패는 확장자 문제가 아니라 **그 해시 파일이 없어서**(`fatal: Cannot open existing pack file …`). 또 `verify-pack`은 SHA 재계산으로 **무결성 검증**까지 수행(끝에 `pack … ok`).
- **`git diff HEAD~1` 함정**: 인자 1개면 `HEAD~1` **vs 작업트리**를 비교(HEAD 아님). 커밋-대-커밋은 `git diff HEAD~1 HEAD -- README.md`처럼 **두 rev** 명시.

---

## [Phase 3] Formal Summary (EN)

> [!definition] Git as a content-addressable object store
> A commit snapshots a whole tree; a tree lists blobs by SHA. Object id = `SHA-1("<type> <size>\0<content>")`, so a blob is immutable and unique to its bytes. A later "redaction" commit adds a *new* blob; the old one is not deleted. A full clone packs every object reachable from all advertised refs, so historical blobs are present locally. `git verify-pack -v` lists them; `git cat-file -p <sha>` reconstructs any (delta transparently inflated) with no checkout.

> [!theorem] Reachability, not checkout, determines local presence — and history retains secrets
> A blob B is in the local pack **iff** B is reachable from some advertised ref at clone time (⇐ full clone). The working tree showing a redacted value does not remove B: `fix info leak` merely re-points HEAD's tree to a placeholder blob while B stays reachable via `HEAD~1`. ∴ any committed secret survives redaction and is recoverable until an unreachability-based `gc` following a **history rewrite** (`git filter-repo`/BFG) + force-push + credential rotation. □

---

## [Phase 4] Better Methods

**Current approach** (used above): 통합 수동법 `verify-pack -v` → `cat-file -p <blob>`. **storage-agnostic** — 어느 blob이 whole/delta인지, 비밀이 history/branch/tag 중 어디 숨었는지 **몰라도** 모든 blob을 훑어 캔다. 단 노이즈가 많다.

**Alternative 1** (이 레벨의 정공법 — history diff):
```bash
git log -p                      # -p/--patch: 커밋마다 diff 출력 → 'fix info leak'의 '-' 줄에 진짜 password
git show HEAD~1:README.md        # <rev>:<path> = 그 커밋 트리의 해당 blob 덤프 (HEAD~1 = 첫 부모 1세대 전)
git diff HEAD~1 HEAD -- README.md # 두 커밋 사이 README 변화; '-- <path>' = pathspec 제한
```
Trade-off: 어느 reachability(=history)인지 알면 가장 깔끔·의미론적. 단 "history에 있다"를 먼저 알아야 함.

**Most elegant**:
```bash
git log -p -- README.md         # README 변경 이력만, 삭제된 password가 diff의 '-' 줄에 바로 노출
```
Why elegant: 한 명령으로 "언제·무엇이 지워졌는가"가 diff로 드러난다 — history 복원의 정의 그 자체.

---

## [Phase 5] Lessons Learned

1. **git은 객체 저장소**: blob/tree/commit/tag, content-addressable. 파일이 아니라 **객체**로 봐야 비밀이 보인다.
2. **"지움"은 덧댐**: redaction 커밋은 옛 blob을 안 지운다. `git log -p`/`git show HEAD~1:README.md`로 복원. 진짜 제거는 filter-repo/BFG + force-push + **rotation**.
3. **통합 수동법**: `verify-pack -v`(모든 객체 열거) → `cat-file -p`(임의 blob 덤프, delta 투명 재구성). L28/29/30 공통 만능키.
4. **reachability가 로컬 존재를 결정**: full clone이 모든 ref 도달 객체를 pack에 담는다. shallow면 옛 blob 누락.
5. **verify-pack size ≠ 파일 길이**(delta 行은 payload 크기); **whole=base는 크기 기준**(최신 아님). 실크기는 `cat-file -s`.

### Quiz

**Q**: (a) `cat README.md`엔 `xxxxxxxxxx`뿐인데 진짜 password를 어떻게 복원했고, 그게 가능한 git의 근본 성질은? (b) `verify-pack -v`에서 어떤 blob의 size 컬럼이 `cat-file -s`보다 **작게** 나오는 이유는? (c) 왜 이 레벨에선 `git clone --depth 1`로 풀 수 없나?

> [!tip]- 풀이
> **(a)** 진짜 password는 `fix info leak` 이전 커밋(`HEAD~1`)의 blob에 남아 있고, full clone이 그 blob까지 pack에 실어 왔다. `git cat-file -p <그 blob>`(또는 `git show HEAD~1:README.md`)로 덤프. 근본 성질은 **content-addressability + reachability** — 커밋된 blob은 해시로 불변 존속하며, redaction 커밋은 그걸 삭제하는 게 아니라 새 blob을 덧댈 뿐.
>
> **(b)** 그 blob이 **delta로 저장**됐을 때. verify-pack의 size 컬럼은 delta 行에선 **delta payload(명령) 크기**를 보이고, `cat-file -s`는 **재구성된 전체 크기**를 보인다. 그래서 delta blob은 size < `cat-file -s`. whole 行에선 둘이 같다.
>
> **(c)** `--depth 1`은 HEAD 스냅샷만 받아 `add missing data` 커밋의 blob이 로컬에 없다. 비밀은 **과거 커밋**에 있으므로 전량 history가 필요.
>
> 핵심: git의 "삭제"는 도달경로 제거가 아니라 **덧대기**. history+reachability가 살아 있으면 비밀도 살아 있다.

> [!flashcard]
> **Q**: 현재 README가 `xxxxxxxxxx`로 가려진 git repo에서 진짜 password를 캐는 두 경로는?
> **A**: (정공) `git log -p` / `git show HEAD~1:README.md`로 삭제 이전 커밋의 blob을 본다. (수동 만능) `git verify-pack -v …idx`로 모든 객체 열거 → `git cat-file -p <blob>` 덤프. 둘 다 옛 blob이 clone된 pack에 존속하기에 가능.

> [!flashcard]
> **Q**: git에서 password를 커밋했다가 다음 커밋에서 지우면 안전한가?
> **A**: 아니다. content-addressable history가 옛 blob을 보관(`git log -p`/`git show`/reflog로 복원). 진짜 제거 = history 재작성(`git filter-repo`/BFG) + force-push + **credential rotation**.

> [!flashcard]
> **Q**: `git verify-pack -v`의 size 컬럼과 delta/whole 관계는?
> **A**: whole(non-delta) 行 size = 실제 객체 크기; delta 行 size = **delta payload 크기**(파일 길이 아님). depth+base-sha가 delta임을 표시. 실제 크기는 `git cat-file -s`. base는 유사 blob 중 **가장 큰 것**(최신 아님).

---

## Links

### Tools Used
- [[Tools/git]] (`clone`, `verify-pack -v`, `cat-file -p/-s/-t`, `log -p`, `show`)
- [[Tools/cat]] / [[Tools/tree]] / [[Tools/ls]] (repo·`.git` 구조 확인)

### Concepts Introduced (first encountered here)
- [[Concepts/Linux/Git_Object_Model]] (lite-note 후보 @EOL — blob/tree/commit/tag, content-addressable, pack/delta, reachability; L29·L30이 재적용)

### Concepts Applied (reused from earlier)
- [[Concepts/Network/Git_Over_SSH]] (L27 — clone over ssh:2220로 repo 확보)
- [[Concepts/Linux/Shell_Fundamentals]] (`<rev>:<path>` selector, `--` pathspec, quoting)

### Navigation
- **Prerequisite**: [[Level_27]] (git-over-SSH clone)
- **Next**: [[Level_29]] (같은 object model, 비밀이 **branch**에)
- **MOC**: [[_MOC/MOC_Bandit]]

### External References
- Bandit Official: https://overthewire.org/wargames/bandit/bandit29.html
- `gitrevisions(7)` (`HEAD~1`, `<rev>:<path>`), `git-cat-file(1)` (`-p/-t/-s`), `git-verify-pack(1)` (`-v`), `git-log(1)` (`-p`)
- Pro Git ch.10 "Git Internals" — objects, packfiles, delta; `git-filter-repo` / BFG (history rewrite remediation)
