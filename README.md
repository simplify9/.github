# Reusable CI Workflows

This repository hosts reusable GitHub Actions workflows for Simplify9 projects.

## Workflows Overview

1. **sw-cicd.yml** - Complete CI/CD pipeline for .NET applications with Docker, Helm, and Kubernetes deployment
2. **ci-docker.yaml** - Build and push Docker images using dynamic profile-based registry credentials
3. **ci-helm.yaml** - Deploy Helm charts with dynamic profile-based kubeconfig secret resolution

---

## 1. sw-cicd.yml - Complete CI/CD Pipeline

Reusable workflow name: `Reusable SW CI/CD Pipeline`

### Overview

A comprehensive CI/CD pipeline that handles the complete application lifecycle:
- Semantic versioning and Git tagging
- .NET project building and testing
- NuGet package publishing (optional)
- Docker image building and pushing
- Helm chart packaging and publishing
- Kubernetes deployment with database connection string support

### Invocation

```yaml
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/sw-cicd.yml@main
    with:
      chart-name: my-app
      helm-set-values: 'ingress.enabled=true,replicas=2,database.connectionString="${{ secrets.DATABASE_CONNECTION_STRING }}"'
    secrets:
      kubeconfig: ${{ secrets.KUBECONFIG }}
      DATABASE_CONNECTION_STRING: ${{ secrets.DATABASE_CONNECTION_STRING }}
```

### Inputs

| Input | Required | Default | Type | Description |
|-------|----------|---------|------|-------------|
| `major-version` | false | `'1'` | string | Major version number for semantic versioning |
| `minor-version` | false | `'0'` | string | Minor version number for semantic versioning |
| `dotnet-version` | false | `'8.0.x'` | string | .NET SDK version to use |
| `nuget-projects` | false | `''` | string | NuGet projects to pack and push (glob pattern). Leave empty to skip NuGet publishing |
| `test-projects` | false | `'**/*UnitTests/*.csproj'` | string | Test projects to run (glob pattern) |
| `run-tests` | false | `'false'` | string | Whether to run tests during build |
| `dockerfile-path` | false | `'./Dockerfile'` | string | Path to Dockerfile |
| `docker-context` | false | `'.'` | string | Docker build context |
| `docker-platforms` | false | `'linux/amd64'` | string | Target platforms for Docker build |
| `chart-path` | false | `'./chart'` | string | Path to Helm chart directory |
| `chart-name` | true | — | string | Helm chart name (required) |
| `deploy-to-development` | false | `true` | boolean | Deploy to development environment |
| `development-namespace` | false | `'development'` | string | Kubernetes namespace for development |
| `container-registry` | false | `'ghcr.io'` | string | Container registry (docker.io, ghcr.io, etc.) |
| `image-name` | false | — | string | Docker image name (defaults to repository name) |
| `helm-set-values` | false | — | string | Helm values as comma-separated key=value pairs. Supports secrets with format: `database.password="${{ secrets.DB_PASSWORD }}"` |

### Secrets

| Secret | Required | Description |
|--------|----------|-------------|
| `nuget-api-key` | false | NuGet API key for package publishing |
| `nuget-source` | false | NuGet source URL (defaults to nuget.org) |
| `registry-username` | false | Container registry username (defaults to github.actor) |
| `registry-password` | false | Container registry password/token (defaults to GITHUB_TOKEN) |
| `kubeconfig` | false | Base64 encoded kubeconfig for Kubernetes deployment |
| `github-token` | false | GitHub token for tagging (defaults to GITHUB_TOKEN) |
| `*` | false | **Any application secrets** - Pass secrets directly through `helm-set-values` using `"${{ secrets.YOUR_SECRET }}"` syntax |

### Secret Handling

Secrets are passed directly through the `helm-set-values` input using GitHub Actions secret interpolation:

```yaml
helm-set-values: |
  ingress.enabled=true,
  database.connectionString="${{ secrets.DATABASE_CONNECTION_STRING }}",
  redis.url="${{ secrets.REDIS_URL }}",
  api.key="${{ secrets.API_SECRET }}"
```

**Key Points:**
- Use double quotes around `${{ secrets.SECRET_NAME }}` for proper escaping
- Supports any secret name - no predefined list required  
- Handles complex values like database connection strings with special characters
- GitHub Actions resolves secrets before passing to the workflow

### Outputs

| Output | Description |
|--------|-------------|
| `version` | Generated semantic version |
| `docker-image` | Built Docker image with tag |
| `helm-chart` | Published Helm chart URL |

### Examples

