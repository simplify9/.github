# Reusable build-deploy workflow

This repository contains a reusable GitHub Actions workflow that builds and pushes a Docker image (CI only).

## How to use (from another repo)

Create a workflow in your application repository (e.g. `.github/workflows/build-deploy.yml`) that calls this reusable workflow:

```yaml
name: build-deploy

on:
  push:
    branches: ["staging"]
  workflow_dispatch:

jobs:
  build-deploy:
    uses: simplify9/.github/.github/workflows/build-deploy-reusable.yml@main
    with:
      app_name: bitween-v2
      version: staging
      docker_registry: registry.digitalocean.com/sf9cr
      # build_context: .
      # dockerfile: Dockerfile
    secrets:
      registry_username: ${{ secrets.REGISTRY_USERNAME }}
      registry_token: ${{ secrets.REGISTRY_TOKEN }}
```

## Inputs

- app_name (required): App name used for image and Helm release
- version (default: staging): Used in image tag `github-<version>`
- docker_registry (default: registry.digitalocean.com/sf9cr)
- build_context (default: .)
- dockerfile (default: Dockerfile)
  (Only build-related inputs are available; CD has been removed.)

## Secrets

- registry_username (required): Registry username
- registry_token (required): Registry token/password
  (Only registry credentials are required.)

## Org-level starter template

Consumers can also start from a workflow template via the GitHub UI. See files under `.github/workflow-templates/` in this repo.
