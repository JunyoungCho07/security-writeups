---
date: 2026-05-28
domain: Linux
topic: Subshell
tags: [linux, shell, process, fork, isolation]
status: 🟡 developing
mastery: 40
first_encountered: (chat-session 2026-05-28)
reapplied_in: []
last_reviewed: 2026-05-28
---

# Subshell

## Core Idea (1-2 sentences, KR)

Subshell = parent shell이 `fork(2)`로 만든 **child shell process**. 환경을 상속받지만 **상태 변화는 parent로 propagate 안 됨** — process isolation의 직접 shell-level 적용.

---

## [Step 1] Concept Categorization

**Process-level isolation primitive** in Unix shells. Shell이 `fork()` system call로 만든 별도 process로 명령을 실행하는 mechanism. 명시적 invocation (`( ... )`) 또는 implicit invocation (`$()`, pipeline, `&`) 양쪽으로 발생.

DNA: **Unix process model + shell scoping**의 교집합. 변수 scoping이 lexical이 아닌 **process-bounded**라는 점에서 다른 언어와 근본적으로 다름.

## [Step 2] Definition

> [!definition] Subshell
> Subshell은 parent shell process가 `fork(2)` system call을 호출하여 생성한 child shell process이다. ∀ state mutation S in subshell (env var, cwd, function, shell option) : S ↛ parent. 즉 subshell 종료 시점에 S는 소멸한다. Child는 parent의 file descriptor table, environment, current directory를 **copy** (copy-on-write) 받지만, 이후 모든 mutation은 child의 process address space에 국한된다.
^definition

**내 언어로 (KR)**: parent shell이 자신의 분신을 만들어 일을 시키되, 분신이 일하는 동안 한 변화는 분신과 함께 사라진다. "임시 작업장 + 자동 청소" 원칙.

## [Step 3] Intuition

> [!tip] Intuition
> 본인 사무실(parent shell) 옆에 같은 세팅의 임시 컨테이너 사무실(child shell) 설치 → 거기서 서류 작업 → 컨테이너 통째로 철수. 컨테이너 안에서 한 일은 본관에 흔적 0. `cd /tmp`, `export X=1`, `set -e` 어떤 변화든 컨테이너 안에 갇힌다.
^intuition

## [Step 4] Theory

**Mechanism — `fork()` based isolation**:

```
parent_shell (PID 1000)
    │
    └── fork() ──> child_shell (PID 1001)
                       │
                       ├── parent의 env, FD, cwd 복사 (COW)
                       ├── parent의 PID 자체는 부모 그대로 ($$ 유지)
                       ├── 자신의 PID는 $BASHPID로 노출
                       ├── commands 실행
                       └── exit(N) → SIGCHLD를 parent에 전달
                                    → parent의 wait()이 N 수확
```

**왜 격리?** Unix kernel은 process가 다른 process의 address space를 직접 수정 못 하게 enforce. Child shell이 `cd`, `export`, `x=5`를 해도 그건 child의 process state만 변경 → parent의 PCB(process control block)는 무관.

**Copy-on-write 의미**: fork 시 즉시 1GB env를 복사하지 않음. Page table만 복사, write 발생 시점에 해당 page만 lazy copy. 그래서 fork 자체는 microsecond order로 빠름.

## [Step 5] When & Condition

Subshell이 **암묵적으로** 생성되는 5가지 케이스:

| Construct | Subshell 생성? | 비고 |
|---|---|---|
| `( cmd )` | ✓ explicit | 가장 명시적 |
| `$(cmd)` | ✓ command substitution | 출력을 capture |
| `` `cmd` `` | ✓ legacy backtick | `$()` 권장 |
| `cmd1 \| cmd2` | ✓ pipeline 양쪽 모두 (bash default) | `shopt -s lastpipe`로 우회 |
| `cmd &` | ✓ background | async + 격리 |
| `./script.sh` | ✓ separate shell process | exec하는 새 shell |
| **`{ cmd; }`** | ✗ **NOT subshell** | brace group: same shell |
| **`source script.sh`** / `. script.sh` | ✗ NOT subshell | 현재 shell에서 실행 |

조건: subshell 격리가 작동하려면 **`fork()` 후 child가 명령을 실행**해야 함. `exec` builtin이 호출되면 child가 다른 binary로 replace됨 → 더 이상 shell 아님.

## [Step 6] Limitation & Alternatives

