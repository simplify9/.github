# API CI/CD Template Usage Example

This file shows how to use the `api-cicd.yml` reusable workflow template for your API projects.

## Basic Usage

```yaml
name: Build and Deploy API

on:
  push:
    branches: [main, develop, feature/*, release/*]
  pull_request:
    branches: [main]

jobs:
  api-pipeline:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      # Required inputs
      chart-name: "my-api"
      
      # Optional version configuration
      major-version: "1"
      minor-version: "0"
      
      # Optional Docker configuration
      dockerfile-path: "./Dockerfile"
      docker-context: "."
      
      # Optional Helm chart configuration
      chart-path: "./chart"
      
      # Development deployment (enabled by default)
      deploy-to-development: true
      development-namespace: "development"
      development-helm-set-values: "app.environment=Development,logging.level=Debug"
      
      # Staging deployment (disabled by default)
      deploy-to-staging: true
      staging-namespace: "staging"
      staging-helm-set-values: "app.environment=Staging,logging.level=Information"
      
      # Production deployment (disabled by default)
      deploy-to-production: true
      production-namespace: "production"
      production-helm-set-values: "app.environment=Production,logging.level=Information,replicas=3"
      
    secrets:
      registry-username: ${{ secrets.REGISTRY_USERNAME }}
      registry-password: ${{ secrets.REGISTRY_PASSWORD }}
      kubeconfig: ${{ secrets.KUBECONFIG }}
      development-helm-set-secret-values: ${{ secrets.DEV_HELM_SECRETS }}
      staging-helm-set-secret-values: ${{ secrets.STAGING_HELM_SECRETS }}
      production-helm-set-secret-values: ${{ secrets.PROD_HELM_SECRETS }}
```

## Advanced Configuration

```yaml
jobs:
  api-pipeline:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      # Chart configuration
      chart-name: "advanced-api"
      chart-path: "./helm/chart"
      
      # Version configuration
      major-version: "2"
      minor-version: "1"
      
      # Docker configuration
      dockerfile-path: "./src/AdvancedApi/Dockerfile"
      docker-context: "./src"
      docker-platforms: "linux/amd64,linux/arm64"
      
      # Registry configuration
      container-registry: "registry.digitalocean.com"
      image-name: "mycompany/advanced-api"
      
      # Development deployment
      deploy-to-development: true
      development-namespace: "dev-apis"
      development-helm-set-values: |
        app.environment=Development
        service.port=8080
        ingress.host=advanced-api-dev.example.com
        resources.requests.memory=256Mi
        resources.limits.memory=512Mi
      development-branch-pattern: "^(main|develop|feature/.+)$"
        
      # Staging deployment
      deploy-to-staging: true
      staging-namespace: "staging-apis"
      staging-helm-set-values: |
        app.environment=Staging
        service.port=8080
        ingress.host=advanced-api-staging.example.com
        replicas=2
        resources.requests.memory=512Mi
        resources.limits.memory=1Gi
      staging-branch-pattern: "^(main|release/.+|staging/.+)$"
        
      # Production deployment
      deploy-to-production: true
      production-namespace: "prod-apis"
      production-helm-set-values: |
        app.environment=Production
        service.port=8080
        ingress.host=api.example.com
        replicas=5
        resources.requests.memory=512Mi
        resources.limits.memory=1Gi
        autoscaling.enabled=true
        autoscaling.minReplicas=3
        autoscaling.maxReplicas=10
      production-branch-pattern: "^(main|release/.+)$"
        
    secrets:
      registry-username: ${{ secrets.DO_REGISTRY_USERNAME }}
      registry-password: ${{ secrets.DO_REGISTRY_TOKEN }}
      kubeconfig: ${{ secrets.KUBECONFIG }}
      github-token: ${{ secrets.GITHUB_TOKEN }}
      development-helm-set-secret-values: ${{ secrets.DEV_API_SECRETS }}
      staging-helm-set-secret-values: ${{ secrets.STAGING_API_SECRETS }}
      production-helm-set-secret-values: ${{ secrets.PROD_API_SECRETS }}
```

