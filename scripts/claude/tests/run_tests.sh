#!/usr/bin/env bash
# =====================================================================
# run_tests.sh — the vault's harness regression suite.
#   bash scripts/claude/tests/run_tests.sh
# Exit 0 = every guard behaves exactly as the policy claims.
#
# Suites:
#   1. guard_bash.py   — adversarial BLOCK / ASK / ALLOW corpus
#   2. guard_bash.py   — fail-mode probes (must never brick a session)
#   3. pre-commit      — secret + no-publish scan, in a THROWAWAY repo
#   4. guard_write.py  — vault placement / naming / credential probes
#   5. wiring          — settings.json parses, every hook script exists
# =====================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GUARD="$ROOT/scripts/claude/guard_bash.py"
WGUARD="$ROOT/scripts/claude/guard_write.py"
HOOK="$ROOT/scripts/pre-commit"
HERE="$ROOT/scripts/claude/tests"

TOTAL=0; FAILED=0
red()   { printf '\033[0;31m%s\033[0m\n' "$1"; }
green() { printf '\033[0;32m%s\033[0m\n' "$1"; }
head2() { printf '\n\033[1;36m── %s\033[0m\n' "$1"; }

record() {  # expect got label
    TOTAL=$((TOTAL + 1))
    if [ "$1" = "$2" ]; then
        printf '  %-6s %-6s ok    %s\n' "$1" "$2" "$3"
    else
        FAILED=$((FAILED + 1))
        printf '  \033[0;31m%-6s %-6s FAIL  %s\033[0m\n' "$1" "$2" "$3"
    fi
}

# --- 1. bash guard corpus --------------------------------------------
head2 "guard_bash.py — adversarial corpus"
while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    expect="${line%%|*}"; cmd="${line#*|}"
    json=$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
    out=$(printf '%s' "$json" | python3 "$GUARD" 2>/dev/null); rc=$?
    if [ "$rc" -eq 2 ]; then got=BLOCK
    elif printf '%s' "$out" | grep -q '"permissionDecision": *"ask"'; then got=ASK
    else got=ALLOW; fi
    record "$expect" "$got" "$cmd"
done < "$HERE/payloads_bash.txt"

# --- 1b. multi-line scripts (each LINE is its own command) ------------
head2 "guard_bash.py — multi-line scripts"
ml() {  # expect label <<heredoc command
    local expect="$1" label="$2"; local cmd; cmd=$(cat)
    json=$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
    out=$(printf '%s' "$json" | python3 "$GUARD" 2>/dev/null); rc=$?
    if [ "$rc" -eq 2 ]; then got=BLOCK
    elif printf '%s' "$out" | grep -q '"permissionDecision": *"ask"'; then got=ASK
    else got=ALLOW; fi
    record "$expect" "$got" "$label"
}

ml BLOCK "benign line 1 must not mask a bypass on line 2" <<'EOF'
echo "preparing the commit"
git commit --no-verify -m "x"
EOF

ml BLOCK "bypass hidden on the last line of a long script" <<'EOF'
cd /tmp
ls -la
echo staging
git add -A
git commit -n -m "x"
EOF

ml ALLOW "multi-line read-only script stays allowed" <<'EOF'
cd /tmp
ls -la
git status
grep -rn "no-verify" scripts/
EOF

ml ALLOW "line 1 mutator must not own line 6's path" <<'EOF'
SB=/tmp/sandbox
cp -R /some/repo/. "$SB"/
git -C "$SB" config user.name sandbox
echo done
test -x "$SB/.git/hooks/pre-commit" && echo present
EOF

ml BLOCK "line continuation is one command, not two" <<'EOF'
git commit \
  --no-verify -m "x"
EOF

ml ASK "quoted newline inside a commit message is not a separator" <<'EOF'
git commit -m "first line
second line mentions --no-verify in prose"
EOF

# --- 2. fail modes ----------------------------------------------------
head2 "guard_bash.py — fail modes (must fail OPEN on internal error)"
fm() { printf '%s' "$2" | python3 "$GUARD" >/dev/null 2>&1; record "0" "$?" "$1"; }
fm "empty stdin"            ""
fm "garbage stdin"          "not json at all"
fm "json but not an object" "[1,2,3]"
fm "no tool_input"          '{"tool_name":"Bash"}'
fm "null command"           '{"tool_name":"Bash","tool_input":{}}'
fm "non-string command"     '{"tool_name":"Bash","tool_input":{"command":42}}'
fm "unbalanced quote"       '{"tool_name":"Bash","tool_input":{"command":"echo \"oops"}}'
printf '  wrapper falls back when python3 is absent: '
json=$(jq -nc '{tool_name:"Bash",tool_input:{command:"git commit --no-verify -m x"}}')
printf '%s' "$json" | env PATH=/usr/bin:/bin bash "$ROOT/scripts/claude/bash-guard.sh" >/dev/null 2>&1
rc=$?; record 2 "$rc" "degraded fallback still blocks --no-verify"

