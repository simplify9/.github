import io
import json
import os
import stat
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

import seed as s
from test_api_check import Stub

COMPONENTS = {
    "shared.seo": {"attributes": {"metaTitle": {"type": "string", "maxLength": 60}}},
    "shared.loop": {"attributes": {"label": {"type": "string"}, "child": {"type": "component", "component": "shared.loop"}}},
}

# Stub psql: logs each -c SQL to $PSQL_LOG, answers column and table queries, prints 1 for RETURNING.
PSQL = r'''import os, sys
sql = sys.argv[sys.argv.index("-c") + 1]
with open(os.environ["PSQL_LOG"], "a") as f:
    f.write(sql + "\n---\n")
if "information_schema.columns" in sql and "'admin_users'" in sql:
    print("\n".join(["id", "document_id", "firstname", "lastname", "username", "email", "password", "is_active",
                     "blocked", "created_at", "updated_at", "published_at"]))
elif "information_schema.columns" in sql and "'files'" in sql:
    print("\n".join(["id", "document_id", "name", "hash", "ext", "mime", "size", "url", "provider", "folder_path",
                     "width", "height", "created_at", "updated_at", "published_at"]))
elif "information_schema.tables" in sql:
    print("admin_users\nadmin_users_roles_lnk\nadmin_roles\nfiles")
elif "RETURNING id" in sql:
    print("7")
'''


def app(root, strapi="5.52.1", installed=None):
    os.makedirs(os.path.join(root, "src", "api", "article", "content-types", "article"))
    os.makedirs(os.path.join(root, "src", "api", "home", "content-types", "home"))
    with open(os.path.join(root, "package.json"), "w") as f:
        json.dump({"dependencies": {"@strapi/strapi": strapi}}, f)
    if installed:
        d = os.path.join(root, "node_modules", "@strapi", "strapi")
        os.makedirs(d)
        with open(os.path.join(d, "package.json"), "w") as f:
            json.dump({"version": installed}, f)
    with open(os.path.join(root, "src", "api", "article", "content-types", "article", "schema.json"), "w") as f:
        json.dump({"kind": "collectionType", "info": {"singularName": "article", "pluralName": "articles"},
                   "attributes": {"title": {"type": "string", "required": True}, "cover": {"type": "media"}}}, f)
    with open(os.path.join(root, "src", "api", "home", "content-types", "home", "schema.json"), "w") as f:
        json.dump({"kind": "singleType", "info": {"singularName": "home", "pluralName": "homes"},
                   "attributes": {"heading": {"type": "string"}}}, f)


