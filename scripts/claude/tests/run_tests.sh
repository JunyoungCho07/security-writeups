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
#   3b. session-guard  — self-heal must never lie, in a THROWAWAY repo
#   3c. pre-push       — publication gate, bare remote + THROWAWAY clone
#   4. guard_write.py  — vault placement / naming / credential probes
#   4b. guard_index.sh — state-based no-publish backstop
#   5. wiring          — settings.json parses, hooks installed, signing key,
#                        and the docs/guards do not drift apart
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

# 2026-09-26 audit (L3 DL-1/DL-2): a comment line or a blank line must not
# swallow the commands that follow it.
ml BLOCK "a comment line must not hide the bypass on the next line" <<'EOF'
echo hi
# stage and commit
git commit --no-verify -m x
EOF

ml BLOCK "a blank line must not fold two commands into one segment" <<'EOF'
echo hi

git commit -n -m x
EOF

ml ASK "blank line before a plain commit still asks" <<'EOF'
git add Wargames/Bandit/Level_21.md

git commit -S -m "feat(bandit): level 21"
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
# A PATH of exactly the tools the fallback uses. /usr/bin:/bin is not enough:
# macOS ships /usr/bin/python3, so that PATH still ran the real engine and this
# check could not fail for the reason its label gives (2026-09-26 verify).
FB=$(mktemp -d)
for t in bash sh cat grep jq dirname tr head; do ln -s "$(command -v "$t")" "$FB/$t" 2>/dev/null; done
json=$(jq -nc '{tool_name:"Bash",tool_input:{command:"git commit --no-verify -m x"}}')
err=$(printf '%s' "$json" | env PATH="$FB" "$FB/bash" "$ROOT/scripts/claude/bash-guard.sh" 2>&1 >/dev/null)
rc=$?; record 2 "$rc" "degraded fallback still blocks --no-verify"
case "$err" in *"§1.2/§1.3"*) got=0 ;; *) got=1 ;; esac
record 0 "$got" "  …and it was the fallback that blocked (its own rule tag)"
rm -rf "$FB"

# --- 3. pre-commit ----------------------------------------------------
head2 "pre-commit — secret scan + no-publish, throwaway repo"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
# The throwaway carries what the hook relies on in the real repo: the real
# .gitignore (check-ignore backstop), a copy of the shared scanner at the
# path the hook resolves, core.ignorecase as on APFS. `base` is the reset
# point every case starts from.
(
  cd "$TMP" || exit 1
  git init -q -b main . 2>/dev/null
  # a noreply identity: the scanner treats any other user.email as a §1.5
  # identifier, and this very file quotes the throwaway's address
  git config user.email t@users.noreply.github.com; git config user.name t
  git config commit.gpgsign false
  git config core.ignorecase true
  cp "$ROOT/.gitignore" .
  mkdir -p scripts/claude && cp "$ROOT/scripts/claude/secret_scan.py" scripts/claude/
  git add .gitignore scripts && git commit -qm base && git tag base
) >/dev/null 2>&1

pc_reset() {  # back to `base`; working tree, .git/info and identity scrubbed
    git reset -q --hard base && git clean -qfdx
    rm -f .git/info/attributes .git/info/identifiers
    git config user.email t@users.noreply.github.com
}

pc_case() {  # label expect path content
    local label="$1" expect="$2" path="$3" content="$4"
    ( cd "$TMP" && pc_reset
      mkdir -p "$(dirname "$path")" 2>/dev/null
      printf '%s\n' "$content" > "$path"
      git add -A -f -- "$path" >/dev/null 2>&1
      bash "$HOOK" >/dev/null 2>&1 )
    if [ $? -ne 0 ]; then got=BLOCK; else got=PASS; fi
    record "$expect" "$got" "$label"
}

pc_cmd() {  # label expect setup-script (runs in $TMP; fixtures exported)
    local label="$1" expect="$2" setup="$3" got
    ( cd "$TMP" && pc_reset
      export ROOT SECRET PKEY AWSK LEV10 LEV10ND KRYW; bash -c "$setup" || exit 99
      env -u LC_ALL LANG=ko_KR.UTF-8 bash "$HOOK" ) >/dev/null 2>&1
    case $? in 0) got=PASS ;; 99) got=SETUP ;; *) got=BLOCK ;; esac   # SETUP = the case itself is broken
    record "$expect" "$got" "$label"
}

# Synthetic credentials, assembled at runtime from short pieces so this
# committed file never itself carries a run the scanner would flag — every
# piece is under 10 chars. (example / placeholder values — not real passwords.)
SECRET="Yk7owGAcW""jwMVRwrTe""sJEwB7WVO""iILLI"   # 32 chars: Bandit / Natas shape
LEV10="aB3kQ""x9TmW"                             # 10 chars, 3 classes: Leviathan shape
LEV10ND="ab3kq""x9tmw"                           # 10 chars, no uppercase: bare-line rule
KRYW="ZQXJK""VBNMP"                              # uppercase word: Krypton shape
PKEY="-----BEGIN OPENSSH ""PRIVATE KEY-----"
AWSK="AKIA""IOSFODNN7EXAMPLE1"
pc_case "md + 32-char secret"        BLOCK "note.md"                    "password: $SECRET"
pc_case "md masked"                  PASS  "note.md"                    "password: <password masked>"
pc_case "md REDACTED"                PASS  "note.md"                    "password: [REDACTED]"
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

# Sub-30-char wargame passwords (Leviathan/Narnia/Behemoth/Utumno = 10 alnum,
# Krypton = uppercase word) and the token-level whitelist (L1b audit).
pc_case "10-char pw after 'password:'"        BLOCK "note.md"  "password: $LEV10"
pc_case "10-char pw after 'pw ='"             BLOCK "note.md"  "pw = $LEV10"
pc_case "10-char pw on a bare line"           BLOCK "note.md"  "$LEV10"
pc_case "10-char pw after cat *_pass (fence)" BLOCK "note.md"  $'```bash\nleviathan1@gibson:~$ cat /etc/leviathan_pass/leviathan2\n'"$LEV10"$'\n```'
pc_case "10-char pw, no upper, bare line"     BLOCK "note.md"  "$LEV10ND"
pc_case "10-char pw, no upper, after cat"     BLOCK "note.md"  $'$ cat /etc/leviathan_pass/leviathan2\n'"$LEV10ND"
pc_case "uppercase word after 'password:'"    BLOCK "note.md"  "password: $KRYW"
pc_case "uppercase word after cat *_pass"     BLOCK "note.md"  $'$ cat /krypton/krypton1/krypton2_pass\n'"$KRYW"
pc_case "natas_webpass then bare token"       BLOCK "note.md"  $'$ cat /etc/natas_webpass/natas5\n'"$LEV10ND"
pc_case "32-char pw beside a <tag> (was blind)" BLOCK "note.md" "password: $SECRET (see <Level_02>)"
pc_case "32-char pw beside the word md5"      BLOCK "note.md"  "$SECRET md5"
pc_case "32-char pw beside a redirect < in > out" BLOCK "note.md" "$SECRET  # via ./bin < in > out"
pc_case "10-char pw beside a <tag>"           BLOCK "note.md"  "pw: $LEV10 (see <Level_02>)"
# false-positive guards — each is a shape that exists on the tree today
pc_case "mktemp dir name"                     PASS  "note.md"  "/tmp/tmp.$LEV10/pass"
pc_case "github handle in URL"                PASS  "note.md"  "https://github.com/$LEV10/security-writeups"
pc_case "github handle in ssh remote"         PASS  "setup.sh" "git remote add origin git@github.com:$LEV10/x.git"
pc_case "@handle mention"                     PASS  "README.md" "GitHub: [@$LEV10](https://github.com/$LEV10)"
pc_case "CamelCase+digits identifier"         PASS  "note.md"  "pwn.college Computing101 후"
pc_case "hex address"                         PASS  "note.md"  "call 0x0804851C <main>"
pc_case "level account after 'password ='"    PASS  "note.md"  "SSH password = bandit27의 password"
pc_case "level-0 public pw = account name"    PASS  "note.md"  "password: leviathan0"
pc_case "prose 'bypass = enabled'"            PASS  "note.md"  "bypass = enabled"
pc_case "prose 'password = correct'"          PASS  "note.md"  "password = correct"
pc_case "sha256 digest (token-safe, no word)" PASS  "note.md"  "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
pc_case "ssh public key body"                 PASS  "note.md"  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGxyz"
pc_case "base64 public prefix, exact"         PASS  "note.md"  "<Base64 string — e.g. VGhlIHBhc3N3b3JkIGlz...>"
pc_case "masked 10-char shape"                PASS  "note.md"  $'$ cat /etc/leviathan_pass/leviathan2\n<password masked>'
pc_case "test-fixture halves <10 chars"       PASS  "t.sh"     'SECRET="Yk7owGAcW""jwMVRwrTe""sJEwB7WVO""iILLI"'