# --- 3. pre-commit ----------------------------------------------------
head2 "pre-commit — secret scan + no-publish, throwaway repo"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
(
  cd "$TMP" || exit 1
  git init -q -b main . 2>/dev/null
  git config user.email t@t.local; git config user.name t
  git config commit.gpgsign false
) >/dev/null 2>&1

pc_case() {  # label expect path content
    local label="$1" expect="$2" path="$3" content="$4"
    ( cd "$TMP" && git reset -q 2>/dev/null
      find . -mindepth 1 -not -path './.git*' -delete 2>/dev/null
      mkdir -p "$(dirname "$path")" 2>/dev/null
      printf '%s\n' "$content" > "$path"
      git add -A -f -- "$path" >/dev/null 2>&1
      bash "$HOOK" >/dev/null 2>&1 )
    if [ $? -ne 0 ]; then got=BLOCK; else got=PASS; fi
    record "$expect" "$got" "$label"
}

# A synthetic 32-char credential, assembled at runtime from two short halves
# so this test file never itself contains a 30+ char run for the scanner to
# flag. (example / placeholder value — not a real password.)
SECRET="Yk7owGAcWjwM""VRwrTesJEwB7WVOiILLI"
pc_case "md + 32-char secret"        BLOCK "note.md"                    "password: $SECRET"
pc_case "md masked"                  PASS  "note.md"                    "password: <password masked>"
pc_case "md REDACTED"                PASS  "note.md"                    "password: [REDACTED]"
# These fixtures are assembled at runtime so the literal trigger strings never
# sit in this committed file (else the pre-commit scanner flags its own tests).
PKEY="-----BEGIN OPENSSH ""PRIVATE KEY-----"
AWSK="AKIA""IOSFODNN7EXAMPLE1"
pc_case "txt + SSH private key"      BLOCK "dump.txt"                   "$PKEY"
pc_case "sh + AWS key"               BLOCK "x.sh"                       "$AWSK"
pc_case "py + secret"                BLOCK "solve.py"                   "pw = '$SECRET'"
pc_case "json + secret"              BLOCK "cfg.json"                   "{\"pw\":\"$SECRET\"}"
pc_case "yaml + secret"              BLOCK "c.yml"                      "pw: $SECRET"
pc_case "no-extension + secret"      BLOCK "creds"                      "$SECRET"
pc_case "filename with space"        BLOCK "my note.md"                 "pw $SECRET"
pc_case "pwn.college path staged"    BLOCK "Wargames/Pwn_College/L1.md" "harmless text"
pc_case "clean note"                 PASS  "clean.md"                   "This is a normal writeup sentence."
pc_case "sha256 whitelisted"         PASS  "h.md"                       "sha256: e3b0c44298fc1c149afbf4c8996fb924"
pc_case "png binary untouched"       PASS  "img.png"                    "binaryish"

