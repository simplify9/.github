# Simplify9 `.github` Repository — Agent Instructions

This repository is the **organization-wide shared CI/CD library** for Simplify9. It contains reusable GitHub Actions workflows, composite actions, and org workflow-templates. No application code lives here.

---

## Repository Layout

```
.github/                    ← workspace root (README.md, AGENTS.md, CLAUDE.md live here)
├── .github/
│   ├── workflows/          ← reusable workflows  (workflow_call triggers)
│   └── actions/            ← composite actions    (uses: in steps)
├── workflow-templates/     ← org starter templates surfaced in GitHub's "New workflow" UI
└── profile/README.md       ← org profile page
```

Every file in `.github/workflows/` is a **reusable workflow** — it has `on: workflow_call:` (and occasionally `on: workflow_dispatch:`) and is never run standalone. Every directory in `.github/actions/` is a **composite action** with its own `action.yml`. Every file in `workflow-templates/` is a thin starter caller (paired with a `.properties.json` metadata sidecar) that GitHub offers when a user clicks "New workflow" in an org repo.

---

## How Callers Reference This Repo

From any repo in the `simplify9` org:

```yaml
# Reusable workflow
uses: simplify9/.github/.github/workflows/<name>.yml@main

# Composite action (inside a step)
uses: simplify9/.github/.github/actions/<name>@main
```

Always use `@main`. Never use a SHA pin or version tag — this repo has no release tags. Note the doubled `.github/.github/` path segment (the repo is named `.github`, and the workflows live in its `.github/` directory).

---

## Architecture: Two-Layer Pattern

```
Caller workflow
    └── reusable workflow (workflows/*.yml)
            ├── composite action (actions/determine-semver)
            ├── composite action (actions/docker-build-push)
            ├── composite action (actions/helm-generic | helm-deploy)
            └── composite action (actions/write-job-summary)
```

Composite actions are the smallest units of work. Reusable workflows orchestrate jobs and call composite actions. Callers only call reusable workflows (never composite actions directly, except for simple utility actions like `determine-semver` or `tag-github-origin`). Every reusable workflow references the composite actions through the **external** `simplify9/.github/.github/actions/<name>@main` path — not local `./.github/actions/...` paths — so a workflow run always uses the actions as published on `main`.

---

## Pinned Action Versions

**Do not change these without a full compatibility audit.** These are the versions currently used by `uses:` references across this repo:

| Action | Version | Notes |
|---|---|---|
| `actions/checkout` | `@v7` | |
| `actions/setup-node` | `@v6` | |
| `actions/setup-dotnet` | `@v5` | |
| `actions/setup-java` | `@v5` | |
| `actions/upload-artifact` | `@v7` | |
| `actions/download-artifact` | `@v8` | Always download by `name:`, never by `artifact-ids:` |
| `actions/cache` | `@v5` (and `@v4` in some CF workflows) | |
| `azure/setup-helm` | `@v5` | Installs latest stable Helm unless a version is pinned |
| `azure/setup-kubectl` | `@v5` | |
| `docker/setup-buildx-action` | `@v4` | |
| `docker/setup-qemu-action` | `@v4` | Multi-platform builds |
| `docker/login-action` | `@v4` | |
| `docker/metadata-action` | `@v6` | |
| `docker/build-push-action` | `@v7` | |
| `cloudflare/wrangler-action` | `@v4` | Used for all Cloudflare Workers deploys (`command: deploy`). Deployment URL is the `deployment-url` output |
| `gradle/actions/setup-gradle` | `@v5` | **Pinned to v5.** Do NOT use `gradle/gradle-build-action` (archived). v6.x is not adopted — stay on v5 |
| `ruby/setup-ruby` | `@v1` | iOS: Ruby/Bundler-managed CocoaPods (`bundler-cache`) |
| `subosito/flutter-action` | `@v2` | Flutter SDK setup (Flutter iOS/Android workflows). Version selector via `flutter-version` input, default `3.x` |
| `maxim-lobanov/setup-xcode` | `@v1` | iOS Xcode version selection |
| `apple-actions/upload-testflight-build` | `@v5` | iOS TestFlight upload (App Store Connect API) — runs on `ubuntu-latest` |
| `r0adkll/upload-google-play` | `@v1` | Android Google Play upload |

