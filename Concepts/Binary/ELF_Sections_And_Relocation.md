---
date: 2026-09-28
domain: Binary
topic: ELF_Sections_And_Relocation
tags: [binary, elf, sections, relocation, linker, loader, static-analysis]
status: 🟡 developing
note_tier: lite
mastery: 45
first_encountered: "External: local-only wargame tree (no-publish) — 오브젝트 파일에서 코드 바이트만 꺼내야 했다"
reapplied_in: []
---

# ELF Sections And Relocation

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> [[Concepts/Binary/ELF_Header_Fields]] 의 `/deep ELF_Format` 슬롯 중 **섹션·프로그램 헤더·
> relocation** 부분을 소비한다 (PLT/GOT 세부는 [[Concepts/Binary/Memory_Protections]] 로).
> "`.o` 에서 코드만 꺼내기"라는 구체적 과제에서 출발한 스레드.

## Definition (Formal, EN)

An ELF file carries **two independent tables** describing the same bytes: the **section
header table** (for the linker and debugger — named regions such as `.text`, `.rodata`,
`.symtab`) and the **program header table** (for the loader — which file ranges map to which
addresses with which permissions). **Relocations** are the linker's to-do list: recorded
positions whose contents are placeholders until an address is known.

## Intuition (KR)

같은 바이트에 대해 **두 개의 서로 다른 지도**가 붙어 있다 — 링커용과 로더용. 그리고 `.o`
에는 "여기 주소를 나중에 채워라"는 쪽지(relocation)가 남아 있다.

## Key Points (무엇을 팠나)

### A. 두 표를 혼동하지 마라

| | section header table | program header table |
|---|---|---|
| 누구를 위한 것 | 링커, 디버거, `nm` | **로더 (실행 시 OS)** |
| 무슨 말을 하나 | "`.text` 는 파일의 offset X 부터 N바이트" | "offset X 부터 N바이트를 주소 A 에 **권한 P로** 매핑해라" |
| 지우면 | 실행은 된다 (`strip`) | **실행 불가** |
| 보는 명령 | `objdump -h` | `objdump -p` |

⭐ **실행 시 메모리 권한에 관한 방어 기제는 program header 에만 있다** —
[[Concepts/Binary/Memory_Protections]]

### B. `.o` 의 대부분은 코드가 아니다

13바이트짜리 코드로 만든 `.o` 를 측정하면:

```
파일 크기 416바이트,  코드는 offset 64 부터 13바이트
앞 64바이트 = ELF 헤더,  뒤 339바이트 = 심볼/섹션 정보
```

| 섹션 | 내용 |
|---|---|
| `.text` | 코드 |
| `.rodata` | 읽기 전용 상수 (문자열 리터럴) |
| `.data` / `.bss` | 초기값 있는 / 0인 전역 변수 |
| `.symtab` / `.strtab` | 심볼 이름 ↔ 주소, 이름 문자열 |

파일 맨 앞은 `7f 45 4c 46 …` 이다 — 코드가 아니라 헤더. **그래서 `.o` 를 통째로 주입하면
CPU가 ELF 매직을 명령어로 실행하려 하고 즉사한다.**

### C. Relocation = 링커가 채울 빈칸의 목록

`write(1, "hi\n", 3)` 를 컴파일한 `.o`:

```
RELOCATION RECORDS FOR [.text.startup]:
OFFSET   TYPE              VALUE
0000000e R_X86_64_PC32     .LC0-0x4        ← 문자열 주소를 여기 채워라
00000013 R_X86_64_PLT32    write-0x4       ← libc 함수 주소를 여기 채워라
```

그 자리의 바이트를 보면 빈칸인 게 드러난다:
```
lea  rsi,[rip+0x0]      ← 48 8d 35 00 00 00 00   변위가 0
call <다음 명령>         ← e8 00 00 00 00         목적지가 0
```