# --- 4. write guard ---------------------------------------------------
if [ -f "$WGUARD" ]; then
    head2 "guard_write.py — placement, naming, credentials"
    wg() {  # expect label file content
        local expect="$1" label="$2" file="$3" content="$4"
        json=$(jq -nc --arg f "$file" --arg c "$content" \
            '{tool_name:"Write",cwd:"'"$ROOT"'",tool_input:{file_path:$f,content:$c}}')
        out=$(printf '%s' "$json" | python3 "$WGUARD" 2>&1); rc=$?
        if [ "$rc" -eq 2 ]; then got=WARN; else got=OK; fi
        record "$expect" "$got" "$label"
    }
    wg WARN "unmasked credential in a level note" \
       "$ROOT/Wargames/Bandit/Level_09.md" "password is $SECRET"
    wg OK   "masked credential"  "$ROOT/Wargames/Bandit/Level_09.md" \
       "password is <password masked>"
    wg WARN "bad level filename" "$ROOT/Wargames/Bandit/level9.md"  "ok"
    wg OK   "good level filename" "$ROOT/Wargames/Bandit/Level_09.md" "ok"
    wg WARN "concept in unknown domain" "$ROOT/Concepts/Random/Foo.md" "ok"
    wg OK   "concept in known domain" "$ROOT/Concepts/Linux/Set_Uid.md" "ok"
    wg WARN "spaces in filename" "$ROOT/Concepts/Linux/My Note.md" "ok"
    wg OK   "tool note lowercase" "$ROOT/Tools/xxd.md" "ok"
    wg WARN "tool note uppercase" "$ROOT/Tools/Xxd.md" "ok"
    wg OK   "session log" "$ROOT/_Log/2026-08-16_session.md" "ok"
    wg WARN "session log bad date" "$ROOT/_Log/aug16_session.md" "ok"
    wg OK   "scratchpad is not policed" \
       "/private/tmp/claude-501/x/scratchpad/t.md" "password $SECRET"
    wg OK   "pwn.college local note allowed (write is fine; only publishing is not)" \
       "$ROOT/Wargames/Pwn_College/Level_01.md" "local only"
    wg OK   "per-game MOC inside a no-publish tree" \
       "$ROOT/Wargames/Pwn_College/MOC_Pwn_College.md" "local only"
    wg OK   "no-publish marker file" \
       "$ROOT/Wargames/Pwn_College/_LOCAL_ONLY.md" "local only"
    wg WARN "new undocumented top-level folder" \
       "$ROOT/Notes/Random.md" "ok"
fi

# --- 4b. index sentinel (state-based no-publish backstop) -------------
head2 "guard_index.sh — state-based no-publish backstop"
ISENT="$ROOT/scripts/claude/guard_index.sh"
if [ -f "$ISENT" ]; then
    IT=$(mktemp -d)
    ( cd "$IT" && git init -q -b main .
      git config user.email t@t.local; git config user.name t
      git config commit.gpgsign false
      mkdir -p Wargames/Pwn_College Wargames/Bandit
      echo x > Wargames/Bandit/Level_01.md
      echo secret > Wargames/Pwn_College/Level_01.md
      touch Wargames/Pwn_College/.nopublish
      git add -f Wargames/Bandit/Level_01.md >/dev/null 2>&1
      git commit -q -m init >/dev/null 2>&1 ) >/dev/null 2>&1

    # smuggle a no-publish file into the index the way the red team did, then
    # let the sentinel run and prove it unstages it.
    ( cd "$IT" && printf '%s\n' Wargames/Pwn_College/Level_01.md \
        | git update-index --add --stdin >/dev/null 2>&1 )
    staged_before=$(cd "$IT" && git diff --cached --name-only | grep -c Pwn_College)
    record 1 "$staged_before" "smuggle put a pwn path in the index (setup)"
    out=$(cd "$IT" && CLAUDE_PROJECT_DIR="$IT" bash "$ISENT" 2>&1); rc=$?
    record 2 "$rc" "sentinel warns (exit 2) on a poisoned index"
    staged_after=$(cd "$IT" && git diff --cached --name-only | grep -c Pwn_College)
    record 0 "$staged_after" "sentinel auto-unstaged the pwn path"

    # a clean index must not trip it
    ( cd "$IT" && echo ok > Wargames/Bandit/Level_02.md && git add Wargames/Bandit/Level_02.md >/dev/null 2>&1 )
    ( cd "$IT" && CLAUDE_PROJECT_DIR="$IT" bash "$ISENT" >/dev/null 2>&1 ); record 0 $? "clean index passes the sentinel"
    rm -rf "$IT"
fi

# --- 5. wiring --------------------------------------------------------
head2 "wiring — settings.json and hook registration"
jq -e . "$ROOT/.claude/settings.json" >/dev/null 2>&1
record 0 $? "settings.json parses"
for s in session-guard.sh bash-guard.sh write-guard.sh; do
    test -f "$ROOT/scripts/claude/$s"; record 0 $? "$s exists"
done
test -x "$ROOT/.git/hooks/pre-commit"; record 0 $? ".git/hooks/pre-commit installed+executable"
cmp -s "$ROOT/scripts/pre-commit" "$ROOT/.git/hooks/pre-commit"
record 0 $? ".git/hooks/pre-commit matches source"

# --- report -----------------------------------------------------------
printf '\n'
if [ "$FAILED" -eq 0 ]; then
    green "ALL GREEN — $TOTAL checks passed"
    exit 0
fi
red "$FAILED of $TOTAL checks FAILED"
exit 1
