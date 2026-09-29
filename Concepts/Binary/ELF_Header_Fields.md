---
date: 2026-09-27
domain: Binary
topic: ELF_Header_Fields
tags: [binary, elf, header, pie, aslr, endianness, static-analysis]
status: 🟡 developing
mastery: 45
note_tier: lite
first_encountered: "External: local-only wargame tree (no-publish) — 바이너리의 함수 주소가 실행마다 바뀌는지를 판정해야 했다"
reapplied_in: []
---

# ELF Header Fields

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> `file` 이 요약해 주는 것 **뒤에** 무엇이 있는지 — magic 4바이트 다음의 고정 위치 필드들을
> `od` 로 직접 읽어, 아키텍처·포인터 크기·**주소 고정 여부(PIE)** 를 손으로 판정한 스레드.
> [[Concepts/Linux/Static_Binary_Triage]] 의 `/deep ELF_Format` 슬롯 중 **헤더 필드 부분**을
> 소비한다 (프로그램·섹션 헤더, PLT/GOT는 아직 미작성).

## Definition (Formal, EN)

The ELF header is a **fixed-layout structure at file offset 0**. Its first 16 bytes
(`e_ident`) are self-describing metadata — magic, class, data encoding — and the fields
that follow (`e_type`, `e_machine`, `e_entry`, …) declare what kind of object it is, for
which machine, and where execution begins. Every field sits at a **constant offset**, so
the header is readable with a hex dump alone; no ELF parser is required.

## Intuition (KR)

파일의 첫 수십 바이트가 **자기 사용설명서**다. 그래서 파서 없이 `od` 로도 읽히고,
libmagic 같은 복잡한 파서를 신뢰 경계 안에서 돌리지 않고도 판정할 수 있다.

## Key Points (무엇을 팠나)

### A. 필드 지도 (ELF64)

| offset | 크기 | 필드 | 값의 의미 |
|---|---|---|---|
| `0x00` | 4 | `EI_MAG` | `7f 45 4c 46` = `\x7f` + `"ELF"`. 아니면 ELF가 아니다 |
| `0x04` | 1 | `EI_CLASS` | `01`=32bit, **`02`=64bit** |
| `0x05` | 1 | `EI_DATA` | **`01`=little endian**, `02`=big endian |
| `0x06` | 1 | `EI_VERSION` | 항상 `01` |
| `0x07` | 1 | `EI_OSABI` | `00`=System V |
| `0x08` | 1 | `EI_ABIVERSION` | 보통 `00` |
| `0x09`–`0x0f` | 7 | `EI_PAD` | 예약, `00` |
| **`0x10`** | **2** | **`e_type`** | `01`=REL, **`02`=EXEC**, **`03`=DYN**, `04`=CORE |
| **`0x12`** | **2** | **`e_machine`** | `3e 00`=x86-64, `b7 00`=AArch64, `03 00`=i386 |
| `0x14` | 4 | `e_version` | |
| `0x18` | 8 | `e_entry` | 진입점 주소 (`_start`) |

⭐ **`e_type`과 `e_machine`은 2바이트 정수다.** 바이트가 `02 00`으로 보이는 건 little
endian이라서고 값은 `0x0002`, `3e 00`은 `0x003e`(=62). **헤더를 읽는 것 자체가 엔디안
연습이다** — payload에 주소를 쓸 때와 같은 규칙. → [[Concepts/Binary/Binary_Number_Encoding]]

### B. ⭐ `e_type` 하나가 주소 고정 여부를 정한다

| `e_type` | 이름 | 뜻 | 함수 주소 |
|---|---|---|---|
| `02 00` | **ET_EXEC** | 고정 주소 실행파일 (**No PIE**) | **매 실행 동일** |
| `03 00` | **ET_DYN** | 위치 독립(PIE) 또는 공유 라이브러리 | **매 실행 변경** |

> [!definition] PIE (Position Independent Executable)
> 코드가 메모리 어디에 올라가도 동작하도록 컴파일된 실행파일. 그래서 OS가 매 실행마다
> base 주소를 무작위로 정할 수 있다 (ASLR의 일부).

ET_EXEC이면 심볼 테이블의 주소가 **실행 중 최종 주소**다. ET_DYN이면 그 값은 **base로부터의
offset**이고, base는 실행 시 정해진다 → 주소를 미리 확정할 수 없고 leak이 필요해진다.

⚠️ **ET_DYN은 PIE와 공유 라이브러리를 구별하지 않는다.** `.so`도 `03 00`이다. 구별은
`DT_FLAGS_1`의 `DF_1_PIE`나 진입점 존재 여부로 한다.

### C. 진입점 값이 같은 것을 재확인해 준다

`objdump -f`의 `start address`:

| | 형태 | 왜 |
|---|---|---|
| No PIE | `0x401050` | 링커 기본 base `0x400000` + offset. **절대 주소가 파일에 박혀 있다** |
| PIE | `0x1050` | base가 없다. base로부터의 offset |

`0x401050 = 0x400000 + 0x1050`. 즉 `e_type`과 `start address`는 **독립된 두 경로**로 같은
결론을 낸다. 한 가지만 믿지 말고 둘을 대조하는 것이 요령이다.

### D. `EI_CLASS`가 포인터 크기를, `e_machine`이 프레임 규약을 정한다