# Index-walk, binary-detection and no-publish shapes (L1a audit). Each case
# is a shell setup run inside the throwaway, then the hook.
pc_cmd "H6a 0:name is scanned (raw -z, no :path parsing)" BLOCK 'printf "password: %s\n" "$SECRET" > 0:s.md; git add -f -- 0:s.md'
pc_cmd "H6b secret + NUL (binary judged on content)" BLOCK 'printf "password: %s\n\0" "$SECRET" > n.md; git add -f n.md'
pc_cmd "H6b private key + NUL"                   BLOCK 'printf "%s\n\0" "$PKEY" > k.md; git add -f k.md'
pc_cmd "H6b AWS key + NUL"                       BLOCK 'printf "%s\n\0" "$AWSK" > k.md; git add -f k.md'
pc_cmd "binary blob: 10-29 runs are not judged"  PASS  'printf "\x89PNG\r\n\x1a\n\0\x01\x02\x03\x04\x05\x06\x07\x0e\x0f\x10\x11\x12\x13\x14\x15\x16%s %s\n" "$LEV10" "$LEV10ND" > i.png; git add -f i.png'
pc_cmd "binary blob: 30+ run still caught"       BLOCK 'printf "\x89PNG\r\n\x1a\n\0\x01\x02\x03\x04\x05\x06\x07\x0e\x0f\x10\x11\x12\x13\x14\x15\x16%s\n" "$SECRET" > i.png; git add -f i.png'
# Encodings and whitelist shapes the 2026-09-26 verifier committed past the
# first v4.1 candidate: wide text, a stray NUL, <…> without a mask word, a
# non-hex token after a digest label, entities and zero-width characters.
pc_cmd "UTF-16LE 10-char pw"                     BLOCK 'python3 -c "import os; open(\"u.md\",\"wb\").write((\"password: \"+os.environ[\"LEV10\"]+\"\n\").encode(\"utf-16-le\"))"; git add -f u.md'
pc_cmd "UTF-16 (BOM) AWS key"                    BLOCK 'python3 -c "import os; open(\"u.md\",\"wb\").write((os.environ[\"AWSK\"]+\"\n\").encode(\"utf-16\"))"; git add -f u.md'
pc_cmd "UTF-16BE private key"                    BLOCK 'python3 -c "import os; open(\"u.md\",\"wb\").write((os.environ[\"PKEY\"]+\"\n\").encode(\"utf-16-be\"))"; git add -f u.md'
pc_cmd "UTF-32 32-char pw"                       BLOCK 'python3 -c "import os; open(\"u.md\",\"wb\").write((os.environ[\"SECRET\"]+\"\n\").encode(\"utf-32\"))"; git add -f u.md'
pc_cmd "UTF-16LE identifier"                     BLOCK 'printf "Jane Placeholder\n" > .git/info/identifiers; python3 -c "open(\"u.md\",\"wb\").write(\"by Jane Placeholder\n\".encode(\"utf-16-le\"))"; git add -f u.md'
pc_cmd "stray NUL beside a 10-char pw"           BLOCK 'printf "x\0y\npassword: %s\n" "$LEV10" > n.md; git add -f n.md'
pc_cmd "NUL inside a 10-char pw"                 BLOCK 'printf "password: %s\0%s\n" "${LEV10:0:5}" "${LEV10:5}" > n.md; git add -f n.md'
pc_cmd "32-char pw inside <…> (no mask word)"    BLOCK 'printf "<%s>\n" "$SECRET" > a.md; git add -f a.md'
pc_cmd "10-char pw inside <…> (no mask word)"    BLOCK 'printf "pw <%s>\n" "$LEV10" > a.md; git add -f a.md'
pc_cmd "non-hex token after md5: label"          BLOCK 'printf "md5: %s\n" "$SECRET" > a.md; git add -f a.md'
pc_cmd "32-char pw after SHA256: label"          BLOCK 'printf "SHA256:%s\n" "$SECRET" > a.md; git add -f a.md'
pc_cmd "HTML numeric entities render a secret"   BLOCK 'python3 -c "import os; open(\"h.md\",\"w\").write(\"\".join(\"&#%d;\" % ord(c) for c in os.environ[\"SECRET\"])+\"\n\")"; git add -f h.md'
pc_cmd "zero-width char inside a 10-char pw"     BLOCK 'python3 -c "import os; t=os.environ[\"LEV10\"]; open(\"z.md\",\"w\").write(\"password: \"+t[:4]+chr(0x200b)+t[4:]+\"\n\")"; git add -f z.md'
pc_cmd "ssh host-key fingerprint (43 b64) passes" PASS 'echo "ED25519 key fingerprint is SHA256:C2ihUBV7ihnV1wUXRb4RrEcLfXC5CXlhmAAM/urerLY." > f.md; git add f.md'
pc_cmd "YouTube id passes"                       PASS  'echo "https://www.youtube.com/watch?v=dQw4w9WgXcQ" > y.md; git add y.md'
pc_cmd "real md5 digest after label passes"      PASS  'echo "md5: d41d8cd98f00b204e9800998ecf8427e" > m.md; git add m.md'
# Round-2 verify: context exemptions are length-capped, NUL is judged over the
# whole blob, <…> exempts nothing, CR-only files have lines.
pc_cmd "32-char pw after youtu.be/ (cap 11)"     BLOCK 'printf "youtu.be/%s\n" "$SECRET" > y.md; git add -f y.md'
pc_cmd "32-char pw after github.com/ (cap 20)"   BLOCK 'printf "https://github.com/%s\n" "$SECRET" > g.md; git add -f g.md'
pc_cmd "32-char pw after user@ (cap 20)"         BLOCK 'printf "root@%s\n" "$SECRET" > g.md; git add -f g.md'
pc_cmd "UTF-16 block after an 8000-byte ASCII head" BLOCK 'python3 -c "import os; open(\"s.md\",\"wb\").write(b\"a\"*8100+b\"\n\"+(\"password: \"+os.environ[\"SECRET\"]+\"\n\").encode(\"utf-16-le\"))"; git add -f s.md'
pc_cmd "32-char pw in <…> beside 'example'"      BLOCK 'printf "<%s example>\n" "$SECRET" > a.md; git add -f a.md'
pc_cmd "CR-only file: bare pw after cat *_pass"  BLOCK 'printf "\$ cat /etc/leviathan_pass/leviathan2\r%s\r" "$LEV10ND" > c.md; git add -f c.md'
pc_cmd "combining grapheme joiner inside a pw"   BLOCK 'python3 -c "import os; open(\"j.md\",\"w\").write(chr(0x34f).join(os.environ[\"SECRET\"])+\"\n\")"; git add -f j.md'
pc_cmd "one-case hex pw after 'password:'"       BLOCK 'echo "password: 3f2""c8a""1b9""e4d" > h.md; git add -f h.md'
pc_cmd "ssh-rsa followed by a pw (no AAAA body)" BLOCK 'printf "ssh-rsa %s\n" "$SECRET" > k.md; git add -f k.md'
pc_cmd "ls /etc/natas_webpass/ lists an account" PASS  'printf "natas15@natas:~\$ ls /etc/natas_webpass/\nnatas16\n" > n.md; git add n.md'
pc_cmd "docker ps -q ids (one-case hex)"         PASS  'printf "\$ docker ps -q\n9504c1f3a2b7\n" > d.md; git add d.md'
pc_cmd "xxd -p dump line (one-case hex)"         PASS  'printf "89504e470d0a1a0a0000000d4948445200000100000001000806000000\n" > x.md; git add x.md'
pc_cmd "ssh-rsa public key body with + and /"    PASS  'echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7x+9aZkQm/Lp3Rt8vNw2YsHcJ4oXeT1bUfKiGdA5qW0rVz/Mn6lPjS3yBhCtF7uEg jy@mac" > k.md; git add k.md'
pc_cmd "SRI sha384 base64 digest"                PASS  'echo "<script integrity=\"sha384-oqVuAfXRKap7fdgcCY5uykM6+R9GqQ8K/uxy9rx7HNQlGYl1kPzQho1wx4JwY8wC\">" > s.md; git add s.md'
pc_cmd "YouTube shorts id"                       PASS  'echo "https://youtube.com/shorts/2YBtspm8j8M" > y.md; git add y.md'
pc_cmd "H6c symlink -> file with secret (T)"     BLOCK 'ln -s a.md l.md; git add l.md; git commit -qm l; rm l.md; printf "password: %s\n" "$SECRET" > l.md; git add l.md'
pc_cmd "H6d quoted name 한글/.env"                BLOCK 'mkdir -p 한글; echo h > 한글/.env; git add -f 한글/.env'
pc_cmd "H6d quoted name q\"uote/.env"            BLOCK 'mkdir -p "q\"uote"; echo h > "q\"uote/.env"; git add -f "q\"uote/.env"'
pc_cmd "H6d forbidden name, case folded"         BLOCK 'echo h > My_Secret_Notes.md; git add -f My_Secret_Notes.md'
pc_cmd "forbidden name: credentials.md"          BLOCK 'mkdir -p notes; echo h > notes/credentials.md; git add -f notes/credentials.md'
pc_cmd "a program named after secrets is a tool, not data" PASS 'mkdir -p t; echo "print(1)" > t/secret_tool.py; git add t/secret_tool.py'
pc_cmd "the harness's own sources are committable" PASS 'rm -rf scripts; cp -R "$ROOT/scripts" .; cp "$ROOT/.gitattributes" .; git add -A .gitattributes scripts'
pc_cmd "H6e1 .gitattributes -diff cannot hide"   BLOCK 'printf "*.md -diff\n" > .gitattributes; printf "password: %s\n" "$SECRET" > n.md; git add -f .gitattributes n.md'
pc_cmd "H6e1 .gitattributes binary cannot hide"  BLOCK 'printf "*.md binary\n" > .gitattributes; printf "password: %s\n" "$SECRET" > n.md; git add -f .gitattributes n.md'
pc_cmd "H6e1 .git/info/attributes cannot hide"   BLOCK 'printf "* -diff\n" > .git/info/attributes; printf "password: %s\n" "$SECRET" > n.md; git add -f n.md'
pc_cmd "H6e2 invalid UTF-8 byte on secret line"  BLOCK 'printf "password: %s \xe9\n" "$SECRET" > l.md; git add -f l.md'
pc_cmd "H6e3 'example' on the line"              BLOCK 'printf "password: %s (for example)\n" "$SECRET" > w.md; git add -f w.md'
pc_cmd "H6e3 autolink on the line"               BLOCK 'printf "password: %s see <https://x.y>\n" "$SECRET" > w.md; git add -f w.md'
pc_cmd "fingerprint label still passes"          PASS  'echo "fingerprint SHA256:AbCdEfGhIjKlMnOpQrStUvWxYz0123456789abcdefg" > c.md; git add c.md'
pc_cmd "token inside <mask> still passes"        PASS  'echo "cookie: <session-token-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA>" > c.md; git add c.md'
pc_cmd "gitlink entry does not crash"            PASS  'git update-index --add --cacheinfo 160000,$(git rev-parse HEAD),sub'
pc_cmd "rename keeps scanning the destination"   BLOCK 'printf "password: %s\n" "$SECRET" > a.md; git add a.md; git commit -qm a; git mv a.md b.md'
pc_cmd "H1 lowercase pwn path via update-index"  BLOCK 'mkdir -p Wargames/Pwn_College; echo h > Wargames/Pwn_College/L1.md; git update-index --add wargames/pwn_college/L1.md'
pc_cmd "H1 UPPER GoN via --cacheinfo"            BLOCK 'b=$(echo h | git hash-object -w --stdin); git update-index --add --cacheinfo 100644,$b,WARGAMES/GON/L1.md'
pc_cmd "H2 GoN canonical"                        BLOCK 'mkdir -p Wargames/GoN; echo h > Wargames/GoN/L1.md; git add -f Wargames/GoN/L1.md'
pc_cmd "H2 marker-only dir, nested"              BLOCK 'mkdir -p Wargames/X/s/d; : > Wargames/X/.nopublish; echo h > Wargames/X/s/d/n.md; git add -f Wargames/X/s/d/n.md'
pc_cmd "H2 marker is a directory"                BLOCK 'mkdir -p Dm/.nopublish; echo h > Dm/n.md; git add -f Dm/n.md'
pc_cmd "ignored *.log force-staged"              BLOCK 'echo h > run.log; git add -f run.log'
pc_cmd "ignored settings.local.json force-staged" BLOCK 'mkdir -p .claude; echo "{}" > .claude/settings.local.json; git add -f .claude/settings.local.json'
pc_cmd "negated .obsidian/app.json is fine"      PASS  'mkdir -p .obsidian; echo "{}" > .obsidian/app.json; git add .obsidian/app.json'
pc_cmd "ordinary vault note is fine"             PASS  'mkdir -p Wargames/Bandit; echo "harmless" > Wargames/Bandit/Level_01.md; git add Wargames/Bandit/Level_01.md'