⭐ **`00 00 00 00` 은 값이 아니라 "아직 모른다"는 표시다.** 링크를 거치지 않고 그 바이트를
실행하면 `call` 이 제자리로 점프해 폭주한다 → [[Concepts/Binary/Shellcode]] §A

### D. `.text` 만 꺼내는 세 방법

| 방법 | 명령 | 제약 |
|---|---|---|
| **정공법** | `objcopy -j .text -O binary in.o out.bin` (`-j`=`--section`) | ⚠️ **macOS 에 없다**, 그리고 아래 §E |
| **hex 덤프 → 되돌리기** | `objdump -s -j .text in.o` 로 찍고 16진수만 파싱 → `xxd -r -p` | 호스트만으로 된다 |
| **직접 잘라내기** | `readelf -S` 로 `.text` 의 Offset/Size 를 읽고 `dd` 또는 `tail -c +N \| head -c M` | 손으로 숫자를 옮겨야 한다 |

세 번째가 `objcopy` 가 내부에서 하는 일 그대로다 — 섹션 헤더 표에서 offset/size를 찾아
그만큼 잘라낸다. 쉘의 `$((0x40))` 이 16진수를 10진수로 바꿔주므로 변환은 필요 없다.

⚠️ **`objdump -s` 출력의 오른쪽은 ASCII 칸이고 거기에 `f`,`U`,`D`,`3` 같은 16진수처럼
보이는 글자가 섞인다.** 16진수 문자만 긁어모으면 쓰레기가 붙는다. 데이터는 고정 칸에 있다.

💡 실전에서 제일 빠른 방법: `objdump -s -j .text` 출력의 16진수를 **복사해서
`bytes.fromhex()` 에 붙인다** — 공백·개행을 무시하므로 그대로 붙여도 된다.

### E. ⭐ BFD 도구는 아키텍처가 게이트, `readelf` 는 아니다

같은 x86-64 `.o` 를 arm64 컨테이너에서:

```
readelf -h  →  Machine: Advanced Micro Devices X86-64      ✅ 읽는다
objcopy     →  Unable to recognise the format of the input file   ❌
objdump --info → aarch64 만                                  ← 원인
```

| | 하는 일 | 아키텍처 의존? |
|---|---|---|
| `readelf` | ELF 구조를 파싱 — **독립 파서** | **아니다** |
| `objcopy` / `objdump` / `nm` | **BFD** 라이브러리 경유 | **그렇다** — 빌드에 포함된 타깃만 |

**규칙: 구조 파서는 아키텍처 독립, BFD 도구는 아니다.** `readelf` 하나가 되는 것을 보고
`objcopy` 도 될 것이라 일반화하면 막힌다. → [[Tools/objdump]]

### F. 컴파일러가 섹션을 쪼갠다

`gcc -Os` 는 `main` 을 `.text` 가 아니라 **`.text.startup`** 에 넣는다. `-j .text` 로
뽑으면 0바이트가 나온다. **추출 전에 `objdump -h` 로 섹션 목록을 먼저 확인해라.**

### G. ⭐ 파일 오프셋 ≠ 가상 주소 — `PT_LOAD` 변환 (2026-09-29 추가)

§A 의 두 표가 **실제로 다른 숫자를 말한다**는 것이 여기서 드러난다. program header 의
`LOAD` 항목은 두 값을 **따로** 적는다:

```
LOAD off 0x00021a40  vaddr 0x00022a40  filesz 0x…  memsz 0x…
         ↑ 파일 안 위치      ↑ 적재될 주소     ← 같을 의무가 없다
```

변환식 — 그 오프셋을 **포함하는** `LOAD` 를 먼저 찾아야 한다 (`off ≤ x < off + filesz`):

```
vaddr = x − seg.off + seg.vaddr
```

### 어느 도구의 값이 이미 가상 주소인가

| 값의 출처 | 좌표계 | 변환 필요? |
|---|---|---|
| 심볼표 `st_value` (`nm`, `readelf -s`) | **가상 주소** | ❌ |
| `objdump -d` 의 왼쪽 주소 | **가상 주소** | ❌ |
| **`strings -t x`** | **파일 오프셋** | ✅ |
| `readelf -S` 의 `Offset` 칸 | **파일 오프셋** | ✅ |

