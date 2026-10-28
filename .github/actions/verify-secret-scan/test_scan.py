import gzip
import io
import json
import os
import tempfile
import time
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


class ReviewFixes(unittest.TestCase):
    def test_email_after_url_is_found(self):
        for line in ["Site: https://acme.co\\njane.doe@client.example.co",
                     "https://acme.co<br>jane.doe@client.example.co",
                     "https://acme.co/unsubscribe?email=jane.doe@client.example.co"]:
            self.assertEqual(kinds(line), ["email"], line)

    def test_location_in_strapi_dump(self):
        rows = ["COPY public.contacts (id, note, mail) FROM stdin;", "1\tx\tjane@client.example.co", "\\."]
        self.assertEqual(s.scan_lines(rows, NONE, True)[0].where, "contacts.mail")

    def test_free_mail_hint_points_to_pii_file(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "f.sql")
            with open(p, "w") as f:
                f.write("someone@gmail.com\n")
            rc, out = run_main([p])
        self.assertEqual(rc, 1)
        self.assertIn("ci/fixture-pii.txt", out)
        self.assertNotIn('add "@gmail.com"', out)

    def test_long_hex_run_is_fast(self):
        import time
        t = time.time()
        self.assertEqual(kinds("\\x" + "ab12" * 50000), [])
        self.assertLess(time.time() - t, 1.0)

    def test_insert_into_secret_table_found(self):
        rows = ["INSERT INTO public.strapi_webhooks (id, url) VALUES (1, 'https://hooks.example.co/x');"]
        self.assertEqual([f.kind for f in s.scan_lines(rows, NONE, True)], ["strapi-secret-table"])
        self.assertEqual(s.scan_lines(rows, NONE, False), [])


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


class ConnectionStringsAnyOrder(unittest.TestCase):
    def test_password_before_host(self):
        self.assertEqual(kinds("User ID=app;Password=x;Host=db.example.co"), ["connection-string"])

    def test_server_with_pwd(self):
        self.assertEqual(kinds("Server=sql.example.co;User Id=sa;Pwd=x"), ["connection-string"])

    def test_redis_host_port_form(self):
        self.assertEqual(kinds('{"Redis": "cache.example.co:6380,password=x,ssl=True"}'), ["connection-string"])

    def test_compose_service_name_is_local(self):
        self.assertEqual(kinds("Host=db;Password=postgres"), [])
        self.assertEqual(kinds("redis:6379,password=x"), [])

    def test_sql_server_tcp_prefix_and_port(self):
        self.assertEqual(kinds('"Data Source=tcp:sql.example.co,1433;Initial Catalog=app;Password=x"'), ["connection-string"])

    def test_no_password_is_clean(self):
        self.assertEqual(kinds("Host=db.example.co;Database=app;Username=app"), [])

    def test_value_never_printed(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "appsettings.json")
            with open(p, "w") as f:
                f.write('{"Db": "Username=app;Password=hunter22secret;Host=db.example.co"}\n')
            rc, out = run_main([p])
        self.assertEqual(rc, 1)
        self.assertIn("connection-string", out)
        self.assertNotIn("hunter22", out)
        self.assertNotIn("db.example.co", out)


class RecordingsAndMocks(unittest.TestCase):
    def test_har_authorization_header(self):
        self.assertEqual(kinds('{"name": "Authorization", "value": "Bearer abcdefgh12345"}'), ["auth-header"])

    def test_mockoon_cookie_header(self):
        self.assertEqual(kinds('{"key": "set-cookie", "value": "sid=abcdefgh123"}'), ["auth-header"])

    def test_short_header_value_ignored(self):
        self.assertEqual(kinds('{"name": "Cookie", "value": "x"}'), [])

    def test_har_password_in_post_data(self):
        line = r'"text": "{\"email\":\"a@example.com\",\"password\":\"Hunter22\"}"'
        self.assertEqual(kinds(line), ["password-field"])

    def test_form_password(self):
        self.assertEqual(kinds("username=a&password=Hunter22&x=1"), ["password-field"])

    def test_empty_password_ignored(self):
        self.assertEqual(kinds('{"password":""}'), [])

    def test_unsigned_jwt_not_flagged(self):
        self.assertEqual(kinds('"token": "eyJhbGciOiJub25lIn0.eyJzdWIiOiIxMjM0NTY3ODkwIn0."'), [])

    def test_masked_output_never_contains_value(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "rec.har")
            with open(p, "w") as f:
                f.write('{"name": "authorization", "value": "Bearer abcdefgh12345"}\n')
                f.write('{"postData": {"text": "password=Hunter22"}}\n')
            rc, out = run_main([p])
        self.assertEqual(rc, 1)
        self.assertIn("auth-header", out)
        self.assertIn("password-field", out)
        self.assertNotIn("abcdefgh", out)
        self.assertNotIn("Hunter22", out)

    def test_big_single_line_is_linear(self):
        line = '{"a":"b"},' * 500000 + '{"name": "X-Api-Key", "value": "k3y-abcdefgh"}'
        t = time.monotonic()
        found = kinds(line)
        self.assertLess(time.monotonic() - t, 5)
        self.assertEqual(found, ["auth-header"])


def har(headers=(), cookies=(), indent=2):
    entry = {"request": {"url": "http://localhost/api", "headers": [{"name": n, "value": v} for n, v in headers],
                         "cookies": [{"name": n, "value": v} for n, v in cookies]}}
    return json.dumps({"log": {"entries": [entry]}}, indent=indent)


def scan_file(name, text):
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, name)
        with open(p, "w") as f:
            f.write(text)
        return run_main([p])


class StructuredRecordings(unittest.TestCase):
    def test_pretty_printed_har_headers_and_cookies_found(self):
        rc, out = scan_file("rec.har", har([("Authorization", "Bearer realtokenvalue123456"),
                                           ("Set-Cookie", "sid=abcdefgh1234")], [("session", "abcdefgh5678")]))
        self.assertEqual(rc, 1)
        self.assertEqual(out.count("auth-header"), 3, out)
        self.assertIn("$.log.entries[0].request.headers[0]", out)
        self.assertNotIn("realtoken", out)
        self.assertNotIn("abcdefgh", out)

    def test_pretty_printed_mockoon_header_found(self):
        mock = json.dumps({"routes": [{"responses": [{"headers": [{"key": "X-Api-Key", "value": "k3y-abcdefgh"}]}]}]},
                          indent=2)
        rc, out = scan_file("mocks.json", mock)
        self.assertEqual(rc, 1)
        self.assertEqual(out.count("auth-header"), 1, out)

    def test_compact_har_not_double_counted(self):
        rc, out = scan_file("rec.har", har([("Authorization", "Bearer realtokenvalue123456")], indent=None))
        self.assertEqual(out.count("auth-header"), 1, out)

    def test_invalid_json_falls_back_to_lines(self):
        rc, out = scan_file("rec.har", '{"name": "Cookie", "value": "abcdefgh123"} not json')
        self.assertEqual(out.count("auth-header"), 1, out)

    def test_recording_email_hint_says_replace(self):
        rc, out = scan_file("rec.har", '{"text": "jane@client.example.co"}')
        self.assertEqual(rc, 1)
        self.assertIn("example.com", out)
        self.assertNotIn("fixture-allow", out)

    def test_many_host_tokens_is_fast(self):
        line = ("this.host=e;" + "x" * 10000) * 300
        t = time.monotonic()
        self.assertEqual(kinds(line), [])
        self.assertLess(time.monotonic() - t, 2)


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