# Personal identifiers (§1.5): <git-dir>/info/identifiers + git user.email.
pc_cmd "identifier from .git/info/identifiers"   BLOCK 'printf "Jane Placeholder\n" > .git/info/identifiers; echo "written by Jane Placeholder" > n.md; git add n.md'
pc_cmd "identifier, different case"              BLOCK 'printf "Jane Placeholder\n" > .git/info/identifiers; echo "JANE PLACEHOLDER was here" > n.md; git add n.md'
pc_cmd "identifiers file absent: same note passes" PASS 'echo "written by Jane Placeholder" > n.md; git add n.md'
pc_cmd "comment / blank / <3-char lines ignored" PASS  'printf "# Jane Placeholder\n\nJa\n" > .git/info/identifiers; echo "written by Jane Placeholder" > n.md; git add n.md'
pc_cmd "git user.email is an identifier"         BLOCK 'git config user.email jane@example.invalid; echo "mail jane@example.invalid for help" > n.md; git add n.md'
pc_cmd "noreply user.email is not"               PASS  'echo "mail t@users.noreply.github.com for help" > n.md; git add n.md'

# The content gate must fail CLOSED, never degrade.
pc_cmd "scanner file missing: commit blocked"    BLOCK 'rm -f scripts/claude/secret_scan.py; echo clean > c.md; git add c.md'
pc_cmd "scanner internal error: commit blocked"  BLOCK 'printf "import sys; sys.exit(3)\n" > scripts/claude/secret_scan.py; echo clean > c.md; git add c.md'
pc_cmd "scanner present, clean note: passes"     PASS  'echo clean > c.md; git add c.md'

# Performance guard: a long clean note must not make committing painful.
( cd "$TMP" && pc_reset
  awk 'BEGIN{for(i=1;i<=2000;i++) print "Line " i " of a perfectly ordinary writeup sentence."}' > big.md
  git add big.md ) >/dev/null 2>&1
t0=$(date +%s); ( cd "$TMP" && bash "$HOOK" >/dev/null 2>&1 ); rc=$?; t1=$(date +%s)
record 0 "$rc" "2000-line clean note passes"
[ $((t1 - t0)) -lt 5 ]; record 0 $? "  …in under 5 s (took $((t1 - t0)) s)"

# --- 3b. session-guard ------------------------------------------------
head2 "session-guard.sh — self-heal must never lie, throwaway repo"
SG="$ROOT/scripts/claude/session-guard.sh"
SGT=$(mktemp -d); SGG="$SGT/gitconfig"
# Every git call here runs against an ISOLATED global config so the
# operator's signing key and keyring are never consulted and no commit is
# ever signed. The throwaway carries the hook sources and the scanner, as
# the real repo does, so "a secret commit is blocked afterwards" is real.
sg() {  # snippet — runs in the throwaway, isolated; prints output, returns rc
    ( cd "$SGT" && export GIT_CONFIG_GLOBAL="$SGG" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
        CLAUDE_PROJECT_DIR="$SGT" SGT ROOT SG SECRET && bash -c "$1" 2>&1 )
}
ms_now() { python3 -c 'import time; print(int(time.time() * 1000))'; }
( export GIT_CONFIG_GLOBAL="$SGG" GIT_CONFIG_NOSYSTEM=1
  git config --file "$SGG" user.name t
  git config --file "$SGG" user.email t@users.noreply.github.com
  cd "$SGT" && git init -q -b main . && mkdir -p scripts/claude Wargames/Pwn_College
  cp "$ROOT/scripts/pre-commit" "$ROOT/scripts/pre-push" scripts/
  cp "$ROOT/scripts/claude/secret_scan.py" scripts/claude/
  cp "$ROOT/.gitignore" .
  echo x > a.md && git add -A && git commit -qm init ) >/dev/null 2>&1
has() { printf '%s' "$1" | grep -qF -- "$2"; }   # fixed string: labels carry [ ] and ( )

sg_case() {  # label want-substring shape   (+ "a secret commit is blocked afterwards")
    local label="$1" want="$2" shape="$3" out got
    sg "rm -rf .git/hooks/pre-commit; $shape" >/dev/null 2>&1
    out=$(sg 'bash "$SG" 2>/dev/null')
    has "$out" "$want"; record 0 $? "$label"
    sg 'printf "password: %s\n" "$SECRET" > leak.md && git add leak.md && git commit -qm leak' >/dev/null 2>&1
    record 1 "$?" "  …and a secret commit is blocked afterwards"
    sg 'git reset -q --hard HEAD; rm -f leak.md' >/dev/null 2>&1
}
sg_case "missing hook is installed"               "pre-commit hook: INSTALLED" ':'
sg_case "symlink -> /dev/null is replaced"        "pre-commit hook: INSTALLED" 'ln -s /dev/null .git/hooks/pre-commit'
sg_case "dangling symlink is replaced"            "pre-commit hook: INSTALLED" 'ln -s /nonexistent/x .git/hooks/pre-commit'
sg_case "directory at the hook path is replaced"  "pre-commit hook: INSTALLED" 'mkdir .git/hooks/pre-commit'
sg_case "non-executable hook is re-armed"         "pre-commit hook: INSTALLED" 'cp scripts/pre-commit .git/hooks/pre-commit; chmod -x .git/hooks/pre-commit'
sg_case "stale hook content is refreshed"         "pre-commit hook: INSTALLED" 'printf "#!/bin/sh\nexit 0\n" > .git/hooks/pre-commit; chmod +x .git/hooks/pre-commit'
sg_case "marker restored in Pwn_College"          "no-publish markers RESTORED in: Wargames/Pwn_College" 'rm -f Wargames/Pwn_College/.nopublish'