#### Basic .NET Application (No Secrets)
```yaml
name: Deploy Application
on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/sw-cicd.yml@main
    with:
      chart-name: my-api
      helm-set-values: 'ingress.enabled=true,replicas=2,environment="Production"'
    secrets:
      kubeconfig: ${{ secrets.KUBECONFIG }}
```

#### .NET Application with Database and API Key
```yaml
name: Deploy API with Secrets
on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/sw-cicd.yml@main
### Usage Examples

#### Simple Application
```yaml
name: Deploy Simple App
on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/sw-cicd.yml@main
    with:
      chart-name: simple-app
      major-version: '1'
      minor-version: '0'
      helm-set-values: 'ingress.enabled=true,replicas=2,environment="production"'
      deploy-to-development: true
      development-namespace: prod
    secrets:
      kubeconfig: ${{ secrets.KUBECONFIG }}
      nuget-api-key: ${{ secrets.NUGET_API_KEY }}
      registry-username: ${{ github.actor }}
      registry-password: ${{ secrets.GITHUB_TOKEN }}
      github-token: ${{ secrets.GITHUB_TOKEN }}
```

#### Application with Secrets
```yaml
name: Deploy App with Database
on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/sw-cicd.yml@main
    with:
      chart-name: surl-api
      major-version: '2'
      minor-version: '1'
      helm-set-values: |
        ingress.enabled=true,
        replicas=1,
        ingress.hosts={surl.sf9.io},
        environment="Staging",
        ingress.path="/api",
        ingress.tls[0].secretName="surl-tls",
        database.connectionString="${{ secrets.DATABASE_CONNECTION_STRING }}",
        api.key="${{ secrets.THIRD_PARTY_API }}"
      deploy-to-development: true
      development-namespace: staging
    secrets:
      kubeconfig: ${{ secrets.KUBECONFIG }}
      DATABASE_CONNECTION_STRING: ${{ secrets.DATABASE_CONNECTION_STRING }}
      THIRD_PARTY_API: ${{ secrets.THIRD_PARTY_API }}
```

#### Complex Application with Multiple Secrets
```yaml
name: Deploy Enterprise Application
on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/sw-cicd.yml@main
    with:
      chart-name: enterprise-app
      helm-set-values: |
        replicas=3,
        environment="production",
        ingress.enabled=true,
        database.primary="${{ secrets.PRIMARY_DATABASE_CONNECTION }}",
        database.readonly="${{ secrets.READONLY_DATABASE_CONNECTION }}",
        cache.redis="${{ secrets.REDIS_CONNECTION_STRING }}",
        storage.s3AccessKey="${{ secrets.AWS_S3_ACCESS_KEY }}",
        email.smtpPassword="${{ secrets.EMAIL_PASSWORD }}",
        auth.jwtSecret="${{ secrets.JWT_SIGNING_KEY }}"
    secrets:
      kubeconfig: ${{ secrets.KUBECONFIG }}
```

#### NuGet Library Publishing
```yaml
name: Build and Publish Library
on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/sw-cicd.yml@main
    with:
      chart-name: my-library
      nuget-projects: 'src/**/*.csproj'
      run-tests: 'true'
      test-projects: 'tests/**/*Tests.csproj'
      deploy-to-development: false
    secrets:
      nuget-api-key: ${{ secrets.NUGET_API_KEY }}
```

### Repository Secrets

Set up these secrets in your repository:

#### Required Secrets
- **KUBECONFIG**: Base64 encoded kubeconfig for your Kubernetes cluster

#### Optional Secrets (as needed by your application)
- Any application secrets (database connections, API keys, etc.)
- Pass them directly in `helm-set-values` using `${{ secrets.SECRET_NAME }}`

#### NuGet Publishing (if applicable)
- **NUGET_API_KEY**: API key for NuGet.org or private feed

### Helm Chart Requirements

Your Helm chart should support these standard values:
- `image.repository`, `image.tag`: Container image settings (automatically set)
- `ingress.enabled`, `ingress.hosts`, `ingress.tls`: Ingress configuration
- `replicas`: Pod replica count
- `environment`: Environment label

#### Custom Values
Any values passed through `helm-set-values` become available in your Helm templates:

```yaml
# values.yaml
database:
  connectionString: ""  # Set via helm-set-values
api:
  key: ""              # Set via helm-set-values
replicas: 1            # Set via helm-set-values
environment: "development"
image:
  repository: ""
  tag: ""
