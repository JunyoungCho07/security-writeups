---
date: 2026-05-28
domain: Linux
topic: Exit_Code
tags: [linux, shell, process, ipc, control-flow]
status: 🟡 developing
mastery: 45
first_encountered: (chat-session 2026-05-28)
reapplied_in:
  - [[Wargames/Bandit/Level_13]]
last_reviewed: 2026-06-24
---

# Exit Code

## Core Idea (1-2 sentences, KR)

Exit code = process가 종료될 때 kernel을 통해 parent에 전달하는 **8-bit unsigned integer** (0~255). Process 간 통신의 minimum viable signal — "성공/실패 + 실패 유형"을 한 byte로 압축한 process termination 메시지.

---

## [Step 1] Concept Categorization

**Inter-process communication primitive** at process termination. OS의 process lifecycle 중 마지막 단계에서 kernel이 child→parent로 전달하는 유일한 atomic value. Shell의 모든 conditional logic (if/while/&&/||)이 이 위에 build됨.

DNA: **OS process model + Unix convention + shell control flow**의 교차점. 8-bit 제약은 1979 Unix V7의 `wait()` status word layout에서 비롯된 historical artifact.

## [Step 2] Definition

> [!definition] Exit Code
> Process P가 `exit(N)` (또는 `_exit(N)`, `return N` from main) 호출 시, kernel은 `N mod 256` (8-bit unsigned)을 P의 PCB에 저장하고 parent에 SIGCHLD를 전달한다. Parent의 `wait(2)` 또는 `waitpid(2)` system call은 이 값을 status word로부터 추출 (macro `WEXITSTATUS`). Shell은 직전 명령의 exit code를 special variable `$?`로 노출한다. 관례 (POSIX, but program-specific):
>
> $$\text{exit\_code} = \begin{cases} 0 & \text{success} \\ 1\text{–}125 & \text{program-specific error} \\ 126 & \text{found but not executable} \\ 127 & \text{command not found} \\ 128+N & \text{terminated by signal } N \\ 255 & \text{out-of-range (wraparound)} \end{cases}$$
^definition

**내 언어로 (KR)**: process의 "유언" — 죽기 직전 한 byte로 "나 이렇게 죽었다"를 parent에게 알리는 최소 단위 신호.

## [Step 3] Intuition

> [!tip] Intuition
> 학생이 시험 끝나고 OMR 카드 마지막 칸에 한 숫자 적고 제출: 0(통과) / 1(실패) / 127(시험장 못 찾음) / 137(감독관이 강제퇴장). 채점자(parent)는 그 한 숫자만 보고 다음 행동 결정. 부가 정보는 stdout/stderr의 "답안 본문"에 있지만 핵심 평가는 한 byte로 환원.
^intuition

## [Step 4] Theory

**Kernel-level mechanism**:

```
process P
   │ exit(N) syscall
   ▼
kernel
   ├── PCB에 N 저장 (status word: lower 8 bits = exit code)
   ├── 모든 자원 해제 (file descriptor close, memory unmap)
   ├── process를 zombie 상태로 (wait() 호출까지 PCB 잔존)
   └── parent에 SIGCHLD 전달
         │
         ▼
       parent의 wait()/waitpid() 호출
         │
         ▼
       status word return (16 bits)
       │
       ├── WEXITSTATUS(s) = (s >> 8) & 0xFF   → exit code
       ├── WIFEXITED(s)   = (s & 0x7F) == 0  → 정상 종료 여부
       ├── WIFSIGNALED(s) = …                → signal-induced 여부
       └── WTERMSIG(s)    = s & 0x7F          → signal number
```

**Status word layout (16-bit)**:
```
 15        8 7  6 5         0
 ┌──────────┬──┬────────────┐
 │ exit code│CD│ signal num │
 └──────────┴──┴────────────┘
 (upper 8)  (core)  (lower 7)
```
- 상위 8-bit: 정상 종료 시 exit code.
- 하위 8-bit: signal-induced 시 signal number (+ core dump flag bit 7).

**Signal convention**: shell에선 signal로 죽으면 **`128 + signal_number`**로 노출. e.g., SIGINT(2)로 죽음 → `$?` = 130. SIGKILL(9) → 137. SIGSEGV(11) → 139. 이 convention은 **shell-level layer**이지 kernel이 직접 부과한 게 아님 — kernel은 status word를 그대로 주고, shell이 `WIFSIGNALED ? 128+WTERMSIG : WEXITSTATUS` 로직으로 `$?` 채움.

## [Step 5] When & Condition