# a healthy repo: one line, every hook ok, marker ok, no identifiers
out=$(sg 'bash "$SG" 2>/dev/null')
record 1 "$(printf '%s\n' "$out" | grep -c .)" "output is ONE line"
has "$out" "hooks ok: pre-commit pre-merge-commit pre-push"; record 0 $? "all three hooks reported ok"
has "$out" "no-publish markers: ok";                          record 0 $? "marker present: ok"
has "$out" "identifiers: none configured";                    record 0 $? "no identifiers file: none configured"
has "$out" "gpg signing: NOT CONFIGURED";                     record 0 $? "isolated config: signing NOT CONFIGURED (never 'ok')"
sg 'test ! -e "$(git rev-parse --git-path info/identifiers)"'; record 0 $? "guard never creates the identifiers file"
for h in pre-commit pre-merge-commit pre-push; do
    sg "test -f .git/hooks/$h && test ! -L .git/hooks/$h && test -x .git/hooks/$h"; record 0 $? "$h: regular, executable"
done
sg 'cmp -s scripts/pre-commit .git/hooks/pre-merge-commit'; record 0 $? "pre-merge-commit is a byte copy of scripts/pre-commit"
sg 'cmp -s scripts/pre-push .git/hooks/pre-push';           record 0 $? "pre-push is a byte copy of scripts/pre-push"

# the other two managed hooks heal the same way
sg 'rm -f .git/hooks/pre-push .git/hooks/pre-merge-commit; ln -s /dev/null .git/hooks/pre-push' >/dev/null 2>&1
out=$(sg 'bash "$SG" 2>/dev/null')
has "$out" "pre-push hook: INSTALLED";         record 0 $? "pre-push symlink is replaced"
has "$out" "pre-merge-commit hook: INSTALLED"; record 0 $? "missing pre-merge-commit is installed"

# install failure is reported as FAILED/DISARMED, never ok
sg 'rm -f .git/hooks/pre-commit; chmod 555 .git/hooks' >/dev/null 2>&1
out=$(sg 'bash "$SG" 2>/dev/null')
sg 'chmod 755 .git/hooks' >/dev/null 2>&1
has "$out" "pre-commit hook: FAILED";  record 0 $? "read-only hooks dir: FAILED reported"
has "$out" "DISARMED";                 record 0 $? "  …and named DISARMED"
has "$out" "hooks ok: pre-commit";     record 1 $? "  …never 'ok' for the missing hook"
sg 'bash "$SG"' >/dev/null 2>&1        # heal before going on

# core.hooksPath redirects git away from .git/hooks
sg 'git config core.hooksPath /tmp/nowhere' >/dev/null 2>&1
out=$(sg 'bash "$SG" 2>/dev/null')
sg 'git config --unset core.hooksPath' >/dev/null 2>&1
has "$out" "DISARMED";  record 0 $? "core.hooksPath set: reported DISARMED"
has "$out" "hooks ok";  record 1 $? "  …and no hook is called ok"

# an unexpected hook is named, not deleted
sg 'printf "#!/bin/sh\nexit 0\n" > .git/hooks/pre-receive; chmod +x .git/hooks/pre-receive' >/dev/null 2>&1
out=$(sg 'bash "$SG" 2>/dev/null')
has "$out" "unexpected hook(s): pre-receive"; record 0 $? "stray pre-receive is reported"
sg 'test -f .git/hooks/pre-receive';          record 0 $? "  …and left in place"
sg 'rm -f .git/hooks/pre-receive' >/dev/null 2>&1
out=$(sg 'bash "$SG" 2>/dev/null')
has "$out" "unexpected hook"; record 1 $? "  …samples alone are not reported"

# identifiers: a count, never the contents
sg 'printf "# comment\n\nJane Placeholder\nJa\nplaceholder@example.invalid\n" > "$(git rev-parse --git-path info/identifiers)"' >/dev/null 2>&1
out=$(sg 'bash "$SG" 2>/dev/null')
has "$out" "identifiers: 2 entries"; record 0 $? "identifiers counted (comment / blank / <3-char lines skipped)"
has "$out" "Jane";                   record 1 $? "  …contents never printed"
sg 'rm -f "$(git rev-parse --git-path info/identifiers)"' >/dev/null 2>&1

# signing: every misconfiguration is named; nothing here touches a real key
sg 'git config commit.gpgsign true; git config user.signingkey DEADBEEFDEADBEEF' >/dev/null 2>&1
out=$(sg 'bash "$SG" 2>/dev/null'); has "$out" "WRONG KEY"; record 0 $? "wrong signing key is named"
sg 'git config user.signingkey E81313B5B651B0D9; git config gpg.format ssh' >/dev/null 2>&1
out=$(sg 'bash "$SG" 2>/dev/null'); has "$out" "WRONG FORMAT"; record 0 $? "gpg.format=ssh is named"
sg 'git config --unset gpg.format; git config gpg.program /usr/bin/true' >/dev/null 2>&1
out=$(sg 'bash "$SG" 2>/dev/null'); has "$out" "is not GnuPG"; record 0 $? "gpg.program that is not GnuPG is named"
# a stand-in gpg: announces itself as GnuPG, has no secret key
sg 'mkdir -p bin; printf "#!/bin/sh\ncase \"\$1\" in --version) echo \"gpg (GnuPG) 9.9.9\";; *) exit 2;; esac\n" > bin/gpg; chmod +x bin/gpg; git config gpg.program "$SGT/bin/gpg"' >/dev/null 2>&1
out=$(sg 'bash "$SG" 2>/dev/null'); has "$out" "NOT IN KEYRING"; record 0 $? "missing secret key is named"
# …and one that has it
sg 'printf "#!/bin/sh\ncase \"\$1\" in --version) echo \"gpg (GnuPG) 9.9.9\";; *) exit 0;; esac\n" > bin/gpg' >/dev/null 2>&1
out=$(sg 'bash "$SG" 2>/dev/null'); has "$out" "gpg signing: ok (key E81313B5B651B0D9, secret present)"; record 0 $? "declared key + secret present: ok"
sg 'git config user.signingkey e81313b5b651b0d9' >/dev/null 2>&1
out=$(sg 'bash "$SG" 2>/dev/null'); has "$out" "gpg signing: ok"; record 0 $? "lowercase key id is the same key"
sg 'git config user.signingkey 55DF1D03939E807157D42293E81313B5B651B0D9' >/dev/null 2>&1
out=$(sg 'bash "$SG" 2>/dev/null'); has "$out" "gpg signing: ok"; record 0 $? "full fingerprint ending in the key id is accepted"
sg 'git config user.signingkey 0123456789ABCDEF0123456789ABCDEF01234567' >/dev/null 2>&1
out=$(sg 'bash "$SG" 2>/dev/null'); has "$out" "WRONG KEY"; record 0 $? "unrelated 40-hex fingerprint is WRONG KEY"
sg 'git config user.signingkey E81313B5B651B0D9' >/dev/null 2>&1
t0=$(ms_now); sg 'bash "$SG"' >/dev/null 2>&1; t1=$(ms_now)
[ $((t1 - t0)) -lt 1000 ]; record 0 $? "full run (hooks + gpg stand-in + markers) in under 1 s (took $((t1 - t0)) ms)"
sg 'git config commit.gpgsign false; git config --unset user.signingkey; git config --unset gpg.program' >/dev/null 2>&1
grep -c 'HARNESS_' "$SG" | { read -r n; record 0 "$n" "no HARNESS_* env override in the source"; }
rm -rf "$SGT"

# --- 3c. pre-push -----------------------------------------------------
head2 "pre-push — publication gate, bare remote + throwaway clone"
PPHOOK="$ROOT/scripts/pre-push"
PT=$(mktemp -d); PPG="$PT/gitconfig"
# Isolated global config (no signing key, no keyring); a HOOKLESS seed clone
# publishes the "already public" history — the hook sources, the scanner and
# the real .gitignore, as tracked in the real repo — then the hooked clone
# gets its three hooks installed by session-guard.sh itself.
pp() {  # snippet — runs in the hooked clone, isolated; prints output, returns rc
    ( cd "$PT/clone" && export GIT_CONFIG_GLOBAL="$PPG" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
        PT ROOT SECRET PKEY AWSK && bash -c "$1" 2>&1 )
}
FRESH='git checkout -q main; git reset -q --hard origin/main; git clean -qfdx'
( export GIT_CONFIG_GLOBAL="$PPG" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
  git config --file "$PPG" user.name t
  git config --file "$PPG" user.email t@users.noreply.github.com
  git config --file "$PPG" init.defaultBranch main
  git config --file "$PPG" advice.detachedHead false
  git init -q --bare "$PT/remote.git"
  git clone -q "$PT/remote.git" "$PT/seed"
  cd "$PT/seed" && mkdir -p scripts/claude
  cp "$ROOT/.gitignore" .; cp "$ROOT/scripts/pre-commit" "$ROOT/scripts/pre-push" scripts/
  cp "$ROOT/scripts/claude/secret_scan.py" scripts/claude/
  printf '# seed\n' > README.md
  git add -A && git commit -qm 'seed: already public (unsigned)' && git push -q origin main \
    && git branch -q stale && git push -q origin stale
  git clone -q "$PT/remote.git" "$PT/clone"
  cd "$PT/clone" && git config core.ignorecase true
  CLAUDE_PROJECT_DIR="$PT/clone" bash "$ROOT/scripts/claude/session-guard.sh"
) >/dev/null 2>&1
SEED=$(git -C "$PT/seed" rev-parse HEAD)
pp 'cmp -s "$ROOT/scripts/pre-push" .git/hooks/pre-push';           record 0 $? "session-guard installed pre-push in the clone"
pp 'cmp -s "$ROOT/scripts/pre-commit" .git/hooks/pre-merge-commit'; record 0 $? "session-guard installed pre-merge-commit in the clone"
pp 'git config --get commit.gpgsign'; record 1 $? "isolation: commit.gpgsign unset in the throwaway (nothing is ever signed)"

