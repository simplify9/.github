import os
import tempfile
import unittest
from datetime import date

import contract as c

WEB_PKG = {"scripts": {k: "x" for k in ("lint", "typecheck", "test", "build", "test:e2e")},
           "engines": {"node": ">=20"}, "devDependencies": {"@playwright/test": "1"}}
WEB_FILES = {"yarn.lock", "playwright.config.ts"}
RN_PKG = {"scripts": {k: "x" for k in ("lint", "typecheck", "test")}, "engines": {"node": "20"},
          "devDependencies": {"@rnx-kit/align-deps": "1"}}
MVC_TESTS = {"path": "Api.Tests/Api.Tests.csproj", "test": True, "testcontainers": True, "mvc_testing": True,
             "clients": [], "refused": [], "kind": "integration"}


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
        self.assertEqual(c.missing_items("dotnet-service", files, None, 1, True, [MVC_TESTS]), [])

    def test_dotnet_multi_project_needs_cpm(self):
        files = {"packages.lock.json", "global.json", "Api.Tests/Api.Tests.csproj", "Dockerfile"}
        self.assertEqual(c.missing_items("dotnet-service", files, None, 2, True, [MVC_TESTS]), ["cpm"])

    def test_service_needs_mvc_testing_project(self):
        files = {"packages.lock.json", "global.json", "Api.Tests/Api.Tests.csproj", "Dockerfile"}
        unit = dict(MVC_TESTS, mvc_testing=False, kind="unit")
        self.assertEqual(c.missing_items("dotnet-service", files, None, 1, True, [unit]), ["integration-tests"])
        self.assertEqual(c.missing_items("dotnet-service", files, None, 1, True, None), ["integration-tests"])

    def test_service_refused_project_does_not_count(self):
        files = {"packages.lock.json", "global.json", "Api.Tests/Api.Tests.csproj", "Dockerfile"}
        refused = dict(MVC_TESTS, kind="refused", refused=["appsettings.json:2 connection-string"])
        self.assertEqual(c.missing_items("dotnet-service", files, None, 1, True, [refused]), ["integration-tests"])

    def test_library_without_clients_needs_nothing(self):
        files = {"Directory.Packages.props", "global.json", "A.Tests/A.Tests.csproj"}
        lib = {"path": "A/A.csproj", "test": False, "testcontainers": False, "mvc_testing": False,
               "clients": [], "refused": [], "kind": None}
        self.assertEqual(c.missing_items("dotnet-library", files, None, 2, False, [lib]), [])

    def test_library_with_redis_needs_testcontainers(self):
        files = {"Directory.Packages.props", "global.json", "A.Tests/A.Tests.csproj"}
        lib = {"path": "A/A.csproj", "test": False, "testcontainers": False, "mvc_testing": False,
               "clients": ["StackExchange.Redis"], "refused": [], "kind": None}
        unit = dict(MVC_TESTS, mvc_testing=False, kind="unit")
        tc = dict(MVC_TESTS, mvc_testing=False, testcontainers=True, kind="integration")
        self.assertEqual(c.missing_items("dotnet-library", files, None, 2, False, [lib, unit]), ["integration-tests"])
        self.assertEqual(c.missing_items("dotnet-library", files, None, 2, False, [lib, tc]), [])

    def test_dotnet_cpm_satisfies_lockfile(self):
        files = {"Directory.Packages.props", "global.json", "A.Tests/A.Tests.csproj"}
        self.assertEqual(c.missing_items("dotnet-library", files, None, 2, False), [])

    def test_rn_missing_align_deps_and_maestro(self):
        pkg = {"scripts": {k: "x" for k in ("lint", "typecheck", "test")}, "engines": {"node": "20"}}
        self.assertEqual(c.missing_items("react-native", {"yarn.lock"}, pkg, 0, False),
                         ["align-deps", "maestro-smoke", "maestro-journeys", "e2e-mocks"])

    def test_rn_journeys_need_three_flows(self):
        two = {"yarn.lock", ".maestro/smoke.yaml", ".maestro/a.yaml", "e2e/mocks.json"}
        self.assertIn("maestro-journeys", c.missing_items("react-native", two, RN_PKG, 0, False))
        three = two | {".maestro/b.yml"}
        self.assertEqual(c.missing_items("react-native", three, RN_PKG, 0, False), [])

    def test_rn_config_and_subflows_not_counted(self):
        files = {"yarn.lock", ".maestro/smoke.yaml", ".maestro/config.yaml", ".maestro/sub/x.yaml",
                 ".maestro/a.yaml", "e2e/mocks.json"}
        self.assertEqual(c.missing_items("react-native", files, RN_PKG, 0, False), ["maestro-journeys"])

    def test_rn_e2e_mocks(self):
        files = {"yarn.lock", ".maestro/smoke.yaml", ".maestro/a.yaml", ".maestro/b.yaml"}
        self.assertEqual(c.missing_items("react-native", files, RN_PKG, 0, False), ["e2e-mocks"])

    def test_rn_new_items_deadline(self):
        for item in ("maestro-journeys", "e2e-mocks"):
            self.assertEqual(c.item_deadline(item, "2026-11-10"), date(2026, 12, 29))

    def test_strapi_needs_no_fixture(self):
        # Generated data covers a repo without ci/fixture.sql.gz, and DevOps (not the repo) makes the copy.
        pkg = {"scripts": {"build": "x"}, "engines": {"node": "20"}}
        self.assertEqual(c.missing_items("strapi", {"package-lock.json"}, pkg, 0, False), [])

    def test_flutter_widget_test(self):
        ok = {"dep": True, "journeys": 3}
        self.assertEqual(c.missing_items("flutter", {"pubspec.lock"}, None, 0, False, flutter_e2e=ok), ["widget-test"])
        self.assertEqual(c.missing_items("flutter", {"pubspec.lock", "test/a_test.dart"}, None, 0, False,
                                         flutter_e2e=ok), [])

    def test_flutter_integration_test_item(self):
        files = {"pubspec.lock", "test/a_test.dart"}
        for fe in (None, {"dep": False, "journeys": 3}, {"dep": True, "journeys": 2}):
            self.assertEqual(c.missing_items("flutter", files, None, 0, False, flutter_e2e=fe), ["integration-test"])

    def test_flutter_item_deadline(self):
        self.assertEqual(c.item_deadline("integration-test", "2026-11-10"), date(2026, 12, 29))


