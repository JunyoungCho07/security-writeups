---
tool: {{tool_name}}
category: file-discovery
man_section: 1
related: []
last_used: {{date}}
tags: [tool, linux]
---

# `{{tool_name}}`

## Purpose
<한 줄 정의. 이 도구가 해결하는 문제>

## Full Signature
```
{{tool_name}} [OPTIONS] <required_arg> [optional_arg]
```

| Position | Name | Type | Description |
|---|---|---|---|
| `<required_arg>` | <name> | <type> | <설명> |

## Common Flags (most-used 5-7)

| Flag | Long | Effect | Example |
|---|---|---|---|
| `-a` | `--all` | <effect> | `{{tool}} -a` |
| `-l` | `--long` | <effect> | `{{tool}} -l` |
| `-r` | `--recursive` | <effect> | `{{tool}} -r dir/` |

## Idiomatic Examples

### 기본 사용
```bash
$ {{tool_name}} <args>
<expected output>
```

### 자주 쓰는 조합
```bash
$ {{tool_name}} -<flag1> -<flag2> <args> | <other_tool>
```

### Power user pattern
```bash
$ <advanced one-liner>
```

## Pitfalls

> [!warning] Common Mistakes
> 1. <함정 1>
> 2. <함정 2>

## Edge Cases
- <edge case 1>
- <edge case 2>

## Related Tools

| Tool | Relationship |
|---|---|
| [[{{related_1}}]] | <relationship: complement / alternative / chained> |
| [[{{related_2}}]] | <> |

## Encountered In (Wargame Levels)
- [[Wargames/Bandit/Level_NN]] (first use)
- (other levels)

## Concepts This Implements
- [[Concepts/{{domain}}/{{concept}}]]

## Quick Reference

```bash
# Most common one-liners
{{tool}} -<flags> <args>      # what it does
{{tool}} ... | <chain>         # combo
```

> [!flashcard]
> **Q**: `{{tool_name}}`의 가장 흔한 trap은?
> **A**: <answer>

---

## Background
<도구의 역사적 맥락, 만든 사람, 흥미로운 일화 (있다면)>

## External Refs
- man page: `man {{tool_name}}`
- GNU docs: https://www.gnu.org/software/{{tool_name}}/
