---
date: 2026-09-27
domain: Linux
topic: C_Input_Functions
tags: [linux, c, libc, read, fgets, strcpy, nul-termination, buffer-overflow, input-validation]
status: 🟡 developing
mastery: 50
note_tier: lite
first_encountered: "External: local-only wargame tree (no-publish) — 같은 버퍼에 쓰는 함수를 바꾸면 취약점 성격이 달라진다는 것"
reapplied_in: []
---

# C Input Functions

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> `read` / `fgets` / `strcpy` / `scanf` 가 **무엇에서 멈추고, NUL을 붙이는가, 임의 바이트를
> 통과시키는가** 를 한 표로 대조한 스레드. "`fgets`는 안전하고 `read`는 위험하다"는 흔한
> 요약이 왜 틀렸는지가 결론.

## Definition (Formal, EN)

C has no string type and no bounds-checked input primitive. Every input function takes a
destination pointer plus **a length the caller supplies**, and differs along three
independent axes: (1) what terminates the read, (2) whether it appends a `'\0'`,
(3) whether the byte values it carries are unrestricted. No function among them can
discover the size of the buffer it was handed — an array decays to a pointer at the call
boundary, and with it the size information.

## Intuition (KR)

C의 입력 함수는 전부 "네가 말해준 만큼" 쓴다. 버퍼가 실제로 얼마나 큰지 **물어볼 방법이
없다.** 그래서 안전성은 함수 이름이 아니라 **네가 넘긴 숫자가 맞는지**에서 온다.

## Key Points (무엇을 팠나)

### A. ⭐ 대조표 — 세 개의 독립 축

| 함수 | 멈추는 조건 | 최대 쓰는 바이트 | NUL 종료 | `0x00` 통과 | `0x0a` 통과 |
|---|---|---|---|---|---|
| `read(fd, buf, n)` | **`n` 도달 또는 EOF만** | **`n`** | ❌ | ✅ | ✅ |
| `fgets(buf, n, fp)` | `'\n'` 또는 `n-1` | `n-1` (+NUL) | ✅ | ✅ | ❌ |
| `gets(buf)` | `'\n'` | **무제한** ☠️ | ✅ | ✅ | ❌ |
| `scanf("%s", buf)` | 공백류(space/tab/`\n`) | **무제한** ☠️ | ✅ | ✅ | ❌ |
| `strcpy(dst, src)` | `src`의 `'\0'` | `src` 길이+1 | ✅ | ❌ | ✅ |
| `strncpy(dst, src, n)` | `'\0'` 또는 `n` | `n` | **⚠️ 조건부** | ❌ | ✅ |

☠️ `gets`는 C11에서 **표준에서 삭제됐다.** `scanf("%s")`는 남아 있지만 같은 결함이다
(폭 지정 `%63s`를 붙여야 한다).

⚠️ `strncpy`는 `src`가 `n`보다 길면 **NUL을 붙이지 않는다.** "n이 붙었으니 안전"이 아니다.

### B. ⭐ `read`는 바이트 운반기다, 문자열 함수가 아니다

세 가지를 새겨야 한다:

1. **NUL 종료를 붙이지 않는다.** 읽은 바이트 뒤에 원래 있던 쓰레기가 그대로 남는다.
   그 버퍼를 `%s`나 `strlen`에 넘기면 **버퍼 밖까지 읽는다.**
2. **`buf`가 얼마나 큰지 모른다.** `n`은 *네가* 알려준 숫자고, 컴파일러도 libc도 커널도
   `n ≤ sizeof(buf)`를 확인하지 않는다.
3. **개행에서 멈추지 않는다.** `'\n'`은 그냥 `0x0a` 바이트다.

반환값 의미론:

| 반환 | 뜻 |
|---|---|
| `> 0` | **실제로** 읽은 바이트 수 — `n`보다 **적을 수 있다** (short read) |
| `0` | EOF |
| `-1` | 에러 (`errno`) |

`ssize_t`가 `size_t`가 아닌 이유: `-1`을 표현해야 하므로 **부호가 필요**하다.

### C. ⚠️ 터미널이 줄 단위로 멈추는 것은 `read`의 성질이 아니다

터미널에서 `read`를 부르면 Enter까지 기다리는 것처럼 보인다. 그건 **tty driver가 canonical
mode에서 줄이 완성될 때까지 커널에 넘기지 않기** 때문이다.

`stdin`이 **pipe나 파일**이면 그 동작은 사라지고 `read`는 있는 대로 집어간다.

> **"터미널에선 되는데 스크립트로는 안 되네"의 정체가 이것이다.**
> → [[Concepts/Linux/Tty_And_Terminals]]

### D. ⭐ `fgets`의 최대 함정 — 개행이 버퍼에 남는다

`"abc\n"`을 입력하면 버퍼는 `a b c \n \0`. 그래서 `strcmp(buf, "abc")`는 **실패한다.**