class Values(unittest.TestCase):
    def v(self, attr, name="body", i=0):
        return s.value(name, attr, i, COMPONENTS, 7)

    def test_values_by_type(self):
        cases = [
            ({"type": "string"}, "body 0"), ({"type": "text"}, "body 0"), ({"type": "richtext"}, "**body** 0"),
            ({"type": "blocks"}, [{"type": "paragraph", "children": [{"type": "text", "text": "body 0"}]}]),
            ({"type": "email"}, "body0@example.com"), ({"type": "uid"}, "body-0"),
            ({"type": "enumeration", "enum": ["draft", "live"]}, "draft"),
            ({"type": "integer"}, 1), ({"type": "integer", "min": 5}, 5), ({"type": "integer", "max": 0}, 0),
            ({"type": "biginteger"}, 1), ({"type": "float"}, 0.5), ({"type": "decimal", "min": 2}, 2),
            ({"type": "boolean"}, True), ({"type": "date"}, "2026-01-01"),
            ({"type": "datetime"}, "2026-01-01T10:00:00.000Z"), ({"type": "timestamp"}, "2026-01-01T10:00:00.000Z"),
            ({"type": "time"}, "10:00:00.000"), ({"type": "json"}, {"field": "body", "i": 0}),
            ({"type": "media"}, 7), ({"type": "media", "multiple": True}, [7]),
            ({"type": "component", "component": "shared.seo"}, {"metaTitle": "metaTitle 0"}),
            ({"type": "relation", "relation": "oneToMany", "target": "api::x.x"}, None), ({"type": "password"}, None),
            ({"type": "string", "customField": "plugin::color-picker.color"}, None), ({"type": "novel"}, None),
            ({"type": "component", "component": "missing.one"}, None),
        ]
        for attr, want in cases:
            self.assertEqual(self.v(attr), want, attr)
        self.assertEqual(s.value("ContactEmail", {"type": "email"}, 2, COMPONENTS, 7), "contactemail2@example.com")
        self.assertEqual(s.value("Slug", {"type": "uid"}, 2, COMPONENTS, 7), "slug-2")

    def test_string_lengths(self):
        self.assertEqual(s.value("title", {"type": "string", "maxLength": 4}, 0, COMPONENTS, 7), "titl")
        self.assertEqual(s.value("title", {"type": "string", "minLength": 12}, 0, COMPONENTS, 7), "title 0xxxxx")

    def test_repeatable_respects_min_max(self):
        rep = {"type": "component", "component": "shared.seo", "repeatable": True}
        self.assertEqual(len(self.v(dict(rep, min=3))), 3)
        self.assertEqual(len(self.v(dict(rep, max=1))), 1)
        self.assertEqual(len(self.v(rep)), 2)

    def test_dynamiczone_one_per_component(self):
        dz = self.v({"type": "dynamiczone", "components": ["shared.seo", "shared.loop"]})
        self.assertEqual([d["__component"] for d in dz], ["shared.seo", "shared.loop"])
        self.assertEqual(dz[0]["metaTitle"], "metaTitle 0")

    def test_depth_cap(self):
        v = self.v({"type": "component", "component": "shared.loop"})
        depth = 0
        while v is not None:
            depth += 1
            v = v.get("child")
        self.assertEqual(depth, 6)  # depths 0..5 render, 6 is cut

    def test_entry_omits_skipped(self):
        attrs = {"title": {"type": "string"}, "author": {"type": "relation"}}
        self.assertEqual(s.entry(attrs, 1, COMPONENTS, 7), {"title": "title 1"})


class Sql(unittest.TestCase):
    ADMIN = {"id", "document_id", "firstname", "lastname", "email", "password", "is_active", "blocked",
             "created_at", "updated_at", "published_at"}

    def test_ci_admin_sql_v5(self):
        sql = s.ci_admin_sql("My-Cms", self.ADMIN, "admin_users_roles_lnk")
        for part in ['"My-Cms".admin_users', '"My-Cms"."admin_users_roles_lnk"', "document_id", "published_at",
                     s.scan.CI_ADMIN_HASH, s.scan.CI_ADMIN_EMAIL, "strapi-super-admin"]:
            self.assertIn(part, sql)
        self.assertEqual(sql.count("NOT EXISTS"), 2)

    def test_ci_admin_sql_without_v5_columns(self):
        sql = s.ci_admin_sql("public", self.ADMIN - {"document_id", "published_at"}, "admin_users_roles_links")
        self.assertNotIn("document_id", sql)
        self.assertIn('"admin_users_roles_links"', sql)

    def test_media_sql_returns_id(self):
        sql = s.media_sql("public", {"name", "hash", "ext", "mime", "size", "url", "provider", "document_id"})
        self.assertIn('"public".files', sql)
        self.assertIn("RETURNING id", sql)
        self.assertIn("document_id", sql)
        self.assertNotIn("folder_path", sql)


class StrapiMajor(unittest.TestCase):
    def test_strapi_major_sources(self):
        with tempfile.TemporaryDirectory() as d:
            app(d, strapi="^4.25.0", installed="5.59.0")
            self.assertEqual(s.strapi_major(d), 5)
        with tempfile.TemporaryDirectory() as d:
            app(d, strapi="^5.48.0")
            self.assertEqual(s.strapi_major(d), 5)
        with tempfile.TemporaryDirectory() as d:
            app(d, strapi="latest")
            self.assertEqual(s.strapi_major(d), 5)
        with tempfile.TemporaryDirectory() as d:
            app(d, strapi="4.25.0")
            self.assertEqual(s.strapi_major(d), 4)


