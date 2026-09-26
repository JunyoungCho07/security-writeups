#!/usr/bin/env python3
# =====================================================================
# secret_scan.py — the ONE credential scanner behind every state gate.
#
# Shared by scripts/pre-commit (hard gate on the index), scripts/pre-push
# (hard gate on pushed history) and scripts/claude/guard_write.py (advisory,
# at write time). One rule set, one whitelist, one preview format — a token
# cannot slip one layer and be caught by the next by accident of wording.
#
# Module API
#   scan_text(text, binary=False, identifiers=()) -> [(lineno, rule, preview)]
#   load_identifiers(repo_root)                   -> [str]
#
# CLI (exit 0 = clean, 1 = hits, 3 = internal error; callers treat EVERY
# non-zero exit as a violation — this layer fails CLOSED)
#   --git-blobs            stdin: NUL-terminated "<blob-sha> <path>" records,
#                          cwd inside the repo; ONE `git cat-file --batch`
#   --text [--label NAME]  stdin is one file
#   one stdout line per hit:  <path>: line <N> [<rule>]: <preview>
#
# Rules (text gets all; a genuine binary blob gets R0 / private-key / api-key /
# identifier only, because a binary carries random 10–29 runs by nature):
#   R0   alnum run >= 30                                  Bandit / Natas
#   R1   alnum run 10..29 with upper AND lower AND digit  Leviathan/Narnia/…
#   R1b  bare line = one alnum run 10..29 (only whitespace / quotes /
#        backticks around it), >= 2 classes, >= 3 class changes
#   R2   (password|passwd|pass|pw)[:=] <6..29 alnum> not shaped like a
#        level account name (bandit27, leviathan0)
#   R3   bare 6..29 alnum line right after a line saying _pass / webpass /
#        password / passwd — the `cat /etc/<game>_pass/<user>` paste shape
#   private-key / api-key   fixed header and vendor-prefix patterns
#   identifier              any string from load_identifiers(), case-insensitive
#
# Design notes (each tied to an audit finding, 2026-09-26):
#   - "binary" is judged on CONTENT, never on .gitattributes or numstat: one
#     attribute line used to switch the whole scan off. A NUL alone does not
#     make a blob binary (the verifier committed a 10-char password beside one
#     stray NUL): UTF-16/32 text is detected (BOM or NUL parity) and decoded,
#     a NUL-stripped blob that still reads as text is scanned as text, and
#     only what is left is binary — and even that is scanned NUL-stripped.
#   - bytes are decoded utf-8 with errors='replace': one invalid byte used to
#     make grep drop the whole line under a UTF-8 locale. Numeric HTML
#     entities are decoded and zero-width characters removed first, so the
#     rendered secret and the scanned text are the same string.
#   - every whitelist clause is judged on the TOKEN or on the characters
#     touching it. A word elsewhere on the line never disarms a token
#     (`password: X (for example)` and `X md5` were both invisible before).
#   - previews are 3 chars + length. A 10-char password must never be
#     echoed back in a hook message; an identifier shows 2 chars.
#   - Python 3.9-compatible on purpose; no third-party imports.
# =====================================================================
import os
import re
import subprocess
import sys

BINARY_PROBE = 8000                     # bytes inspected for a NUL

RUN = re.compile(r"[A-Za-z0-9]+")
BARE = re.compile(r"""^[\s"'`]*([A-Za-z0-9]{6,29})[\s"'`]*$""")
PW_KEY = re.compile(
    r"(?:^|[^A-Za-z0-9_])(?:password|passwd|pass|pw)\s*[:=]\s*"
    r"([A-Za-z0-9]{6,29})(?![A-Za-z0-9])", re.I)
CTX = re.compile(r"_pass|webpass|password|passwd", re.I)
ACCOUNT = re.compile(r"^[a-z]+[0-9]{0,2}$")
PRIVATE_KEY = re.compile(r"BEGIN (?:RSA |DSA |EC |OPENSSH |PGP )?PRIVATE KEY")
API_KEY = re.compile(
    r"AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|sk_live_[0-9a-zA-Z]{24,}"
    r"|ghp_[0-9A-Za-z]{36}|github_pat_[0-9A-Za-z_]{22,}|xox[baprs]-[0-9A-Za-z-]{10,}")

