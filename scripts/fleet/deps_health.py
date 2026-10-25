#!/usr/bin/env python3
"""Fleet metrics for the dependency-automation success criteria (S1, S2, S4-S7).

Read-only: GitHub GraphQL search, the org Dependabot alerts GET, and an issue
count. Output is plain ASCII on stdout; nothing is written anywhere.

GitHub search returns at most 1000 results per query, so PRs are fetched in
weekly created-date windows (each paginated), and the counts are computed from
the fetched PRs. A window that hits the cap is reported on stderr.

Usage:
  scripts/fleet/deps_health.py --since 2026-10-08 [--json]

Requires: gh (authenticated with repo read on the org).
"""
import argparse
import json
import statistics
import subprocess
import sys
from datetime import datetime, timedelta, timezone

BOTS = ("app/dependabot", "app/s9-deps-bot")
NONMAJOR = "non-major dependencies"

SEARCH = """query($q:String!,$after:String){search(query:$q,type:ISSUE,first:100,after:$after){
issueCount pageInfo{hasNextPage endCursor}
nodes{... on PullRequest{title state createdAt mergedAt closedAt repository{name}}}}}"""


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def pr_metrics(prs, now):
    """S1/S2/S4 numbers from [{state, createdAt, mergedAt, closedAt}]."""
    opn = [p for p in prs if p["state"] == "OPEN"]
    merged = [p for p in prs if p["state"] == "MERGED"]
    closed = [p for p in prs if p["state"] == "CLOSED"]
    done = len(merged) + len(closed)
    hours = [(ts(p["mergedAt"]) - ts(p["createdAt"])).total_seconds() / 3600 for p in merged]
    return {
        "open": len(opn),
        "open_over_24h": sum(now - ts(p["createdAt"]) > timedelta(hours=24) for p in opn),
        "merged": len(merged),
        "closed_unmerged": len(closed),
        "merge_rate": len(merged) / done if done else None,
        "median_hours_to_merge": statistics.median(hours) if hours else None,
    }


def stale_nonmajor(prs, now, days=14):
    """S5: repos with an open non-major group PR older than `days`."""
    return sorted({p["repo"] for p in prs
                   if p["state"] == "OPEN" and NONMAJOR in p["title"]
                   and now - ts(p["createdAt"]) > timedelta(days=days)})


def overdue_alerts(alerts, now, high=30, medium=90):
    """S6: open alerts past deadline per severity; critical counts at any age."""
    limit = {"high": high, "medium": medium}
    out = {}
    for a in alerts:
        sev = a["security_advisory"]["severity"]
        if sev == "critical" or (sev in limit and now - ts(a["created_at"]) > timedelta(days=limit[sev])):
            out[sev] = out.get(sev, 0) + 1
    return out


def gh(*args):
    r = subprocess.run(["gh", *args], capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"gh {args[0]} failed: {r.stderr.strip()[:200]}")
    return r.stdout


def search_prs(query, bail_over_cap=False):
    """All PRs for one search query (<=1000), flattened for the pure functions.
    bail_over_cap: return after page 1 when the query exceeds the cap (caller splits it)."""
    out, after = [], None
    while True:
        a = ["api", "graphql", "-f", f"query={SEARCH}", "-f", f"q={query}"]
        if after:
            a += ["-f", f"after={after}"]
        s = json.loads(gh(*a))["data"]["search"]
        out += [{**n, "repo": n["repository"]["name"]} for n in s["nodes"] if n]
        if not s["pageInfo"]["hasNextPage"] or (bail_over_cap and s["issueCount"] > 1000):
            return out, s["issueCount"]
        after = s["pageInfo"]["endCursor"]


def fetch_window(bot, org, lo, hi, extra=""):
    """PRs created on days lo..hi inclusive. Over the 1000 cap: halve the window, and for a
    single day split by state (extra qualifier) before giving up with a warning."""
    q = f"org:{org} is:pr author:{bot} created:{lo:%Y-%m-%d}..{hi:%Y-%m-%d} {extra}".strip()
    got, total = search_prs(q, bail_over_cap=lo < hi or not extra)
    if total <= 1000:
        return got
    if lo < hi:
        mid = lo + (hi - lo) // 2  # dates, so halves never overlap
        return fetch_window(bot, org, lo, mid) + fetch_window(bot, org, mid + timedelta(days=1), hi)
    if not extra:
        return [p for st in ("is:open", "is:merged", "is:closed -is:merged")
                for p in fetch_window(bot, org, lo, hi, st)]
    print(f"warning: {q!r} has {total} results, capped at 1000", file=sys.stderr)
    return got


def fetch_prs(since, now, org):
    prs = [p for bot in BOTS for p in fetch_window(bot, org, since.date(), now.date())]
    return [p for p in prs if not p["repo"].startswith("riverhead-")]


def pct(x):
    return "n/a" if x is None else f"{x * 100:.1f}%"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--since", required=True, help="YYYY-MM-DD, PRs created on/after")
    ap.add_argument("--org", default="simplify9")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    now = datetime.now(timezone.utc)
    since = datetime.fromisoformat(a.since).replace(tzinfo=timezone.utc)

    prs = fetch_prs(since, now, a.org)
    m = pr_metrics(prs, now)
    stale = stale_nonmajor(prs, now)
    alerts = [json.loads(l) for l in gh(
        "api", f"/orgs/{a.org}/dependabot/alerts?state=open&per_page=100",
        "--paginate", "--jq", ".[]|tojson").splitlines() if l]
    overdue = overdue_alerts(alerts, now)
    contract = len(json.loads(gh("search", "issues", "--owner", a.org, "--label", "verify-contract",
                                 "--state", "open", "--limit", "1000", "--json", "number")))
    res = {"since": a.since, "prs": m, "stale_nonmajor_repos": stale,
           "overdue_alerts": overdue, "open_verify_contract_issues": contract}
    if a.json:
        print(json.dumps(res, indent=2))
        return
    print(f"deps health since {a.since} ({len(prs)} bot PRs, org {a.org})")
    h = m["median_hours_to_merge"]
    for k, v in [
        ("S1 open bot PRs", f"{m['open']} ({m['open_over_24h']} older than 24h)"),
        ("S2 merge rate", f"{pct(m['merge_rate'])} ({m['merged']} merged, {m['closed_unmerged']} closed unmerged)"),
        ("S4 median hours to merge", "n/a" if h is None else f"{h:.1f}"),
        ("S5 repos non-major pending >14d", f"{len(stale)}"),
        ("S6 alerts past deadline", ", ".join(f"{s}={n}" for s, n in sorted(overdue.items())) or "0"),
        ("S7 open verify-contract issues", f"{contract}"),
    ]:
        print(f"  {k:<34} {v}")


if __name__ == "__main__":
    main()
