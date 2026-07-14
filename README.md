# Simplify9 Reusable CI/CD Library

> Organization-wide shared GitHub Actions workflows, composite actions, and starter templates for Simplify9 projects.
> Callers reference this repo with `@main` — no versioned tags exist.

![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?style=flat-square&logo=githubactions&logoColor=white)
![React Native](https://img.shields.io/badge/React_Native-61DAFB?style=flat-square&logo=react&logoColor=black)
![iOS](https://img.shields.io/badge/iOS-000000?style=flat-square&logo=apple&logoColor=white)
![Android](https://img.shields.io/badge/Android-3DDC84?style=flat-square&logo=android&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat-square&logo=kubernetes&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-277A9F?style=flat-square&logo=helm&logoColor=white)
![Cloudflare](https://img.shields.io/badge/Cloudflare-F38020?style=flat-square&logo=cloudflare&logoColor=white)
![Next.js](https://img.shields.io/badge/Next.js-000000?style=flat-square&logo=nextdotjs&logoColor=white)
![Vite](https://img.shields.io/badge/Vite-646CFF?style=flat-square&logo=vite&logoColor=white)
![.NET](https://img.shields.io/badge/.NET-512BD4?style=flat-square&logo=dotnet&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-339933?style=flat-square&logo=nodedotjs&logoColor=white)

---

## Table of Contents

- [Which Workflow Should I Use?](#which-workflow-should-i-use)
- [Starter Templates](#starter-templates)
- [Prerequisites — Secrets](#prerequisites--secrets)
- [Repository Structure](#repository-structure)
- [Workflow Reference](#workflow-reference)
  - [Frontend · Cloudflare Workers](#frontend--cloudflare-workers)
  - [Service & Backend · Kubernetes](#service--backend--kubernetes)
  - [Helm Chart CI/CD](#helm-chart-cicd)
  - [Mobile · iOS & Android](#mobile--ios--android)
  - [Security](#security)
- [Composite Action Reference](#composite-action-reference)
- [Dependabot](#dependabot)
- [Core Architecture & Conventions](#core-architecture--conventions)
- [Repository Metadata Standard](#repository-metadata-standard)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

---

## Which Workflow Should I Use?

| Stack | Deployment target | Use this workflow |
|---|---|---|
| Next.js (SSR, OpenNext adapter) | Cloudflare Workers | [`next-cloudflare-worker.yaml`](#next-cloudflare-workeryaml) |
| Vite single-page app | Cloudflare Workers (static assets) | [`vite-cloudflare-worker.yml`](#vite-cloudflare-workeryml) |
| Containerized service (any stack, .NET-friendly) | Docker + Helm (GHCR OCI / ChartMuseum), optional K8s deploy | [`reusable-service-cicd.yml`](#reusable-service-cicdyml) |
| Service deployed over ingress-nginx | Docker + `s9genericchart` → Kubernetes | [`generic-chart-helm.yml`](#generic-chart-helmyml) |
| Service deployed behind the Cilium Gateway API | Docker + `s9genericchart-v2` → Kubernetes | [`generic-gateway-helm-template.yml`](#generic-gateway-helm-templateyml) |
| Deploy an already-published chart from a values file | Kubernetes via Helm | [`helm-deploy-values.yml`](#helm-deploy-valuesyml) |
| Cilium Gateway API-aware Helm chart (chart dev) | ChartMuseum | [`gateway-chart-cicd.yml`](#gateway-chart-cicdyml) |
| iOS app (React Native or native) | TestFlight | [`ios-build.yml`](#ios-buildyml) |
| Android app (React Native) | Google Play | [`android-build.yml`](#android-buildyml) |
| iOS app (Flutter) | TestFlight | [`flutter-ios-build.yml`](#flutter-ios-buildyml) |
| Android app (Flutter) | Google Play | [`flutter-android-build.yml`](#flutter-android-buildyml) |

All workflows are **reusable** (`on: workflow_call:`). Call them from your repo:

```yaml
uses: simplify9/.github/.github/workflows/<name>.yml@main
```

---

## Starter Templates

This repo also ships **org workflow templates** (`workflow-templates/`) that appear in GitHub's **Actions → New workflow** picker for any `simplify9` repo. Each template is a thin caller wired to a reusable workflow with example inputs pre-filled — start from one and edit.

| Template (in "New workflow") | Wraps | Default triggers |
|---|---|---|
| Service CI/CD Pipeline | `reusable-service-cicd.yml` | `push` → `main`, `workflow_dispatch` |
| Generic Chart Helm CI/CD | `generic-chart-helm.yml` | `push` → `staging`/`main`, `workflow_dispatch` |
| Next.js + Cloudflare Workers | `next-cloudflare-worker.yaml` | `push` → `staging`/`main`, `workflow_dispatch` |
| Vite + Cloudflare Workers | `vite-cloudflare-worker.yml` | `push` → `staging`/`main`, `workflow_dispatch` |
| Android App CI/CD | `android-build.yml` | `workflow_dispatch` |
| iOS App CI/CD | `ios-build.yml` | `workflow_dispatch` |
| Flutter Android App CI/CD | `flutter-android-build.yml` | `workflow_dispatch` |
| Flutter iOS App CI/CD | `flutter-ios-build.yml` | `workflow_dispatch` |
| Critical Vulnerability Check | `critical-vuln-gate.yml` | `pull_request` → `main`, `develop` |
| Dependabot Auto-Merge | `critical-vuln-gate.yml` | `pull_request` → `main`, `develop` |

---

## Prerequisites — Secrets

Set these as **Organization** or repository secrets. Names below are the secret keys the workflows expect under `secrets:` (some workflows accept `secrets: inherit`).

### Frontend (Cloudflare Workers)

```text
cloudflare_api_token     # API token with Workers + DNS permissions
cloudflare_account_id    # Cloudflare account ID
dependabot-alerts-token  # PAT/App token with "Dependabot alerts: read", for the build-time critical-vuln gate (pass secrets.DEPENDABOT_ALERTS_TOKEN — GITHUB_TOKEN cannot access this API)
```

### Service / Backend (Kubernetes + Container Registry + Helm)

```text
registry-username        # Container registry username (GHCR: github.actor)
registry-password        # Container registry password/token (GHCR: GITHUB_TOKEN)
kubeconfig               # Base64-encoded (or raw YAML) kubeconfig — ingress-nginx deploys
kubeconfig-gateway       # Base64 kubeconfig for the gateway-api routing mode (reusable-service-cicd)
chartmuseum-username     # ChartMuseum username (when publishing/pulling via ChartMuseum)
chartmuseum-password     # ChartMuseum password/token
helm-set-secret-values   # Sensitive Helm values, applied with --set-string
github-token             # Tags the origin after deploy (falls back to built-in GITHUB_TOKEN) — not used by `helm-deploy-values.yml`
dependabot-alerts-token  # PAT/App token with "Dependabot alerts: read", for the build-time critical-vuln gate (pass secrets.DEPENDABOT_ALERTS_TOKEN — GITHUB_TOKEN cannot access this API)
nuget-api-key            # NuGet API key (only if publishing packages)
```

### Mobile — iOS

```text
ios-p12-base64                    # Base64-encoded .p12 signing certificate
ios-p12-password                  # Password for the .p12
ios-mobileprovision-base64        # Base64-encoded .mobileprovision
ios-team-id                       # (optional) explicit Apple Team ID
appstore-api-key-id               # App Store Connect API Key ID
appstore-issuer-id                # App Store Connect Issuer ID
appstore-api-private-key-base64   # Base64-encoded App Store Connect .p8 private key
```

### Mobile — Android

```text
android-keystore-base64           # Base64-encoded .jks / .keystore
android-keystore-password         # Keystore password
android-key-alias                 # Key alias
android-key-password              # Key password
google-play-service-account-json  # Google Play service account JSON
```

---

## Repository Structure

```text
.github/                          ← workspace root (README.md, AGENTS.md, CLAUDE.md)
├── .github/
│   ├── workflows/                ← reusable workflows (workflow_call)
│   │   ├── next-cloudflare-worker.yaml
│   │   ├── vite-cloudflare-worker.yml
│   │   ├── reusable-service-cicd.yml
│   │   ├── generic-chart-helm.yml
│   │   ├── generic-gateway-helm-template.yml
│   │   ├── helm-deploy-values.yml
│   │   ├── gateway-chart-cicd.yml
│   │   ├── ios-build.yml
│   │   ├── android-build.yml
│   │   ├── flutter-ios-build.yml
│   │   ├── flutter-android-build.yml
│   │   └── critical-vuln-gate.yml
│   ├── actions/                  ← composite actions
│   │   ├── determine-semver/
│   │   ├── tag-github-origin/
│   │   ├── docker-build-push/
│   │   ├── helm-deploy/
│   │   ├── helm-deploy-s9generic/
│   │   ├── helm-generic/
│   │   ├── helm-package-push/
│   │   ├── gateway-routing/      (render.sh)
│   │   ├── gateway-onboard/      (onboard.sh)
│   │   ├── dotnet-build/
│   │   ├── dotnet-pack-push/
│   │   ├── generate-wrangler-config/
│   │   ├── setup-cloudflare-domain/
│   │   ├── ios-install-cert/
│   │   ├── ios-install-profile/
│   │   ├── xcode-build/
│   │   ├── xcode-export/
│   │   ├── write-job-summary/
│   │   └── check-critical-vulns/
│   └── dependabot.yml            ← this repo's own Dependabot config (github-actions only)
├── workflow-templates/           ← org starter templates (*.yml + *.properties.json)
└── dependabot-templates/         ← ready-made per-category `dependabot.yml` configs for consumer repos to copy
```

---

## Workflow Reference

> Big workflows (the gateway/service pipelines) expose dozens of inputs. The tables below cover the **commonly used** ones; the workflow file itself is the complete, authoritative input list.

---

### Frontend · Cloudflare Workers

---

#### `next-cloudflare-worker.yaml`

Builds a Next.js app with the **OpenNext.js** Cloudflare adapter and deploys it to Cloudflare Workers.

| Input | Required | Default | Description |
|---|---|---|---|
| `project_name` | ✅ | — | Base Worker project name (without env suffix) |
| `environment` | ✅ | — | Wrangler environment (`staging`, `production`) |
| `route` | | `''` | Route / custom domain (falls back to repo var `CLOUDFLARE_ROUTE` then `ROUTE`) |
| `package_manager` | | `yarn` | `npm`, `yarn`, or `pnpm` |
| `node_version` | | `24` | Node.js version |
| `opennextjs_version` | | `1.20.1` | `@opennextjs/cloudflare` adapter version |
| `compatibility_date` | | `2026-05-01` | Cloudflare compatibility date |
| `assets_dir` | | `.open-next/assets` | Static assets directory |
| `build_script` | | `build` | Build npm script |
| `run_lint` | | `true` | Run lint step |

**Required secrets:** `cloudflare_api_token`, `cloudflare_account_id`, `dependabot-alerts-token` (PAT/App token with "Dependabot alerts: read", for the build-time critical-vuln gate — pass `secrets.DEPENDABOT_ALERTS_TOKEN`; `GITHUB_TOKEN` cannot access this API regardless of granted permissions)

```yaml
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/next-cloudflare-worker.yaml@main
    with:
      project_name: my-nextjs-app
      environment: production
      route: myapp.com
    secrets:
      cloudflare_api_token: ${{ secrets.CLOUDFLARE_API_TOKEN }}
      cloudflare_account_id: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
      dependabot-alerts-token: ${{ secrets.DEPENDABOT_ALERTS_TOKEN }}
```

---

#### `vite-cloudflare-worker.yml`

Builds a Vite single-page app and deploys it to Cloudflare Workers **static assets** — SPA routing is handled natively by Cloudflare (`not_found_handling = "single-page-application"`); no custom Worker script is generated.

| Input | Required | Default | Description |
|---|---|---|---|
| `project_name` | ✅ | — | Base Worker project name |
| `environment` | ✅ | — | Wrangler environment |
| `route` | ✅ | — | Route / custom domain |
| `assets_dir` | | `dist` | Vite build output directory |
| `package_manager` | | `yarn` | `npm`, `yarn`, or `pnpm` |
| `node_version` | | `24` | Node.js version |
| `compatibility_date` | | `2026-05-01` | Cloudflare compatibility date |
| `pre_build_commands` | | `''` | Optional shell commands run before the build |
| `run_lint` | | `true` | Run lint step |

**Required secrets:** `cloudflare_api_token`, `cloudflare_account_id`, `dependabot-alerts-token` (PAT/App token with "Dependabot alerts: read", for the build-time critical-vuln gate — pass `secrets.DEPENDABOT_ALERTS_TOKEN`; `GITHUB_TOKEN` cannot access this API regardless of granted permissions)

> Unlike the Next.js workflow, `route` is **required** here.

---

### Service & Backend · Kubernetes

---

#### `reusable-service-cicd.yml`

The consolidated service pipeline: compute semver → optionally publish NuGet → build & push a Docker image → package and publish the Helm chart (GHCR OCI, ChartMuseum, or **both**) → optionally deploy to Kubernetes (ingress-nginx or gateway-api) → tag the git origin.

**Publishing is always on; deploying is opt-in (`deploy: false` by default).**

| Input | Required | Default | Description |
|---|---|---|---|
| `chart-name` | ✅ | — | Helm chart name (must match `Chart.yaml` `name:`) |
| `chart-publish-method` | | `both` | `github-oci`, `chartmuseum`, or `both` (empty/unknown hard-fails) |
| `chart-repo-url` | | — | ChartMuseum base URL (required for `chartmuseum`/`both`) |
| `chart-path` | | `./chart` | Helm chart directory |
| `container-registry` | | `ghcr.io` | Container registry |
| `image-name` | | (repo name) | Docker image name |
| `dotnet-version` | | `8.0.x` | .NET SDK (for NuGet/tests) |
| `nuget-projects` | | `''` | NuGet project glob(s); one or more, space- or newline-separated (YAML `\|` block). Empty = skip NuGet |
| `deploy` | | `false` | Deploy the published chart after publishing |
| `routing-mode` | | `ingress-nginx` | `ingress-nginx` or `gateway-api` |
| `deploy-namespace` | | `playground` | Kubernetes namespace |
| `deploy-environment` | | `Development` | GitHub Environment for the deploy job |
| `helm-set-values` | | `''` | Non-secret `--set` values |
| `gateway-hostnames` | | `''` | Hostnames for the HTTPRoute (gateway-api) |
| `major-version` / `minor-version` | | `1` / `0` | Semver components |

**Secrets** (conditionally required): `registry-username`, `registry-password`, `chartmuseum-username` + `chartmuseum-password` (for `chartmuseum`/`both`), `kubeconfig` (deploy + ingress-nginx) or `kubeconfig-gateway` (deploy + gateway-api), `helm-set-secret-values`, `nuget-api-key`, `github-token` (tags the origin after deploy), `dependabot-alerts-token` (PAT/App token with "Dependabot alerts: read", for the build-time critical-vuln gate — `GITHUB_TOKEN` cannot access this API).

**Required caller permissions:** `contents: write`, `packages: write` (GHCR image/chart push), `security-events: read` (build-time critical-vuln gate) — must be declared in the caller's own top-level `permissions:` block. A job's own permission request inside this reusable workflow can only narrow what the caller grants, never widen it, so a caller missing `packages: write` gets a silent 403 on the GHCR push regardless of what this workflow's own jobs request.

**Outputs:** `version`, `docker-image`, `helm-chart`.

```yaml
jobs:
  publish:
    uses: simplify9/.github/.github/workflows/reusable-service-cicd.yml@main
    with:
      chart-name: my-service
      chart-publish-method: both
      chart-repo-url: https://charts.sf9.io
      major-version: '2'
      minor-version: '1'
    secrets:
      github-token: ${{ secrets.GITHUB_TOKEN }}
      dependabot-alerts-token: ${{ secrets.DEPENDABOT_ALERTS_TOKEN }}
      chartmuseum-username: ${{ secrets.CM_USER }}
      chartmuseum-password: ${{ secrets.CM_PASSWORD }}
      nuget-api-key: ${{ secrets.NUGET_API_KEY }}   # omit to skip NuGet
```

Set `chart-publish-method: github-oci` to publish only to GHCR OCI (no ChartMuseum secrets needed — the OCI push uses the built-in `GITHUB_TOKEN`).

---

#### `generic-chart-helm.yml`

Full CI/CD that builds a Docker image and deploys the shared **`s9genericchart`** over **ingress-nginx**, with optional pre-deploy EF Core migration Job, then tags the version after a successful deploy.

| Input | Required | Default | Description |
|---|---|---|---|
| `app-name` | | — | Application name (`app.name` Helm value) |
| `namespace` | | `development` | Kubernetes namespace |
| `deploy-environment` | | `development` | GitHub Environment for the deploy job |
| `container-registry` | | `ghcr.io` | Container registry |
| `ingress-hosts` | | — | Comma-separated ingress hosts |
| `ingress-paths` | | — | Comma-separated ingress paths |
| `ingress-tls-secrets` | | — | TLS secrets matching hosts by index |
| `service-target-port` | | — | Service `targetPort` |
| `environment` | | — | `environment` Helm value (e.g. `Development`) |
| `helm-set-values` | | — | Extra non-secret `--set` values |
| `package-nuget` | | `false` | Build & publish NuGet packages |
| `init-job-image` | | `''` | If set, runs a K8s migration Job before deploy |
| `init-job-secret-name` | | `''` | Secret holding the migration connection string |
| `major-version` / `minor-version` | | `1` / `0` | Semver components |

**Secrets:** `registry-username`, `registry-password`, `kubeconfig`, `github-token` (tags the origin after deploy), `dependabot-alerts-token` (PAT/App token with "Dependabot alerts: read", for the build-time critical-vuln gate — `GITHUB_TOKEN` cannot access this API), `helm-set-secret-values`, `nuget-api-key`, `nuget-source`, `NUGET_PACKAGE_PAT`.

**Required caller permissions:** `contents: write`, `packages: write` (GHCR image push), `security-events: read` (build-time critical-vuln gate) — must be declared in the caller's own top-level `permissions:` block. A job's own permission request inside this reusable workflow can only narrow what the caller grants, never widen it, so a caller missing `packages: write` gets a silent 403 on the GHCR push regardless of what this workflow's own jobs request.

**Outputs:** `version`, `docker-image`, `nuget-version`.

---

#### `generic-gateway-helm-template.yml`

Gateway-first CI/CD: semver → Docker build/push → Gateway listener + TLS certificate auto-onboarding → Helm deploy of **`s9genericchart-v2`** → tag. The standard pipeline for any service that needs its own hostname on the cluster via the **Cilium Gateway API**.

**Pipeline:** version → (optional NuGet) → build → deploy (`gateway-routing` renders values, `gateway-onboard` provisions listeners + cert, `helm-generic` deploys) → tag.

| Input | Required | Default | Description |
|---|---|---|---|
| `app-name` | | — | Helm release / image name |
| `namespace` | | `development` | Kubernetes namespace |
| `routing-mode` | | `gateway` | `gateway`, `ingress`, or `dual` |
| `gateway-hostnames` | | `''` | Comma/newline hostnames for the HTTPRoute |
| `gateway-section-name` | | `''` | Single shared-listener name (all hosts attach to it) |
| `gateway-section-names` | | `''` | Per-hostname section names, one line per hostname (blank line = dedicated mode) |
| `gateway-paths` | | `''` | Route paths |
| `gateway-parent-name` | | `public-gateway` | Gateway resource name |
| `gateway-parent-namespace` | | `s9-dev-edge` | Gateway resource namespace |
| `gateway-auto-onboarding` | | `true` | Provision listeners + cert for dedicated hosts |
| `gateway-cert-issuer-name` | | `letsencrypt-production-gateway` | cert-manager issuer |
| `gateway-cert-wait` | | `true` | Wait for the certificate to become `Ready` |
| `chart-name` | | `s9genericchart-v2` | Helm chart name |
| `chart-repo` | | `https://charts.sf9.io` | Helm repo URL |
| `init-job-image` | | `''` | Optional pre-deploy migration Job |
| `helm-set-values` | | — | Extra non-secret `--set` values |
| `major-version` / `minor-version` | | `1` / `0` | Semver components |

**Secrets:** `registry-username`, `registry-password`, `kubeconfig`, `github-token` (tags the origin after deploy), `dependabot-alerts-token` (PAT/App token with "Dependabot alerts: read", for the build-time critical-vuln gate — `GITHUB_TOKEN` cannot access this API), `helm-set-secret-values`, `nuget-api-key`, `nuget-source`, `NUGET_PACKAGE_PAT`.

**Required caller permissions:** `contents: write`, `packages: write` (GHCR image/chart push), `security-events: read` (build-time critical-vuln gate) — must be declared in the caller's own top-level `permissions:` block. A job's own permission request inside this reusable workflow can only narrow what the caller grants, never widen it, so a caller missing `packages: write` gets a silent 403 on the GHCR push regardless of what this workflow's own jobs request.

**Outputs:** `version`, `docker-image`, `helm-chart`, `nuget-version`.

**Listener modes**

| Mode | When to use | What onboarding does |
|---|---|---|
| **Dedicated** (default) | Custom domains (`api-stg.zeenah.io`) | Creates HTTP + HTTPS listeners, issues a TLS cert via cert-manager HTTP-01 |
| **Shared / wildcard** | Internal subdomains (`myapp.sf9.io`) | Validates the named shared listener exists; skips cert + listener creation |

```yaml
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/generic-gateway-helm-template.yml@main
    with:
      app-name: my-api
      namespace: my-api-dev
      gateway-hostnames: api-stg.myapp.io
    secrets:
      kubeconfig: ${{ secrets.KUBECONFIG }}
      registry-username: ${{ secrets.REGISTRY_USERNAME }}
      registry-password: ${{ secrets.REGISTRY_PASSWORD }}
      helm-set-secret-values: ${{ secrets.DEV_HELM_SECRET_VALUES }}
```

**Shared wildcard (e.g. `*.sf9.io`):**

```yaml
with:
  app-name: my-api
  namespace: my-api-dev
  gateway-hostnames: my-api.sf9.io
  gateway-section-name: https-wildcard-sf9-io
```

##### Mixed listener mode

One release, two hostnames, different modes. A **blank line** in `gateway-section-names` means dedicated; a non-empty line names a shared listener. Keep every non-empty line at the same indentation (YAML sets block-scalar indent from the first non-empty line).

```yaml
with:
  gateway-hostnames: |
    api-stg.zeenah.io
    zeenah-api.sf9.io
  gateway-section-names: |

    https-wildcard-sf9-io
```

The first (blank) line → dedicated for `api-stg.zeenah.io` (gets its own listeners + cert); the second → shared listener for `zeenah-api.sf9.io` (validated only). When two hosts share one section name the pipeline emits a single `parentRefs` entry (the Gateway API forbids duplicate `(name, namespace, sectionName)` tuples).

> **DNS / Cloudflare proxy:** HTTP-01 needs the hostname to resolve directly to the gateway IP. With Cloudflare, set the record to **DNS-only (grey cloud)** while the cert is issued; re-enable the orange cloud once it is `Ready` (the pipeline skips the DNS pre-flight when a valid cert already exists).

---

#### `helm-deploy-values.yml`

Deploy-only: deploys an already-published chart from a ChartMuseum-style repo using a caller-supplied values file plus friendly ingress/service inputs. Does not build, package, or tag.

| Input | Required | Default | Description |
|---|---|---|---|
| `release-name` | ✅ | — | Helm release name |
| `chart-name` | ✅ | — | Chart name |
| `chart-repo` | ✅ | — | Classic (ChartMuseum-style) Helm repo URL |
| `namespace` | ✅ | — | Kubernetes namespace |
| `values-file` | | `values.yaml` | Values file in the caller repo (applied if present) |
| `chart-version` | | `''` | Empty = latest published; set to pin |
| `environment` | | `''` | Helm `environment=` value (not the GitHub Environment) |
| `gh-environment` | | `''` | Optional GitHub Environment for protection/secrets |
| `ingress-hosts` / `ingress-paths` / `ingress-tls-secrets` | | `''` | Ingress config (hosts zipped with TLS secrets by index) |
| `image-tag` | | `''` | Image tag |
| `helm-version` | | `v4.2.0` | Helm CLI version |
| `kubectl-version` | | `v1.33.0` | kubectl CLI version |

**Secrets:** `kubeconfig` (or `kubeconfig64` alias), `helm-set-secret-values`, `dependabot-alerts-token` (PAT/App token with "Dependabot alerts: read", for the build-time critical-vuln gate; pass `secrets.DEPENDABOT_ALERTS_TOKEN` — `GITHUB_TOKEN` cannot access this API regardless of granted permissions).

---

### Helm Chart CI/CD

---

#### `gateway-chart-cicd.yml`

CI/CD for a **Cilium Gateway API-aware** Helm chart: compute SemVer (from git tags) → `helm lint --strict` + routing/ConfigMap render assertions (parsed with `yq`) → package → push to ChartMuseum → tag origin. The version comes from `determine-semver`, not the run number.

| Input | Required | Default | Description |
|---|---|---|---|
| `chart-path` | | `chart` | Chart directory |
| `chartmuseum-url` | | `https://charts.sf9.io/api/charts` | ChartMuseum upload endpoint |
| `helm-version` | | `v4.2.2` | Helm CLI version |
| `major-version` / `minor-version` | | `1` / `0` | SemVer components |
| `update-dependencies` | | `true` | `helm package --dependency-update` |
| `validate-routing` | | `true` | Validate default/ingress/gateway/dual rendering |
| `validate-configmap` | | `true` | Validate ConfigMap gating + key routing (`config.data` → ConfigMap, `environmentVariables` → Secret) |

**Secrets:** `registry-username`, `registry-password` (required); `github-token` (optional — used by the tag job, falls back to `GITHUB_TOKEN`).

**Outputs:** `version`, `chart-name`, `chart-package`, `chart-repo-url`.

> **TODO — migrate to OCI.** ChartMuseum HTTP upload is the legacy distribution path. Publishing via an OCI registry (`helm push chart.tgz oci://...`), as `reusable-service-cicd.yml` already supports, gives immutable, digest-pinned, signable charts and removes the standalone ChartMuseum dependency.

---

### Mobile · iOS & Android

There are two flavors: **React Native** (`ios-build.yml` / `android-build.yml`) and **Flutter** (`flutter-ios-build.yml` / `flutter-android-build.yml`). All four share the same shape — a **build** job that itself `needs` the critical-vuln gate (a critical alert blocks the build, not just the release, so CI never spends a runner building something that can't ship) and a **release** job (`release_with_environment`) gated on the input flags AND on both the build and the gate having actually succeeded (or the gate having been skipped), bound to a named GitHub Environment for approvals. Per-branch dev/prod selection is done by the `workflow_dispatch` caller (see the matching starter templates). The Flutter and RN iOS workflows reuse the same `ios-install-cert` / `ios-install-profile` composite actions for signing.

---

#### `ios-build.yml`

Builds, signs, and archives a React Native / native iOS app on a macOS runner, exports an IPA, and uploads it to TestFlight from `ubuntu-latest` via the App Store Connect API (`apple-actions/upload-testflight-build@v5`).

| Input | Required | Default | Description |
|---|---|---|---|
| `workspace` | ✅ | — | Path to `.xcworkspace` |
| `scheme` | ✅ | — | Xcode scheme to archive |
| `configuration` | | `Release` | Build configuration |
| `xcode-version` | | `''` | Xcode major or major.minor (e.g. `16.4`) |
| `macos-runner` | | `macos-latest` | macOS runner label |
| `node-version` | | `24` | Node.js version (React Native) |
| `package-manager` | | `yarn` | `yarn` or `npm` |
| `ios-dir` | | `ios` | iOS directory for pod operations |
| `clean-reinstall-pods` | | `false` | `pod deintegrate` + `pod install --repo-update` |
| `enable-ccache` | | `true` | ccache for ObjC/C++ pod compilation |
| `ruby-version` | | `''` | Ruby version (empty disables Ruby setup) |
| `use-bundler` | | `false` | Install gems via Bundler (needs `ruby-version`) |
| `marketing-prefix` | | `1.0` | Marketing version start (X.Y or X.Y.Z) |
| `release-environment` | | `ios-staging` | GitHub Environment for the release job |
| `disable-release` | | `false` | Build only; skip TestFlight upload |

**Required secrets:** `ios-p12-base64`, `ios-p12-password`, `ios-mobileprovision-base64`, `appstore-api-key-id`, `appstore-issuer-id`, `appstore-api-private-key-base64` (and optional `ios-team-id`).

**Recommended secret:** `dependabot-alerts-token` (a PAT/App token with "Dependabot alerts: read" — sourced from the org secret `DEPENDABOT_ALERTS_TOKEN`, **not** `GITHUB_TOKEN`, which cannot access the Dependabot Alerts API). Without it, the critical-vuln gate fails closed on every run, which now blocks the `build` job itself (not just the TestFlight upload) — no signing/archiving happens until the gate resolves.

**Outputs:** `version`, `build-number`, `ipa-file`.

```yaml
jobs:
   build-and-release:
    uses: simplify9/.github/.github/workflows/ios-build.yml@main
    with:
      workspace: ios/App.xcworkspace
      scheme: App
      xcode-version: "26"
      release-environment: ios-production
    secrets:
      ios-p12-base64: ${{ secrets.IOS_P12_BASE64 }}
      ios-p12-password: ${{ secrets.IOS_P12_PASSWORD }}
      ios-mobileprovision-base64: ${{ secrets.IOS_PROVISIONING_PROFILE_BASE64 }}
      appstore-api-key-id: ${{ secrets.APPSTORE_API_KEY_ID }}
      appstore-issuer-id: ${{ secrets.APPSTORE_ISSUER_ID }}
      appstore-api-private-key-base64: ${{ secrets.APPSTORE_API_KEY_BASE64 }}
      dependabot-alerts-token: ${{ secrets.DEPENDABOT_ALERTS_TOKEN }}
```

**Notes:** manual signing only (automatic signing needs an interactive Xcode session); CocoaPods spec repo + Pods dir are cached on `Podfile.lock`; ccache speeds ObjC/C++ rebuilds (no Swift benefit). Use the **iOS App CI/CD** starter template for a `workflow_dispatch` entry point.

---

#### `android-build.yml`

Builds and signs a React Native Android App Bundle (AAB) via Gradle and publishes it to Google Play (`r0adkll/upload-google-play@v1`).

| Input | Required | Default | Description |
|---|---|---|---|
| `app-id` | ✅ | — | Android `applicationId` (package name) |
| `app-slug` | | `app` | Output AAB filename slug |
| `gradle-task` | | `bundleRelease` | Gradle task |
| `version-prefix` | | `1.0.0` | Base version (X.Y or X.Y.Z) |
| `version-code-offset` | | `80000` | Added to `github.run_number` for versionCode |
| `java-version` | | `17` | Java version (temurin) |
| `node-version` | | `24` | Node.js version (React Native) |
| `package-manager` | | `yarn` | `yarn` or `npm` |
| `build-root-directory` | | `android` | Gradle project root |
| `use-jetifier` | | `true` | Run `npx jetify` (AndroidX migration) |
| `play-track` | | `internal` | `internal`, `alpha`, `beta`, `production` |
| `changes-not-sent-for-review` | | `false` | Use `changesNotSentForReview` (internal tracks) |
| `release-environment` | | `android-staging` | GitHub Environment for the release job |
| `disable-release` | | `false` | Build only; skip Play upload |

**Required secrets:** `android-keystore-base64`, `android-keystore-password`, `android-key-alias`, `android-key-password`, `google-play-service-account-json`.

**Recommended secret:** `dependabot-alerts-token` (a PAT/App token with "Dependabot alerts: read" — sourced from the org secret `DEPENDABOT_ALERTS_TOKEN`, **not** `GITHUB_TOKEN`, which cannot access the Dependabot Alerts API). Without it, the critical-vuln gate fails closed on every run, which now blocks the `build` job itself (not just the Play upload) — no signing/building happens until the gate resolves.

**Outputs:** `version-name`, `version-code`, `aab-file`.

```yaml
jobs:
  build-and-release:
    uses: simplify9/.github/.github/workflows/android-build.yml@main
    with:
      app-id: com.mycompany.myapp
      gradle-task: bundleRelease
      version-prefix: "2.0.0"
      version-code-offset: "80000"
      release-environment: android-production
      play-track: production
    secrets:
      android-keystore-base64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
      android-keystore-password: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
      android-key-alias: ${{ secrets.ANDROID_KEY_ALIAS }}
      android-key-password: ${{ secrets.ANDROID_KEY_PASSWORD }}
      google-play-service-account-json: ${{ secrets.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON }}
      dependabot-alerts-token: ${{ secrets.DEPENDABOT_ALERTS_TOKEN }}
```

**Notes:** Gradle uses `gradle/actions/setup-gradle@v5` (do not use the archived `gradle/gradle-build-action`, and do not add `cache: gradle` to `setup-java` — it conflicts). The workflow sets `org.gradle.caching=true` itself, so callers no longer need to. NDK `27.1.12297006` (r27b LTS) is pinned and installed via `sdkmanager` (not `actions/cache` — the Android SDK dir is root-owned). Use the **Android App CI/CD** starter template for a `workflow_dispatch` entry point.

---

#### `flutter-ios-build.yml`

Builds and signs a **Flutter** iOS app on a macOS runner, exports an IPA via `flutter build ipa`, and uploads it to TestFlight from `ubuntu-latest` via the App Store Connect API (`apple-actions/upload-testflight-build@v5`). Set the marketing version's major/minor through `marketing-prefix` (`X.Y`); the patch remains the `pubspec.yaml` patch plus `github.run_number`, and the build number remains the pubspec `+BUILD` plus `github.run_number`.

| Input | Required | Default | Description |
|---|---|---|---|
| `macos-runner` | | `macos-latest` | macOS runner label (e.g. `macos-26`) |
| `xcode-version` | | `""` | Xcode selector via `maxim-lobanov/setup-xcode` (empty = runner default) |
| `flutter-version` | | `3.x` | `subosito/flutter-action` version selector (pin exact for reproducible builds) |
| `flutter-channel` | | `stable` | Flutter channel |
| `project-directory` | | `.` | Flutter project root relative to repo root (set to e.g. `mobile` for a monorepo); `ios-dir`/`pbxproj-path` resolve under it |
| `ios-dir` | | `ios` | iOS project directory (Podfile + Runner project) |
| `pbxproj-path` | | `ios/Runner.xcodeproj/project.pbxproj` | project.pbxproj that gets the manual-signing rewrite |
| `app-slug` | | `app` | Output IPA filename slug |
| `marketing-prefix` | | `1.0` | Marketing version major/minor (`X.Y` only); patch stays automatic from pubspec + run number |
| `export-method` | | `app-store-connect` | ExportOptions.plist distribution method |
| `run-analyze` | | `false` | Run `flutter analyze` before building |
| `ipa-name-pattern` | | `{app_slug}-{version}-{build_number}.ipa` | Output IPA name tokens |
| `wait-for-processing` | | `false` | Poll App Store Connect until processing finishes (fire-and-forget by default) |
| `release-environment` | | `ios-staging` | GitHub Environment for the release job |
| `disable-release` | | `false` | Build only; skip TestFlight upload |

**Required secrets:** `ios-p12-base64`, `ios-p12-password`, `ios-mobileprovision-base64` (plus `appstore-api-key-id`, `appstore-issuer-id`, `appstore-api-private-key-base64` for the upload, and optional `ios-team-id`).

**Recommended secret:** `dependabot-alerts-token` (a PAT/App token with "Dependabot alerts: read" — sourced from the org secret `DEPENDABOT_ALERTS_TOKEN`, **not** `GITHUB_TOKEN`, which cannot access the Dependabot Alerts API). Without it, the critical-vuln gate fails closed on every run, which blocks the `build` job itself (not just the TestFlight upload) — no signing/archiving happens until the gate resolves.

**Outputs:** `version`, `build-number`, `ipa-file`.

```yaml
jobs:
  build-and-release:
    uses: simplify9/.github/.github/workflows/flutter-ios-build.yml@main
    with:
      macos-runner: macos-26
      xcode-version: "26.3"
      app-slug: myapp
      marketing-prefix: "1.0"
      release-environment: ios-production
    secrets:
      ios-p12-base64: ${{ secrets.IOS_P12_BASE64 }}
      ios-p12-password: ${{ secrets.IOS_P12_PASSWORD }}
      ios-mobileprovision-base64: ${{ secrets.IOS_MOBILEPROVISION_BASE64 }}
      ios-team-id: ${{ secrets.IOS_TEAM_ID }}
      appstore-api-key-id: ${{ secrets.APPSTORE_API_KEY_ID }}
      appstore-issuer-id: ${{ secrets.APPSTORE_ISSUER_ID }}
      appstore-api-private-key-base64: ${{ secrets.APPSTORE_API_PRIVATE_KEY_BASE64 }}
      dependabot-alerts-token: ${{ secrets.DEPENDABOT_ALERTS_TOKEN }}
```

**Notes:** manual signing only — keychain/cert/profile install is delegated to the shared `ios-install-cert` / `ios-install-profile` composite actions, then the `pbxproj` is rewritten to manual signing (`Apple Distribution`) with fail-loud `grep` asserts and a generated `ExportOptions.plist`. The pub package cache is handled by `subosito/flutter-action`'s `cache: true` (no separate `actions/cache` step), and `ios/Pods` is cached on `Podfile.lock`; `pod install` deliberately avoids `deintegrate`/`--repo-update` to preserve the cache. Use the **Flutter iOS App CI/CD** starter template for a `workflow_dispatch` entry point.

---

#### `flutter-android-build.yml`

Builds and signs a **Flutter** Android App Bundle (AAB) via `flutter build appbundle` and publishes it to Google Play (`r0adkll/upload-google-play@v1`). Signing uses Flutter's `key.properties` convention (decoded keystore + generated `android/key.properties`).

| Input | Required | Default | Description |
|---|---|---|---|
| `app-id` | ✅ | — | Android `applicationId` / Play package name |
| `app-slug` | | `app` | Output AAB filename slug |
| `project-directory` | | `.` | Flutter project root relative to repo root (set to e.g. `mobile` for a monorepo) |
| `flutter-version` | | `3.x` | `subosito/flutter-action` version selector (pin exact for reproducible builds) |
| `flutter-channel` | | `stable` | Flutter channel |
| `java-version` | | `17` | Java version (temurin) |
| `version-prefix` | | `1.0.0` | Base version (X.Y or X.Y.Z) |
| `version-code-offset` | | `80000` | Added to `github.run_number` for versionCode |
| `run-analyze` | | `true` | Run `flutter analyze` before building |
| `analyze-fatal-level` | | `none` | `flutter analyze` fatal severity (`none`/`warning`/`info`) |
| `keystore-output-path` | | `android/app/release.keystore` | Where the decoded keystore is written |
| `aab-name-pattern` | | `{app_slug}-release-{version_name}.aab` | Output AAB name tokens |
| `play-track` | | `internal` | `internal`, `alpha`, `beta`, `production` |
| `release-status` | | `draft` | Play release status (`draft`/`completed`/...) |
| `changes-not-sent-for-review` | | `false` | Use `changesNotSentForReview` (internal tracks) |
| `release-environment` | | `android-staging` | GitHub Environment for the release job |
| `disable-release` | | `false` | Build only; skip Play upload |

**Required secrets:** `android-keystore-base64`, `android-keystore-password`, `android-key-alias`, `android-key-password`, `google-play-service-account-json`.

**Recommended secret:** `dependabot-alerts-token` (a PAT/App token with "Dependabot alerts: read" — sourced from the org secret `DEPENDABOT_ALERTS_TOKEN`, **not** `GITHUB_TOKEN`, which cannot access the Dependabot Alerts API). Without it, the critical-vuln gate fails closed on every run, which blocks the `build` job itself (not just the Play upload) — no signing/building happens until the gate resolves.

**Outputs:** `version-name`, `version-code`, `aab-file`.

```yaml
jobs:
  build-and-release:
    uses: simplify9/.github/.github/workflows/flutter-android-build.yml@main
    with:
      app-id: com.mycompany.myapp
      app-slug: myapp
      version-prefix: "2.0.0"
      version-code-offset: "80000"
      release-environment: android-production
      play-track: production
    secrets:
      android-keystore-base64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
      android-keystore-password: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
      android-key-alias: ${{ secrets.ANDROID_KEY_ALIAS }}
      android-key-password: ${{ secrets.ANDROID_KEY_PASSWORD }}
      google-play-service-account-json: ${{ secrets.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON }}
      dependabot-alerts-token: ${{ secrets.DEPENDABOT_ALERTS_TOKEN }}
```

**Notes:** versionName is a SemVer patch counter — `major.minor` are fixed by `version-prefix` and only the patch increments (`patch = base patch + run_number`, e.g. `1.1.69 → 1.1.70`, no carry/rollover, no upper bound); versionCode is `run_number + version-code-offset` (strictly monotonic — set the offset above your last shipped versionCode, and trigger a new run rather than re-running a failed one, since re-runs reuse the run number). No NDK plumbing — Flutter owns the actual build — but the Gradle User Home is cached via `gradle/actions/setup-gradle@v5` (which applies to the `gradlew` Flutter invokes), and both jobs opt JS-based actions onto Node 24 via `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24`. The keystore and generated `android/key.properties` are removed by an `always()` cleanup step. Use the **Flutter Android App CI/CD** starter template for a `workflow_dispatch` entry point.

---

### Security

---

#### `critical-vuln-gate.yml`

Thin `workflow_call` wrapper around the `check-critical-vulns` composite action: fails if the calling repository has any open **critical-severity** Dependabot alert. Has no `inputs:` — only a required secret. Called by the `critical-vuln-check` and `dependabot-auto-merge` starter templates, and the same underlying check is embedded as an early gating job inside 10 of the 11 other reusable workflows in this repo (both Cloudflare workflows, all four Service & Backend workflows, and all four mobile workflows) — everything except the chart-lint-only `gateway-chart-cicd.yml`.

**Required secrets:** `dependabot-alerts-token` (a PAT/App token with "Dependabot alerts: read" on the calling repo — pass `secrets.DEPENDABOT_ALERTS_TOKEN`; `GITHUB_TOKEN` cannot access the Dependabot Alerts API regardless of granted permissions, confirmed by live testing).

**Outputs:** none directly from the workflow; the underlying `check-critical-vulns` action's `critical-count` output is available to the job that calls it.

```yaml
jobs:
  vuln-gate:
    uses: simplify9/.github/.github/workflows/critical-vuln-gate.yml@main
    secrets:
      dependabot-alerts-token: ${{ secrets.DEPENDABOT_ALERTS_TOKEN }}
```

**Notes:** this is the same check embedded as a build-time gate in 10 of the other reusable workflows in this repo (see above) — see the **Critical Vulnerability Check** and **Dependabot Auto-Merge** starter templates below for the PR-time uses. Requires Dependabot alerts enabled on the repo (a free feature — no GitHub Advanced Security license needed). Also forwards `github-token: secrets.GITHUB_TOKEN` to `check-critical-vulns` so it can verify npm alerts against the PR's own branch — see [PR-branch verification](#pr-branch-verification-npm-only--breaking-the-fix-your-own-block-deadlock) below.

---

## Composite Action Reference

Call composite actions directly in job steps:

```yaml
uses: simplify9/.github/.github/actions/<name>@main
```

All 19 actions are **composite** (`runs.using: composite`). Only `gateway-onboard` (`onboard.sh`), `gateway-routing` (`render.sh`), and `check-critical-vulns` (`parse_yarn_lock.py`, for its PR-branch npm verification — see below) keep logic in a sibling script; the rest is inline bash.

### Versioning & Tagging

| Action | Purpose | Key inputs | Key outputs |
|---|---|---|---|
| `determine-semver` | Compute next `major.minor.patch` from git tags | `major`, `minor`, `release-branch`, `current-ref`, `build-id` | `version`, `git-tag`, `is-release` |
| `tag-github-origin` | Create a git tag via the GitHub REST API (no checkout) | `github-token`, `repository`, `tag`, `sha` | `created`, `ref` |

### Docker

| Action | Purpose | Key inputs | Key outputs |
|---|---|---|---|
| `docker-build-push` | Build + push (multi-platform via Buildx/QEMU) up to three tags | `image-name`, `version`, `username`, `password`, `registry`, `platforms` | `image-tags`, `image-digest` |

### Helm

| Action | Purpose | Key inputs |
|---|---|---|
| `helm-generic` | `helm upgrade --install` of `s9genericchart` (default) + optional pre-deploy migration Job. Helm 4. snake_case inputs | `app_name`, `namespace`, `kubeconfig_data`, `extra_set_values`, `secret_set_values`, `init_job_image` |
| `helm-deploy` | Deploy from OCI **or** ChartMuseum (`chart-source-type`) | `chart-name`, `repository`, `kubeconfig`, `chart-source-type`, `chart-repo-url` |
| `helm-deploy-s9generic` | Deploy from OCI **or** a local chart dir (`chart-path`) with failure diagnostics | `chart-name`, `chart-path`, `kubeconfig` |
| `helm-package-push` | Package + publish to OCI or ChartMuseum | `chart-path`, `chart-name`, `version`, `publish-method` |

> ⚠️ **Three overlapping deploy actions.** `helm-deploy`, `helm-deploy-s9generic`, and `helm-generic` all wrap `helm upgrade --install` and re-implement the same concerns (kubeconfig handling, atomic rollback, `--set`/`--set-string`, verification), differing only in input naming, chart source, and migration-Job support. Every hardening fix must be applied in three places. The intended direction is to consolidate them into a single parameterized deploy action and keep the old names as thin shims. See [AGENTS.md](./AGENTS.md#helm).

### Gateway API (Cilium)

| Action | Purpose | Key outputs |
|---|---|---|
| `gateway-routing` | Render gateway/ingress/configmap Helm values + host/section lists (pure, no cluster access) | `values-file`, `gateway-host-list`, `gateway-section-names-list` |
| `gateway-onboard` | Ensure parent Gateway listeners + cert-manager Certificates exist before deploy (cluster-mutating) | — |

### .NET

| Action | Purpose | Key outputs |
|---|---|---|
| `dotnet-build` | Resolve `.sln`/glob, then restore → build → optional test | `build-target` |
| `dotnet-pack-push` | `dotnet pack --no-build` → `nuget push --skip-duplicate` (empty = skip) | `packages-pushed`, `package-paths` |

### Cloudflare

| Action | Purpose | Key outputs |
|---|---|---|
| `generate-wrangler-config` | Generate `wrangler.toml` (plain Workers, OpenNext, static assets, SPA) | `config-path` |
| `setup-cloudflare-domain` | Add a custom domain to a Pages project (`fail-on-error: false` = non-blocking) | `domain-status` |

### iOS

| Action | Purpose |
|---|---|
| `ios-install-cert` | Import a `.p12` into a temporary keychain (`p12Base64`, `p12Password`) |
| `ios-install-profile` | Install a `.mobileprovision`, extract UUID/Name + best-effort Team ID/Bundle ID (`profileBase64`) |
| `xcode-build` | `xcodebuild archive` with manual signing (`workspace`, `scheme`, `archivePath`, `developmentTeam`, `provisioningProfileUuid`, `keychainPath`) |
| `xcode-export` | `xcodebuild -exportArchive` → `.ipa` (`archivePath`, `exportOptionsPlist`, `exportPath`) |

### Shared

| Action | Purpose |
|---|---|
| `write-job-summary` | Append a standardized, status-aware section to `$GITHUB_STEP_SUMMARY` (`title`, `status`, `icon`, `details`) |
| `check-critical-vulns` | Fail if the repository has any open critical-severity Dependabot alert (`dependabot-alerts-token` — a PAT/App token with "Dependabot alerts: read"; `GITHUB_TOKEN` cannot access this API regardless of granted permissions — `repository`; optional `github-token`; output `critical-count`). Uses `Link`-header cursor pagination (this endpoint rejects `page=N`). When run under `pull_request_target` with a `github-token` forwarded, also verifies open npm alerts against the PR's own HEAD branch lockfile (`parse_yarn_lock.py` sibling script for `yarn.lock`; `package-lock.json` handled inline via `jq`) — see [PR-branch verification](#pr-branch-verification-npm-only--breaking-the-fix-your-own-block-deadlock). Used by `critical-vuln-gate.yml` and embedded as a build-time gate in 10 of the other reusable workflows (all but `gateway-chart-cicd.yml`) |

---

## Dependabot

This is the org-wide reference for how Dependabot is implemented across every `simplify9`
repository. It covers two genuinely different systems that are easy to conflate — read the
first section before anything else.

### Two separate systems

**1. The Dependabot *service*.** Not a GitHub Actions workflow — a backend GitHub runs on
your behalf. It reads `.github/dependabot.yml` from a repo's **default branch only**. This
is fixed and non-configurable: the file's own `target-branch:` field controls where
*update* PRs get opened, never where the config file itself must live. On the schedule you
set, the service:

- Parses manifest files (`package.json`, `*.csproj`, `Dockerfile`, `pubspec.yaml`, `Gemfile`, `action.yml`, …)
- Diffs current versions against the registry's latest and against the GitHub Advisory Database
- Opens one PR per update (or per group) directly as `dependabot[bot]`, based on/against whatever `target-branch:` says

Two independent triggers feed it, both toggled per-repo in **Settings → Code security**:

- **Version updates** — scheduled (the `schedule:` block below), routine bumps regardless of vulnerability status.
- **Security updates** — event-driven, fires immediately when a new advisory affecting something in the dependency graph is published, independent of schedule.

**2. GitHub Actions.** The workflows that *react* to what the service produces — this is
where the gate/auto-merge logic and the one non-obvious secrets restriction (below) live.

### The three-file pattern

Every onboarded repo gets the same three files:

| File | Role |
|---|---|
| `.github/dependabot.yml` | Service config — which ecosystems, schedule, limits, grouping. Category-specific, rendered from a template below. |
| `.github/workflows/critical-vuln-check.yml` | PR-time gate — see [Starter Templates](#starter-templates) / [`critical-vuln-gate.yml`](#critical-vuln-gateyml). |
| `.github/workflows/dependabot-auto-merge.yml` | Auto-merge for safe bumps — see below. |

Both workflow files are thin callers of this repo's [`critical-vuln-gate.yml`](#critical-vuln-gateyml)
reusable workflow, which wraps the [`check-critical-vulns`](#composite-action-reference)
composite action — one source of truth reused at three call sites: the PR-time gate, the
build-time gate embedded in 10 of the 11 other reusable workflows in this repo, and as a
dependency of auto-merge.

### `dependabot.yml` templates (`dependabot-templates/`)

Ready-made per-category configs live in [`dependabot-templates/`](./dependabot-templates)
for copying into a consumer repo, with `{{TARGET_BRANCH}}` replaced by `develop` (if the
repo has that branch) or the repo's actual default branch otherwise:

| Template | Ecosystems | Schedule (all `Asia/Amman`) | Primary limit | Docker/Actions limit |
|---|---|---|---|---|
| `nuget-api.yml` | nuget, docker, github-actions | Monday 06:00 | 10 | 5 |
| `npm-frontend.yml` | npm, docker, github-actions | Tuesday 06:00 | 10 | 5 |
| `react-native-mobile.yml` | npm, bundler, github-actions | Wednesday 06:00 | 10 | 5 |
| `flutter-mobile.yml` | pub, github-actions | Wednesday 06:00 | 10 | 5 |
| `infra-actions-only.yml` | github-actions, docker | Thursday 06:00 | 5 | 5 |
| `github-repo.yml` | github-actions (`/` + `/.github/actions/*`) | Sunday 06:00 | 5 | — |

Schedule days are deliberately staggered by category (and land on the `Asia/Amman`
Sunday–Thursday work week) so Dependabot PR volume doesn't land on every repo the same
morning. Every primary-ecosystem block also groups same-update-type bumps:

```yaml
groups:
  npm-minor-patch:      # (or nuget-/pub-/actions-minor-patch, per ecosystem)
    update-types: ["minor", "patch"]
```

A grouped batch of minor+patch bumps opens as **one** PR and counts as **one** toward
`open-pull-requests-limit` — this is what keeps PR volume manageable at org scale.

### `open-pull-requests-limit` — how it actually behaves

- Scoped **per `updates:` block** (i.e., per ecosystem + directory + branch), not per repo — a repo with 3 `updates:` blocks has 3 independent limits.
- Only throttles **version updates**. Security updates always fire regardless of how many PRs are already open — the limit never blocks a real vulnerability fix.
- It doesn't queue skipped updates — Dependabot just doesn't open a new PR for that slot until an existing one is closed or merged, then backfills on the next scheduled run (or immediately for security updates).
- Closing a PR without merging does **not** permanently suppress that dependency version — Dependabot will reopen it on the next run unless you comment `@dependabot ignore this major/minor version` (or this dependency) on the PR, or add it to the config's `ignore:` list.

### Where the file must live vs. `target-branch`

Many repos have a `develop` branch that diverges from `main`. `target-branch` is set to
`develop` for these, so Dependabot's own update PRs land where normal dev flow expects
them. But `dependabot.yml` itself — the file the service reads to know `target-branch`
exists at all — **must be committed to the default branch**, always, regardless of what
`target-branch` says inside it. These are two independent facts that are easy to conflate:
"which branch gets the file commit" (always default) vs. "what the file's `target-branch`
field says" (`develop`, when it exists). Committing the config to `develop` instead of the
default branch leaves it completely undiscovered by the service — no error, no PRs, just
silence.

### PR-time gate & auto-merge

See [`critical-vuln-gate.yml`](#critical-vuln-gateyml) and the **Critical Vulnerability
Check** / **Dependabot Auto-Merge** rows in [Starter Templates](#starter-templates) for the
reusable-workflow/template pairing. Both caller templates trigger on `pull_request_target`
(not `pull_request` — see **Known pitfalls** below), scoped to `branches: [main, develop]`.

**`dependabot-auto-merge.yml` merges a Dependabot PR only when all of:**

- Actor is `dependabot[bot]` (both jobs gate on this explicitly)
- [`dependabot/fetch-metadata@v2`](https://github.com/dependabot/fetch-metadata) reports a **patch**-level semver bump (never minor/major)
- Ecosystem is npm, NuGet, pub, Bundler, or GitHub Actions — **never Docker** (base-image bumps always need a human)
- **If, and only if, the PR targets `main`:** no open critical Dependabot alert on the repo (re-checked here explicitly via its own `vuln-gate` job — reusable-workflow jobs can't `needs:` a job defined in a *different* workflow file, so this can't just piggyback on the check template's result)

"Auto-merge" arms GitHub's native auto-merge feature (`gh pr merge --auto --squash`) — it
still waits for the repo's own required status checks (build/test) to pass before actually
merging. It does not bypass CI.

**Why the critical-alert check is scoped to `main` only:** matches the two-layer policy
below — `develop`'s branch protection never requires `critical-vuln-check.yml`, so a human
merging a patch bump into `develop` by hand is never blocked by an open alert. Auto-merge
must not be stricter than a human would be: gating it on the same repo-wide alert for a
`develop`-bound PR would refuse to arm auto-merge there for no enforced reason, and since
alerts only clear once a fix lands on the **default** branch, an unrelated open alert could
stall a `develop`-bound patch bump indefinitely. `vuln-gate`'s own `if:` now checks
`github.event.pull_request.base.ref == 'main'`; `auto-merge`'s `if:` uses `always()` plus
explicit branch-aware logic so it isn't skipped when `vuln-gate` itself was skipped for a
`develop`-bound PR, while still requiring `vuln-gate` to have succeeded for a `main`-bound one.

### Enforcement is two layers, deliberately redundant

- **PR-time** (`critical-vuln-check.yml` + branch protection): on `main`, mark the check **required** in branch protection — merge is physically blocked while any critical alert is open. On `develop`, leave it present but **not required** — a visible red check, no block.
- **Build-time** (embedded directly as an early job in 10 of the 11 other reusable workflows in this repo — everything except the chart-lint-only `gateway-chart-cicd.yml` — triggered on `push`, not `pull_request`): re-checks at actual deploy time. This is **not** subject to the Dependabot secrets restriction below (that restriction is specific to `pull_request`-family events; `push` never carries it), and it's the real safety net on any repo where branch protection can't enforce anything at all — e.g. private repos on a plan tier below GitHub Team/Enterprise, where classic branch protection is unavailable outright (`403: Upgrade to GitHub Pro`). The build-time gate still blocks an actual release even with zero branch protection configured.

### PR-branch verification (npm only) — breaking the fix-your-own-block deadlock

A critical alert only clears once its fix lands on the **default** branch — GitHub never
re-scans a PR's own branch. That's a real deadlock on `main`: a PR that itself contains the
fix for the only open critical alert could never merge, because the alert was still "open"
by definition until that exact merge happened.

`check-critical-vulns` breaks this for **npm** specifically. When it runs under
`pull_request_target` (i.e. from `critical-vuln-gate.yml`, not the build-time embedded uses,
which run on `push` and have no PR to compare against), it re-checks every open
npm-ecosystem alert against the PR's own HEAD branch: it reads the flagged package's
**lockfile** (`package-lock.json` or `yarn.lock` — not the manifest, which shows a requested
range, not the resolved version) at the PR head ref, and if **every** resolved occurrence of
that package falls outside the alert's `vulnerable_version_range`, that alert no longer
counts against this PR. Checking every occurrence matters: the same package commonly
resolves to different versions at different points in the dependency tree (confirmed live:
`form-data` resolved to both a patched version nested under one dependency and a vulnerable
version at the top level, in the same lockfile) — one unpatched occurrence still means the
vulnerability is present.

Version comparison uses the real `semver` npm package (`npx semver <version> -r <range>`),
not string comparison — GitHub's `vulnerable_version_range` uses comma-separated AND clauses
(e.g. `">= 1.0.0, < 2.3.4"`), converted to node-semver's space-separated form before evaluation.

**Scope, deliberately narrow:** this only applies to the npm ecosystem for now (NuGet,
Composer, pip, Maven, GitHub Actions, and Docker all still fail closed, exactly as before —
a genuinely open, unrelated critical alert still blocks the PR, whatever ecosystem it's in).
An org-wide audit (2026-07-14) found npm makes up 96% of open critical alerts here, so this
covers the overwhelming majority of real cases; the rest still need the manual `fix_started`
dismissal path (see **Known pitfalls** below) as a fallback.

**Fails closed, always:** non-npm ecosystem, no lockfile match at the PR head, an
unsupported/unrecognized lockfile format, a parse failure, or a missing `github-token` input
— any of these leaves that alert counted as still-blocking, same as before this feature
existed. Nothing here can silently let a genuinely-still-vulnerable PR merge.

**Safety under `pull_request_target`:** this is pure static text parsing of the lockfile via
the Contents API — it never checks out or executes the PR's own code (no `npm ci`, no
`dotnet restore`, no package-manager invocation against untrusted content), so it doesn't
reintroduce the code-injection risk `pull_request_target` is normally dangerous for.
`github-token` (forwarded as `secrets.GITHUB_TOKEN` from `critical-vuln-gate.yml`, which
already grants `contents: write`) is used only to read the lockfile — composite actions
can't read the `secrets` context directly, so it must be passed in explicitly even though
it's just the workflow's own ambient token.

### Secrets — why a real PAT, not `GITHUB_TOKEN`

The Dependabot Alerts REST API (`GET /repos/{owner}/{repo}/dependabot/alerts`) rejects the
ephemeral Actions `GITHUB_TOKEN` outright ("Resource not accessible by integration") —
confirmed by live testing, not a `permissions:` scoping issue. No amount of `permissions:`
configuration anywhere in the call chain fixes it. `DEPENDABOT_ALERTS_TOKEN` — a PAT or
GitHub App installation token with **"Dependabot alerts: read"** — must be forwarded
explicitly through every caller in the chain (`secrets: inherit` does not apply to custom
secrets crossing a `workflow_call` boundary the same way it does for `GITHUB_TOKEN`).
Missing/empty token → the gate fails closed with an explicit `Missing dependabot-alerts-token`
error rather than silently passing.

### Known pitfalls (already fixed org-wide — do not reintroduce)

**1. `pull_request` silently strips secrets from Dependabot's own PRs.** GitHub treats any
PR authored by `dependabot[bot]` like a fork PR for token/secrets purposes: a plain
`pull_request` trigger gets **zero repository secrets and a read-only `GITHUB_TOKEN`**, no
matter what `permissions:` requests — and since both gate workflows exist specifically to
react to Dependabot's own PRs, this broke their entire reason for existing. It went
unnoticed as long as testing only exercised human-authored PRs. Fix: both workflows use
`pull_request_target` instead, which evaluates from the trusted base branch and gets full
secrets/token access. This is safe here specifically because neither workflow ever checks
out or executes the PR's own code — every step is a pure API call (Dependabot Alerts API,
PR metadata via `fetch-metadata`, `gh pr merge` by URL) — which is exactly the case where
`pull_request_target` doesn't carry its usual code-injection risk. **Never revert either
gate template back to a plain `pull_request` trigger.**

**2. A missing `permissions:` block causes total, invisible silence — not a loud failure.**
`critical-vuln-gate.yml`'s own job requests `contents: write` + `security-events: read`. A
reusable-workflow call can only **narrow** permissions from what its caller grants, never
widen them — so a caller file missing its own top-level `permissions:` block doesn't fail
at runtime, it fails to **parse**, and GitHub never triggers the workflow at all: no error,
no failed check, nothing in the Actions tab, zero run history. The only symptom is a repo
with zero check runs where there should be dozens. **Every caller template copy must keep
its `permissions:` block** (`critical-vuln-check.yml`: `contents: write`,
`security-events: read`; `dependabot-auto-merge.yml`: adds `pull-requests: write`).

### Current scope

- Deployed to every active repo in the `simplify9` org.
- Repos with a genuine open critical alert correctly gate `main` (or show a non-blocking warning on `develop`) until the alert is resolved or dismissed — this is expected behavior, not a bug.

---

## Core Architecture & Conventions

### Two-Layer Pattern

```
Caller repository workflow
    └── Reusable workflow  (workflows/*.yml)
            ├── Composite action  (actions/determine-semver)
            ├── Composite action  (actions/docker-build-push)
            ├── Composite action  (actions/helm-generic | helm-deploy)
            └── Composite action  (actions/write-job-summary)
```

Callers only call **reusable workflows**. Composite actions are internal building blocks (except simple utilities like `determine-semver` / `tag-github-origin`). Workflows reference actions via the external `simplify9/.github/.github/actions/<name>@main` path.

### Versioning — `determine-semver`

Every pipeline that produces a deployable artifact computes its version with `determine-semver`: it reads the highest existing `major.minor.N` git tag and outputs `major.minor.(N+1)`. After a successful deploy/publish, `tag-github-origin` writes the tag back so the next run increments from it. Branch behavior is controlled by `release-branch: github.event.repository.default_branch` — the default branch yields a clean release version + tag; other branches yield a qualified prerelease (`x.y.z-<branch>.<run>`).

### Branch-to-Environment Mapping

Per-branch gating lives in the **caller** (template), not inside the reusable workflows:

| Branch | Typical use | How it's wired |
|---|---|---|
| `staging` | Staging/dev | Caller job `if: github.ref == 'refs/heads/staging'` → staging GitHub Environment |
| `main` / `master` | Production | Caller job `if: github.ref == 'refs/heads/main'` → production GitHub Environment |

Mobile workflows additionally gate the release job on `release-environment != '' && !disable-release`.

### Helm Values vs Helm Secret Values

The most important security pattern in the repo. **Never put secrets into `helm-set-values`.**

| Parameter | Passed as | Helm flag | Use for |
|---|---|---|---|
| `helm-set-values` | Workflow **input** | `--set` | Non-sensitive config: replicas, ingress, environment label |
| `helm-set-secret-values` | Workflow **secret** | `--set-string` | Sensitive data: DB connection strings, API keys |

`--set-string` bypasses Helm type coercion and prevents `=`, `SSL:`, `//` in connection strings from being misinterpreted.

```yaml
# Correct
with:
  helm-set-values: 'replicas=2,ingress.enabled=true,environment=production'
secrets:
  helm-set-secret-values: ${{ secrets.MY_DB_CONNECTION_STRING }}

# Wrong — secret exposed as a plain workflow input
with:
  helm-set-values: 'db=${{ secrets.DATABASE_URL }}'
```

### Pinned Tool Versions

| Tool | Pinned version |
|---|---|
| `actions/checkout` | `@v7` |
| `actions/setup-node` | `@v6` |
| `actions/setup-dotnet` | `@v5` |
| `actions/setup-java` | `@v5` |
| `actions/upload-artifact` | `@v7` |
| `actions/download-artifact` | `@v8` |
| `actions/cache` | `@v5` (some CF workflows `@v4`) |
| `azure/setup-helm` | `@v5` |
| `azure/setup-kubectl` | `@v5` |
| `docker/setup-buildx-action` | `@v4` |
| `docker/setup-qemu-action` | `@v4` |
| `docker/login-action` | `@v4` |
| `docker/metadata-action` | `@v6` |
| `docker/build-push-action` | `@v7` |
| `cloudflare/wrangler-action` | `@v4` |
| `gradle/actions/setup-gradle` | `@v5` |
| `ruby/setup-ruby` | `@v1` |
| `maxim-lobanov/setup-xcode` | `@v1` |
| `apple-actions/upload-testflight-build` | `@v5` |
| `r0adkll/upload-google-play` | `@v1` |

Helm/kubectl CLI: the deploy/package actions default to `latest`; some workflows pin (`helm-deploy-values.yml`: Helm `v4.2.0` / kubectl `v1.33.0`; `gateway-chart-cicd.yml`: Helm `v4.2.2`). `gradle/actions/setup-gradle` is pinned to `@v5`; do not switch to the archived `gradle/gradle-build-action` and do not add `cache: gradle` to `setup-java` (it conflicts with `setup-gradle`).

---

## Repository Metadata Standard

Every active repo in the org **must** have a one-line **description** and 3–6 **topics**.
They are the org's lightweight service catalog: the repo list becomes self-explanatory,
and GitHub search / the API can filter by facet (e.g. `org:simplify9 topic:api topic:dotnet`,
`org:simplify9 topic:mobile`).

### Description

- One sentence, sentence case, **no trailing period**, ≤ 120 characters.
- Says what the repo **is** and **for which product**: `Backend REST API for the <Product> platform` — never `<Product> repo.`
- No secrets, hostnames, or contract details — descriptions are visible to every org member.

### Topics

3–6 lowercase topics, one per facet, in this order (minimum 2 only where a facet is
genuinely unknowable — empty stubs, org-config repos):

| # | Facet | Values |
|---|-------|--------|
| 1 | Product / client | The product prefix of the repo name (lowercase). Org-level repos (`SW-*` libraries, `infrastructure-*`, this repo) use `simplify9` |
| 2 | Sub-product | Only when present in the name (e.g. `iot`, `last-mile`) |
| 3 | Component (exactly one) | `api`, `web`, `website`, `mobile`, `cms`, `library`, `integration`, `infrastructure`, `docs`, `desktop`, `monorepo`, `data` |
| 4 | Stack (1–2) | `dotnet`, `react`, `nextjs`, `react-native`, `expo`, `flutter`, `nodejs`, `nestjs`, `strapi`, `medusa`, `php`, `laravel`, `python`, `java`, `kotlin`, `swift`, `kubernetes`, `helm`, `terraform`, `ansible`, `rabbitmq`, `mqtt`, `elasticsearch`, … |
| 5 | Lifecycle (when true) | `legacy`, `poc`, `nuget`, `open-source` |

Example (public library repo): **SW-CloudFiles** → description
`.NET abstraction over cloud file storage providers (S3, Azure, GCS, OCI) using streams and ASP.NET Core DI`,
topics `simplify9 library dotnet nuget open-source`.

**Rules:**

- Controlled vocabulary only — new topics require updating the standard first. A
  half-consistent taxonomy is worse than none.
- Public repos may add up to 3 extra ecosystem topics (e.g. `actions`, `reusable-workflows`)
  for external discoverability.
- **New repos must be created with description + topics.** Drift is corrected with
  [`scripts/backfill-repo-metadata.py`](./scripts/backfill-repo-metadata.py) (dry-run by
  default, `--apply` to write), driven by an internal reviewed CSV — the mapping CSV and
  the full client vocabulary are internal-only and are **not** committed to this public repo.

---

## Troubleshooting

### Checkout fails: `No url found for submodule path '.claude/worktrees/...' in .gitmodules`

Symptom — every job that runs `actions/checkout` dies at the end (the "Removing auth" / submodule cleanup step) with exit code 128, even though the checkout itself succeeded:

```text
Error: fatal: No url found for submodule path '.claude/worktrees/agent-xxxxxxxx' in .gitmodules
Error: The process '/usr/bin/git' failed with exit code 128
```

This is **not** a problem with the reusable workflow — it's a corrupted state in **your (the consumer) repo**. A Claude Code git worktree under `.claude/worktrees/` was accidentally committed. Because that directory contains its own `.git`, git recorded it as a **gitlink** (a `160000` tree entry, the same way submodules are stored) but there's no matching entry in `.gitmodules`. `actions/checkout`'s teardown runs `git submodule foreach --recursive`, hits the URL-less gitlink, and fails. It surfaces on whichever job checks out first (often the versioning job).

**Fix** — in your repo, remove the stray gitlink and stop it recurring:

```sh
git rm --cached -r .claude/worktrees      # drop the gitlink from the index (keeps working tree)
echo ".claude/" >> .gitignore
git commit -m "Remove stray .claude worktree gitlink breaking CI checkout"
git push
```

If the recursive form complains, target the exact path (`git rm --cached .claude/worktrees/agent-xxxxxxxx`). Verify none remain before pushing — this should print nothing:

```sh
git ls-files -s | grep 160000            # any output = a stray gitlink still tracked
```

If the bad commit is on more than one branch, repeat on each affected branch.

### Deploy job shows as "skipped"

- For `reusable-service-cicd.yml`, set `deploy: true` (publishing happens regardless; deploying is opt-in).
- For mobile workflows, the release job needs a non-empty `release-environment` and `disable-release: false`.
- Confirm the relevant kubeconfig secret is set and base64-encoded (`kubeconfig` for ingress-nginx, `kubeconfig-gateway` for gateway-api).

### Build directory not found (Vite / Next.js)

- Vite (`vite-cloudflare-worker.yml`): set `assets_dir: dist`.
- Next.js (`next-cloudflare-worker.yaml`): default `assets_dir` is `.open-next/assets` — change only if your build differs.

### Helm parse error: "SSL: command not found" or malformed `--set` value

A secret value contains special characters being parsed by the shell. Move it from `helm-set-values` to `helm-set-secret-values` (a workflow secret, applied with `--set-string`).

### iOS: "No matching provisioning profile"

Confirm the provisioning profile matches the bundle ID and team ID. Manual signing is mandatory in CI; the certificate is imported into a temporary keychain before the archive step.

### Android versionCode conflicts on Play Console

Increase `version-code-offset` (default `80000`) above your previous CI system's last published versionCode.

### Certificate issuance times out / stays pending (Gateway API)

The pipeline runs a DNS pre-flight and purges failed ACME Orders. The two most common causes:

- **DNS not pointing to the gateway** — create the A record before running.
- **Cloudflare orange-cloud proxy** — cert-manager's HTTP-01 self-check can't traverse the proxy; set the record to **DNS-only (grey cloud)** for issuance, then re-enable once `Ready`.

### kubeconfig not working

Ensure it is base64-encoded before storing as a secret:

```sh
base64 -w 0 ~/.kube/config   # Linux
base64 -b 0 ~/.kube/config   # macOS
```

(Workflows also accept raw-YAML kubeconfig; both are auto-detected.)

---

## Contributing

1. Create a feature branch.
2. Test changes by calling the workflow/action from a separate repo on a branch (point a caller at `@<branch>`) and watching the Actions run — there is no local test runner.
3. Follow all conventions in [AGENTS.md](./AGENTS.md) — pinned action versions, the 4-pillar log framework, composite-action shell requirements, and secrets-vs-inputs.
4. If you change a workflow that has a starter template, update the paired `workflow-templates/<name>.yml` and `.properties.json`.
5. Update both `README.md` and `AGENTS.md` in the same change.

**Key rules:**
- Every `run:` step in a composite action must have `shell: bash`.
- All new inputs need `description:` and a sensible `default:` or `required: true`.
- Do not add `on: push:` / `on: pull_request:` triggers to files in `.github/workflows/`.
- Secrets go under `on.workflow_call.secrets:`, never as inputs.
- Optional deploys are gated (`deploy: false`) or bound to a GitHub Environment.