**Helm / kubectl CLI versions:** the composite actions (`helm-deploy`, `helm-deploy-s9generic`, `helm-package-push`) default their `helm-version` / `kubectl-version` inputs to `latest`. Some reusable workflows pin a specific CLI: `helm-deploy-values.yml` defaults Helm `v4.2.0` / kubectl `v1.33.0`; `gateway-chart-cicd.yml` defaults Helm `v4.2.2`. There is no single global CLI pin — check the specific workflow/action input.

---

## Conventions — Must Follow for Every Change

### Composite Actions
- File: `.github/actions/<name>/action.yml`
- `runs.using: "composite"` always — **all 18 actions in this repo are composite**; none are Docker- or JavaScript-based
- Every `run:` step must have `shell: bash`
- Every input must have `description:` and a sensible `default:` (or `required: true`)
- Outputs must have a `value:` expression pointing to a step output
- Keep heavy logic in a sibling script only when it is genuinely large or shared — currently only `gateway-onboard/onboard.sh` (cluster-mutating) and `gateway-routing/render.sh` (pure value rendering) do this; every other action keeps its logic inline in `action.yml`

### Reusable Workflows
- File: `.github/workflows/<name>.yml`
- Must have `on: workflow_call:` as the primary trigger
- All inputs must have `description:`, `type:`, and `required:` set explicitly
- Secrets are declared under `on.workflow_call.secrets:` — never passed as inputs
- Branch-to-environment mapping is **not** done with `if:` checks on `github.ref` inside these workflows. Instead it is delegated to `determine-semver` via `release-branch: ${{ github.event.repository.default_branch }}`: a build on the default branch produces a clean release version + git tag; any other branch produces a qualified prerelease tag (`x.y.z-<branch>.<run>`) and is not treated as a release. Caller workflows / templates do the per-branch gating with `if: github.ref_name == '...'` and choose the GitHub Environment.
- Deploy jobs bind to a GitHub Environment via a `deploy-environment` / `release-environment` / `gh-environment` input (use environment protection rules for approvals), and where a deploy is optional it is gated by a boolean (`deploy: false` in `reusable-service-cicd.yml`) or by leaving the environment input empty

### Secrets vs Inputs for Helm
This is a critical pattern. **Never mix Helm config and secrets in a single parameter:**

| Parameter | Helm flag | Used for |
|---|---|---|
| `helm-set-values` (workflow input) | `--set` | Non-sensitive config: replicas, ingress, environment label |
| `helm-set-secret-values` (workflow secret) | `--set-string` | Secrets: DB connection strings, API keys, anything with special characters |

Use `--set-string` for secrets because it bypasses Helm type coercion / shell parsing and prevents `SSL:`, `=`, or `//` characters from causing failures. At the composite-action layer the secret input is `secret_set_values` (`helm-generic`, snake_case) or `secret-set-string-values` (`helm-deploy` / `helm-deploy-s9generic`, kebab-case).

### Artifact Upload/Download Pairing
When adding upload/download artifact pairs (e.g. mobile build → release jobs):
- Always use a matching `name:` input — never `artifact-ids:`
- Upload with `actions/upload-artifact@v7`, download with `actions/download-artifact@v8`
- Set `retention-days: 1` for build artifacts not needed beyond the pipeline run

### Versioning
All Docker/Helm/NuGet versioning flows through `actions/determine-semver`:
- Inputs `major` + `minor`; reads git tags matching `major.minor.*` and auto-increments the patch from the highest match
- Output `version` is always a clean `x.y.z` (no `v` prefix); output `git-tag` is clean on the release branch and qualified (`x.y.z-<branch>.<run>`) elsewhere; output `is-release` is `'true'`/`'false'`
- After a successful deploy/publish, `tag-github-origin` creates the tag via the GitHub REST API (no checkout needed), so the next run increments from it

### Log Output Standards

