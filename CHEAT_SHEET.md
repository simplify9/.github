# 🚀 Cloudflare Pages Deployment - Cheat Sheet

## **Prerequisites (One-time setup)**
Ask DevOps to set these **Organization secrets**:
- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

## **Template File**
Copy to your project: `.github/workflows/deploy.yml`

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
      project-name: YOUR_APP_NAME          # 👈 CHANGE THIS
      environment: development
      project-name-suffix: -dev
      build-directory: dist                # 👈 'dist' for Vite, 'build' for CRA

  deploy-prod:
    if: github.ref == 'refs/heads/main'
    uses: simplify9/.github/.github/workflows/vite-ci.yml@main
    with:
      project-name: YOUR_APP_NAME          # 👈 SAME NAME
      environment: production
      build-directory: dist
      run-tests: true
```

## **Required Changes**
1. **`project-name`**: Your app name (e.g., `customer-portal`, `admin-app`)
2. **`build-directory`**: 
   - Vite projects: `dist`
   - Create React App: `build`

## **Optional Additions**

**Custom domains:**
```yaml
custom-domain: yourapp.com               # Add this line
fail-on-domain-error: true              # Fail if domain setup fails
```

**Staging environment:**
```yaml
deploy-staging:
  if: github.ref == 'refs/heads/staging'
  uses: simplify9/.github/.github/workflows/vite-ci.yml@main
  with:
    project-name: YOUR_APP_NAME
    environment: staging
    project-name-suffix: -staging
    build-directory: dist
```

**Different package manager:**
```yaml
package-manager: yarn                    # or 'pnpm'
build-command: yarn build               # or 'pnpm build'
test-command: yarn test                 # or 'pnpm test'
```

## **What Gets Created**

| Branch Push | Creates Project | URL |
|-------------|----------------|-----|
| `development` | `your-app-dev` | Auto-generated + custom domain |
| `staging` | `your-app-staging` | Auto-generated + custom domain |
| `main` | `your-app` | Auto-generated + custom domain |

## **Common Issues**

❌ **"Build directory not found"**  
→ Fix: Use `build-directory: dist` for Vite projects

❌ **"Project creation failed"**  
→ Fix: Check project name isn't already taken

❌ **"Unauthorized"**  
→ Fix: Ask DevOps about organization secrets

## **Need More Examples?**
👉 [QUICK_START_README.md](./QUICK_START_README.md) - Complete guide with patterns