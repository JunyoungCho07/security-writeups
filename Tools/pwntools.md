---
tool: pwntools
category: exploitation
man_section: null
related: [objdump, nm, xxd, strings]
last_used: 2026-09-29
tags: [tool, python, exploitation, binary, ctf]
---

# `pwntools`

## Purpose

CTF exploit 작성용 **Python 라이브러리**다 (커맨드라인 툴이 아니다 — `from pwn import *`).
손으로 쓰면 매번 반복되는 배관을 함수 하나로 줄여준다: 소켓 대화, 주소 패킹, 어셈블,
ELF 파싱, ROP 체인 조립.

> [!warning] 도입 시점이 중요하다
> 모든 편의 기능은 **방금 배운 것을 가린다.** `p64()` 는 엔디안을, `ELF().symbols` 는 심볼
> 테이블을, `cyclic()` 은 스택 프레임을, `checksec` 은 각 방어 기제가 어느 ELF 구조에 있는지를
> 가린다. **손으로 한 번 해본 뒤에** 쓰는 것과 처음부터 쓰는 것은 전혀 다른 결과를 낸다.
> 이 저장소의 방침: 원리를 손으로 확인한 항목만 툴에 넘긴다.

## Installation (측정된 함정)

```bash
python3 -m pip install pwntools 'unicorn==2.1.1'
```

⚠️ **그냥 `pip install pwntools` 는 실패할 수 있다:**

```
error: [Errno 2] No such file or directory: 'cmake'
ERROR: Failed building wheel for unicorn
```

원인 추적: pwntools 4.15.0 이 `unicorn!=2.1.3,!=2.1.4,>=2.0.1` 을 요구하고, pip는 허용되는
**가장 높은 버전(2.1.2)** 을 고르는데 **그 버전만 해당 플랫폼 wheel 이 없다.**

| unicorn | pwntools 허용 | wheel (py3.13 / arm64 mac) |
|---|---|---|
| 2.1.4 / 2.1.3 | ❌ 제외됨 | ✅ |
| **2.1.2** | ✅ | **❌** ← pip가 이걸 고른다 |
| **2.1.1** / 2.1.0 | ✅ | ✅ |

→ **wheel 있는 버전을 함께 지정하면 소스 빌드가 일어나지 않는다.** 대안은 `brew install cmake`
(빌드 가능해지지만 느리다).

## Core API (이 저장소에서 쓰는 만큼)

| 함수 | 손으로 쓰면 | 하는 일 |
|---|---|---|
| `remote(host, port)` | `socket.create_connection((h,p))` | TCP 연결 |
| `r.recvline()` | `recv` 루프로 `\n` 까지 모으기 | 한 줄 받기 |
| `r.recvuntil(b'…')` | 같은 루프 | 특정 바이트열까지 |
| `r.send(b)` / `r.sendline(b)` | `sendall` | 보내기 (`sendline` 은 `\n` 추가) |
| **`p64(n)`** | `struct.pack('<Q', n)` | 정수 → **리틀엔디안 8바이트** |
| `u64(b)` | `struct.unpack('<Q', b)[0]` | 역변환 |
| `p32` / `u32` | `'<I'` | 4바이트판 |
| **`r.interactive()`** | `select` 루프로 stdin↔소켓 왕복 | shell과 대화 |
| `cyclic(n)` / `cyclic_find(x)` | 직접 패턴 생성/검색 | 오프셋 찾기 |
| `ELF('./bin')` | `nm`, `objdump` | 심볼·섹션을 Python 객체로 |
| `e.symbols['puts']` | `nm -D` | 심볼의 주소/오프셋 |
| `next(e.search(b'/bin/sh\x00'))` | `strings -t x` **+ `PT_LOAD` 변환** | 바이트열의 **가상 주소** |
| **`e.address = base`** | 손으로 `base + off` | ⭐ 이후 모든 조회가 **런타임 주소**로 바뀐다 |
| `process('./bin')` | `subprocess` | 로컬 실행 |
| `context.arch = 'amd64'` | — | 아키텍처 전역 설정 (`p64` 등의 기본값) |

## Idiomatic Example — 유출 → 조립 → 대화

```python
from pwn import *

sc = bytes.fromhex("""            # objdump -s -j .text 출력을 그대로 붙여도 된다
  48b82f62 696e2f73 6800…
""")

r = remote(HOST, PORT)
leak = int(r.recvline().split()[1], 16)      # b'buffer: 0x…' → 정수
payload = sc + b'A' * (OFFSET - len(sc)) + p64(leak)
assert len(payload) == OFFSET + 8, len(payload)
r.send(payload)
r.interactive()
```

⭐ `int()` 는 **bytes 를 그대로 받는다** — `.decode()` 가 필요 없고, `0x` 접두사도
`base=16` 이면 허용된다.

## ⭐ `ELF` 객체 — 오프셋 산수를 대신한다 (2026-09-29)

ret2libc 의 두 줄 산수(`base = leak − off`, `target = base + off`)를 `.address` 대입 하나가
흡수한다:

```python
libc = ELF('./libc.so.6')            # 오프셋들 (ET_DYN 이므로 base 상대)
libc.address = leak - libc.symbols['puts']     # ← base 를 알려준다
# 이 시점부터
libc.symbols['system']               # 런타임 실제 주소
next(libc.search(b'/bin/sh\x00'))    # 런타임 실제 주소
```