Exit code가 의미 있는 경우:

1. **Synchronous command 직후**: `$?`로 직전 명령 결과 접근.
2. **Pipeline 종료 후**: default는 마지막 stage의 exit code. `set -o pipefail`로 어느 stage라도 실패 시 non-zero.
3. **Background job**: `wait $!` 호출 후 `$?`로 수확.
4. **Script 종료 시**: 마지막 명령의 exit code가 script의 exit code. 명시 `exit N`으로 override.
5. **`trap` handler**: `EXIT` trap이 exit code를 덮어쓸 수 있음.

조건:
- **Process가 정상 종료**해야 exit code 정의 (`exit`/`return`/main 종료).
- Signal로 종료 시 exit code는 별도로 없고, shell이 `128+sig` convention으로 합성.
- Zombie 상태에서 wait()이 호출되어야 exit code 수확 가능. Wait 안 하면 zombie 누적.

## [Step 6] Limitation & Alternatives

### 한계
- **8-bit only**: 256 values. Rich error reporting 불가능. e.g., HTTP의 400 vs 401 vs 403 구분 못 함 (전부 1로 환원되기 쉬움).
- **Convention의 약함**: 0=success만 universal. 1, 2, 3의 의미는 **program-specific**. `grep`의 `1`은 "매치 없음"이지 error 아닌데, `set -e` script에선 fatal로 인식 → silent bug.
- **Pipeline 정보 손실**: default 마지막 stage만. `$PIPESTATUS` 없으면 중간 stage 실패 못 봄.
- **Signal vs exit 모호**: `128+N` convention은 exit code 128을 명시한 process와 SIGSEGV(11)을 합성한 139를 헷갈리지 않게 하려는 우회. 그러나 ` 128~143`을 exit code로 명시한 program이 있다면 충돌.

### 우월한 대안
- **Structured stdout** (JSON/YAML): exit code는 binary signal로만, 상세 error는 stdout에 structured data. `jq`로 parse.
- **Logging framework** (syslog, journald): trace 정보를 별도 channel로.
- **gRPC error codes**: 17개 표준 (UNAVAILABLE, DEADLINE_EXCEEDED, ...) + structured details. exit code의 RPC 일반화.
- **Erlang's `{ok, Val}` / `{error, Reason}` tuple**: 언어 level의 풍부한 error semantics. process boundary 안에선 우월.

그러나 **process boundary를 넘는 atomic termination signal**로는 exit code가 여전히 유일.

## [Step 7] Duality & Null Space

**Dual**: **stdout/stderr** — exit code의 보완 채널. Exit code는 atomic, single-byte, structured. stdout/stderr는 streaming, multi-byte, unstructured. 둘은 보완이지 대체 아님.

**Null space**: exit code가 표현하지 못하는 것 = "성공/실패 외의 모든 차원". e.g., warning (non-fatal issue), partial success (10개 중 8개 성공), progress (반쯤 진행 후 중단). 이 모든 정보는 stdout/stderr/exit code 외 채널(named pipe, signal, IPC) 필요.

## [Step 8] Validation

**Limit Test**:
- Exit code 0개 (반환 못 함) → parent가 child 상태 알 방법 없음 → process chaining 불가능 (`make && make install` 불가). Unix shell programming 마비.
- Exit code 무한 bit → 256-bit exit code 가정? → 풍부한 reporting 가능하나 wait()/status word ABI 깨짐. 모든 Unix syscall 인터페이스 재설계 필요. 비용 ≫ 이득.
- → 8-bit는 historical artifact이지만 "충분히 작아 atomic" + "충분히 크아 분류 가능"의 sweet spot.

**Dimensional Check**:
- `$?`는 **time-local**: 직전 명령에만 valid. echo 자체도 명령이므로 `echo $?` 호출 후 다시 `$?` 보면 echo의 exit code (=0). dimension = "single command ago".

**Control Knob**:
- `set -e` (errexit): non-zero exit code 만나면 script 즉시 종료. **shell scripting의 fail-fast 스위치.**
- `set -o pipefail`: pipeline의 어느 stage라도 non-zero면 pipeline 전체 non-zero. default off → 명시 필수.
- `set -u`: undefined variable 사용 시 종료. exit code error path 확보용.
- 3-line prelude: `set -euo pipefail`. **모든 production shell script의 첫 줄.**

## [Step 9] Advanced Perspective

**Process group의 exit status**: subshell이 background로 여러 child를 띄우면 각각 별도 exit code. `wait -n` (bash 4.3+)으로 "가장 먼저 끝난 child의 exit code"만 수확 가능. **race-aware scripting**의 도구.

