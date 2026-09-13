# =============================================================================
# alerts_to_csv.jq -- blocking-alerts CSV report for check-critical-vulns
# =============================================================================
# Turns the merged Dependabot Alerts API pages (a JSON array of alert objects,
# exactly as action.yml accumulates them in $alerts_file) into the CSV that is
# uploaded as a run artifact when the gate fails. One row per alert that is
# still blocking, with everything a developer -- or the coding agent they hand
# the file to -- needs to fix it without opening each alert by hand.
#
# Usage:
#   jq -r --arg repo owner/repo --arg cleared "$cleared_numbers" \
#     -f alerts_to_csv.jq alerts.json
#
#   $repo     Written into every row so a file stays self-describing once it
#             has been downloaded and passed around.
#   $cleared  Newline-separated alert numbers that PR-branch verification
#             already cleared (may be empty). Those are excluded, so the CSV
#             always matches the blocking count the gate reports.
#
# Output is RFC 4180 via @csv: every string quoted, embedded quotes doubled,
# newlines kept inside the quoted cell. Absent optional values are "".
#
# Free-text cells (summary, description) are third-party authored advisory
# text, so a leading = + - @ TAB or CR gets a ' prefix to stop spreadsheet
# apps evaluating it as a formula (OWASP "CSV injection"). Structured cells --
# package names, version ranges such as "= 1.0.0", paths -- stay verbatim,
# because a tool acting on them needs the exact value.
# =============================================================================

def header: [
  "repository", "alert_number", "alert_url", "ghsa_id", "cve_id", "severity",
  "cvss_score", "cvss_vector", "ecosystem", "package", "manifest_path",
  "relationship", "scope", "vulnerable_version_range", "first_patched_version",
  "suggested_fix", "summary", "cwes", "advisory_url", "references",
  "alert_created_at", "description"
];

def safe_text: if test("^[=+\\-@\t\r]") then "'" + . else . end;

# The API reports a missing CVSS version as score 0.0 (not null), so "absent"
# means null OR zero. Prefer v4, then v3, then the legacy top-level cvss.
def cvss:
  .security_advisory as $a
  | [$a.cvss_severities.cvss_v4, $a.cvss_severities.cvss_v3, $a.cvss]
  | map(select(. != null and (.score // 0) > 0))
  | .[0] // {score: "", vector_string: ""};

def override_hint:
  {
    "npm":   "npm overrides / yarn resolutions / pnpm overrides",
    "nuget": "a direct PackageReference (or a Central Package Management pin)",
    "maven": "Maven dependencyManagement / Gradle dependency constraints",
    "pip":   "a pinned requirement or constraints file",
    "pub":   "pubspec dependency_overrides"
  }[.dependency.package.ecosystem // ""]
  // "your package manager's override mechanism";

def suggested_fix:
  (.dependency.package.name // "the package") as $pkg
  | (.dependency.manifest_path // "its manifest") as $manifest
  | (.security_vulnerability.first_patched_version.identifier // "") as $patched
  | if $patched == "" then
      "No patched version of \($pkg) has been published: remove or replace it (flagged in \($manifest)), or dismiss the alert with a documented reason if the vulnerable code is unreachable."
    elif .dependency.relationship == "direct" then
      "Direct dependency: upgrade \($pkg) to >= \($patched) (flagged in \($manifest)) and regenerate the lockfile."
    elif .dependency.relationship == "transitive" then
      "Transitive dependency: upgrade the direct dependency that pulls in \($pkg) to a release requiring >= \($patched); if none exists, force \($pkg) >= \($patched) via \(override_hint). Then regenerate \($manifest)."
    else
      "Upgrade \($pkg) to >= \($patched) (flagged in \($manifest)); if it is only pulled in transitively, upgrade its parent or force the version via \(override_hint)."
    end;

def row:
  cvss as $cvss
  | .security_advisory as $a
  | [
      $repo,
      .number,
      .html_url // "",
      $a.ghsa_id // "",
      $a.cve_id // "",
      .security_vulnerability.severity // $a.severity // "",
      $cvss.score,
      $cvss.vector_string // "",
      .dependency.package.ecosystem // "",
      .dependency.package.name // "",
      .dependency.manifest_path // "",
      .dependency.relationship // "",
      .dependency.scope // "",
      .security_vulnerability.vulnerable_version_range // "",
      .security_vulnerability.first_patched_version.identifier // "",
      suggested_fix,
      ($a.summary // "" | safe_text),
      ([$a.cwes[]? | "\(.cwe_id): \(.name)"] | join("; ")),
      (if $a.ghsa_id then "https://github.com/advisories/\($a.ghsa_id)" else "" end),
      ([$a.references[]?.url] | join(" ")),
      .created_at // "",
      ($a.description // "" | safe_text)
    ];

($cleared | split("\n") | map(select(. != "") | tonumber)) as $cleared_numbers
| header,
  (.[] | select(.number as $n | any($cleared_numbers[]; . == $n) | not) | row)
| @csv
