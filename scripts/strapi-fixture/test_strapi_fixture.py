import io
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout

import strapi_fixture as f

T, V = "text", "character varying"
V5 = [
    ("admin_roles", "id", "integer"), ("admin_roles", "code", V),
    ("admin_users", "id", "integer"), ("admin_users", "document_id", V), ("admin_users", "firstname", V),
    ("admin_users", "lastname", V), ("admin_users", "username", V), ("admin_users", "email", V),
    ("admin_users", "password", V), ("admin_users", "reset_password_token", V),
    ("admin_users", "registration_token", V), ("admin_users", "is_active", "boolean"),
    ("admin_users", "blocked", "boolean"), ("admin_users", "published_at", "timestamp(6) without time zone"),
    ("admin_users_roles_lnk", "id", "integer"), ("admin_users_roles_lnk", "user_id", "integer"),
    ("admin_users_roles_lnk", "role_id", "integer"),
    ("up_users", "id", "integer"), ("up_users", "username", V), ("up_users", "email", V),
    ("up_users", "password", V), ("up_users", "reset_password_token", V),
    ("up_users", "confirmation_token", V), ("up_users", "phone", V),
    ("strapi_api_tokens", "id", "integer"), ("strapi_api_token_permissions_token_lnk", "id", "integer"),
    ("strapi_webhooks", "id", "integer"), ("strapi_history_versions", "id", "integer"),
    ("strapi_core_store_settings", "id", "integer"), ("strapi_core_store_settings", "value", T),
    ("articles", "id", "integer"), ("articles", "title", V),
]
V4_LINK = [c for c in V5 if not c[0].endswith("_lnk")] + [
    ("admin_users_roles_links", "id", "integer"), ("admin_users_roles_links", "user_id", "integer"),
    ("admin_users_roles_links", "role_id", "integer")]


class PiiColumns(unittest.TestCase):
    def test_pii_columns_name_patterns(self):
        cols = [("c", n, V) for n in ("email", "user_phone", "mobile_no", "ip_address",
                                      "shipping", "iphone_model", "description")]
        self.assertEqual([c[1] for c in f.pii_columns(cols, set())],
                         ["email", "user_phone", "mobile_no", "ip_address"])

    def test_pii_columns_extra_file_entries(self):
        cols = [("contacts", "full_name", V), ("contacts", "notes", T)]
        self.assertEqual(f.pii_columns(cols, {("contacts", "full_name")}), [("contacts", "full_name", V)])

    def test_pii_columns_skip_handled_and_core_store(self):
        cols = [("admin_users", "email", V), ("up_users", "email", V), ("up_users", "phone", V),
                ("strapi_core_store_settings", "email", T)]
        self.assertEqual(f.pii_columns(cols, set()), [("up_users", "phone", V)])


class SanitizeSql(unittest.TestCase):
    def sql(self, cols=V5, truncate=()):
        return f.sanitize_sql(cols, f.pii_columns(cols, set()), list(truncate))

    def test_sanitize_sql_v5_link_table(self):
        out = self.sql()
        self.assertIn('"admin_users_roles_lnk"', out)
        self.assertNotIn("_links", out)

    def test_sanitize_sql_v4_link_table(self):
        out = self.sql(V4_LINK)
        self.assertIn('"admin_users_roles_links"', out)
        self.assertNotIn("_lnk", out)

    def test_sanitize_sql_ci_admin(self):
        out = self.sql()
        self.assertIn(f.scan.CI_ADMIN_EMAIL, out)
        self.assertIn(f.scan.CI_ADMIN_HASH, out)
        self.assertIn("'strapi-super-admin'", out)
        self.assertIn("'@example.invalid'", out)  # every other admin anonymized

    def test_sanitize_sql_up_users_anonymized(self):
        out = self.sql()
        self.assertIn('UPDATE "up_users" SET', out)
        self.assertIn('"confirmation_token" = NULL', out)

    def test_sanitize_sql_quotes_identifiers(self):
        cols = [("Orders", "id", "integer"), ("Orders", "order", V), ("Orders", "contact_email", V)]
        out = f.sanitize_sql(cols, f.pii_columns(cols, {("Orders", "order")}), [])
        self.assertIn('UPDATE "Orders" SET "order" = ', out)
        self.assertIn('"contact_email" = ', out)

    def test_sanitize_sql_truncates_only_present_secret_tables(self):
        out = self.sql()
        line = [l for l in out.splitlines() if l.startswith("TRUNCATE")][0]
        self.assertIn('"strapi_api_tokens"', line)
        self.assertIn('"strapi_webhooks"', line)
        self.assertIn('"strapi_history_versions"', line)
        self.assertNotIn("strapi_sessions", line)
        self.assertNotIn("CASCADE", line)

    def test_sanitize_sql_no_id_uses_constant(self):
        cols = [("leads", "email", V), ("leads", "count", "integer")]
        out = f.sanitize_sql(cols, f.pii_columns(cols, set()), [])
        self.assertIn("'redacted@example.invalid'", out)
        self.assertNotIn("|| id", out)

    def test_sanitize_sql_non_text_pii_nulled(self):
        cols = [("t", "id", "integer"), ("t", "ip", "inet")]
        self.assertIn('"ip" = NULL', f.sanitize_sql(cols, f.pii_columns(cols, set()), []))

    def test_sanitize_sql_truncate_option(self):
        self.assertIn('DELETE FROM "form_submissions";', self.sql(truncate=["form_submissions"]))