## Required Repository Secrets

Set these secrets in your repository settings:

### Registry and Kubernetes Access
- `REGISTRY_USERNAME`: Container registry username
- `REGISTRY_PASSWORD`: Container registry password/token
- `KUBECONFIG`: Base64 encoded kubeconfig for cluster access

### Environment-Specific Secrets
- `DEV_HELM_SECRETS` or `DEV_API_SECRETS`: Development secret values
  ```
  database.connectionString=Server=dev-db;Database=MyApi;...
  apiKeys.external=dev-api-key-here
  ```

- `STAGING_HELM_SECRETS` or `STAGING_API_SECRETS`: Staging secret values
  ```
  database.connectionString=Server=staging-db;Database=MyApi;...
  apiKeys.external=staging-api-key-here
  ```

- `PROD_HELM_SECRETS` or `PROD_API_SECRETS`: Production secret values
  ```
  database.connectionString=Server=prod-db;Database=MyApi;...
  apiKeys.external=prod-api-key-here
  ```

### Optional
- `GITHUB_TOKEN`: For GitHub release tagging (defaults to automatic token)

## Branch-Based Deployment

The template automatically deploys based on branch patterns:

### Development Deployment
Default triggers on pushes to:
- `main`, `master`, `develop`, `development` 
- `feature/*`, `bugfix/*`, `hotfix/*`

### Staging Deployment  
Default triggers on pushes to:
- `main`, `master`
- `release/*`, `staging/*` branches

### Production Deployment  
Default triggers on pushes to:
- `main`, `master`
- `release/*` branches
- Version tags starting with `v`

**Deployment Dependencies:**
- Staging deployment depends on successful development deployment (if development is enabled)
- Production deployment depends on successful staging deployment (if staging is enabled)
- If staging is disabled, production deployment depends on development deployment

## Workflow Jobs

1. **Version Job**: 
   - Uses `determine-semver` action to generate semantic version
   - Tags GitHub releases using `tag-github-origin` action

2. **Build Job**: 
   - Uses `docker-build-push` action to build and push container image
   - Uses `helm-package-push` action to package and push Helm chart

3. **Deploy Development Job**: 
   - Uses `helm-deploy` action to deploy to development environment
   - Triggered based on development branch pattern
   - **Optional** - controlled by `deploy-to-development` input

4. **Deploy Staging Job**: 
   - Uses `helm-deploy` action to deploy to staging environment
   - Triggered based on staging branch pattern
   - Depends on successful development deployment (if enabled)
   - **Optional** - controlled by `deploy-to-staging` input

5. **Deploy Production Job**: 
   - Uses `helm-deploy` action to deploy to production environment
   - Triggered based on production branch pattern
   - Depends on successful staging deployment (if enabled)
   - **Optional** - controlled by `deploy-to-production` input

## Composite Actions Used

- `simplify9/.github/.github/actions/determine-semver@main`: Semantic version calculation
- `simplify9/.github/.github/actions/docker-build-push@main`: Docker build and push
- `simplify9/.github/.github/actions/helm-package-push@main`: Helm chart packaging and push
- `simplify9/.github/.github/actions/tag-github-origin@main`: Git release tagging  
- `simplify9/.github/.github/actions/helm-deploy@main`: Kubernetes deployment

## Key Differences from sw-cicd.yml

- **API-focused**: Optimized for API deployments without .NET specific steps
- **Three-Environment Pipeline**: Built-in support for development, staging, and production deployments
- **All Deployments Optional**: Each deployment stage can be enabled/disabled independently
- **Branch-based**: Configurable branch patterns for deployment conditions
- **Dependency Chain**: Smart deployment dependencies (dev → staging → production)
- **Simplified**: Removed NuGet packaging and testing steps