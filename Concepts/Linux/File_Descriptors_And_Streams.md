---
date: 2026-09-27
domain: Linux
topic: File_Descriptors_And_Streams
tags: [linux, libc, stdio, file-descriptor, buffering, setvbuf, isatty, syscall]
status: 🟡 developing
mastery: 50
note_tier: lite
first_encountered: "External: local-only wargame tree (no-publish) — 원격 서비스 코드 첫 줄의 setvbuf 호출이 왜 거의 항상 있는지"
reapplied_in: []
---

# File Descriptors vs Streams

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> C의 I/O가 **두 개의 서로 다른 세계**(정수 fd / `FILE*` 스트림)라는 축을 세우고, 그 차이에서
> `setvbuf(stdout, NULL, _IONBF, 0)` 이 왜 필요한지까지 유도한 스레드.
> [[Concepts/Linux/File_IO_And_Cursor]] 의 Expand Later에 파킹돼 있던 "버퍼링 계층" 항목을
> **C 층위에서** 소비한다 (Python `io.BufferedReader`/`fsync` 쪽은 여전히 미작성).

## Definition (Formal, EN)

A **file descriptor** is a small non-negative integer indexing the kernel's per-process
open-file table; `read(2)`/`write(2)` operate on it directly and **unbuffered**. A
**stream** (`FILE *`) is a libc structure *wrapping* a descriptor with a user-space
buffer, position state and error flags; `fgets`/`fputs`/`printf` operate on it. Streams
are strictly a layer **above** descriptors — every stream operation eventually issues
descriptor syscalls, batched according to the stream's **buffering mode**.

## Intuition (KR)

fd는 커널이 준 **번호표**이고, `FILE*`는 그 번호표를 감싼 libc의 **포장지**다. 포장지가
있으니 포장 방식을 바꾸는 손잡이(`setvbuf`)도 있다 — 그리고 그 손잡이가 기본값으로
어디에 놓이는지가 "터미널에선 되는데 파이프로는 멈추는" 현상의 원인 전부다.

## Key Points (무엇을 팠나)

### A. 두 세계 대조표

| | **file descriptor** | **FILE\* stream** |
|---|---|---|
| 정체 | **정수** (0, 1, 2, 3…) | libc **구조체 포인터** |
| 헤더 | `<unistd.h>` | `<stdio.h>` |
| 표준입출력 | `STDIN_FILENO`(0), `STDOUT_FILENO`(1), `STDERR_FILENO`(2) | `stdin`, `stdout`, `stderr` |
| 함수 | `read`, `write`, `open`, `close` | `fgets`, `fputs`, `printf`, `fopen`, `setvbuf` |
| 버퍼링 | **없음.** 부르면 곧바로 syscall | **있음.** 메모리에 모아뒀다 한 번에 |
| 층위 | 커널 경계 (syscall) | 커널 **앞**의 사용자 공간 래퍼 |

⭐ `stdin`/`stdout`/`stderr`도 **특별한 타입이 아니다.** 프로그램 시작 시 libc가 fd 0/1/2를
감싸 만들어 둔 평범한 `FILE*`다. 그래서 `fgets(buf, n, stdin)`과 `fgets(buf, n, someFile)`은
문법적으로 완전히 대등하다.

`STDIN_FILENO`는 그냥 `0`의 매크로다 (`#define STDIN_FILENO 0`). `read(0, …)`과 100% 동일.
**이름은 컴파일러를 위한 게 아니라 읽는 사람을 위한 것**이다 — `0`만 보면 fd인지 길이인지
플래그인지 알 수 없다.

### B. 섞어 쓰면 순서가 뒤집힌다

같은 fd를 두 세계로 동시에 만지면, 한쪽은 버퍼에 쌓고 한쪽은 즉시 내보내므로 **출력 순서가
소스 순서와 달라진다.**

```c
printf("A");                       // libc 버퍼에 쌓인다
write(STDOUT_FILENO, "B", 1);      // 즉시 나간다
// 화면: B 그리고 나중에 A
```

⚠️ 규칙: 하나의 fd에 대해 **한 세계만 쓴다.** 꼭 섞어야 하면 전환 전에 `fflush`.

### C. ⭐ 버퍼링 모드 — `isatty`가 기본값을 정한다

```c
int setvbuf(FILE *stream, char *buf, int mode, size_t size);
//          ①             ②          ③         ④
```

| mode | 이름 | flush 시점 |
|---|---|---|
| `_IOFBF` | **F**ull buffering | 버퍼가 꽉 찰 때 (보통 4096바이트) |
| `_IOLBF` | **L**ine buffering | `'\n'`을 만날 때 |
| `_IONBF` | **N**o buffering | **즉시.** 모을 게 없다 |

libc는 `stdout`의 기본 모드를 **연결 대상을 보고** 정한다 (`isatty(1)`):

| `stdout`이 어디에 붙었나 | 기본 모드 | 결과 |
|---|---|---|
| 터미널 | `_IOLBF` | 줄 단위로 나온다. 사람이 쓰기 자연스러움 |
| **pipe / socket / 파일** | **`_IOFBF`** | 4KB 찰 때까지 **아무것도 안 나온다** |

> **이것이 `setvbuf(stdout, NULL, _IONBF, 0)` 이 거의 모든 원격 서비스 코드 첫 줄에 있는
> 이유 전부다.** 서버는 `socat`/`xinetd`로 프로그램의 `stdout`을 **소켓**에 붙인다. 터미널이
> 아니니 full buffering → 프롬프트가 libc 버퍼에 갇힌다. 프로그램은 이미 입력을 기다리는데
> 클라이언트는 프롬프트를 못 받아 계속 기다린다 → **deadlock.**

