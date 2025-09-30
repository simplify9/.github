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
      helm-set-values: 'ingress.enabled=true,replicas=2'
    secrets:
      database-connection-string: ${{ secrets.DBCS }}
      kubeconfig: ${{ secrets.KUBECONFIG }}
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
| `helm-set-values` | false | — | string | Additional Helm set values (comma-separated: key1=value1,key2=value2) |
| `helm-secret-mappings` | false | — | string | Map GitHub secrets to Helm values (format: helm.key:SECRET_NAME,another.key:ANOTHER_SECRET) |

### Secrets

| Secret | Required | Description |
|--------|----------|-------------|
| `nuget-api-key` | false | NuGet API key for package publishing |
| `nuget-source` | false | NuGet source URL (defaults to nuget.org) |
| `registry-username` | false | Container registry username (defaults to github.actor) |
| `registry-password` | false | Container registry password/token (defaults to GITHUB_TOKEN) |
| `kubeconfig` | false | Base64 encoded kubeconfig for Kubernetes deployment |
| `github-token` | false | GitHub token for tagging (defaults to GITHUB_TOKEN) |
| `helm-set-secret-values` | false | Additional Helm set secret values (comma-separated) |
| `DBCS_ESCAPED` | false | Database connection string (for helm-secret-mappings) |
| `*` | false | **Custom secrets** - Add any secret to the workflow's secrets section, then use `helm-secret-mappings` to map to Helm values |

### Secret-to-Helm Mapping Solution

For mapping GitHub secrets to Helm values, declare your secrets explicitly and use `helm-secret-mappings`.

#### How It Works

1. **Declare your secrets explicitly** in the `secrets:` section  
2. **Use `helm-secret-mappings`** to map any declared secret to any Helm value
3. **Enhanced debugging** shows exactly what's happening with secret processing

#### Usage Pattern

```yaml
jobs:
  cicd:
    uses: simplify9/.github/.github/workflows/sw-cicd.yml@main
    with:
      # ... your configuration ...
      helm-secret-mappings: 'database.connectionString:DBCS_ESCAPED,app.apiKey:MY_API_SECRET'
    secrets:
      # Standard workflow secrets
      nuget-api-key: ${{ secrets.SWNUGETKEY }}
      registry-username: ${{ github.actor }}
      registry-password: ${{ secrets.GITHUB_TOKEN }}
      kubeconfig: ${{ secrets.S9Dev_KUBECONFIG }}
      github-token: ${{ secrets.S9_GITHUB_TOKEN }}
      
      # Custom secrets for helm-secret-mappings
      DBCS_ESCAPED: ${{ secrets.DBCS_ESCAPED }}
      MY_API_SECRET: ${{ secrets.MY_API_SECRET }}
      # Add any other secrets you want to map to Helm values
```

#### Pre-declared Secrets

The workflow already declares these common secret names - just pass your values:

- `DBCS_ESCAPED` - For database connection strings
- `nuget-api-key` - NuGet API key  
- `kubeconfig` - Kubernetes configuration
- `github-token` - GitHub token for tagging
- `registry-username` / `registry-password` - Container registry credentials

#### Adding Custom Secrets

To map additional secrets to Helm values:
1. **Add them to the workflow's secrets section** (edit the workflow file)
2. **Pass them in your calling workflow** 
3. **Reference them in `helm-secret-mappings`**

#### Examples

**Basic Application with Database:**
```yaml
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/sw-cicd.yml@main
    with:
      enable-ci: true
      enable-deployment: true
      helm-secret-mappings: 'database.connectionString:DBCS_ESCAPED'
    secrets:
      nuget-api-key: ${{ secrets.SWNUGETKEY }}
      kubeconfig: ${{ secrets.S9Dev_KUBECONFIG }}
      DBCS_ESCAPED: ${{ secrets.DBCS_ESCAPED }}
```

**Complex Application with Multiple Secrets:**
```yaml
# Add custom secrets to the workflow first, then use them:
helm-secret-mappings: 'db:DATABASE_URL,api:API_KEY,redis:REDIS_URL'
```

**Complex nested Helm paths:**
```yaml
helm-secret-mappings: 'app.database.primary:PRIMARY_DB_ABC,integrations.payment.stripe:STRIPE_KEY_456,email.smtp.password:EMAIL_PASS_789'
```

#### Secret Mapping Format

- **Format**: `helm.key:SECRET_NAME,another.key:ANOTHER_SECRET`
- **Flexible secret names**: Use any secret name you want - `MY_SECRET_123`, `CUSTOM_API_KEY`, `RANDOM_NAME_XYZ`
- **Flexible Helm paths**: Use any dot notation - `app.db`, `integrations.stripe.key`, `services.redis.url`
- **Secure handling**: Secret values are not logged or exposed in workflow output
- **No escaping needed**: The workflow handles special characters automatically
- **Optional**: Works perfectly for applications without secrets

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
    with:
      chart-name: surl-api
      major-version: '2'
      minor-version: '1'
      helm-set-values: 'ingress.enabled=true,replicas=1,ingress.hosts={surl.sf9.io},environment="Staging",ingress.path="/api",ingress.tls[0].secretName="surl-tls"'
      helm-secret-mappings: 'db:PROD_DATABASE,apiKey:THIRD_PARTY_API'
      deploy-to-development: true
      development-namespace: staging
    secrets:
      PROD_DATABASE: ${{ secrets.PROD_DATABASE }}
      THIRD_PARTY_API: ${{ secrets.THIRD_PARTY_API }}
      kubeconfig: ${{ secrets.KUBECONFIG }}
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
      helm-set-values: 'replicas=3,environment="production",ingress.enabled=true'
      helm-secret-mappings: 'database.primary:PRIMARY_DATABASE_CONNECTION,database.readonly:READONLY_DATABASE_CONNECTION,cache.redis:REDIS_CONNECTION_STRING,storage.s3AccessKey:AWS_S3_ACCESS_KEY,email.smtpPassword:EMAIL_PASSWORD,auth.jwtSecret:JWT_SIGNING_KEY'
    secrets:
      PRIMARY_DATABASE_CONNECTION: ${{ secrets.PRIMARY_DATABASE_CONNECTION }}
      READONLY_DATABASE_CONNECTION: ${{ secrets.READONLY_DATABASE_CONNECTION }}
      REDIS_CONNECTION_STRING: ${{ secrets.REDIS_CONNECTION_STRING }}
      AWS_S3_ACCESS_KEY: ${{ secrets.AWS_S3_ACCESS_KEY }}
      EMAIL_PASSWORD: ${{ secrets.EMAIL_PASSWORD }}
      JWT_SIGNING_KEY: ${{ secrets.JWT_SIGNING_KEY }}
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