### 한계
- **Variable 못 가져옴**: subshell에서 정의/변경한 변수는 parent에 없음. 우회: `$()`로 stdout capture, 또는 임시 파일 / named pipe / `coproc` 사용.
- **fork overhead**: tight loop에서 매번 subshell 생성하면 수십 μs × N번 누적. 큰 batch에서 10~100배 느려짐.
- **Signal handling 미묘**: subshell이 parent와 별도 process group일 수도 (`set -m` job control mode) — `Ctrl+C` 전파가 의도와 다를 수 있음.

### 우월한 대안
- **Brace group `{ }`**: 격리 불필요 시 fork 비용 zero. 단 trailing `;` + space 문법 주의.
- **Shell function**: 재사용 가능 + parameter 받기 가능. variable scope은 dynamic이지만 `local` 키워드로 격리 가능 (function-scoped).
- **`coproc`** (bash 4.0+): bidirectional pipe로 subshell 결과를 점진적으로 받기. fire-and-forget이 아니라 dialog 필요할 때.

## [Step 7] Duality & Null Space

**Dual concept**: **`source` / `.` 명령** — subshell의 정확한 반대. 현재 shell process 안에서 script를 evaluate하므로 모든 부작용이 parent에 영구 반영. Subshell은 **격리**, `source`는 **흡수**.

**Null space**: subshell 안에서 변경한 어떤 상태도 parent에서 관찰 불가능. 이는 "변경 사항을 외부로 내보내는 channel은 오직 stdout/stderr/exit-code/IPC 4개뿐"이라는 Unix process boundary의 직접 결과. → variable export조차 child→parent 방향은 불가능 (`export`는 parent→child만).

## [Step 8] Validation

**Limit Test**:
- subshell 없는 shell? → command substitution 불가, 임시 cd 후 자동 복귀 불가, pipeline 우측 격리 불가. **Shell programming 사실상 마비.**
- 모든 명령이 subshell? → 매 명령마다 fork = 미친 overhead. 또한 `cd` 같은 navigation도 효과 없음 (parent 안 바뀜) → shell 사용성 zero.

**Dimensional Check**:
- Subshell은 dimension = process count. `( ( ( cmd ) ) )` 3중 nested = 3개 child process. 각각 fork → 3 × fork cost.
- Memory dimension: COW 덕분에 dim ≈ O(modified pages) ≪ O(parent total memory).

**Control Knob**:
- **`$BASHPID` vs `$$`**: subshell 안에서 `$$`는 parent PID 유지, `$BASHPID`는 child PID. 두 변수 차이로 "지금 subshell 안인지" 판정 가능. 이걸 모르면 디버깅 영원히 헤맴.
- `set -e` (errexit)의 subshell 적용 범위: bash 버전마다 미묘. defensive하게 subshell 내부에 `set -e` 재선언.

## [Step 9] Advanced Perspective

**Process group + session 측면**:

Subshell은 default로 parent와 **같은 process group** + **같은 controlling terminal** 공유. 그러나 `set -m` (monitor / job control) 활성 시 background subshell은 새 process group leader가 됨 → `Ctrl+C`가 foreground process group에만 전달, background subshell은 영향 안 받음.

**`exec` builtin in subshell**: `( exec ls )` vs `( ls )`:
- `( ls )` — child shell이 fork 후 `ls`를 추가 fork+exec. 총 2개 child process 생성 (subshell + ls).
- `( exec ls )` — child shell이 자신을 `ls`로 replace. fork 1개로 끝. 미세 최적화.

**Subshell이 inheritance하지 못하는 것**:
- Trap handler (default reset됨, `trap '...' EXIT`로 명시 재정의 가능)
- Aliases (interactive shell에서만, non-interactive bash는 alias 안 받음)
- Shell history list

## [Step 10] Link to Upper Concepts

- **Process model in OS** (general): subshell은 `fork()` + `wait()` 패턴의 가장 단순한 사례. `/var/folders/.../JY_KAIST/CS_OS` 외부 노트 (External: `JY_KAIST/02_Concepts/CS/Process_Lifecycle`)
- **Lexical scoping vs dynamic scoping**: 대부분 언어는 lexical, shell은 dynamic + process-bounded. Subshell이 dynamic scoping의 "boundary" 역할.
- **Capability-based security**: subshell의 격리는 mandatory access control의 약한 형태. 더 강력한 격리는 namespace (`unshare`), cgroup, container (Docker).

## [Step 11] Generalization

Subshell을 n차원으로 일반화:

1. **Same machine, same user**: subshell (`fork`).
2. **Same machine, different user**: `sudo -u user cmd` — UID 격리 추가.
3. **Same kernel, isolated namespace**: `unshare`, container (Linux namespaces: PID, mount, network, user, IPC, UTS, cgroup).
4. **Different VM**: hypervisor-level isolation.
5. **Different machine**: SSH session, RPC.

각 단계는 isolation boundary가 점점 강해짐. Subshell은 가장 weak (memory 격리만, kernel 공유). 그러나 가장 **저비용** (μs 단위 fork).

Pattern: "**state mutation을 외부 영향 없이 시도**" = isolation primitive. 모든 isolation은 동일한 root pattern의 다른 강도.

## [Step 12] Confer (Comparison)

- **vs. Brace Group `{ }`**: 둘 다 명령 grouping. 그러나 `{ }`는 same shell → cd, export 모두 parent에 반영. Subshell은 격리. 격리 필요 = `( )`, grouping만 = `{ }`. 잘못 고르면 silent bug.

- **vs. `source` / `.`**: 정반대. Source는 현재 shell이 script를 line-by-line 실행 → 모든 부작용 inherit. Subshell은 별도 process. 단 source는 fork 비용 0.

- **vs. Function (`func() { ... }`)**: function은 same shell에서 실행 (subshell 아님). `local` 키워드로 변수 scoping 가능. function 호출 비용 ≪ subshell.

- **vs. Background job (`cmd &`)**: `&` 자체가 subshell 생성. 차이: `&`는 async (parent가 wait 안 함), 보통 subshell은 sync.

- **vs. `nohup` / `disown` / `setsid`**: 모두 subshell + process group/session 조작. 더 강한 detach.

## [Step 13] Implication

1. **Shell programming의 가장 흔한 silent bug**의 원천. `while read line | ...` pattern에서 변수가 안 보존되는 이유 = 우측이 subshell이라.
2. **Idempotent script** 작성의 기반. 임시 cd, env 변경을 `( ... )`로 감싸면 cleanup 자동.
3. **Container 사상의 mini-prototype**: "변경 사항을 외부에 영향 안 주고 시도" → Docker의 정신적 조상.
4. **Security boundary로는 부족**: subshell은 격리지만 kernel 공유, file system 공유, network 공유. 진짜 격리 필요하면 namespace + cgroup.

## [Step 14] Application

**보안**:
- Subshell 안에서 untrusted 환경 변수 처리 → parent의 PATH/IFS/LD_PRELOAD 오염 방지.
- 임시 `umask` 변경: `( umask 077; touch secret )` — secret 파일은 600 권한, parent의 umask는 그대로.
- CTF/wargame에서 격리된 env로 sandbox 시도 (단, escape 가능).

**일반 scripting**:
- 임시 cd: `( cd /tmp && make )` — 항상 자동 복귀.
- 다중 redirect: `( echo h; cmd; echo f ) > out.txt` — 여러 명령 출력 한 파일로.
- variable scoping: `( unset HOME; some_cmd )` — `HOME`을 잠시 없애고 명령 실행.
- 병렬 처리 prototype: `( task1 ) & ( task2 ) & wait` — 2개 task 병렬.

**Bandit 맥락**:
- SSH 세션 안에서 `( cd inhere && find . -size 1033c )` — 작업 후 자동으로 home으로 돌아옴. cwd 추적 부담 zero.

## [Step 15] Background Knowledge

- **`fork()`**: 1969년 Ken Thompson의 Unix V1에 도입. 당시 Multics의 process 생성은 별도 binary load + 명시적 IPC였음. fork()는 "기존 process의 정확한 복사"라는 단순화로 패러다임 전환.
- **Bourne shell (1977)**: Stephen Bourne이 작성. `( )` subshell, `$()` (당시는 backtick만) 도입. 이후 모든 POSIX shell의 표준.
- **Plan 9의 비판**: Rob Pike는 fork()의 over-generality를 비판. Plan 9의 `rfork()`는 어떤 자원을 공유/격리할지 명시적 선택. Linux의 namespace + `clone()`이 이 영향.
- **Erlang/Elixir의 actor model**: subshell처럼 격리된 process 모델을 언어 level로 확장. 다만 message passing이 명시적 channel을 통과 (subshell의 stdout/exit-code의 풍부한 일반화).

---

## Formal Summary (EN)

> [!theorem] Subshell Isolation Property
> Let P be a parent shell process and S a subshell spawned by P via `fork()`. Let σ_P, σ_S denote their respective shell-state mappings (variables, cwd, options, traps). After S terminates with exit code N: σ_P' = σ_P (state preserved). The only information transmitted from S to P is the exit code N (and side effects on shared resources: filesystem, IPC). All mutations to σ_S are unobservable from P.