⭐ **`search()` 가 파일 오프셋 → 가상 주소 변환을 이미 해 준다.** 손으로 하면
`PT_LOAD` 의 `off`/`vaddr` 를 찾아 빼고 더해야 하는 단계다 →
[[Concepts/Binary/ELF_Sections_And_Relocation]] §G

> [!tip] 교차 검증으로 한 번만 쓰고 넘겨라
> 손 계산값과 `ELF` 값을 대조해 같으면 이해가 맞고, 다르면 어느 쪽이 틀렸는지가 학습거리다.
> 그 한 번 이후에는 도구를 쓴다 — 이 저장소의 도입 원칙 그대로.

## Pitfalls

> [!warning] Common Mistakes
> 1. **`asm()` 이 macOS에서 안 될 수 있다.** 타깃용 어셈블러(`x86_64-linux-gnu-as`)를 찾는데
>    맥에는 없다 → `Could not find 'as' for 'amd64'`. 우회: `clang -target
>    x86_64-unknown-linux-gnu -c` 로 어셈블하고 `objdump -s -j .text` 로 뽑아
>    `bytes.fromhex()` 에 붙인다. → [[Concepts/Binary/ELF_Sections_And_Relocation]]
> 2. **`No module named 'pwn'` 은 거의 항상 인터프리터 불일치다.** pyenv의 python3에만 깔려
>    있고 `/usr/bin/python3` 이나 IDE가 고른 인터프리터에는 없다. `python3 -c "import pwn;
>    print(pwn.__file__)"` 로 경로를 확인해라. → [[Concepts/Linux/Shell_Fundamentals]]
> 3. **`interactive()` 는 실제 tty 가 필요하다.** IDE 출력 패널에서 돌리면 입력이 안 간다.
>    터미널에서 실행해라.
> 4. **`p64` 를 쓰면서 `bytes.fromhex` 로 주소를 만들지 마라.** `fromhex` 는 글자를 그대로
>    바이트로 바꿔 **빅엔디안**이 되고, 길이도 8바이트가 아니다. 복귀 주소는 리틀엔디안
>    8바이트여야 한다. → [[Concepts/Binary/Binary_Number_Encoding]]
> 5. **`search()` 는 제너레이터다.** `libc.search(b'/bin/sh')` 자체는 주소가 아니라
>    이터레이터다 — `next(...)` 로 꺼내야 한다. 그냥 `p64()` 에 넣으면 타입 에러가 나거나,
>    더 나쁘게는 f-string 에서 `<generator object …>` 로 조용히 찍힌다.
> 6. **`.address` 는 심볼을 읽기 *전에* 대입해라.** 대입 전에 꺼낸 값은 오프셋이고 대입 후는
>    절대 주소다. 두 값이 같은 변수명으로 섞이면 원인 추적이 어렵다.
> 7. **`assert len(payload) == …` 를 빼지 마라.** 위 4번 같은 실수는 에러 없이 짧은 payload를
>    만들고, 서버에서 조용히 실패한다. 길이 검산이 유일한 방어다.

## 의도적으로 쓰지 않는 것

| 기능 | 이유 |
|---|---|
| `checksec` | 네 방어 기제가 **어느 ELF 구조**에 있는지를 가린다 → [[Concepts/Binary/Memory_Protections]] |
| `shellcraft` | shellcode의 제약(NUL, 자족성)을 가린다 → [[Concepts/Binary/Shellcode]] |
| `ROP()` 자동 체인 | gadget 선택을 대신 **결정**한다 |

one_gadget / `ropper --auto` / angr 처럼 **무엇을 할지 결정하는** 자동화는 영구 제외.

## Related Tools

| Tool | Relationship |
|---|---|
| [[Tools/objdump]] | 보완 — 바이트·디스어셈블은 여전히 objdump 로 본다 |
| [[Tools/nm]] | 대안 — `ELF().symbols` 가 같은 정보를 준다 |
| [[Tools/strings]] | 대안 — `ELF().search()` 가 같은 일을 하고 **좌표 변환까지** 해 준다 |
| `gdb` + `pwndbg` | 보완 — pwntools 의 `gdb.attach()` 로 연동 |

## Concepts This Implements

- [[Concepts/Binary/Binary_Number_Encoding]] — `p64`/`u64` 가 `struct` 를 감싼 것
- [[Concepts/Binary/Ret2Win_Pattern]] — payload 조립의 대상
- [[Concepts/Binary/Shellcode]] — 실어 보내는 내용
- [[Concepts/Binary/Ret2Libc_Pattern]] — `ELF().address` 가 대신하는 산수
- [[Concepts/Binary/ROP]] — `p64` 로 조립하는 체인

## Quick Reference

```python
from pwn import *
context.arch = 'amd64'
r = remote(host, port)            # 또는 process('./bin')
r.recvuntil(b'prompt')            # 배너 소비
n = int(r.recvline().split()[1], 16)
r.send(payload)                   # sendline 은 \n 추가
r.interactive()
```

## External Refs

- docs: https://docs.pwntools.com
- `python3 -c "import pwnlib; help(pwnlib.tubes.remote)"`