Every composite action **must** follow the 4-pillar log output framework. This applies to all new actions and any modification to existing ones.

**4 Pillars:**
1. **Meaningful and context-aware** — emit a `::notice::` announcement on the first step with key input values
2. **Checkpoint-driven** — wrap each critical operation in `::group::`/`::endgroup::`, track status in **namespaced** `<PREFIX>_CP{N}_STATUS` env vars (e.g. `DOCKER_CP1_STATUS`, `HELM_DEPLOY_CP2_STATUS`). Never use bare `CHECKPOINT_N_STATUS` in a composite action — see the namespacing rule below
3. **Systematically consistent** — use the canonical emoji/tag vocabulary below
4. **Summarised** — write a structured section to `$GITHUB_STEP_SUMMARY`. Reusable workflows do this through the shared **`write-job-summary`** composite action (inputs: `title`, `status` = `${{ job.status }}`, optional `icon`, `details`); composite actions append their own summary table in an `if: always()` final step

**Canonical emoji/tag vocabulary:**

| Domain | Tag | Emoji |
|--------|-----|-------|
| Docker | `[DOCKER]` | 🐳 |
| Helm / Kubernetes | `[HELM]` | ☸️ |
| Gateway API | `[GATEWAY]` | 🚪 |
| .NET / NuGet | `[DOTNET]` | 🔷 |
| Cloudflare Workers | `[CF-WORKERS]` | ⚡ |
| iOS | `[IOS]` | 🍎 |
| Android | `[ANDROID]` | 🤖 |
| Versioning / Tagging | `[VERSION]` | 🏷️ |
| Code Signing | `[SIGN]` | 🔏 |

**Step template for a composite action:**

```yaml
steps:
  # 1. Announce (first step — always runs)
  - name: Announce <action>
    shell: bash
    run: |
      echo "::notice title=🏷️ [DOMAIN] Action Name::key: ${{ inputs.key }}"
      # <PREFIX> = a short, action-specific prefix (e.g. DOCKER, HELM_DEPLOY, CF_DOMAIN)
      echo "<PREFIX>_CP1_STATUS=⏳ Pending" >> "$GITHUB_ENV"
      echo "<PREFIX>_CP2_STATUS=⏳ Pending" >> "$GITHUB_ENV"

  # 2. Existing work step — wrap with group, set status at end
  - name: Do the work
    shell: bash
    run: |
      echo "::group::🏷️ [CHECKPOINT 1/2] Step Name"
      # ... existing commands ...
      echo "<PREFIX>_CP1_STATUS=✅ PASSED" >> "$GITHUB_ENV"
      echo "::endgroup::"

  # 3. For uses: steps — add a confirm step immediately after
  - uses: some/action@v1
  - name: Confirm step complete
    shell: bash
    run: |
      echo "<PREFIX>_CP2_STATUS=✅ PASSED" >> "$GITHUB_ENV"

  # 4. Failure report (before summary)
  - name: Report failure
    if: failure()
    shell: bash
    run: |
      echo "::error title=❌ [DOMAIN] Action failed::context. Checkpoints — 1) Name: ${<PREFIX>_CP1_STATUS:-⏭️ Not reached} | 2) Name: ${<PREFIX>_CP2_STATUS:-⏭️ Not reached}."

  # 5. Summary (always last, always runs)
  - name: Write action summary
    if: always()
    shell: bash
    run: |
      EOF=$(dd if=/dev/urandom bs=15 count=1 status=none | base64)
      cat >> "$GITHUB_STEP_SUMMARY" << "$EOF"
      ## 🏷️ Action Title

      | Field | Value |
      |-------|-------|
      | Key input | ${{ inputs.key }} |
      | Triggered by | ${{ github.actor }} |

      ## 📋 Checkpoint Summary

      | # | Checkpoint | Status |
      |---|------------|--------|
      | 1 | Step One | ${<PREFIX>_CP1_STATUS:-⏭️ Not reached} |
      | 2 | Step Two | ${<PREFIX>_CP2_STATUS:-⏭️ Not reached} |
      $EOF
```