# --- token-level whitelist ------------------------------------------------
# md5(32) sha1(40) sha224(56) sha256(64) sha384(96) sha512(128)
SAFE_HEX = re.compile(
    r"^(?:[0-9a-fA-F]{32}|[0-9a-fA-F]{40}|[0-9a-fA-F]{56}"
    r"|[0-9a-fA-F]{64}|[0-9a-fA-F]{96}|[0-9a-fA-F]{128})$")
SSH_PUB_PREFIX = ("AAAAB3Nza", "AAAAC3Nza", "AAAAE2VjZHNh")   # OpenSSH key body
B64_PUBLIC_PREFIX = "VGhlIHBhc3N3b3JkIGlz"   # base64("The password is"), exact
HEXLIT = re.compile(r"^0[xX][0-9A-Fa-f]+$")  # 0x0804851C
IDENT = re.compile(                          # Computing101: three single-class blocks
    r"^(?:[A-Z]+[a-z]+[0-9]+|[a-z]+[A-Z]+[0-9]+|[A-Z]+[0-9]+[a-z]+"
    r"|[a-z]+[0-9]+[A-Z]+|[0-9]+[A-Z]+[a-z]+|[0-9]+[a-z]+[A-Z]+)$")
SELF_MASK = re.compile(r"masked|redacted|example|placeholder", re.I)
# Left contexts that vouch for the run right after them, each only up to the
# length its real shape has — uncapped, `youtu.be/<32-char password>` passed
# (2026-09-26 round-2 verify). A 30+ run is never vouched for.
LEFT_CTX = (
    (re.compile(r"(?:youtube\.com/watch\?(?:[^\s]*&)?v=|youtu\.be/"
                r"|youtube(?:-nocookie)?\.com/(?:embed|shorts|live)/)$", re.I), 11),
    (re.compile(r"tmp\.$"), 12),                           # mktemp: tmp.XXXXXXXXXX
    (re.compile(r"(?:github\.com[/:]|@)$", re.I), 20),     # handle / user@host
)
LABEL = re.compile(                          # a label ending <= 6 non-alnum chars before the token
    r"(?:fingerprint|sha-?(?:1|224|256|384|512)|md5|checksum|digest|uuid"
    r"|key\s+id|public\s+key|ssh-(?:rsa|dss|ed25519|ecdsa)[a-z0-9@.-]*)"
    r"[^A-Za-z0-9]{0,6}$", re.I)
HEXISH = re.compile(r"^[0-9a-fA-F]+$")
# one-case hex of 12+: a container/commit id or an `xxd -p` dump line, never a
# base62 wargame password (R2/R3 still judge it when a password label or a
# pass-file read sits right before it)
HEX_ARTEFACT = re.compile(r"^(?:[0-9a-f]{12,}|[0-9A-F]{12,})$")
# an OpenSSH public-key body: the wire format always starts AAAA; `ssh-rsa`
# followed by a password does not
SSH_PUB_SPAN = re.compile(
    r"(?:ssh-(?:rsa|dss|ed25519)|ecdsa-sha2-nistp(?:256|384|521)|sk-[a-z0-9-]+@openssh\.com)"
    r"\s+(AAAA[A-Za-z0-9+/]{20,}=*)")
# a base64 digest right after its label, at the exact padded length of
# md5 / sha1 / sha256 / sha384 / sha512 (SRI `integrity="sha384-…"`, openssl)
B64_DIGEST = re.compile(
    r"(?:sha-?(?:256|384|512)|sha-?1|md5)[-:=\s(\[]{1,4}([A-Za-z0-9+/]{22,86}={0,2})"
    r"(?![A-Za-z0-9+/=])", re.I)
B64_DIGEST_LEN = {24, 28, 44, 64, 88}
# OpenSSH host-key fingerprint, shown on the first connect to every SSH
# wargame: exactly 43 base64 chars after "SHA256:". A 32-char password after
# the same label does not fit the structure and is still scanned.
SSH_FP = re.compile(r"SHA256:[A-Za-z0-9+/]{43}(?![A-Za-z0-9+/])")


