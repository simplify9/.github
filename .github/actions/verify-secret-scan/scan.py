#!/usr/bin/env python3
"""Personal-data and secret scanner for files committed for CI (Strapi fixtures, HAR, mock files).

CLI: python3 scan.py [--allow FILE] [--strapi-dump] PATH...
Exit 0 clean, 1 findings, 2 usage or IO error. Reads .gz transparently, line by line.
Never prints a value: emails as ***@<domain>, everything else as its first 4 characters + "…".
Stdlib only.
"""
from __future__ import annotations

import argparse
import gzip
import json
import re
import sys
from collections import namedtuple

# where: "table.column" for findings inside a pg_dump COPY section (--strapi-dump), else "".
Finding = namedtuple("Finding", "line kind masked where", defaults=("",))

# Public by design: the CI admin that scripts/strapi-fixture puts into every fixture. Its password
# ("VerifyCiOnly-1") is only valid in throwaway databases; never restore a fixture into a real one.
CI_ADMIN_EMAIL = "ci-admin@example.invalid"
CI_ADMIN_HASH = "$2a$10$FUuVZn5/lwHIjKjs.fVdr.xz3IiWY.0rSLaLNtQjSGlUVwFcMsEMy"

# Strapi v4 (`_links`) and v5 (`_lnk`) tables that must be empty in a fixture (token-linked tables included).
STRAPI_SECRET_TABLES = frozenset({
    "strapi_api_tokens", "strapi_api_token_permissions",
    "strapi_api_token_permissions_token_links", "strapi_api_token_permissions_token_lnk",
    "strapi_transfer_tokens", "strapi_transfer_token_permissions",
    "strapi_transfer_token_permissions_token_links", "strapi_transfer_token_permissions_token_lnk",
    "strapi_sessions", "strapi_webhooks",
    "strapi_api_tokens_admin_user_owner_lnk", "admin_permissions_api_token_lnk",
})

# strapi.io: Strapi's own default email settings (no-reply@strapi.io) live in every core store.
EXAMPLE_DOMAINS = {"example.com", "example.org", "example.net", "strapi.io"}
RESERVED_SUFFIXES = (".invalid", ".example", ".test", ".localhost")
LOCAL_HOSTS = r"(?:localhost|127\.0\.0\.1|host\.docker\.internal)"
# Personal mailboxes: never allow-list the domain, scrub the column instead.
FREE_MAIL = {"gmail.com", "googlemail.com", "yahoo.com", "hotmail.com", "outlook.com", "live.com", "msn.com",
             "icloud.com", "me.com", "aol.com", "proton.me", "protonmail.com", "gmx.com", "yandex.com", "mail.ru"}

# The lookbehind anchors the local part at its first character: without it a long run of local-part
# characters (a hex bytea column) makes the search quadratic.
EMAIL = re.compile(r"(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]+@((?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,})")
PATTERNS = [
    ("password-hash", re.compile(r"\$2[aby]\$\d{2}\$[./A-Za-z0-9]{53}")),
    ("password-hash", re.compile(r"\$argon2(?:id|i|d)\$")),
    ("jwt", re.compile(r"eyJ[\w-]{10,}\.eyJ[\w-]{10,}\.[\w-]{10,}")),
    ("private-key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("token", re.compile(r"ghp_[A-Za-z0-9]{36}|github_pat_\w{50,}|AKIA[0-9A-Z]{16}"
                         r"|sk_live_[0-9A-Za-z]{16,}|xox[abpr]-[0-9A-Za-z-]{10,}")),
    ("connection-string", re.compile(
        r"(?i)(?:postgres(?:ql)?|amqps?|mongodb(?:\+srv)?|redis)://[^:/@\s\"']*:[^@\s\"']+@(?!" + LOCAL_HOSTS + r"\b)")),
    # Recorded (HAR {"name","value"}) or mocked (Mockoon {"key","value"}) credential headers.
    ("auth-header", re.compile(
        r'(?i)"(?:name|key)"\s*:\s*"(?:authorization|proxy-authorization|cookie|set-cookie|x-api-key|api-key'
        r'|x-auth-token)"\s*,\s*"value"\s*:\s*"[^"]{8,}"')),
    # A non-empty password in JSON, in JSON escaped inside a HAR postData string, or form-encoded.
    ("password-field", re.compile(r'(?i)(?<![a-z])pass(?:word|wd)\\*"\s*:\s*\\*"[^"\\]+')),
    # Form-encoded only: after & ? a quote or whitespace (a `;Password=` connection string is reported above).
    ("password-field", re.compile(r'(?i)(?:^|(?<=[&?"\s]))pass(?:word|wd)=[^&\s"]+')),
]
# Credential headers and cookies, also found by walking parsed HAR/Mockoon JSON (pretty-printed files put
# "name" and "value" on separate lines, which the line patterns cannot see).
CRED_HEADERS = {"authorization", "proxy-authorization", "cookie", "set-cookie", "x-api-key", "api-key", "x-auth-token"}
# Key=value connection strings are checked by _connection_strings (any key order), not a pattern.
CONN_SEGMENT = re.compile(r"[^\"'\n<>]+")  # quotes, newlines and tags bound one candidate value
CONN_HOST_KEYS = {"host", "server", "data source", "address", "addr", "network address"}
CONN_PASSWORD_KEYS = {"password", "pwd"}
LOCAL_NAMES = {"localhost", "127.0.0.1", "host.docker.internal", "::1"}
HOST_PORT = re.compile(r"^\s*([A-Za-z0-9.-]+):\d{2,5}\s*$")  # StackExchange.Redis "host:port,password=..."
COPY = re.compile(r"^COPY public\.\"?([A-Za-z0-9_]+)\"? \((.*)\) FROM stdin;$")
INSERT = re.compile(r"^INSERT INTO (?:public\.)?\"?([A-Za-z0-9_]+)\"?[ (]")