**Rules:**
- **Namespace checkpoint env vars per action** — use `<PREFIX>_CP{N}_STATUS` (e.g. `DOCKER_CP1_STATUS`), never bare `CHECKPOINT_N_STATUS`. A composite action's `>> "$GITHUB_ENV"` writes leak into the **caller's** job environment, so a bare `CHECKPOINT_1_STATUS` silently overwrites the calling workflow's (and sibling actions') same-named checkpoints, corrupting their failure reports and summaries. The prefix must be unique per action (e.g. `IOS_CERT` vs `IOS_PROFILE`, `HELM_DEPLOY` vs `HELM_PKG`) so two actions in one job can't collide either
- Use `EOF=$(dd if=/dev/urandom bs=15 count=1 status=none | base64)` for the heredoc delimiter — never a fixed string like `EOF` which can collide with step output
- `<PREFIX>_CP{N}_STATUS` defaults to `⏭️ Skipped` (not `⏳ Pending`) when the step is always skipped (e.g. optional `if:` steps that never run in most call sites)
- Do not add checkpoints for trivial one-liner steps (masking, `mkdir`, `chmod`) — only for operations that can meaningfully fail independently

---

## Deployment Infrastructure

- **Kubernetes**: DigitalOcean managed cluster
- **Ingress/Gateway**: Cilium Gateway API and classic ingress-nginx coexist; `reusable-service-cicd.yml` and `generic-gateway-helm-template.yml` select between them with `routing-mode`
- **Helm chart registry**: ChartMuseum at `https://charts.sf9.io` **and** GHCR as an OCI registry (`oci://ghcr.io/...`). `reusable-service-cicd.yml` publishes to `github-oci`, `chartmuseum`, or `both`
- **Default generic charts**: `s9genericchart` (ingress-nginx pipeline, `generic-chart-helm.yml`) and `s9genericchart-v2` (gateway pipeline, `generic-gateway-helm-template.yml`) from `https://charts.sf9.io`
- **Container registry**: `ghcr.io` (default for most workflows), `docker.io`, or `registry.digitalocean.com/<namespace>`
- **kubeconfig**: passed as a base64-encoded (or raw-YAML) secret — `kubeconfig` for ingress, `kubeconfig-gateway` for the gateway routing-mode in `reusable-service-cicd.yml`

---

## Workflow Reference

All nine workflows live in `.github/workflows/`. (When in doubt, `ls .github/workflows` is the source of truth — this table is maintained, not generated.)

### Frontend / Cloudflare

| Workflow | Purpose | Key inputs |
|---|---|---|
| `next-cloudflare-worker.yaml` | Next.js (OpenNext adapter) → Cloudflare Workers | `project_name`, `environment`, `route`, `package_manager`, `opennextjs_version` |
| `vite-cloudflare-worker.yml` | Vite SPA → Cloudflare Workers static assets (native SPA routing, no Worker script) | `project_name`, `environment`, `route` (required), `assets_dir` |

Both call `generate-wrangler-config` to produce `wrangler.toml` dynamically, and `write-job-summary`.

### Service / Backend (Docker + Helm → Kubernetes)

| Workflow | Purpose | Key inputs |
|---|---|---|
| `reusable-service-cicd.yml` | Consolidated pipeline: semver → optional NuGet → Docker → publish chart (`github-oci` / `chartmuseum` / `both`) → optional deploy (`ingress-nginx` or `gateway-api`) → tag | `chart-name` (required), `chart-publish-method`, `deploy`, `routing-mode` |
| `generic-chart-helm.yml` | Full CI/CD deploying `s9genericchart` over **ingress-nginx**, with optional EF Core migration init Job; tags after a successful deploy | `app-name`, `namespace`, `ingress-hosts`, `init-job-image` |
| `generic-gateway-helm-template.yml` | Gateway-first CI/CD deploying `s9genericchart-v2` behind the **Cilium Gateway API** (auto-onboards listeners + cert-manager Certificates); supports `gateway`/`ingress`/`dual` | `app-name`, `gateway-hostnames`, `routing-mode`, `gateway-section-names` |
| `helm-deploy-values.yml` | Deploy-only: deploys an already-published chart from a ChartMuseum-style repo using a caller values file (no build/package/tag) | `release-name`, `chart-name`, `chart-repo`, `namespace`, `values-file` |

