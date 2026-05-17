# Simplify9 `.github` Repository — Agent Instructions

This repository is the **organization-wide shared CI/CD library** for Simplify9. It contains only reusable GitHub Actions workflows and composite actions. No application code lives here.

---

## Repository Layout

```
.github/               ← workspace root (README.md lives here)
└── .github/
    ├── workflows/     ← reusable workflows  (workflow_call triggers only)
    └── actions/       ← composite actions   (uses: in steps)
```

Every file in `workflows/` is a **reusable workflow** — it has `on: workflow_call:` (and optionally `on: workflow_dispatch:`) and is never run standalone. Every directory in `actions/` is a **composite action** with its own `action.yml`.

---

## How Callers Reference This Repo

From any repo in the `simplify9` org:

```yaml
# Reusable workflow
uses: simplify9/.github/.github/workflows/<name>.yml@main

# Composite action (inside a step)
uses: simplify9/.github/.github/actions/<name>@main
```

Always use `@main`. Never use a SHA pin or version tag — this repo has no release tags.

---

## Architecture: Two-Layer Pattern

```
Caller workflow
    └── reusable workflow (workflows/*.yml)
            ├── composite action (actions/determine-semver)
            ├── composite action (actions/docker-build-push)
            ├── composite action (actions/helm-package-push)
            └── composite action (actions/helm-deploy-s9generic)
```

Composite actions are the smallest units of work. Reusable workflows orchestrate jobs and call composite actions. Callers only call reusable workflows (never composite actions directly, except for simple utility actions like `determine-semver` or `tag-github-origin`).

---

## Pinned Action Versions

**Do not change these without a full compatibility audit.** All `uses:` references in this repo must use the versions below:

| Action | Version | Notes |
|---|---|---|
| `actions/checkout` | `@v6` | |
| `actions/setup-node` | `@v6` | |
| `actions/setup-dotnet` | `@v5` | |
| `actions/setup-java` | `@v4` | |
| `actions/upload-artifact` | `@v7` | |
| `actions/download-artifact` | `@v8` | Always download by `name:`, never by `artifact-ids:` |
| `azure/setup-helm` | `@v5` | |
| `azure/setup-kubectl` | `@v5` | |
| `docker/setup-buildx-action` | `@v4` | |
| `docker/login-action` | `@v4` | |
| `docker/metadata-action` | `@v6` | |
| `docker/build-push-action` | `@v7` | |
| `cloudflare/wrangler-action` | `@v4` | |
| `cloudflare/pages-action` | `@v1` | Repo is archived; v1 is the final version — do not upgrade |
| `gradle/actions/setup-gradle` | `@v3` | Do NOT use `gradle/gradle-build-action` (archived). Do NOT upgrade to v5/v6: v5 requires runner ≥ 2.327.1; v6 has commercial caching license terms |

**Pinned CLI binary versions (defaults in action inputs):**
- Helm CLI: `v3.21.0`
- kubectl CLI: `v1.33.0`

---

## Conventions — Must Follow for Every Change

### Composite Actions
- File: `.github/actions/<name>/action.yml`
- `runs.using: "composite"` always
- Every `run:` step must have `shell: bash`
- Every input must have `description:` and a sensible `default:` (or `required: true`)
- Outputs must have a `value:` expression pointing to a step output

### Reusable Workflows
- File: `.github/workflows/<name>.yml`
- Must have `on: workflow_call:` as the primary trigger
- All inputs must have `description:`, `type:`, and `required:` set explicitly
- Secrets are declared under `on.workflow_call.secrets:` — never passed as inputs
- Jobs that deploy must be **disabled by default**: `deploy-to-development: false`, `deploy-to-staging: false`, `deploy-to-production: false`
- Branch-to-environment mapping is enforced by job `if:` conditions:
  - `development` branch → dev environment
  - `staging` branch → staging environment
  - `main` or `master` branch → production environment

### Secrets vs Inputs for Helm
This is a critical pattern. **Never mix Helm config and secrets in a single parameter:**

| Parameter | Helm flag | Used for |
|---|---|---|
| `helm-set-values` (workflow input) | `--set` | Non-sensitive config: replicas, ingress, environment label |
| `helm-set-secret-values` (workflow secret) | `--set-string` | Secrets: DB connection strings, API keys, anything with special characters |

Use `--set-string` for secrets because it bypasses shell parsing and prevents `SSL:` or `=` characters from causing failures.

### Artifact Upload/Download Pairing
When adding upload/download artifact pairs:
- Always use a matching `name:` input — never `artifact-ids:`
- Upload with `actions/upload-artifact@v7`, download with `actions/download-artifact@v8`
- Set `retention-days: 1` for build artifacts not needed beyond the pipeline run

