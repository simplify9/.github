import gzip
import io
import os
import tempfile
import unittest
from contextlib import redirect_stdout

import scan as s

NONE = (set(), set())
BCRYPT = "$2b$12$" + "abcdefghijklmnopqrstuvABCDEFGHIJKLMNOPQRSTUVWXYZ01234"[:53]
GHP = "ghp_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"


def kinds(text, allow=NONE, strapi=False):
    return [f.kind for f in s.scan_lines(text.splitlines(), allow, strapi)]


def run_main(argv):
    buf = io.StringIO()
    with redirect_stdout(buf):
        rc = s.main(argv)
    return rc, buf.getvalue()


class Emails(unittest.TestCase):
    def test_example_domains_allowed(self):
        self.assertEqual(s.scan_lines(["a@example.com b@x.example.invalid c@y.test"], NONE, False), [])

    def test_real_email_found_and_masked(self):
        self.assertEqual(s.scan_lines(["mail jane.doe@client.example.co"], NONE, False),
                         [s.Finding(1, "email", "***@client.example.co")])

    def test_email_message_names_allow_line(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "f.sql")
            with open(p, "w") as f:
                f.write("x\nhello jane@client.example.co\n")
            rc, out = run_main([p])
        self.assertEqual(rc, 1)
        self.assertIn('add "@client.example.co" or the address to ci/fixture-allow.txt', out)
        self.assertNotIn("jane@", out)

    def test_allow_exact_and_domain(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "allow.txt")
            with open(p, "w") as f:
                f.write("# business contacts\r\n  INFO@acme.example.co \r\n\r\n@public.example.co\n")
            allow = s.load_allow(p)
        self.assertEqual(allow, ({"info@acme.example.co"}, {"public.example.co"}))
        self.assertEqual(kinds("info@acme.example.co a@public.example.co", allow), [])
        self.assertEqual(kinds("x@other.example.co", allow), ["email"])

    def test_strapi_vendor_defaults_allowed(self):
        # Strapi's own default email settings (core store) ship no-reply@strapi.io.
        self.assertEqual(kinds('{"from":"no-reply@strapi.io","response":"x@strapi.io"}'), [])

    def test_missing_allow_file_is_empty(self):
        self.assertEqual(s.load_allow("/nonexistent/allow.txt"), NONE)
        self.assertEqual(s.load_allow(None), NONE)


class Secrets(unittest.TestCase):
    def test_bcrypt_found_ci_admin_allowed(self):
        self.assertEqual(s.scan_lines([BCRYPT], NONE, False), [s.Finding(1, "password-hash", "$2b$…")])
        self.assertEqual(kinds(s.CI_ADMIN_HASH), [])

    def test_argon2_jwt_private_key_tokens_found(self):
        lines = "\n".join([
            "$argon2id$v=19$m=65536,t=3,p=4$c2FsdA$aGFzaA",
            "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnop",
            "-----BEGIN RSA PRIVATE KEY-----",
            GHP,
            "github_pat_" + "a" * 60,
            "AKIAABCDEFGHIJKLMNOP",
            "sk_live_" + "x" * 24,
            "xoxb-123456789012-abc",
        ])
        self.assertEqual(kinds(lines), ["password-hash", "jwt", "private-key"] + ["token"] * 5)

    def test_connection_strings(self):
        found = ["Host=db.example.co;Password=x",
                 "Server=sql.example.co;User Id=a;Password=b",
                 "amqps://u:p@mq.example.co/v",
                 "postgresql://u:p@pg.example.co/db"]
        clean = ["Host=localhost;Password=postgres",
                 "Host=127.0.0.1;Port=5432;Password=postgres",
                 "amqp://guest:guest@localhost",
                 "postgres://strapi:strapi@localhost:5432/strapi",
                 "redis://:pw@host.docker.internal:6379"]
        for line in found:
            self.assertEqual(kinds(line), ["connection-string"], line)
        for line in clean:
            self.assertEqual(kinds(line), [], line)


class StrapiDump(unittest.TestCase):
    COPY = "COPY public.strapi_api_tokens (id, name, access_key) FROM stdin;"

    def test_strapi_secret_table_rows(self):
        rows = ["SET x;", self.COPY, "1\tci\tdeadbeef", "\\.", "COPY public.articles (id) FROM stdin;", "1", "\\."]
        self.assertEqual(s.scan_lines(rows, NONE, True), [s.Finding(2, "strapi-secret-table", "strapi_api_tokens")])
        self.assertEqual(s.scan_lines([self.COPY, "\\."], NONE, True), [])
        self.assertEqual(s.scan_lines(rows, NONE, False), [])

    def test_v5_link_table_listed(self):
        self.assertIn("strapi_api_token_permissions_token_lnk", s.STRAPI_SECRET_TABLES)
        self.assertIn("strapi_webhooks", s.STRAPI_SECRET_TABLES)
        # Newer v5 links tokens to an owner and to admin permissions: emptied with the tokens.
        self.assertIn("strapi_api_tokens_admin_user_owner_lnk", s.STRAPI_SECRET_TABLES)
        self.assertIn("admin_permissions_api_token_lnk", s.STRAPI_SECRET_TABLES)


class Cli(unittest.TestCase):
    def test_cli_gz_exit_codes_and_no_leak(self):
        with tempfile.TemporaryDirectory() as d:
            bad, good = os.path.join(d, "bad.sql.gz"), os.path.join(d, "good.sql.gz")
            with gzip.open(bad, "wt") as f:
                f.write("a\n" + GHP + "\n")
            with gzip.open(good, "wt") as f:
                f.write("nothing here\n")
            rc, out = run_main([bad])
            self.assertEqual(rc, 1)
            self.assertIn("::error file=%s,line=2,title=[VERIFY] secret-scan::token: ghp_…" % bad, out)
            self.assertNotIn(GHP, out)
            self.assertEqual(run_main([good])[0], 0)
            self.assertEqual(run_main([os.path.join(d, "missing.sql")])[0], 2)

    def test_strapi_dump_flag(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "f.sql")
            with open(p, "w") as f:
                f.write(StrapiDump.COPY + "\n1\tci\tx\n\\.\n")
            self.assertEqual(run_main([p])[0], 0)
            self.assertEqual(run_main(["--strapi-dump", p])[0], 1)


if __name__ == "__main__":
    unittest.main()