# A: unsigned clean commit → blocked, only the new commit inspected
pp "$FRESH; printf 'clean note\n' > note.md; git add note.md; git commit -q -m 'A: unsigned clean commit'" >/dev/null 2>&1
A_SHA=$(pp 'git rev-parse --short HEAD')
out=$(pp 'git push origin main'); rc=$?
record 1 "$rc" "A unsigned clean commit: push refused"
has "$out" "UNSIGNED / UNVERIFIED COMMIT $A_SHA"; record 0 $? "A names the unsigned commit"
has "$out" "NO signature — A: unsigned clean commit"; record 0 $? "A subject survives empty %GK/%GF/%GP fields"
has "$out" "${SEED:0:7}"; record 1 $? "A already-remote seed commit is NOT re-checked"
has "$out" "1 commit(s) new"; record 0 $? "A exactly 1 commit inspected"
[ "$(git -C "$PT/remote.git" rev-parse main)" = "$SEED" ]; record 0 $? "A remote main unchanged"

# B: no-publish path, pre-commit bypassed → blocked
pp "$FRESH; mkdir -p Wargames/Pwn_College; printf 'local only\n' > Wargames/Pwn_College/Level_01.md; git add -f Wargames/Pwn_College/Level_01.md" >/dev/null 2>&1
pp 'bash .git/hooks/pre-commit' >/dev/null 2>&1; record 1 $? "B control: pre-commit blocks the path"
pp "git commit -q --no-verify -m 'B: bypassed'" >/dev/null 2>&1
out=$(pp 'git push origin main'); rc=$?
record 1 "$rc" "B no-publish path in history: push refused"
has "$out" "NO-PUBLISH PATH"; record 0 $? "B NO-PUBLISH reported"
has "$out" "Wargames/Pwn_College/Level_01.md"; record 0 $? "B offending path listed"

# C: case-variant no-publish path via plumbing → blocked by both layers
pp "$FRESH; b=\$(printf 'x\n' | git hash-object -w --stdin); git update-index --add --cacheinfo 100644,\$b,WARGAMES/PWN_COLLEGE/L2.md" >/dev/null 2>&1
pp 'bash .git/hooks/pre-commit' >/dev/null 2>&1; record 1 $? "C control: pre-commit blocks the case variant (was a gap)"
pp "git commit -q --no-verify -m 'C: case variant'" >/dev/null 2>&1
out=$(pp 'git push origin main'); rc=$?
record 1 "$rc" "C case-variant path in history: push refused"
has "$out" "WARGAMES/PWN_COLLEGE/L2.md"; record 0 $? "C case-variant path reported"

# D: dir carrying an untracked .nopublish marker → blocked
pp "$FRESH; mkdir -p Wargames/Private_Game; : > Wargames/Private_Game/.nopublish; printf 'x\n' > Wargames/Private_Game/L1.md; git add Wargames/Private_Game/L1.md" >/dev/null 2>&1
pp 'bash .git/hooks/pre-commit' >/dev/null 2>&1; record 1 $? "D control: pre-commit blocks the marker dir"
pp "git commit -q --no-verify -m 'D: marker dir'" >/dev/null 2>&1
out=$(pp 'git push origin main'); rc=$?
record 1 "$rc" "D marker-dir path in history: push refused"
has "$out" "Wargames/Private_Game/L1.md"; record 0 $? "D marker-dir path reported"

# E: delete push → allowed
out=$(pp "$FRESH; git push origin --delete stale"); rc=$?
record 0 "$rc" "E delete push allowed"
has "$out" "delete refs/heads/stale"; record 0 $? "E hook saw the delete"
record 0 "$(git -C "$PT/remote.git" for-each-ref refs/heads/stale | grep -c .)" "E branch gone on remote"

# F: new branch at already-remote commits → allowed (range empty)
out=$(pp "$FRESH; git branch -q newbr origin/main; git push origin newbr"); rc=$?
record 0 "$rc" "F new branch with nothing new: allowed"
has "$out" "nothing new for the remote"; record 0 $? "F range computed as empty"

# G: new branch with a new unsigned commit → blocked, seed excluded
pp "$FRESH; git checkout -q -b feat origin/main; printf 'y\n' > f.md; git add f.md; git commit -q -m 'G: unsigned on new branch'" >/dev/null 2>&1
G_SHA=$(pp 'git rev-parse --short HEAD')
out=$(pp 'git push origin feat'); rc=$?
record 1 "$rc" "G new branch with an unsigned commit: refused"
has "$out" "1 commit(s) new"; record 0 $? "G only the new commit inspected (--not --remotes)"
has "$out" "$G_SHA"; record 0 $? "G names the commit"

# H: force push (rewritten remote tip) → force announced, only the rewrite inspected
pp "$FRESH; git commit -q --amend --allow-empty --no-verify -m 'H: rewritten seed'" >/dev/null 2>&1
H_SHA=$(pp 'git rev-parse --short HEAD')
out=$(pp 'git push --force origin main'); rc=$?
record 1 "$rc" "H force push of an unsigned rewrite: refused"
has "$out" "FORCE PUSH"; record 0 $? "H force push announced"
has "$out" "1 commit(s) new"; record 0 $? "H only the rewritten commit inspected"
has "$out" "$H_SHA"; record 0 $? "H names the rewritten commit"

# I: 32-char secret, pre-commit bypassed → blocked; token never echoed
pp "$FRESH; printf 'password: %s\n' \"\$SECRET\" > note.md; git add note.md" >/dev/null 2>&1
pp 'bash .git/hooks/pre-commit' >/dev/null 2>&1; record 1 $? "I control: pre-commit blocks the secret"
pp "git commit -q --no-verify -m 'I: bypassed secret'" >/dev/null 2>&1
out=$(pp 'git push origin main'); rc=$?
record 1 "$rc" "I secret in a pushed blob: refused"
has "$out" "SUSPECT CREDENTIAL"; record 0 $? "I credential reported"
has "$out" "note.md: line 1"; record 0 $? "I file and line named"
has "$out" "$SECRET"; record 1 $? "I full token NOT echoed"

# I2: secret added then masked within the range (tip clean) → still blocked
pp "$FRESH; printf 'password: %s\n' \"\$SECRET\" > note.md; git add note.md; git commit -q --no-verify -m 'I2a: secret in'; printf 'password: <password masked>\n' > note.md; git add note.md; git commit -q -m 'I2b: masked at tip'" >/dev/null 2>&1
out=$(pp 'git push origin main'); rc=$?
record 1 "$rc" "I2 secret in an intermediate commit: refused (history, not tip)"
has "$out" "SUSPECT CREDENTIAL"; record 0 $? "I2 credential found in history"

# J / K: vendor key patterns
pp "$FRESH; printf 'key=%s\n' \"\$AWSK\" > cfg.txt; git add cfg.txt; git commit -q --no-verify -m 'J: api key'" >/dev/null 2>&1
out=$(pp 'git push origin main'); rc=$?
record 1 "$rc" "J cloud/API key pattern: refused"
has "$out" "cfg.txt: line 1 [api-key]"; record 0 $? "J api-key rule named"
pp "$FRESH; printf '%s\n' \"\$PKEY\" > k.txt; git add k.txt; git commit -q --no-verify -m 'K: private key'" >/dev/null 2>&1
out=$(pp 'git push origin main'); rc=$?
record 1 "$rc" "K private key block: refused"
has "$out" "k.txt: line 1 [private-key]"; record 0 $? "K private-key rule named"

# L: forbidden filename (also .gitignore-excluded: *_rsa)
pp "$FRESH; mkdir -p keys; printf 'x\n' > keys/server_rsa; git add -f keys/server_rsa; git commit -q --no-verify -m 'L: forbidden name'" >/dev/null 2>&1
out=$(pp 'git push origin main'); rc=$?
record 1 "$rc" "L forbidden filename: refused"
has "$out" "FORBIDDEN FILENAME in pushed history: keys/server_rsa"; record 0 $? "L names the file"
has "$out" "IGNORED PATH"; record 0 $? "L …and it is also an ignored path (.gitignore backstop)"
pp "$FRESH; mkdir -p t; printf 'print(1)\n' > t/secret_tool.py; git add t/secret_tool.py; git commit -q -m 'L2: a program named after secrets'" >/dev/null 2>&1
out=$(pp 'git push origin main')
has "$out" "FORBIDDEN FILENAME"; record 1 $? "L2 a program named after secrets is not a forbidden name"