| `EI_CLASS` | 포인터 | `struct` 포맷 | `ret`이 pop하는 크기 |
|---|---|---|---|
| `02` (64bit) | 8바이트 | `Q` | 8바이트 |
| `01` (32bit) | 4바이트 | `I` | 4바이트 |

`e_machine`은 어느 호출 규약·프레임 구조를 적용할지 정한다 — x86-64는 복귀 주소를 스택에
push하고, AArch64는 `x30` 레지스터에 넣는다. → [[Concepts/Binary/Stack_Frame_And_Call_Ret]]

### E. 파서를 신뢰 경계 안에 들이지 않는 법

```bash
od -A d -t x1 -N 20 ./binary     # 바이트만. 복잡한 파서 없음
objdump -f ./binary              # 교차 검증
```

- `-A d`: offset을 **10진수**로 (기본은 8진수 — 8진수로 세면 `0x10`을 못 찾는다)
- `-t x1`: **1바이트 단위** 16진수. `x2`/`x4`는 바이트 순서가 뒤집혀 보여 헤더 판독에 못 쓴다

⭐ `od`/`xxd`는 hexdump일 뿐 **포맷 파서가 아니다.** 정체불명 파일을 호스트에서 만질 때
libmagic(`file`)보다 공격면이 작다 — libmagic에는 CVE 이력이 있다.

### F. ⭐ `e_type` 은 심볼 주소의 **의미**까지 정한다 (2026-09-29 추가)

§B 가 "주소를 미리 박을 수 있나"를 정한다면, 같은 필드가 **심볼표 값을 어떻게 읽어야 하나**도
정한다:

| `e_type` | 심볼표 `st_value` 의 의미 | 쓸 때 |
|---|---|---|
| `ET_EXEC` (2) | **절대 가상 주소** | 그대로 payload 에 넣는다 |
| `ET_DYN` (3) | **적재 base 로부터의 오프셋** | `base + st_value` |

⭐ 그래서 **하나의 payload 안에 두 종류의 주소가 섞인다** — No PIE 실행 파일의 가젯 주소는
그대로, 공유 라이브러리(`ET_DYN`)의 함수 주소는 base 를 더해서. 같은 `nm` 출력 형식인데
전처리가 다르다는 것이 초보가 가장 자주 틀리는 지점이다.

→ [[Concepts/Binary/Ret2Libc_Pattern]] §D, [[Tools/nm]] Pitfalls 2

## Related

- [[Concepts/Linux/Static_Binary_Triage]] — `file`/`strings`/`nm` 수준의 정찰. 이 노트는 그
  **아래 층**(헤더 바이트)이다. 그쪽 Expand Later의 `/deep ELF_Format` 중 헤더 필드 부분을 소비.
- [[Concepts/Linux/File_Signatures]] — magic 4바이트(`e_ident[0..3]`)의 일반 이론. 이 노트는
  magic **다음**을 다룬다.
- [[Concepts/Binary/Binary_Number_Encoding]] — 2/8바이트 정수와 엔디안. 헤더 판독의 전제.
- [[Concepts/Binary/Stack_Frame_And_Call_Ret]] — `e_machine`이 어느 프레임 규약인지 정한다.
- [[Concepts/Binary/Ret2Win_Pattern]] — `e_type`이 공격 난이도(주소를 미리 박을 수 있나)를 정한다.
- [[Concepts/Binary/Ret2Libc_Pattern]] — `e_type` 이 `st_value` 의 의미를 정한다(§F). 한 payload 에 절대 주소와 base 상대 오프셋이 함께 들어가는 이유.
- [[Concepts/Binary/ELF_Sections_And_Relocation]] — 이 노트의 **다음 층**: 헤더가 가리키는
  두 표(섹션/프로그램 헤더)와 relocation. 위 Expand Later 를 소비한 노트.
- [[Concepts/Binary/Memory_Protections]] — `e_type` 이 네 방어 기제 중 **PIE 하나**를 말해준다.
  나머지 셋은 다른 구조에 있다.
- [[Tools/objdump]] · [[Tools/nm]] · [[Tools/xxd]] — 판독 도구.

## Encountered / Applied In

- External: local-only wargame tree (no-publish) — 함수 주소를 payload에 미리 박을 수 있는지
  판정하기 위해 `e_type`을 직접 읽은 사례. `od`·`e_machine`·`start address` 세 경로가 같은
  결론을 냈다.

## Expand Later (`/deep` candidates)

- ~~**`/deep ELF_Format`의 잔여분** — program header, section header, 둘의 차이~~
  → **2026-09-28 소비됨**: [[Concepts/Binary/ELF_Sections_And_Relocation]] (+ relocation 추가)
- ~~**ELF에서 방어 기제를 판독하기** — NX/RELRO/canary/PIE 가 각각 어느 구조에 있나~~
  → **2026-09-28 소비됨**: [[Concepts/Binary/Memory_Protections]]
- **Dynamic linking / PLT·GOT** — `U` 심볼이 실행 중 해소되는 경로, lazy binding.
  (GOT 의 존재 이유와 RELRO 3단계는 `Memory_Protections` §E 에 있고, PLT 스텁의 기계어
  수준 동작은 미작성.)
- ELF vs Mach-O vs PE 헤더 대조 — 같은 정보를 어디에 어떻게 두는가.
