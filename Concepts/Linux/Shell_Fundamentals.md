---
date: 2026-07-15
domain: Linux
topic: Shell_Fundamentals
tags: [linux, shell, bash, redirection, heredoc, quoting]
status: 🟡 developing
note_tier: lite
mastery: 35
first_encountered: [[Wargames/Bandit/Level_23]]
reapplied_in: [[[Wargames/Bandit/Level_24]], [[Wargames/Bandit/Level_25]]]
---

# Shell Fundamentals

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> Bandit L23 도중 JY가 shell 기초를 정밀 심문(17문항)한 것을 정리. 각 항목은 독립 `/deep` 아톰으로 승격 가능(§Expand Later). 원자 원칙 유지: "판 개념"만, "모든 용어"는 아님.

## Definition (Formal, EN)

The Bourne-again shell (bash) is a **command language**: input is a byte stream tokenized on whitespace into words; the first word decides command-vs-assignment. Almost every non-obvious behavior below follows from that model plus **expansion** (`$`), **quoting** (`"` vs `'`), and **file-descriptor redirection** (`0/1/2`, `>`, `2>&1`).

## Intuition (KR)

shell은 "공백으로 단어를 자르고, `$`를 치환하고, 스트림(fd)의 방향을 바꾸는" 세 기계다. 이 세 개만 잡으면 나머지(heredoc·CRLF·`%`·chmod)는 파생이다.

## Key Points (무엇을 팠나)

### A. 변수 · 확장 · 인용
- **`NAME=value` 공백 금지** — `=` 양옆 공백 있으면 shell이 첫 단어를 명령으로 오인(`D: command not found`). 할당은 공백 없는 단일 토큰이어야.
- **`$` 확장 종류** — `$VAR`/`${VAR}`(변수), `$(cmd)`(명령치환=서브셸 실행 후 stdout으로 치환), `$((expr))`(산술), 백틱(구식 명령치환). **괄호 유무**가 변수 vs 명령을 가른다: `$whoami`=빈 변수, `$(whoami)`=명령 실행.
- **`"` vs `'`** — 큰따옴표: `$`·`$()` 확장 O(단어분리/glob만 억제). 작은따옴표: 아무 확장 X(리터럴, `$`도 글자). printf format을 `'...'`로 감싸 shell이 `\n`/`%s`를 안 건드리게 하는 이유.

### B. I/O · 리다이렉션
- **fd 3종** — 0=stdin, 1=stdout, 2=stderr.
- **`>` vs `>>`** — `>`=truncate(없으면 생성, 있으면 비운 뒤 쓰기), `>>`=append(끝에 덧붙임).
- **`2>&1`** — "fd 2(stderr)를 fd 1(stdout)이 **현재 가리키는 곳**으로." `&1`의 `&`=파일명 아닌 fd 번호 표시. 순서 중요: `>file 2>&1`(둘 다 파일) vs `2>&1 >file`(stderr는 터미널).