class FlutterJourneys(unittest.TestCase):
    def tree(self, files):
        d = tempfile.mkdtemp()
        for rel, text in files.items():
            path = os.path.join(d, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as f:
                f.write(text)
        return d

    PUBSPEC = "name: app\ndev_dependencies:\n  flutter_test:\n    sdk: flutter\n  integration_test:\n    sdk: flutter\n"

    def test_flutter_dep_and_count(self):
        d = self.tree({"pubspec.yaml": self.PUBSPEC,
                       "integration_test/app_test.dart": "testWidgets('a', (t) async {});\n  testWidgets('b', (t) async {});\n",
                       "integration_test/more_test.dart": "testWidgets('c', (t) async {});\n"})
        self.assertEqual(c.flutter_journeys(d), {"dep": True, "journeys": 3})

    def test_flutter_commented_testwidgets_not_counted(self):
        d = self.tree({"pubspec.yaml": self.PUBSPEC,
                       "integration_test/app_test.dart": "// testWidgets('old', (t) async {});\ntestWidgets('a', (t) async {});\n"})
        self.assertEqual(c.flutter_journeys(d)["journeys"], 1)

    def test_flutter_nested_files_not_counted(self):
        d = self.tree({"pubspec.yaml": self.PUBSPEC,
                       "integration_test/sub/x_test.dart": "testWidgets('a', (t) async {});\n",
                       "integration_test/helpers.dart": "testWidgets('b', (t) async {});\n"})
        self.assertEqual(c.flutter_journeys(d)["journeys"], 0)

    def dep(self, pubspec):
        return c.flutter_journeys(self.tree({"pubspec.yaml": pubspec}))["dep"]

    def test_flutter_dep_forms_accepted(self):
        for text in ("dev_dependencies:\n  integration_test: { sdk: flutter }\n",       # the prompt's own form
                     "dev_dependencies:\n  integration_test: {sdk: flutter}\n",
                     "dev_dependencies:\n  integration_test:\n    sdk: flutter\n",
                     "dev_dependencies:\r\n  integration_test:\r\n    sdk: flutter\r\n",
                     "dev_dependencies:\n  integration_test: # e2e journeys\n    sdk: flutter\n"):
            self.assertTrue(self.dep(text), repr(text))

    def test_flutter_dep_forms_rejected(self):
        for text in ("dev_dependencies:\n#  integration_test:\n#    sdk: flutter\n",       # commented out
                     "dev_dependencies:\n  # integration_test: { sdk: flutter }\n",
                     "integration_test:\n  sdk: flutter\n",                                # top level
                     "dev_dependencies:\n  integration_test: ^1.0.0\n"):                   # hosted
            self.assertFalse(self.dep(text), repr(text))

    def test_flutter_dep_missing(self):
        d = self.tree({"pubspec.yaml": "name: app\ndev_dependencies:\n  flutter_test:\n    sdk: flutter\n"})
        self.assertEqual(c.flutter_journeys(d), {"dep": False, "journeys": 0})

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

    def test_integration_tests_deadline(self):
        self.assertEqual(c.item_deadline("integration-tests", "2026-12-21"), date(2026, 12, 29))

    def test_item_levels_no_repo_deadline_warns_forever(self):
        self.assertEqual(c.item_levels(["playwright", "lockfile"], "", date(2030, 1, 1)),
                         {"playwright": "warning", "lockfile": "warning"})


if __name__ == "__main__":
    unittest.main()
