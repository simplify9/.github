# API CI/CD Template Usage Guide

This guide shows how to use the `api-cicd.yml` reusable workflow template for your API projects. 

**Important**: All deployment stages are **disabled by default** to keep your GitHub Actions UI clean. You must explicitly enable the deployments you need.

## Input Parameters Reference

### Chart Configuration

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `chart-path` | false | `'./chart'` | **Local chart**: Path to chart directory (e.g., `"./chart"`, `"./helm/mychart"`)<br>**External chart**: Helm repository URL (e.g., `"https://charts.sf9.io"`, `"https://my-company.github.io/helm-charts"`) |
| `chart-name` | **true** | — | **Your application name**: This becomes your app name in Kubernetes and the final chart name |
| `chart-version` | false | `'latest'` | **Local chart**: Ignored (uses generated semantic version)<br>**External chart**: Version to pull (e.g., `"1.2.3"`, `"latest"`) |
| `source-chart-name` | false | `'s9genericchart'` | **External charts only**: Name of the chart to pull from the repository. Ignored for local charts. |

### Chart Configuration Examples

#### ✅ **Local Chart Examples**
```yaml
# Basic local chart
chart-name: "my-api"           # Your app name
chart-path: "./chart"          # Local chart directory
# source-chart-name is ignored

# Local chart in subdirectory  
chart-name: "payment-service"  # Your app name
chart-path: "./helm/payment"   # Local chart directory
# source-chart-name is ignored
```

#### ✅ **External Chart Examples**
```yaml
# SF9 public charts - pull s9genericchart, rename to your app
chart-name: "my-api"                    # Your app name in cluster
chart-path: "https://charts.sf9.io"    # Repository URL
source-chart-name: "s9genericchart"    # Chart to pull from repo
chart-version: "1.2.3"                 # Version to pull

# Company charts - pull web-template, rename to your app
chart-name: "backend-service"           # Your app name in cluster  
chart-path: "https://my-company.github.io/helm-charts"
source-chart-name: "web-template"      # Chart to pull from repo
chart-version: "2.1.0"                 # Version to pull

# Harbor charts - pull generic-api, rename to your app
chart-name: "payment-api"               # Your app name in cluster
chart-path: "https://harbor.example.com/chartrepo/public"
source-chart-name: "generic-api"       # Chart to pull from repo  
chart-version: "latest"                # Version to pull
```

### Version Configuration

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `major-version` | false | `'1'` | Major version number for semantic versioning |
| `minor-version` | false | `'0'` | Minor version number for semantic versioning |

### Docker Configuration

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `dockerfile-path` | false | `'./Dockerfile'` | Path to Dockerfile |
| `docker-context` | false | `'.'` | Docker build context |
| `docker-platforms` | false | `'linux/amd64'` | Target platforms for Docker build |
| `container-registry` | false | `'ghcr.io'` | Container registry URL |
| `image-name` | false | `github.repository` | Docker image name |

### Deployment Configuration

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `deploy-to-development` | false | `false` | Enable development deployment |
| `deploy-to-staging` | false | `false` | Enable staging deployment |
| `deploy-to-production` | false | `false` | Enable production deployment |
| `development-namespace` | false | `'development'` | Kubernetes namespace for development |
| `staging-namespace` | false | `'staging'` | Kubernetes namespace for staging |
| `production-namespace` | false | `'production'` | Kubernetes namespace for production |
| `development-helm-set-values` | false | — | Development Helm values (comma-separated) |
| `staging-helm-set-values` | false | — | Staging Helm values (comma-separated) |
| `production-helm-set-values` | false | — | Production Helm values (comma-separated) |

## Basic Usage - Development Only

