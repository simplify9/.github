import os
import tempfile
import unittest
from datetime import date

import contract as c

WEB_PKG = {"scripts": {k: "x" for k in ("lint", "typecheck", "test", "build", "test:e2e")},
           "engines": {"node": ">=20"}, "devDependencies": {"@playwright/test": "1"}}
WEB_FILES = {"yarn.lock", "playwright.config.ts"}


class MissingItems(unittest.TestCase):
    def test_web_complete_has_nothing_missing(self):
        self.assertEqual(c.missing_items("web", WEB_FILES, WEB_PKG, 0, False), [])

    def test_web_missing_playwright(self):
        pkg = dict(WEB_PKG, devDependencies={})
        self.assertEqual(c.missing_items("web", WEB_FILES, pkg, 0, False), ["playwright"])

    def test_web_playwright_needs_root_config(self):
        files = {"yarn.lock", "e2e/playwright.config.ts"}
        self.assertEqual(c.missing_items("web", files, WEB_PKG, 0, False), ["playwright"])

    def test_web_missing_e2e(self):
        pkg = {"scripts": {k: "x" for k in ("lint", "typecheck", "test", "build")},
               "packageManager": "yarn@4", "devDependencies": {"@playwright/test": "1"}}
        self.assertEqual(c.missing_items("web", {"yarn.lock", "playwright.config.mjs"}, pkg, 0, False),
                         ["script:test:e2e"])

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

    def test_strapi_needs_no_fixture(self):
        # Generated data covers a repo without ci/fixture.sql.gz, and DevOps (not the repo) makes the copy.
        pkg = {"scripts": {"build": "x"}, "engines": {"node": "20"}}
        self.assertEqual(c.missing_items("strapi", {"package-lock.json"}, pkg, 0, False), [])

    def test_flutter_widget_test(self):
        self.assertEqual(c.missing_items("flutter", {"pubspec.lock"}, None, 0, False), ["widget-test"])
        self.assertEqual(c.missing_items("flutter", {"pubspec.lock", "test/a_test.dart"}, None, 0, False), [])

    def test_infra_has_no_requirements(self):
        self.assertEqual(c.missing_items("infra", set(), None, 0, False), [])

    def test_unknown_stack_raises(self):
        with self.assertRaises(ValueError):
            c.missing_items("cobol", set(), None, 0, False)

class Scan(unittest.TestCase):
    def test_scan_ignores_vendored_dirs(self):
        with tempfile.TemporaryDirectory() as d:
            for rel in ("node_modules/yarn.lock", "ios/Pods/X.Tests/X.Tests.csproj"):
                path = os.path.join(d, rel)
                os.makedirs(os.path.dirname(path))
                open(path, "w").close()
            files, csprojs, health = c.scan(d)
        self.assertEqual((files, csprojs, health), (set(), 0, False))
        self.assertEqual(c.missing_items("dotnet-library", files, None, csprojs, health),
                         ["lockfile", "toolchain-pin", "cpm", "test-project"])


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


class ItemDeadlines(unittest.TestCase):
    def test_item_deadline_v1_uses_repo_deadline(self):
        self.assertEqual(c.item_deadline("script:test:e2e", "2026-11-10"), date(2026, 11, 10))

    def test_item_deadline_new_item_is_later_of_repo_and_grace(self):
        self.assertEqual(c.item_deadline("playwright", "2026-11-10"), date(2026, 12, 29))
        self.assertEqual(c.item_deadline("playwright", "2027-02-01"), date(2027, 2, 1))

    def test_item_deadline_empty_or_invalid_repo_is_never(self):
        for repo in ("", "soon"):
            self.assertIsNone(c.item_deadline("playwright", repo))
            self.assertIsNone(c.item_deadline("lockfile", repo))

    def test_item_levels_mixed(self):
        missing = ["script:test:e2e", "playwright"]
        self.assertEqual(c.item_levels(missing, "2026-11-10", date(2026, 12, 1)),
                         {"script:test:e2e": "error", "playwright": "warning"})
        self.assertEqual(c.item_levels(missing, "2026-11-10", date(2026, 12, 29)),
                         {"script:test:e2e": "error", "playwright": "error"})

    def test_item_levels_no_repo_deadline_warns_forever(self):
        self.assertEqual(c.item_levels(["playwright", "lockfile"], "", date(2030, 1, 1)),
                         {"playwright": "warning", "lockfile": "warning"})


if __name__ == "__main__":
    unittest.main()