**Container & orchestration**:
- Docker container exit code = main process의 exit code. Kubernetes의 `restartPolicy`가 0/non-zero 기준으로 restart 결정.
- `kubectl wait --for=condition=complete` 안에서 Job의 exit code가 retry policy의 input.
- 단순한 8-bit 값이 cluster orchestration의 control plane signal로 elevation됨 — Unix process model이 distributed system에 fractal하게 확장된 예.

**`trap` 과의 상호작용**:
```bash
trap 'echo "trapped, exit code was $?"' EXIT
false
# 출력: "trapped, exit code was 1"
# 그러나 trap handler 안에서 다시 명령 실행하면 $?가 덮여 쓰임
```
Trap handler가 exit code를 보존하려면 시작 직후 `rc=$?` capture.

## [Step 10] Link to Upper Concepts

- **OS process lifecycle**: fork → exec → exit → wait. exit code는 마지막 단계의 출력. External: `JY_KAIST/02_Concepts/CS/Process_Lifecycle`.
- **IPC mechanism taxonomy**: pipe, signal, shared memory, message queue, socket, **exit code**. 후자는 가장 단순/제한적이나 가장 reliable.
- **Control flow theory**: shell의 `if`, `while`은 **strict evaluation + exit code 0 = truthy**라는 boolean encoding. 다른 언어의 `True`/`False`와 직접 대응.

## [Step 11] Generalization

Exit code를 더 추상화:

1. **8-bit exit code**: Unix process.
2. **`int` return value** in function: 같은 패턴, 더 큰 range. C library의 `errno` 시스템.
3. **HTTP status code**: 3-digit (100~599). 추가로 `100 Continue`, `200 OK`, `404 Not Found` 등 의미 표준화.
4. **gRPC status code**: 17 standardized codes + structured details (`google.rpc.Status`).
5. **Tagged union / sum type** (Haskell `Either`, Rust `Result<T, E>`): type system level의 success/error 일반화. exit code의 가장 풍부한 일반화.

Pattern: "**operation의 종료 결과를 atomic value로 encode**". granularity와 expressiveness의 trade-off를 다양한 level에서 풀어낸 design space.

## [Step 12] Confer (Comparison)

- **vs. Exception**: throw/catch는 control flow를 직접 transfer (stack unwinding). Exit code는 polling 기반 (parent가 `wait` 명시 호출). Exception은 풍부, exit code는 단순/atomic.

- **vs. errno**: `errno`는 C library의 thread-local 변수, syscall 실패 시 set됨. Exit code는 process-level. errno는 process 내부, exit code는 process 외부 channel.

- **vs. stdout/stderr**: 보완 (Step 7 참조).

- **vs. Signal**: signal은 async (kernel이 임의 시점 전달). Exit code는 sync (process 종료 시점). Signal로 죽은 process도 exit code로 환원됨 (`128+N`).

## [Step 13] Implication

1. **모든 shell control flow의 기반**: `if`, `while`, `&&`, `||`는 모두 exit code 기반. boolean이라는 별도 type이 없음 — exit code 0/non-zero가 boolean encoding.
2. **`set -e` 같은 fail-fast의 가능성**: exit code가 atomic이라 단일 if/else로 매 명령 후 check 가능 → shell이 declarative하게 "어디서든 실패 시 종료" 표현.
3. **Process chaining의 단위**: pipeline, scripts, CI/CD pipeline, container orchestration이 모두 exit code 위에 build. Cluster level까지 reach.
4. **Convention의 의존성**: 0 외에는 program-specific → man page의 `EXIT STATUS` section 읽지 않으면 silent bug. 이게 shell scripting의 가장 흔한 학습 함정.

## [Step 14] Application

**보안 / 침투 테스트**:
- 침투 자동화에서 `nmap`, `nikto`, `sqlmap` 등 도구의 exit code로 단계 전이 결정. `nmap -oG ... && parse_results` 패턴.
- CI/CD에서 `bandit`, `safety`, `trivy` 등 SAST 도구의 exit code 0/1 기준으로 PR 차단.

**Bandit 맥락**:
```bash
ssh -p 2220 bandit5@bandit.labs.overthewire.org 'cat /etc/bandit_pass/bandit6'
echo $?
# 0 → password 획득
# 5 → 인증 실패
# 255 → connection refused
```
자동화 스크립트가 단계별 exit code 분기 가능.

