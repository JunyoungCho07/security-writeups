---
date: 2026-10-31
domain: Binary
topic: Use_After_Free
tags: [binary, heap, memory-safety, uaf, function-pointer]
status: 🟡 developing
note_tier: lite
mastery: 45
first_encountered: "External: local-only wargame tree (no-publish) — 단순화된 커스텀 allocator 위에서의 UAF"
reapplied_in: []
---

# Use-After-Free (UAF)

> [!tip] Lite note — session-explored, **not** a full 15-step atom.
> Captures what was actually asked about / dug into. Promote to a full atom via `/deep` when it earns the deep treatment.

## Definition (Formal, EN)

A **use-after-free** occurs when a pointer `p` is dereferenced after the object it designates has been released. If the allocator later returns the same storage to a new owner `q`, then `p` and `q` **alias**: stores through `q` are visible to loads through `p`. If the loaded field is a code pointer, the attacker who controls `q`'s contents controls the call target.

## Intuition (KR)

호텔 방 열쇠(`p`)를 반납하지 않았는데 프런트가 같은 방을 다음 손님(`q`)에게 줬다. 다음 손님이 방을 어떻게 꾸미든, 옛 열쇠로 들어가면 그 방이 열린다.

## Key Points (무엇을 팠나)

### A. `free` 는 "표시"일 뿐이다
- `free(p)` 가 하는 일은 allocator 의 장부에서 그 칸을 **사용 가능**으로 바꾸는 것이다.
- 변수 `p` 의 값(주소)은 그대로 남는다 → **dangling pointer**. 칸의 내용도 보통 지워지지 않는다.
- 합성 모델: 고정 크기 칸 배열 + `used[i]` 표시. `free` 는 `used[i] = false` 만 하고 끝, 포인터도 내용도 그대로.

### B. 재사용 규칙이 결정성을 준다
- **first-fit**(첫 빈 칸) allocator 에서는 방금 반납한 칸이 가장 먼저 발견되므로, `free` 직후 같은 크기의 `malloc` 은 **같은 주소**를 돌려준다.
- 실제 glibc 의 tcache / fastbin 은 같은 크기의 free 청크를 **LIFO** 로 재사용한다. 같은 원리의 현실판이다.
- 확인법은 간단하다: 두 주소를 출력해서 **눈으로 비교한다**. "같을 것 같다"는 추측으로 두지 않는다.

### C. 공격 모양: 필드 offset 맞추기
- 합성 예: 객체가 `struct { char name[24]; void (*action)(void); }` 이면 `action` 의 offset 은 **24**, 크기는 합계 32.
- 새 소유자에게 쓰는 32바이트 중 **24~31번 바이트**가 옛 포인터의 `action` 이 된다. 앞 24바이트는 무엇이어도 된다 (읽히지 않는다).
- offset 은 필드 크기를 앞에서부터 **더한 값**이다 (정렬 padding 이 끼면 달라지므로 `sizeof`/디스어셈블리로 확인한다).
- 그 칸에 호출하고 싶은 함수의 주소를 8바이트 little-endian 으로 넣으면, `p->action()` 이 그 주소로 `call` 한다. CPU 는 그 주소가 원래 무엇이었는지 검사하지 않는다.
- 객체를 **0으로 초기화**하는 allocator 라도, 그 초기화는 새 소유자가 쓰기 **전**에 일어나므로 방어가 되지 않는다.

### D. 방어는 "포인터 하나 지우기"로 안 된다
- `free` 후 `p = NULL` 은 그 변수 하나만 막는다. 같은 객체를 가리키는 **다른 사본**이 있으면 그것은 여전히 dangling 이다.
- 근본 질문은 **소유권**: 누가 마지막 사용자이고, 그 뒤에 아무도 쓰지 않음이 구조로 보장되는가.
- 언어 수준의 답: 소유권 시스템(Rust), 참조 카운트, GC.

### E. 이것은 BOF 와 다른 종류의 버그다
- BOF 는 **공간** 오류(경계를 넘음). UAF 는 **시간** 오류(수명을 넘음).
- 그래서 canary·스택 오프셋 계산이 개입하지 않는다. 대신 "무엇이 그 칸을 다시 받는가"를 추적한다.

## Encountered / Applied In

- External: local-only wargame tree (no-publish) — 고정 크기 칸을 쓰는 단순한 커스텀 allocator. free 직후 재할당으로 같은 칸을 받고, 함수 포인터 필드를 덮어 호출 대상을 바꿨다.

## Related

- [[Concepts/Binary/Ret2Win_Pattern]] — 호출 대상을 "선물 함수"로 바꾼다는 목적이 같다 (복귀 주소 대신 함수 포인터).
- [[Concepts/Binary/Memory_Protections]] — PIE off 여야 함수의 파일 주소가 곧 실제 주소다.
- [[Concepts/Binary/Binary_Number_Encoding]] — 8바이트 little-endian 패킹, `fread` 처럼 raw 로 읽는 입력에는 텍스트 변환 없이 바이트를 보낸다.
- [[Concepts/Linux/C_Input_Functions]] — 정확히 N바이트를 요구하는 입력 함수 (`send` vs `sendline`).

## Expand Later (`/deep` candidates)

- **tcache poisoning / double free** — free 리스트의 `next` 포인터를 덮어 임의 주소를 할당받기
- **type confusion** — 같은 칸을 다른 struct 로 재해석
- **ASan / valgrind** 으로 UAF 를 잡는 법
- 실제 glibc 청크 헤더와 bin 구조
