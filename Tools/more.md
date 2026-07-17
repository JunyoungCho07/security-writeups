---
tool: more
category: pager
man_section: 1
related: [less, cat, vi]
last_used: 2026-07-17
tags: [tool, linux, pager, shell-escape]
---

# `more`

## Purpose
터미널에서 텍스트를 **한 화면(screenful)씩 끊어 보여주는 페이저**. 파일이 화면보다 길 때 스크롤·검색을 제공하고, **짧으면 `cat`처럼 전량 출력 후 즉시 종료**한다.

## Full Signature
```
more [OPTIONS] <file...>
<command> | more
```

| Position | Name | Type | Description |
|---|---|---|---|
| `<file...>` | 입력 파일 | path(s) | 페이징할 파일. 생략 시 stdin(파이프) |

## Common Flags (most-used 5-7)

| Flag | Long | Effect | Example |
|---|---|---|---|
| `-d` | — | 하단에 조작 힌트 표시(`[Press space…]`) | `more -d big.log` |
| `-f` | — | 논리적 줄 기준 카운트(긴 줄 wrap 무시) | `more -f wide.txt` |
| `-p` | — | 화면 clear 후 표시(스크롤 대신) | `more -p file` |
| `+N` | — | N번째 줄부터 시작 | `more +100 file` |
| `+/pat` | — | 패턴 첫 매치부터 시작 | `more +/ERROR log` |
| `-s` | `--squeeze` | 연속 빈 줄을 하나로 | `more -s file` |

## Interactive Commands (페이징 중 — 보안상 핵심)

| Key | Action |
|---|---|
| `Space` / `f` | 다음 화면 |
| `Enter` | 한 줄 아래 |
| `b` | 뒤로 한 화면(파일 입력 시) |
| `/pattern` | 정방향 검색 |
| `!command` | **subshell(`$SHELL`)에서 command 실행** ← 탈출 벡터(단, `$SHELL` 오염 시 무력) |
| `v` | **`$VISUAL`/`$EDITOR`(default `vi`)로 editor 기동** ← `$SHELL` 우회 탈출 벡터 |
| `q` | 종료 |

## Idiomatic Examples

### 기본 사용
```bash
$ more /var/log/syslog          # 긴 로그를 한 화면씩
$ dmesg | more                  # 파이프 입력
```

### 자주 쓰는 조합
```bash
$ more +/panic kernel.log       # 'panic' 첫 등장부터
$ git log | more                # 페이저 없는 출력을 페이징
```

### Power user pattern (restricted shell escape)
```text
# 로그인 셸이 exec more ~/text.txt 인 감옥에서:
# 1) 접속 전 터미널 창을 파일보다 작게 → more가 --More-- 로 페이징 진입
# 2) more 안에서 'v' → editor(vi) 기동 ($SHELL 우회)
# 3) vi에서 :set shell=/bin/bash 후 :sh → 진짜 셸
#    (또는 :e /etc/target_file 로 셸 없이 파일 직접 열람)
```

## Pitfalls

> [!warning] Common Mistakes
> 1. **파일 ≤ 화면이면 페이징 안 함**: `cat`처럼 즉시 종료. 페이징을 기대하려면 파일이 화면보다 길어야(또는 창을 줄여야).
> 2. **크기는 시작 시점에 한 번 읽음**: 실행 후 터미널 resize는 반영 안 됨(`ioctl(TIOCGWINSZ)`는 기동 시). 페이징 유도는 **실행 전** 창 조절.
> 3. **`!command`는 `$SHELL`에 의존**: `$SHELL`이 정상 셸이 아니면(restricted 환경) 명령이 실행 안 되고 페이저가 재출력된다.
> 4. **`more` vs `less`**: `more`는 기본 전진 위주(구식), `less`는 양방향 스크롤·검색이 강력("less is more"). 스크롤백이 필요하면 `less`.

## Edge Cases
- 입력이 파이프(stdin)면 `b`(뒤로)가 제한된다(스트림은 되감기 불가).
- 바이너리를 넣으면 터미널이 깨질 수 있음 → `cat -v`/`strings` 선행.
- `$MORE` 환경변수로 기본 옵션 지정 가능.

## Related Tools

| Tool | Relationship |
|---|---|
| [[less]] | 상위 호환 페이저(양방향·검색 강화) — alternative |
| [[cat]] | 페이징 없는 전량 출력 — 짧은 파일용 complement |
| [[vi]] | `more`의 `v`가 기동하는 editor — chained(탈출 벡터) |

## Encountered In (Wargame Levels)
- [[Wargames/Bandit/Level_25]] (first use — restricted shell escape: `exec more` 감옥의 `v` 탈출)

## Concepts This Implements
- [[Concepts/Linux/Restricted_Shell_Escape]] (`!`/`v` = subprocess spawn 탈출 벡터)

## Quick Reference

```bash
more file                 # 한 화면씩
more +/pat file           # 패턴부터
cmd | more                # 파이프 페이징
# 페이징 중: Space=다음, /pat=검색, v=편집기, !cmd=셸, q=종료
```

> [!flashcard]
> **Q**: `more`의 가장 흔한 trap은?
> **A**: 파일이 화면(터미널 세로줄)보다 **짧으면 페이징 없이 즉시 종료**(cat처럼)한다는 것, 그리고 크기를 **시작 시점에 한 번만** 읽어 이후 resize가 무효라는 것. 페이징 유도는 실행 전 창 축소로.

---

## Background
`more`는 1978년 Daniel Halbert(UC Berkeley)가 만든 초기 페이저. 이름은 프롬프트 `--More--`에서. 전진 위주의 한계를 보완해 Mark Nudelman이 `less`("less is more")를 만들었다. 현대 리눅스의 `more`는 대개 util-linux 구현.

## External Refs
- man page: `man 1 more`
- GTFOBins: https://gtfobins.github.io/gtfobins/more/ (shell escape)