def load_allow(path):
    """-> (exact lowercased addresses, domains from `@domain` lines). Missing file: empty sets."""
    exact, domains = set(), set()
    if not path:
        return exact, domains
    try:
        with open(path, encoding="utf-8") as f:
            for raw in f:
                line = raw.split("#", 1)[0].strip().lower()
                if line.startswith("@"):
                    domains.add(line[1:])
                elif line:
                    exact.add(line)
    except FileNotFoundError:
        pass
    return exact, domains


def _email_allowed(address, domain, allow):
    exact, domains = allow
    domain = domain.lower()
    return (domain in EXAMPLE_DOMAINS or domain.endswith(RESERVED_SUFFIXES)
            or domain in domains or address.lower() in exact)


def _in_url_userinfo(line, start):
    """True when the match sits in `scheme://user:pass@host` (reported as a connection string instead):
    a `://` in the same token with no path, query, fragment, escape or tag between it and the match."""
    token_start = max(line.rfind(c, 0, start) for c in " \t\"'") + 1
    i = line.rfind("://", token_start, start)
    return i >= 0 and not re.search(r"[/?#\\<>]", line[i + 3:start])


def _remote(host):
    """True for a host a CI run could really reach: not local, and not a dotless name such as a
    docker-compose service (`db`, `postgres`), which only resolves inside that compose network."""
    host = host.strip().lower()
    if host.startswith("tcp:"):
        host = host[4:]
    host = host.split(",")[0].strip()
    if host.count(":") == 1:
        host = host.split(":")[0]
    return bool(host) and host not in LOCAL_NAMES and "." in host


def _connection_strings(line):
    """Start offsets of key=value connection strings holding a non-empty password and a remote host,
    in any key order (parts split on ; or ,). Linear in the line: each segment is split once."""
    out = []
    for m in CONN_SEGMENT.finditer(line):
        seg = m.group(0)
        low = seg.lower()
        if "=" not in seg or ("password" not in low and "pwd" not in low):
            continue
        password = remote = False
        for part in re.split(r"[;,]", seg):
            key, eq, value = part.partition("=")
            key = key.strip().lower()
            if eq and key in CONN_PASSWORD_KEYS and value.strip():
                password = True
            elif eq and key in CONN_HOST_KEYS:
                remote = remote or _remote(value)
            elif not eq:
                hp = HOST_PORT.match(part)
                remote = remote or bool(hp and _remote(hp.group(1)))
        if password and remote:
            out.append(m.start())
    return out


