import unittest
from datetime import date

import contract as c

WEB_PKG = {"scripts": {k: "x" for k in ("lint", "typecheck", "test", "build", "test:e2e")},
           "engines": {"node": ">=20"}}


class MissingItems(unittest.TestCase):
    def test_web_complete_has_nothing_missing(self):
        self.assertEqual(c.missing_items("web", {"yarn.lock"}, WEB_PKG, 0, False), [])

    def test_web_missing_e2e(self):
        pkg = {"scripts": {k: "x" for k in ("lint", "typecheck", "test", "build")},
               "packageManager": "yarn@4"}
        self.assertEqual(c.missing_items("web", {"yarn.lock"}, pkg, 0, False), ["script:test:e2e"])

    def test_dotnet_single_project_does_not_need_cpm(self):
        files = {"packages.lock.json", "global.json", "Api/Api.csproj", "Api.Tests/Api.Tests.csproj", "Dockerfile"}
        self.assertEqual(c.missing_items("dotnet-service", files, None, 1, True), [])

    def test_dotnet_multi_project_needs_cpm(self):
        files = {"packages.lock.json", "global.json", "Api.Tests/Api.Tests.csproj", "Dockerfile"}
        self.assertEqual(c.missing_items("dotnet-service", files, None, 2, True), ["cpm"])

    def test_dotnet_cpm_satisfies_lockfile(self):
        files = {"Directory.Packages.props", "global.json", "A.Tests/A.Tests.csproj"}
        self.assertEqual(c.missing_items("dotnet-library", files, None, 2, False), [])

    def test_rn_missing_align_deps_and_maestro(self):
        pkg = {"scripts": {k: "x" for k in ("lint", "typecheck", "test")}, "engines": {"node": "20"}}
        self.assertEqual(c.missing_items("react-native", {"yarn.lock"}, pkg, 0, False),
                         ["align-deps", "maestro-smoke"])

    def test_strapi_needs_fixture(self):
        pkg = {"scripts": {"build": "x"}, "engines": {"node": "20"}}
        self.assertEqual(c.missing_items("strapi", {"package-lock.json"}, pkg, 0, False), ["strapi-fixture"])

    def test_flutter_widget_test(self):
        self.assertEqual(c.missing_items("flutter", {"pubspec.lock"}, None, 0, False), ["widget-test"])
        self.assertEqual(c.missing_items("flutter", {"pubspec.lock", "test/a_test.dart"}, None, 0, False), [])

    def test_infra_has_no_requirements(self):
        self.assertEqual(c.missing_items("infra", set(), None, 0, False), [])

    def test_unknown_stack_raises(self):
        with self.assertRaises(ValueError):
            c.missing_items("cobol", set(), None, 0, False)


class Mode(unittest.TestCase):
    today = date(2026, 11, 1)

    def test_mode_before_deadline_is_warn(self):
        self.assertEqual(c.mode_for("2026-11-02", self.today), "warn")

    def test_mode_on_deadline_is_enforce(self):
        self.assertEqual(c.mode_for("2026-11-01", self.today), "enforce")

    def test_mode_empty_deadline_is_warn(self):
        self.assertEqual(c.mode_for("", self.today), "warn")

    def test_mode_garbage_deadline_is_warn(self):
        self.assertEqual(c.mode_for("soon", self.today), "warn")


if __name__ == "__main__":
    unittest.main()
