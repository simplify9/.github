import os
import unittest

import e2e_report as r

HERE = os.path.dirname(os.path.abspath(__file__))


def data(name):
    with open(os.path.join(HERE, "testdata", name), encoding="utf-8") as f:
        return f.read()


class Parse(unittest.TestCase):
    def test_parse_failed_and_flaky(self):
        res = r.parse(data("failed_flaky.txt"))
        self.assertEqual(res["failed"], ["[chromium] › e2e/journeys.spec.ts:5:7 › orders › list shows items"])
        self.assertEqual(res["flaky"], ["[chromium] › e2e/journeys.spec.ts:3:5 › sign in works"])
        self.assertEqual(res["passed"], 1)

    def test_parse_green(self):
        res = r.parse(data("green.txt"))
        self.assertEqual((res["failed"], res["flaky"], res["passed"]), ([], [], 1))

    def test_parse_strips_ansi(self):
        res = r.parse(data("failed_flaky.txt"))
        self.assertFalse(any("\x1b" in t or "─" in t for t in res["failed"] + res["flaky"]))

    def test_parse_unknown_reporter_output(self):
        res = r.parse("To open last HTML report run:\n\n  npx playwright show-report\n")
        self.assertEqual((res["failed"], res["flaky"], res["passed"]), ([], [], None))


class Markdown(unittest.TestCase):
    def test_markdown_names_tests(self):
        md = r.markdown({"failed": ["[chromium] › a.spec.ts:1:1 › x"], "flaky": ["[chromium] › b.spec.ts:2:2 › y"],
                         "passed": 3})
        self.assertIn("a.spec.ts:1:1 › x", md)
        self.assertIn("b.spec.ts:2:2 › y", md)
        self.assertIn("3 passed", md)

    def test_markdown_without_summary_says_so(self):
        md = r.markdown({"failed": [], "flaky": [], "passed": None})
        self.assertIn("list", md)


if __name__ == "__main__":
    unittest.main()
