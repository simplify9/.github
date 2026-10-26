import io
import json
import os
import tempfile
import threading
import unittest
from contextlib import redirect_stderr, redirect_stdout
from http.server import BaseHTTPRequestHandler, HTTPServer

import api_check as a


def schema(root, api, kind, singular, plural):
    d = os.path.join(root, "src", "api", api, "content-types", singular)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "schema.json"), "w") as f:
        json.dump({"kind": kind, "info": {"singularName": singular, "pluralName": plural}}, f)


def write(d, name, text):
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, name + ".json"), "w") as f:
        f.write(text)


class Stub:
    """Tiny Strapi stand-in: routes maps (method, path) -> (status, body)."""

    def __init__(self, routes):
        seen = self.seen = []

        class H(BaseHTTPRequestHandler):
            def _reply(self):
                path = self.path.split("?", 1)[0]
                n = int(self.headers.get("Content-Length") or 0)
                sent = json.loads(self.rfile.read(n)) if n else None
                seen.append((self.command, self.path, self.headers.get("Authorization"), sent))
                status, body = routes.get((self.command, path), (404, {"error": "nope"}))
                data = json.dumps(body).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            do_GET = do_POST = _reply

            def log_message(self, *args):
                pass

        self.server = HTTPServer(("127.0.0.1", 0), H)
        self.url = "http://127.0.0.1:%d" % self.server.server_port
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()


def run(argv):
    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        rc = a.main(argv)
    return rc, out.getvalue(), err.getvalue()


class Types(unittest.TestCase):
    def test_types_union_and_kinds(self):
        with tempfile.TemporaryDirectory() as base, tempfile.TemporaryDirectory() as head:
            schema(base, "article", "collectionType", "article", "articles")
            schema(head, "article", "collectionType", "article", "articles")
            schema(head, "home", "singleType", "home", "homes")
            self.assertEqual(a.content_types([base, head]), [
                {"kind": "collectionType", "singularName": "article", "pluralName": "articles"},
                {"kind": "singleType", "singularName": "home", "pluralName": "homes"}])

    def test_types_ignores_components_and_bad_json(self):
        with tempfile.TemporaryDirectory() as root:
            schema(root, "article", "collectionType", "article", "articles")
            os.makedirs(os.path.join(root, "src", "components", "shared"))
            with open(os.path.join(root, "src", "components", "shared", "seo.json"), "w") as f:
                f.write("{}")
            bad = os.path.join(root, "src", "api", "x", "content-types", "x")
            os.makedirs(bad)
            with open(os.path.join(bad, "schema.json"), "w") as f:
                f.write("{not json")
            self.assertEqual([t["pluralName"] for t in a.content_types([root])], ["articles"])


