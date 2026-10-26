import os
import tempfile
import unittest

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