# M: clean commit → the SIGNATURE violation only (no false positives)
pp "$FRESH; printf 'A normal writeup sentence with sha256: e3b0c44298fc1c149afbf4c8996fb924\n' > clean.md; git add clean.md; git commit -q -m 'M: clean'" >/dev/null 2>&1
out=$(pp 'git push origin main'); rc=$?
record 1 "$rc" "M clean unsigned commit: refused for the signature only"
has "$out" "PUSH BLOCKED: 1 violation"; record 0 $? "M exactly one violation"
for w in "NO-PUBLISH" "IGNORED PATH" "SUSPECT" "FORBIDDEN" "WRONG SIGNING" "MESSAGE" "scanner"; do
    has "$out" "$w"; record 1 $? "M no false positive: $w"
done

# O: multi-ref push → every ref evaluated, violations aggregated
pp "$FRESH; printf 'o\n' > o.md; git add o.md; git commit -q -m 'O: main'; git checkout -q -b br2 origin/main; printf 'p\n' > p.md; git add p.md; git commit -q -m 'O: br2'; git checkout -q main" >/dev/null 2>&1
out=$(pp 'git push origin main br2'); rc=$?
record 1 "$rc" "O multi-ref push: refused"
has "$out" "refs/heads/main"; record 0 $? "O main evaluated"
has "$out" "refs/heads/br2";  record 0 $? "O br2 evaluated"
has "$out" "2 violation";     record 0 $? "O violations aggregated across refs"

# P: push by bare URL (no remote name), nothing new → allowed
out=$(pp "$FRESH; git branch -q -f anon origin/main; git push \"\$PT/remote.git\" anon"); rc=$?
record 0 "$rc" "P push by URL with nothing new: allowed"
has "$out" "nothing new"; record 0 $? "P falls back to --not --remotes (any remote)"

# Q: remote tip unknown locally (pushed from elsewhere) + --force → fallback range, refused
( cd "$PT/seed" && export GIT_CONFIG_GLOBAL="$PPG" GIT_CONFIG_NOSYSTEM=1
  git fetch -q origin && git reset -q --hard origin/main && printf 'z\n' > z.md && git add z.md \
  && git commit -q -m 'seed: elsewhere' && git push -q origin main ) >/dev/null 2>&1
X=$(git -C "$PT/seed" rev-parse HEAD)
pp "$FRESH; printf 'q\n' > q.md; git add q.md; git commit -q -m 'Q: local'" >/dev/null 2>&1
Q_SHA=$(pp 'git rev-parse --short HEAD')
pp "git cat-file -e '$X^{commit}'" >/dev/null 2>&1; record 128 $? "Q setup: remote tip absent from the clone"
out=$(pp 'git push --force origin main'); rc=$?
record 1 "$rc" "Q force over an unknown remote tip: refused"
has "$out" "1 commit(s) new"; record 0 $? "Q fallback range = the local commit only"
has "$out" "$Q_SHA"; record 0 $? "Q names the commit"
[ "$(git -C "$PT/remote.git" rev-parse main)" = "$X" ]; record 0 $? "Q remote main not overwritten"
( cd "$PT/clone" && export GIT_CONFIG_GLOBAL="$PPG" GIT_CONFIG_NOSYSTEM=1 && git fetch -q origin ) >/dev/null 2>&1

# R: no skip switch — env vars are ignored, the source has none
pp "$FRESH; printf 'r\n' > r.md; git add r.md; git commit -q -m 'R: unsigned'" >/dev/null 2>&1
pp 'PREPUSH_SKIP=1 SKIP=1 NO_VERIFY=1 HARNESS_SIGNING_KEY= git push origin main' >/dev/null 2>&1
record 1 $? "R env vars do not bypass"
grep -cE 'SKIP|BYPASS|ALLOW_UNSIGNED|getenv|HARNESS_|\$\{?[A-Z_]*SKIP' "$PPHOOK" | { read -r n; record 0 "$n" "R no skip-like token or env override in the source"; }

# S: --check mode is read-only and cannot make a push pass
pp 'bash scripts/pre-push --check origin/main..HEAD' >/dev/null 2>&1; record 1 $? "S --check reports the unsigned commit"
pp 'git push origin main' >/dev/null 2>&1;                          record 1 $? "S a real push afterwards is still refused"
out=$(pp "$FRESH; bash scripts/pre-push --check origin/main..HEAD"); rc=$?
record 0 "$rc" "S --check on an empty range passes"
has "$out" "empty range"; record 0 $? "S …and says so"

# T: GoN added then deleted inside the range → the tree of commit 1 still ships
pp "$FRESH; mkdir -p Wargames/GoN; printf 'x\n' > Wargames/GoN/L1.md; git add -f Wargames/GoN/L1.md; git commit -q --no-verify -m 'T1: add'; git rm -q Wargames/GoN/L1.md; git commit -q -m 'T2: delete'" >/dev/null 2>&1
pp 'git ls-tree -r --name-only HEAD | grep -q GoN'; record 1 $? "T setup: the tip tree is clean"
out=$(pp 'git push origin main'); rc=$?
record 1 "$rc" "T GoN added-then-deleted in the range: refused"
has "$out" "NO-PUBLISH PATH"; record 0 $? "T NO-PUBLISH reported"
has "$out" "Wargames/GoN/L1.md"; record 0 $? "T the deleted path is still named"

# U: an ignored path committed by force → refused by the .gitignore backstop
pp "$FRESH; printf 'h\n' > run.log; git add -f run.log; git commit -q --no-verify -m 'U: ignored'" >/dev/null 2>&1
out=$(pp 'git push origin main'); rc=$?
record 1 "$rc" "U ignored *.log in history: refused"
has "$out" "IGNORED PATH"; record 0 $? "U IGNORED PATH reported"
has "$out" "run.log";      record 0 $? "U names the path"

# V: secret only in a commit MESSAGE (no new blob at all) → refused
pp "$FRESH; git commit -q --allow-empty -m \"V: pw: \$SECRET\"" >/dev/null 2>&1
out=$(pp 'git push origin main'); rc=$?
record 1 "$rc" "V secret in a commit message: refused"
has "$out" "in a commit MESSAGE"; record 0 $? "V message scan reported"
has "$out" "message: line 1";     record 0 $? "V commit and line named"
has "$out" "$SECRET";             record 1 $? "V full token NOT echoed (the subject line is previewed, not printed)"
has "$out" "NO signature — V: pw: ${SECRET:0:3}…"; record 0 $? "V subject shown as a 3-char preview"

# W: scanner missing from the working tree → fail closed
pp "$FRESH; rm -f scripts/claude/secret_scan.py; printf 'x\n' > w.md; git add w.md; git commit -q --no-verify -m 'W: no scanner'" >/dev/null 2>&1
out=$(pp 'git push origin main'); rc=$?
record 1 "$rc" "W scanner missing: push refused"
has "$out" "secret scanner unavailable"; record 0 $? "W fail-closed reason named"

# X: --no-ff merge of a secret side branch is stopped by pre-merge-commit
pp "$FRESH; git checkout -q -b side; printf 'password: %s\n' \"\$SECRET\" > s.md; git add s.md; git commit -q --no-verify -m 'X: side secret'; git checkout -q main" >/dev/null 2>&1
pp 'git merge --no-ff -q side' >/dev/null 2>&1; record 1 $? "X --no-ff merge of a secret branch: refused"
pp '[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]'; record 0 $? "X no merge commit was created"
pp 'git merge --abort 2>/dev/null; git reset -q --hard origin/main; git branch -q -D side' >/dev/null 2>&1
pp "$FRESH; git checkout -q -b side2; printf 'clean\n' > s.md; git add s.md; git commit -q -m 'X2: clean side'; git checkout -q main; git merge --no-ff -q side2" >/dev/null 2>&1
record 0 $? "X2 control: --no-ff merge of a clean branch succeeds"
pp 'git reset -q --hard origin/main; git branch -q -D side2' >/dev/null 2>&1
rm -rf "$PT"

