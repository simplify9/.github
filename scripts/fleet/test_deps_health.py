import sys
import unittest
from datetime import datetime, timedelta, timezone

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import deps_health as d

NOW = datetime(2026, 10, 25, tzinfo=timezone.utc)


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def pr(state, age_h, merged_after_h=None, closed=False):
    c = NOW - timedelta(hours=age_h)
    m = iso(c + timedelta(hours=merged_after_h)) if merged_after_h is not None else None
    return {"state": state, "createdAt": iso(c), "mergedAt": m,
            "closedAt": m or (iso(c + timedelta(hours=1)) if closed else None)}


class T(unittest.TestCase):
    def test_pr_metrics_merge_rate_and_median(self):
        prs = [pr("MERGED", 100, 2), pr("MERGED", 100, 4), pr("MERGED", 100, 30),
               pr("CLOSED", 100, closed=True), pr("OPEN", 30), pr("OPEN", 5)]
        m = d.pr_metrics(prs, NOW)
        self.assertEqual((m["open"], m["open_over_24h"], m["merged"], m["closed_unmerged"]),
                         (2, 1, 3, 1))
        self.assertEqual(m["merge_rate"], 0.75)
        self.assertEqual(m["median_hours_to_merge"], 4.0)
        e = d.pr_metrics([], NOW)
        self.assertEqual((e["merge_rate"], e["median_hours_to_merge"]), (None, None))

    def test_stale_nonmajor_threshold(self):
        def o(repo, days, title="Update all non-major dependencies"):
            return {"repo": repo, "state": "OPEN", "title": title,
                    "createdAt": iso(NOW - timedelta(days=days))}
        prs = [o("a", 14), o("b", 15), o("c", 40, "Update dep X (major)"), o("b", 20)]
        self.assertEqual(d.stale_nonmajor(prs, NOW), ["b"])

    def test_overdue_alerts_thresholds(self):
        def a(sev, days):
            return {"security_advisory": {"severity": sev},
                    "created_at": iso(NOW - timedelta(days=days))}
        alerts = [a("high", 30), a("high", 31), a("medium", 90), a("medium", 91),
                  a("critical", 0), a("low", 500)]
        self.assertEqual(d.overdue_alerts(alerts, NOW),
                         {"critical": 1, "high": 1, "medium": 1})

    def test_excluded(self):
        self.assertTrue(d.excluded("zz-app", ["zz-"]))
        self.assertFalse(d.excluded("app-zz", ["zz-"]))
        self.assertFalse(d.excluded("zz-app", []))

    def test_summarize_scopes_and_exclusions(self):
        old = {**pr("OPEN", 24 * 40), "repo": "keep", "title": "Update all non-major dependencies"}
        gone = {**old, "repo": "zz-skip"}
        win = [{**pr("MERGED", 10, 1), "repo": "keep"}, {**pr("MERGED", 10, 1), "repo": "zz-skip"}]
        alerts = [{"repository": {"name": n}, "security_advisory": {"severity": "critical"},
                   "created_at": iso(NOW)} for n in ("keep", "zz-skip")]
        issues = [{"repository": {"name": n}} for n in ("keep", "zz-skip", "zz-skip")]
        r = d.summarize([old, gone], win, alerts, issues, NOW, ["zz-"])
        self.assertEqual(r["open"]["open"], 1)  # created before --since, still counted
        self.assertEqual(r["stale_nonmajor_repos"], ["keep"])
        self.assertEqual(r["window"]["merged"], 1)
        self.assertEqual(r["overdue_alerts"], {"critical": 1})
        self.assertEqual(r["open_verify_contract_issues"], 1)

    def test_split_window_keeps_extra_qualifier(self):
        qs = []

        def fake(q, bail_over_cap=False):
            qs.append(q)
            return [], 1500 if "2026-10-01..2026-10-04" in q else 0
        orig, d.search_prs = d.search_prs, fake
        try:
            d.fetch_window("bot", "o", datetime(2026, 10, 1), datetime(2026, 10, 4), "is:open")
        finally:
            d.search_prs = orig
        self.assertEqual(len(qs), 3)
        self.assertTrue(all("is:open" in q for q in qs), qs)


if __name__ == "__main__":
    unittest.main()