```yaml
name: Build and Deploy API

on:
  push:
    branches: [main, develop, feature/*]
  pull_request:
    branches: [main]

jobs:
  api-pipeline:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      # Required inputs
      chart-name: "my-api"  # This will be your app name in Kubernetes!
      
      # Optional version configuration
      major-version: "1"
      minor-version: "0"
      
      # Optional Docker configuration
      dockerfile-path: "./Dockerfile"
      docker-context: "."
      
      # Helm chart configuration (local chart)
      chart-path: "./chart"
      
      # Enable only development deployment
      deploy-to-development: true
      
      # Development deployment configuration
      development-namespace: "development"
      development-helm-set-values: "app.environment=Development,logging.level=Debug"
      
    secrets:
      registry-username: ${{ secrets.REGISTRY_USERNAME }}
      registry-password: ${{ secrets.REGISTRY_PASSWORD }}
      kubeconfig: ${{ secrets.KUBECONFIG }}
      development-helm-set-secret-values: ${{ secrets.DEV_HELM_SECRETS }}
```

## Using External Charts

**Smart Repackaging**: The template automatically pulls external charts, repackages them with your application name, and deploys them as local charts. This works with **any** Helm repository URL.

### SF9 Public Charts
```yaml
jobs:
  api-pipeline:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      # Chart configuration - SF9 public charts
      chart-name: "my-api"                     # Your app name in cluster
      chart-path: "https://charts.sf9.io"     # Repository URL  
      source-chart-name: "s9genericchart"     # Chart to pull from repo
      chart-version: "1.2.3"                  # Version to pull
      
      # Enable deployments
      deploy-to-development: true
      deploy-to-staging: true
      
      # Environment configurations
      development-namespace: "development"
      development-helm-set-values: "service.port=8080,replicas=1"
      
      staging-namespace: "staging"
      staging-helm-set-values: "service.port=8080,replicas=2"
      
    secrets:
      registry-username: ${{ secrets.REGISTRY_USERNAME }}
      registry-password: ${{ secrets.REGISTRY_PASSWORD }}
      kubeconfig: ${{ secrets.KUBECONFIG }}
      development-helm-set-secret-values: ${{ secrets.DEV_HELM_SECRETS }}
      staging-helm-set-secret-values: ${{ secrets.STAGING_HELM_SECRETS }}
```

### Company/Private Chart Repository
```yaml
jobs:
  api-pipeline:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      # Chart configuration - company repository
      chart-name: "backend-service"            # Your app name in cluster
      chart-path: "https://my-company.github.io/helm-charts"
      source-chart-name: "web-template"       # Chart to pull from repo
      chart-version: "2.1.0"                  # Version to pull
      
      deploy-to-development: true
      development-namespace: "dev-services"
      development-helm-set-values: "environment=development,debug=true"
      
    secrets:
      registry-username: ${{ secrets.REGISTRY_USERNAME }}
      registry-password: ${{ secrets.REGISTRY_PASSWORD }}
      kubeconfig: ${{ secrets.KUBECONFIG }}
```

### Harbor Chart Repository
```yaml
jobs:
  api-pipeline:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      # Chart configuration - Harbor registry
      chart-name: "web-api"                   # Your app name in cluster
      chart-path: "https://harbor.example.com/chartrepo/public"
      source-chart-name: "generic-api"       # Chart to pull from repo
      chart-version: "latest"                # Version to pull
      
      deploy-to-development: true
      development-helm-set-values: "ingress.enabled=true,service.type=ClusterIP"
      
    secrets:
      registry-username: ${{ secrets.HARBOR_USERNAME }}
      registry-password: ${{ secrets.HARBOR_PASSWORD }}
      kubeconfig: ${{ secrets.KUBECONFIG }}
```

**How it works** (matching Azure Pipelines pattern):
1. � **Repository**: Adds the chart repository URL to Helm  
2. � **Pull**: Pulls the `source-chart-name` chart from the repository
3. ✏️ **Rename**: Renames the chart to your `chart-name` 
4. ✏️ **Repackage**: Updates Chart.yaml with your app name and version
5. 📦 **Push**: Pushes the customized chart to your registry  
6. 🚀 **Deploy**: Deploys with your app name visible in Kubernetes

## Full Pipeline - All Environments

