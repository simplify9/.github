#!/usr/bin/env python3
"""Generated test data for the Strapi upgrade rehearsal when a repo has no ci/fixture.sql.gz (stdlib only).

  seed.py --app DIR --base-url URL --db-url URL [--schema S]

Runs against the base version booted on an empty throwaway database:
- inserts the CI admin (SQL: an app's bootstrap may already have created an admin, which makes
  /admin/register-admin refuse) and one `files` row that every media field points at (no upload, so any
  upload provider works);
- logs in, creates a full-access API token and creates published entries from the repo's schemas:
  3 per collection type, 1 per single type, values derived from type, name and index (never random).
Relations, passwords and custom fields are left out. Strapi 5 only.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import subprocess
import sys

import api_check

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "verify-secret-scan"))
import scan  # noqa: E402

MAX_DEPTH = 5
DOCUMENT_ID_ADMIN = "verifyciadmin00000000001"
DOCUMENT_ID_FILE = "verifyseedfile0000000001"


def load_schemas(app_dir):
    """-> (content types sorted by file path, components keyed 'category.name')."""
    types = []
    for path in sorted(glob.glob(os.path.join(app_dir, "src", "api", "*", "content-types", "*", "schema.json"))):
        with open(path, encoding="utf-8") as f:
            types.append(json.load(f))
    components = {}
    for path in glob.glob(os.path.join(app_dir, "src", "components", "*", "*.json")):
        with open(path, encoding="utf-8") as f:
            components["%s.%s" % (os.path.basename(os.path.dirname(path)), os.path.basename(path)[:-5])] = json.load(f)
    return types, components


def _clamp(v, attr):
    if "min" in attr:
        v = max(v, attr["min"])
    if "max" in attr:
        v = min(v, attr["max"])
    return v


def value(name, attr, i, components, media_id, depth=0):
    """The generated value of one attribute, or None to leave it out."""
    t = attr.get("type")
    if attr.get("customField"):
        return None
    if t in ("string", "text"):
        v = "%s %d" % (name, i)
        if attr.get("maxLength"):
            v = v[: attr["maxLength"]]
        return v.ljust(attr.get("minLength") or 0, "x")
    if t == "richtext":
        return "**%s** %d" % (name, i)
    if t == "blocks":
        return [{"type": "paragraph", "children": [{"type": "text", "text": "%s %d" % (name, i)}]}]
    if t == "email":
        return "%s%d@example.com" % (name.lower(), i)
    if t == "uid":
        return "%s-%d" % (name.lower(), i)
    if t == "enumeration":
        return attr["enum"][0] if attr.get("enum") else None
    if t in ("integer", "biginteger"):
        return _clamp(i + 1, attr)
    if t in ("float", "decimal"):
        return _clamp(i + 0.5, attr)
    if t == "boolean":
        return True
    if t == "date":
        return "2026-01-%02d" % (i + 1)
    if t in ("datetime", "timestamp"):
        return "2026-01-%02dT10:00:00.000Z" % (i + 1)
    if t == "time":
        return "10:00:00.000"
    if t == "json":
        return {"field": name, "i": i}
    if t == "media":
        return [media_id] if attr.get("multiple") else media_id
    if t == "component":
        comp = components.get(attr.get("component"))
        if comp is None or depth >= MAX_DEPTH + 1:
            return None
        one = lambda k: entry(comp.get("attributes", {}), k, components, media_id, depth + 1)  # noqa: E731
        if attr.get("repeatable"):
            return [one(k) for k in range(_clamp(2, attr))]
        return one(i)
    if t == "dynamiczone":
        if depth >= MAX_DEPTH + 1:
            return None
        return [dict({"__component": c}, **entry(components[c].get("attributes", {}), i, components, media_id, depth + 1))
                for c in attr.get("components", []) if c in components]
    return None  # relation, password, unknown


def entry(attributes, i, components, media_id, depth=0):
    out = {}
    for name, attr in attributes.items():
        v = value(name, attr, i, components, media_id, depth)
        if v is not None:
            out[name] = v
    return out


def _q(ident):
    return '"' + ident.replace('"', '""') + '"'


def _lit(text):
    return "'" + text.replace("'", "''") + "'"


def ci_admin_sql(schema, admin_columns, link_table):
    """Insert the CI admin (super admin) unless present; the password is scan.CI_ADMIN_HASH."""
    s = _q(schema)
    email = _lit(scan.CI_ADMIN_EMAIL)
    cols = [("firstname", "'CI'"), ("lastname", "'Admin'"), ("email", email), ("password", _lit(scan.CI_ADMIN_HASH)),
            ("is_active", "true"), ("blocked", "false"), ("document_id", _lit(DOCUMENT_ID_ADMIN)),
            ("published_at", "now()"), ("created_at", "now()"), ("updated_at", "now()")]
    cols = [(c, v) for c, v in cols if c in admin_columns]
    link = "%s.%s" % (s, _q(link_table))
    return ("INSERT INTO %s.admin_users (%s) SELECT %s WHERE NOT EXISTS (SELECT 1 FROM %s.admin_users WHERE email = %s);\n"
            "INSERT INTO %s (user_id, role_id) SELECT u.id, r.id FROM %s.admin_users u, %s.admin_roles r "
            "WHERE u.email = %s AND r.code = 'strapi-super-admin' AND NOT EXISTS "
            "(SELECT 1 FROM %s l WHERE l.user_id = u.id AND l.role_id = r.id);\n"
            % (s, ", ".join(c for c, _ in cols), ", ".join(v for _, v in cols), s, email, link, s, s, email, link))


def media_sql(schema, file_columns):
    """One `files` row for every media field; RETURNING its id."""
    cols = [("name", "'verify.png'"), ("hash", "'verify_seed'"), ("ext", "'.png'"), ("mime", "'image/png'"),
            ("size", "0.07"), ("url", "'/uploads/verify_seed.png'"), ("provider", "'local'"), ("folder_path", "'/'"),
            ("width", "1"), ("height", "1"), ("document_id", _lit(DOCUMENT_ID_FILE)), ("published_at", "now()"),
            ("created_at", "now()"), ("updated_at", "now()")]
    cols = [(c, v) for c, v in cols if c in file_columns]
    return "INSERT INTO %s.files (%s) VALUES (%s) RETURNING id;" % (
        _q(schema), ", ".join(c for c, _ in cols), ", ".join(v for _, v in cols))


def strapi_major(app_dir):
    """The installed @strapi/strapi major, else the first number of its range in package.json, else 5."""
    try:
        with open(os.path.join(app_dir, "node_modules", "@strapi", "strapi", "package.json"), encoding="utf-8") as f:
            return int(json.load(f)["version"].split(".")[0])
    except (OSError, ValueError, KeyError):
        pass
    try:
        with open(os.path.join(app_dir, "package.json"), encoding="utf-8") as f:
            rng = json.load(f).get("dependencies", {}).get("@strapi/strapi", "")
    except (OSError, ValueError):
        rng = ""
    m = re.search(r"\d+", rng)
    return int(m.group()) if m else 5


def _psql(db_url, sql):
    return subprocess.run(["psql", db_url, "-v", "ON_ERROR_STOP=1", "-qAt", "-c", sql],
                          check=True, capture_output=True, text=True).stdout


def _names(db_url, schema, query):
    return set(_psql(db_url, query % _lit(schema)).split())


def _reason(body):
    err = (body or {}).get("error") if isinstance(body, dict) else None
    if not isinstance(err, dict):
        return "no error message"
    msg = str(err.get("message", ""))
    details = [("%s: %s" % (".".join(map(str, e.get("path", []))), e.get("message", "")))
               for e in (err.get("details") or {}).get("errors", []) if isinstance(e, dict)]
    return ("%s (%s)" % (msg, "; ".join(details)) if details else msg)[:300]


def main(argv):
    ap = argparse.ArgumentParser(description="Generate published test data in an empty Strapi 5")
    for opt in ("--app", "--base-url", "--db-url"):
        ap.add_argument(opt, required=True)
    ap.add_argument("--schema", default="public")
    a = ap.parse_args(argv)
    if strapi_major(a.app) < 5:
        print("::error title=[VERIFY] Rehearsal::generated data needs Strapi 5; add ci/fixture.sql.gz", file=sys.stderr)
        return 1
    try:
        types, components = load_schemas(a.app)
        cols = "SELECT column_name FROM information_schema.columns WHERE table_schema = %s AND table_name = '%s'"
        tables = _names(a.db_url, a.schema, "SELECT table_name FROM information_schema.tables WHERE table_schema = %s")
        link = "admin_users_roles_lnk" if "admin_users_roles_lnk" in tables else "admin_users_roles_links"
        _psql(a.db_url, ci_admin_sql(a.schema, _names(a.db_url, a.schema, cols.replace("'%s'", "'admin_users'")), link))
        media_id = int(_psql(a.db_url, media_sql(a.schema, _names(a.db_url, a.schema, cols.replace("'%s'", "'files'")))).split()[0])
        status, body = api_check._request("POST", a.base_url + "/admin/login",
                                          body={"email": scan.CI_ADMIN_EMAIL, "password": api_check.CI_ADMIN_PASSWORD})
        jwt = ((body or {}).get("data") or {}).get("token")
        if status != 200 or not jwt:
            raise RuntimeError("admin login as the CI admin failed (HTTP %s)" % status)
        status, body = api_check._request("POST", a.base_url + "/admin/api-tokens", token=jwt, body={
            "name": "verify-seed-%d" % os.getpid(), "description": "verify generated data", "type": "full-access"})
        key = ((body or {}).get("data") or {}).get("accessKey")
        if status not in (200, 201) or not key:
            raise RuntimeError("creating a full-access API token failed (HTTP %s)" % status)
    except (subprocess.CalledProcessError, OSError, ValueError, RuntimeError, IndexError) as e:
        print("::error title=[VERIFY] Rehearsal::generated data: %s" % e, file=sys.stderr)
        return 1
    created = 0
    for t in types:
        info, single = t["info"], t.get("kind") == "singleType"
        n, ok = (1 if single else 3), 0
        for i in range(n):
            data = entry(t.get("attributes", {}), i, components, media_id)
            if single:
                status, body = api_check._request("PUT", "%s/api/%s?status=published" % (a.base_url, info["singularName"]),
                                                  token=key, body={"data": data})
            else:
                status, body = api_check._request("POST", "%s/api/%s?status=published" % (a.base_url, info["pluralName"]),
                                                  token=key, body={"data": data})
            if status in (200, 201):
                ok += 1
            else:
                print("[VERIFY] generated: %s #%d rejected (HTTP %s): %s" % (info["pluralName"], i, status, _reason(body)))
        print("[VERIFY] generated: %s: %d/%d created" % (info["pluralName"], ok, n))
        created += ok
    if not created:
        print("::error title=[VERIFY] Rehearsal::generated data: no entry could be created (see the rejections above)",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