```

#### Kubernetes Secret Creation
Your Helm chart can create Kubernetes secrets from these values:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Values.fullname }}-secrets
data:
  {{- if .Values.database.connectionString }}
  ConnectionStrings__DefaultConnection: {{ .Values.database.connectionString | b64enc }}
  {{- end }}
  {{- if .Values.api.key }}
  ExternalApiKey: {{ .Values.api.key | b64enc }}
  {{- end }}
```

### Quick Reference

#### Basic Usage Pattern
```yaml
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/sw-cicd.yml@main
    with:
      chart-name: "your-app-name"
      helm-set-values: |
        key1=value1,
        key2=value2,
        secret.value="${{ secrets.YOUR_SECRET }}"
    secrets:
      kubeconfig: ${{ secrets.KUBECONFIG }}
```

#### Common Patterns
```yaml
# Simple configuration
helm-set-values: 'replicas=3,environment="production",ingress.enabled=true'

# With secrets
helm-set-values: |
  replicas=2,
  database.connectionString="${{ secrets.DATABASE_URL }}",
  api.key="${{ secrets.API_SECRET }}"

# Complex configuration with multiple secrets
helm-set-values: |
  database.primary="${{ secrets.PRIMARY_DB }}",
  cache.redis="${{ secrets.REDIS_URL }}",
  storage.s3="${{ secrets.S3_ACCESS }}",
  email.smtp="${{ secrets.SMTP_PASS }}"
```

---

## 2. ci-docker.yaml - Build and Deploy

## 2. ci-docker.yaml - Build and Deploy

Reusable workflow name: `build-deploy (reusable)`

### Invocation

Use `workflow_call` from another repository.

### Inputs (Helm)

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `registry_profile` | false | `S9` | Profile code prefixing secrets/vars (e.g. `S9`, `WISEWELL`). Case-insensitive. |
| `app_name` | true | — | Image (and optionally Helm release) base name. |
| `version` | false | `staging` | Logical version label added to `github-<branch>-<version>` tag (branch is sanitized). |
| `docker_registry` | false | `registry.digitalocean.com/sf9cr` | Fallback registry if profile-scoped var not set. |
| `build_context` | false | `.` | Docker build context directory. |
| `dockerfile` | false | `Dockerfile` | Path to Dockerfile. |

### Dynamic Vars & Secrets Resolution

Order for registry base:

1. Repository / org variable: `<UPPER_PROFILE>_DOCKER_REGISTRY`
2. Variable: `DOCKER_REGISTRY`
3. Input: `docker_registry`

Credentials (must be defined as secrets):

- `<UPPER_PROFILE>_REGISTRY_USERNAME`
- `<UPPER_PROFILE>_REGISTRY_TOKEN`

### Produced Tags

Tags now include a sanitized lowercase branch segment to avoid collisions across branches:

- `<registry>/<app_name>:github-<branch>-<version>`
- `<registry>/<app_name>:github-<branch>-<run_number>`

Branch sanitization: convert to lowercase, replace any character not in `[a-z0-9._-]` with `-`, collapse repeats, trim leading/trailing dashes, fallback to `detached` if empty, and truncate to 40 chars.

### Minimal Example Caller (Helm)

```yaml
name: Build Image
on: [push]
jobs:
  build:
    uses: simplify9/.github/.github/workflows/ci-docker.yaml@main
    with:
      app_name: myservice
```

### Expanded Example with Overrides

```yaml
jobs:
  build:
    uses: simplify9/.github/.github/workflows/ci-docker.yaml@main
    with:
      registry_profile: WISEWELL
      app_name: api-gateway
      version: prod
      docker_registry: registry.digitalocean.com/custom
      build_context: ./src
      dockerfile: infra/Dockerfile
```

---

## 3. ci-helm.yaml - Helm Deploy

Reusable workflow name: `helm-deploy (reusable)`

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `registry_profile` | false | `S9` | Profile code to locate kubeconfig secret `<PROFILE>_KUBECONFIG`. Case-insensitive. |
| `app_name` | true | — | Helm release name. |
| `version` | false | `staging` | Logical version (used for concurrency grouping; image tags & app.version embed branch: `github-<branch>-<run_number>`). |
| `namespace` | true | — | Target Kubernetes namespace. |
| `chart` | false | `s9genericchart` | Chart name (repo or local path). |
| `chart_repo` | false | `https://charts.sf9.io` | Helm repo URL (added as alias `s9generic`). |
| `environment_label` | false | `Staging` | Value passed as `--set environment=...`. |
| `service_target_port` | false | `5000` | Service target port. |
| `ingress_host` | true | — | Primary ingress host. |
| `ingress_tls_secret` | true | — | TLS secret for host. |
| `ingress_cert_issuer` | false | `letsencrypt-nginx` | cert-manager cluster issuer annotation. |
| `ingress_proxy_body_size` | false | `50m` | NGINX annotation proxy body size. |
| `image_repo` | false | `registry.digitalocean.com/sf9cr` | Image repo (no tag) passed to chart. |
| `pull_secret` | false | `sf9cr` | Image pull secret name. |
| `helm_timeout` | false | `15m` | Helm upgrade timeout. |
| `extra_set_values` | false | '' | Newline-separated additional `--set key=value` pairs. |
| `extra_args` | false | '' | Raw extra args appended to `helm upgrade`. |
| `ingress_paths` | false | `- /` | YAML list of ingress path entries (converted to `ingress.paths[n]` values). Default only root `/`. |