class BlankSecrets(unittest.TestCase):
    def test_blank_secrets_nested(self):
        v = {"github": {"key": "a", "secret": "b", "enabled": True, "callback": "/x"},
             "list": [{"apiKey": "k", "name": "n"}]}
        self.assertEqual(f.blank_secrets(v), {"github": {"key": "", "secret": "", "enabled": True, "callback": "/x"},
                                              "list": [{"apiKey": "", "name": "n"}]})

    def test_blank_secrets_leaves_non_strings(self):
        self.assertEqual(f.blank_secrets({"password": 3, "token": None}), {"password": 3, "token": None})


class ReviewFixes(unittest.TestCase):
    def test_unmatched_pii_entries_reported(self):
        cols = [("contacts", "full_name", V), ("articles", "title", V)]
        self.assertEqual(f.unmatched_pii(cols, ["contacts.full_name", "articels.title", "nodot"]),
                         ["articels.title", "nodot"])
        self.assertEqual(f.unmatched_pii(cols, ["contacts.full_name"]), [])

    def test_pg_env_from_url(self):
        env = f.pg_env("postgres://ro%40user:p%3Ass@db.example.co:25060/cms?sslmode=require")
        self.assertEqual(env, {"PGHOST": "db.example.co", "PGPORT": "25060", "PGUSER": "ro@user",
                               "PGPASSWORD": "p:ss", "PGDATABASE": "cms", "PGSSLMODE": "require"})
        self.assertEqual(f.pg_env("postgresql://u@h/d"), {"PGHOST": "h", "PGUSER": "u", "PGDATABASE": "d"})


class SchemaAndSource(unittest.TestCase):
    def test_source_dump_cmd_public_is_whole_database(self):
        # pg_dump --schema=public emits CREATE SCHEMA public, which does not restore into a fresh database.
        self.assertEqual(f.source_dump_cmd("public"), "pg_dump --no-owner --no-privileges")

    def test_source_dump_cmd_named_schema_only(self):
        self.assertEqual(f.source_dump_cmd("my-cms"), "pg_dump --no-owner --no-privileges --schema='\"my-cms\"'")

    def test_dump_server_major_from_header(self):
        head = b"--\n-- PostgreSQL database dump\n--\n\n-- Dumped from database version 18.6\n-- Dumped by pg_dump version 18.1\n"
        self.assertEqual(f.dump_server_major(head), 18)
        self.assertIsNone(f.dump_server_major(b"SET statement_timeout = 0;\n"))

    def test_image_major(self):
        self.assertEqual([f.image_major(i) for i in ("postgres:18", "postgres:17-alpine", "postgres:16.4", "registry/pg")],
                         [18, 17, 16, None])

    def test_detect_schema(self):
        self.assertEqual(f.detect_schema({"public": 0, "my-cms": 40}), "my-cms")
        self.assertEqual(f.detect_schema({"public": 12}), "public")
        with self.assertRaises(ValueError) as cm:
            f.detect_schema({"public": 3, "my-cms": 40})
        self.assertIn("my-cms", str(cm.exception))
        self.assertIn("public", str(cm.exception))
        with self.assertRaises(ValueError):
            f.detect_schema({})

    def test_image_for(self):
        self.assertEqual(f.image_for(18), "postgres:18")
        self.assertEqual(f.image_for(None), "postgres:17")

    def test_defaults_are_auto(self):
        a = f.parse_args(["--repo", "r", "--source-dump", "-"])
        self.assertEqual((a.schema, a.postgres_image), ("auto", "auto"))

    def test_cli_needs_exactly_one_source(self):
        a = f.parse_args(["--repo", "r", "--source-dump", "-", "--schema", "my-cms"])
        self.assertEqual((a.source_env, a.source_dump, a.schema), (None, "-", "my-cms"))
        self.assertEqual(f.parse_args(["--repo", "r", "--source-env", "SRC_DB"]).schema, "auto")
        for argv in (["--repo", "r"], ["--repo", "r", "--source-env", "X", "--source-dump", "-"]):
            with self.assertRaises(SystemExit) as cm, redirect_stderr(io.StringIO()):
                f.parse_args(argv)
            self.assertEqual(cm.exception.code, 2)