> [!proof] Sketch
> By `fork(2)` semantics, S receives a COW copy of P's address space. The kernel enforces process address-space separation: writes to S's memory pages trigger COW page allocation, leaving P's pages unmodified. ⟹ shell state stored in S's memory is invisible to P. The only kernel-supported parent↔child channel is the wait status (exit code + signal info), retrieved via `wait(2)`/`waitpid(2)`. ⟹ no other information leakage absent shared resource side effects. ∎

---

## Cross-References

### Encountered In
- (chat-session 2026-05-28) — first conceptual exposition
- Re-applications expected: Bandit Level 6+ (when `( cmd; cmd )` grouping enters scripts)

### Tools That Implement This
- [[Tools/find]] — `-exec ... \;` 실행 시 subshell-like fork per result. `-exec ... +`는 batching.

### Related Concepts
- [[Concepts/Linux/Exit_Code]] (Related — subshell이 외부로 내보내는 유일한 채널 중 하나)
- [[Concepts/Linux/Shell_Quoting]] (Related — `$()` 안에서의 quoting rule)
- [[Concepts/Linux/Stderr_Redirection]] (Related — subshell이 own FD table 보유, redirection 효과 격리)

### Cross-Domain
- External: JY_KAIST/02_Concepts/CS/Process_Lifecycle (OS-level fork/exec mechanics)
- External: JY_KAIST/02_Concepts/CS/Address_Space_Isolation (memory isolation 일반론)

---

## Quiz

**Q1** (Graduate-level): 다음 코드에서 `count`의 최종 값을 예측하고, 그렇게 되는 이유를 **process model 관점**에서 정확히 설명하라.

```bash
count=0
seq 1 5 | while read n; do
  count=$((count + 1))
done
echo "count=$count"
```

또한 (a) bash 4.2+에서 `shopt -s lastpipe` 활성화 시 동작, (b) zsh에서 동일 코드의 동작 차이를 설명하라. (힌트: 각 shell의 pipeline 우측 subshell 정책)

> [!tip]- 풀이
> **출력**: `count=0`
>
> **이유**: bash default에서 pipeline `|`의 양쪽 모두 subshell. `while read n; do count=$((count+1)); done`은 subshell A에서 실행 → `count`는 subshell A의 process state. A 종료 시 변수 소멸. parent의 `count`는 0 그대로.
>
> Process model: parent → fork(A) → A 안에서 count=1,2,3,4,5 → A `exit(0)` → SIGCHLD → parent의 `count`는 fork 시점 값(0) 유지.
>
> (a) `shopt -s lastpipe` (bash 4.2+, non-interactive 또는 job control off): pipeline 마지막 stage가 **parent에서 실행** → `count=5` 출력.
>
> (b) **zsh**: default로 lastpipe 동작 = `count=5` 출력. zsh는 pipeline 마지막 stage를 parent에서 돌림. → 같은 코드가 shell마다 다른 결과를 내는 portability hell.
>
> 핵심: **pipeline 우측 = subshell**이라는 default 정책 + 각 shell의 customization. `while ... done < <(seq 1 5)` (process substitution) 또는 `< file`로 직접 redirect하면 subshell 없이 동작.

---

> [!flashcard]
> **Q**: `( cd /tmp; pwd )` 후 parent shell의 `pwd`는?
> **A**: 원래 디렉토리. subshell 안의 `cd`는 subshell 종료 시 소멸 → parent의 `$PWD`는 fork 이전 값 그대로. 이것이 subshell isolation의 핵심 예.

> [!flashcard]
> **Q**: `$$`와 `$BASHPID`의 차이는?
> **A**: `$$` = parent shell의 PID (subshell 안에서도 부모 값 유지). `$BASHPID` = 현재 process의 실제 PID (subshell이면 child의 PID). `( echo "$$ vs $BASHPID" )`로 다른 값 확인 가능. POSIX 표준은 `$$`만 보장 (`$BASHPID`는 bash extension).

> [!flashcard]
> **Q**: subshell `( )`와 brace group `{ }`의 가장 큰 차이를 한 줄로?
> **A**: `( )` = `fork()` 후 격리 (상태 변화 parent에 반영 안 됨), `{ }` = same shell에서 단순 grouping (cd/export가 parent에 반영). 격리 필요 = `( )`, 비용 절감 = `{ }`.
