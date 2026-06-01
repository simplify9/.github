# Simplify9 Reusable CI/CD Library

> Organization-wide shared GitHub Actions workflows and composite actions for Simplify9 projects.  
> Callers reference this repo with `@main` — no versioned tags exist.

---

## Table of Contents

- [Which Template Should I Use?](#which-template-should-i-use)
- [Prerequisites — Organization Secrets](#prerequisites--organization-secrets)
- [Repository Structure](#repository-structure)
- [Workflow Reference](#workflow-reference)
  - [Frontend · Cloudflare Pages](#frontend--cloudflare-pages)
  - [Frontend · Cloudflare Workers](#frontend--cloudflare-workers)
  - [API & Backend · Kubernetes](#api--backend--kubernetes)
  - [Mobile · iOS & Android](#mobile--ios--android)
  - [Helm Chart CI/CD](#helm-chart-cicd)
- [Composite Action Reference](#composite-action-reference)
- [Core Architecture & Conventions](#core-architecture--conventions)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

---

## Which Template Should I Use?

| Stack | Deployment target | Use this workflow |
|---|---|---|
| React / Vue / Svelte / Vite (static) | Cloudflare Pages | [`vite-ci.yml`](#vite-ciyml) |
| Next.js with SSR | Cloudflare Workers (OpenNext) | [`next-cloudflare-worker.yaml`](#next-cloudflare-workeryaml) |
| Next.js static export | Cloudflare Workers | [`next-static-cloudflare-worker.yaml`](#next-static-cloudflare-workeryaml) |
| Vite (Workers edge deploy) | Cloudflare Workers | [`vite-cloudflare-worker.yml`](#vite-cloudflare-workeryml) |
| REST API / microservice | Docker + Kubernetes | [`api-cicd.yml`](#api-cicdyml) |
| .NET application | NuGet + Docker + Kubernetes | [`sw-cicd.yml`](#sw-cicdyml) |
| Docker image only (no deploy) | Container registry | [`ci-docker.yaml`](#ci-dockeryaml) |
| Helm deploy only (no Docker) | Kubernetes via Helm | [`ci-helm.yaml`](#ci-helmyaml) |
| Helm deploy from a values file | Kubernetes via Helm | [`helm-deploy-values.yml`](#helm-deploy-valuesyml) |
| iOS app | TestFlight | [`generic-ios-testflight.yml`](#generic-ios-testflightyml) |
| Android app | Google Play | [`generic-android-google-play.yml`](#generic-android-google-playyml) |
| Helm chart development | ChartMuseum / OCI | [`generic-chart-helm.yml`](#generic-chart-helmyml) |
| Helm chart with Gateway API | ChartMuseum | [`generic-gateway-chart-cicd.yml`](#generic-gateway-chart-cicdyml) |

---

## Prerequisites — Organization Secrets

Set these secrets once at the **Organization** level so every repo inherits them automatically.

### Frontend (Cloudflare)

```
CLOUDFLARE_API_TOKEN     # API token with Pages:Edit and Workers:Edit permissions
CLOUDFLARE_ACCOUNT_ID    # Your Cloudflare account ID
```

### API / Backend (Kubernetes + Container Registry)

```
KUBECONFIG               # Base64-encoded kubeconfig  →  base64 -w 0 ~/.kube/config
```

Container registry credentials are resolved dynamically from org/repo variables by profile (see [`ci-docker.yaml`](#ci-dockeryaml)).  
The default profile is `S9`, so set:

```
S9_REGISTRY_USERNAME     # Registry username
S9_REGISTRY_TOKEN        # Registry password / token
S9_KUBECONFIG            # (used by ci-helm.yaml)  base64-encoded kubeconfig
```

### .NET / NuGet

```
NUGET_API_KEY            # NuGet.org API key (only if publishing packages)
```

### Mobile — iOS

```
IOS_P12_BASE64                       # Base64-encoded .p12 signing certificate
IOS_P12_PASSWORD                     # Password for the .p12
IOS_PROVISIONING_PROFILE_BASE64      # Base64-encoded .mobileprovision
APPSTORE_API_KEY_ID                  # App Store Connect API Key ID
APPSTORE_ISSUER_ID                   # App Store Connect Issuer ID
APPSTORE_API_KEY_BASE64              # Base64-encoded App Store Connect .p8 private key
```

### Mobile — Android

```
ANDROID_KEYSTORE_BASE64              # Base64-encoded .jks or .keystore file
ANDROID_KEYSTORE_PASSWORD            # Keystore password
ANDROID_KEY_ALIAS                    # Key alias
ANDROID_KEY_PASSWORD                 # Key password
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON     # Google Play service account JSON
```

---

## Repository Structure

```
.github/                        ← workspace root
└── .github/
    ├── workflows/              ← reusable workflows  (workflow_call triggers only)
    │   ├── vite-ci.yml
    │   ├── next-cloudflare-worker.yaml
    │   ├── next-static-cloudflare-worker.yaml
    │   ├── vite-cloudflare-worker.yml
    │   ├── api-cicd.yml
    │   ├── sw-cicd.yml
    │   ├── ci-docker.yaml
    │   ├── ci-helm.yaml
    │   ├── helm-deploy-values.yml
    │   ├── generic-ios-testflight.yml
    │   ├── generic-android-google-play.yml
    │   ├── ios-testflight-dispatch-template.yml
    │   ├── android-google-play-dispatch-template.yml
    │   ├── generic-chart-helm.yml
    │   ├── generic-gateway-chart-cicd.yml
    │   └── generic-gateway-helm-template.yml
    └── actions/                ← composite actions
        ├── determine-semver/
        ├── tag-github-origin/
        ├── docker-build-push/
        ├── helm-deploy/
        ├── helm-deploy-s9generic/
        ├── helm-generic/
        ├── helm-package-push/
        ├── dotnet-build/
        ├── dotnet-pack-push/
        ├── generate-wrangler-config/
        ├── setup-cloudflare-project/
        ├── setup-cloudflare-domain/
        ├── ios-install-cert/
        ├── ios-install-profile/
        ├── xcode-setup/
        ├── xcode-build/
        ├── xcode-export/
        └── upload-google-play-release/
```

---

## Workflow Reference

All workflows are **reusable** — they have `on: workflow_call:` only. Call them from your repo:

```yaml
uses: simplify9/.github/.github/workflows/<name>.yml@main
```

---

### Frontend · Cloudflare Pages

---

#### `vite-ci.yml`

Deploys any Vite-based application (React, Vue, Svelte, vanilla JS) to Cloudflare Pages with automatic project creation and optional custom domain.

**Key inputs**

| Input | Required | Default | Description |
|---|---|---|---|
| `project-name` | ✅ | — | Cloudflare Pages project base name |
| `environment` | | `development` | Environment name |
| `build-directory` | | `build` | Build output directory (`dist` for Vite, `build` for CRA) |
| `package-manager` | | `npm` | `npm`, `yarn`, or `pnpm` |
| `build-command` | | `npm run build` | Build command |
| `project-name-suffix` | | `''` | Append `-dev`, `-staging`, etc. |
| `custom-domain` | | `''` | Custom domain to configure |
| `fail-on-domain-error` | | `false` | Fail the run if domain setup fails |
| `run-tests` | | `true` | Run tests before deploy |
| `node-version` | | `24` | Node.js version |

**Required secrets:** `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`

**Minimal example**

```yaml
jobs:
  deploy-dev:
    if: github.ref == 'refs/heads/development'
    uses: simplify9/.github/.github/workflows/vite-ci.yml@main
    with:
      project-name: my-app
      environment: development
      build-directory: dist
      project-name-suffix: -dev
      custom-domain: dev.mysite.com
    # secrets inherited from org

  deploy-prod:
    if: github.ref == 'refs/heads/main'
    uses: simplify9/.github/.github/workflows/vite-ci.yml@main
    with:
      project-name: my-app
      environment: production
      build-directory: dist
      custom-domain: mysite.com
      fail-on-domain-error: true
```

---

### Frontend · Cloudflare Workers

---

#### `next-cloudflare-worker.yaml`

Deploys Next.js applications with full SSR to Cloudflare Workers using **OpenNext.js**. Compatible with Next.js 15.

**Key inputs**

| Input | Required | Default | Description |
|---|---|---|---|
| `project_name` | ✅ | — | Worker project base name |
| `environment` | ✅ | — | Wrangler environment (`staging`, `production`) |
| `route` | | `''` | Custom domain / route (falls back to repo var `CLOUDFLARE_ROUTE`) |
| `package_manager` | | `yarn` | `npm`, `yarn`, or `pnpm` |
| `node_version` | | `24` | Node.js version |
| `compatibility_date` | | `2026-05-01` | Cloudflare compatibility date |
| `build_script` | | `build` | npm script to run for build |
| `run_lint` | | `true` | Run lint step |

**Required secrets:** `cloudflare_api_token`, `cloudflare_account_id`

**Example**

```yaml
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/next-cloudflare-worker.yaml@main
    with:
      project_name: my-nextjs-app
      environment: production
      route: myapp.com
      package_manager: yarn
    secrets:
      cloudflare_api_token: ${{ secrets.CLOUDFLARE_API_TOKEN }}
      cloudflare_account_id: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
```

---

#### `next-static-cloudflare-worker.yaml`

Deploys Next.js **static export** (`output: 'export'`) to Cloudflare Workers. Same interface as `next-cloudflare-worker.yaml` but for static-only builds.

---

#### `vite-cloudflare-worker.yml`

Deploys Vite apps to Cloudflare Workers (edge). Uses the `generate-wrangler-config` action to produce `wrangler.toml` dynamically.

**Key inputs**

| Input | Required | Default | Description |
|---|---|---|---|
| `project_name` | ✅ | — | Worker project name |
| `environment` | ✅ | — | Wrangler environment |
| `route` | ✅ | — | Route pattern (e.g. `mysite.com/*`) |
| `assets_dir` | | `dist` | Static assets directory |
| `node_version` | | `24` | Node.js version |
| `package_manager` | | `yarn` | `npm`, `yarn`, or `pnpm` |
| `compatibility_date` | | `2026-05-01` | Cloudflare compatibility date |

**Required secrets:** `cloudflare_api_token`, `cloudflare_account_id`

---

### API & Backend · Kubernetes

---

#### `api-cicd.yml`

Full CI/CD pipeline: builds a Docker image, packages a Helm chart, and deploys to Kubernetes across up to three environments. Supports both **local charts** (checked in to the repo) and **external charts** (pulled from `https://charts.sf9.io`).

**All deploy jobs are disabled by default.** Set `deploy-to-<env>: true` to enable.

**Key inputs**

| Input | Required | Default | Description |
|---|---|---|---|
| `chart-name` | ✅ | — | Your app name in Kubernetes (release name, image name) |
| `container-registry` | | `ghcr.io` | Container registry URL |
| `image-name` | | (repo name) | Docker image name |
| `helm-image-repo` | | (registry/image) | Value for `image.repo` in Helm chart |
| `chart-path` | | `./chart` | Local chart dir or external repo URL (e.g. `https://charts.sf9.io`) |
| `source-chart-name` | | `s9genericchart` | Chart to pull when using an external repo |
| `chart-version` | | `latest` | External chart version to pull |
| `deploy-to-development` | | `false` | Enable dev deploy (triggers on `development` branch) |
| `deploy-to-staging` | | `false` | Enable staging deploy (triggers on `staging` branch) |
| `deploy-to-production` | | `false` | Enable prod deploy (triggers on `main`/`master`) |
| `development-namespace` | | `development` | Kubernetes namespace for dev |
| `development-helm-set-values` | | — | Extra `--set` values for dev |
| `major-version` | | `1` | Semver major |
| `minor-version` | | `0` | Semver minor |

**Secrets**

| Secret | Description |
|---|---|
| `kubeconfig` | Base64-encoded kubeconfig |
| `registry-username` | Container registry username |
| `registry-password` | Container registry password/token |
| `development-helm-set-secret-values` | `--set-string` values for dev (DB strings, API keys) |
| `staging-helm-set-secret-values` | `--set-string` values for staging |
| `production-helm-set-secret-values` | `--set-string` values for production |

**Example — ghcr.io with local chart**

```yaml
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      chart-name: my-api
      container-registry: ghcr.io
      image-name: simplify9/my-api
      deploy-to-development: true
      deploy-to-production: true
      development-namespace: my-api-dev
      production-namespace: my-api
      development-helm-set-values: >-
        ingress.enabled=true,
        ingress.hosts={dev.myapi.com},
        replicas=1
      production-helm-set-values: >-
        ingress.enabled=true,
        ingress.hosts={myapi.com},
        replicas=3
    secrets:
      kubeconfig: ${{ secrets.KUBECONFIG }}
      registry-username: ${{ github.actor }}
      registry-password: ${{ secrets.GITHUB_TOKEN }}
      production-helm-set-secret-values: ${{ secrets.PROD_HELM_SECRETS }}
```

**Example — external SF9 generic chart**

```yaml
with:
  chart-name: my-api
  chart-path: https://charts.sf9.io
  source-chart-name: s9genericchart
  chart-version: latest
```

---

#### `sw-cicd.yml`

Full CI/CD pipeline for **.NET applications**: semantic versioning → .NET build/test → optional NuGet publish → Docker build/push → Helm chart package/push → Kubernetes deploy.

**Key inputs**

| Input | Required | Default | Description |
|---|---|---|---|
| `chart-name` | ✅ | — | Helm chart / app name |
| `dotnet-version` | | `8.0.x` | .NET SDK version |
| `nuget-projects` | | `''` | Glob for projects to publish as NuGet (empty = skip) |
| `test-projects` | | `**/*UnitTests/*.csproj` | Test projects glob |
| `run-tests` | | `false` | Run tests |
| `chart-path` | | `./chart` | Helm chart directory |
| `chart-publish-method` | | `oci` | `oci` or `chartmuseum` |
| `container-registry` | | `ghcr.io` | Container registry |
| `deploy-to-development` | | `false` | Enable dev deploy |
| `development-namespace` | | `development` | Dev namespace |
| `helm-set-values` | | — | Non-sensitive `--set` config values |
| `major-version` | | `1` | Semver major |
| `minor-version` | | `0` | Semver minor |

**Secrets**

| Secret | Description |
|---|---|
| `kubeconfig` | Base64-encoded kubeconfig |
| `nuget-api-key` | NuGet API key (if publishing) |
| `registry-username` | Container registry username |
| `registry-password` | Registry password/token |
| `helm-set-secret-values` | Sensitive Helm values via `--set-string` (DB strings, API keys) |

**Critical:** Pass secrets through `helm-set-secret-values`, never through `helm-set-values`. See [Helm Values vs Secrets](#helm-values-vs-helm-secret-values).

**Example**

```yaml
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/sw-cicd.yml@main
    with:
      chart-name: my-dotnet-api
      dotnet-version: 8.0.x
      nuget-projects: src/MyApp.Sdk/MyApp.Sdk.csproj
      run-tests: 'true'
      deploy-to-development: true
      development-namespace: my-api-dev
      helm-set-values: >-
        ingress.enabled=true,
        ingress.hosts={dev.myapi.com},
        replicas=1,
        environment=Development
    secrets:
      kubeconfig: ${{ secrets.KUBECONFIG }}
      nuget-api-key: ${{ secrets.NUGET_API_KEY }}
      helm-set-secret-values: ${{ secrets.DEV_HELM_SECRET_VALUES }}
```

---

#### `ci-docker.yaml`

Builds and pushes a Docker image only — no Helm, no Kubernetes. Uses a **profile-based credential resolver** so the same workflow works across registries (DigitalOcean, Docker Hub, GHCR) without code changes.

**Credential resolution** for registry base URL (first match wins):
1. Org/repo variable `<PROFILE>_DOCKER_REGISTRY`
2. Variable `DOCKER_REGISTRY`
3. Input `docker_registry` (default: `registry.digitalocean.com/sf9cr`)

**Key inputs**

| Input | Required | Default | Description |
|---|---|---|---|
| `app_name` | ✅ | — | Image name (also Helm release name if used with `ci-helm.yaml`) |
| `registry_profile` | | `S9` | Profile prefix for credential vars/secrets |
| `version` | | `staging` | Label embedded in image tag |
| `docker_registry` | | `registry.digitalocean.com/sf9cr` | Fallback registry |
| `dockerfile` | | `Dockerfile` | Path to Dockerfile |
| `build_context` | | `.` | Docker build context |

**Required secrets (profile-scoped):** `<PROFILE>_REGISTRY_USERNAME`, `<PROFILE>_REGISTRY_TOKEN`

**Image tags produced:**  
`<registry>/<app_name>:github-<branch>-<version>`  
`<registry>/<app_name>:github-<branch>-<run_number>`

**Docker layer caching:** Registry-backed BuildKit cache is enabled using a dedicated `:buildcache` tag (`type=registry,mode=max`). On warm runs, unchanged layers are restored from the registry and show as `CACHED` in the build log. The `:buildcache` tag is written to the same registry using the existing credentials — no additional auth is required.

**Example**

```yaml
jobs:
  build:
    uses: simplify9/.github/.github/workflows/ci-docker.yaml@main
    with:
      app_name: my-service
      version: prod
```

---

#### `ci-helm.yaml`

Deploys a Helm chart to Kubernetes. Typically called after `ci-docker.yaml` in a two-job pipeline. Resolves kubeconfig from `<PROFILE>_KUBECONFIG` secret automatically.

**Key inputs**

| Input | Required | Default | Description |
|---|---|---|---|
| `app_name` | ✅ | — | Helm release name |
| `namespace` | ✅ | — | Target Kubernetes namespace |
| `ingress_host` | ✅ | — | Primary ingress hostname |
| `ingress_tls_secret` | ✅ | — | TLS secret name for ingress |
| `registry_profile` | | `S9` | Profile prefix for kubeconfig secret |
| `chart` | | `s9genericchart` | Chart name |
| `chart_repo` | | `https://charts.sf9.io` | Helm repo URL |
| `environment_label` | | `Staging` | Value for `--set environment=` |
| `service_target_port` | | `5000` | Service target port |
| `image_repo` | | `registry.digitalocean.com/sf9cr` | Container image repo (no tag) |
| `helm_timeout` | | `15m` | Helm deploy timeout |
| `ingress_paths` | | `- /` | YAML list of ingress paths |
| `extra_set_values` | | `''` | Newline-separated extra `--set key=value` pairs |

**Required secret:** `<PROFILE>_KUBECONFIG`

**Ingress path configuration**

```yaml
ingress_paths: |
  - /
  - /api
  - /docs
```

**Example — combined build + deploy pipeline**

```yaml
jobs:
  build:
    uses: simplify9/.github/.github/workflows/ci-docker.yaml@main
    with:
      app_name: my-service

  deploy:
    needs: build
    uses: simplify9/.github/.github/workflows/ci-helm.yaml@main
    with:
      app_name: my-service
      namespace: my-namespace
      ingress_host: myservice.example.com
      ingress_tls_secret: myservice-tls
      ingress_paths: |
        - /
        - /api
```

---

#### `helm-deploy-values.yml`

Deploys a Helm chart using a **values file** from the calling repository. Useful when charts have complex configurations that do not fit `--set` flags.

**Key inputs**

| Input | Required | Default | Description |
|---|---|---|---|
| `release-name` | ✅ | — | Helm release name |
| `chart-name` | ✅ | — | Chart name in the repo |
| `chart-repo` | ✅ | — | Helm chart repo URL |
| `namespace` | ✅ | — | Kubernetes namespace |
| `values-file` | | `values.yaml` | Path to values file in the calling repo |
| `image-tag` | | `''` | Image tag to set |
| `global-environment` | | `''` | Value for `global.environment` |
| `ingress-host` | | `''` | Ingress hostname |
| `ingress-tls-secret` | | `''` | TLS secret name |
| `helm-version` | | `v3.21.0` | Helm CLI version |
| `kubectl-version` | | `v1.33.0` | kubectl CLI version |

**Required secret:** `kubeconfig`

---

### Mobile · iOS & Android

---

#### `generic-ios-testflight.yml`

Builds an iOS application and uploads it to TestFlight. Supports React Native and native Swift/ObjC projects. Uses **manual signing only** in CI.

**Key inputs**

| Input | Required | Default | Description |
|---|---|---|---|
| `bundle-id` | ✅ | — | App bundle identifier |
| `scheme` | ✅ | — | Xcode scheme to build |
| `workspace` | ✅ | — | Path to `.xcworkspace` |
| `configuration` | | `Release` | Build configuration |
| `xcode-version` | | `''` | Xcode major or major.minor (e.g. `16.4`) |
| `development-team` | ✅ | — | Apple Developer Team ID |
| `macos-runner` | | `macos-latest` | macOS runner label |
| `node-version` | | `24` | Node.js version (for React Native) |
| `package-manager` | | `yarn` | `yarn` or `npm` |
| `use-simplify9-xcode-setup` | | `true` | Run `xcode-setup` (pod install + selector) |
| `ios-dir` | | `ios` | iOS directory for pod operations |
| `artifact-name` | | `app` | Artifact name for IPA transfer between jobs |
| `release-environment` | | `''` | GitHub environment for release job (optional) |
| `disable-release` | | `false` | Build only, skip TestFlight upload |

**Required secrets**

| Secret | Description |
|---|---|
| `p12-base64` | Base64-encoded `.p12` signing certificate |
| `p12-password` | `.p12` password |
| `provisioning-profile-base64` | Base64-encoded `.mobileprovision` |
| `appstore-api-key-id` | App Store Connect API Key ID |
| `appstore-issuer-id` | App Store Connect Issuer ID |
| `appstore-api-key-base64` | Base64-encoded `.p8` private key |

**Example**

```yaml
jobs:
  build-and-release:
    uses: simplify9/.github/.github/workflows/generic-ios-testflight.yml@main
    with:
      bundle-id: com.mycompany.myapp
      scheme: MyApp
      workspace: MyApp.xcworkspace
      xcode-version: "16"
      development-team: ABCDE12345
      package-manager: yarn
    secrets:
      p12-base64: ${{ secrets.IOS_P12_BASE64 }}
      p12-password: ${{ secrets.IOS_P12_PASSWORD }}
      provisioning-profile-base64: ${{ secrets.IOS_PROVISIONING_PROFILE_BASE64 }}
      appstore-api-key-id: ${{ secrets.APPSTORE_API_KEY_ID }}
      appstore-issuer-id: ${{ secrets.APPSTORE_ISSUER_ID }}
      appstore-api-key-base64: ${{ secrets.APPSTORE_API_KEY_BASE64 }}
```

**Notes:**
- Always uses **manual signing** (`signingStyle: manual`) — automatic signing requires an interactive Xcode session unavailable in CI.
- Certificate and profile installation uses `ios-install-cert` and `ios-install-profile` composite actions internally.
- **CocoaPods caching:** The `~/.cocoapods/repos` spec repository and `ios/Pods` directory are cached between runs, keyed on `Podfile.lock`. This eliminates the spec repo re-download on warm runs (typically the largest time sink). The cache is bypassed automatically when `clean-reinstall-pods: true` is set.
- Two release paths exist: `release` (no environment protection) and `release_with_environment` (with approval gate via `release-environment` input).
- Use `ios-testflight-dispatch-template.yml` to add a manual `workflow_dispatch` trigger to your repo.

---

#### `generic-android-google-play.yml`

Builds a signed Android App Bundle (AAB) and publishes it to Google Play.

**Key inputs**

| Input | Required | Default | Description |
|---|---|---|---|
| `app-id` | ✅ | — | Android applicationId (package name) |
| `gradle-task` | ✅ | — | Gradle task (e.g. `bundleRelease`) |
| `keystore-output-path` | ✅ | — | Path where keystore is written |
| `app-slug` | | `app` | Output AAB file name slug |
| `version-prefix` | | `1.0.0` | Base version (X.Y.Z) |
| `version-code-offset` | | `80000` | Added to `github.run_number` for versionCode. Set high when migrating from another CI system to avoid Play Console collisions. |
| `version-name-offset` | | `0` | Added to `github.run_number` for versionName |
| `java-version` | | `17` | Java version (temurin) |
| `node-version` | | `24` | Node.js version (for React Native) |
| `package-manager` | | `yarn` | `yarn` or `npm` |
| `build-root-directory` | | `.` | Gradle project root |
| `release-environment` | | `''` | GitHub environment name for release job |
| `disable-release` | | `false` | Build only, skip Play Store upload |
| `artifact-name` | | `app` | Artifact name for AAB transfer between jobs |

**Required secrets**

| Secret | Description |
|---|---|
| `keystore-base64` | Base64-encoded keystore (`.jks` / `.keystore`) |
| `keystore-password` | Keystore password |
| `key-alias` | Key alias |
| `key-password` | Key password |
| `service-account-json` | Google Play service account JSON |

**Example**

```yaml
jobs:
  build-and-release:
    uses: simplify9/.github/.github/workflows/generic-android-google-play.yml@main
    with:
      app-id: com.mycompany.myapp
      gradle-task: bundleRelease
      keystore-output-path: /tmp/my-app.keystore
      version-prefix: "2.0.0"
      version-code-offset: "80000"
      package-manager: yarn
    secrets:
      keystore-base64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
      keystore-password: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
      key-alias: ${{ secrets.ANDROID_KEY_ALIAS }}
      key-password: ${{ secrets.ANDROID_KEY_PASSWORD }}
      service-account-json: ${{ secrets.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON }}
```

**Notes:**
- Uses `gradle/actions/setup-gradle@v5` with Gradle home caching enabled (`caches`, `notifications`, `wrapper` directories). Do not use `gradle/gradle-build-action` — that repo is archived. Do not add `cache: gradle` to `actions/setup-java` — it conflicts with `setup-gradle` caching.
- **Caller repo requirement for task-output caching:** Add the following to `android/gradle.properties` (or your `build-root-directory`) to enable task-level output reuse (`FROM-CACHE`). Without this, Gradle home caching still works but individual task outputs are not reused:
  ```properties
  org.gradle.caching=true
  org.gradle.parallel=true
  org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g
  ```
- **Android NDK pre-install:** NDK versions are installed via `sdkmanager` before the Gradle build. `actions/cache` cannot be used for `/usr/local/lib/android/sdk/` on GitHub-hosted runners — that directory is root-owned and `tar` extraction fails with permission errors. `sdkmanager` has the correct elevated permissions and installs both required NDK versions directly.
- **Metro transform cache:** The Metro JS transform cache is stored in `.metro-cache` at the workspace root (set via `METRO_CACHE_DIR` env on the build step) and persisted between runs via `actions/cache@v4`, keyed on the lockfile hash. This eliminates the `WARN the transform cache was reset` message that caused Metro to retranspile all JS from scratch on every run.
- **Node.js 24 opt-in:** All three jobs set `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true` at job level, opting in early ahead of GitHub's Node.js 20 retirement on September 16th 2026.
- The `upload-google-play-release` action is **Docker-based** — it calls the Google Play Android Publisher API via Python. Modifying `play_upload.py` takes effect immediately (Docker image rebuilt per run).
- Use `android-google-play-dispatch-template.yml` to add a `workflow_dispatch` trigger to your repo.

---

### Helm Chart CI/CD

---

#### `generic-chart-helm.yml`

Full CI/CD pipeline for developing a **Helm chart**: lint → template render → package → push to ChartMuseum at `https://charts.sf9.io`.

**Key inputs**

| Input | Required | Default | Description |
|---|---|---|---|
| `chart-path` | | `chart` | Path to chart directory |
| `chartmuseum-url` | | `https://charts.sf9.io/api/charts` | ChartMuseum upload endpoint |
| `version-prefix` | | `1.0` | Semver `major.minor` prefix |
| `helm-version` | | `v3.21.0` | Helm CLI version |
| `update-dependencies` | | `true` | Run `helm package --dependency-update` |

**Required secrets:** `registry-username`, `registry-password`

---

#### `generic-gateway-chart-cicd.yml`

CI/CD for **Cilium Gateway API-aware** Helm charts. Extends `generic-chart-helm.yml` with routing mode validation (default / ingress / gateway / dual) and ConfigMap gating tests.

**Key inputs** — same as `generic-chart-helm.yml`, plus:

| Input | Required | Default | Description |
|---|---|---|---|
| `validate-routing` | | `true` | Validate all four routing rendering modes |
| `validate-configmap` | | `true` | Validate ConfigMap gating and merged key rendering |

**Outputs:** `version`, `chart-name`, `chart-package`, `helm-chart` (ChartMuseum URL)

---

#### `generic-gateway-helm-template.yml`

Runs `helm template` rendering validation only — no packaging, no pushing. Use in pull requests to verify chart correctness without publishing.

---

## Composite Action Reference

Call composite actions directly in job steps:

```yaml
uses: simplify9/.github/.github/actions/<name>@main
```

### Versioning

| Action | Purpose | Key inputs | Key outputs |
|---|---|---|---|
| `determine-semver` | Compute next `major.minor.patch` from git tags | `major`, `minor` | `version` (e.g. `1.4.7`) |
| `tag-github-origin` | Create and push a git tag via GitHub API | `tag`, `sha`, `repository`, `github-token` | — |

`determine-semver` reads all git tags matching `major.minor.*`, finds the highest patch, increments it by 1. Starts from `.0` when no matching tag exists.

### Docker

| Action | Purpose | Key inputs | Key outputs |
|---|---|---|---|
| `docker-build-push` | Build + push with BuildKit cache, multi-platform support, OCI labels | `image-name`, `version`, `username`, `password` | `image-tags`, `image-digest` |

### Helm

| Action | Purpose | Key inputs |
|---|---|---|
| `helm-deploy` | Profile-based deploy; supports `init_job_image` for pre-deploy DB migration Jobs | `app_name`, `namespace`, `kubeconfig_data` |
| `helm-deploy-s9generic` | Deploy `s9genericchart` from `https://charts.sf9.io`; handles `set-values` (`--set`) and `set-string-values` (`--set-string`) separately | `chart-name`, `chart-version`, `kubeconfig` |
| `helm-generic` | Checkout + Helm lint + package + push in a single composite | `app-name`, `version` |
| `helm-package-push` | Package chart and push to OCI registry | `chart-path`, `chart-name`, `chart-version` |

### .NET

| Action | Purpose | Key inputs |
|---|---|---|
| `dotnet-build` | `dotnet restore` → `dotnet build` → optional `dotnet test`. Detects solution files automatically. | `dotnet-version`, `projects`, `run-tests` |
| `dotnet-pack-push` | `dotnet pack` → `dotnet nuget push` | `projects`, `package-version`, `nuget-api-key` |

### Cloudflare

| Action | Purpose | Key inputs |
|---|---|---|
| `setup-cloudflare-project` | Create or verify a Cloudflare Pages project | `api-token`, `account-id`, `project-name` |
| `setup-cloudflare-domain` | Configure a custom domain; `fail-on-error: false` makes it non-blocking | `api-token`, `account-id`, `project-name`, `custom-domain` |
| `generate-wrangler-config` | Generate `wrangler.toml` dynamically | `PROJECT_NAME`, `ROUTE`, `COMPATIBILITY_DATE`, `BUILD_FOR_OPENNEXT` |

### iOS

| Action | Purpose | Key inputs |
|---|---|---|
| `ios-install-cert` | Import `.p12` into a temporary keychain | `p12Base64`, `p12Password` |
| `ios-install-profile` | Install `.mobileprovision` to `~/Library/MobileDevice/Provisioning Profiles/` | `provisioningProfileBase64` |
| `xcode-setup` | CocoaPods install + optional Xcode version selector | `xcode-version`, `ios-dir` |
| `xcode-build` | `xcodebuild archive` with manual signing | `workspace`, `scheme`, `configuration`, `archivePath`, `provisioningProfileUuid`, `developmentTeam`, `keychainPath` |
| `xcode-export` | `xcodebuild -exportArchive` → `.ipa` | `archivePath`, `exportPath`, `exportOptionsPlist` |

### Android

| Action | Purpose | Notes |
|---|---|---|
| `upload-google-play-release` | Upload AAB to Google Play via Android Publisher API | **Docker-based** (has `Dockerfile` + `play_upload.py`). `service_account_json` must come from secrets. |

---

## Core Architecture & Conventions

### Two-Layer Pattern

```
Caller repository workflow
    └── Reusable workflow  (workflows/*.yml)
            ├── Composite action  (actions/determine-semver)
            ├── Composite action  (actions/docker-build-push)
            ├── Composite action  (actions/helm-package-push)
            └── Composite action  (actions/helm-deploy-s9generic)
```

Callers only call **reusable workflows**. Composite actions are internal building blocks and are not called directly by callers (except for simple utilities like `determine-semver` or `tag-github-origin`).

### Versioning — `determine-semver`

Every pipeline that produces a deployable artifact computes its version with `determine-semver`:

1. Fetches all git tags from the calling repo.
2. Finds the highest existing `major.minor.N` tag.
3. Increments `N` → outputs `major.minor.(N+1)`.
4. After a successful deploy, `tag-github-origin` writes the tag back to the repo so the next run can increment from it.

### Branch-to-Environment Mapping

| Branch | Environment | Deploy flag to enable |
|---|---|---|
| `development` | Development | `deploy-to-development: true` |
| `staging` | Staging | `deploy-to-staging: true` |
| `main` / `master` | Production | `deploy-to-production: true` |

Deploy jobs are **disabled by default**. You must set the corresponding flag to `true`.

### Helm Values vs Helm Secret Values

This is the most important security pattern in the repo. **Never put secrets into `helm-set-values`.**

| Parameter | Passed as | Helm flag | Use for |
|---|---|---|---|
| `helm-set-values` | Workflow **input** | `--set` | Non-sensitive config: replicas, ingress, environment label |
| `helm-set-secret-values` | Workflow **secret** | `--set-string` | Sensitive data: DB connection strings, API keys |

`--set-string` bypasses shell parsing and prevents characters like `=`, `SSL:`, `//` in connection strings from being misinterpreted.

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

### Artifact Transfer Pattern

When a `build` job must pass a file to a `deploy` job:

- Upload with `actions/upload-artifact@v7`, specify a `name:`.
- Download with `actions/download-artifact@v8` using the same `name:`.
- Set `retention-days: 1` — artifacts are only needed within the same pipeline run.
- Always download by `name:`, never by `artifact-ids:`.

### Pinned Tool Versions

| Tool | Pinned version |
|---|---|
| Helm CLI | `v3.21.0` |
| kubectl CLI | `v1.33.0` |
| `actions/checkout` | `@v6` |
| `actions/setup-node` | `@v6` |
| `actions/setup-dotnet` | `@v5` |
| `actions/setup-java` | `@v4` |
| `actions/upload-artifact` | `@v7` |
| `actions/download-artifact` | `@v8` |
| `azure/setup-helm` | `@v5` |
| `azure/setup-kubectl` | `@v5` |
| `docker/setup-buildx-action` | `@v4` |
| `docker/login-action` | `@v4` |
| `docker/metadata-action` | `@v6` |
| `docker/build-push-action` | `@v7` |
| `cloudflare/wrangler-action` | `@v4` |
| `cloudflare/pages-action` | `@v1` (repo archived; v1 is final) |
| `gradle/actions/setup-gradle` | `@v4` |

Do not upgrade `gradle/actions/setup-gradle` to v5 (requires runner ≥ 2.327.1) or v6 (proprietary commercial caching component).
- Do not add `cache: gradle` to `actions/setup-java` — this secretly invokes `gradle/gradle-build-action` and conflicts with `setup-gradle`, causing the `setup-gradle` cache restore to be skipped.

---

## Troubleshooting

### Deploy jobs show as "skipped"

- Set `deploy-to-development: true` (or staging/production) on the calling workflow.
- Push to the correct branch: `development` for dev, `staging` for staging, `main`/`master` for production.
- Confirm the `kubeconfig` secret is set and base64-encoded correctly.

### Wrong image in Kubernetes pods

Set `helm-image-repo` explicitly — the default derives from `container-registry/image-name` which may differ from what your chart expects:

```yaml
with:
  helm-image-repo: registry.digitalocean.com/my-namespace/my-api
```

### Build directory not found (Vite / Next.js)

Set the correct output directory:
- Vite projects: `build-directory: dist`
- Create React App: `build-directory: build`
- Next.js static export: `build-directory: out`

### Domain setup fails (Cloudflare)

Set `fail-on-domain-error: false` to treat domain setup as non-blocking:

```yaml
with:
  fail-on-domain-error: false
```

### Helm parse error: "SSL: command not found" or malformed `--set` value

A secret value contains special characters being parsed by the shell. Move it from `helm-set-values` to `helm-set-secret-values` (passed as a workflow secret, applied with `--set-string`).

### iOS: "No matching provisioning profile"

Confirm the provisioning profile UUID matches the bundle ID and team ID. Certificates must be imported before calling `xcode-build` — use `ios-install-cert` first.

### Android versionCode conflicts on Play Console

Increase `version-code-offset`. The default `80000` prevents collisions when migrating from another CI system with a lower run number sequence. Set it above your old system's last published versionCode.

### kubeconfig not working

Ensure the kubeconfig is **base64-encoded** before storing it as a secret:

```sh
# Linux
base64 -w 0 ~/.kube/config

# macOS
base64 -b 0 ~/.kube/config
```

---

## Contributing

1. Fork this repository and create a feature branch.
2. Test your changes by calling the workflow/action from a separate repository before merging.
3. Follow all conventions in [AGENTS.md](./AGENTS.md) — pinned action versions, composite action shell requirements, secrets vs inputs.
4. Open a pull request with a description of what changed and which callers are affected.

**Key rules:**
- Every `run:` step in a composite action must have `shell: bash`.
- All new inputs must have `description:` and a sensible `default:` or `required: true`.
- Do not add `on: push:` or `on: pull_request:` triggers to files in `workflows/`.
- All deploy jobs default to `false`.
- Secrets go under `on.workflow_call.secrets:`, never as inputs.

See [AGENTS.md](./AGENTS.md) for the full contribution guide.

---

## License

MIT — see [LICENSE](LICENSE) for details.
