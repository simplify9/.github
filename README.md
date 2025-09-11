# Reusable CI Workflows

This repository hosts reusable GitHub Actions workflows for Simplify9 projects.

## Workflows Overview

1. build-deploy (ci-docker.yaml)
   Builds and pushes a Docker image using dynamic profile-based registry credentials.
2. helm-deploy (ci-helm.yaml)
   Deploys (upgrade --install) a Helm chart with dynamic profile-based kubeconfig secret resolution.

---

## 1. build-deploy (ci-docker.yaml)

Reusable workflow name: `build-deploy (reusable)`

### Invocation

Use `workflow_call` from another repository.

### Inputs (Helm)

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `registry_profile` | false | `S9` | Profile code prefixing secrets/vars (e.g. `S9`, `WISEWELL`). Case-insensitive. |
| `app_name` | true | — | Image (and optionally Helm release) base name. |
| `version` | false | `staging` | Logical version label added to `github-<version>` tag. |
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

- `<registry>/<app_name>:github-<version>`
- `<registry>/<app_name>:github-<run_number>`

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

## 2. helm-deploy (ci-helm.yaml)

Reusable workflow name: `helm-deploy (reusable)`

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `registry_profile` | false | `S9` | Profile code to locate kubeconfig secret `<PROFILE>_KUBECONFIG`. Case-insensitive. |
| `app_name` | true | — | Helm release name. |
| `version` | false | `staging` | Logical version (used only for concurrency grouping and optional tagging logic). |
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

### Required Secret

- `<UPPER_PROFILE>_KUBECONFIG` (raw kubeconfig OR base64-encoded). The workflow auto-detects format.

### Base `--set` Payload (always included)

- `service.targetPort`
- `app.name`
- `app.version` = `github-<run_number>`
- `environment`
- `ingress.hosts[0].host`
- `ingress.hosts[0].tlsSecret`
- `image.repo`
- `image.pullSecret`
- `ingress.annotations.cert-manager.io/cluster-issuer`
- `ingress.annotations.nginx.ingress.kubernetes.io/proxy-body-size`

### Adding Extra Values

Supply newline-separated lines via `extra_set_values`, e.g.:

```text
ingress.hosts[1].host=alt.example.com
ingress.hosts[1].tlsSecret=alt-example-com-tls
```

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