# --- 4. write guard ---------------------------------------------------
if [ -f "$WGUARD" ]; then
    head2 "guard_write.py — placement, naming, credentials"
    wg_run() {  # expect label json  — WARN = exit 2, OK = exit 0, anything else is a defect
        local expect="$1" label="$2" json="$3" rc got
        printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$ROOT" python3 "$WGUARD" >/dev/null 2>&1; rc=$?
        case "$rc" in 2) got=WARN ;; 0) got=OK ;; *) got="RC$rc" ;; esac
        record "$expect" "$got" "$label"
    }
    wg() {  # expect label file content   (the Write tool's shape)
        wg_run "$1" "$2" "$(jq -nc --arg f "$3" --arg c "$4" --arg cwd "$ROOT" \
            '{tool_name:"Write",cwd:$cwd,tool_input:{file_path:$f,content:$c}}')"
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

    # same rule set as the hook (L1b): sub-30-char shapes, token-level whitelist
    wg WARN "10-char credential after 'password:'" "$ROOT/Wargames/Leviathan/Level_01.md" "password: $LEV10"
    wg WARN "10-char credential on a bare line"    "$ROOT/Wargames/Leviathan/Level_01.md" "$LEV10"
    wg WARN "10-char credential after cat *_pass"  "$ROOT/Wargames/Leviathan/Level_01.md" $'$ cat /etc/leviathan_pass/leviathan2\n'"$LEV10ND"
    wg WARN "32-char credential beside a <tag>"    "$ROOT/Wargames/Bandit/Level_09.md" "password: $SECRET (see <Level_02>)"
    wg OK   "mktemp name is not a credential"      "$ROOT/Wargames/Leviathan/Level_01.md" "/tmp/tmp.$LEV10/pass"
    wg OK   "CamelCase+digits identifier"          "$ROOT/Roadmap_Post_Bandit.md" "Computing101 후"

    # tool shapes and malformed input the guard used to miss or crash on (L2)
    wg_run WARN "MultiEdit: secret inside edits[].new_string" \
       "$(jq -nc --arg f "$ROOT/Wargames/Bandit/Level_09.md" --arg s "$SECRET" --arg cwd "$ROOT" \
          '{tool_name:"MultiEdit",cwd:$cwd,tool_input:{file_path:$f,edits:[{old_string:"a",new_string:"fine"},{old_string:"b",new_string:("pw: "+$s)}]}}')"
    wg_run WARN "NotebookEdit: notebook_path + new_source carries a secret" \
       "$(jq -nc --arg f "$ROOT/Tools/solve.ipynb" --arg s "$SECRET" --arg cwd "$ROOT" \
          '{tool_name:"NotebookEdit",cwd:$cwd,tool_input:{notebook_path:$f,new_source:("pw = "+$s)}}')"
    wg_run OK   "tool_input is a string: exit 0, not a traceback" '{"tool_name":"Write","tool_input":"nope"}'
    wg_run OK   "tool_input is a list: exit 0"      '{"tool_name":"Write","tool_input":[1,2]}'
    wg_run OK   "file_path is an int: exit 0"       '{"tool_name":"Write","tool_input":{"file_path":42,"content":"x"}}'
    wg_run OK   "file_path with embedded NUL: exit 0" "$(jq -nc --arg f "$ROOT/Tools/x" '{tool_name:"Write",tool_input:{file_path:($f+"\u0000y.md"),content:"x"}}')"
    printf '%s' "$(jq -nc --arg f "$ROOT/Tools/xxd.md" '{tool_name:"Write",cwd:7,tool_input:{file_path:$f,content:"ok"}}')" \
        | env -u CLAUDE_PROJECT_DIR python3 "$WGUARD" >/dev/null 2>&1; record 0 $? "cwd is a number, no CLAUDE_PROJECT_DIR: exit 0"
    wg OK   ".gitattributes is a known root file"   "$ROOT/.gitattributes" "*.md text eol=lf"
    wg WARN "note directly under Wargames/"         "$ROOT/Wargames/Random.md" "ok"
    wg OK   "_ marker directly under Wargames/"     "$ROOT/Wargames/_LOCAL_ONLY.md" "ok"
    wg OK   "MOC directly under Wargames/"          "$ROOT/Wargames/MOC_All.md" "ok"

    # identifiers (§1.5): a throwaway whose .git/info/identifiers names a placeholder
    WT=$(mktemp -d)
    ( cd "$WT" && git init -q -b main . && printf 'Jane Placeholder\n' > .git/info/identifiers ) >/dev/null 2>&1
    json=$(jq -nc --arg f "$WT/Concepts/Linux/Foo.md" --arg cwd "$WT" \
        '{tool_name:"Write",cwd:$cwd,tool_input:{file_path:$f,content:"reviewed by jane placeholder"}}')
    printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$WT" python3 "$WGUARD" >/dev/null 2>&1
    record 2 $? "identifier from .git/info/identifiers: WARN"
    json=$(jq -nc --arg f "$WT/Concepts/Linux/Foo.md" --arg cwd "$WT" \
        '{tool_name:"Write",cwd:$cwd,tool_input:{file_path:$f,content:"reviewed by nobody"}}')
    printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$WT" python3 "$WGUARD" >/dev/null 2>&1
    record 0 $? "same file without the identifier: OK"
    rm -rf "$WT"
fi

# --- 4b. index sentinel (state-based no-publish backstop) -------------
head2 "guard_index.sh — state-based no-publish backstop"
ISENT="$ROOT/scripts/claude/guard_index.sh"
if [ -f "$ISENT" ]; then
    IT=$(mktemp -d)
    ( cd "$IT" && git init -q -b main .
      git config user.email t@users.noreply.github.com; git config user.name t
      git config commit.gpgsign false
      cp "$ROOT/.gitignore" .          # the check-ignore backstop reads the real rules
      mkdir -p Wargames/Pwn_College Wargames/Bandit
      echo x > Wargames/Bandit/Level_01.md
      echo secret > Wargames/Pwn_College/Level_01.md
      touch Wargames/Pwn_College/.nopublish
      git add -f Wargames/Bandit/Level_01.md >/dev/null 2>&1
      git commit -q -m init >/dev/null 2>&1 ) >/dev/null 2>&1
    sentinel() { ( cd "$IT" && CLAUDE_PROJECT_DIR="$IT" bash "$ISENT" 2>"$IT/.sentinel.err" >/dev/null ); }
    staged() { ( cd "$IT" && git diff --cached --name-only | grep -ci -- "$1" ); }

    # smuggle a no-publish file into the index the way the red team did, then
    # let the sentinel run and prove it unstages it.
    ( cd "$IT" && printf '%s\n' Wargames/Pwn_College/Level_01.md \
        | git update-index --add --stdin >/dev/null 2>&1 )
    record 1 "$(staged Pwn_College)" "smuggle put a pwn path in the index (setup)"
    sentinel; record 2 $? "sentinel warns (exit 2) on a poisoned index"
    record 0 "$(staged Pwn_College)" "sentinel auto-unstaged the pwn path"

    # a clean index must not trip it
    ( cd "$IT" && echo ok > Wargames/Bandit/Level_02.md && git add Wargames/Bandit/Level_02.md >/dev/null 2>&1 )
    sentinel; record 0 $? "clean index passes the sentinel"

    # L1a §4b: spelling games, marker-only dirs, marker as a directory, ignored paths
    ( cd "$IT" && git update-index --add --cacheinfo 100644,$(echo h | git hash-object -w --stdin),WARGAMES/GON/L1.md ) >/dev/null 2>&1
    sentinel; record 2 $? "sentinel warns on an UPPER-cased no-publish path"
    record 0 "$(staged gon)" "sentinel unstaged the UPPER-cased path"
    ( cd "$IT" && mkdir -p Wargames/Pwn_College && echo h > Wargames/Pwn_College/L3.md && git update-index --add wargames/pwn_college/L3.md ) >/dev/null 2>&1
    sentinel; record 2 $? "sentinel warns on a lower-cased pwn path"
    record 0 "$(staged pwn_college)" "sentinel unstaged the lower-cased path"
    ( cd "$IT" && mkdir -p Wargames/Other && : > Wargames/Other/.nopublish && echo h > Wargames/Other/n.md && git add -f Wargames/Other/n.md ) >/dev/null 2>&1
    sentinel; record 2 $? "sentinel warns on a marker-only dir (not hardcoded)"
    record 0 "$(staged Other)" "sentinel unstaged the marker-only path"
    ( cd "$IT" && mkdir -p Dm/.nopublish && echo h > Dm/n.md && git add -f Dm/n.md ) >/dev/null 2>&1
    sentinel; record 2 $? "sentinel warns when the marker is a directory"
    record 0 "$(staged Dm/)" "sentinel unstaged the path under a directory marker"
    ( cd "$IT" && echo h > run.log && git add -f run.log ) >/dev/null 2>&1
    sentinel; record 2 $? "sentinel warns on a force-staged ignored *.log"
    record 0 "$(staged run.log)" "sentinel unstaged the ignored path"
    record 1 "$(staged Level_02)" "the clean staged note survived every pass"
    # two bad paths at once: each on its own line, no word splitting
    ( cd "$IT" && mkdir -p "Wargames/GoN/sub dir" && echo h > "Wargames/GoN/sub dir/n.md" && git add -f "Wargames/GoN/sub dir/n.md" && echo h > run.log && git add -f run.log ) >/dev/null 2>&1
    sentinel; record 2 $? "sentinel warns on two bad paths at once"
    record 2 "$(grep -c '^    ' "$IT/.sentinel.err")" "  …listing exactly two paths, one per line"
    grep -q '^    Wargames/GoN/sub dir/n.md$' "$IT/.sentinel.err"; record 0 $? "  …a path with a space is printed whole"
    record 0 "$(staged GoN)" "  …and both are unstaged"
    rm -rf "$IT"
fi

# --- 5. wiring --------------------------------------------------------
head2 "wiring — settings.json, hooks, signing, doc/guard drift"
jq -e . "$ROOT/.claude/settings.json" >/dev/null 2>&1
record 0 $? "settings.json parses"
for s in $(jq -r '.. | .command? // empty' "$ROOT/.claude/settings.json" 2>/dev/null | grep -oE 'scripts/claude/[A-Za-z_-]+\.sh' | sort -u); do
    test -f "$ROOT/$s"; record 0 $? "hook script named in settings.json exists: $s"
done
HD=$(cd "$ROOT" && git rev-parse --git-path hooks)
case "$HD" in /*) ;; *) HD="$ROOT/$HD" ;; esac
test -z "$(cd "$ROOT" && git config --get core.hooksPath)"; record 0 $? "core.hooksPath is unset"
for h in pre-commit pre-merge-commit pre-push; do
    [ -f "$HD/$h" ] && [ ! -L "$HD/$h" ] && [ -x "$HD/$h" ]; record 0 $? "$h installed: regular file, executable"
done
cmp -s "$ROOT/scripts/pre-commit" "$HD/pre-commit";       record 0 $? "pre-commit hook matches scripts/pre-commit"
cmp -s "$ROOT/scripts/pre-commit" "$HD/pre-merge-commit"; record 0 $? "pre-merge-commit hook matches scripts/pre-commit"
cmp -s "$ROOT/scripts/pre-push"   "$HD/pre-push";         record 0 $? "pre-push hook matches scripts/pre-push"
test "$(cd "$ROOT" && git config --get user.signingkey | tr a-z A-Z)" = "E81313B5B651B0D9"; record 0 $? "user.signingkey is the CLAUDE.md §1.3 key"
gpg --batch --list-secret-keys E81313B5B651B0D9 >/dev/null 2>&1; record 0 $? "secret key present in the keyring"
# HEAD~5, not deeper: 20c1577 (2026-08-16) carries the pre-v4.1 test fixture that
# the v4.1 scanner flags; it is already public, so pre-push never re-sends it.
out=$(cd "$ROOT" && bash scripts/pre-push --check HEAD~5..HEAD 2>&1); rc=$?
record 0 "$rc" "pre-push --check HEAD~5..HEAD passes on the real history"
printf '%s' "$out" | grep -qE 'UNSIGNED|WRONG SIGNING KEY'; record 1 $? "  …every one of those commits verifies G with the declared key"

# drift: the four shell guards carry the same no-publish list, and every
# entry is mirrored in .gitignore and in the bash parser's markers
a=$(grep -m1 '^NO_PUBLISH_DIRS=' "$ROOT/scripts/pre-commit")
b=$(grep -m1 '^NO_PUBLISH_DIRS=' "$ROOT/scripts/pre-push")
c=$(grep -m1 '^NO_PUBLISH_DIRS=' "$ROOT/scripts/claude/guard_index.sh")
d=$(grep -m1 '^NO_PUBLISH_DIRS=' "$ROOT/scripts/claude/session-guard.sh")
[ -n "$a" ] && [ "$a" = "$b" ] && [ "$b" = "$c" ] && [ "$c" = "$d" ]
record 0 $? "NO_PUBLISH_DIRS line identical in pre-commit, pre-push, guard_index.sh, session-guard.sh"
markers=$(grep -m1 '^NO_PUBLISH_MARKERS' "$ROOT/scripts/claude/guard_bash.py")
for dir in $(printf '%s' "$a" | grep -oE '"[^"]+"' | tr -d '"'); do
    grep -qxE "$(printf '%s' "$dir" | sed 's/[.[\*^$]/\\&/g')/?" "$ROOT/.gitignore"
    record 0 $? "  $dir has its .gitignore line"
    printf '%s' "$markers" | grep -qiF "\"$(basename "$dir")\""
    record 0 $? "  $dir has a guard_bash.py NO_PUBLISH_MARKERS entry"
done

# drift: every model-invocable skill has a row in CLAUDE.md §3
for f in "$ROOT"/.claude/skills/*/SKILL.md; do
    n=$(basename "$(dirname "$f")")
    grep -qE '^disable-model-invocation:[[:space:]]*true' "$f" && continue
    grep -qE "^\| \`/$n[ \`]" "$ROOT/CLAUDE.md"; record 0 $? "CLAUDE.md §3 names /$n"
done

# drift: every protocol and template is reachable from CLAUDE.md
for f in "$ROOT"/_System/*.md "$ROOT"/_Templates/*.md; do
    rel=${f#"$ROOT"/}
    grep -qF "$rel" "$ROOT/CLAUDE.md"; record 0 $? "CLAUDE.md references $rel"
done

# drift: one concept-domain list everywhere
gd=$(grep -m1 '^CONCEPT_DOMAINS' "$ROOT/scripts/claude/guard_write.py" | grep -oE '"[A-Za-z]+"' | tr -d '"' | sort | tr '\n' ' ')
vs=$(grep -m1 -i '^Current domains:' "$ROOT/_System/Vault_Structure.md" | grep -oE '`[A-Za-z]+`' | tr -d '`' | sort | tr '\n' ' ')
[ -n "$gd" ] && [ "$gd" = "$vs" ]; record 0 $? "CONCEPT_DOMAINS == Vault_Structure.md domain list (${gd% })"
for f in _System/Frontmatter.md _Templates/Concept_Lite_Template.md; do
    en=$(grep -m1 -E '^domain:' "$ROOT/$f" | sed 's/^domain://' | tr '|' '\n' | tr -d ' ' | grep . | sort | tr '\n' ' ')
    [ -n "$gd" ] && [ "$gd" = "$en" ]; record 0 $? "CONCEPT_DOMAINS == $f domain enum (${en% })"
done

# drift: one signing key id across docs, setup and the two hooks that pin it
ref=$(grep -oE '(^|[^[:alnum:]])[0-9A-F]{16}([^[:alnum:]]|$)' "$ROOT/CLAUDE.md" | tr -cd '0-9A-F\n' | head -1)
[ -n "$ref" ]; record 0 $? "CLAUDE.md declares a 16-hex signing key id"
for f in README.md scripts/setup.sh scripts/pre-push scripts/claude/session-guard.sh; do
    grep -qF "$ref" "$ROOT/$f"; record 0 $? "  $f carries the same key id"
done
keys=$(cat "$ROOT/CLAUDE.md" "$ROOT/README.md" "$ROOT/scripts/setup.sh" "$ROOT/scripts/pre-push" "$ROOT/scripts/claude/session-guard.sh" \
       | grep -oE '(^|[^[:alnum:]])[0-9A-F]{16}([^[:alnum:]]|$)' | tr -cd '0-9A-F\n' | sort -u | grep -c .)
record 1 "$keys" "  …and no other 16-hex id appears in those five files"

# drift: CLAUDE.md must not carry a hard-coded test count (it is stale within a week)
n=$(grep -E '[0-9]{2,}\+? (regression )?checks' "$ROOT/CLAUDE.md" | grep -vcE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
record 0 "$n" "CLAUDE.md has no hard-coded test count outside a dated line ($n line(s))"

# drift: the settings rules CLAUDE.md §1 relies on are actually there
S_JSON="$ROOT/.claude/settings.json"
for r in 'Read(~/.ssh/**)' 'Read(~/.gnupg/**)' 'Read(~/.aws/**)' 'Read(~/.colima/_lima/_config/user)' \
         'Read(~/.config/gh/hosts.yml)' 'Read(~/.docker/config.json)' 'Read(./.git/info/identifiers)' \
         'Edit(./.git/info/identifiers)' 'Write(./.git/info/identifiers)' 'Bash(git commit --no-verify:*)'; do
    jq -e --arg r "$r" '.permissions.deny | index($r)' "$S_JSON" >/dev/null 2>&1
    record 0 $? "settings deny has $r"
done
for r in 'Bash(git commit:*)' 'Bash(git push:*)' 'Edit(./.claude/**)' 'Write(./.claude/**)' \
         'Edit(./scripts/**)' 'Write(./scripts/**)' 'Edit(./CLAUDE.md)'; do
    jq -e --arg r "$r" '.permissions.ask | index($r)' "$S_JSON" >/dev/null 2>&1
    record 0 $? "settings ask has $r"
done
jq -e '.hooks.PostToolUse[] | select(.matcher | test("MultiEdit") and test("NotebookEdit"))' "$S_JSON" >/dev/null 2>&1
record 0 $? "write-guard matcher covers MultiEdit and NotebookEdit"

# drift: §1.7 — the /commit skill can read git state and nothing else
CS="$ROOT/.claude/skills/commit/SKILL.md"
tools=$(awk '/^allowed-tools:/{f=1;next} f&&/^[^ -]/{f=0} f' "$CS")
[ -n "$tools" ]; record 0 $? "/commit declares an allowed-tools list"
printf '%s' "$tools" | grep -qE 'Write|Edit|git commit|git push|git add|push\.sh'
record 1 $? "  …with no write tool and no commit/push/add on it"

# drift: _System/Harness.md names every layer it documents
H="$ROOT/_System/Harness.md"
for w in session-guard.sh bash-guard.sh guard_bash.py write-guard.sh guard_write.py guard_index.sh \
         secret_scan.py scripts/pre-commit scripts/pre-push pre-merge-commit "$ref"; do
    grep -qF "$w" "$H"; record 0 $? "Harness.md names $w"
done

# --- report -----------------------------------------------------------
printf '\n'
if [ "$FAILED" -eq 0 ]; then
    green "ALL GREEN — $TOTAL checks passed"
    exit 0
fi
red "$FAILED of $TOTAL checks FAILED"
exit 1
