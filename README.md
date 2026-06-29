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
- [Composite Action Reference](#composite-action-reference)
- [Core Architecture & Conventions](#core-architecture--conventions)
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

---

## Prerequisites — Secrets

Set these as **Organization** or repository secrets. Names below are the secret keys the workflows expect under `secrets:` (some workflows accept `secrets: inherit`).

### Frontend (Cloudflare Workers)

```
cloudflare_api_token     # API token with Workers + DNS permissions
cloudflare_account_id    # Cloudflare account ID
```

### Service / Backend (Kubernetes + Container Registry + Helm)

```
registry-username        # Container registry username (GHCR: github.actor)
registry-password        # Container registry password/token (GHCR: GITHUB_TOKEN)
kubeconfig               # Base64-encoded (or raw YAML) kubeconfig — ingress-nginx deploys
kubeconfig-gateway       # Base64 kubeconfig for the gateway-api routing mode (reusable-service-cicd)
chartmuseum-username     # ChartMuseum username (when publishing/pulling via ChartMuseum)
chartmuseum-password     # ChartMuseum password/token
helm-set-secret-values   # Sensitive Helm values, applied with --set-string
github-token             # Token for tagging the origin (falls back to built-in GITHUB_TOKEN)
nuget-api-key            # NuGet API key (only if publishing packages)
```

### Mobile — iOS

```
ios-p12-base64                    # Base64-encoded .p12 signing certificate
ios-p12-password                  # Password for the .p12
ios-mobileprovision-base64        # Base64-encoded .mobileprovision
ios-team-id                       # (optional) explicit Apple Team ID
appstore-api-key-id               # App Store Connect API Key ID
appstore-issuer-id                # App Store Connect Issuer ID
appstore-api-private-key-base64   # Base64-encoded App Store Connect .p8 private key
```

### Mobile — Android

```
android-keystore-base64           # Base64-encoded .jks / .keystore
android-keystore-password         # Keystore password
android-key-alias                 # Key alias
android-key-password              # Key password
google-play-service-account-json  # Google Play service account JSON
```

---

## Repository Structure

```
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
│   │   └── android-build.yml
│   └── actions/                  ← composite actions
│       ├── determine-semver/
│       ├── tag-github-origin/
│       ├── docker-build-push/
│       ├── helm-deploy/
│       ├── helm-deploy-s9generic/
│       ├── helm-generic/
│       ├── helm-package-push/
│       ├── gateway-routing/      (render.sh)
│       ├── gateway-onboard/      (onboard.sh)
│       ├── dotnet-build/
│       ├── dotnet-pack-push/
│       ├── generate-wrangler-config/
│       ├── setup-cloudflare-domain/
│       ├── ios-install-cert/
│       ├── ios-install-profile/
│       ├── xcode-build/
│       ├── xcode-export/
│       └── write-job-summary/
└── workflow-templates/           ← org starter templates (*.yml + *.properties.json)
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

**Required secrets:** `cloudflare_api_token`, `cloudflare_account_id`

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

**Required secrets:** `cloudflare_api_token`, `cloudflare_account_id`

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
| `nuget-projects` | | `''` | NuGet projects glob (empty = skip NuGet) |
| `deploy` | | `false` | Deploy the published chart after publishing |
| `routing-mode` | | `ingress-nginx` | `ingress-nginx` or `gateway-api` |
| `deploy-namespace` | | `playground` | Kubernetes namespace |
| `deploy-environment` | | `Development` | GitHub Environment for the deploy job |
| `helm-set-values` | | `''` | Non-secret `--set` values |
| `gateway-hostnames` | | `''` | Hostnames for the HTTPRoute (gateway-api) |
| `major-version` / `minor-version` | | `1` / `0` | Semver components |

**Secrets** (conditionally required): `registry-username`, `registry-password`, `chartmuseum-username` + `chartmuseum-password` (for `chartmuseum`/`both`), `kubeconfig` (deploy + ingress-nginx) or `kubeconfig-gateway` (deploy + gateway-api), `helm-set-secret-values`, `nuget-api-key`, `github-token`.

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

**Secrets:** `registry-username`, `registry-password`, `kubeconfig`, `github-token`, `helm-set-secret-values`, `nuget-api-key`, `nuget-source`, `NUGET_PACKAGE_PAT`.

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

**Secrets:** `registry-username`, `registry-password`, `kubeconfig`, `github-token`, `helm-set-secret-values`, `nuget-api-key`, `nuget-source`, `NUGET_PACKAGE_PAT`.

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

**Secrets:** `kubeconfig` (or `kubeconfig64` alias), `helm-set-secret-values`.

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
| `validate-configmap` | | `true` | Validate ConfigMap gating + merged keys |

**Secrets:** `registry-username`, `registry-password` (required); `github-token` (optional — used by the tag job, falls back to `GITHUB_TOKEN`).

**Outputs:** `version`, `chart-name`, `chart-package`, `chart-repo-url`.

> **TODO — migrate to OCI.** ChartMuseum HTTP upload is the legacy distribution path. Publishing via an OCI registry (`helm push chart.tgz oci://...`), as `reusable-service-cicd.yml` already supports, gives immutable, digest-pinned, signable charts and removes the standalone ChartMuseum dependency.

---

### Mobile · iOS & Android

Both mobile workflows have a **build** job (runs unconditionally) and a **release** job (`release_with_environment`) gated by `if: release-environment != '' && !disable-release` and bound to a named GitHub Environment for approvals. Per-branch dev/prod selection is done by the `workflow_dispatch` caller (see the Android/iOS starter templates).

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
```

**Notes:** Gradle uses `gradle/actions/setup-gradle@v5` (do not use the archived `gradle/gradle-build-action`, and do not add `cache: gradle` to `setup-java` — it conflicts). The workflow sets `org.gradle.caching=true` itself, so callers no longer need to. NDK `27.1.12297006` (r27b LTS) is pinned and installed via `sdkmanager` (not `actions/cache` — the Android SDK dir is root-owned). Use the **Android App CI/CD** starter template for a `workflow_dispatch` entry point.

---

## Composite Action Reference

Call composite actions directly in job steps:

```yaml
uses: simplify9/.github/.github/actions/<name>@main
```

All 18 actions are **composite** (`runs.using: composite`). Only `gateway-onboard` (`onboard.sh`) and `gateway-routing` (`render.sh`) keep logic in a sibling script; the rest is inline bash.

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
| `ios-install-profile` | Install a `.mobileprovision`, extract UUID/Name (`profileBase64`) |
| `xcode-build` | `xcodebuild archive` with manual signing (`workspace`, `scheme`, `archivePath`, `developmentTeam`, `provisioningProfileUuid`, `keychainPath`) |
| `xcode-export` | `xcodebuild -exportArchive` → `.ipa` (`archivePath`, `exportOptionsPlist`, `exportPath`) |

### Shared

| Action | Purpose |
|---|---|
| `write-job-summary` | Append a standardized, status-aware section to `$GITHUB_STEP_SUMMARY` (`title`, `status`, `icon`, `details`) |

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

## Troubleshooting

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