### Helm Chart Development

| Workflow | Purpose |
|---|---|
| `gateway-chart-cicd.yml` | CI/CD for a Cilium Gateway API-aware Helm chart: compute SemVer → `helm lint --strict` + routing/ConfigMap render assertions (via `yq`) → package → push to ChartMuseum → tag origin |

### Mobile

| Workflow | Purpose | Key inputs |
|---|---|---|
| `ios-build.yml` | React Native / native iOS → TestFlight. Builds + archives + exports on a macOS runner; uploads from `ubuntu-latest` via App Store Connect API | `workspace`, `scheme`, `release-environment`, `disable-release` |
| `android-build.yml` | React Native Android AAB → Google Play | `app-id`, `gradle-task`, `version-code-offset`, `release-environment`, `disable-release` |
| `flutter-ios-build.yml` | Flutter iOS → TestFlight. `flutter build ipa` on a macOS runner; uploads from `ubuntu-latest` via App Store Connect API. Version from `pubspec.yaml` + `run_number` | `macos-runner`, `xcode-version`, `app-slug`, `release-environment`, `disable-release` |
| `flutter-android-build.yml` | Flutter Android AAB → Google Play. `flutter build appbundle` with `key.properties` signing | `app-id`, `app-slug`, `version-code-offset`, `release-environment`, `disable-release` |

All four mobile workflows have a `build` job (no gating) and a `release_with_environment` job gated by `if: release-environment != '' && !disable-release` and bound to the named GitHub Environment. They use **marketplace** release actions (`apple-actions/upload-testflight-build@v5`, `r0adkll/upload-google-play@v1`) — there is **no** Docker-based upload action. The Flutter and RN iOS workflows both reuse `ios-install-cert` / `ios-install-profile` for signing; Flutter sets up the SDK with `subosito/flutter-action@v2`. Per-branch environment selection (e.g. `android-staging` vs `android-production`) is done by the caller template's `workflow_dispatch` jobs, gated on `github.ref_name`.

---

## Workflow Templates

`workflow-templates/` holds the six starter workflows GitHub surfaces in the "New workflow" picker for org repos. Each is a `<name>.yml` + `<name>.properties.json` pair (the `.properties.json` supplies `name`, `description`, `iconName`, `categories`). Each template's job `uses:` a reusable workflow at `@main`.

| Template | Calls reusable workflow | Trigger |
|---|---|---|
| `service-cicd` | `reusable-service-cicd.yml` | `push` on `main` + `workflow_dispatch` |
| `generic-chart-cicd` | `generic-chart-helm.yml` | `push` on `staging`, `main` + `workflow_dispatch` |
| `next-cloudflare` | `next-cloudflare-worker.yaml` | `push` on `staging`, `main` + `workflow_dispatch` |
| `vite-cloudflare` | `vite-cloudflare-worker.yml` | `push` on `staging`, `main` + `workflow_dispatch` |
| `android-app` | `android-build.yml` | `workflow_dispatch` only |
| `ios-app` | `ios-build.yml` | `workflow_dispatch` only |

**When you add, rename, or change the interface of a reusable workflow that has a template, update the matching `workflow-templates/<x>.yml` AND its `.properties.json` in the same change.** The two Cloudflare and the two Helm-service templates gate per-branch with `if: github.ref`/`github.ref_name`; the two mobile templates are `workflow_dispatch`-only and gate the dev/prod jobs on `github.ref_name`.

---

## Composite Action Reference

All 18 actions are composite. Call them in job steps with `uses: simplify9/.github/.github/actions/<name>@main`.

### Versioning & Tagging
- `determine-semver` — Computes the next `major.minor.patch` from git tags. Inputs: `major`, `minor`, `release-branch`, `current-ref`, `build-id`. Outputs: `version`, `git-tag`, `is-release`.
- `tag-github-origin` — Creates a lightweight git tag via the GitHub REST API (no checkout). Inputs: `github-token`, `repository`, `tag`, `sha`. Outputs: `created`, `ref`.

