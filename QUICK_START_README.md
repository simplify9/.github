# 🚀 Simplify9 Reusable Workflows

Quick-start templates for common deployment scenarios.

---

## 📋 **Cloudflare Pages for Vite Apps** - Most Popular! 

**Perfect for:** React, Vue, Svelte, or any Vite-based applications

### **⚡ 30-Second Setup**

1. **One-time org setup** (ask DevOps if not done):
   - Set organization secrets: `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`

2. **Copy this to your Vite project** → `.github/workflows/deploy.yml`:

```yaml
name: Deploy to Cloudflare Pages

on:
  push:
    branches: [development, main]

jobs:
  deploy-dev:
    if: github.ref == 'refs/heads/development'
    uses: simplify9/.github/.github/workflows/vite-ci.yml@main
    with:
      project-name: my-awesome-app        # 👈 CHANGE THIS
      environment: development
      project-name-suffix: -dev
      build-directory: dist               # 👈 Vite uses 'dist', not 'build'

  deploy-prod:
    if: github.ref == 'refs/heads/main'
    uses: simplify9/.github/.github/workflows/vite-ci.yml@main
    with:
      project-name: my-awesome-app        # 👈 SAME NAME
      environment: production
      build-directory: dist
      run-tests: true
```

3. **Done!** Push to `development` or `main` and watch it deploy.

### **📝 Customization Checklist**

**Required changes:**
- [ ] Change `project-name` to your actual app name
- [ ] Verify `build-directory` (Vite = `dist`, CRA = `build`)

**Optional customizations:**
- [ ] Add custom domains: `custom-domain: yourapp.com`
- [ ] Change package manager: `package-manager: yarn` or `pnpm`  
- [ ] Add staging environment (copy dev job, change branch to `staging`)

### **🎯 Common Patterns**

<details>
<summary><strong>Pattern 1: Basic Dev + Prod (Most Common)</strong></summary>

```yaml
name: Deploy to Cloudflare Pages
on:
  push:
    branches: [development, main]

jobs:
  deploy-dev:
    if: github.ref == 'refs/heads/development'
    uses: simplify9/.github/.github/workflows/vite-ci.yml@main
    with:
      project-name: customer-portal
      environment: development
      project-name-suffix: -dev
      build-directory: dist

  deploy-prod:
    if: github.ref == 'refs/heads/main'
    uses: simplify9/.github/.github/workflows/vite-ci.yml@main
    with:
      project-name: customer-portal
      environment: production
      build-directory: dist
      run-tests: true
```

**Result:**
- `development` branch → `customer-portal-dev` 
- `main` branch → `customer-portal`

</details>

<details>
<summary><strong>Pattern 2: Three Environments (Dev + Staging + Prod)</strong></summary>

```yaml
name: Deploy to Cloudflare Pages
on:
  push:
    branches: [development, staging, main]

jobs:
  deploy-dev:
    if: github.ref == 'refs/heads/development'
    uses: simplify9/.github/.github/workflows/vite-ci.yml@main
    with:
      project-name: admin-dashboard
      environment: development
      project-name-suffix: -dev
      build-directory: dist

  deploy-staging:
    if: github.ref == 'refs/heads/staging'
    uses: simplify9/.github/.github/workflows/vite-ci.yml@main
    with:
      project-name: admin-dashboard
      environment: staging
      project-name-suffix: -staging
      build-directory: dist
      run-tests: true

  deploy-prod:
    if: github.ref == 'refs/heads/main'
    uses: simplify9/.github/.github/workflows/vite-ci.yml@main
    with:
      project-name: admin-dashboard
      environment: production
      build-directory: dist
      run-tests: true
      fail-on-domain-error: true
```

**Result:**
- `development` → `admin-dashboard-dev`
- `staging` → `admin-dashboard-staging`  
- `main` → `admin-dashboard`

</details>

<details>
<summary><strong>Pattern 3: With Custom Domains</strong></summary>

```yaml
jobs:
  deploy-dev:
    if: github.ref == 'refs/heads/development'
    uses: simplify9/.github/.github/workflows/vite-ci.yml@main
    with:
      project-name: client-app
      environment: development
      project-name-suffix: -dev
      build-directory: dist
      custom-domain: dev.clientapp.com

  deploy-prod:
    if: github.ref == 'refs/heads/main'
    uses: simplify9/.github/.github/workflows/vite-ci.yml@main
    with:
      project-name: client-app
      environment: production
      build-directory: dist
      custom-domain: clientapp.com
      fail-on-domain-error: true
```

</details>

<details>
<summary><strong>Pattern 4: Using Yarn/PNPM</strong></summary>

```yaml
deploy-dev:
  uses: simplify9/.github/.github/workflows/vite-ci.yml@main
  with:
    project-name: my-app
    environment: development
    project-name-suffix: -dev
    build-directory: dist
    package-manager: yarn              # or 'pnpm'
    build-command: yarn build          # or 'pnpm build'
    test-command: yarn test            # or 'pnpm test'
```

</details>

### **🔧 All Configuration Options**

| Setting | Description | Default | Common Values |
|---------|-------------|---------|---------------|
| `project-name` | **Cloudflare project name** | - | `customer-portal`, `admin-app` |
| `environment` | Environment label | `development` | `development`, `staging`, `production` |
| `project-name-suffix` | Added to project name | `''` | `-dev`, `-staging`, `-prod` |
| `build-directory` | Where your build outputs | `build` | `dist` (Vite), `build` (CRA) |
| `custom-domain` | Your domain | `''` | `myapp.com`, `dev.myapp.com` |
| `package-manager` | Package manager | `npm` | `npm`, `yarn`, `pnpm` |
| `node-version` | Node.js version | `18` | `16`, `18`, `20` |
| `run-tests` | Run tests before deploy | `true` | `true`, `false` |
| `fail-on-domain-error` | Fail if domain setup fails | `false` | `true` (prod), `false` (dev) |

### **🆘 Troubleshooting**

**❌ "Build directory not found"**
- **Fix:** Change `build-directory: dist` (Vite projects use `dist`, not `build`)

**❌ "Project creation failed"**  
- **Fix:** Check if project name already exists in Cloudflare
- **Fix:** Ensure you have Cloudflare Pages quota available

**❌ "Domain setup failed"**
- **Fix:** Set `fail-on-domain-error: false` for development
- **Fix:** Check if domain is already configured in another project

**❌ "Unauthorized"**
- **Fix:** Ask DevOps to verify organization secrets are set

---

## 📋 **Other Available Templates**

### **.NET Applications → Kubernetes**
Use `sw-cicd.yml` for complete .NET CI/CD with Docker + Helm + Kubernetes deployment.

### **Docker Images**  
Use `ci-docker.yaml` for building and pushing Docker images.

### **Helm Charts**
Use `ci-helm.yaml` for deploying Helm charts to Kubernetes.

---

## 💡 **Need Help?**

1. **Quick questions**: Check the troubleshooting section above
2. **Template not working**: Compare your workflow with the patterns above
3. **New requirements**: Open an issue or ask in team chat

**Most common fix:** Change `build-directory: dist` for Vite projects! 🎯