---
date: 2026-07-23
domain: Linux
topic: Git_Object_Model
tags: [linux, git, version-control, content-addressable, packfile, delta, reachability]
status: 🟡 developing
note_tier: lite
mastery: 42
first_encountered: [[Wargames/Bandit/Level_28]]
reapplied_in: [[[Wargames/Bandit/Level_29]], [[Wargames/Bandit/Level_30]], [[Wargames/Bandit/Level_31]]]
---

# Git Object Model

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> Bandit L28~30(history/branch/tag)을 **하나의 수동 방법론**(`verify-pack`+`cat-file`)으로 풀며 판 개념. `/deep` 시 pack 포맷 바이너리 레이아웃, delta 인코딩, gc/reflog까지.

## Definition (Formal, EN)

Git is a **content-addressable object store** with four object types — **blob**(file bytes), **tree**(directory listing), **commit**(one tree + parents + meta), **tag**(annotated). Object id = `SHA-1("<type> <size>\0<content>")`, so identical content dedups and a blob persists as long as **any ref** reaches it. DAG: `commit → tree → blob`.

## Intuition (KR)

git은 커밋마다 파일을 **통째 스냅샷(blob)**으로 찍어 내용 해시로 주소를 매긴다. "지움"은 삭제가 아니라 **새 버전 덧대기** — 도달 경로(ref)만 있으면 옛 객체는 산다.

## Key Points (무엇을 팠나)

### A. 통합 수동 방법론 (L28~30 공통 만능키)
- `git verify-pack -v <pack>.idx` → pack 안 **모든 객체** 열거(sha/type/size/[depth+base]) + 무결성 검증. `git cat-file -p <sha>` → **임의 객체** 덤프(delta도 투명 재구성), `-t`=타입, `-s`=실제크기.
- 이게 history(L28)/branch(L29)/tag(L30)를 몰라도 통하는 이유: **full clone은 모든 advertised ref**(브랜치+태그)에서 도달가능한 객체를 한 packfile에 담는다.

### B. reachability가 로컬 존재를 결정 (checkout 아님)
- L29: master는 placeholder여도 `dev` blob이 로컬 pack에 있음 → `refs/remotes/origin/dev` + pack reachability(체크아웃 아님). `git branch`(플래그 없음)는 로컬만 → `-a`/`-r` 필요.
- L30: password blob이 **커밋 트리에 없고** lightweight tag가 **직접** 가리킴 → `git log`/`show HEAD` 무력, `git show secret`만. `git fsck`는 tag 살아있으면 dangling 신고 안 함.

### C. whole vs delta / size 함정
- packer는 유사 blob 중 **가장 큰 것**을 whole base로, 짧은 것들을 delta로. → **최신/HEAD가 whole 아님**(L28: 옛 password blob이 base).
- `verify-pack`의 size 컬럼: whole行=실제크기, **delta行=delta payload 크기**(파일 길이 아님) → 실제는 `cat-file -s`.

### D. 보안 함의
- content-addressable history는 커밋된 비밀을 **redaction 커밋 후에도** 보관 → `git log -p`/`show`/reflog로 복원. 진짜 제거 = history 재작성(`filter-repo`/BFG) + force-push + **rotation**.

## Encountered / Applied In
- [[Wargames/Bandit/Level_28]] — history(옛 커밋 blob) 복원.
- [[Wargames/Bandit/Level_29]] — branch(remote-tracking ref) reachability.
- [[Wargames/Bandit/Level_30]] — lightweight tag → 커밋 DAG 밖 blob.
- [[Wargames/Bandit/Level_31]] — push가 보내는 객체(commit+tree+blob)로 재적용; [[Git_Server_Side_Hooks]].

## Expand Later (`/deep` candidates)
- **`/deep Git_Packfile`** — .idx/.pack/.rev 바이너리 레이아웃, delta chain, bitmap, `Total N (delta M)`/`reused`/`pack-reused` 카운터.
- **`/deep Git_Refs`** — refs/heads·remotes·tags, packed-refs, reflog, gc reachability.