### Versioning
All Docker and Helm versioning flows through `actions/determine-semver`:
- Reads git tags in `major.minor.*` pattern
- Auto-increments patch from the highest matching tag
- Outputs `version` (e.g., `1.4.7`) — no `v` prefix
- The `tag-github-origin` action then creates the tag after a successful deployment

---

## Deployment Infrastructure

- **Kubernetes**: DigitalOcean managed cluster
- **Ingress/Gateway**: Cilium Gateway API (both classic Ingress and Gateway API routing coexist in some workloads)
- **Helm chart registry**: `https://charts.sf9.io` (ChartMuseum) and OCI
- **Default generic chart**: `s9genericchart` from `https://charts.sf9.io`
- **Container registry**: `ghcr.io` (default), `docker.io` (Docker Hub), or `registry.digitalocean.com/<namespace>`
- **kubeconfig**: Passed as a base64-encoded secret named `kubeconfig`

---

## Workflow Reference

### Frontend / Cloudflare

| Workflow | Purpose | Key inputs |
|---|---|---|
| `vite-ci.yml` | Vite (React/Vue/Svelte) → Cloudflare Pages | `project-name`, `build-directory`, `package-manager` |
| `next-cloudflare-worker.yaml` | Next.js SSR → Cloudflare Workers | Uses `@cloudflare/next-on-pages`, OpenNext |
| `next-static-cloudflare-worker.yaml` | Next.js static → Cloudflare Workers | Static export variant |
| `vite-cloudflare-worker.yml` | Vite → Cloudflare Workers | `generate-wrangler-config` action for dynamic `wrangler.toml` |

### API / Backend

| Workflow | Purpose | Key inputs |
|---|---|---|
| `api-cicd.yml` | Docker + Helm → Kubernetes | `chart-name` (required), `container-registry`, deploy flags |
| `sw-cicd.yml` | .NET → NuGet + Docker + Helm → Kubernetes | `dotnet-version`, `nuget-projects`, `chart-name` |
| `ci-docker.yaml` | Docker build+push only | No deployment |
| `ci-helm.yaml` | Helm package+push only | No Docker, no deployment |
| `helm-deploy-values.yml` | Helm deploy from a values file | `release-name`, `chart-name`, `chart-repo`, `values-file` |

### Mobile

| Workflow | Purpose | Key inputs |
|---|---|---|
| `generic-ios-testflight.yml` | iOS → TestFlight | `macos-runner`, `xcode-version`, `bundle-id`, signing inputs |
| `generic-android-google-play.yml` | Android AAB → Google Play | `app-id`, `gradle-task`, `version-code-offset`, `keystore-*` |
| `ios-testflight-dispatch-template.yml` | `workflow_dispatch` entry point for iOS | Wraps `generic-ios-testflight.yml` |
| `android-google-play-dispatch-template.yml` | `workflow_dispatch` entry point for Android | Wraps `generic-android-google-play.yml` |

### Helm Chart Development

| Workflow | Purpose |
|---|---|
| `generic-chart-helm.yml` | CI/CD for a generic Helm chart (lint → package → push to ChartMuseum) |
| `generic-gateway-chart-cicd.yml` | CI/CD for a Gateway API-aware Helm chart; validates routing modes and ConfigMap gating |
| `generic-gateway-helm-template.yml` | Helm template rendering validation only (no push) |

---

## Composite Action Reference

### Versioning & Tagging
- `determine-semver` — Computes next `major.minor.patch` from git tags. Inputs: `major`, `minor`. Output: `version`.
- `tag-github-origin` — Creates and pushes a git tag. Input: `tag-name`.

### Docker
- `docker-build-push` — Full Docker build+push with BuildKit cache, multi-platform support, OCI metadata labels. Outputs: `image-tags`, `image-digest`.

### Helm
- `helm-deploy` — Profile-based deploy (`registry_profile` selects dynamic secrets). Supports `init_job_image` for database migration Jobs before deploy.
- `helm-deploy-s9generic` — Deploy using `s9genericchart` from `https://charts.sf9.io`. Handles `set-values` (`--set`) and `set-string-values` (`--set-string`) separately.
- `helm-generic` — Checkout + lint + package + push (single composite for chart CI).
- `helm-package-push` — Package a chart and push to OCI registry.

### .NET
- `dotnet-build` — `dotnet restore` → `dotnet build` → optional `dotnet test`. Detects solution files automatically.
- `dotnet-pack-push` — `dotnet pack` → `dotnet nuget push`.

### Cloudflare
- `setup-cloudflare-project` — Creates or verifies a Cloudflare Pages project.
- `setup-cloudflare-domain` — Configures a custom domain on a Pages project. Has `fail-on-error` to make domain failure non-blocking.
- `generate-wrangler-config` — Generates `wrangler.toml` dynamically. Supports OpenNext, static assets, and custom route lists.

