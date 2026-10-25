import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
import singletons  # noqa: E402


def pkg(root, rel, name, version):
    d = Path(root, rel)
    d.mkdir(parents=True, exist_ok=True)
    (d / "package.json").write_text(json.dumps({"name": name, "version": version}))


class SingletonTests(unittest.TestCase):
    def setUp(self):
        self._t = tempfile.TemporaryDirectory()
        self.root = Path(self._t.name)
        self.addCleanup(self._t.cleanup)

    def find(self, names=("react",)):
        return singletons.find_versions(self.root, list(names))

    def test_single_version_ok(self):
        pkg(self.root, "node_modules/react", "react", "18.3.1")
        found = self.find()
        self.assertEqual(found["react"], {"18.3.1"})
        self.assertEqual(singletons.problems(found), [])

    def test_nested_duplicate_detected(self):
        pkg(self.root, "node_modules/react", "react", "18.3.1")
        pkg(self.root, "node_modules/some-lib/node_modules/react", "react", "19.0.0")
        out = singletons.problems(self.find())
        self.assertEqual(len(out), 1)
        self.assertIn("react resolves to 18.3.1, 19.0.0", out[0])

    def test_same_version_twice_is_ok(self):
        pkg(self.root, "node_modules/react", "react", "18.3.1")
        pkg(self.root, "node_modules/x/node_modules/react", "react", "18.3.1")
        self.assertEqual(singletons.problems(self.find()), [])

    def test_scoped_names_supported(self):
        pkg(self.root, "node_modules/@types/react", "@types/react", "18.0.0")
        pkg(self.root, "node_modules/a/node_modules/@types/react", "@types/react", "19.0.0")
        out = singletons.problems(self.find(["@types/react"]))
        self.assertEqual(len(out), 1)
        self.assertIn("@types/react", out[0])

    def test_pnpm_layout_duplicate_detected(self):
        pkg(self.root, "node_modules/.pnpm/react@18.3.1/node_modules/react", "react", "18.3.1")
        pkg(self.root, "node_modules/.pnpm/react@19.0.0/node_modules/react", "react", "19.0.0")
        self.assertEqual(len(singletons.problems(self.find())), 1)

    def test_symlinks_not_followed(self):
        pkg(self.root, "node_modules/.pnpm/react@18.3.1/node_modules/react", "react", "18.3.1")
        (self.root / "node_modules/react").symlink_to(
            self.root / "node_modules/.pnpm/react@18.3.1/node_modules/react")
        (self.root / "node_modules/loop").symlink_to(self.root / "node_modules")
        self.assertEqual(self.find()["react"], {"18.3.1"})

    def test_pnp_reports_skipped(self):
        (self.root / ".pnp.cjs").write_text("")
        r = subprocess.run([sys.executable, str(HERE / "singletons.py"), "--dir", str(self.root),
                            "--names", "react"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0)
        self.assertIn("skipped (PnP)", r.stdout)

    def test_missing_node_modules_fails(self):
        r = subprocess.run([sys.executable, str(HERE / "singletons.py"), "--dir", str(self.root),
                            "--names", "react"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 1)
        self.assertIn("::error title=[VERIFY] Node deps::node_modules not found in "
                      + str(self.root) + " (install did not run?)", r.stdout)

    def test_cli_duplicate_fails(self):
        pkg(self.root, "node_modules/react", "react", "18.3.1")
        pkg(self.root, "node_modules/l/node_modules/react", "react", "19.0.0")
        r = subprocess.run([sys.executable, str(HERE / "singletons.py"), "--dir", str(self.root),
                            "--names", "react"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 1)
        self.assertIn("::error title=[VERIFY] Duplicate singleton::react resolves to 18.3.1, 19.0.0", r.stdout)


if __name__ == "__main__":
    unittest.main()