Set up these secrets in your repository based on your application needs:

#### Essential Secrets
1. **KUBECONFIG**: Base64 encoded kubeconfig for your Kubernetes cluster

#### Custom Application Secrets
To use secrets in Helm deployments:
1. **Add the secret to the workflow's secrets section** (edit the workflow file)
2. **Pass the secret in your calling workflow**
3. **Reference it in `helm-secret-mappings`**

**Examples:**
   - `DBCS_ESCAPED` → maps to `database.connectionString`
   - `API_KEY` → maps to `app.apiKey`  
   - `JWT_SECRET` → maps to `auth.jwt.secret`

#### Pre-declared Secrets
These are already declared in the workflow and ready to use:
- `DBCS_ESCAPED` - Database connection string
- `nuget-api-key` - NuGet API key
- `kubeconfig` - Kubernetes configuration
- `github-token` - GitHub token for operations
- `registry-username` / `registry-password` - Container registry credentials
4. **Infrastructure secrets** (if needed):
   - `REDIS_CONNECTION_STRING`: Redis cache connection
   - `SMTP_PASSWORD`: Email service password
   - `S3_ACCESS_KEY`: Cloud storage access key
5. **NUGET_API_KEY** (if publishing NuGet packages): API key for NuGet.org or private feed

#### Secret Naming Convention
- Use descriptive, uppercase names with underscores
- Examples: `DATABASE_CONNECTION_STRING`, `EXTERNAL_API_KEY`, `JWT_SIGNING_SECRET`
- Map them to Helm values using `helm-secret-mappings`: `'db:DATABASE_CONNECTION_STRING,api.key:EXTERNAL_API_KEY'`

### Helm Chart Requirements

Your Helm chart should support these standard values:
- `image.repository`, `image.tag`: Container image settings (automatically set)
- `ingress.enabled`, `ingress.hosts`, `ingress.tls`: Ingress configuration
- `replicas`: Pod replica count
- `environment`: Environment label

#### Custom Secret Values
Any secrets mapped via `helm-secret-mappings` will be passed as Helm values. For example:
- `helm-secret-mappings: 'db:DATABASE_SECRET'` → Creates Helm value `db`
- `helm-secret-mappings: 'api.key:API_SECRET'` → Creates Helm value `api.key`
- `helm-secret-mappings: 'database.primary:DB1,database.readonly:DB2'` → Creates `database.primary` and `database.readonly`

#### Example values.yaml structure:
```yaml
# Application secrets (from helm-secret-mappings)
db: ""  # Database connection string
api:
  key: ""  # External API key
auth:
  jwtSecret: ""  # JWT signing secret

# Standard application values
replicas: 1
environment: "development"
image:
  repository: ""
  tag: ""
ingress:
  enabled: false
  hosts: []
  tls: []
```

#### Kubernetes Secret Creation
Your Helm chart should create Kubernetes secrets from these values:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Values.fullname }}-secrets
data:
  {{- if .Values.db }}
  ConnectionStrings__DefaultConnection: {{ .Values.db | b64enc }}
  {{- end }}
  {{- if .Values.api.key }}
  ExternalApiKey: {{ .Values.api.key | b64enc }}
  {{- end }}
```

### Quick Reference

#### Template Usage Pattern
```yaml
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/sw-cicd.yml@main
    with:
      chart-name: "your-app-name"
      helm-set-values: 'key1=value1,key2=value2'
      helm-secret-mappings: 'helm.key:SECRET_NAME,another.key:ANOTHER_SECRET'
    secrets:
      SECRET_NAME: ${{ secrets.YOUR_SECRET }}
      ANOTHER_SECRET: ${{ secrets.ANOTHER_SECRET }}
      kubeconfig: ${{ secrets.KUBECONFIG }}
```

#### Common Secret Mappings
```yaml
# Database applications
helm-secret-mappings: 'db:DATABASE_CONNECTION_STRING'

# API with authentication
helm-secret-mappings: 'db:DATABASE_CS,api.key:EXTERNAL_API,jwt.secret:JWT_SECRET'

# Microservice with multiple dependencies
helm-secret-mappings: 'database.primary:MAIN_DB,cache.redis:REDIS_URL,storage.s3:S3_ACCESS,email.smtp:SMTP_PASS'
```

#### Helm Output Examples
```bash
# From: helm-secret-mappings: 'db:DATABASE_CS,api.key:API_SECRET'
helm upgrade --install app chart \
  --set db="Server=localhost;Database=mydb;..." \
  --set api.key="abc123secret"
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