class Cli(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.app = os.path.join(self.tmp.name, "app")
        os.makedirs(self.app)
        bindir = os.path.join(self.tmp.name, "bin")
        os.makedirs(bindir)
        psql = os.path.join(bindir, "psql")
        with open(psql, "w") as f:
            f.write("#!%s\n%s" % (sys.executable, PSQL))
        os.chmod(psql, os.stat(psql).st_mode | stat.S_IEXEC)
        self.log = os.path.join(self.tmp.name, "psql.log")
        self.env = {"PATH": bindir + os.pathsep + os.environ["PATH"], "PSQL_LOG": self.log}
        self.old = {k: os.environ.get(k) for k in self.env}
        os.environ.update(self.env)

    def tearDown(self):
        for k, v in self.old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.tmp.cleanup()

    def routes(self, article):
        return {("POST", "/admin/login"): (200, {"data": {"token": "jwt"}}),
                ("POST", "/admin/api-tokens"): (201, {"data": {"accessKey": "full-key"}}),
                ("POST", "/api/articles"): article,
                ("PUT", "/api/home"): (200, {"data": {"id": 1}})}

    def run_cli(self, routes):
        stub = Stub(routes)
        out, err = io.StringIO(), io.StringIO()
        try:
            with redirect_stdout(out), redirect_stderr(err):
                rc = s.main(["--app", self.app, "--base-url", stub.url, "--db-url", "postgres://x@localhost/strapi"])
        finally:
            stub.close()
        return rc, out.getvalue() + err.getvalue(), stub.seen

    def test_cli_creates_and_publishes(self):
        app(self.app)
        rc, out, seen = self.run_cli(self.routes((201, {"data": {"id": 1}})))
        self.assertEqual(rc, 0, out)
        token_req = [x for x in seen if x[1] == "/admin/api-tokens"][0]
        self.assertEqual(token_req[3]["type"], "full-access")
        posts = [x for x in seen if x[0] == "POST" and x[1].startswith("/api/articles")]
        puts = [x for x in seen if x[0] == "PUT" and x[1].startswith("/api/home")]
        self.assertEqual((len(posts), len(puts)), (3, 1))
        self.assertTrue(all(x[1].endswith("?status=published") for x in posts + puts))
        self.assertEqual(posts[0][3], {"data": {"title": "title 0", "cover": 7}})
        self.assertEqual(posts[0][2], "Bearer full-key")
        self.assertIn("[VERIFY] generated: articles: 3/3 created", out)
        self.assertNotIn("full-key", out)
        with open(self.log) as f:
            sql = f.read()
        self.assertIn("ci-admin@example.invalid", sql)
        self.assertIn("RETURNING id", sql)

    def test_cli_reports_rejections_and_continues(self):
        app(self.app)
        calls = []

        def article(_body):
            calls.append(1)
            return (400, {"data": None, "error": {"status": 400, "message": "title must be unique"}}) if len(calls) == 1 \
                else (201, {"data": {"id": len(calls)}})
        rc, out, _ = self.run_cli(self.routes(article))
        self.assertEqual(rc, 0, out)
        self.assertIn("[VERIFY] generated: articles #0 rejected (HTTP 400): title must be unique", out)
        self.assertIn("[VERIFY] generated: articles: 2/3 created", out)

    def test_cli_fails_when_nothing_created(self):
        app(self.app)
        routes = self.routes((400, {"error": {"message": "nope"}}))
        routes[("PUT", "/api/home")] = (400, {"error": {"message": "nope"}})
        rc, out, _ = self.run_cli(routes)
        self.assertEqual(rc, 1)
        self.assertIn("::error title=[VERIFY] Rehearsal::generated data: no entry could be created (see the rejections above)", out)

    def test_cli_refuses_strapi4(self):
        app(self.app, strapi="4.25.0")
        rc, out, seen = self.run_cli(self.routes((201, {})))
        self.assertEqual(rc, 1)
        self.assertIn("generated data needs Strapi 5; add ci/fixture.sql.gz", out)
        self.assertEqual(seen, [])


if __name__ == "__main__":
    unittest.main()
