---
date: 2026-07-23
domain: Linux
topic: Git_Server_Side_Hooks
tags: [linux, git, git-push, pre-receive, receive-pack, quarantine, gatekeeping]
status: 🟡 developing
note_tier: lite
mastery: 40
first_encountered: [[Wargames/Bandit/Level_31]]
reapplied_in: []
---

# Git Server-Side Hooks

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> Bandit L31(31→32) push 레벨에서 판 개념. "이긴 push도 rejected로 끝난다"의 정체 = pre-receive가 password 출력 후 거부. `/deep` 시 hook 전체 taxonomy, quarantine 내부, push option, protocol까지.

## Definition (Formal, EN)

On `git push`, the client's send-pack talks to the server's **`git-receive-pack`**, which unpacks objects into a **quarantine** dir (`GIT_QUARANTINE_PATH`) and runs the **`pre-receive`** hook **once per push** — reading `<old> <new> <refname>` per ref on **stdin**, *after* objects are received but *before* any ref updates. A **non-zero exit rejects the entire push atomically** (no ref moves, quarantined objects discarded); the hook's stdout/stderr are relayed to the client as `remote:` lines regardless of exit.

## Intuition (KR)

서버 문지기(pre-receive)가 짐(objects)을 **격리 창고**에 받아 검사한다. 통과 못 하면 **선반(ref)에 안 올리고 창고째 버린다**. 검사 결과(=password)를 문틈으로 알려주고도 문은 안 열 수 있다 → "password 받았는데 rejected".

## Key Points (무엇을 팠나)

### A. pre-receive 게이트 역학
- **push당 1회**(≠ ref당 1회, 그건 `update` hook), stdin으로 ref 목록. non-zero면 **전체** 거부.
- **수락/거부는 오직 hook의 exit code.** `git push --force`·pull·merge는 fast-forward 검사만 건드림 → 게이트 못 뚫음.
- stdout·stderr **둘 다** `remote:`로 중계 → 이긴 push도 `! [remote rejected] ... (pre-receive hook declined)`로 끝, password는 그 **위** `remote:` 줄.

### B. quarantine, not rollback
- 거부 시 **ref가 애초에 안 움직임** + 격리 객체 폐기 → golden repo **불변**(다음 플레이어도 동일 초기상태). "커밋 후 롤백"이 아니다.

### C. hook taxonomy
- **서버**: pre-receive(push당1회·게이트) · update(ref당1회) · post-receive(성공 후). **클라이언트**: pre-commit·commit-msg(commit 시).
- clone의 `.git/hooks/*.sample`은 **실행 안 되는 템플릿**. 서버 실hook은 클라에 **전송 안 됨** → 열어봐야 red herring.

### D. 부수 (L31 solve)
- `.gitignore`의 `*.txt`가 `git add key.txt`를 막음(무시 안내+exit 1) → `git add -f`(최초 1회, untracked만 관장). clean clone에선 3줄이면 끝: `add -f` → `commit -m <비지않음>` → `push`. 삽질(fetch/pull/merge/switch/reset)은 게이트와 무관.

## Encountered / Applied In
- [[Wargames/Bandit/Level_31]] — key.txt push; pre-receive가 password 출력 후 거부. [[Git_Over_SSH]] write 방향, [[Git_Object_Model]] 객체 전송.

## Expand Later (`/deep` candidates)
- **`/deep Git_Hooks`** — 15종 hook 전체 lifecycle, 인자/stdin 계약, sample→active 활성화, push options(`GIT_PUSH_OPTION_*`).
- **`/deep Git_Quarantine`** — `tmp_objdir` 내부, migrate-on-accept, alternates.