def token_is_safe(tok, line, start):
    """True when TOK (at LINE[start:]) is a known non-secret shape."""
    if SAFE_HEX.match(tok) or tok.startswith(SSH_PUB_PREFIX):
        return True
    if tok == B64_PUBLIC_PREFIX or HEXLIT.match(tok) or IDENT.match(tok):
        return True
    if SELF_MASK.search(tok) or len(set(tok)) <= 2:
        return True                          # xxxxxxxxxx / AAAA… placeholders
    prefix = line[:start]
    for ctx, cap in LEFT_CTX:
        if len(tok) <= cap and ctx.search(prefix):
            return True
    # a digest label only vouches for a digest-shaped (hex) token — a
    # non-hex secret written after "md5:" used to pass (2026-09-26 verify)
    if LABEL.search(prefix) and HEXISH.match(tok):
        return True
    end = start + len(tok)
    for pat, grp in ((SSH_FP, 0), (SSH_PUB_SPAN, 1)):
        for m in pat.finditer(line):
            if m.start(grp) <= start and end <= m.end(grp):
                return True
    for m in B64_DIGEST.finditer(line):
        if len(m.group(1)) in B64_DIGEST_LEN and m.start(1) <= start and end <= m.end(1):
            return True
    # No blanket <…> exemption: `<realpassword>` and `<pw example>` are not
    # placeholders, and every mask the vault uses (<password masked>,
    # <REDACTED>, <example-token-here>) passes on its own short/SELF_MASK words.
    return False


def classes(tok):
    return sum(1 for f in (str.isupper, str.islower, str.isdigit)
               if any(f(c) for c in tok))


def changes(tok):
    kinds = ["U" if c.isupper() else "L" if c.islower() else "D" for c in tok]
    return sum(1 for a, b in zip(kinds, kinds[1:]) if a != b)


def preview(tok):
    return "%s…(%d chars)" % (tok[:3], len(tok))


def is_binary(data):
    """Kept for callers that only ask "is there a NUL up front?"."""
    return b"\0" in data[:BINARY_PROBE]


_BOMS = (                                   # longest first: UTF-32LE starts like UTF-16LE
    (b"\xff\xfe\x00\x00", "utf-32-le"), (b"\x00\x00\xfe\xff", "utf-32-be"),
    (b"\xff\xfe", "utf-16-le"), (b"\xfe\xff", "utf-16-be"),
)
# invisible or zero-width: format chars, joiners, bidi controls, variation
# selectors, Mongolian/Khmer/Hangul fillers (round-2 verify found the first
# set too narrow). Built from code points so this source stays plain ASCII.
_ZW_POINTS = (0x00AD, 0x034F, 0x115F, 0x1160, 0x17B4, 0x17B5, 0x3164, 0xFEFF, 0xFFA0)
_ZW_RANGES = ((0x180B, 0x180E), (0x200B, 0x200F), (0x202A, 0x202E),
              (0x2060, 0x206F), (0xFE00, 0xFE0F))
_ZERO_WIDTH = re.compile("[%s]" % "".join(
    [re.escape(chr(c)) for c in _ZW_POINTS]
    + ["%s-%s" % (re.escape(chr(a)), re.escape(chr(b))) for a, b in _ZW_RANGES]))
_REPLACEMENT = chr(0xFFFD)
_BOM = chr(0xFEFF)
_NUM_ENTITY = re.compile(r"&#(?:[xX]([0-9a-fA-F]{1,6})|([0-9]{1,7}));")


def _wide_encoding(probe):
    """UTF-16/32 by BOM, else by NUL parity: ASCII-range UTF-16 puts a NUL
    in every other byte, always on the same side."""
    for bom, enc in _BOMS:
        if probe.startswith(bom):
            return enc
    n = len(probe) - (len(probe) % 2)
    if n < 8:
        return None
    even = probe[0:n:2].count(0)
    odd = probe[1:n:2].count(0)
    half = n // 2
    if odd >= 0.4 * half and even <= 0.05 * half:
        return "utf-16-le"
    if even >= 0.4 * half and odd <= 0.05 * half:
        return "utf-16-be"
    return None