인수 ②④의 실제 의미: `_IONBF`에서는 **버퍼 자체가 없으므로** `buf=NULL`과 `size=0`이 모두
무의미하다(무시된다). 관용적으로 그렇게 쓴다.

⚠️ **그 스트림에 첫 I/O를 하기 전에** 불러야 한다. 이미 출력을 시작한 뒤 바꾸는 것은 표준상
미정의다. 그래서 `main` 맨 위에 온다.

`setvbuf` 없이 같은 효과를 내려면 출력마다 `fflush(stdout)`.

### D. 관찰 실험 (개행 없는 프롬프트 × 터미널/파이프)

```c
/* setvbuf(stdout, NULL, _IONBF, 0); */   // 주석을 풀고 다시
fputs("prompt: ", stdout);                 // 개행 없음 — 일부러
sleep(3);
fputs("done\n", stdout);
```

| 실험 | 결과 |
|---|---|
| 터미널, 주석 상태 | `_IOLBF`인데 개행이 없어 flush 안 됨 → 3초 뒤 한꺼번에 |
| 터미널, `_IONBF` | `prompt: `가 **즉시**, 3초 뒤 `done` |
| `\| cat`, 주석 상태 | `_IOFBF` → **개행조차 flush를 못 일으킨다.** 프로그램 종료 시 한 번에 |

네 칸이 다 채워지지 않으면 버퍼링을 이해한 게 아니다.

### E. 버퍼가 있는 곳에는 항상 flush 문제가 있다

같은 구조가 층마다 반복된다:

| 층 | 버퍼 | flush 계기 |
|---|---|---|
| Python `open()` | `io.BufferedWriter` | `close()` / `with` 블록 종료 / `flush()` |
| C `FILE*` | libc 버퍼 | `fflush` / `exit` / 버퍼 만장 / 개행(`_IOLBF`) |
| 커널 | page cache | `fsync` |

⭐ `exit()`는 열린 모든 스트림을 flush하지만 **SIGSEGV로 죽으면 하지 않는다.** 그래서
크래시하는 프로그램의 마지막 출력이 사라지는 일이 생긴다 — 디버깅 시 `stderr`(기본
`_IONBF`)를 쓰거나 `_IONBF`로 바꾸는 이유.

### F. `_exit` 는 flush 를 건너뛴다 (2026-09-29 추가)

| | 하는 일 |
|---|---|
| `exit(n)` | `atexit` 핸들러 실행 + **모든 `FILE*` flush** → `_exit(n)` |
| **`_exit(n)`** | **곧장 syscall.** 버퍼에 남은 것은 **버려진다** |

⭐ 그래서 `fputs(..., stdout); _exit(0);` 는 **stdout 이 버퍼링되어 있으면 아무것도 출력하지
않는다.** 앞에서 `setvbuf(stdout, NULL, _IONBF, 0)` 로 버퍼링을 껐다면 안전하다 — 두 호출이
**짝으로** 성립하는 코드다. §C·§E 의 실전 사례.

파이프로 붙였을 때 출력이 사라지면 이 조합을 먼저 의심해라.

## Related

- [[Concepts/Linux/File_IO_And_Cursor]] — 같은 계층 구조를 **Python 층위**에서 다룬다
  (`open()` → `BufferedReader` → `os.read()` → syscall). 이 노트는 C 층위. 그쪽 Expand Later의
  "버퍼링 계층" 항목을 부분 소비.
- [[Concepts/Linux/Tty_And_Terminals]] — `isatty`가 프로그램 **행동**을 바꾼다는 일반 원리.
  이 노트는 그 원리가 **버퍼링 모드**에 적용된 구체적 사례다.
- [[Concepts/Linux/C_Input_Functions]] — 두 세계의 입력 함수들을 의미론으로 대조.
- [[Concepts/Linux/Process_Creation]] — syscall과 libc wrapper의 구분.
- [[Concepts/Linux/Exit_Code]] — `exit()`가 flush한다는 것, SIGSEGV는 안 한다는 것.
- [[Concepts/Linux/Shell_Fundamentals]] — 파이프·리다이렉션이 fd를 갈아끼우는 메커니즘.

## Encountered / Applied In

- External: local-only wargame tree (no-publish) — 원격 서비스 소스 첫 줄의
  `setvbuf(stdout, NULL, _IONBF, 0)` 이 무엇을 보장하는지 역추론. 출제자가 "버퍼링 때문에
  안 풀리는 일은 없게 하겠다"고 선언한 줄이었다.

## Expand Later (`/deep` candidates)

- **`fflush(NULL)`과 `exit` 경로** — `atexit` 핸들러, `_exit`(flush 안 함)와 `exit`의 차이,
  `fork` 후 자식이 부모의 미flush 버퍼를 복제해 **같은 출력이 두 번** 나오는 고전 함정.
- **`fsync`/`fdatasync`와 내구성** — "썼다"가 언제 디스크에 도달하는가 (Python 쪽 파킹 항목과 합류).
- **fd 테이블의 의미론** — `dup`/`dup2`, `O_CLOEXEC`, fd가 `fork`/`exec`를 어떻게 건너가는가.
- `stderr`가 왜 기본 `_IONBF`인가 — 에러 메시지가 크래시에 살아남아야 한다는 설계.
