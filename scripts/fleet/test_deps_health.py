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


if __name__ == "__main__":
    unittest.main()
