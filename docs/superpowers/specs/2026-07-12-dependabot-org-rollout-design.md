# Org-wide Dependabot rollout + critical-vulnerability merge gate

Status: approved by Musa Misto on 2026-07-12, pending written-spec review before implementation planning.

## Context

Simplify9's `simplify9` GitHub organization has 244 repos (232 active — 12 archived, 0 forks). None of them have a `dependabot.yml` today, including this `.github` repo itself. Goal: roll out Dependabot version updates + security updates across all 232 active repos, and add a mechanism (not provided by stock Dependabot) that blocks merges into `main` — and warns on `develop` — when a repo has an open **critical**-severity Dependabot alert.

Org is on the GitHub **Team** plan (confirmed via API: `orgs/simplify9/security-configurations` → 404), not Enterprise/GHAS — no org-wide security policy toggle exists. Everything here must be done per-repo.

## Scope

- **232 active repos** in `simplify9` (exclude the 12 archived; 0 forks to worry about).
- Ecosystem mix (from audit): ~76 C# (`nuget`), ~98 TypeScript/JavaScript (`npm`), ~26 no clear manifest (infra/config-only), small pockets of Dart (`pub`), Java, Python, etc. Sub-categories within the TS/JS group matter for template selection (see Rollout Mechanism).
- Branch layout: 230/232 default to `main` (2 outliers: `Bitween-api` → `releases/r8.0`, `Bitween-Adapters` → `net6`, handled as-is — Dependabot config uses each repo's actual default branch, not a hardcoded assumption).
- `develop` branch exists on 140/232 (60%); absent on 92 (mostly standalone C# NuGet library repos under `SW-*`, plus `-www`/`-docs`/`-cms` static sites, plus `.github` itself).

## Decision: `target-branch`

- **`develop`** where the branch exists (140 repos).
- **The repo's actual default branch** (`main`, or the 2 outliers) for the 92 repos without `develop` — these are predominantly libraries/static sites that don't use a staged branch flow, so their default branch is their integration branch.
- The rollout script determines this per-repo at generation time (checks for `develop`'s existence via the API), it is not a static assumption baked into a template.

## Rollout mechanism

GitHub has no native org-wide `dependabot.yml` — every repo needs its own file committed. Approach:

1. Author a small set of **category templates** under a new `dependabot-templates/` folder in this `.github` repo, mirroring the existing `workflow-templates/` convention:
   - `nuget-api.yml` — ecosystems: `nuget`, `docker` (if Dockerfile present), `github-actions`
   - `npm-frontend.yml` — ecosystems: `npm`, `docker` (if present), `github-actions` (covers React/Vite/Next/Vue/Strapi — same shape, template is ecosystem-driven not framework-driven)
   - `react-native-mobile.yml` — ecosystems: `npm`, `bundler` (fastlane Gemfile), `github-actions` (no `docker`)
   - `flutter-mobile.yml` — ecosystems: `pub`, `github-actions`
   - `infra-actions-only.yml` — ecosystems: `github-actions` only (+ `docker` if a Dockerfile exists) — for Helm-chart/infra repos and any repo with no application package manifest
   - `github-repo.yml` — this `.github` repo's own config: `github-actions` only (workflows + actions), since there's no application code here.
2. A rollout script (`gh` CLI + git) iterates the 232 repos. For each repo it **does not** trust the GitHub API's coarse `primaryLanguage` field alone (that can't distinguish, e.g., a plain Node/Express API from a React/Vite frontend, or a Strapi CMS from a plain npm frontend). It inspects the actual repo tree (via `contents` API or a shallow temp clone) for `package.json` (+ its `dependencies` to distinguish React Native / Next / Strapi / plain Node), `*.csproj`/`*.sln`, `pubspec.yaml`, `Dockerfile`, `Gemfile`, and existing `.github/workflows/*.yml` reusable-workflow references, then picks the matching category template, fills in the resolved `target-branch`, and opens **one PR per repo** adding `.github/dependabot.yml`.
3. Same script (or a companion pass) also, per repo:
   - Explicitly `PATCH`-enables **Dependabot vulnerability alerts** and **Dependabot automated security fixes** (do not assume already-on, even though one spot-checked repo had it — confirmed not to be an org-wide guarantee).
   - Adds the new PR-time check (see below) as a **required** status check on the `main` branch protection rule, and as a **present-but-not-required** check on `develop`'s branch protection rule (creating a minimal branch protection rule on `develop` if none exists yet, without altering any other existing protection settings there).

## Cadence & PR volume

- **Weekly** update schedule (daily is unworkable at 232-repo scale even with grouping).
- **Staggered by category** across weekdays (e.g. `.NET` APIs Monday, frontend Tuesday, mobile Wednesday, infra Thursday) so PRs don't all land the same morning org-wide.
- **Grouping enabled** per ecosystem (bundle minor/patch bumps into one PR per ecosystem per repo, rather than one PR per dependency) — this is the primary lever keeping PR volume survivable at this scale.

## Auto-merge policy

- **Patch-level semver bumps only**, for `npm`, `nuget`, `pub`, `bundler`, `github-actions` ecosystems. **Never** `docker` (base image bumps can change OS-level behavior — always manual review). **Never** minor/major (semver compatibility promises are unreliable in practice) — always manual review.
- Mechanism: a new workflow-template (`workflow-templates/dependabot-auto-merge.yml` + `.properties.json`, `on: pull_request` — same rationale as the vuln-check template above, this needs a real trigger so it belongs in `workflow-templates/`, not `.github/workflows/`) using `dependabot/fetch-metadata@v2` to read the PR's `update-type`; when it equals `version-update:semver-patch` for an eligible ecosystem, run `gh pr merge --auto --squash`.
- Since Dependabot never targets `main` directly (it targets `develop`, or a repo's default branch when no `develop` exists), auto-merge only ever lands on that target branch, never `main`.
- Auto-merge additionally has an explicit job dependency (`needs:`) on the new critical-vuln-check job succeeding — this closes the gap where the vuln check is only a *required* branch-protection check on `main`, not on `develop` (where Dependabot's own PRs land) — without this, a patch bump could auto-merge into `develop` past an unresolved critical alert simply because that check isn't "required" there.

## Critical-vulnerability merge gate

**Chosen mechanism**: a single new composite action, reused at three call sites — not `actions/dependency-review-action`, because that action's enforcement guarantees for private repos have historically been tied to a GitHub Advanced Security license, and this org is on the Team plan (not Enterprise+GHAS). Building the safety mechanism on an assumption we can't verify against the current plan tier is a risk not worth taking when a plan-tier-independent alternative exists.

- **New composite action** — `.github/actions/check-critical-vulns` — calls `GET /repos/{owner}/{repo}/dependabot/alerts?state=open&severity=critical` and fails (with an explicit `::error::` stating the failure is due to an unresolved critical Dependabot alert, listing the affected package(s)/advisory ID(s)) if the count is nonzero. Requires the calling workflow to grant `permissions: security-events: read`. Follows the repo's 4-pillar log-output framework (namespaced `<PREFIX>_CP{N}_STATUS`, e.g. `VULN_GATE_CP1_STATUS`) and the `write-job-summary` convention like every other action here.
- **Call site 1 — PR-time check**: a new reusable workflow (`.github/workflows/critical-vuln-gate.yml`, `on: workflow_call:` only, per this repo's convention that reusable workflows never carry `pull_request`/`push` triggers themselves) wraps the composite action. A new workflow-template (`workflow-templates/critical-vuln-check.yml` + `.properties.json`, mirroring the existing `service-cicd`/`generic-chart-cicd` template pattern) carries `on: pull_request: branches: [main, develop]` and calls the reusable workflow. This is the file callers actually adopt into their repos.
  - On `main`: the check is marked **required** in branch protection → merge is physically blocked while a critical alert is open.
  - On `develop`: the check is present but **not required** → shows as a failing/red check (a visible warning) without blocking the merge.
- **Call site 2 — build-time gate**, two variants depending on the pipeline's existing gating idiom:
  - **Helm/Cloudflare pipelines** — `reusable-service-cicd.yml`, `generic-chart-helm.yml`, `generic-gateway-helm-template.yml`, `helm-deploy-values.yml`, `next-cloudflare-worker.yaml`, `vite-cloudflare-worker.yml`. New early job gated on `needs.<version-job>.outputs.is-release == 'true'` (the existing `determine-semver` output already used org-wide to detect "this run is on the default/release branch"), consistent with this repo's convention of never gating on raw `if: github.ref_name == 'main'` inside a reusable workflow.
  - **Mobile pipelines** (added 2026-07-12 — initially excluded, then reinstated by Musa) — `ios-build.yml`, `android-build.yml`, `flutter-ios-build.yml`, `flutter-android-build.yml`. These don't use `determine-semver`/`is-release` — confirmed via direct inspection that all four share a `build` job followed by a `release_with_environment` job (`needs: build`, `if: inputs.release-environment != '' && !inputs.disable-release`). The gate here is a new job that `release_with_environment` adds to its `needs:` list, so a critical alert blocks the TestFlight/Play Store release step without blocking the plain `build` (compile/archive) job. This matches the same semantic as the Helm variant — block *shipping*, not *building*.
  - Both variants are defense-in-depth against a merge that bypassed the PR-time check (e.g. an admin override, or a critical CVE published *after* merge).
  - **Explicitly excluded**: `gateway-chart-cicd.yml` only — it builds/publishes a Helm chart, not a running application, so there's nothing to compromise at deploy time.

## Explicit per-repo enablement (not assumed)

Only one repo (`SW-Bus`) was spot-checked and found to already have Dependabot vulnerability alerts + automated security fixes enabled — this is **not** assumed to be true org-wide. The rollout script explicitly enables both, per repo, for all 232, rather than relying on GitHub's default-on behavior.

## Out of scope / open items for the implementation plan to size

- Exact category-template YAML content (ecosystem lists, `open-pull-requests-limit`, grouping rules) — drafted during implementation, following the shapes above.
- The ~179 of 232 repos not already deep-audited locally need the script's live-inspection logic (not a one-time manual audit) to pick the correct template — this is a rollout-script requirement, not a pre-rollout audit task.
- Whether `develop` branch protection needs to be created from scratch on the 140 repos that have the branch but no protection rule yet, vs. modified in place — the rollout script must check current state per repo rather than assume no protection exists.
- Token/credential scope needed for: opening PRs across 232 repos, PATCHing branch protection, and enabling vulnerability alerts — needs a token with org-wide repo admin rights (current `gh auth status` confirmed `repo`, `read:org`, `workflow` scopes present; branch-protection and vulnerability-alert-toggle endpoints need admin-level repo permission, which should follow from Musa's org-owner access but should be verified against the token actually in use, not assumed).