```yaml
jobs:
  api-pipeline:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      # Chart configuration
      chart-name: "advanced-api"
      chart-path: "./helm/chart"  # Local chart
      
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
      
      # Enable all deployments
      deploy-to-development: true
      deploy-to-staging: true
      deploy-to-production: true
      
      # Development deployment
      development-namespace: "dev-apis"
      development-helm-set-values: |
        app.environment=Development
        service.port=8080
        ingress.host=advanced-api-dev.example.com
        resources.requests.memory=256Mi
        resources.limits.memory=512Mi
      development-branch-pattern: "^(main|develop|feature/.+)$"
        
      # Staging deployment
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
   - Uses `helm-package-push` action to package and push Helm chart (only if `use-external-chart` is false)

3. **Deploy Development Job**: 
   - Uses `helm-deploy` action to deploy to development environment
   - Triggered based on development branch pattern
   - **Optional** - controlled by `deploy-to-development` input (disabled by default)

4. **Deploy Staging Job**: 
   - Uses `helm-deploy` action to deploy to staging environment
   - Triggered based on staging branch pattern
   - Depends on successful development deployment (if development is enabled)
   - **Optional** - controlled by `deploy-to-staging` input (disabled by default)

5. **Deploy Production Job**: 
   - Uses `helm-deploy` action to deploy to production environment
   - Triggered based on production branch pattern
   - Depends on successful staging deployment (if staging is enabled)
   - **Optional** - controlled by `deploy-to-production` input (disabled by default)

## Chart Configuration Options

### Local Chart (Default)
```yaml
use-external-chart: false
chart-path: "./chart"
# Chart will be packaged and pushed to OCI registry
```

### External Chart
```yaml
use-external-chart: true
chart-repo: "https://charts.sf9.io"
chart-name: "s9genericchart"
chart-version: "1.2.3"  # or "latest"
# Chart will be pulled from external repository
```

## Composite Actions Used

- `simplify9/.github/.github/actions/determine-semver@main`: Semantic version calculation
- `simplify9/.github/.github/actions/docker-build-push@main`: Docker build and push
- `simplify9/.github/.github/actions/helm-package-push@main`: Helm chart packaging and push
- `simplify9/.github/.github/actions/tag-github-origin@main`: Git release tagging  
- `simplify9/.github/.github/actions/helm-deploy@main`: Kubernetes deployment

## Supported Chart Sources

### ✅ **Local Charts**
- ✅ `"./chart"` - Chart in root chart directory
- ✅ `"./helm/mychart"` - Chart in subdirectory
- ✅ `"charts/api-chart"` - Relative path to chart
- ✅ Any local directory containing Chart.yaml

### ✅ **External Chart Repositories**  
- ✅ **GitHub Pages**: `"https://my-org.github.io/helm-charts"`
- ✅ **SF9 Charts**: `"https://charts.sf9.io"`
- ✅ **Harbor Registry**: `"https://harbor.example.com/chartrepo/public"`
- ✅ **Artifactory**: `"https://artifactory.company.com/helm"`
- ✅ **ChartMuseum**: `"https://charts.company.com"`
- ✅ Any HTTP/HTTPS Helm repository

### ❌ **Not Supported**
- ❌ Git repositories (`git://` or SSH URLs)
- ❌ OCI registries in chart-path (these should use local charts)
- ❌ File system paths outside the repository (`/absolute/paths`)

## Chart Validation Checklist

Before using external charts, verify:

- [ ] **Repository is accessible**: URL returns 200 OK
- [ ] **Chart exists**: Chart name exists in the repository
- [ ] **Version available**: Specified version exists (or use "latest")
- [ ] **Repository is public** or credentials are configured
- [ ] **Chart is compatible** with your application requirements

**Quick validation command**:
```bash
# Replace with your values
REPO_URL="https://charts.sf9.io"
SOURCE_CHART_NAME="s9genericchart"    # Chart to pull from repo
YOUR_APP_NAME="my-api"                # Your app name (can be anything)
VERSION="1.2.3"

# Test the repository and chart
helm repo add validate-repo "$REPO_URL"
helm repo update
helm search repo "validate-repo/$SOURCE_CHART_NAME" --version "$VERSION"

# Test pulling the chart
helm pull "validate-repo/$SOURCE_CHART_NAME" --version "$VERSION" --untar
ls -la "$SOURCE_CHART_NAME"/
```