def _looks_textual(text):
    sample = text[:BINARY_PROBE]
    if not sample:
        return True
    bad = sum(1 for c in sample
              if c == _REPLACEMENT or (ord(c) < 32 and c not in "\t\n\r\f\v"))
    return bad <= 0.05 * len(sample)


def _entity(m):
    cp = int(m.group(1), 16) if m.group(1) else int(m.group(2))
    return chr(cp) if 32 <= cp <= 0x10FFFF and not 0xD800 <= cp <= 0xDFFF else m.group(0)


def normalise(text):
    """What a reader SEES: numeric entities decoded, zero-width chars gone
    (neither ever adds or removes a line, so line numbers stay true)."""
    if "&#" in text:
        text = _NUM_ENTITY.sub(_entity, text)
    return _ZERO_WIDTH.sub("", text)


def decode_blob(data):
    """-> (text, binary). Wide text is decoded as what it is; a NUL-stripped
    blob that still reads as text is text; only the rest is binary, and even
    that is returned NUL-stripped so an embedded ASCII secret stays contiguous."""
    probe = data[:BINARY_PROBE]
    enc = _wide_encoding(probe)
    if enc:
        return normalise(data.decode(enc, errors="replace").lstrip(_BOM)), False
    # the WHOLE blob, not the probe: an ASCII head of 8000+ bytes followed by
    # a UTF-16 block used to decode as UTF-8 and hide the block (round 2)
    if b"\0" not in data:
        return normalise(data.decode("utf-8", errors="replace")), False
    text = data.replace(b"\0", b"").decode("utf-8", errors="replace")
    return normalise(text), not _looks_textual(text)


def scan_text(text, binary=False, identifiers=()):
    """Return [(lineno, rule, preview)] for every hit in TEXT."""
    hits = []
    idents = [(i, i.lower()) for i in identifiers if i]
    prev = ""
    # CR-only files (classic Mac) are lines too, or R3/R1b never see a line
    for lineno, line in enumerate(re.split(r"\r\n|\r|\n", text), start=1):
        seen = set()

        def add(rule, tok):
            if tok not in seen:
                seen.add(tok)
                hits.append((lineno, rule, preview(tok)))

        m = PRIVATE_KEY.search(line)
        if m:
            add("private-key", m.group(0))
        m = API_KEY.search(line)
        if m:
            add("api-key", m.group(0))
        if idents:
            low = line.lower()
            for raw, folded in idents:
                if folded in low:
                    hits.append((lineno, "identifier",
                                 "[identifier %s…(%d)]" % (raw[:2], len(raw))))

        bare = None if binary else BARE.match(line)
        if not binary:
            # `ls /etc/natas_webpass/` prints `natas16`: an account name, not a password
            if bare and CTX.search(prev) and not ACCOUNT.match(bare.group(1)) \
                    and not token_is_safe(bare.group(1), line, bare.start(1)):
                add("R3", bare.group(1))
            m = PW_KEY.search(line)
            if m and not ACCOUNT.match(m.group(1)) and not token_is_safe(m.group(1), line, m.start(1)):
                add("R2", m.group(1))

        for m in RUN.finditer(line):
            tok = m.group(0)
            n = len(tok)
            if n < 10 or token_is_safe(tok, line, m.start()):
                continue
            if HEX_ARTEFACT.match(tok):
                continue
            if n >= 30:
                add("R0", tok)
                break
            if binary:
                continue
            if classes(tok) == 3:
                add("R1", tok)
                break
            if bare and classes(tok) >= 2 and changes(tok) >= 3:
                add("R1b", tok)
                break
        prev = line
    return hits


def scan_bytes(data, identifiers=()):
    text, binary = decode_blob(data)
    return scan_text(text, binary=binary, identifiers=identifiers)


# --- identifiers (CLAUDE.md §1.5) ------------------------------------------
def _git(repo_root, *args):
    out = subprocess.run(["git", "-C", repo_root] + list(args),
                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False)
    return out.stdout.decode("utf-8", errors="replace").strip() if out.returncode == 0 else ""