**일반 scripting**:
- Deployment script: 각 단계 exit code check → fail-fast.
- Backup script: `tar`, `rsync`, `gzip` 각각 exit code 확인 → partial failure 감지.
- Health check probe: `curl -f` exit code 0이면 healthy.

## [Step 15] Background Knowledge

- **Unix V7 (1979)**: `wait()` system call의 status word를 16-bit으로 정의. 하위 8-bit = signal/core, 상위 8-bit = exit code. 이 layout이 4.4BSD/POSIX/Linux로 그대로 전승.
- **POSIX.1-2017**: exit code 0=success, non-zero=failure 명문화. `EX_USAGE=64` 등 `sysexits.h` standard exit codes (1990년대 BSD mail 시스템에서 비롯)는 권장사항이지 의무 아님.
- **Plan 9 (1990s, Rob Pike et al.)**: exit code를 8-bit가 아닌 **string**으로 변경. process 종료 시 임의 message 가능. 더 풍부하나 ABI 호환성 깨짐 → 주류 채택 실패.
- **Erlang's design (Joe Armstrong, 1986)**: process termination을 `{exit, Reason}` tuple로 — Reason은 임의 Erlang term. exit code의 풍부한 일반화이며 distributed actor model의 기반.
- **Werner Heisenberg 비유 — 인문 connection**: exit code의 8-bit 제약은 "관측의 단순화가 정보 손실을 강제한다"는 측정 이론의 shell-level 예시. parent가 child를 "관측"하는 채널이 좁기에 child의 풍부한 내부 상태가 한 byte로 collapse됨.

---

## Formal Summary (EN)

> [!theorem] Exit Code Atomicity & Universality
> For any process P terminating via `exit(N)` on POSIX-compliant systems:
> 1. **Atomicity**: N is delivered to parent in a single kernel transaction; parent observes either the full value or nothing (no torn read).
> 2. **Universality**: All shell control flow operators (`if`, `while`, `&&`, `||`, `until`) reduce to predicates over exit codes; specifically, "truthy" ≡ exit code 0.
> 3. **Range constraint**: Only the low 8 bits of N are observable: `WEXITSTATUS(s) = N mod 256`. Programs returning N > 255 silently wrap.
> 4. **Signal coalescing**: If P is terminated by signal S without explicit exit, shells synthesize an effective exit code of `128 + S`, distinguishing signal-induced from normal termination only via `WIFSIGNALED`/`WIFEXITED` macros.

> [!proof] Sketch
> (1) Atomicity follows from the kernel updating the PCB's status word as a single 16-bit write under process lock before sending SIGCHLD. (2) Universality is by definition: POSIX shell grammar specifies these constructs in terms of "command exit status" (POSIX.1-2017 §2.9.4). (3) Range constraint follows from `WEXITSTATUS` macro definition `((s >> 8) & 0xFF)` extracting 8 bits. (4) Signal coalescing is a shell-level convention (Bourne shell 1977 onward), not enforced by kernel; verified by reading bash source `execute_cmd.c::wait_for`. ∎

---

## Cross-References

### Encountered In
- (chat-session 2026-05-28) — first conceptual exposition
- [[Wargames/Bandit/Level_13]] — Better Methods의 `&&` 체인이 exit-code 0 의존 (키 반출 → `chmod` → `ssh` 단계 게이팅)
- Reapplication expected: every Bandit Level script + all shell scripting 작업.

### Tools That Implement This
- [[Tools/find]] — exit code 0 = traversal 정상, 1 = 일부 dir 접근 실패 (permission). silent skip이라도 exit code엔 반영.
- 모든 shell builtin / external command가 exit code 생산자.

### Related Concepts
- [[Concepts/Linux/Subshell]] (Related — subshell이 parent로 내보내는 단 하나의 channel = exit code)
- [[Concepts/Linux/Stderr_Redirection]] (Related — stdout/stderr은 exit code의 보완 channel)
- [[Concepts/Linux/Find_Predicates]] (Related — `find`도 exit code로 결과 신호)

### Cross-Domain
- External: JY_KAIST/02_Concepts/CS/IPC_Taxonomy (IPC mechanism comparison)
- External: JY_KAIST/02_Concepts/CS/Process_Lifecycle (fork-exec-exit-wait)

---

## Quiz

**Q1** (Graduate-level): 다음 코드의 동작과 최종 exit code를 정확히 예측하라.

```bash
#!/bin/bash
set -e
trap 'echo "EXIT trap: \$? = $?"' EXIT
foo() {
  false
  echo "after false"
}
foo || echo "foo failed"
echo "still alive"
false | true
echo "after pipe: \$? = $?"
exit 42
```

