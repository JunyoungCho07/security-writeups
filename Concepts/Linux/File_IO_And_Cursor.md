---
date: 2026-08-30
domain: Linux
topic: File_IO_And_Cursor
tags: [linux, syscall, file-descriptor, cursor, python, binary-mode]
status: 🟡 developing
note_tier: lite
mastery: 55
first_encountered: "External: local-only wargame tree (no-publish) — 바이너리 파일 읽기/패치"
reapplied_in: []
---

# File I/O and the Cursor

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> `open("f","rb").read()` 한 줄을 분해하다가 fd·커서·모드 플래그·`with`·fd 고갈까지 간 스레드.

## Definition (Formal, EN)

Opening a file registers an entry in the process's file-descriptor table and returns its
integer index. The kernel maintains, per open file description, a **cursor** (file offset):
the byte position at which the next read or write begins. Every read and write advances it.

## Intuition (KR)

파일을 "연다"는 건 커널에게 번호표를 받는 것이고, 그 번호표에는 **"지금 어디까지 봤는지"** 가 붙어 있다. `read`도 `write`도 그 위치를 밀고 간다.

## Key Points (무엇을 팠나)

### A. 계층 — 마법은 없다
```
open("f","rb")            ① 파이썬 내장. 버퍼링·인코딩·객체 래핑
  └ io.BufferedReader
     └ os.open()/os.read() ② 시스템콜의 얇은 래퍼 (정수 fd로 직접 대화)
        └ libc open(3)     ③
           └ syscall open(2) ④ 여기서 커널 진입
```
- "내장 함수"란 인터프리터 실행 파일에 **C로 컴파일되어 들어간 함수**다. 파이썬도 PID를 가진 평범한 프로세스이고, **파일을 만지는 방법은 시스템콜뿐**이다 — `cat`도 vim도 똑같이 줄을 선다.
- `os` 모듈은 사실상 시스템콜 목록: `os.open/read/write/lseek/close/stat/dup2/fork/execve` ↔ `open(2)/read(2)/…`. 셸이 하는 일을 그대로 할 수 있다.
- fd 번호는 **비어 있는 가장 작은 값**이 배정된다. 0/1/2가 이미 stdin/stdout/stderr이라 첫 파일은 보통 3 ([[Concepts/Linux/Shell_Fundamentals]]의 `2>&1`과 같은 번호 체계).
- 실무에서는 `open()`을 써라. 버퍼링 덕에 `os.open()`보다 **보통 더 빠르다**(시스템콜 횟수가 줄어든다).

### B. 커서 — read도 write도 민다
- `f.tell()`이 현재 위치, `f.seek(n)`이 이동. `f.seek(n,1)`=상대, `f.seek(-n,2)`=끝 기준.
- `read()`는 **순수 함수가 아니다.** 같은 인자로 두 번 부르면 다른 결과가 나온다. `f.read()` 뒤 커서는 EOF이고, 그래서 이어서 `write`하면 **덮어쓰기가 아니라 append처럼 보인다.**
- 반환 `b''`가 EOF 신호.
- 커서는 파일의 속성이 아니라 **"연 행위"의 속성**이다. 같은 파일을 두 번 열면 커서가 둘 생겨 독립적으로 움직인다.
- 전부 읽어 메모리에 올리면(`d = f.read()`) 커널 커서의 역할이 **인덱스 변수**로 넘어간다. 큰 파일은 `seek`+`read(n)` 스트리밍 또는 `mmap`.

### C. 모드 문자열은 **두 축**이다
| 축 A (접근) | 플래그 | 기존 내용 |
|---|---|---|
| `r` | `O_RDONLY` | 보존 |
| `w` | `O_WRONLY\|O_CREAT\|O_TRUNC` | ⚠️ **여는 순간 0바이트로** |
| `a` | `O_WRONLY\|O_CREAT\|O_APPEND` | 보존, 커서 끝 |
| `x` | `O_WRONLY\|O_CREAT\|O_EXCL` | 있으면 에러 |
| `r+` | `O_RDWR` | 보존, 커서 0 |

축 B(표현): `t`(기본, `str`) vs `b`(`bytes`). 즉 `"r"` == `"rt"`.

- ⭐ **셸의 `>`와 파이썬의 `'w'`는 "비슷"한 게 아니라 같은 것이다** — 둘 다 커널에 `O_TRUNC`를 넘긴다. `>>`는 `O_APPEND`.
- **`>`가 위험한 진짜 이유**: 셸은 명령을 실행하기 *전에* 리다이렉션을 설정한다. `sort f > f`는 `sort`가 열기도 전에 파일이 비어 있다. `cmd`가 실패해도 파일은 이미 날아간 뒤.
- 진짜 append 모드(`'a'`/`O_APPEND`)는 커널이 **매 write마다 커서를 강제로 끝으로** 보낸다. `seek`이 무시되고, 그래서 여러 프로세스가 같은 로그에 안전하게 쓸 수 있다.

### D. ⚠️ `b`를 빼면 조용히 망가진다
텍스트 모드는 자동 변형을 셋 적용한다.

1. **개행 변환(universal newlines)** ← 최악. `0d 0a`가 `0a`로 접힌다. **에러도 경고도 없이 길이가 줄고, 그 지점 이후 모든 오프셋이 밀린다.** 바이너리에서 `0d 0a`는 그냥 값 13과 10일 뿐인데 구분할 방법이 없다.
2. **디코딩** — 임의 바이트는 유효 UTF-8이 아니라 대개 `UnicodeDecodeError`. 시끄럽게 실패하니 그나마 낫다.
3. **인코딩이 환경 의존** — 같은 코드가 다른 머신에서 다른 결과. 재현 불가능.

