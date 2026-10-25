# Overdue open Dependabot alerts: high older than $high days, medium older than
# $medium days (strictly more than the deadline). Critical is enforced by the
# main gate step and low is report-only, so both are ignored here.
# Usage: jq --argjson now <epoch> --argjson high <d> --argjson medium <d> -f sla_overdue.jq
[ .[]
  | (.security_advisory.severity // "") as $sev
  | select($sev == "high" or $sev == "medium")
  | ((($now - (.created_at | fromdateiso8601)) / 86400) | floor) as $age
  | (if $sev == "high" then $high else $medium end) as $deadline
  | select($age > $deadline)
  | { number,
      severity: $sev,
      package: (.dependency.package.name // "unknown"),
      ecosystem: (.dependency.package.ecosystem // "unknown"),
      age_days: $age,
      deadline_days: $deadline,
      html_url: (.html_url // "") } ]
| sort_by(-.age_days)