### Required Secret

- `<UPPER_PROFILE>_KUBECONFIG` (raw kubeconfig OR base64-encoded). The workflow auto-detects format.

### Base `--set` Payload (always included)

- `service.targetPort`
- `app.name`
- `app.version` = `github-<branch>-<run_number>`
- `environment`
- `ingress.hosts[0].host`
- `ingress.hosts[0].tlsSecret`
- `image.repo`
- `image.pullSecret`
- `ingress.annotations.cert-manager.io/cluster-issuer`
- `ingress.annotations.nginx.ingress.kubernetes.io/proxy-body-size`
  
Additionally, each provided ingress path (from `ingress_paths`) is translated into:

- `ingress.paths[<index>] = <path>`

If you don't pass `ingress_paths`, only `ingress.paths[0]=/` is set (root path).

### Adding Extra Values

Supply newline-separated lines via `extra_set_values`, e.g.:

```text
ingress.hosts[1].host=alt.example.com
ingress.hosts[1].tlsSecret=alt-example-com-tls
```

### Configuring Ingress Paths

Provide a simple YAML list (each line starting with a dash) via `ingress_paths`. Example:

```yaml
ingress_paths: |
  - /
  - /api
  - /docs
  - /downloadapp
  - /.well-known
```

This becomes Helm flags:

```text
--set ingress.paths[0]=/
--set ingress.paths[1]=/api
--set ingress.paths[2]=/docs
--set ingress.paths[3]=/downloadapp
--set ingress.paths[4]=/.well-known
```

Blank lines and comments beginning with `#` in the list are ignored. Quotes around paths are optional.

### Minimal Example Caller

```yaml
name: Deploy Helm
on: [workflow_dispatch]
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/ci-helm.yaml@main
    with:
      app_name: myservice
      namespace: my-namespace
      ingress_host: my.example.com
      ingress_tls_secret: my-tls-secret
```

### Expanded Example with Extras

```yaml
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/ci-helm.yaml@main
    with:
      registry_profile: WISEWELL
      app_name: myservice
      version: prod
      namespace: prod-space
      chart: s9genericchart
      chart_repo: https://charts.sf9.io
      environment_label: Production
      service_target_port: '8080'
      ingress_host: api.prod.example.com
      ingress_tls_secret: api-prod-tls
      ingress_cert_issuer: letsencrypt-nginx
      ingress_proxy_body_size: 100m
      image_repo: registry.digitalocean.com/company
      pull_secret: regcred
      helm_timeout: 20m
      extra_set_values: |
        ingress.hosts[1].host=alt.example.com
        ingress.hosts[1].tlsSecret=alt-example-com-tls
      ingress_paths: |
        - /
        - /api
        - /docs
        - /downloadapp
        - /.well-known
      extra_args: --atomic --debug
```

---

## Combined Minimal Build + Deploy Pipeline

Example pipeline in an application repo that first builds the image then deploys it via Helm (two jobs, same run_number for tagging):

```yaml
name: Build & Deploy
on:
  push:
    branches: [ main ]

jobs:
  build:
    uses: simplify9/.github/.github/workflows/ci-docker.yaml@main
    with:
      app_name: myservice

  deploy:
    needs: build
    uses: simplify9/.github/.github/workflows/ci-helm.yaml@main
    with:
      app_name: myservice
      namespace: my-namespace
      ingress_host: my.example.com
      ingress_tls_secret: my-tls-secret
```

---

## Tips

- Always define required secrets/vars at the org level to reuse across repos.
- To change the registry per profile, add a repository/org variable named `<PROFILE>_DOCKER_REGISTRY`.
- For new clusters, add secret `<PROFILE>_KUBECONFIG` with either raw kubeconfig or base64 representation.
- Use `extra_set_values` instead of large `extra_args` for structured chart overrides (better auditing).

\n## License
Internal use.