### iOS
- `xcode-setup` — CocoaPods install + optional Xcode selector.
- `xcode-build` — `xcodebuild archive` with manual signing. Uses `keychainPath`, `provisioningProfileUuid`, `developmentTeam`.
- `xcode-export` — `xcodebuild -exportArchive` to produce `.ipa`.
- `ios-install-cert` — Imports `.p12` signing certificate into a temporary keychain.
- `ios-install-profile` — Installs a `.mobileprovision` to `~/Library/MobileDevice/Provisioning Profiles/`.

### Android
- `upload-google-play-release` — **Docker-based action** (not composite). Contains `Dockerfile`, `entrypoint.sh`, and `play_upload.py`. Calls Google Play Android Publisher API. Input `service_account_json` must come from secrets.

---

## iOS-Specific Rules

- Always use **manual signing** in CI (`signingStyle: manual`). Automatic signing requires an interactive Xcode session.
- Certificate and profile installation must use `ios-install-cert` and `ios-install-profile` before calling `xcode-build`.
- The `xcode-setup` action (with `use-simplify9-xcode-setup: true`) handles pod install and Xcode path selection.
- `xcode-version` input accepts a major version (`26`) or major.minor (`16.4`). Selector searches `/Applications/Xcode_*.app` variants.

---

## Android-Specific Rules

- `version-code` = `github.run_number + version-code-offset`. Set `version-code-offset` high (default `80000`) when migrating from another CI system to avoid versionCode collisions on the Play Console.
- The `gradle/actions/setup-gradle@v3` action is used — **not** `gradle/gradle-build-action` (that repo is archived).
- `upload-google-play-release` is a Docker action. If you modify `play_upload.py`, rebuild context is automatic (GitHub rebuilds the Docker image per run). Do not cache the image manually.

---

## Adding a New Composite Action

1. Create `.github/actions/<kebab-name>/action.yml`
2. Set `name:`, `description:`, `author: 'Simplify9'`
3. `runs.using: "composite"` — every `run:` step needs `shell: bash`
4. Declare all inputs with `description:` and either `default:` or `required: true`
5. If it installs a CLI tool (Helm, kubectl), use the pinned versions from the table above
6. Do not hardcode registry URLs or credentials — accept them as inputs
7. Reference self-contained: do not call other composite actions from within a composite action unless the dependency is stable and clearly documented

## Adding a New Reusable Workflow

1. Create `.github/workflows/<kebab-name>.yml`
2. Primary trigger: `on: workflow_call:` with full `inputs:` and `secrets:` blocks
3. Add `on: workflow_dispatch:` with matching inputs if humans need to trigger it manually
4. All deploy jobs must be guarded by both a boolean input (`deploy-to-*: false` default) and a `github.ref_name` branch check
5. Upload artifacts with `retention-days: 1` unless the artifact has a cross-pipeline use case
6. Follow the job naming convention: `version` → `build` → `deploy-development` → `deploy-staging` → `deploy-production`
7. Pass secrets using `secrets: inherit` only if the caller docs explicitly say so; otherwise declare each secret explicitly

---

## What NOT To Do

- **Do not hardcode versions** of Helm, kubectl, or Node inside action `run:` scripts — use action inputs with defaults so callers can override
- **Do not add `on: push:` or `on: pull_request:` triggers** to files in `workflows/` — all triggers must come from caller repos
- **Do not use `gradle/gradle-build-action`** — it is archived; use `gradle/actions/setup-gradle@v3`
- **Do not upgrade `gradle/actions/setup-gradle` to v6** without explicit approval — v6 contains a proprietary caching component under Gradle's commercial Terms of Use
- **Do not enable any deployment by default** — all `deploy-to-*` inputs default to `false`
- **Do not pass secrets as regular inputs** — declare them under `on.workflow_call.secrets:` or use `secrets: inherit`
- **Do not mix Helm config and secret values** in a single `--set` call — use `--set-string` for anything that contains special characters or is sourced from a secret
- **Do not use `cloudflare/pages-action` above `@v1`** — the repo is archived at v1.5.0; there is no v2

---

## Keeping README.md Up to Date

**After every change to this repository, update `README.md` to reflect the current state of the codebase.**

Specifically, update `README.md` whenever you:

- Add, remove, or rename a workflow (`.github/workflows/`)
- Add, remove, or rename a composite action (`.github/actions/`)
- Add, change, or remove an input or secret on any workflow or action
- Change a pinned action version or CLI tool version
- Change the default value of any input that is documented in the README
- Change deployment infrastructure (registry, cluster, chart repo URL)

The README must always be an accurate reflection of what callers will experience. An outdated README is a source of broken pipelines and wasted debugging time — treat it as part of the same change, not an afterthought.