### **External Chart Not Found**
If you see errors like "Failed to pull chart", verify:

1. **Chart Repository URL**: Ensure the URL is accessible
   ```bash
   # Test locally
   helm repo add test-repo https://your-chart-url.com
   helm repo update
   helm search repo test-repo
   ```

2. **Chart Name**: Verify the chart exists in the repository
   ```yaml
   # Make sure this chart exists in the repository
   chart-name: "existing-chart-name"
   chart-path: "https://charts.example.com"
   ```

3. **Chart Version**: Check if the version exists
   ```bash
   # List available versions
   helm search repo test-repo/chart-name --versions
   ```

### **Common Chart Configuration Issues**

#### ❌ **Wrong**: Using chart name that doesn't exist in the repository
```yaml
chart-name: "my-api"                 # Your app name (correct)
chart-path: "https://charts.sf9.io" # Repository URL (correct)
source-chart-name: "nonexistent"    # Chart doesn't exist in sf9 repo (WRONG)
```

#### ✅ **Correct**: Using existing source chart name  
```yaml
chart-name: "my-api"                 # Your app name 
chart-path: "https://charts.sf9.io" # Repository URL
source-chart-name: "s9genericchart" # Chart exists in sf9 repo (CORRECT)
```

#### ❌ **Wrong**: Missing source chart name for external charts
```yaml
chart-name: "my-api"
chart-path: "https://custom-repo.com"
# source-chart-name: missing - will default to "s9genericchart" which may not exist
```

#### ✅ **Correct**: Specifying correct source chart name
```yaml
chart-name: "my-api"                 # Your app name
chart-path: "https://custom-repo.com"
source-chart-name: "web-template"   # Chart that exists in custom-repo
```

#### 💡 **Pro Tip**: Match Azure Pipelines pattern
```yaml
# Azure Pipelines equivalent:
# chartName: 's9genericchart'  
# --repo https://charts.sf9.io

# GitHub Actions equivalent:
chart-name: "my-api"                 # Your app name (different from Azure!)
chart-path: "https://charts.sf9.io" # Same repo URL
source-chart-name: "s9genericchart" # Same as Azure chartName
```

### **Chart Repository Authentication**
For private repositories, ensure your secrets are configured:

```yaml
secrets:
  # May need repository-specific credentials
  registry-username: ${{ secrets.CHART_REPO_USERNAME }}
  registry-password: ${{ secrets.CHART_REPO_PASSWORD }}
```

### **Debugging Steps**

1. **Check repository accessibility**:
   ```bash
   curl -I https://your-chart-repository.com
   ```

2. **Test chart pull locally**:
   ```bash
   helm repo add debug-repo https://your-chart-repository.com
   helm search repo debug-repo
   helm pull debug-repo/your-chart-name --version your-version
   ```

3. **Verify chart structure**:
   ```bash
   tar -tf your-chart-name-version.tgz
   ```

- **API-focused**: Optimized for API deployments without .NET specific steps
- **Three-Environment Pipeline**: Built-in support for development, staging, and production deployments
- **All Deployments Optional**: Each deployment stage can be enabled/disabled independently
- **Branch-based**: Configurable branch patterns for deployment conditions
- **Dependency Chain**: Smart deployment dependencies (dev → staging → production)
- **Simplified**: Removed NuGet packaging and testing steps
- **Automatic App Naming**: The template automatically sets `app.name` to your `chart-name`, so you'll see your application name instead of generic chart names in your cluster

## Automatic App Name Configuration

The template uses an intelligent repackaging approach to ensure your application appears with the correct name:

### **For Local Charts**
- ✅ **Direct usage**: Your chart is packaged and deployed as-is
- ✅ **App name**: Uses the name defined in your Chart.yaml