class Compare(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.before = os.path.join(self.tmp.name, "api-before")
        self.after = os.path.join(self.tmp.name, "api-after")
        write(self.before, "articles", '{"data": [1]}')
        write(self.before, "homes", '{"data": {}}')

    def tearDown(self):
        self.tmp.cleanup()

    def test_compare_equal(self):
        write(self.after, "articles", '{"data": [1]}')
        write(self.after, "homes", '{"data": {}}')
        self.assertEqual(a.compare_snapshots(self.before, self.after, set()), ([], []))

    def test_compare_changed_fails(self):
        write(self.after, "articles", '{"data": [2]}')
        write(self.after, "homes", '{"data": {}}')
        self.assertEqual(a.compare_snapshots(self.before, self.after, set()),
                         (["[VERIFY] rehearsal: api articles response changed"], []))
        self.assertTrue(os.path.exists(os.path.join(self.tmp.name, "diff", "api-articles.diff")))

    def test_compare_removed_fails(self):
        write(self.after, "articles", '{"data": [1]}')
        self.assertEqual(a.compare_snapshots(self.before, self.after, set()),
                         (["[VERIFY] rehearsal: api homes removed"], []))

    def test_compare_new_ignored(self):
        write(self.after, "articles", '{"data": [1]}')
        write(self.after, "homes", '{"data": {}}')
        write(self.after, "pages", '{"data": []}')
        self.assertEqual(a.compare_snapshots(self.before, self.after, set()), ([], []))

    def test_compare_declared_reported(self):
        write(self.after, "articles", '{"data": [2]}')
        write(self.after, "homes", '{"data": {}}')
        self.assertEqual(a.compare_snapshots(self.before, self.after, {"articles"}),
                         ([], ["[VERIFY] rehearsal: api articles response changed (declared)"]))

    def test_compare_cli_reads_api_lines_only(self):
        write(self.after, "articles", '{"data": [2]}')
        write(self.after, "homes", '{"data": {}}')
        decl = os.path.join(self.tmp.name, "declared.txt")
        with open(decl, "w") as f:
            f.write("articles.title\napi:articles\n")
        rc, out, _ = run(["compare", "--before", self.before, "--after", self.after, "--declared", decl])
        self.assertEqual(rc, 0)
        self.assertIn("api articles response changed (declared)", out)


class ReviewFixes(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.before = os.path.join(self.tmp.name, "api-before")
        self.after = os.path.join(self.tmp.name, "api-after")

    def tearDown(self):
        self.tmp.cleanup()

    def test_compare_additions_ignored(self):
        write(self.before, "articles", '{"data": [{"id": 1, "title": "a"}], "meta": {}}')
        write(self.after, "articles", '{"data": [{"id": 1, "title": "a", "slug": null}], "meta": {"x": 1}}')
        self.assertEqual(a.compare_snapshots(self.before, self.after, set()), ([], []))

    def test_compare_removed_key_or_entry_fails(self):
        write(self.before, "articles", '{"data": [{"id": 1, "title": "a"}, {"id": 2, "title": "b"}]}')
        write(self.after, "articles", '{"data": [{"id": 1}, {"id": 2, "title": "b"}]}')
        self.assertEqual(a.compare_snapshots(self.before, self.after, set())[0],
                         ["[VERIFY] rehearsal: api articles response changed"])
        write(self.after, "articles", '{"data": [{"id": 1, "title": "a"}]}')
        self.assertEqual(len(a.compare_snapshots(self.before, self.after, set())[0]), 1)

    def test_compare_nothing_compared_fails(self):
        write(self.before, "articles", '{"status": 403}')
        write(self.after, "articles", '{"status": 403}')
        self.assertEqual(a.compare_snapshots(self.before, self.after, set())[0],
                         ["[VERIFY] rehearsal: api check compared nothing: every content type answered non-200 at base"])

    def test_compare_no_types_is_fine(self):
        os.makedirs(self.before)
        os.makedirs(self.after)
        self.assertEqual(a.compare_snapshots(self.before, self.after, set()), ([], []))

    def test_token_body_has_no_lifespan(self):
        stub = Stub({("POST", "/admin/login"): (200, {"data": {"token": "jwt"}}),
                     ("POST", "/admin/api-tokens"): (201, {"data": {"accessKey": "k"}})})
        try:
            run(["token", "--base-url", stub.url])
        finally:
            stub.close()
        self.assertNotIn("lifespan", stub.seen[1][3])
        self.assertEqual(stub.seen[1][3]["type"], "read-only")


class Http(unittest.TestCase):
    def test_token_ok(self):
        stub = Stub({("POST", "/admin/login"): (200, {"data": {"token": "jwt"}}),
                     ("POST", "/admin/api-tokens"): (201, {"data": {"accessKey": "k123"}})})
        try:
            rc, out, _ = run(["token", "--base-url", stub.url])
        finally:
            stub.close()
        self.assertEqual((rc, out.strip()), (0, "k123"))
        self.assertEqual(stub.seen[1][2], "Bearer jwt")

    def test_token_login_failure_message(self):
        stub = Stub({("POST", "/admin/login"): (400, {"error": {"message": "Invalid credentials"}})})
        try:
            rc, _, err = run(["token", "--base-url", stub.url])
        finally:
            stub.close()
        self.assertEqual(rc, 1)
        self.assertIn("regenerate it with scripts/strapi-fixture", err)

    def test_snapshot_writes_sorted_json_and_status(self):
        stub = Stub({("GET", "/api/articles"): (200, {"data": [{"b": 1, "a": 2}]})})
        with tempfile.TemporaryDirectory() as d:
            types = os.path.join(d, "types.json")
            with open(types, "w") as f:
                json.dump([{"kind": "collectionType", "singularName": "article", "pluralName": "articles"},
                           {"kind": "singleType", "singularName": "home", "pluralName": "homes"}], f)
            out = os.path.join(d, "snap")
            try:
                rc, _, _ = run(["snapshot", "--base-url", stub.url, "--token", "k", "--types", types, "--out", out])
            finally:
                stub.close()
            self.assertEqual(rc, 0)
            with open(os.path.join(out, "articles.json")) as f:
                self.assertEqual(f.read(), json.dumps({"data": [{"a": 2, "b": 1}]}, sort_keys=True, indent=1))
            with open(os.path.join(out, "homes.json")) as f:
                self.assertEqual(json.load(f), {"status": 404})
        self.assertTrue(stub.seen[0][1].startswith("/api/articles?"))
        self.assertIn("sort=id%3Aasc", stub.seen[0][1])
        self.assertEqual(stub.seen[1][1].split("?")[0], "/api/home")
        self.assertEqual(stub.seen[0][2], "Bearer k")


if __name__ == "__main__":
    unittest.main()