### Docker
- `docker-build-push` — Build + push (optionally multi-platform via Buildx/QEMU) up to three tags (version, branch name, `latest`). Inputs: `image-name`, `version`, `username`, `password`, `registry`, `platforms`, `build-args`, `build-secrets`. Outputs: `image-tags`, `image-digest`.

### Helm
> **Maintenance smell — three overlapping deploy actions.** `helm-deploy`, `helm-deploy-s9generic`, and `helm-generic` all wrap `helm upgrade --install` and re-implement the same concerns (kubeconfig decode, Helm/kubectl install, atomic rollback, `--set`/`--set-string` handling, release verification). They diverge in incidental details — input naming (`kebab-case` vs `snake_case`), chart source (OCI / ChartMuseum / Helm repo / local path), Helm version strategy, and whether a pre-deploy migration Job is supported. Every hardening fix has to be applied in three places. **Recommended direction:** consolidate into one parameterized deploy action covering every chart source with optional migration Job, standardizing on one input-naming convention and one secret path (`--set-string`); keep the old names as thin shims so existing callers aren't broken.

- `helm-generic` — `helm upgrade --install` of `s9genericchart` (default) from `https://charts.sf9.io`, with an optional pre-deploy DB migration Job (`init_job_image` + related `init_job_*` inputs). **Requires Helm 4**, always uses `--rollback-on-failure`. snake_case inputs (`app_name`, `namespace`, `kubeconfig_data`, `extra_set_values`, `secret_set_values`). Used by `generic-chart-helm.yml` and `generic-gateway-helm-template.yml`. Output: `chart-ref`.
- `helm-deploy` — Deploy from an OCI registry **or** ChartMuseum (`chart-source-type`). Detects Helm 3 vs 4. kebab-case inputs. Used by `reusable-service-cicd.yml` and `helm-deploy-values.yml`. Output: `chart-url`.
- `helm-deploy-s9generic` — Deploy from an OCI registry **or** a local chart directory (`chart-path` mode), with on-failure cluster diagnostics. Output: `chart-url`, `deployed-image`.
- `helm-package-push` — Package a chart and publish to OCI (`helm push`) or ChartMuseum (HTTP upload); optionally rewrites Chart.yaml version/appVersion and values.yaml image fields. Outputs: `chart-package`, `chart-url`.

### Gateway API (Cilium)
- `gateway-routing` — Pure rendering (no cluster access; logic in `render.sh`): produces the gateway/ingress/configmap Helm values file and the host/section lists. Outputs: `values-file`, `gateway-host-list`, `gateway-section-names-list`.
- `gateway-onboard` — Cluster-mutating (logic in `onboard.sh`): ensures the parent Gateway has the HTTP/HTTPS listeners and cert-manager Certificates for the requested hostnames before deploy. No outputs. Consumes the host/section lists from `gateway-routing`.

### .NET
- `dotnet-build` — Resolves a build target (existing `*.sln` or an ephemeral generated one), then `restore` → `build` → optional `test`. Output: `build-target`.
- `dotnet-pack-push` — `dotnet pack --no-build` → `dotnet nuget push --skip-duplicate`; empty `projects` is a graceful skip. Outputs: `packages-pushed`, `package-paths`.

**Project-list inputs** (`projects` / `test-projects` on `dotnet-build`, `projects` on `dotnet-pack-push`, and the `nuget-projects` workflow input) accept one or more glob patterns as a **space- OR newline-separated** list. A YAML `|` block scalar (one project per line) is honoured in full. These are split with `read -rd '' -a` — plain `read -ra` stops at the first newline and silently drops every entry after the first, so never revert to it.

### Cloudflare
- `generate-wrangler-config` — Generates `wrangler.toml` dynamically (plain Workers, OpenNext via `build-for-opennext`, static assets, SPA `not-found-handling`, route lists). Output: `config-path`.
- `setup-cloudflare-domain` — Adds a custom domain to a Cloudflare Pages project via the CF REST API (idempotent). Input `fail-on-error` (default `false`) makes failure non-blocking. Output: `domain-status`.