관용구:
```c
buf[strcspn(buf, "\n")] = '\0';    // 첫 '\n'을 NUL로. 없으면 아무 일도 안 한다
```
`strcspn(s, reject)`는 `reject`의 문자가 처음 나오는 위치를 준다 — 없으면 문자열 길이를
반환하므로, 개행이 없어도 안전하게 동작한다(이미 있는 NUL을 NUL로 덮는다).

`size`가 `size_t`가 아니라 `int`인 것도 역사적 잔재다.

### E. ⭐ "`fgets`는 안전, `read`는 위험"은 틀렸다

`fgets(buf, 200, stdin)`을 크기 64인 `buf`에 쓰면 `read`와 **똑같이** 망한다.

진짜 차이는 하나다:

| | 동작 |
|---|---|
| `fgets` | 받은 `size`를 **스스로 지킨다** (`size-1`에서 자동 절단) → **틀린 숫자를 줘야** 깨진다 |
| `read` | 지킬 size라는 개념이 없다. `n`을 **명령으로** 받는다 → 게다가 NUL 종료 쪽에서 **별도로** 깨질 수 있다 |

> 안전성은 함수 이름이 아니라 **네가 넘긴 숫자가 실제 버퍼 크기와 일치하는가**에서 온다.
> `sizeof(buf)`를 넘기면 `fgets`는 안전하고, 손으로 박은 숫자를 넘기면 둘 다 위험하다.

### F. 함수 경계를 넘으면 크기 정보가 소멸한다

```c
char buf[64];
sizeof(buf)            // 64 — 선언된 함수 안에서만
void f(char *p) { sizeof(p); }   // 8 — 포인터 크기. 배열 크기를 알 방법이 없다
```

배열을 인수로 넘기면 **포인터로 붕괴(decay)한다.** 이것이 "입력 함수가 버퍼 크기를 모른다"의
기계적 이유이고, `-Wall`이 잡아주는 범위가 **같은 함수 안**으로 한정되는 이유다.

### G. 보안적 귀결 — 함수 선택이 payload의 자유도를 정한다

| 쓰인 함수 | payload에 넣을 수 있는 것 |
|---|---|
| `strcpy` | `0x00` **불가** — 첫 NUL에서 복사가 멈춘다 |
| `fgets`/`scanf` | `0x0a` **불가** — 개행에서 멈춘다 |
| **`read`** | **제한 없음** |

⭐ 64비트 주소는 상위 여러 바이트가 `0x00`이다. 즉 **`strcpy`로는 주소를 온전히 심을 수
없고, `read`라면 공짜다.** 소스에서 입력 함수가 무엇인지 보는 것만으로 공격 가능한 payload의
모양이 절반 결정된다.

→ [[Concepts/Binary/Ret2Win_Pattern]]

## Related

- [[Concepts/Linux/File_Descriptors_And_Streams]] — `read`(fd 세계)와 `fgets`/`fputs`(스트림
  세계)가 왜 다른 층위인지. **선수 개념.**
- [[Concepts/Linux/Tty_And_Terminals]] — canonical mode가 `read`의 겉보기 동작을 바꾼다.
- [[Concepts/Binary/Ret2Win_Pattern]] — §G의 payload 자유도가 공격 가능성을 좌우한다.
- [[Concepts/Binary/Binary_Number_Encoding]] — 왜 주소에 `0x00`이 섞이는가.
- [[Concepts/Linux/Shell_Fundamentals]] — `< file` 리다이렉션으로 stdin을 교체하는 것이
  §C의 pipe 경로를 만든다.
- [[Concepts/Binary/Shellcode]] — 어떤 입력 함수를 통과하느냐가 shellcode의 **인코딩 제약**을
  정한다 (`read` → NUL 자유, `strcpy` → NUL 금지).
- ⚠️ payload 를 `< file` 로 흘려보내면 shell 이 떠도 **stdin 이 EOF** 라 즉시 죽는다.
  `(cat payload; cat) | prog` 로 stdin 을 열어 둬야 한다.

## Encountered / Applied In

- External: local-only wargame tree (no-publish) — 고정 크기 버퍼에 손으로 박은 큰 숫자를
  넘기는 `read` 호출. 출제자가 `fgets`나 `strcpy`가 아니라 `read`를 고른 것이 payload에
  NUL 바이트를 허용하려는 의도적 선택이었다.

## Expand Later (`/deep` candidates)

- **`printf` 계열과 format string bug** — `printf(user_input)`이 별개 취약점 계열인 이유,
  `%n`, 그리고 `fputs`를 쓰면 그 경로가 아예 없어진다는 점.
- **C 문자열 함수 전반의 안전 대체군** — `strlcpy`/`strlcat`(BSD), `snprintf`,
  `_FORTIFY_SOURCE`가 컴파일 타임에 잡는 것과 못 잡는 것.
- **`scanf` 포맷 지정자 전체** — 폭 지정, `%[^\n]`, 반환값 검사, 실패 시 스트림에 남는 입력.
- short read를 올바르게 처리하는 관용구 (`read` 루프) — 네트워크 소켓에서 필수.