> **바이트 오프셋을 다루는 순간, 예외 없이 `b`.** `"rb"`일 때만 `len(d) == 파일 크기`이고 `d[i]`의 `i`가 곧 파일 오프셋이며, `grep -abo`가 준 숫자를 그대로 넣을 수 있다.

### E. bytes / bytearray / write
- `f.read()`는 **`bytes`(읽기 전용)**를 준다. 한 바이트도 못 고친다. 고치려면 `bytearray`(수정 가능).
- ⚠️ **`bytearray` 슬라이스 대입은 길이를 강제하지 않는다.** 4칸에 2바이트를 넣으면 리스트처럼 **조용히 크기가 바뀐다** → 이후 오프셋 전부 붕괴. 쓰기 전에 `assert len(d) == 원래크기`.
- `write`는 **커서 자리부터 덮어쓰는 것이 기본**이다. 파일이 커지는 유일한 경우는 쓰기가 기존 끝을 넘어갈 때. 반환값 = 쓴 바이트 수(assert 가능).
- ⭐ **몇 바이트만 고칠 땐 `bytearray`도 `seek(0)`도 필요 없다**: `r+b`로 열고 `seek(오프셋)` + 그만큼만 `write`. 구조적으로 파일 크기가 변할 수 없다.
- 인덱싱 `d[i]`는 `int`, 슬라이싱 `d[i:j]`는 `bytes`. `struct.unpack`은 `bytes`를 요구하므로 `d[p]`를 넘기면 `TypeError`.

### F. 비파괴적 수정과 원자적 교체
- 원본은 `'rb'`로만 열어라. 수정은 **복사본**에.
- 통째로 바꿔야 하면 **임시파일 + `os.replace`**:
  ```
  방법 A(w)  [원본] → (비어있음) → [새것]   ← 이 구간에서 죽으면 전멸
  방법 B     [원본] → [원본]+[새것.tmp] → [새것]   ← 언제 죽어도 온전한 파일이 하나는 있다
  ```
- `os.replace`는 `rename(2)`. 내용을 옮기지 않고 **이름표만 갈아끼우므로** 크기와 무관하게 순간이고, **같은 파일시스템 안에서 원자적**이다("절반만 바뀐 상태"가 존재할 수 없다).
- ⚠️ 임시파일은 **목적지와 같은 디렉토리**에 만들어야 한다. `/tmp`→`/home`은 복사+삭제가 되어 원자성이 깨진다.
- vim·패키지 매니저·DB가 전부 이 write-rename 패턴을 쓴다.

### G. `with` — try/finally의 축약형
- `with 식 as 변수:` 는 진입 시 `__enter__()`, **블록을 어떻게 벗어나든**(정상·예외·`return`·`break`) `__exit__()`를 호출한다.
- 그냥 순서대로 쓴 `f.close()`는 **예외가 나면 건너뛰어진다.** `finally`는 파이썬이 반드시 실행을 보장하는 블록이고, `with`는 그 `try/finally`를 자동 생성한다.
- 보장의 근거가 **언어 명세**라 구현에 의존하지 않는다.
- 파일 전용이 아니다 — 소켓·락·DB 연결·임시 디렉토리 등 "열었으면 닫아야 하는 것" 전부.

### H. fd 고갈은 실제로 일어난다
- 상한이 둘이고 **낮은 쪽이 이긴다**: `RLIMIT_NOFILE`(프로세스)과 OS 커널의 별도 상한(macOS `kern.maxfilesperproc`). 실측에서 리스트가 참조를 붙잡으면 커널 상한 −3(이미 쓰던 0/1/2)에서 정확히 `[Errno 24] Too many open files`가 났다.
- `d = open(...).read()`가 안 터지는 건 **CPython의 참조 카운팅** 덕이다 — 참조수 0이 되는 즉시 `close`. 이건 **구현 세부사항이지 언어 보장이 아니다.** PyPy·Jython은 추적 GC라 GC가 돌 때까지 fd가 남고, 루프에서 고갈된다.
- 위험 구간: 수천 개 파일 처리 루프, 소켓, 장시간 프로세스. `python3 -W error::ResourceWarning`으로 미닫힌 파일을 예외로 승격시켜 잡을 수 있다.

## Encountered / Applied In
- External: local-only wargame tree (no-publish) — 바이너리 파일 파싱 및 4바이트 제자리 패치

## Related
- [[Concepts/Linux/Shell_Fundamentals]] — fd 0/1/2, `>`/`>>`/`2>&1` (같은 커널 메커니즘의 셸 쪽 얼굴)
- [[Concepts/Linux/Process_Creation]] — `fork`/`execve`와 fd 상속
- [[Concepts/Binary/Binary_Number_Encoding]] — 읽어들인 바이트를 값으로 바꾸는 단계
- [[Concepts/Binary/Binary_Format_Forensics]] — 원본 보존 원칙
- [[Concepts/Linux/File_Signatures]] — 텍스트 모드 손상을 시그니처가 잡도록 설계된 이유

## Expand Later (`/deep` candidates)
- `mmap` — 커널 페이지 캐시를 그대로 주소 공간에 매핑, 큰 파일 임의 접근
- `O_APPEND`의 원자성 보장 범위와 NFS에서 깨지는 이유
- 버퍼링 계층(`io.BufferedReader`)과 `flush`/`fsync` — "썼다"가 언제 디스크에 도달하는가