### iOS
- `ios-install-cert` — Imports a base64 `.p12` into a temporary keychain. Inputs: `p12Base64`, `p12Password`, `keychainPath`. Exports `KEYCHAIN_PATH` to `$GITHUB_ENV`.
- `ios-install-profile` — Installs a base64 `.mobileprovision` and extracts its UUID/Name. Input: `profileBase64`. Exports `IOS_PROFILE_UUID` / `IOS_PROFILE_NAME` to `$GITHUB_ENV`.
- `xcode-build` — `xcodebuild archive` (manual signing by default). Inputs: `workspace`, `scheme`, `configuration`, `archivePath`, `signingStyle`, `developmentTeam`, `provisioningProfileUuid`, `keychainPath`.
- `xcode-export` — `xcodebuild -exportArchive` → `.ipa`. Inputs: `archivePath`, `exportOptionsPlist`, `exportPath`.

(There is no `xcode-setup` action — CocoaPods, Ruby/Bundler, and Xcode selection are handled inline by `ios-build.yml`.)

### Shared
- `write-job-summary` — Appends a standardized, status-aware section to `$GITHUB_STEP_SUMMARY`. Inputs: `title`, `status` (`${{ job.status }}` → ✅ SUCCESS / ❌ FAILED), `icon`, `details`. Used by every reusable workflow.

---

## iOS-Specific Rules

- Always use **manual signing** in CI (`signingStyle: manual` in `xcode-build`). Automatic signing requires an interactive Xcode session.
- Certificate and profile installation must use `ios-install-cert` and `ios-install-profile` before the archive step.
- The build job runs on a macOS runner (`macos-runner`, default `macos-latest`); the **release job runs on `ubuntu-latest`** and uploads to TestFlight via `apple-actions/upload-testflight-build@v5` (App Store Connect API) — no macOS tooling needed for the upload.
- `xcode-version` accepts a major (`26`) or major.minor (`16.4`) selector (resolved by `maxim-lobanov/setup-xcode@v1`).
- **CocoaPods caching:** two independent `actions/cache@v5` steps key on `Podfile.lock` — `~/.cocoapods/repos` (global spec repo, always restored) and `ios/Pods` (project Pods dir, skipped when `clean-reinstall-pods: true`).
- **ccache (`enable-ccache`, default `true`):** caches ObjC/C++ pod compilation under `~/Library/Caches/ccache`. No benefit for Swift targets. The workflow patches the Podfile to set `:ccache_enabled => true` when enabled.
- **Ruby/Bundler:** set `ruby-version` + `use-bundler: true` to manage CocoaPods via Bundler (`ruby/setup-ruby@v1` with `bundler-cache`).

## Android-Specific Rules

- `VERSION_CODE` = `github.run_number + version-code-offset`. Set `version-code-offset` high (default `80000`) when migrating from another CI system to avoid versionCode collisions on the Play Console. `VERSION_NAME` derives from `version-prefix` as a SemVer patch counter — `major.minor` fixed, `patch = base patch + run_number` (no carry/rollover, no upper bound) — unless `version-name-override` is set.
- Release uses `r0adkll/upload-google-play@v1` (a marketplace action) — **not** a Docker-based action. Track via `play-track` (default `internal`); set `changes-not-sent-for-review: true` for internal tracks.
- Gradle uses `gradle/actions/setup-gradle@v5` (Gradle home caching). Do **not** use `gradle/gradle-build-action` (archived). Do **not** add `cache: gradle` to `actions/setup-java` — it invokes `gradle-build-action` internally and conflicts with `setup-gradle`. Do not add a manual `actions/cache` step for `~/.gradle` — `setup-gradle` owns Gradle home caching.
- The workflow **itself** sets `org.gradle.caching=true` in the project's `gradle.properties` (the caller no longer needs to add it manually).
- **NDK is pinned to `27.1.12297006` (r27b LTS)** for RN 0.85 and installed via `sdkmanager`, not `actions/cache` — `/usr/local/lib/android/sdk/` is root-owned on GitHub-hosted runners, so `tar` extraction fails with `Cannot utime` / `Cannot change mode`. `sdkmanager` has the correct elevated permissions.
- **Node.js 24 opt-in:** both jobs set `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true` so `actions/cache`, `actions/setup-java@v5`, and `gradle/actions/setup-gradle@v5` use Node 24 ahead of GitHub's Node 20 retirement.
- `use-jetifier` (default `true`) runs `npx jetify` for AndroidX migration; disable for projects that don't need it.