def scan_lines(lines, allow, strapi_dump):
    findings, secret_copy, copy = [], None, None  # copy: (table, [columns]) while inside COPY data
    for n, line in enumerate(lines, 1):
        line = line.rstrip("\r\n")
        if strapi_dump:
            if secret_copy is not None:
                if line == "\\.":
                    secret_copy = None
                elif secret_copy[1] is False:
                    findings.append(Finding(secret_copy[0], "strapi-secret-table", secret_copy[2]))
                    secret_copy = (secret_copy[0], True, secret_copy[2])
                continue
            if copy is not None and line == "\\.":
                copy = None
                continue
            m = COPY.match(line)
            if m:
                if m.group(1) in STRAPI_SECRET_TABLES:
                    secret_copy = (n, False, m.group(1))
                else:
                    copy = (m.group(1), [c.strip().strip('"') for c in m.group(2).split(",")])
                continue
            m = INSERT.match(line)
            if m and m.group(1) in STRAPI_SECRET_TABLES:
                findings.append(Finding(n, "strapi-secret-table", m.group(1)))
                continue

        def where(pos):
            if copy is None:
                return ""
            i = line.count("\t", 0, pos)
            return "%s.%s" % (copy[0], copy[1][i] if i < len(copy[1]) else "?")
        for m in EMAIL.finditer(line):
            if not _email_allowed(m.group(0), m.group(1), allow) and not _in_url_userinfo(line, m.start()):
                findings.append(Finding(n, "email", "***@" + m.group(1).lower(), where(m.start())))
        for kind, rx in PATTERNS:
            for m in rx.finditer(line):
                if m.group(0) != CI_ADMIN_HASH:
                    findings.append(Finding(n, kind, m.group(0)[:4] + "…", where(m.start())))
        for pos in _connection_strings(line):
            findings.append(Finding(n, "connection-string", "key=value with a password…", where(pos)))
    return findings


def json_findings(obj, path="$"):
    """Credential headers ({"name"|"key": <header>, "value": >= 8 chars}) and HAR cookies in parsed JSON."""
    out = []
    if isinstance(obj, dict):
        name = obj.get("name", obj.get("key"))
        value = obj.get("value")
        cookie = path.rsplit(".", 1)[-1].startswith("cookies[")
        if isinstance(name, str) and isinstance(value, str) and len(value) >= 8 and (
                cookie or name.lower() in CRED_HEADERS):
            out.append(Finding(1, "auth-header", ("cookie " if cookie else "") + name, path))
        for k, v in obj.items():
            out.extend(json_findings(v, "%s.%s" % (path, k)))
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            out.extend(json_findings(v, "%s[%d]" % (path, i)))
    return out


def scan_path(path, allow, strapi_dump):
    """Line scan; for .har/.json that parse, credential headers come from the JSON walk instead."""
    if path.endswith((".har", ".json")):
        try:
            with _open(path) as f:
                found = json_findings(json.load(f))
        except ValueError:
            found = None
        if found is not None:
            with _open(path) as f:
                return found + [x for x in scan_lines(f, allow, strapi_dump) if x.kind != "auth-header"]
    with _open(path) as f:
        return scan_lines(f, allow, strapi_dump)


def _open(path):
    if path.endswith(".gz"):
        return gzip.open(path, "rt", encoding="utf-8", errors="replace")
    return open(path, encoding="utf-8", errors="replace")


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--allow", help="allow-list file: one address or @domain per line")
    ap.add_argument("--strapi-dump", action="store_true", help="also require Strapi token/session/webhook tables to be empty")
    ap.add_argument("paths", nargs="+")
    try:
        a = ap.parse_args(argv)
    except SystemExit:
        return 2
    allow = load_allow(a.allow)
    total = 0
    for path in a.paths:
        try:
            found = scan_path(path, allow, a.strapi_dump)
        except (OSError, EOFError) as e:
            print("::error title=[VERIFY] secret-scan::cannot read %s: %s" % (path, e))
            return 2
        recording = not path.endswith((".sql", ".sql.gz"))  # HAR, its body files, Mockoon mocks
        for fd in found:
            hint = ""
            if recording and fd.kind == "email":
                hint = " (recordings and mocks must not hold real addresses: replace it with an example.com address)"
            elif recording and fd.kind in ("auth-header", "password-field"):
                hint = " (remove it from the recording or mock, or use a placeholder under 8 characters)"
            elif fd.kind == "email" and fd.masked[4:] in FREE_MAIL:
                hint = " (a personal mailbox: list the column in ci/fixture-pii.txt and regenerate the fixture)"
            elif fd.kind == "jwt":
                hint = ' (for a mock, use an unsigned token: header {"alg":"none"} and an empty signature)'
            elif fd.kind == "email":
                hint = ' (if this is public business content, add "@%s" or the address to ci/fixture-allow.txt)' % fd.masked[4:]
            at = " in " + fd.where if fd.where else ""
            print("::error file=%s,line=%d,title=[VERIFY] secret-scan::%s: %s%s%s" % (path, fd.line, fd.kind, fd.masked, at, hint))
        total += len(found)
    if total:
        print("[VERIFY] secret-scan: %d finding(s); values are masked" % total)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