(a) `set -e`가 `||` 좌측에서 비활성화되는 이유와 그 영향. (b) `false | true`에서 `set -e`가 발동하지 않는 이유. (c) `set -o pipefail` 추가 시 어떻게 달라지는가? (d) 최종 EXIT trap이 출력하는 `$?` 값과 그 출처 (script의 어느 명령에서 파생?).

> [!tip]- 풀이
> **실행 trace**:
> 1. `foo` 호출 → `false` 실행. **`set -e`가 `||` 좌측 함수 호출 안에서는 비활성화** (POSIX 미묘 rule, bash docs `set` section 참조). 따라서 `false` 후 `set -e`로 종료 안 함. `foo`의 body 계속 진행: `echo "after false"` 출력 → `foo`의 exit code = 0 (마지막 echo 성공). 그러므로 `foo || echo "foo failed"`에서 좌측 성공 → 우측 실행 안 함.
>
>    *Wait*: bash 정책은 buggy/version-dependent. 실제로는 bash 4.x에서 함수 안 `false`도 errexit 발동시킬 수 있음. POSIX는 errexit이 `||` 좌측 전체 sub-expression에 disable됨을 명시 → 함수 안의 `false`도 `||` context 안이라 disable 일관성. 하지만 일부 bash 버전은 inherit-errexit 옵션 필요.
>
>    **실용적 결론**: 결과가 bash 버전/`shopt inherit_errexit` 설정에 따라 다름. 그래서 production에선 함수 안에 명시적 `|| return 1` 또는 `local ec=$?` 패턴 사용.
>
> 2. (set -e가 발동 안 했다고 가정 시) `echo "still alive"` 출력.
>
> 3. `false | true`: pipeline의 default exit code = 마지막 stage = `true` = 0. `set -e`는 0이라 발동 안 함. 출력: `after pipe: $? = 0`.
>
> 4. `exit 42` → script 종료, exit code = 42.
>
> 5. **EXIT trap** 실행: `$?`는 직전 명령 = `exit 42` → trap이 `EXIT trap: $? = 42` 출력. 최종 script exit code = 42.
>
> (a) `set -e`의 `||` 좌측 비활성화: 사용자가 명시적으로 "실패 시 우측 실행" 의도를 표현했으므로 errexit이 silent하게 종료시키면 의도 위반. POSIX `set -e`는 `||`, `&&`, `if`/`while` condition, `!` 좌측에서 disable.
>
> (b) `false | true`: pipeline의 마지막 stage가 성공하면 전체 pipeline exit code = 0. errexit은 0이라 발동 안 함. → 중간 실패 묻힘 (silent bug).
>
> (c) `set -o pipefail` 추가 시: pipeline의 **어느 stage라도 non-zero**면 pipeline exit code = 그 non-zero. `false | true`의 exit code = 1 (false에서). `set -e`와 결합 시 즉시 종료.
>
> (d) EXIT trap의 `$?` = 42 (직전 `exit 42`에서).
>
> 핵심: `set -e`는 **silent bug 매그넷**. 함수, pipeline, 조건문에서 부분적으로 disable되므로 의도와 다르게 동작. production script는 `set -euo pipefail` + 함수 별 명시적 error handling 권장.

---

> [!flashcard]
> **Q**: `$?`로 직전 명령 exit code를 보존하려면 어떻게 해야 하는가?
> **A**: 즉시 변수로 capture: `cmd; rc=$?`. 이후 `echo $?`나 다른 명령을 실행하면 `$?`가 덮여쓰임 (echo 자체도 명령 → exit code 0 반환). 변수 capture가 유일한 보존 방법.

> [!flashcard]
> **Q**: 신호로 죽은 process의 exit code 규칙은?
> **A**: shell convention으로 `128 + signal_number`. SIGINT(2) → 130, SIGKILL(9) → 137, SIGSEGV(11) → 139. 이는 shell-level 합성 — kernel은 status word의 lower bits에 signal number를 별도로 저장. `WIFSIGNALED(s)` 매크로로 signal-induced vs explicit exit 구분.

> [!flashcard]
> **Q**: pipeline의 exit code를 모든 stage에서 보려면?
> **A**: `$PIPESTATUS` array 사용. `false | true | false`; `echo "${PIPESTATUS[@]}"` → `1 0 1`. default `$?`는 마지막 stage만. `set -o pipefail`은 "어느 stage라도 non-zero면 non-zero" 정책.