def load_identifiers(repo_root):
    """Lines of <git-dir>/info/identifiers (blank / # lines skipped, entries
    shorter than 3 chars ignored) plus git user.email unless it is a
    @users.noreply.github.com address. Never raises."""
    found = []
    try:
        path = _git(repo_root, "rev-parse", "--git-path", "info/identifiers")
        if path:
            if not os.path.isabs(path):
                path = os.path.join(repo_root, path)
            if os.path.isfile(path):
                with open(path, "r", encoding="utf-8", errors="replace") as fh:
                    for raw in fh:
                        entry = raw.strip()
                        if entry and not entry.startswith("#") and len(entry) >= 3:
                            found.append(entry)
        email = _git(repo_root, "config", "--get", "user.email")
        if email and len(email) >= 3 and not email.lower().endswith("@users.noreply.github.com"):
            found.append(email)
    except Exception:
        pass
    seen = set()
    return [i for i in found if not (i.lower() in seen or seen.add(i.lower()))]


# --- CLI --------------------------------------------------------------------
def _emit(label, hits):
    for lineno, rule, prev in hits:
        sys.stdout.write("%s: line %d [%s]: %s\n" % (label, lineno, rule, prev))


def _read_records(raw):
    """NUL-terminated "<sha> <path>" records -> [(sha, path)]."""
    records = []
    for rec in raw.split(b"\0"):
        if not rec:
            continue
        sha, sep, path = rec.partition(b" ")
        if not sep or not sha or not path:
            raise ValueError("malformed record: %r" % rec[:60])
        records.append((sha.decode("ascii"), path.decode("utf-8", errors="replace")))
    return records


def _cat_file_batch(shas):
    """{sha: bytes} via ONE `git cat-file --batch`. A missing object raises."""
    if not shas:
        return {}
    proc = subprocess.Popen(["git", "cat-file", "--batch"],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = proc.communicate(("\n".join(shas) + "\n").encode("ascii"))
    if proc.returncode != 0:
        raise RuntimeError("git cat-file --batch failed: %s" % err.decode("utf-8", "replace").strip())
    blobs = {}
    pos = 0
    for sha in shas:
        nl = out.find(b"\n", pos)
        if nl < 0:
            raise RuntimeError("truncated cat-file output at %s" % sha)
        header = out[pos:nl].decode("ascii", errors="replace").split()
        if len(header) < 3:
            raise RuntimeError("object %s: %s" % (sha, " ".join(header[1:]) or "unreadable"))
        size = int(header[2])
        body = out[nl + 1:nl + 1 + size]
        if len(body) != size:
            raise RuntimeError("short read for object %s" % sha)
        blobs[sha] = body if header[1] == "blob" else None   # a tree/commit is not content
        pos = nl + 1 + size + 1
    return blobs


def _main(argv):
    mode = None
    label = "<stdin>"
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--git-blobs", "--text"):
            mode = a
        elif a == "--label" and i + 1 < len(argv):
            i += 1
            label = argv[i]
        else:
            sys.stderr.write("usage: secret_scan.py --git-blobs | --text [--label NAME]\n")
            return 3
        i += 1
    if mode is None:
        sys.stderr.write("usage: secret_scan.py --git-blobs | --text [--label NAME]\n")
        return 3

    identifiers = load_identifiers(os.getcwd())
    raw = sys.stdin.buffer.read()
    total = 0
    if mode == "--text":
        hits = scan_bytes(raw, identifiers)
        _emit(label, hits)
        total = len(hits)
    else:
        records = _read_records(raw)
        blobs = _cat_file_batch(sorted({sha for sha, _ in records}))
        for sha, path in records:
            data = blobs[sha]
            if data is None:
                continue
            hits = scan_bytes(data, identifiers)
            _emit(path, hits)
            total += len(hits)
    sys.stdout.flush()
    return 1 if total else 0


if __name__ == "__main__":
    try:
        sys.exit(_main(sys.argv[1:]))
    except SystemExit:
        raise
    except BaseException as exc:            # anything at all → fail closed
        sys.stderr.write("secret_scan: internal error: %s: %s\n" % (type(exc).__name__, exc))
        sys.exit(3)
