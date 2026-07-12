# Dependabot Org-Wide Rollout + Critical-Vuln Merge Gate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Roll out Dependabot version updates + security updates across all 232 active repos in the `simplify9` GitHub org, targeting `develop` (or the repo's actual default branch where `develop` doesn't exist), and add a critical-severity Dependabot-alert gate that blocks merges into `main` (warns on `develop`) and blocks build/deploy pipelines running on the release branch.

**Architecture:** One new composite action (`check-critical-vulns`) queries the Dependabot Alerts REST API for open critical-severity alerts; it is reused at three call sites — a PR-time check (new reusable workflow + workflow-template, enforced via branch protection), a build-time gate wired into every deploy/build reusable workflow, and a dependency of a new patch-only auto-merge template. Six category `dependabot.yml` templates and a Python rollout script handle the 232-repo fan-out.

**Tech Stack:** GitHub Actions composite actions (bash), GitHub REST API via `curl`/`jq` (no `gh api` dependency, matching this repo's existing `tag-github-origin` style), Python 3 stdlib + `gh` CLI subprocess calls for the rollout script (no new pip dependencies — this is one-off ops tooling, not a maintained library).

## Global Constraints

- Org is on GitHub **Team** plan, not Enterprise/GHAS — no org-wide security policy toggle exists; every enablement (vuln alerts, branch protection, dependabot.yml) is done per-repo.
- 232 active repos in scope (244 total minus 12 archived; 0 forks).
- Vulnerability severity gate is **critical-only** (not critical+high).
- Auto-merge is **patch-level bumps only**, ecosystems `npm`, `nuget`, `pub`, `bundler`, `github-actions` — never `docker`, never minor/major.
- `target-branch` is `develop` where it exists (140/232 repos), else the repo's actual default branch (92/232 repos) — never hardcode `main`.
- Every new/modified file in `.github/actions/` and `.github/workflows/` follows AGENTS.md's 4-pillar log framework exactly: `::notice::` announce, `::group::`/`::endgroup::` checkpoints with **namespaced** `<PREFIX>_CP{N}_STATUS` env vars, canonical emoji/tag vocabulary, `write-job-summary` (reusable workflows) or an inline `if: always()` summary step (composite actions).
- Reusable workflows in `.github/workflows/*.yml` never carry `on: push`/`on: pull_request` triggers — those live only in `workflow-templates/`.
- Never call composite actions via local `./.github/actions/...` paths from inside reusable workflows — always the external `simplify9/.github/.github/actions/<name>@main` form.
- There is no local test runner for this repo (per CLAUDE.md) — every task's verification step says so explicitly and describes the real validation path (temp branch + a consumer repo, or direct inspection).

---

## Deviations from the spec found during grounding (read this before Tasks 8-10)

The spec assumed all six Helm/Cloudflare deploy pipelines expose a `determine-semver`-derived `is-release` output to gate on. Direct inspection found this is only true for **three** of them:

- `reusable-service-cicd.yml`, `generic-chart-helm.yml`, `generic-gateway-helm-template.yml` — all have a `version` job with `is-release: ${{ steps.semver.outputs.is-release }}`. Gate these on `needs.version.outputs.is-release == 'true'` as the spec intended (Tasks 5-7).
- `helm-deploy-values.yml`, `next-cloudflare-worker.yaml`, `vite-cloudflare-worker.yml` are **deploy-only** pipelines with a single `deploy` job, no versioning, no `is-release` output — they deploy to whatever `environment`/`gh-environment` input the caller passes, with no ref-based release concept at all. There is nothing to delegate to. For these three, the gate condition inline-compares `github.ref_name == github.event.repository.default_branch` — the same underlying signal `determine-semver` uses internally (`release-branch: github.event.repository.default_branch`), just computed directly since no version job exists to source it from (Tasks 8-10). This is flagged here rather than silently deviating from the written spec.

---

### Task 1: `check-critical-vulns` composite action

**Files:**
- Create: `.github/actions/check-critical-vulns/action.yml`

**Interfaces:**
- Consumes: nothing from other tasks (first task).
- Produces: composite action `simplify9/.github/.github/actions/check-critical-vulns@main`. Inputs: `github-token` (required), `repository` (optional, default `${{ github.repository }}`). Outputs: `critical-count` (string, integer count). **On any open critical alert, the step itself exits non-zero** with an `::error::` explicitly naming the failure as a critical Dependabot alert (this is the contract every later task relies on — the action fails the calling job, callers don't need their own `if: steps.x.outputs.critical-count > 0` check).

- [ ] **Step 1: Create the action file**

```yaml
# =============================================================================
# Check Critical Dependabot Vulnerabilities
# =============================================================================
# Queries the Dependabot Alerts REST API for open CRITICAL-severity alerts on
# the target repository and FAILS the step (non-zero exit) if any are found.
# This is the single mechanism reused at three call sites: the PR-time
# critical-vuln-gate reusable workflow (enforced via branch protection), the
# build-time gate embedded in every deploy/build reusable workflow, and a
# dependency of the dependabot-auto-merge workflow-template.
#
# Deliberately NOT actions/dependency-review-action: that action's private-repo
# enforcement guarantees have historically required a GitHub Advanced Security
# license, and this org is on the Team plan. This action only needs Dependabot
# alerts enabled on the repo (a free feature) plus a token with
# `security-events: read`.
#
# Inputs:
#   github-token  (required)  Token with security-events:read on the target
#                             repo (the caller's job must grant this in its
#                             own `permissions:` block — job-level permissions
#                             override the workflow-level default).
#   repository    (optional)  owner/repo to check. Default: the calling repo.
#
# Outputs (set on both pass and fail — unlike this repo's version/tag actions,
# the count is useful even when it causes a failure, e.g. for the caller's
# job summary):
#   critical-count  Number of open critical-severity alerts found.
# =============================================================================
name: 'Check Critical Dependabot Vulnerabilities'
author: 'Simplify9'
description: 'Fails if the repository has any open critical-severity Dependabot alert.'

inputs:
  github-token:
    description: 'Token with security-events:read permission on the target repository.'
    required: true
  repository:
    description: 'Target repository in owner/repo format. Defaults to the calling repository.'
    required: false
    default: ${{ github.repository }}

outputs:
  critical-count:
    description: 'Number of open critical-severity Dependabot alerts found. Set on both pass and fail.'
    value: ${{ steps.check.outputs.critical-count }}

runs:
  using: "composite"
  steps:
    - name: Announce critical-vuln check
      shell: bash
      env:
        REPOSITORY: ${{ inputs.repository }}
      run: |
        echo "::notice title=🔒 [VULN-GATE] Critical Vulnerability Check::repository: ${REPOSITORY}"
        echo "VULN_GATE_CP1_STATUS=⏳ Pending" >> "$GITHUB_ENV"

    - name: Query Dependabot alerts and evaluate
      id: check
      shell: bash
      env:
        GITHUB_TOKEN: ${{ inputs.github-token }}
        REPOSITORY: ${{ inputs.repository }}
      run: |
        set -euo pipefail
        echo "::add-mask::$GITHUB_TOKEN"
        echo "::group::🔒 [CHECKPOINT 1/1] Query Open Critical Dependabot Alerts"

        page=1
        total_critical=0
        summary_rows=""

        while :; do
          response_file="$(mktemp)"
          http_code="$(curl -sS \
            --max-time 30 \
            --retry 3 \
            --retry-connrefused \
            -o "$response_file" \
            -w '%{http_code}' \
            -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "https://api.github.com/repos/${REPOSITORY}/dependabot/alerts?state=open&severity=critical&per_page=100&page=${page}")"

          if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
            echo "::error title=❌ [VULN-GATE] Dependabot Alerts API call failed::HTTP ${http_code} on page ${page} for ${REPOSITORY}. Response: $(cat "$response_file")"
            rm -f "$response_file"
            exit 1
          fi

          page_count="$(jq 'length' "$response_file")"
          if [[ "$page_count" -eq 0 ]]; then
            rm -f "$response_file"
            break
          fi

          total_critical=$((total_critical + page_count))
          summary_rows+="$(jq -r '.[] | "| " + (.security_advisory.ghsa_id // "unknown") + " | " + (.dependency.package.name // "unknown") + " | [" + (.html_url // "") + "](" + (.html_url // "") + ") |"' "$response_file")"
          summary_rows+=$'\n'
          rm -f "$response_file"

          if [[ "$page_count" -lt 100 ]]; then
            break
          fi
          page=$((page + 1))
          if [[ "$page" -gt 10 ]]; then
            echo "::warning title=⚠️ [VULN-GATE] Pagination cap reached::Stopped after 10 pages (1000 alerts) for ${REPOSITORY} — true count may be higher."
            break
          fi
        done

        echo "critical-count=${total_critical}" >> "$GITHUB_OUTPUT"
        EOF="$(dd if=/dev/urandom bs=15 count=1 status=none | base64)"
        {
          echo "alert-summary<<$EOF"
          printf '%s\n' "$summary_rows"
          echo "$EOF"
        } >> "$GITHUB_OUTPUT"

        echo "VULN_GATE_CP1_STATUS=✅ PASSED" >> "$GITHUB_ENV"
        echo "::endgroup::"

        if [[ "$total_critical" -gt 0 ]]; then
          echo "::error title=❌ [VULN-GATE] Blocked by critical Dependabot alert(s)::${REPOSITORY} has ${total_critical} open CRITICAL-severity Dependabot alert(s) — this check/pipeline is blocked until they are resolved or dismissed."
          printf '%s\n' "$summary_rows"
          exit 1
        fi

    - name: Report failure
      if: failure()
      shell: bash
      env:
        REPOSITORY: ${{ inputs.repository }}
      run: |
        echo "::error title=❌ [VULN-GATE] Critical vulnerability gate failed::${REPOSITORY} is blocked — either the Dependabot Alerts API call failed, or an open CRITICAL-severity alert exists. Checkpoint — 1) Query alerts: ${VULN_GATE_CP1_STATUS:-⏭️ Not reached}. See the step above for affected package(s)/advisory ID(s)."

    - name: Write action summary
      if: always()
      shell: bash
      env:
        REPOSITORY: ${{ inputs.repository }}
        CRITICAL_COUNT: ${{ steps.check.outputs.critical-count }}
      run: |
        EOF="$(dd if=/dev/urandom bs=15 count=1 status=none | base64)"
        cat >> "$GITHUB_STEP_SUMMARY" << "$EOF"
        ## 🔒 Critical Dependabot Vulnerability Check

        | Field | Value |
        |-------|-------|
        | Repository | ${{ inputs.repository }} |
        | Open critical alerts found | ${CRITICAL_COUNT:-unknown} |

        ## 📋 Checkpoint Summary

        | # | Checkpoint | Status |
        |---|------------|--------|
        | 1 | Query open critical Dependabot alerts | ${VULN_GATE_CP1_STATUS:-⏭️ Not reached} |
        $EOF

branding:
  icon: 'shield'
  color: 'red'
```

- [ ] **Step 2: Commit**

```bash
git add .github/actions/check-critical-vulns/action.yml
git commit -m "feat: add check-critical-vulns composite action"
```

- [ ] **Step 3: Verify (no local test runner — this repo's real validation is a consumer-repo run)**

There is nothing to execute locally. Confirm the YAML parses by running `yamllint .github/actions/check-critical-vulns/action.yml` if `yamllint` is available, otherwise visually re-check indentation. Full verification happens in Task 2's caller once a reusable workflow exists to invoke this action.

---

### Task 2: `critical-vuln-gate.yml` reusable workflow

**Files:**
- Create: `.github/workflows/critical-vuln-gate.yml`

**Interfaces:**
- Consumes: `simplify9/.github/.github/actions/check-critical-vulns@main` (Task 1) — inputs `github-token`, `repository`; output `critical-count`.
- Produces: reusable workflow `simplify9/.github/.github/workflows/critical-vuln-gate.yml@main`, `on: workflow_call:`. Secrets: `github-token` (required). Job id: **`check`** — this exact job id is the name later tasks (workflow-templates in Tasks 3-4, and branch-protection config in Task 27) reference as the check context.

- [ ] **Step 1: Create the reusable workflow**

```yaml
# =============================================================================
# Critical Dependabot Vulnerability Gate — reusable workflow
# =============================================================================
# Thin wrapper around the check-critical-vulns composite action. Called from:
#   - workflow-templates/critical-vuln-check.yml (PR-time check, enforced via
#     branch protection: required on main, present-but-not-required on develop)
#   - workflow-templates/dependabot-auto-merge.yml (gates auto-merge)
# Never called with on: push/pull_request itself — those triggers live only
# in workflow-templates/, per this repo's convention.
# =============================================================================
name: Critical Dependabot Vulnerability Gate

on:
  workflow_call:
    secrets:
      github-token:
        description: 'Token with security-events:read on the calling repository. Pass secrets.GITHUB_TOKEN.'
        required: true

permissions: {}

jobs:
  check:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      security-events: read
    steps:
      - name: Check for open critical Dependabot alerts
        uses: simplify9/.github/.github/actions/check-critical-vulns@main
        with:
          github-token: ${{ secrets.github-token }}
          repository: ${{ github.repository }}

      - name: Write job summary
        if: always()
        uses: simplify9/.github/.github/actions/write-job-summary@main
        with:
          icon: '🔒'
          title: Critical Dependabot Vulnerability Gate
          status: ${{ job.status }}
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/critical-vuln-gate.yml
git commit -m "feat: add critical-vuln-gate reusable workflow"
```

- [ ] **Step 3: Verify**

No local runner. Real validation happens in Task 3 once a workflow-template can call this on a real PR in a test/consumer repo — confirm the Actions tab shows a job named `check` under the workflow run, and that it fails when a repo has an open critical alert (or passes/succeeds cleanly when it doesn't).

---

### Task 3: `critical-vuln-check` workflow-template (PR-time trigger)

**Files:**
- Create: `workflow-templates/critical-vuln-check.yml`
- Create: `workflow-templates/critical-vuln-check.properties.json`

**Interfaces:**
- Consumes: `simplify9/.github/.github/workflows/critical-vuln-gate.yml@main` (Task 2), job id `check`.
- Produces: the file callers copy into their own repo at `.github/workflows/critical-vuln-check.yml`. **The status-check context this produces for branch protection is the job id `check` as it appears under this template's job `vuln-gate`** — GitHub Actions typically renders nested reusable-workflow checks as `<caller-job-id> / <called-job-id>`, so the expected context string is `vuln-gate / check`. **This exact string must be confirmed against the Task 28 pilot run** (nested-workflow check-name rendering is a known GitHub Actions nuance not worth asserting blind) — Task 27's branch-protection code takes this string as a documented, overridable constant for exactly that reason.

- [ ] **Step 1: Create the template**

```yaml
# =============================================================================
# Critical Dependabot Vulnerability Check — Caller template
# =============================================================================
# USAGE:
#   Copy this file to your repo at .github/workflows/critical-vuln-check.yml.
#   No REPLACE values needed — this template requires no customization.
#
# WHAT IT DOES:
#   Runs on every PR targeting main or develop. Fails if the repository has
#   any open CRITICAL-severity Dependabot alert.
#
#   Enforcement differs by target branch via each repo's OWN branch
#   protection settings (not by anything in this file):
#     - On `main`:    mark this check REQUIRED in branch protection — merge
#                     is physically blocked while a critical alert is open.
#     - On `develop`: leave this check NOT required — it still shows as a
#                     failing/red check (a visible warning) without blocking
#                     the merge.
# =============================================================================
name: Critical Vulnerability Check
run-name: vuln-check-${{ github.event.pull_request.number }}

on:
  pull_request:
    branches: [main, develop]

permissions:
  security-events: read

jobs:
  vuln-gate:
    uses: simplify9/.github/.github/workflows/critical-vuln-gate.yml@main
    secrets:
      github-token: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 2: Create the properties sidecar**

```json
{
    "name": "Critical Vulnerability Check",
    "description": "Fails a PR check if the repository has any open critical-severity Dependabot alert. Mark this check required on main's branch protection to block merges; leave it optional on develop to only warn.",
    "iconName": "octicon-shield",
    "categories": [
        "Security"
    ]
}
```

- [ ] **Step 3: Commit**

```bash
git add workflow-templates/critical-vuln-check.yml workflow-templates/critical-vuln-check.properties.json
git commit -m "feat: add critical-vuln-check workflow-template"
```

- [ ] **Step 4: Verify**

No local runner. Real validation is Task 28's pilot: copy this file into a pilot repo, open a PR, confirm the check named `vuln-gate / check` (or whatever GitHub actually renders — record the real string) appears, and that it fails/passes correctly based on that repo's alert state.

---

### Task 4: `dependabot-auto-merge` workflow-template

**Files:**
- Create: `workflow-templates/dependabot-auto-merge.yml`
- Create: `workflow-templates/dependabot-auto-merge.properties.json`
- Modify: `AGENTS.md` — add `dependabot/fetch-metadata` to the Pinned Action Versions table (Task 22 does the full documentation pass, but pin the version here since this task introduces it).

**Interfaces:**
- Consumes: `simplify9/.github/.github/workflows/critical-vuln-gate.yml@main` (Task 2).
- Produces: caller file `.github/workflows/dependabot-auto-merge.yml`. Two jobs: `vuln-gate` (needs nothing) and `auto-merge` (`needs: vuln-gate`). **This template re-runs the vuln-gate check independently of the `critical-vuln-check.yml` template's own run** — GitHub Actions jobs can only `needs:` other jobs within the *same* workflow file, so there is no way to make `auto-merge` depend on a job defined in a different workflow file. This is a deliberate, minor duplication of the check run, not an oversight.

- [ ] **Step 1: Create the template**

```yaml
# =============================================================================
# Dependabot Auto-Merge — Caller template
# =============================================================================
# USAGE:
#   Copy this file to your repo at .github/workflows/dependabot-auto-merge.yml.
#   No REPLACE values needed.
#
# WHAT IT DOES:
#   Auto-merges a Dependabot PR ONLY when ALL of the following hold:
#     - The PR author is dependabot[bot]
#     - The update is a semver PATCH bump (never minor/major)
#     - The ecosystem is npm, nuget, pub, bundler, or github-actions
#       (NEVER docker — base image bumps always need manual review)
#     - This repo currently has no open critical Dependabot alert (re-checked
#       here explicitly — see workflow-templates/critical-vuln-check.yml's
#       header for why this can't just `needs:` that file's job)
#   "Auto-merge" here means GitHub's native auto-merge feature: it still
#   waits for the repo's actual required status checks (build/test) to pass
#   before merging — this workflow does not bypass those.
# =============================================================================
name: Dependabot Auto-Merge

on:
  pull_request:
    branches: [main, develop]

permissions:
  security-events: read
  pull-requests: write
  contents: write

jobs:
  vuln-gate:
    if: ${{ github.actor == 'dependabot[bot]' }}
    uses: simplify9/.github/.github/workflows/critical-vuln-gate.yml@main
    secrets:
      github-token: ${{ secrets.GITHUB_TOKEN }}

  auto-merge:
    needs: vuln-gate
    if: ${{ github.actor == 'dependabot[bot]' }}
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - name: Fetch Dependabot metadata
        id: metadata
        uses: dependabot/fetch-metadata@v2
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}

      - name: Enable auto-merge for eligible patch bumps
        if: |
          steps.metadata.outputs.update-type == 'version-update:semver-patch' &&
          contains(fromJSON('["npm_and_yarn", "nuget", "pub", "bundler", "github_actions"]'), steps.metadata.outputs.package-ecosystem)
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          PR_URL: ${{ github.event.pull_request.html_url }}
        run: |
          set -euo pipefail
          echo "::notice title=🤖 [AUTO-MERGE] Enabling auto-merge::${PR_URL} — patch-level ${{ steps.metadata.outputs.package-ecosystem }} bump, vuln gate passed"
          gh pr merge --auto --squash "$PR_URL"
```

- [ ] **Step 2: Create the properties sidecar**

```json
{
    "name": "Dependabot Auto-Merge",
    "description": "Auto-merges Dependabot PRs for patch-level semver bumps in npm/nuget/pub/bundler/github-actions (never docker, never minor/major), gated on the repository having no open critical Dependabot alert.",
    "iconName": "octicon-git-merge",
    "categories": [
        "Security",
        "Automation"
    ]
}
```

- [ ] **Step 3: Pin the new action version in AGENTS.md**

Add a row to the Pinned Action Versions table (after the `apple-actions/upload-testflight-build` row):

```markdown
| `dependabot/fetch-metadata` | `@v2` | Reads Dependabot PR metadata (`update-type`, `package-ecosystem`) for the auto-merge template |
```

- [ ] **Step 4: Commit**

```bash
git add workflow-templates/dependabot-auto-merge.yml workflow-templates/dependabot-auto-merge.properties.json AGENTS.md
git commit -m "feat: add dependabot-auto-merge workflow-template"
```

- [ ] **Step 5: Verify**

No local runner. Real validation: Task 28's pilot repos — open (or wait for) a real Dependabot patch-bump PR in a pilot repo with this template installed, confirm `vuln-gate` runs, then `auto-merge` runs and either enables auto-merge (patch + eligible ecosystem) or is skipped (any other bump type/ecosystem) — check both branches of the condition manually with two different pilot PRs if possible.

---

### Task 5: Build-time gate in `reusable-service-cicd.yml`

**Files:**
- Modify: `.github/workflows/reusable-service-cicd.yml` (jobs block starts at line 490: `version` at 491-538, `nuget` at 539-585, `ci` at 586-1123, `deploy` at 1124-1472 with `needs: [version, ci]`, `tag` at 1473+ with `needs: [version, nuget, ci]`)

**Interfaces:**
- Consumes: `simplify9/.github/.github/actions/check-critical-vulns@main` (Task 1); `needs.version.outputs.is-release` (existing output, confirmed at line 499).
- Produces: new job id **`critical-vuln-gate`**, needed by `deploy` (so a critical alert blocks the deploy step but not `nuget`/`ci`/building — the "block shipping, not building" semantic used consistently across every pipeline in this plan).

- [ ] **Step 1: Add the new job** — insert immediately after the `version` job (before `nuget` at line 539):

```yaml
  critical-vuln-gate:
    needs: version
    if: ${{ needs.version.outputs.is-release == 'true' }}
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      security-events: read
    steps:
      - name: Check for open critical Dependabot alerts
        uses: simplify9/.github/.github/actions/check-critical-vulns@main
        with:
          github-token: ${{ secrets.github-token }}
          repository: ${{ github.repository }}

      - name: Write job summary
        if: always()
        uses: simplify9/.github/.github/actions/write-job-summary@main
        with:
          icon: '🔒'
          title: Critical Dependabot Vulnerability Gate
          status: ${{ job.status }}
```

- [ ] **Step 2: Add the new job to `deploy`'s `needs:`** — change (around line 1127):

```yaml
    needs: [version, ci]
```

to:

```yaml
    needs: [version, ci, critical-vuln-gate]
```

- [ ] **Step 3: Confirm `github-token` secret already exists on this workflow** — this workflow already declares and uses a `github-token` secret (used by `tag-github-origin` per the existing `tag` job); no new secret needs to be added to `on.workflow_call.secrets:`. Grep to confirm before moving on:

```bash
grep -n "github-token" .github/workflows/reusable-service-cicd.yml
```

Expected: existing `secrets: github-token:` declaration plus its use in the `tag` job.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/reusable-service-cicd.yml
git commit -m "feat: add critical-vuln build-time gate to reusable-service-cicd"
```

- [ ] **Step 5: Verify**

No local runner (per CLAUDE.md, this repo's tests are validated by calling from a branch in a consumer repo). Point a consumer repo's `service-cicd` caller at this branch (`uses: simplify9/.github/.github/workflows/reusable-service-cicd.yml@<branch>`), push to its release branch, and confirm the Actions run shows a `critical-vuln-gate` job that runs before `deploy` and blocks it if the repo has an open critical alert.

---

### Task 6: Build-time gate in `generic-chart-helm.yml`

**Files:**
- Modify: `.github/workflows/generic-chart-helm.yml` (jobs: `version` at 239-294 with `is-release` output at line 248, `nuget` at 295-389, `build` at 390-455 with `needs: [version, nuget]`, `deploy` at 456-639 with `needs: [version, build]`, `tag` at 640+ with `needs: [version, nuget, build, deploy]`)

**Interfaces:**
- Consumes: `check-critical-vulns` (Task 1), `needs.version.outputs.is-release`.
- Produces: new job id `critical-vuln-gate`, needed by `deploy`.

- [ ] **Step 1: Add the new job** — insert after the `version` job (before `nuget` at line 295):

```yaml
  critical-vuln-gate:
    needs: version
    if: ${{ needs.version.outputs.is-release == 'true' }}
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      security-events: read
    steps:
      - name: Check for open critical Dependabot alerts
        uses: simplify9/.github/.github/actions/check-critical-vulns@main
        with:
          github-token: ${{ secrets.github-token }}
          repository: ${{ github.repository }}

      - name: Write job summary
        if: always()
        uses: simplify9/.github/.github/actions/write-job-summary@main
        with:
          icon: '🔒'
          title: Critical Dependabot Vulnerability Gate
          status: ${{ job.status }}
```

- [ ] **Step 2: Update `deploy`'s `needs:`** (around line 460), change:

```yaml
    needs: [version, build]
```

to:

```yaml
    needs: [version, build, critical-vuln-gate]
```

- [ ] **Step 3: Confirm the `github-token` secret exists** on this workflow (used already by its `tag` job):

```bash
grep -n "github-token" .github/workflows/generic-chart-helm.yml
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/generic-chart-helm.yml
git commit -m "feat: add critical-vuln build-time gate to generic-chart-helm"
```

- [ ] **Step 5: Verify**

No local runner. Same consumer-repo-branch approach as Task 5, using a repo whose caller template is `generic-chart-cicd`.

---

### Task 7: Build-time gate in `generic-gateway-helm-template.yml`

**Files:**
- Modify: `.github/workflows/generic-gateway-helm-template.yml` (jobs: `version` at 446-496 with `is-release` at 455, `nuget` at 497-591, `build` at 592-654 with `needs: [version, nuget]`, `deploy` at 655-814 with `needs: [version, build]`, `tag` at 815+ with `needs: [version, nuget, build, deploy]`)

**Interfaces:**
- Consumes: `check-critical-vulns` (Task 1), `needs.version.outputs.is-release`.
- Produces: new job id `critical-vuln-gate`, needed by `deploy`.

- [ ] **Step 1: Add the new job** — insert after `version` (before `nuget` at line 497):

```yaml
  critical-vuln-gate:
    needs: version
    if: ${{ needs.version.outputs.is-release == 'true' }}
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      security-events: read
    steps:
      - name: Check for open critical Dependabot alerts
        uses: simplify9/.github/.github/actions/check-critical-vulns@main
        with:
          github-token: ${{ secrets.github-token }}
          repository: ${{ github.repository }}

      - name: Write job summary
        if: always()
        uses: simplify9/.github/.github/actions/write-job-summary@main
        with:
          icon: '🔒'
          title: Critical Dependabot Vulnerability Gate
          status: ${{ job.status }}
```

- [ ] **Step 2: Update `deploy`'s `needs:`** (around line 659), change:

```yaml
    needs: [version, build]
```

to:

```yaml
    needs: [version, build, critical-vuln-gate]
```

- [ ] **Step 3: Confirm the `github-token` secret exists**:

```bash
grep -n "github-token" .github/workflows/generic-gateway-helm-template.yml
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/generic-gateway-helm-template.yml
git commit -m "feat: add critical-vuln build-time gate to generic-gateway-helm-template"
```

- [ ] **Step 5: Verify**

No local runner. Consumer-repo-branch validation as in Task 5, using a repo on the gateway-first template.

---

### Task 8: Build-time gate in `helm-deploy-values.yml` (no `is-release` — inline ref check)

**Files:**
- Modify: `.github/workflows/helm-deploy-values.yml` (single `deploy` job at line ~192, `environment: ${{ inputs.gh-environment }}`, top-level `permissions: contents: read` at line 188)

**Interfaces:**
- Consumes: `check-critical-vulns` (Task 1). No `version` job exists in this file — per the Deviations section above, gates on `github.ref_name == github.event.repository.default_branch` directly instead.
- Produces: new job id `critical-vuln-gate`, needed by `deploy`.

- [ ] **Step 1: Add the new job** — insert immediately before `jobs: deploy:` (i.e., right after the `permissions:` block at line 189):

```yaml
jobs:
  critical-vuln-gate:
    if: ${{ github.ref_name == github.event.repository.default_branch }}
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      security-events: read
    steps:
      - name: Check for open critical Dependabot alerts
        uses: simplify9/.github/.github/actions/check-critical-vulns@main
        with:
          github-token: ${{ secrets.github-token }}
          repository: ${{ github.repository }}

      - name: Write job summary
        if: always()
        uses: simplify9/.github/.github/actions/write-job-summary@main
        with:
          icon: '🔒'
          title: Critical Dependabot Vulnerability Gate
          status: ${{ job.status }}

  deploy:
    needs: critical-vuln-gate
```

(The existing `deploy:` job's own body — `runs-on`, `timeout-minutes`, `environment`, `concurrency`, `steps:` — is unchanged; only the `needs: critical-vuln-gate` line is newly inserted directly under `deploy:`.)

- [ ] **Step 2: Add a `github-token` secret to this workflow's `on.workflow_call.secrets:` block** — this workflow currently has no `tag`/versioning job, so it has never needed one. Add, in the `secrets:` block (near line 35+ where `on: workflow_call:` is declared):

```yaml
      github-token:
        description: 'Token with security-events:read on the calling repository. Pass secrets.GITHUB_TOKEN.'
        required: true
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/helm-deploy-values.yml
git commit -m "feat: add critical-vuln build-time gate to helm-deploy-values"
```

- [ ] **Step 4: Verify**

No local runner. Consumer-repo-branch validation — point a caller using `helm-deploy-values.yml` at this branch, run it once with the caller's ref matching the target repo's default branch (gate should run) and once from a non-default branch (gate should be skipped, `deploy` proceeds straight through).

---

### Task 9: Build-time gate in `next-cloudflare-worker.yaml` (no `is-release` — inline ref check)

**Files:**
- Modify: `.github/workflows/next-cloudflare-worker.yaml` (single `deploy` job at line 109, job-level `permissions: contents: read` at line ~118)

**Interfaces:**
- Consumes: `check-critical-vulns` (Task 1). Same inline-ref-check deviation as Task 8.
- Produces: new job id `critical-vuln-gate`, needed by `deploy`.

- [ ] **Step 1: Add the new job** — insert immediately before `jobs: deploy:` (line 108):

```yaml
jobs:
  critical-vuln-gate:
    if: ${{ github.ref_name == github.event.repository.default_branch }}
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      security-events: read
    steps:
      - name: Check for open critical Dependabot alerts
        uses: simplify9/.github/.github/actions/check-critical-vulns@main
        with:
          github-token: ${{ secrets.github-token }}
          repository: ${{ github.repository }}

      - name: Write job summary
        if: always()
        uses: simplify9/.github/.github/actions/write-job-summary@main
        with:
          icon: '🔒'
          title: Critical Dependabot Vulnerability Gate
          status: ${{ job.status }}

  deploy:
    needs: critical-vuln-gate
```

(All existing `deploy:` job content — `name: Deploy ${{ inputs.environment }}`, `runs-on`, `timeout-minutes`, `concurrency`, `permissions`, `steps:` — stays as-is; only `needs: critical-vuln-gate` is newly added directly under `deploy:`.)

- [ ] **Step 2: Add a `github-token` secret** to this workflow's `on.workflow_call.secrets:` block (alongside the existing `cloudflare_api_token`/`cloudflare_account_id`):

```yaml
      github-token:
        description: 'Token with security-events:read on the calling repository. Pass secrets.GITHUB_TOKEN.'
        required: true
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/next-cloudflare-worker.yaml
git commit -m "feat: add critical-vuln build-time gate to next-cloudflare-worker"
```

- [ ] **Step 4: Verify**

No local runner. Consumer-repo-branch validation as Task 8, using a repo on the `next-cloudflare` template.

---

### Task 10: Build-time gate in `vite-cloudflare-worker.yml` (no `is-release` — inline ref check)

**Files:**
- Modify: `.github/workflows/vite-cloudflare-worker.yml` (single `deploy` job at line 108, job-level `permissions: contents: read` at line ~117)

**Interfaces:**
- Consumes: `check-critical-vulns` (Task 1). Same inline-ref-check deviation as Tasks 8-9.
- Produces: new job id `critical-vuln-gate`, needed by `deploy`.

- [ ] **Step 1: Add the new job** — insert immediately before `jobs: deploy:` (line 107):

```yaml
jobs:
  critical-vuln-gate:
    if: ${{ github.ref_name == github.event.repository.default_branch }}
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      security-events: read
    steps:
      - name: Check for open critical Dependabot alerts
        uses: simplify9/.github/.github/actions/check-critical-vulns@main
        with:
          github-token: ${{ secrets.github-token }}
          repository: ${{ github.repository }}

      - name: Write job summary
        if: always()
        uses: simplify9/.github/.github/actions/write-job-summary@main
        with:
          icon: '🔒'
          title: Critical Dependabot Vulnerability Gate
          status: ${{ job.status }}

  deploy:
    needs: critical-vuln-gate
```

- [ ] **Step 2: Add a `github-token` secret** to this workflow's `on.workflow_call.secrets:` block (alongside `cloudflare_api_token`/`cloudflare_account_id`):

```yaml
      github-token:
        description: 'Token with security-events:read on the calling repository. Pass secrets.GITHUB_TOKEN.'
        required: true
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/vite-cloudflare-worker.yml
git commit -m "feat: add critical-vuln build-time gate to vite-cloudflare-worker"
```

- [ ] **Step 4: Verify**

No local runner. Consumer-repo-branch validation as Task 8, using a repo on the `vite-cloudflare` template.

---

### Task 11: Build-time gate in `ios-build.yml` (mobile — gates `release_with_environment`)

**Files:**
- Modify: `.github/workflows/ios-build.yml` (`build` job at line 296, `release_with_environment` job at line 1014 with `needs: build` at 1020 and `if: inputs.release-environment != '' && !inputs.disable-release` at 1021)

**Interfaces:**
- Consumes: `check-critical-vulns` (Task 1). No `is-release` concept here — per the spec's mobile-pipeline design, the gate blocks *shipping* (the TestFlight upload in `release_with_environment`) not *building* (compiling/archiving in `build`).
- Produces: new job id `critical-vuln-gate` (independent of `build` — it can run in parallel), added to `release_with_environment`'s `needs:` list.

- [ ] **Step 1: Add the new job** — insert immediately before `jobs: build:` (line 295/296):

```yaml
  critical-vuln-gate:
    if: ${{ inputs.release-environment != '' && !inputs.disable-release }}
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      security-events: read
    steps:
      - name: Check for open critical Dependabot alerts
        uses: simplify9/.github/.github/actions/check-critical-vulns@main
        with:
          github-token: ${{ secrets.github-token }}
          repository: ${{ github.repository }}

      - name: Write job summary
        if: always()
        uses: simplify9/.github/.github/actions/write-job-summary@main
        with:
          icon: '🔒'
          title: Critical Dependabot Vulnerability Gate
          status: ${{ job.status }}
```

- [ ] **Step 2: Update `release_with_environment`'s `needs:`** (line 1020), change:

```yaml
    needs: build
```

to:

```yaml
    needs: [build, critical-vuln-gate]
```

(Its existing `if:` condition at line 1021 is unchanged — both the gate and the release job share the same `release-environment`/`disable-release` condition, so the gate never runs, and never blocks anything, for a plain non-release build.)

- [ ] **Step 3: Add a `github-token` secret** to this workflow's `on.workflow_call.secrets:` block:

```yaml
      github-token:
        description: 'Token with security-events:read on the calling repository. Pass secrets.GITHUB_TOKEN.'
        required: true
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ios-build.yml
git commit -m "feat: add critical-vuln build-time gate to ios-build release job"
```

- [ ] **Step 5: Verify**

No local runner. Consumer-repo-branch validation — trigger the `ios-app` template's `workflow_dispatch` with a `release-environment` set, on this branch, and confirm `critical-vuln-gate` runs alongside `build` and blocks `release_with_environment` if the repo has an open critical alert.

---

### Task 12: Build-time gate in `android-build.yml`

**Files:**
- Modify: `.github/workflows/android-build.yml` (`build` job at line 239, `release_with_environment` job at line 693 with `needs: build` at 696, `if:` at 698)

**Interfaces:**
- Consumes: `check-critical-vulns` (Task 1). Same shape as Task 11.
- Produces: new job id `critical-vuln-gate`, added to `release_with_environment`'s `needs:`.

- [ ] **Step 1: Add the new job** — insert immediately before `jobs: build:` (line 238/239):

```yaml
  critical-vuln-gate:
    if: ${{ inputs.release-environment != '' && !inputs.disable-release }}
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      security-events: read
    steps:
      - name: Check for open critical Dependabot alerts
        uses: simplify9/.github/.github/actions/check-critical-vulns@main
        with:
          github-token: ${{ secrets.github-token }}
          repository: ${{ github.repository }}

      - name: Write job summary
        if: always()
        uses: simplify9/.github/.github/actions/write-job-summary@main
        with:
          icon: '🔒'
          title: Critical Dependabot Vulnerability Gate
          status: ${{ job.status }}
```

- [ ] **Step 2: Update `release_with_environment`'s `needs:`** (line 696), change `needs: build` to `needs: [build, critical-vuln-gate]`.

- [ ] **Step 3: Add a `github-token` secret** to this workflow's `on.workflow_call.secrets:` block (same shape as Task 11 Step 3).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/android-build.yml
git commit -m "feat: add critical-vuln build-time gate to android-build release job"
```

- [ ] **Step 5: Verify**

No local runner. Consumer-repo-branch validation as Task 11, using the `android-app` template.

---

### Task 13: Build-time gate in `flutter-ios-build.yml`

**Files:**
- Modify: `.github/workflows/flutter-ios-build.yml` (`build` job at line 189, `release_with_environment` job at line 581 with `needs: build` at 583, `if:` at 584)

**Interfaces:**
- Consumes: `check-critical-vulns` (Task 1). Same shape as Task 11.
- Produces: new job id `critical-vuln-gate`, added to `release_with_environment`'s `needs:`.

- [ ] **Step 1: Add the new job** — insert immediately before `jobs: build:` (line 188/189):

```yaml
  critical-vuln-gate:
    if: ${{ inputs.release-environment != '' && !inputs.disable-release }}
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      security-events: read
    steps:
      - name: Check for open critical Dependabot alerts
        uses: simplify9/.github/.github/actions/check-critical-vulns@main
        with:
          github-token: ${{ secrets.github-token }}
          repository: ${{ github.repository }}

      - name: Write job summary
        if: always()
        uses: simplify9/.github/.github/actions/write-job-summary@main
        with:
          icon: '🔒'
          title: Critical Dependabot Vulnerability Gate
          status: ${{ job.status }}
```

- [ ] **Step 2: Update `release_with_environment`'s `needs:`** (line 583), change `needs: build` to `needs: [build, critical-vuln-gate]`.

- [ ] **Step 3: Add a `github-token` secret** to this workflow's `on.workflow_call.secrets:` block.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/flutter-ios-build.yml
git commit -m "feat: add critical-vuln build-time gate to flutter-ios-build release job"
```

- [ ] **Step 5: Verify**

No local runner. Consumer-repo-branch validation as Task 11, using a Flutter iOS caller.

---

### Task 14: Build-time gate in `flutter-android-build.yml`

**Files:**
- Modify: `.github/workflows/flutter-android-build.yml` (`build` job at line 199, `release_with_environment` job at line 578 with `needs: build` at 580, `if:` at 581)

**Interfaces:**
- Consumes: `check-critical-vulns` (Task 1). Same shape as Task 11.
- Produces: new job id `critical-vuln-gate`, added to `release_with_environment`'s `needs:`.

- [ ] **Step 1: Add the new job** — insert immediately before `jobs: build:` (line 198/199):

```yaml
  critical-vuln-gate:
    if: ${{ inputs.release-environment != '' && !inputs.disable-release }}
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      security-events: read
    steps:
      - name: Check for open critical Dependabot alerts
        uses: simplify9/.github/.github/actions/check-critical-vulns@main
        with:
          github-token: ${{ secrets.github-token }}
          repository: ${{ github.repository }}

      - name: Write job summary
        if: always()
        uses: simplify9/.github/.github/actions/write-job-summary@main
        with:
          icon: '🔒'
          title: Critical Dependabot Vulnerability Gate
          status: ${{ job.status }}
```

- [ ] **Step 2: Update `release_with_environment`'s `needs:`** (line 580), change `needs: build` to `needs: [build, critical-vuln-gate]`.

- [ ] **Step 3: Add a `github-token` secret** to this workflow's `on.workflow_call.secrets:` block.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/flutter-android-build.yml
git commit -m "feat: add critical-vuln build-time gate to flutter-android-build release job"
```

- [ ] **Step 5: Verify**

No local runner. Consumer-repo-branch validation as Task 11, using a Flutter Android caller.

---

### Task 15: `nuget-api.yml` dependabot template

**Files:**
- Create: `dependabot-templates/nuget-api.yml`

**Interfaces:**
- Consumes: nothing (pure static template — the rollout script fills in `{{TARGET_BRANCH}}` and conditionally strips the `docker` block).
- Produces: template consumed by Task 23's rollout script. Placeholder token: `{{TARGET_BRANCH}}` — the rollout script's templating step (Task 23) does a literal string replace of this token before committing the file into each repo.

- [ ] **Step 1: Create the template**

```yaml
# Dependabot config for .NET / NuGet API repos.
# {{TARGET_BRANCH}} is replaced by the rollout script with `develop` (if the
# repo has that branch) or the repo's actual default branch otherwise.
version: 2
updates:
  - package-ecosystem: "nuget"
    directory: "/"
    target-branch: "{{TARGET_BRANCH}}"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "06:00"
      timezone: "UTC"
    open-pull-requests-limit: 10
    groups:
      nuget-minor-patch:
        update-types: ["minor", "patch"]
    labels:
      - "dependencies"
      - "nuget"

  - package-ecosystem: "docker"
    directory: "/"
    target-branch: "{{TARGET_BRANCH}}"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "06:00"
      timezone: "UTC"
    open-pull-requests-limit: 5
    labels:
      - "dependencies"
      - "docker"

  - package-ecosystem: "github-actions"
    directory: "/"
    target-branch: "{{TARGET_BRANCH}}"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "06:00"
      timezone: "UTC"
    open-pull-requests-limit: 5
    groups:
      actions-minor-patch:
        update-types: ["minor", "patch"]
    labels:
      - "dependencies"
      - "github-actions"
```

- [ ] **Step 2: Commit**

```bash
git add dependabot-templates/nuget-api.yml
git commit -m "feat: add nuget-api dependabot template"
```

- [ ] **Step 3: Verify**

Run `python3 -c "import yaml, sys; yaml.safe_load(open('dependabot-templates/nuget-api.yml'))"` (or `yamllint`) to confirm it parses as valid YAML. There is no way to validate Dependabot's own schema locally beyond this — real validation is Dependabot actually picking it up after Task 23 commits a filled-in copy to a real repo.

---

### Task 16: `npm-frontend.yml` dependabot template

**Files:**
- Create: `dependabot-templates/npm-frontend.yml`

**Interfaces:**
- Consumes: nothing. Placeholder token: `{{TARGET_BRANCH}}` (Task 23 fills in, and strips the `docker` block for repos without a Dockerfile).
- Produces: template consumed by Task 23. Covers React/Vite/Next/Vue/Strapi repos — ecosystem-driven, not framework-driven, per the spec.

- [ ] **Step 1: Create the template**

```yaml
# Dependabot config for npm-based frontend/CMS repos (React/Vite/Next/Vue/Strapi).
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    target-branch: "{{TARGET_BRANCH}}"
    schedule:
      interval: "weekly"
      day: "tuesday"
      time: "06:00"
      timezone: "UTC"
    open-pull-requests-limit: 10
    groups:
      npm-minor-patch:
        update-types: ["minor", "patch"]
    labels:
      - "dependencies"
      - "npm"

  - package-ecosystem: "docker"
    directory: "/"
    target-branch: "{{TARGET_BRANCH}}"
    schedule:
      interval: "weekly"
      day: "tuesday"
      time: "06:00"
      timezone: "UTC"
    open-pull-requests-limit: 5
    labels:
      - "dependencies"
      - "docker"

  - package-ecosystem: "github-actions"
    directory: "/"
    target-branch: "{{TARGET_BRANCH}}"
    schedule:
      interval: "weekly"
      day: "tuesday"
      time: "06:00"
      timezone: "UTC"
    open-pull-requests-limit: 5
    groups:
      actions-minor-patch:
        update-types: ["minor", "patch"]
    labels:
      - "dependencies"
      - "github-actions"
```

- [ ] **Step 2: Commit**

```bash
git add dependabot-templates/npm-frontend.yml
git commit -m "feat: add npm-frontend dependabot template"
```

- [ ] **Step 3: Verify**

Same YAML-parse check as Task 15, Step 3.

---

### Task 17: `react-native-mobile.yml` dependabot template

**Files:**
- Create: `dependabot-templates/react-native-mobile.yml`

**Interfaces:**
- Consumes: nothing. Placeholder token: `{{TARGET_BRANCH}}`.
- Produces: template consumed by Task 23. No `docker` ecosystem (mobile apps don't ship a Dockerfile); includes `bundler` for the fastlane `Gemfile`.

- [ ] **Step 1: Create the template**

```yaml
# Dependabot config for React Native mobile repos (npm + fastlane Gemfile).
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    target-branch: "{{TARGET_BRANCH}}"
    schedule:
      interval: "weekly"
      day: "wednesday"
      time: "06:00"
      timezone: "UTC"
    open-pull-requests-limit: 10
    groups:
      npm-minor-patch:
        update-types: ["minor", "patch"]
    labels:
      - "dependencies"
      - "npm"

  - package-ecosystem: "bundler"
    directory: "/"
    target-branch: "{{TARGET_BRANCH}}"
    schedule:
      interval: "weekly"
      day: "wednesday"
      time: "06:00"
      timezone: "UTC"
    open-pull-requests-limit: 5
    labels:
      - "dependencies"
      - "fastlane"

  - package-ecosystem: "github-actions"
    directory: "/"
    target-branch: "{{TARGET_BRANCH}}"
    schedule:
      interval: "weekly"
      day: "wednesday"
      time: "06:00"
      timezone: "UTC"
    open-pull-requests-limit: 5
    groups:
      actions-minor-patch:
        update-types: ["minor", "patch"]
    labels:
      - "dependencies"
      - "github-actions"
```

- [ ] **Step 2: Commit**

```bash
git add dependabot-templates/react-native-mobile.yml
git commit -m "feat: add react-native-mobile dependabot template"
```

- [ ] **Step 3: Verify**

Same YAML-parse check as Task 15, Step 3.

---

### Task 18: `flutter-mobile.yml` dependabot template

**Files:**
- Create: `dependabot-templates/flutter-mobile.yml`

**Interfaces:**
- Consumes: nothing. Placeholder token: `{{TARGET_BRANCH}}`.
- Produces: template consumed by Task 23. Ecosystems: `pub`, `github-actions` only.

- [ ] **Step 1: Create the template**

```yaml
# Dependabot config for Flutter mobile repos.
version: 2
updates:
  - package-ecosystem: "pub"
    directory: "/"
    target-branch: "{{TARGET_BRANCH}}"
    schedule:
      interval: "weekly"
      day: "wednesday"
      time: "06:00"
      timezone: "UTC"
    open-pull-requests-limit: 10
    groups:
      pub-minor-patch:
        update-types: ["minor", "patch"]
    labels:
      - "dependencies"
      - "pub"

  - package-ecosystem: "github-actions"
    directory: "/"
    target-branch: "{{TARGET_BRANCH}}"
    schedule:
      interval: "weekly"
      day: "wednesday"
      time: "06:00"
      timezone: "UTC"
    open-pull-requests-limit: 5
    groups:
      actions-minor-patch:
        update-types: ["minor", "patch"]
    labels:
      - "dependencies"
      - "github-actions"
```

- [ ] **Step 2: Commit**

```bash
git add dependabot-templates/flutter-mobile.yml
git commit -m "feat: add flutter-mobile dependabot template"
```

- [ ] **Step 3: Verify**

Same YAML-parse check as Task 15, Step 3.

---

### Task 19: `infra-actions-only.yml` dependabot template

**Files:**
- Create: `dependabot-templates/infra-actions-only.yml`

**Interfaces:**
- Consumes: nothing. Placeholder token: `{{TARGET_BRANCH}}`; the rollout script conditionally includes the `docker` block only when a Dockerfile is found.
- Produces: template consumed by Task 23, for Helm-chart/infra repos and any repo with no application package manifest.

- [ ] **Step 1: Create the template**

```yaml
# Dependabot config for infra/Helm-chart repos with no application package manifest.
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    target-branch: "{{TARGET_BRANCH}}"
    schedule:
      interval: "weekly"
      day: "thursday"
      time: "06:00"
      timezone: "UTC"
    open-pull-requests-limit: 5
    groups:
      actions-minor-patch:
        update-types: ["minor", "patch"]
    labels:
      - "dependencies"
      - "github-actions"

  - package-ecosystem: "docker"
    directory: "/"
    target-branch: "{{TARGET_BRANCH}}"
    schedule:
      interval: "weekly"
      day: "thursday"
      time: "06:00"
      timezone: "UTC"
    open-pull-requests-limit: 5
    labels:
      - "dependencies"
      - "docker"
```

- [ ] **Step 2: Commit**

```bash
git add dependabot-templates/infra-actions-only.yml
git commit -m "feat: add infra-actions-only dependabot template"
```

- [ ] **Step 3: Verify**

Same YAML-parse check as Task 15, Step 3.

---

### Task 20: `github-repo.yml` dependabot template (for the `.github` repo itself)

**Files:**
- Create: `dependabot-templates/github-repo.yml`

**Interfaces:**
- Consumes: nothing.
- Produces: template applied directly (not via the rollout script — this repo isn't one of the 232 external targets) in Task 21 as this repo's own `.github/dependabot.yml`.

- [ ] **Step 1: Create the template**

```yaml
# Dependabot config for this .github repo itself — github-actions only, no
# application code lives here. Target branch is main (this repo has no
# develop branch).
version: 2
updates:
  - package-ecosystem: "github-actions"
    directories:
      - "/"
      - "/.github/actions/*"
    target-branch: "main"
    schedule:
      interval: "weekly"
      day: "friday"
      time: "06:00"
      timezone: "UTC"
    open-pull-requests-limit: 5
    groups:
      actions-minor-patch:
        update-types: ["minor", "patch"]
    labels:
      - "dependencies"
      - "github-actions"
```

- [ ] **Step 2: Commit**

```bash
git add dependabot-templates/github-repo.yml
git commit -m "feat: add github-repo dependabot template"
```

- [ ] **Step 3: Verify**

Same YAML-parse check as Task 15, Step 3.

---

### Task 21: Onboard this `.github` repo onto Dependabot

**Files:**
- Create: `.github/dependabot.yml` (copy of `dependabot-templates/github-repo.yml` from Task 20 — this repo needs onboarding too, not just the 232 external ones)

**Interfaces:**
- Consumes: `dependabot-templates/github-repo.yml` (Task 20).
- Produces: this repo's live Dependabot config.

- [ ] **Step 1: Copy the template to the real location**

```bash
cp dependabot-templates/github-repo.yml .github/dependabot.yml
```

- [ ] **Step 2: Commit**

```bash
git add .github/dependabot.yml
git commit -m "chore: onboard this repo onto Dependabot"
```

- [ ] **Step 3: Verify**

Push this commit (or merge to `main`) and check the repo's Insights → Dependency graph → Dependabot tab within a few minutes for the config to register with no parse errors. This is the one task in this plan where GitHub itself validates the file syntactically — an invalid config shows an error banner there.

---

### Task 22: Update `README.md` and `AGENTS.md`

**Files:**
- Modify: `README.md` — add the two new workflow-templates (`critical-vuln-check`, `dependabot-auto-merge`) to whatever template-listing section already exists, following the exact structure used for the existing templates.
- Modify: `AGENTS.md` — add `check-critical-vulns` to the Composite Action Reference section (### Shared, alongside `write-job-summary`); add `critical-vuln-gate.yml` to the Workflow Reference table (new "### Security" subsection); add both new entries to the Workflow Templates table; note the `github-token` secret addition on the three previously-secretless deploy-only workflows (`helm-deploy-values.yml`, `next-cloudflare-worker.yaml`, `vite-cloudflare-worker.yml`) in their respective table rows if those rows list secrets.

**Interfaces:**
- Consumes: nothing new — this is a documentation pass over everything Tasks 1-20 added.
- Produces: docs that satisfy CLAUDE.md's "keep README.md accurate" mandate and AGENTS.md's "Keeping Documentation Up to Date" checklist.

- [ ] **Step 1: Add to AGENTS.md's Composite Action Reference, under `### Shared`**

```markdown
- `check-critical-vulns` — Fails if the repository has any open critical-severity Dependabot alert (queries `GET /repos/{owner}/{repo}/dependabot/alerts?state=open&severity=critical`). Inputs: `github-token`, `repository` (defaults to the calling repo). Output: `critical-count`. Reused at three call sites: the `critical-vuln-gate` reusable workflow (PR-time check + auto-merge gate) and the build-time gate embedded in every deploy/build reusable workflow.
```

- [ ] **Step 2: Add a new subsection to AGENTS.md's Workflow Reference, after "### Mobile"**

```markdown
### Security

| Workflow | Purpose | Key inputs |
|---|---|---|
| `critical-vuln-gate.yml` | Thin `workflow_call` wrapper around `check-critical-vulns` — fails if the calling repo has an open critical-severity Dependabot alert. Called from the `critical-vuln-check` and `dependabot-auto-merge` workflow-templates, and embedded as an early job in every deploy/build reusable workflow. | none (secret: `github-token`) |
```

- [ ] **Step 3: Add both new templates to AGENTS.md's Workflow Templates table**

```markdown
| `critical-vuln-check` | `critical-vuln-gate.yml` | `pull_request` on `main`, `develop` |
| `dependabot-auto-merge` | `critical-vuln-gate.yml` (+ inline auto-merge job) | `pull_request` on `main`, `develop` |
```

- [ ] **Step 4: Read README.md's current template-listing section to match its exact format, then mirror Steps 2-3's additions there**

```bash
grep -n "workflow-templates\|Templates" README.md | head -20
```

Add the same two rows (adapted to whatever caller-facing phrasing README.md already uses for the other templates — copy the tone/column structure of the nearest existing template entry rather than reusing AGENTS.md's wording verbatim).

- [ ] **Step 5: Commit**

```bash
git add README.md AGENTS.md
git commit -m "docs: document critical-vuln gate and new workflow-templates"
```

- [ ] **Step 6: Verify**

Re-read both files end to end once more and confirm every new file from Tasks 1-20 is mentioned somewhere (composite action, reusable workflow, 2 templates, 6 dependabot-templates don't need an AGENTS.md entry since they're not `.github/actions`/`.github/workflows` — but do add one sentence to CLAUDE.md's "Current inventory" section noting the new `dependabot-templates/` folder exists, since that section explicitly lists "11 reusable workflows / 18 composite actions / 8 starter templates" and those counts are now stale — bump them to 12 reusable workflows, 19 composite actions, 10 starter templates, and mention `dependabot-templates/` as a new fourth content category).

---

## PHASE BOUNDARY — merge checkpoint (confirmed with Musa on 2026-07-12)

Tasks 1-22 (Phase A) and Tasks 23-29 (Phase B) ship as **two separate PRs**, not one. Reason: every consumer repo in the org references `simplify9/.github/...@main`, so Task 28's pilot (and Task 29's full rollout) can only validate against the *real*, live `@main` versions of the new composite action / reusable workflow / workflow-templates — not a not-yet-merged branch. Sequencing:

1. Execute Tasks 1-22 in this worktree/branch. Full task-by-task review + final whole-branch review + `finishing-a-development-branch` (merge to `main`) happens once Task 22 is done — treat that as this plan's first shipped unit.
2. Only after Phase A is confirmed live on `main` (spot check: `curl -s https://raw.githubusercontent.com/simplify9/.github/main/workflow-templates/critical-vuln-check.yml` returns real content, not 404), start Phase B (Tasks 23-29), either continuing in a fresh worktree off the now-updated `main` or reusing this one after a rebase. Task 28's pilot step 1 (`curl .../main/workflow-templates/critical-vuln-check.yml`) depends on this — do not run Task 28 before confirming Phase A is live.

---

### Task 23: Rollout script — repo enumeration + live template selection

**Files:**
- Create: `scripts/dependabot-rollout/__init__.py` (empty, makes this a package for internal imports)
- Create: `scripts/dependabot-rollout/inspect_repo.py`
- Create: `scripts/dependabot-rollout/rollout.py` (entry point, built up across Tasks 23-27)
- Create: `scripts/dependabot-rollout/README.md` (short usage note — this is ops tooling, not covered by the main repo README)

**Interfaces:**
- Consumes: `gh` CLI (subprocess), assumes caller is already authenticated (`gh auth status`).
- Produces: `inspect_repo.categorize(owner: str, name: str) -> str` returning one of `"nuget-api"`, `"npm-frontend"`, `"react-native-mobile"`, `"flutter-mobile"`, `"infra-actions-only"` — the exact basenames (without `.yml`) of the Task 15-19 templates. Later tasks (24-27) import this module and extend `rollout.py`.

- [ ] **Step 1: Create the package marker**

```bash
mkdir -p scripts/dependabot-rollout
touch scripts/dependabot-rollout/__init__.py
```

- [ ] **Step 2: Write `inspect_repo.py`**

```python
"""Live repo-tree inspection to pick the correct Dependabot category template.

Does NOT trust the GitHub GraphQL primaryLanguage field alone (it can't tell
a plain Node/Express API apart from a React/Vite frontend, or a Strapi CMS
from a plain npm frontend) -- it inspects the actual file tree via `gh api`.
"""
import json
import subprocess


def _gh_api(path: str) -> dict | list | None:
    """Run `gh api <path>`, return parsed JSON, or None on a 404."""
    result = subprocess.run(
        ["gh", "api", path],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        if "404" in result.stderr or "Not Found" in result.stderr:
            return None
        raise RuntimeError(f"gh api {path} failed: {result.stderr.strip()}")
    return json.loads(result.stdout)


def _file_exists(owner: str, name: str, path: str) -> bool:
    return _gh_api(f"repos/{owner}/{name}/contents/{path}") is not None


def _read_file(owner: str, name: str, path: str) -> str | None:
    """Return the decoded text content of a file, or None if it doesn't exist."""
    import base64

    data = _gh_api(f"repos/{owner}/{name}/contents/{path}")
    if data is None or "content" not in data:
        return None
    return base64.b64decode(data["content"]).decode("utf-8", errors="replace")


def categorize(owner: str, name: str) -> str:
    """Return one of: nuget-api, npm-frontend, react-native-mobile,
    flutter-mobile, infra-actions-only."""
    has_pubspec = _file_exists(owner, name, "pubspec.yaml")
    if has_pubspec:
        return "flutter-mobile"

    has_csproj_marker = _file_exists(owner, name, "global.json") or any(
        entry.get("name", "").endswith(".sln")
        for entry in (_gh_api(f"repos/{owner}/{name}/contents/") or [])
        if isinstance(entry, dict)
    )
    if has_csproj_marker:
        return "nuget-api"

    package_json = _read_file(owner, name, "package.json")
    if package_json:
        try:
            manifest = json.loads(package_json)
        except json.JSONDecodeError:
            manifest = {}
        deps = {**manifest.get("dependencies", {}), **manifest.get("devDependencies", {})}
        if "react-native" in deps or _file_exists(owner, name, "Gemfile"):
            return "react-native-mobile"
        return "npm-frontend"

    return "infra-actions-only"
```

- [ ] **Step 2b: Note the `.sln` detection caveat inline (do not silently trust it)** — GitHub's Contents API for a directory listing (`contents/`) only lists the repo root; a `.sln` nested in a subdirectory (common in this org's multi-project C# repos, e.g. `Bitween-api`) will be missed by this shallow check. Add a fallback using the Search API before falling through to `infra-actions-only`:

```python
    # Fallback: a repo-root listing might miss a nested .sln (common in this
    # org's multi-project C# repos). Use code search as a second check before
    # concluding "no C# project found".
    search_result = _gh_api(
        f"search/code?q=extension:sln+repo:{owner}/{name}"
    )
    if search_result and search_result.get("total_count", 0) > 0:
        return "nuget-api"
```

(Insert this block into `categorize()` right after the existing `has_csproj_marker` check, before falling through to the `package_json` check.)

- [ ] **Step 3: Write `rollout.py` with the `--dry-run` enumeration entry point**

```python
#!/usr/bin/env python3
"""Dependabot org-wide rollout script for simplify9.

Usage:
    python3 rollout.py --dry-run                 # print chosen template per repo, no mutation
    python3 rollout.py --dry-run --repos foo,bar  # limit to named repos
"""
import argparse
import json
import subprocess
import sys

from inspect_repo import categorize

ORG = "simplify9"


def list_active_repos() -> list[dict]:
    """Return all non-archived, non-fork repos in the org."""
    result = subprocess.run(
        [
            "gh", "api", "graphql", "--paginate",
            "-f", f"query=query($cursor: String) {{ organization(login: \"{ORG}\") "
                  "{ repositories(first: 100, after: $cursor, isFork: false) { "
                  "nodes { name isArchived defaultBranchRef { name } } "
                  "pageInfo { hasNextPage endCursor } } } }",
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    repos = []
    for line in result.stdout.strip().splitlines():
        payload = json.loads(line)
        for node in payload["data"]["organization"]["repositories"]["nodes"]:
            if not node["isArchived"]:
                repos.append({
                    "name": node["name"],
                    "default_branch": node["defaultBranchRef"]["name"],
                })
    return repos


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", required=True,
                         help="This task only supports --dry-run; mutation flags land in Tasks 25-27.")
    parser.add_argument("--repos", type=str, default="",
                         help="Comma-separated repo names to limit to (for testing).")
    args = parser.parse_args()

    repos = list_active_repos()
    if args.repos:
        wanted = set(args.repos.split(","))
        repos = [r for r in repos if r["name"] in wanted]

    for repo in repos:
        category = categorize(ORG, repo["name"])
        print(f"{repo['name']}\t{category}\tdefault_branch={repo['default_branch']}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Write the usage README**

```markdown
# Dependabot Org Rollout

One-off ops tooling to roll out `.github/dependabot.yml` across all active
`simplify9` repos. Not a maintained library — stdlib + `gh` CLI subprocess
calls only, no pip dependencies.

Requires `gh auth status` to already show a valid token with `repo`,
`read:org` scopes (branch-protection/vuln-alert endpoints in later tasks
additionally need repo-admin rights).

## Usage

    cd scripts/dependabot-rollout
    python3 rollout.py --dry-run
```

- [ ] **Step 5: Run the dry-run against a handful of known repos to sanity-check categorization**

```bash
cd scripts/dependabot-rollout
python3 rollout.py --dry-run --repos Bitween-api,Bitween-UI-1,laflef-mobile,gig-dxp-cms,infrastructure-rabbitmq
```

Expected output: one line per repo, e.g. `Bitween-api	nuget-api	default_branch=releases/r8.0`, `Bitween-UI-1	npm-frontend	default_branch=main`, `laflef-mobile	flutter-mobile	default_branch=main`, `gig-dxp-cms	npm-frontend	default_branch=main`, `infrastructure-rabbitmq	infra-actions-only	default_branch=main`. If any of these five don't match the already-known-correct category from the earlier manual audit, fix `categorize()` before proceeding — these five are a regression check, not a formality.

- [ ] **Step 6: Commit**

```bash
git add scripts/dependabot-rollout/
git commit -m "feat: add dependabot rollout script with repo enumeration and template selection"
```

---

### Task 24: Rollout script — `target-branch` resolution

**Files:**
- Modify: `scripts/dependabot-rollout/inspect_repo.py` — add `resolve_target_branch`.
- Modify: `scripts/dependabot-rollout/rollout.py` — call it and print the result in `--dry-run` output.

**Interfaces:**
- Consumes: `_gh_api` (already in `inspect_repo.py` from Task 23).
- Produces: `resolve_target_branch(owner: str, name: str, default_branch: str) -> str` — `"develop"` if that branch exists, else `default_branch`. Later tasks (25) call this to fill in each repo's `{{TARGET_BRANCH}}`.

- [ ] **Step 1: Add the function to `inspect_repo.py`**

```python
def resolve_target_branch(owner: str, name: str, default_branch: str) -> str:
    """`develop` if it exists on this repo, else the repo's actual default branch."""
    has_develop = _gh_api(f"repos/{owner}/{name}/branches/develop") is not None
    return "develop" if has_develop else default_branch
```

- [ ] **Step 2: Wire it into `rollout.py`'s per-repo loop** — replace the `print(...)` line in `main()` with:

```python
    from inspect_repo import categorize, resolve_target_branch

    for repo in repos:
        category = categorize(ORG, repo["name"])
        target_branch = resolve_target_branch(ORG, repo["name"], repo["default_branch"])
        print(f"{repo['name']}\t{category}\ttarget_branch={target_branch}")
```

(Move the `from inspect_repo import ...` line to the top of the file alongside the existing import, rather than inline inside `main()` — shown split here only to make the diff obvious against Task 23's version.)

- [ ] **Step 3: Re-run the dry-run sanity check**

```bash
python3 rollout.py --dry-run --repos Bitween-api,SW-Bus,laflef-mobile
```

Expected: `Bitween-api` → `target_branch=releases/r8.0` (no `develop`, per the earlier org audit), `SW-Bus` → `target_branch=main` (no `develop`, confirmed in the audit's "92 without develop" list), `laflef-mobile` → `target_branch=develop` (assuming it's among the 140 that have one — if this specific repo turns out to be an exception, verify against `gh api repos/simplify9/laflef-mobile/branches/develop` directly before treating the script as wrong).

- [ ] **Step 4: Commit**

```bash
git add scripts/dependabot-rollout/inspect_repo.py scripts/dependabot-rollout/rollout.py
git commit -m "feat: add target-branch resolution to rollout script"
```

---

### Task 25: Rollout script — PR-opening logic

**Files:**
- Create: `scripts/dependabot-rollout/open_pr.py`
- Modify: `scripts/dependabot-rollout/rollout.py` — add a `--commit` flag (mutating; `--dry-run` remains the safe default) that calls this module.

**Interfaces:**
- Consumes: `categorize`, `resolve_target_branch` (Task 24); the six filled-in templates from Tasks 15-19 (read from `dependabot-templates/<category>.yml` in this repo's own checkout).
- Produces: `open_pr.open_dependabot_pr(owner: str, name: str, category: str, target_branch: str, has_dockerfile: bool) -> str | None` — returns the PR URL, or `None` if skipped because `.github/dependabot.yml` already exists on that repo (idempotency guard).

- [ ] **Step 1: Write `open_pr.py`**

```python
"""Commits a filled-in dependabot.yml template to a new branch and opens a PR."""
import pathlib
import subprocess
import tempfile

TEMPLATES_DIR = pathlib.Path(__file__).resolve().parent.parent.parent / "dependabot-templates"


def _run(*args: str, cwd: str) -> str:
    result = subprocess.run(args, capture_output=True, text=True, cwd=cwd, check=True)
    return result.stdout.strip()


def _already_onboarded(owner: str, name: str) -> bool:
    result = subprocess.run(
        ["gh", "api", f"repos/{owner}/{name}/contents/.github/dependabot.yml"],
        capture_output=True, text=True, check=False,
    )
    return result.returncode == 0


def _render_template(category: str, target_branch: str, has_dockerfile: bool) -> str:
    template_path = TEMPLATES_DIR / f"{category}.yml"
    content = template_path.read_text().replace("{{TARGET_BRANCH}}", target_branch)
    if not has_dockerfile and category in {"nuget-api", "npm-frontend", "infra-actions-only"}:
        # Strip the docker package-ecosystem block for repos with no Dockerfile.
        lines = content.splitlines(keepends=True)
        out, skip = [], False
        for line in lines:
            if line.strip() == '- package-ecosystem: "docker"':
                skip = True
                continue
            if skip and line.strip().startswith("- package-ecosystem:"):
                skip = False
            if not skip:
                out.append(line)
        content = "".join(out)
    return content


def open_dependabot_pr(owner: str, name: str, category: str, target_branch: str, has_dockerfile: bool) -> str | None:
    if _already_onboarded(owner, name):
        print(f"SKIP {name}: .github/dependabot.yml already exists")
        return None

    rendered = _render_template(category, target_branch, has_dockerfile)

    with tempfile.TemporaryDirectory() as tmp:
        _run("gh", "repo", "clone", f"{owner}/{name}", ".", "--", "--depth=1", cwd=tmp)
        branch = "add-dependabot-config"
        _run("git", "checkout", "-b", branch, cwd=tmp)
        dependabot_dir = pathlib.Path(tmp) / ".github"
        dependabot_dir.mkdir(exist_ok=True)
        (dependabot_dir / "dependabot.yml").write_text(rendered)
        _run("git", "add", ".github/dependabot.yml", cwd=tmp)
        _run("git", "-c", "user.name=dependabot-rollout-bot",
             "-c", "user.email=devops@simplify9.com",
             "commit", "-m", "chore: add Dependabot configuration", cwd=tmp)
        _run("git", "push", "-u", "origin", branch, cwd=tmp)
        pr_url = _run(
            "gh", "pr", "create",
            "--title", "chore: add Dependabot configuration",
            "--body", f"Adds `.github/dependabot.yml` (category: `{category}`, target-branch: `{target_branch}`) as part of the org-wide Dependabot rollout.",
            cwd=tmp,
        )
        return pr_url
```

- [ ] **Step 2: Add `has_dockerfile` detection to `inspect_repo.py`**

```python
def has_dockerfile(owner: str, name: str) -> bool:
    return _file_exists(owner, name, "Dockerfile")
```

- [ ] **Step 3: Wire a `--commit` flag into `rollout.py`** — replace the argument parser and main loop:

```python
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--commit", action="store_true",
                         help="Actually open PRs. Mutually exclusive with --dry-run.")
    args = parser.parse_args()
    if args.dry_run == args.commit:
        parser.error("pass exactly one of --dry-run or --commit")
```

```python
    from inspect_repo import categorize, resolve_target_branch, has_dockerfile
    from open_pr import open_dependabot_pr

    for repo in repos:
        category = categorize(ORG, repo["name"])
        target_branch = resolve_target_branch(ORG, repo["name"], repo["default_branch"])
        dockerfile_present = has_dockerfile(ORG, repo["name"])
        if args.dry_run:
            print(f"{repo['name']}\t{category}\ttarget_branch={target_branch}\thas_dockerfile={dockerfile_present}")
        else:
            pr_url = open_dependabot_pr(ORG, repo["name"], category, target_branch, dockerfile_present)
            print(f"{repo['name']}\t{pr_url or 'SKIPPED (already onboarded)'}")
```

- [ ] **Step 4: Commit**

```bash
git add scripts/dependabot-rollout/
git commit -m "feat: add PR-opening logic to rollout script"
```

- [ ] **Step 5: Verify**

Do NOT run `--commit` yet against any real repo in this task — that's Task 28 (pilot). Verify only that `--dry-run` still works after the argparse change:

```bash
python3 rollout.py --dry-run --repos Bitween-api
```

Expected: same style of output as Task 24, now with a `has_dockerfile=` field appended.

---

### Task 26: Rollout script — vulnerability-alerts + automated-security-fixes enablement

**Files:**
- Create: `scripts/dependabot-rollout/enable_security_features.py`
- Modify: `scripts/dependabot-rollout/rollout.py` — call this after a successful PR open in `--commit` mode.

**Interfaces:**
- Consumes: nothing new.
- Produces: `enable_security_features.enable(owner: str, name: str) -> None` — explicitly `PUT`s both endpoints, does not assume already-on (per Musa's explicit instruction).

- [ ] **Step 1: Write `enable_security_features.py`**

```python
"""Explicitly enables Dependabot vulnerability alerts + automated security
fixes per repo. Does NOT assume these are already on -- only one repo
(SW-Bus) was spot-checked during the org audit, this is not an org-wide
guarantee."""
import subprocess


def enable(owner: str, name: str) -> None:
    for path in (
        f"repos/{owner}/{name}/vulnerability-alerts",
        f"repos/{owner}/{name}/automated-security-fixes",
    ):
        result = subprocess.run(
            ["gh", "api", "--method", "PUT", path],
            capture_output=True, text=True, check=False,
        )
        if result.returncode != 0:
            print(f"WARNING: failed to enable {path}: {result.stderr.strip()}")
```

- [ ] **Step 2: Wire it into `rollout.py`'s `--commit` branch, right after `open_dependabot_pr`**

```python
        else:
            pr_url = open_dependabot_pr(ORG, repo["name"], category, target_branch, dockerfile_present)
            print(f"{repo['name']}\t{pr_url or 'SKIPPED (already onboarded)'}")
            enable_security_features.enable(ORG, repo["name"])
```

(Add `import enable_security_features` alongside the other local imports at the top of `rollout.py`.)

- [ ] **Step 3: Commit**

```bash
git add scripts/dependabot-rollout/
git commit -m "feat: explicitly enable vulnerability alerts and security fixes per repo"
```

- [ ] **Step 4: Verify**

No mutation yet against a real repo (still Task 28). Confirm the module imports cleanly:

```bash
python3 -c "import sys; sys.path.insert(0, 'scripts/dependabot-rollout'); import enable_security_features"
```

Expected: no import error.

---

### Task 27: Rollout script — branch-protection configuration

**Files:**
- Create: `scripts/dependabot-rollout/branch_protection.py`
- Modify: `scripts/dependabot-rollout/rollout.py` — call this after `enable_security_features.enable(...)`.

**Interfaces:**
- Consumes: nothing new.
- Produces: `branch_protection.configure(owner: str, name: str, main_branch: str, develop_branch: str | None) -> None`. **Reads existing protection first and merges — never blind-overwrites.** The required-check context name is a module-level constant `VULN_CHECK_CONTEXT = "vuln-gate / check"`, explicitly flagged as **unverified** pending Task 28's pilot (see Task 3's Interfaces note) — this constant is the one thing in this task that must be corrected after the pilot if the real rendered name differs.

**Correctness note (caught in self-review, fixed inline below):** an earlier draft of this task re-PUT the *entire* protection object on every run, reusing the GET response's `required_pull_request_reviews`/`restrictions` fields as PUT input. GitHub's GET and PUT schemas for those fields don't match (GET returns full user/team objects; PUT expects login/slug arrays) — on any repo that already has reviewer requirements configured, that would either 422 or silently corrupt those settings. Fixed by using the dedicated `required_status_checks` sub-resource endpoint (`PATCH .../protection/required_status_checks`) to touch *only* the contexts list on repos that already have a protection rule, and a full `PUT` only for the case where no rule exists yet (nothing to clobber there).

- [ ] **Step 1: Write `branch_protection.py`**

```python
"""Configures branch protection so the critical-vuln check is REQUIRED on
main and present-but-not-required on develop.

Never re-PUTs a repo's whole protection object when one already exists --
GitHub's GET response shape for required_pull_request_reviews/restrictions
does not match what PUT expects for those same fields (GET returns full
user/team objects, PUT expects login/slug arrays), so blindly reusing GET
output as PUT input can corrupt or reject-with-422 a repo's existing reviewer
requirements. Instead, existing rules are updated via the dedicated
required_status_checks sub-resource endpoint, which touches only the
contexts list and leaves every other protection setting untouched. A full
PUT is only ever used to create a rule from scratch, where there is nothing
pre-existing to clobber.

VULN_CHECK_CONTEXT is the status-check context string GitHub renders for a
nested reusable-workflow job. This is a best-guess based on GitHub's
documented "<caller-job-id> / <called-job-id>" nesting convention and MUST be
confirmed against a real PR in Task 28's pilot before the full rollout
(Task 29) runs -- correct this constant first if the pilot shows otherwise.
"""
import json
import subprocess

VULN_CHECK_CONTEXT = "vuln-gate / check"


def _gh_api_json(path: str) -> dict | None:
    result = subprocess.run(["gh", "api", path], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        return None
    return json.loads(result.stdout)


def _create_protection(owner: str, name: str, branch: str, contexts: list[str]) -> None:
    """Create a new branch protection rule from scratch. Only used when no
    protection rule exists yet -- there is nothing pre-existing to clobber,
    so a full PUT with sane defaults is safe here."""
    payload = {
        "required_status_checks": {"strict": False, "contexts": contexts},
        "enforce_admins": False,
        "required_pull_request_reviews": None,
        "restrictions": None,
    }
    subprocess.run(
        ["gh", "api", "--method", "PUT", f"repos/{owner}/{name}/branches/{branch}/protection",
         "--input", "-"],
        input=json.dumps(payload), capture_output=True, text=True, check=True,
    )


def _add_required_contexts(owner: str, name: str, branch: str, existing: dict, contexts_to_add: list[str]) -> None:
    """Add contexts to an EXISTING protection rule via the dedicated
    required_status_checks sub-resource endpoint -- deliberately does NOT
    touch required_pull_request_reviews/restrictions/enforce_admins, so a
    repo's pre-existing reviewer requirements or other required checks are
    never clobbered."""
    existing_checks = existing.get("required_status_checks") or {"strict": False, "contexts": []}
    merged_contexts = sorted(set(existing_checks.get("contexts", [])) | set(contexts_to_add))
    payload = {"strict": existing_checks.get("strict", False), "contexts": merged_contexts}
    subprocess.run(
        ["gh", "api", "--method", "PATCH",
         f"repos/{owner}/{name}/branches/{branch}/protection/required_status_checks",
         "--input", "-"],
        input=json.dumps(payload), capture_output=True, text=True, check=True,
    )


def _ensure_required_contexts(owner: str, name: str, branch: str, contexts: list[str]) -> None:
    existing = _gh_api_json(f"repos/{owner}/{name}/branches/{branch}/protection")
    if existing is None:
        _create_protection(owner, name, branch, contexts)
    else:
        _add_required_contexts(owner, name, branch, existing, contexts)


def _ensure_protection_exists_no_required_contexts(owner: str, name: str, branch: str) -> None:
    """develop: make sure SOME protection rule exists, without adding any
    required contexts and without touching an already-existing rule at all
    (if one exists, its required_status_checks are left exactly as-is --
    the vuln check still shows up there as a plain, non-required check
    purely because the workflow-template file exists in the repo)."""
    existing = _gh_api_json(f"repos/{owner}/{name}/branches/{branch}/protection")
    if existing is None:
        _create_protection(owner, name, branch, contexts=[])


def configure(owner: str, name: str, main_branch: str, develop_branch: str | None) -> None:
    # main: VULN_CHECK_CONTEXT is REQUIRED.
    _ensure_required_contexts(owner, name, main_branch, [VULN_CHECK_CONTEXT])

    # develop (if it exists): ensure a protection rule exists, but never add
    # the vuln check to its required contexts -- its presence as a plain
    # (non-required) check comes from the workflow-template file existing in
    # the repo, not from anything in branch protection.
    if develop_branch:
        _ensure_protection_exists_no_required_contexts(owner, name, develop_branch)
```

- [ ] **Step 2: Wire it into `rollout.py`'s `--commit` branch**

```python
        else:
            pr_url = open_dependabot_pr(ORG, repo["name"], category, target_branch, dockerfile_present)
            print(f"{repo['name']}\t{pr_url or 'SKIPPED (already onboarded)'}")
            enable_security_features.enable(ORG, repo["name"])
            develop = target_branch if target_branch == "develop" else None
            branch_protection.configure(ORG, repo["name"], repo["default_branch"], develop)
```

(Add `import branch_protection` alongside the other local imports.)

- [ ] **Step 3: Commit**

```bash
git add scripts/dependabot-rollout/
git commit -m "feat: add branch-protection configuration to rollout script"
```

- [ ] **Step 4: Verify**

No mutation against a real repo yet. Confirm the module imports cleanly:

```bash
python3 -c "import sys; sys.path.insert(0, 'scripts/dependabot-rollout'); import branch_protection; print(branch_protection.VULN_CHECK_CONTEXT)"
```

Expected: prints `vuln-gate / check` with no import error.

---

### Task 28: Pilot run — 2-3 named repos

**Files:** none (execution task, no new files).

**Interfaces:**
- Consumes: the full `rollout.py --commit` pipeline (Tasks 23-27).
- Produces: real PRs + real branch-protection/security-feature changes on a small, deliberately chosen set of pilot repos — and, critically, the **confirmed real value** for `VULN_CHECK_CONTEXT` to correct in Task 27's constant before Task 29.

- [ ] **Step 1: Merge Task 3's `critical-vuln-check.yml` workflow-template into ONE pilot repo manually first** (before running the rollout script on it), so there's a real PR to observe the check-name rendering on:

```bash
gh repo clone simplify9/SW-Surl-api /tmp/vuln-check-pilot
cd /tmp/vuln-check-pilot
git checkout -b add-vuln-check
mkdir -p .github/workflows
curl -s https://raw.githubusercontent.com/simplify9/.github/main/workflow-templates/critical-vuln-check.yml \
  -o .github/workflows/critical-vuln-check.yml
git add .github/workflows/critical-vuln-check.yml
git commit -m "chore: add critical vulnerability check"
git push -u origin add-vuln-check
gh pr create --title "chore: add critical vulnerability check" --body "Pilot for the org-wide critical-vuln gate."
```

- [ ] **Step 2: Open the resulting PR in the GitHub UI and read the exact status-check name shown** under "Some checks haven't completed yet" / "All checks have passed". Record it verbatim.

- [ ] **Step 3: If the recorded name differs from `vuln-gate / check`, fix `branch_protection.py`'s constant** (Task 27, Step 1) before proceeding:

```python
VULN_CHECK_CONTEXT = "<the real observed name>"
```

Commit this correction on its own if it changes anything:

```bash
git add scripts/dependabot-rollout/branch_protection.py
git commit -m "fix: correct VULN_CHECK_CONTEXT to the observed GitHub check name"
```

- [ ] **Step 4: Choose 2 more pilot repos from different categories** — one `.NET` API not yet touched (e.g. `SW-Mtm-api`) and one npm frontend (e.g. `sparetify-admin-ui`) — and run the full rollout script against these plus the Step 1 repo:

```bash
cd scripts/dependabot-rollout
python3 rollout.py --commit --repos SW-Surl-api,SW-Mtm-api,sparetify-admin-ui
```

- [ ] **Step 5: Manual verification checklist** — for each of the 3 pilot repos, confirm:
  - [ ] A PR exists adding `.github/dependabot.yml` with the correct ecosystems for its category and the correct `target-branch`.
  - [ ] `gh api repos/simplify9/<repo>/vulnerability-alerts` returns `204` (enabled).
  - [ ] `gh api repos/simplify9/<repo>/automated-security-fixes` returns `200` with `{"enabled": true}`.
  - [ ] `gh api repos/simplify9/<repo>/branches/main/protection` shows the vuln-check context in `required_status_checks.contexts`, and any pre-existing required checks/reviews on that repo are still present (not clobbered).
  - [ ] If the repo has a `develop` branch, its protection rule exists but does **not** list the vuln-check context as required.

- [ ] **Step 6: STOP — report the pilot results to Musa and get explicit go/no-go before Task 29.** Do not proceed to the full 232-repo rollout in the same session without this confirmation — this is the last checkpoint before mutating the remaining ~229 repos' branch protection and security settings.

---

### Task 29: Full rollout — all 232 repos, batched by category

**Files:** none (execution task, no new files).

**Interfaces:**
- Consumes: the full `rollout.py --commit` pipeline (Tasks 23-27), corrected per Task 28's findings.

- [ ] **STOP: This task mutates branch protection and security settings on ~229 live repos (232 minus the 3 already piloted in Task 28). Do not run this unattended — confirm with Musa immediately before firing, even if every prior task and the pilot succeeded cleanly.**

- [ ] **Step 1: Run in category batches, not one single invocation** — matching the same Monday/Tuesday/Wednesday/Thursday stagger used for Dependabot's own schedule, so a failure in one category doesn't block the others and each batch's PR volume lands on a predictable day:

```bash
cd scripts/dependabot-rollout
# .NET APIs (Monday cadence)
python3 rollout.py --commit --repos "$(python3 rollout.py --dry-run | awk -F'\t' '$2=="nuget-api"{print $1}' | paste -sd, -)"
```

- [ ] **Step 2: Repeat Step 1's pattern for each remaining category** (`npm-frontend`, `react-native-mobile`, `flutter-mobile`, `infra-actions-only`), reviewing the printed per-repo output after each batch for `SKIPPED` (already onboarded — expected for the 3 pilot repos) or any `WARNING:` lines from `enable_security_features.py` before moving to the next batch.

- [ ] **Step 3: After all batches complete, spot-check 5 repos not in the pilot set** using the same Task 28 Step 5 checklist, to catch any category-specific failure mode the pilot's 3 repos didn't expose.

- [ ] **Step 4: Report final counts to Musa** — repos onboarded, repos skipped (already had a config), any repos that hard-failed (e.g. an unexpected API permission error) and need manual follow-up.

---

## Self-Review

**Spec coverage:** every section of the 2026-07-12 design spec maps to a task — scope/target-branch (Tasks 23-24), rollout mechanism/templates (Tasks 15-21, 23, 25), cadence/staggering (Tasks 15-19's `day:` fields, Task 29's batching), auto-merge (Task 4), the critical-vuln gate's three call sites (Tasks 2-3 PR-time, Tasks 5-14 build-time, Task 4 auto-merge dependency), explicit security-feature enablement (Task 26), branch-protection required-vs-not (Task 27), and documentation upkeep (Task 22).

**Placeholder scan:** no TBD/TODO markers; every step has complete, runnable code. The one intentionally-flagged uncertainty (`VULN_CHECK_CONTEXT`'s exact string) is not a placeholder — it is a documented, testable unknown with an explicit correction step (Task 28, Steps 2-3) before it's relied upon in the un-attended Task 29.

**Type/name consistency:** `check-critical-vulns` (Task 1) is referenced identically in Tasks 2, 5-14. The `critical-vuln-gate` job id (Tasks 5-14) and `vuln-gate` job id (Tasks 2-4, which wrap the reusable workflow rather than the raw action) are deliberately different names for different things — the former is a raw composite-action-calling job inlined directly into six/ten existing workflows, the latter is a job that calls the shared `critical-vuln-gate.yml` reusable workflow via `uses:`; this distinction is intentional, not a naming slip, and is called out explicitly in each task's Interfaces block. `categorize()`, `resolve_target_branch()`, `has_dockerfile()`, `open_dependabot_pr()`, `enable()`, `configure()` are defined once (Tasks 23, 24, 25, 26, 27 respectively) and imported with matching signatures everywhere they're subsequently called.
