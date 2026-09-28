---
date: 2026-09-28
domain: Binary
topic: Shellcode
tags: [binary, shellcode, assembly, x86-64, exploitation, encoding]
status: 🟡 developing
note_tier: lite
mastery: 50
first_encountered: "External: local-only wargame tree (no-publish) — 점프할 기존 함수가 없어서 코드를 직접 주입해야 했다"
reapplied_in: []
---

# Shellcode

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> 처음으로 x86-64 어셈블리를 손으로 써서 동작하는 `execve` shellcode를 만든 스레드.
> 문법이 아니라 **제약**이 본질이라는 것, 그리고 컴파일러 출력이 왜 대체로 못 쓰이는지.

## Definition (Formal, EN)

Shellcode is machine code that is **position-independent and self-contained**: it carries
no relocations and references nothing outside its own bytes. It must run correctly when
dropped at an arbitrary address, with no linker having processed it, no loader having
mapped anything for it, and no surrounding tables (GOT/PLT, `.rodata`) present.

## Intuition (KR)

"어셈블리로 쓴 코드"가 아니라 **"혼자서 동작하는 바이트 열"** 이다. 어셈블리를 쓰는 건
자족성을 확보하기 위한 수단이고, 목적이 아니다.

## Key Points (무엇을 팠나)

### A. ⭐ 판정 기준은 relocation 이다

`.o` 를 만든 뒤 두 명령이 합격/불합격을 가른다:

```bash
objdump -r x.o     # RELOCATION RECORDS 가 비어야 한다
objdump -h x.o     # .text 외에 .rodata / .data 가 있으면 안 된다
```

측정한 대조 (같은 동작, `write` + `exit`):

| | libc 호출하는 C | freestanding C (`-nostdlib` + inline asm) |
|---|---|---|
| 섹션 | `.text.startup`, **`.rodata.str1.1`**, `.eh_frame` | **`.text` 뿐** |
| relocation | **3개** | **0개** |
| `.text` 추출해 실행 | **SIGSEGV (exit 139)** | 정상 동작 |

불합격 쪽의 relocation 세 줄이 실패 원인을 그대로 적어준다:

| relocation | 뜻 | 왜 치명적인가 |
|---|---|---|
| `R_X86_64_PC32  .LC0` | 문자열 상수 주소를 채워라 | 문자열이 **`.rodata`** 에 있다 — `.text` 만 뽑으면 따라오지 않는다 |
| `R_X86_64_PLT32 write` | libc 함수의 PLT 주소를 채워라 | PLT/GOT 표가 없는 곳에 떨어지면 **갈 곳이 없다** |

그리고 추출한 바이트에 그 빈칸이 보인다 — `e8 00 00 00 00` (`call` 목적지가 0),
`48 8d 35 00 00 00 00` (`lea rsi,[rip+0]`). **주소 자리가 값이 아니라 링커용 빈칸이다.**

### B. 제약을 만족하는 인코딩을 고르는 일이다

같은 결과를 내는 명령이 여럿이고, **길이와 NUL 포함 여부가 다르다** (측정값):

| 명령 | 바이트 | 길이 | NUL |
|---|---|---|---|
| `mov rax, 60` | `48 c7 c0 3c 00 00 00` | 7 | 4 |
| `mov eax, 60` | `b8 3c 00 00 00` | 5 | 3 |
| **`mov al, 60`** | `b0 3c` | **2** | **0** |
| **`xor rsi, rsi`** | `48 31 f6` | 3 | **0** |
| `mov rsi, 0` | `48 c7 c6 00 00 00 00` | 7 | 4 |

- 작은 상수는 **작은 레지스터**(`al`/`eax`)로 쓰면 짧고 NUL이 없다 — 32비트 쓰기는 상위
  비트를 0으로 만들어 주므로 결과가 같다 → [[Concepts/Binary/Stack_Frame_And_Call_Ret]]
- 0을 만들 때 `mov reg, 0` 은 NUL 범벅, `xor reg, reg` 는 깨끗하다
- ⚠️ NUL 제약이 걸리는지는 **입력 함수가 정한다.** `read` 로 들어가면 아무 바이트나 되고,
  `strcpy`/`gets`/`scanf("%s")` 면 `0x00` 하나에 잘린다 →
  [[Concepts/Linux/C_Input_Functions]]

### C. 데이터 섹션이 없으니 문자열을 **만들어 넣어야** 한다

`execve("/bin/sh", …)` 는 문자열의 **주소**를 요구하는데 shellcode에는 `.rodata` 가 없다.
쓸 수 있는 쓰기 가능 메모리는 **스택**이고, 그 주소는 `rsp` 가 들고 있다.

`push` 의 한계를 측정하면 방법이 정해진다:

| | 바이트 | 결과 |
|---|---|---|
| `push 0x41` | `6a 41` | imm8 |
| `push 0x6968` | `68 68 69 00 00` | **imm32 — 4바이트로 0 패딩된다** |
| `push 0x7fffffff` | `68 ff ff ff 7f` | imm32 최대 |
| `push <7바이트 값>` | — | **`error: invalid operand`** |

⭐ **`push` 는 상수를 4바이트까지만 받는다.** 8바이트는 `mov r64, imm64`(`movabs`)로 레지스터에
담고 그 레지스터를 push한다. 그 인코딩에 문자열이 그대로 보인다:

```
movabs rax, 0x68732f6e69622f   →   48 b8 2f 62 69 6e 2f 73 68 00
                                         └─ '/' 'b' 'i' 'n' '/' 's' 'h' NUL
push rax                       →   50
```

8바이트를 채우다 남은 상위 1바이트가 `00` 이 되어 **C 문자열의 끝 NUL 을 공짜로 준다.**
그리고 값 → 메모리 순서가 리틀엔디안이라 글자 순서가 맞아떨어진다 →
[[Concepts/Binary/Binary_Number_Encoding]]

### D. C로 쓸 수 있다 — 대가가 있다

| | freestanding C | 어셈블리 |
|---|---|---|
| 로직 표현 | 쉽다 | 어렵다 |
| 크기 | 크다 (`write`+`exit` 45바이트) | 작다 |
| **바이트 통제** | **없다** — 컴파일러가 정한다 | 완전하다 |
| NUL 회피 | 거의 불가능 | 가능 |
| relocation 사고 | 방심하면 생긴다 | 안 생긴다 |

필수 플래그와 **각각이 막는 relocation**:

| 플래그 | 없으면 |
|---|---|
| `-nostdlib` | libc 호출 → PLT relocation. 진입점도 `main` 대신 `_start` 를 써야 한다 |
| `-fno-stack-protector` | ⭐ canary 코드가 **`__stack_chk_fail` 호출**을 만든다 = relocation |
| `-fno-asynchronous-unwind-tables` | `.eh_frame` 이 `.text` 를 가리키는 relocation을 만든다 |
| `-fno-builtin` | 배열 초기화가 `memcpy` 호출로 치환될 수 있다 |
| `-fPIC` / `-Os` | 위치 독립 / 크기 |

⚠️ **함정:** `gcc -Os` 는 `main` 을 `.text` 가 아니라 **`.text.startup`** 에 넣는다.
`objcopy -j .text` 를 믿고 뽑으면 **0바이트**가 나온다. `objdump -h` 로 섹션 목록을 먼저 봐라.

**실무 절충:** C로 골격을 쓰고 `gcc -S` 로 어셈블리를 뽑아 손으로 줄인다.

### E. 서버에 붙기 전에 혼자 검증하는 법

rwx 메모리를 `mmap(PROT_READ|PROT_WRITE|PROT_EXEC)` 로 얻어 바이트를 복사하고 함수
포인터로 캐스팅해 호출하면, 그게 곧 "데이터를 코드로 실행"이다 →
[[Concepts/Binary/Memory_Protections]]

⚠️ **하니스는 shellcode 바이트를 stdin으로 받지 마라.** shell이 떠도 **stdin이 EOF**라
즉시 죽는다. 파일 인자로 받아라. 같은 이유로 payload를 파일 리다이렉트로 흘려보낼 때도
`(cat payload; cat) | prog` 로 stdin을 열어 둬야 프롬프트를 볼 수 있다.

### F. 검산이 유일한 방어

```bash
wc -c sc.bin                                  # 기대 길이와 일치하나
od -An -tx1 sc.bin                            # objdump 출력과 대조
python3 -c "d=open('sc.bin','rb').read(); print(len(d), d.count(0), d.count(0x0a))"
```

⚠️ 추출 단계는 **조용히 틀린다.** 파싱이 한 줄을 놓쳐도 에러가 안 나고, 잘린 shellcode가
"성공적으로" 만들어진다. 길이·첫바이트·끝바이트 대조 외에 방어가 없다.

## Encountered / Applied In

- External: local-only wargame tree (no-publish) — 점프할 기존 함수가 제거되어 있고 스택이
  실행 가능했던 사례. 손으로 쓴 `execve` shellcode를 주입했다.

## Expand Later (`/deep` candidates)

- **NUL-free / alphanumeric shellcode** — 제약이 심할 때의 인코딩 기법, encoder + decoder stub
- **egg hunter / stager** — 버퍼가 shellcode보다 작을 때
- `open`/`read`/`write` 로 파일을 직접 읽는 shellcode — shell 없이 목적 달성
- arm64 shellcode 대조 — syscall 번호와 레지스터가 전부 다르다
