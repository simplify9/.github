#!/usr/bin/env python3
"""Content-API comparison for the Strapi upgrade rehearsal (stdlib only).

  api_check.py types --src DIR...                      content types from src/api/*/content-types/*/schema.json (JSON)
  api_check.py token --base-url URL                    log in as the fixture's CI admin, print a read-only API token
  api_check.py snapshot --base-url URL --token T --types FILE --out DIR
  api_check.py compare --before DIR --after DIR --declared FILE

Base and head boot on the same restored fixture, so their API responses must match unless the PR
declares `api:<pluralName>` in ci/rehearsal-expected-changes.txt.
"""
from __future__ import annotations

import argparse
import difflib
import glob
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

# The CI admin scripts/strapi-fixture puts into every fixture. Public by design: valid only in throwaway databases.
CI_ADMIN_EMAIL = "ci-admin@example.invalid"
CI_ADMIN_PASSWORD = "VerifyCiOnly-1"
TIMEOUT = 30


def content_types(dirs):
    found = {}
    for d in dirs:
        for path in glob.glob(os.path.join(d, "src", "api", "*", "content-types", "*", "schema.json")):
            try:
                with open(path, encoding="utf-8") as f:
                    s = json.load(f)
                t = {"kind": s["kind"], "singularName": s["info"]["singularName"], "pluralName": s["info"]["pluralName"]}
            except (ValueError, KeyError, TypeError):
                print("[VERIFY] rehearsal: skipped unreadable %s" % path, file=sys.stderr)
                continue
            found[t["pluralName"]] = t
    return [found[k] for k in sorted(found)]


def _request(method, url, token=None, body=None):
    """-> (status, parsed JSON or None); an HTTP error returns its JSON body when it has one."""
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={"Content-Type": "application/json"})
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return r.status, json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"null")
        except ValueError:
            return e.code, None


def api_token(base_url):
    status, body = _request("POST", base_url + "/admin/login", body={"email": CI_ADMIN_EMAIL, "password": CI_ADMIN_PASSWORD})
    if status != 200 or not ((body or {}).get("data") or {}).get("token"):
        raise RuntimeError("admin login as %s failed (HTTP %s): the fixture has no CI admin (or a different password); "
                           "regenerate it with scripts/strapi-fixture" % (CI_ADMIN_EMAIL, status))
    status, created = _request("POST", base_url + "/admin/api-tokens", token=body["data"]["token"],
                               body={"name": "verify-ci", "description": "verify rehearsal", "type": "read-only"})
    key = ((created or {}).get("data") or {}).get("accessKey")
    if status not in (200, 201) or not key:
        raise RuntimeError("creating a read-only API token failed (HTTP %s)" % status)
    return key


def snapshot(base_url, token, types, out):
    os.makedirs(out, exist_ok=True)
    for t in types:
        if t["kind"] == "collectionType":
            query = urllib.parse.urlencode({"pagination[page]": 1, "pagination[pageSize]": 100, "populate": "*", "sort": "id:asc"})
            url = "%s/api/%s?%s" % (base_url, t["pluralName"], query)
        else:
            url = "%s/api/%s?%s" % (base_url, t["singularName"], urllib.parse.urlencode({"populate": "*"}))
        status, body = _request("GET", url, token=token)
        obj = body if status == 200 else {"status": status}
        with open(os.path.join(out, t["pluralName"] + ".json"), "w", encoding="utf-8") as f:
            f.write(json.dumps(obj, sort_keys=True, indent=1))


def _covers(base, head):
    """True when head keeps everything base had: equal scalars, equal list lengths. Keys only in head are
    additions (a new field, new meta), which a consumer of the API does not break on, so they pass."""
    if isinstance(base, dict):
        return isinstance(head, dict) and all(k in head and _covers(v, head[k]) for k, v in base.items())
    if isinstance(base, list):
        return isinstance(head, list) and len(base) == len(head) and all(_covers(b, h) for b, h in zip(base, head))
    return base == head


def _is_status(obj):
    return isinstance(obj, dict) and set(obj) == {"status"}


def compare_snapshots(before_dir, after_dir, declared):
    """-> (failures, reported). Diffs go to <parent of before_dir>/diff/api-<pluralName>.diff."""
    diff_dir = os.path.join(os.path.dirname(os.path.abspath(before_dir)), "diff")
    failures, reported = [], []
    names = sorted(n for n in os.listdir(before_dir) if n.endswith(".json"))
    compared = 0
    for name in names:
        plural = name[:-5]
        b, after = os.path.join(before_dir, name), os.path.join(after_dir, name)
        with open(b, encoding="utf-8") as f1:
            old = f1.read()
        compared += not _is_status(json.loads(old))
        if not os.path.exists(after):
            msg = "[VERIFY] rehearsal: api %s removed" % plural
        else:
            with open(after, encoding="utf-8") as f2:
                new = f2.read()
            if _covers(json.loads(old), json.loads(new)):
                continue
            old, new = old.splitlines(True), new.splitlines(True)
            os.makedirs(diff_dir, exist_ok=True)
            with open(os.path.join(diff_dir, "api-%s.diff" % plural), "w", encoding="utf-8") as f:
                f.writelines(difflib.unified_diff(old, new, "base/" + name, "head/" + name))
            msg = "[VERIFY] rehearsal: api %s response changed" % plural
        if plural in declared:
            reported.append(msg + " (declared)")
        else:
            failures.append(msg)
    if names and not compared:
        failures.append("[VERIFY] rehearsal: api check compared nothing: every content type answered non-200 at base")
    return failures, reported


def main(argv):
    ap = argparse.ArgumentParser(description="Strapi content-API comparison for the upgrade rehearsal")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("types")
    p.add_argument("--src", nargs="+", required=True)
    p = sub.add_parser("token")
    p.add_argument("--base-url", required=True)
    p = sub.add_parser("snapshot")
    for opt in ("--base-url", "--token", "--types", "--out"):
        p.add_argument(opt, required=True)
    p = sub.add_parser("compare")
    for opt in ("--before", "--after", "--declared"):
        p.add_argument(opt, required=True)
    a = ap.parse_args(argv)
    try:
        if a.cmd == "types":
            print(json.dumps(content_types(a.src)))
        elif a.cmd == "token":
            print(api_token(a.base_url))
        elif a.cmd == "snapshot":
            with open(a.types, encoding="utf-8") as f:
                snapshot(a.base_url, a.token, json.load(f), a.out)
        else:
            declared = set()
            if os.path.exists(a.declared):
                with open(a.declared, encoding="utf-8") as f:
                    declared = {l.strip()[4:] for l in f if l.strip().startswith("api:")}
            failures, reported = compare_snapshots(a.before, a.after, declared)
            for line in sorted(failures + reported):
                print(line)
            return 1 if failures else 0
    except (RuntimeError, OSError, urllib.error.URLError) as e:
        print("::error title=[VERIFY] Rehearsal::%s" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