---

## Adding a New Composite Action

1. Create `.github/actions/<kebab-name>/action.yml`
2. Set `name:`, `description:`, `author: 'Simplify9'`
3. `runs.using: "composite"` — every `run:` step needs `shell: bash`
4. Declare all inputs with `description:` and either `default:` or `required: true`
5. If it installs a CLI tool (Helm, kubectl), use an input with a `latest` (or workflow-pinned) default so callers can override
6. Do not hardcode registry URLs or credentials — accept them as inputs
7. Follow the 4-pillar log framework with a namespaced `<PREFIX>_CP{N}_STATUS`

## Adding a New Reusable Workflow

1. Create `.github/workflows/<kebab-name>.yml`
2. Primary trigger: `on: workflow_call:` with full `inputs:` and `secrets:` blocks
3. Compute the version with `determine-semver` (`release-branch: github.event.repository.default_branch`) rather than `if:`-gating on `github.ref`
4. Bind deploy/release jobs to a GitHub Environment input and gate optional deploys with a boolean (`deploy:`) or an empty-environment check
5. Upload artifacts with `retention-days: 1` unless the artifact has a cross-pipeline use case
6. Call `write-job-summary` (with `status: ${{ job.status }}`) at the end of each job
7. If the workflow should be offered as a starter, add a paired `workflow-templates/<name>.yml` + `.properties.json`

---

## What NOT To Do

- **Do not hardcode CLI versions** (Helm, kubectl, Node) inside action `run:` scripts — use action inputs with defaults so callers can override
- **Do not add `on: push:` or `on: pull_request:` triggers** to files in `.github/workflows/` — all triggers come from caller repos (templates in `workflow-templates/` are the place for `push`/`workflow_dispatch`)
- **Do not use `gradle/gradle-build-action`** — it is archived; use `gradle/actions/setup-gradle@v5`
- **Do not add `cache: gradle` to `actions/setup-java`** — it invokes `gradle-build-action` internally and silently disables the `setup-gradle` cache restore
- **Do not add a manual `actions/cache` step for `~/.gradle`** — `setup-gradle` already owns Gradle home caching
- **Do not use `actions/cache` for `/usr/local/lib/android/sdk/` paths** — root-owned on GitHub-hosted runners; use `sdkmanager` to install NDK/CMake directly
- **Do not pass secrets as regular inputs** — declare them under `on.workflow_call.secrets:`
- **Do not mix Helm config and secret values** in a single `--set` call — use `--set-string` (`helm-set-secret-values` / `secret_set_values` / `secret-set-string-values`) for anything sensitive or containing special characters
- **Do not call composite actions via local `./.github/actions/...` paths from inside the reusable workflows** — use the external `simplify9/.github/.github/actions/<name>@main` form so runs use the published actions
- **Do not reintroduce a Docker-based mobile upload action** — TestFlight and Play uploads use the pinned marketplace actions

---

## Keeping Documentation Up to Date

**After every change to this repository, update `README.md` (caller-facing) and this `AGENTS.md` (conventions) to reflect the current state.** `CLAUDE.md` points at this file as the authoritative contract, so keep it accurate.

Specifically, update the docs whenever you:

- Add, remove, or rename a workflow, composite action, or workflow-template
- Add, change, or remove an input or secret on any workflow or action
- Change a pinned action version or a CLI tool version default
- Change the default value of any documented input
- Change deployment infrastructure (registry, cluster, chart repo URL, chart name)

An outdated README is a source of broken pipelines and wasted debugging time — treat it as part of the same change, not an afterthought.