### **For External Charts**  
- 🔄 **Smart repackaging**: Template pulls the external chart, modifies its metadata with your `chart-name`, and repackages it
- ✅ **Custom app name**: Your `chart-name` becomes the actual chart name and app name
- 📦 **Unified deployment**: External charts are treated exactly like local charts after repackaging

**Benefits**:
- ✅ **Proper identification**: Your application appears with YOUR name in Kubernetes
- ✅ **No more generic names**: Never see "s9genericchart" in your cluster
- ✅ **Consistent experience**: Local and external charts work identically
- ✅ **Zero configuration**: Automatically handled by the template

**Example**: With `chart-name: "payment-api"` and `chart-path: "https://charts.sf9.io"`:
1. Template pulls `s9genericchart` from sf9 repository
2. Renames it to `payment-api` in Chart.yaml  
3. Repackages and pushes as `payment-api:1.0.0`
4. Deploys with app name `payment-api` in your cluster

## Fixing Common Calling Workflow Issues

### 🔧 **Issue 1**: Workflow fails with "chart not found"

**Problem**: Using external chart but wrong source chart name
```yaml
# ❌ Broken calling workflow
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      chart-name: "my-api"
      chart-path: "https://charts.sf9.io"
      # Missing or wrong source-chart-name
```

**Solution**: Add correct source chart name
```yaml
# ✅ Fixed calling workflow
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      chart-name: "my-api"                    # Your app name
      chart-path: "https://charts.sf9.io"    # Repository URL
      source-chart-name: "s9genericchart"    # Chart that exists in the repo
      chart-version: "1.2.3"                 # Optional: specific version
```

### 🔧 **Issue 2**: No deployments happening

**Problem**: All deployments are disabled by default
```yaml
# ❌ Broken - no deployments enabled
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      chart-name: "my-api"
      # No deploy-to-* flags set
```

**Solution**: Enable the deployments you need
```yaml
# ✅ Fixed - enable deployments explicitly
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      chart-name: "my-api"
      deploy-to-development: true    # Enable dev deployment
      deploy-to-staging: true        # Enable staging deployment
      # deploy-to-production: false  # Keep production disabled for safety
```

### 🔧 **Issue 3**: Secret handling errors

**Problem**: Secrets not properly passed or named incorrectly
```yaml
# ❌ Broken secret handling
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      chart-name: "my-api"
      deploy-to-development: true
    secrets:
      # Wrong secret names or missing secrets
      username: ${{ secrets.DOCKER_USERNAME }}
      password: ${{ secrets.DOCKER_PASSWORD }}
```

**Solution**: Use correct secret names and include all required secrets
```yaml
# ✅ Fixed secret handling
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      chart-name: "my-api"
      deploy-to-development: true
    secrets:
      # Correct secret names (as defined in template)
      registry-username: ${{ secrets.REGISTRY_USERNAME }}
      registry-password: ${{ secrets.REGISTRY_PASSWORD }}
      kubeconfig: ${{ secrets.KUBECONFIG }}
      development-helm-set-secret-values: ${{ secrets.DEV_HELM_SECRETS }}
```

### 🔧 **Issue 4**: Converting from Azure Pipelines

**Problem**: Direct translation doesn't work
```yaml
# ❌ Wrong translation from Azure Pipelines
# Azure: chartName: 's9genericchart', --repo https://charts.sf9.io
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      chart-name: "s9genericchart"           # Wrong - this is source chart name
      chart-path: "https://charts.sf9.io" 
```

**Solution**: Separate your app name from source chart name
```yaml
# ✅ Correct Azure Pipelines translation
# Azure: chartName: 's9genericchart', --repo https://charts.sf9.io
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      chart-name: "my-actual-app-name"       # Your app name (what you want in cluster)
      chart-path: "https://charts.sf9.io"   # Same repo URL
      source-chart-name: "s9genericchart"   # Azure's chartName goes here
```

### 🔧 **Issue 5**: Wrong Docker/Chart paths

**Problem**: Default paths don't match your project structure
```yaml
# ❌ Broken with non-standard paths
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      chart-name: "my-api"
      # Using defaults: dockerfile-path: "./Dockerfile", chart-path: "./chart"
      # But your project has: src/MyApi/Dockerfile, deployment/helm/
```