### C. 스크립트 작성
- **shebang** — `#!/bin/bash` 첫 줄. 커널이 `#!` 읽고 그 인터프리터로 실행. CRLF면 `/bin/bash\r` → `bad interpreter`.
- **`\n` vs `\r`** — LF(0x0A, 줄내림) vs CR(0x0D, 줄맨앞). Unix=LF, Windows=CRLF(`\r\n`), old mac=CR. `file`/`cat -A`(끝 `^M$`)로 확인, `dos2unix`/`sed 's/\r$//'`로 수정.
- **printf > echo(스크립트 생성 시)** — `\n` 해석 + `%s` 치환 + 한 줄 format이라 CRLF 낄 자리 없음.
- **`%` 포맷** — placeholder("다음 인자를 여기 채워라"). 뒤 글자가 타입(`%s`문자열/`%d`정수/`%x`16진/`%%`리터럴). 왼→오 위치로 인자 대응. **도구마다 사전 다름**: printf `%s`(문자열) ≠ stat `%s`(size) ≠ date `%s`(epoch).
- **heredoc** — `cat > file << EOF … EOF`: 종료어(`EOF`)는 그 줄에 **홀로**(뒤 공백·백슬래시 금지). `<<EOF`=본문 `$` 확장 O, `<<'EOF'`=리터럴.
- **`\` 이어쓰기** — 줄 **맨 마지막 문자**여야(뒤 공백 금지) 다음 줄과 병합. 개별 명령 이으려면 `;`(순차)/`&&`(성공 시). PS2 `>`=shell이 더 기다리는 중(Ctrl-C 탈출).

### D. 권한 · 원자적 생성
- **`chmod +x` 대상** — who 생략 시 u/g/o 전부(umask 반영). `u+x`/`g+x`/`o+x`로 특정. 실행 주체 계정의 x가 관건.
- **`install -m 755 /dev/stdin dest`** — copy+chmod(+chown)를 **한 명령**으로. `-m`이 "모드째 생성" → 별도 chmod 창(=두-명령 race) 제거. 완전 원자는 "temp에 만들고 같은 fs에서 `mv`(rename)".

### E. 환경 · 기타
- **`.d` 디렉터리** — drop-in config fragment 모음(`cron.d`, `sudoers.d`, `sources.list.d`, `profile.d`). 데몬이 전부 읽어 합침.
- **stat `%` 코드** — 외우지 말고 `stat --help`/`man stat`. `%n`이름 `%s`크기 `%U`/`%G`owner/group명 `%A`/`%a`권한 `%y`mtime `%F`종류.
- **paste vs 타이핑** — 동일 파서·동일 바이트 스트림. 차이는 "정확한 텍스트냐"뿐. bracketed paste는 안전 포장일 뿐 파싱 규칙 불변.
- **cron 타이밍** — `* * * * *`의 "1분"은 데드라인 아닌 **재시도 주기**(무한 반복). heredoc은 `EOF`에 파일 생성 → 타이핑 시간 무관.

### F. 반복문 · 범위 생성 (L24 brute-force에서 팜)
- **C-style `for (( ))`** — `for ((i=0;i<N;i++)); do …; done`. 산술 컨텍스트(`$` 없이 변수). **zero-pad 안 됨**(`0`,`1`,…) → `printf "%04d"` 필요.
- **brace expansion `{a..b}`** — 셸이 `{0000..9999}`를 만 개 토큰으로 **전개**. 시작값 leading zero(`0000`)면 **폭 자동 통일(zero-pad)**. 단 변수 불가(`{1..$n}` ✗).
- **`seq`** — `seq 0 9999`(범위 출력). **`-w`=equal width**로 최대값 폭에 맞춰 zero-pad(`0000`). 변수 범위 OK(brace의 대안).
- **`while`/`until`** — `while [ cond ]`(참인 동안) / `until`(거짓인 동안). 조건 기반 반복. `[ "$i" -lt N ]`(`-lt/-ge` 정수 비교).
- **루프 출력을 명령에 먹이기** — `for …; done | cmd`(파이프) 또는 파일 경유 `cmd < file`. 루프 위에 `cmd`를 **단독으로** 두면 **안 이어진다**(별개 순차 명령) — L24의 대표 실수.

### G. 로그인 셸 · 프로세스 교체 (L25 escape에서 팜)
- **login shell (`/etc/passwd` 마지막 필드)** — 접속 시 실행되는 프로그램. 정상 셸이 아니면(예: `/usr/bin/showtext`) 프롬프트 부재·`ssh host "cmd"` 무력 등 이상 현상. → [[Concepts/Linux/Restricted_Shell_Escape]].
- **`exec cmd`** — 현재 셸 프로세스를 `cmd`로 **교체**(fork 없음, 같은 PID). 이후 줄은 실행 안 됨(dead code). `cmd` 종료 시 돌아갈 셸이 없어 세션 종료.
- **`$SHELL`** — 사용자의 로그인 셸 경로 env. `more`의 `!`·vi의 `:sh`가 이걸 참조 → 오염되면(restricted) 탈출 무력. `$EDITOR`/`$VISUAL`은 별개 경로.

## Encountered / Applied In

- [[Wargames/Bandit/Level_25]] — login shell(`showtext`)·`exec`·`$SHELL`·`$EDITOR`를 restricted shell escape 문맥에서 팜(§G).
- [[Wargames/Bandit/Level_24]] — brute-force에서 `for`/brace expansion/`seq -w`/루프→`nc` 파이프 연결을 팜(§F).
- [[Wargames/Bandit/Level_23]] — cron script injection 디버깅 중 heredoc/CRLF/fd·redirect/`install`을 실전에서 팠다.
- [[Wargames/Bandit/Level_22]] — `$(whoami)` 명령치환 + `cut -d' ' -f1` 필드 추출.
- (cross-level) `$`·quote·redirect는 L06 이래 거의 모든 레벨에서 재등장.

## Expand Later (`/deep` candidates)

- **`/deep Shell_Expansion`** — `$VAR`/`$(...)`/`$((...))`/glob/brace, 확장 순서.
- **`/deep Shell_Quoting`** — `"` vs `'` vs `\` vs `$'...'`, word-splitting/globbing 억제.
- **`/deep File_Descriptors_Redirection`** — 0/1/2, `>`/`>>`/`2>&1`/`&>`/`<`/heredoc/process substitution.
- **`/deep Heredoc`** — `<<`/`<<-`/quoted-vs-unquoted delimiter, stdin 공급 메커니즘.
- **`/deep CRLF_Shebang`** — 줄바꿈 규약 + exec 실패 진단.
