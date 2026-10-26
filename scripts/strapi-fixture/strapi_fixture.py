#!/usr/bin/env python3
"""Make a sanitized Strapi fixture (ci/fixture.sql.gz) for verify's upgrade rehearsal.

Run by DevOps on a machine with Docker, never in CI:

  SRC_DB='postgres://readonly_user:...@host:5432/db' \\
    python3 scripts/strapi-fixture/strapi_fixture.py --source-env SRC_DB --repo ../some-cms

The source database is only read (pg_dump). Everything else happens in a throwaway local Postgres
container: personal data and secrets are replaced, the result is scanned with
.github/actions/verify-secret-scan/scan.py, and only a clean dump is written to <repo>/ci/fixture.sql.gz.
The fixture contains a CI admin with a public password: never restore it into a real environment.
Stdlib only.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..",
                                ".github", "actions", "verify-secret-scan"))
import scan  # noqa: E402

MAX_BYTES = 50 * 1024 * 1024
TEXT_TYPES = {"text", "character varying"}
PII_NAME = re.compile(r"(?i)(^|_)(e_?mail|phone|mobile|msisdn|national_?id|ip|ip_?address)(_|$)")
EMAIL_NAME = re.compile(r"(?i)(^|_)e_?mail(_|$)")
SECRET_KEY = re.compile(r"(?i)^(secret|client_?secret|password|api_?key|access_?token|private_?key|key)$")
HANDLED = {("admin_users", "email"), ("up_users", "email")}
# Content history stores full entry snapshots, so it would carry copies of the personal data scrubbed below.
EMPTIED = scan.STRAPI_SECRET_TABLES | {"strapi_history_versions"}


def q(ident):
    return '"' + ident.replace('"', '""') + '"'


def lit(value):
    return "'" + value.replace("'", "''") + "'"


def parse_list_file(path):
    """Non-comment, non-blank lines, stripped (CRLF and surrounding whitespace). Missing file: []."""
    try:
        with open(path, encoding="utf-8") as fh:
            lines = [raw.split("#", 1)[0].strip() for raw in fh]
    except FileNotFoundError:
        return []
    return [line for line in lines if line]


def pii_columns(columns, extra):
    """Columns to scrub: personal-data names plus `extra` (table, column) pairs; core store and the
    admin/app-user emails (handled by sanitize_sql) are skipped."""
    out = []
    for table, column, data_type in columns:
        if table == "strapi_core_store_settings" or (table, column) in HANDLED:
            continue
        if PII_NAME.search(column) or (table, column) in extra:
            out.append((table, column, data_type))
    return out


def _tables(columns):
    tables = {}
    for table, column, _ in columns:
        tables.setdefault(table, set()).add(column)
    return tables


def _set(tables, table, assignments):
    pairs = [(c, v) for c, v in assignments if c in tables.get(table, ())]
    if not pairs:
        return []
    return ["UPDATE %s SET %s;" % (q(table), ", ".join("%s = %s" % (q(c), v) for c, v in pairs))]


def _admin_sql(tables):
    if "admin_users" not in tables:
        return []
    link = next((t for t in ("admin_users_roles_lnk", "admin_users_roles_links") if t in tables), None)
    out = _set(tables, "admin_users", [
        ("email", "'admin' || id || '@example.invalid'"), ("firstname", "'Admin'"), ("lastname", "id::text"),
        ("username", "NULL"), ("password", "NULL"), ("reset_password_token", "NULL"),
        ("registration_token", "NULL"), ("is_active", "false")])
    if not link:
        return out
    ci = [("email", lit(scan.CI_ADMIN_EMAIL)), ("password", lit(scan.CI_ADMIN_HASH)),
          ("is_active", "true"), ("blocked", "false"), ("firstname", "'CI'"), ("lastname", "'Admin'")]
    super_admin = ("SELECT min(l.user_id) FROM %s l JOIN admin_roles r ON r.id = l.role_id "
                   "WHERE r.code = 'strapi-super-admin'" % q(link))
    pairs = [(c, v) for c, v in ci if c in tables["admin_users"]]
    out.append("UPDATE admin_users SET %s WHERE id = (%s);" % (", ".join("%s = %s" % (q(c), v) for c, v in pairs), super_admin))
    # No super admin in the source: insert the CI admin and link it to the role.
    extra = [(c, v) for c, v in [("created_at", "now()"), ("updated_at", "now()"), ("published_at", "now()"),
                                 ("document_id", "'verifyciadmin00000000001'")] if c in tables["admin_users"]]
    cols = pairs + extra
    out.append("INSERT INTO admin_users (%s) SELECT %s WHERE NOT EXISTS (SELECT 1 FROM admin_users WHERE email = %s);"
               % (", ".join(q(c) for c, _ in cols), ", ".join(v for _, v in cols), lit(scan.CI_ADMIN_EMAIL)))
    out.append("INSERT INTO %s (user_id, role_id) SELECT u.id, r.id FROM admin_users u, admin_roles r "
               "WHERE u.email = %s AND r.code = 'strapi-super-admin' AND NOT EXISTS "
               "(SELECT 1 FROM %s l WHERE l.user_id = u.id AND l.role_id = r.id);"
               % (q(link), lit(scan.CI_ADMIN_EMAIL), q(link)))
    return out


def sanitize_sql(columns, pii, truncate):
    """SQL that replaces personal data and secrets in a restored Strapi v4/v5 database."""
    tables = _tables(columns)
    out = _admin_sql(tables)
    out += _set(tables, "up_users", [
        ("email", "'user' || id || '@example.invalid'"), ("username", "'user' || id"), ("password", "NULL"),
        ("reset_password_token", "NULL"), ("confirmation_token", "NULL")])
    emptied = sorted(t for t in tables if t in EMPTIED)
    if emptied:
        # No CASCADE: an unexpected foreign key into these tables must fail loudly.
        out.append("TRUNCATE TABLE %s;" % ", ".join(q(t) for t in emptied))
    by_table = {}
    for table, column, data_type in pii:
        has_id = "id" in tables.get(table, ())
        if data_type not in TEXT_TYPES:
            value = "NULL"
        elif EMAIL_NAME.search(column):
            value = "'redacted-' || id || '@example.invalid'" if has_id else "'redacted@example.invalid'"
        else:
            value = "'redacted-' || id" if has_id else "'redacted'"
        by_table.setdefault(table, []).append("%s = %s" % (q(column), value))
    for table, sets in by_table.items():
        out.append("UPDATE %s SET %s;" % (q(table), ", ".join(sets)))
    out += ["DELETE FROM %s;" % q(t) for t in truncate]
    return "\n".join(out) + "\n"


def blank_secrets(value):
    """Recursively replace string values under secret-looking keys with ""."""
    if isinstance(value, dict):
        return {k: ("" if isinstance(v, str) and SECRET_KEY.match(k) else blank_secrets(v)) for k, v in value.items()}
    if isinstance(value, list):
        return [blank_secrets(v) for v in value]
    return value


# --- Docker orchestration (exercised by the manual round trip in the README, not by unit tests) ---

def _run(args, **kw):
    return subprocess.run(args, check=True, **kw)


def _psql(name, sql=None, query=None):
    base = ["docker", "exec", "-i", name, "psql", "-v", "ON_ERROR_STOP=1", "-q", "-U", "postgres", "-d", "fixture"]
    if query:
        return _run(base + ["-At", "-F", "\t", "-c", query], capture_output=True, text=True).stdout
    return _run(base, input=sql, text=True)


def _core_store_updates(name):
    rows = _psql(name, query="SELECT id, replace(encode(convert_to(value, 'UTF8'), 'base64'), E'\\n', '') "
                             "FROM strapi_core_store_settings WHERE value IS NOT NULL")
    out = []
    for line in rows.splitlines():
        rid, b64 = line.split("\t", 1)
        try:
            value = json.loads(base64.b64decode(b64).decode("utf-8"))
        except ValueError:
            continue
        new = blank_secrets(value)
        if new != value:
            enc = base64.b64encode(json.dumps(new).encode("utf-8")).decode("ascii")
            out.append("UPDATE strapi_core_store_settings SET value = convert_from(decode('%s', 'base64'), 'UTF8') "
                       "WHERE id = %d;" % (enc, int(rid)))
    return out


def main(argv):
    ap = argparse.ArgumentParser(description="Make a sanitized Strapi fixture (ci/fixture.sql.gz).")
    ap.add_argument("--source-env", required=True, help="name of the environment variable holding the source Postgres URL")
    ap.add_argument("--repo", required=True, help="the Strapi repository checkout to write ci/fixture.sql.gz into")
    ap.add_argument("--truncate", action="append", default=[], help="empty this table (repeatable), e.g. form submissions")
    ap.add_argument("--postgres-image", default="postgres:16",
                    help="must match the repo's verify postgres-version and be >= the source server's major version")
    a = ap.parse_args(argv)
    if not os.environ.get(a.source_env):
        print("environment variable %s is empty" % a.source_env, file=sys.stderr)
        return 2
    ci_dir = os.path.join(a.repo, "ci")
    pii_extra = {tuple(e.split(".", 1)) for e in parse_list_file(os.path.join(ci_dir, "fixture-pii.txt")) if "." in e}
    name = "strapi-fixture-%d" % os.getpid()
    env = dict(os.environ, SRC=os.environ[a.source_env])
    try:
        _run(["docker", "run", "-d", "--rm", "--name", name, "-e", "POSTGRES_PASSWORD=fixture",
              "-e", "POSTGRES_DB=fixture", a.postgres_image], capture_output=True)
        for _ in range(60):
            if subprocess.run(["docker", "exec", name, "pg_isready", "-h", "127.0.0.1", "-U", "postgres", "-d", "fixture"],
                              capture_output=True).returncode == 0:
                break
            time.sleep(1)
        else:
            print("throwaway Postgres did not become ready", file=sys.stderr)
            return 1
        print("copying the source database into the throwaway container (read-only on the source)")
        _run(["docker", "exec", "-e", "SRC", name, "bash", "-o", "pipefail", "-c",
              'pg_dump --no-owner --no-privileges "$SRC" | psql -v ON_ERROR_STOP=1 -q -U postgres -d fixture > /dev/null'], env=env)
        columns = [tuple(l.split("\t")) for l in _psql(name, query=(
            "SELECT table_name, column_name, data_type FROM information_schema.columns "
            "WHERE table_schema = 'public' ORDER BY table_name, ordinal_position")).splitlines()]
        sql = sanitize_sql(columns, pii_columns(columns, pii_extra), a.truncate)
        if any(c[0] == "strapi_core_store_settings" for c in columns):
            sql += "\n".join(_core_store_updates(name)) + "\n"
        _psql(name, sql="BEGIN;\n" + sql + "COMMIT;\n")
        fd, tmp = tempfile.mkstemp(suffix=".sql.gz")
        with os.fdopen(fd, "wb") as out:
            _run(["docker", "exec", name, "bash", "-o", "pipefail", "-c",
                  "pg_dump --no-owner --no-privileges -U postgres fixture | gzip -9"], stdout=out)
        if scan.main(["--strapi-dump", "--allow", os.path.join(ci_dir, "fixture-allow.txt"), tmp]) != 0:
            print("the sanitized dump still failed the scan (above); nothing written. List the columns in "
                  "ci/fixture-pii.txt, or business addresses in ci/fixture-allow.txt, and run again.", file=sys.stderr)
            os.unlink(tmp)
            return 1
        size = os.path.getsize(tmp)
        if size > MAX_BYTES:
            print("fixture is %d MB; over the 50 MB cap: truncate large tables (--truncate) instead of sampling"
                  % (size // (1024 * 1024)), file=sys.stderr)
            os.unlink(tmp)
            return 1
        os.makedirs(ci_dir, exist_ok=True)
        shutil.move(tmp, os.path.join(ci_dir, "fixture.sql.gz"))  # tmp may be on another filesystem
        print("wrote %s (%d KB). Never restore it into a real environment." % (os.path.join(ci_dir, "fixture.sql.gz"), size // 1024))
        return 0
    except subprocess.CalledProcessError as e:
        print("command failed (exit %d): %s" % (e.returncode, " ".join(e.cmd[:4])), file=sys.stderr)
        return 1
    finally:
        subprocess.run(["docker", "rm", "-f", name], capture_output=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