**Solution**: Specify correct paths for your project
```yaml
# ✅ Fixed with correct paths
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      chart-name: "my-api"
      dockerfile-path: "./src/MyApi/Dockerfile"  # Your actual Dockerfile location
      docker-context: "./src"                    # Build context
      chart-path: "./deployment/helm"            # Your actual chart location
```

### 🔧 **Issue 6**: Environment-specific configuration

**Problem**: Same configuration for all environments
```yaml
# ❌ No environment-specific settings
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      chart-name: "my-api"
      deploy-to-development: true
      deploy-to-production: true
      # Same settings for dev and prod - dangerous!
```

**Solution**: Configure each environment appropriately
```yaml
# ✅ Environment-specific configuration
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      chart-name: "my-api"
      deploy-to-development: true
      deploy-to-production: true
      
      # Development: relaxed settings
      development-namespace: "dev"
      development-helm-set-values: "replicas=1,resources.limits.memory=512Mi,debug=true"
      
      # Production: strict settings  
      production-namespace: "production"
      production-helm-set-values: "replicas=3,resources.limits.memory=2Gi,debug=false,autoscaling.enabled=true"
    secrets:
      registry-username: ${{ secrets.REGISTRY_USERNAME }}
      registry-password: ${{ secrets.REGISTRY_PASSWORD }}
      kubeconfig: ${{ secrets.KUBECONFIG }}
      development-helm-set-secret-values: ${{ secrets.DEV_SECRETS }}
      production-helm-set-secret-values: ${{ secrets.PROD_SECRETS }}
```

### 🔧 **Issue 7**: Version/tagging problems

**Problem**: No version control or wrong versioning
```yaml
# ❌ No version strategy
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      chart-name: "my-api"
      # No version inputs - gets default 1.0.x
```

**Solution**: Define proper versioning strategy
```yaml
# ✅ Proper version management
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/api-cicd.yml@main
    with:
      chart-name: "my-api"
      major-version: "2"        # Control major version
      minor-version: "1"        # Control minor version  
      # Patch version auto-incremented based on commits
    secrets:
      github-token: ${{ secrets.GITHUB_TOKEN }}  # For release tagging
```

### 🚀 **Quick Fix Checklist**

When your calling workflow fails, check these in order:

1. **✅ Required inputs set**:
   - [ ] `chart-name` is specified (this becomes your app name)

2. **✅ Chart configuration correct**:
   - [ ] For local charts: `chart-path` points to your chart directory  
   - [ ] For external charts: `chart-path` is repository URL AND `source-chart-name` is correct

3. **✅ Deployments enabled**:
   - [ ] At least one `deploy-to-*` is set to `true`

4. **✅ Secrets provided**:
   - [ ] `registry-username` and `registry-password` set
   - [ ] `kubeconfig` set for deployments
   - [ ] Environment secrets set if using secret values

5. **✅ Paths match your project**:
   - [ ] `dockerfile-path` points to your actual Dockerfile
   - [ ] `docker-context` is correct build context
   - [ ] `chart-path` points to your chart (if local)

### 🎯 **Migration from Other Templates**

**From ci-helm template**:
```yaml
# Old ci-helm approach
- uses: ./.github/workflows/ci-helm.yml
  with:
    use-external-chart: true
    chart-repo: "https://charts.sf9.io"
    chart-name: "s9genericchart"

# New api-cicd approach  
- uses: simplify9/.github/.github/workflows/api-cicd.yml@main
  with:
    chart-name: "my-app"                    # Your app name
    chart-path: "https://charts.sf9.io"    # Repository URL
    source-chart-name: "s9genericchart"    # Chart to pull
    deploy-to-development: true             # Enable deployment
```

**From sw-cicd template** (if you were using it for APIs):
```yaml
# Most inputs transfer directly, just add:
deploy-to-development: true  # Enable the deployments you need
deploy-to-staging: true      # sw-cicd doesn't have staged deployments
```