⭐ **`nm` 과 `strings` 가 같은 파일에 대해 다른 좌표계로 답한다.** 함수 주소는 그대로 쓰고
문자열 주소는 변환해야 하는 이유가 이것이고, 섞어 쓰면 정확히 세그먼트 차이만큼 틀린다.

### 측정 — 통설이 통하는 것은 우연이다

실제 `libc.so.6` 의 `LOAD` 4개를 대조한 결과:

| 세그먼트 | `off` vs `vaddr` |
|---|---|
| `r--` (첫 번째) | **같다** |
| `r-x` (코드) | **같다** |
| `r--` (`.rodata`) | **같다** ← 문자열이 사는 곳 |
| `rw-` (데이터) | **정확히 `0x1000` 어긋난다** |

→ "libc 는 `strings` 오프셋 그대로 쓰면 된다"가 실무에서 통하는 이유는 **문자열이 세 번째
세그먼트에 살기 때문**이고, 규칙이 아니라 배치의 우연이다. 같은 파일 안에 반례가 있다.

링커가 보장하는 것은 `vaddr ≡ off (mod pagesize)` 뿐이다 — **완전히 같을 의무는 없다.**
`PT_LOAD` 정렬(`align 2**12`)이 요구하는 것은 그 합동뿐이다.

💡 실무: `ELF().search(b'…')` 가 이 변환을 해서 **vaddr** 를 돌려준다. 손으로 한 번 해보고
두 값을 대조한 뒤 도구로 넘기면 된다 → [[Tools/pwntools]]

## Related

- [[Concepts/Binary/ELF_Header_Fields]] — 이 노트의 **앞 층**. 헤더가 두 표를 가리킨다.
- [[Concepts/Binary/Memory_Protections]] — program header 에만 있는 런타임 권한 정보.
- [[Concepts/Binary/Ret2Libc_Pattern]] — §G 변환이 실제로 필요해지는 곳.
- [[Concepts/Binary/Shellcode]] — relocation 0 기준의 근거 (§C).
- [[Tools/strings]] — §G 의 **파일 오프셋**을 만들어내는 도구. 변환 전 좌표계.
- [[Tools/objdump]] — `-h`(섹션) / `-p`(세그먼트) / `-s`(내용) / `-r`(relocation).

## Encountered / Applied In

- External: local-only wargame tree (no-publish) — 손으로 쓴 어셈블리를 주입 가능한 생바이트로
  만들기 위해. libc를 부르는 C 버전과 freestanding 버전의 relocation 개수를 대조해
  "shellcode = relocation 0개" 라는 기준을 확인했다.
- External: local-only wargame tree (no-publish) — 공유 라이브러리 안 문자열의 **적재 주소**가
  필요해서 §G 의 변환을 손으로 수행. `strings` 의 오프셋과 심볼표의 주소가 서로 다른 좌표계라는
  것을 여기서 확인했다. → [[Concepts/Binary/Ret2Libc_Pattern]]

## Expand Later (`/deep` candidates)

- **PLT / GOT 와 lazy binding** — `U` 심볼이 실행 중 해소되는 경로
- relocation 타입 전체 (`R_X86_64_64`, `GOTPCREL`, `TPOFF` …) 와 각각이 채우는 값
- ~~`PT_LOAD` 세그먼트와 섹션의 대응 — 로더는 섹션을 보지 않는다~~
  → **2026-09-29 부분 소비됨**: §G (오프셋↔주소 변환). 섹션↔세그먼트 **귀속** 관계(어느 섹션이 어느 세그먼트에 들어가나)는 아직 미작성.
- `.init_array` / `.fini_array` — main 전후에 실행되는 함수 포인터 배열
- ELF vs Mach-O vs PE 섹션 모델 대조