@unittest.skipUnless(shutil.which("docker") and os.environ.get("FIXTURE_DOCKER_TEST"), "set FIXTURE_DOCKER_TEST=1 (needs Docker)")
class KeepSchemaDocker(unittest.TestCase):
    """keep_schema_sql against a real Postgres: the CMS schema ends up in public, nothing else survives."""

    def setUp(self):
        self.name = "fixture-test-%d" % os.getpid()
        subprocess.run(["docker", "run", "-d", "--rm", "--name", self.name, "-e", "POSTGRES_PASSWORD=x",
                        "-e", "POSTGRES_DB=fixture", "postgres:17"], check=True, capture_output=True)
        for _ in range(60):
            if subprocess.run(["docker", "exec", self.name, "pg_isready", "-h", "127.0.0.1", "-U", "postgres", "-d", "fixture"],
                              capture_output=True).returncode == 0:
                break
            time.sleep(1)

    def tearDown(self):
        subprocess.run(["docker", "rm", "-f", self.name], capture_output=True)

    def sql(self, text):
        return subprocess.run(["docker", "exec", "-i", self.name, "psql", "-v", "ON_ERROR_STOP=1", "-qAt", "-U", "postgres",
                               "-d", "fixture"], input=text, text=True, capture_output=True)

    def test_named_schema_moves_to_public_and_others_dropped(self):
        self.sql('CREATE SCHEMA "my-cms"; CREATE TABLE "my-cms".articles (id serial PRIMARY KEY, title text);'
                 'CREATE TABLE "my-cms".links (id serial, article_id int REFERENCES "my-cms".articles(id));'
                 'CREATE SEQUENCE "my-cms".loose_seq; INSERT INTO "my-cms".articles (title) VALUES (\'a\');'
                 'CREATE SCHEMA api; CREATE TABLE api.customers (email text);')
        r = self.sql(f.keep_schema_sql("my-cms"))
        self.assertEqual(r.returncode, 0, r.stderr)
        r = self.sql("INSERT INTO articles (title) VALUES ('b'); SELECT max(id) FROM articles;"
                     "SELECT string_agg(nspname, ',' ORDER BY nspname) FROM pg_namespace WHERE nspname NOT LIKE 'pg\\_%';"
                     "SELECT string_agg(relname, ',' ORDER BY relname) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace "
                     "WHERE n.nspname = 'public' AND relkind IN ('r', 'S');")
        self.assertEqual(r.stdout.split(), ["2", "information_schema,public",
                                            "articles,articles_id_seq,links,links_id_seq,loose_seq"])

    def test_named_schema_refuses_tables_in_public_too(self):
        self.sql('CREATE TABLE public.customers (email text); CREATE SCHEMA cms; CREATE TABLE cms.articles (id int);')
        r = self.sql(f.keep_schema_sql("cms"))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("dump only the CMS schema", r.stderr)

    def test_auto_schema_round_trip(self):
        self.sql('CREATE SCHEMA "my-cms"; CREATE TABLE "my-cms".articles (id serial PRIMARY KEY, title text);'
                 'INSERT INTO "my-cms".articles (title) VALUES (\'a\');')
        dump = subprocess.run(["docker", "exec", self.name, "pg_dump", "-U", "postgres", "--no-owner", "--no-privileges",
                               "--schema=\"my-cms\"", "fixture"], check=True, capture_output=True).stdout
        with tempfile.TemporaryDirectory() as d:
            src = os.path.join(d, "dump.sql")
            with open(src, "wb") as fh:
                fh.write(dump)
            repo = os.path.join(d, "repo")
            os.makedirs(repo)
            with redirect_stderr(io.StringIO()), redirect_stdout(io.StringIO()):
                rc = f.main(["--source-dump", src, "--repo", repo])
            self.assertEqual(rc, 0)
            out = subprocess.run(["gunzip", "-c", os.path.join(repo, "ci", "fixture.sql.gz")], check=True,
                                 capture_output=True, text=True).stdout
        self.assertIn("CREATE TABLE public.articles", out)
        self.assertNotIn("my-cms", out)
        self.assertIn("Dumped from database version 17", out)

    def test_public_keeps_public_and_drops_other_schemas(self):
        self.sql("CREATE TABLE public.articles (id int); CREATE SCHEMA api; CREATE TABLE api.customers (email text);")
        r = self.sql(f.keep_schema_sql("public"))
        self.assertEqual(r.returncode, 0, r.stderr)
        r = self.sql("SELECT count(*) FROM articles; SELECT count(*) FROM pg_namespace WHERE nspname = 'api';")
        self.assertEqual(r.stdout.split(), ["0", "0"])


class ListFile(unittest.TestCase):
    def test_parse_list_file_crlf_comments(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "pii.txt")
            with open(p, "w", newline="") as fh:
                fh.write("# PII\r\n  contacts.full_name  \r\n\r\nleads.notes # free text\r\n")
            self.assertEqual(f.parse_list_file(p), ["contacts.full_name", "leads.notes"])
            self.assertEqual(f.parse_list_file(os.path.join(d, "missing.txt")), [])


if __name__ == "__main__":
    unittest.main()
