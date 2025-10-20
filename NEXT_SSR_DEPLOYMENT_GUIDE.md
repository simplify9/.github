# Next.js Deployment to Cloudflare Pages

**For:** Next.js Applications (SSR, Static, API Routes)  
**Platform:** Cloudflare Pages with Functions  
**Quick Start:** Follow the setup guide below

---

## 🎯 **What This Template Does**

✅ **Deploys SSR Next.js apps** to Cloudflare Pages with Functions  
✅ **Supports dynamic routes** and API routes  
✅ **Works with App Router and Pages Router**  
✅ **Handles middleware** and server-side rendering  
✅ **Automatic project setup** with proper configuration  
✅ **Multi-environment support** (dev, staging, production)  
✅ **Validates Next.js config** for Cloudflare compatibility  

## 🚨 **Key Differences from Static Sites**

| Feature | Static Sites (Vite/React) | Next.js Apps (SSR/Static) |
|---------|------------------------|--------------------------|
| **Template** | `vite-ci.yml` | `next-ci.yml` |
| **Build Output** | `next export` → `out/` | `@cloudflare/next-on-pages` → `.vercel/output/` |
| **Deployment** | Cloudflare Pages (static) | Cloudflare Pages + Functions |
| **Dynamic Routes** | ❌ No | ✅ Yes |
| **API Routes** | ❌ No | ✅ Yes |
| **SSR/ISR** | ❌ No | ✅ Yes |
| **Middleware** | ❌ No | ✅ Yes |

---

## 📋 **Prerequisites**

### 1. Install Required Dependencies

In your Next.js project, install the Cloudflare adapter:

```bash
npm install --save-dev @cloudflare/next-on-pages wrangler
```

### 2. Update Package.json Scripts

Add these scripts to your `package.json`:

```json
{
  "scripts": {
    "pages:build": "next-on-pages",
    "pages:dev": "next-on-pages --watch",
    "pages:preview": "wrangler pages dev .vercel/output/static --compatibility-date=2024-10-20"
  }
}
```

### 3. Next.js Configuration (Optional but Recommended)

Create or update `next.config.js`:

```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  // Remove or comment out these lines if present (they're for static export only):
  // output: 'export',
  // trailingSlash: true,
  
  // Optional: Configure for better Cloudflare compatibility
  images: {
    unoptimized: false, // Cloudflare supports image optimization
  },
  
  // Optional: Configure rewrites if needed
  async rewrites() {
    return []
  }
}

module.exports = nextConfig
```

### 4. Environment Variables (Optional)

Create `.env.local` for local development:

```bash
# Cloudflare-specific variables (if needed)
CLOUDFLARE_ACCOUNT_ID=your-account-id
NEXT_PUBLIC_APP_ENV=development
```

---

## 🚀 **Basic Workflow Setup**

Create `.github/workflows/deploy.yml` in your Next.js project:

```yaml
name: Deploy Next.js SSR to Cloudflare

on:
  push:
    branches: [development, main]

jobs:
  # Development deployment
  deploy-dev:
    if: github.ref == 'refs/heads/development'
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      project-name: my-nextjs-app
      environment: development
      project-name-suffix: -dev
      custom-domain: dev.myapp.com
      build-command: npm run pages:build

  # Production deployment
  deploy-prod:
    if: github.ref == 'refs/heads/main'
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      project-name: my-nextjs-app
      environment: production
      custom-domain: myapp.com
      build-command: npm run pages:build
      fail-on-domain-error: true
```

---

## ⚙️ **Configuration Options**

### Required Parameters

- `project-name`: Your Cloudflare project name
- `build-command`: Should be `npm run pages:build` (or equivalent)

### Common Parameters

```yaml
with:
  # Project setup
  project-name: my-app
  environment: production
  project-name-suffix: -prod
  
  # Build configuration
  build-command: npm run pages:build
  node-version: '18'
  package-manager: npm
  
  # Cloudflare specific
  custom-domain: myapp.com
  compatibility-date: '2024-10-20'
  
  # Quality checks
  run-tests: true
  run-lint: true
```

---

## 🏗️ **How It Works**

### 1. Build Process

```mermaid
graph TD
    A[Next.js Source] --> B[next build]
    B --> C[@cloudflare/next-on-pages]
    C --> D[.vercel/output/static/]
    C --> E[.vercel/output/functions/]
    D --> F[Cloudflare Pages]
    E --> G[Cloudflare Functions]
```

### 2. What Gets Created

After running `npm run pages:build`:

```
.vercel/output/
├── static/           # Static assets (HTML, CSS, JS, images)
│   ├── _next/        # Next.js assets
│   ├── favicon.ico
│   └── ...
├── functions/        # Server-side functions (if any)
│   └── index.js      # Main server function
└── config.json       # Deployment configuration
```

### 3. Deployment Flow

1. **Build**: `@cloudflare/next-on-pages` converts Next.js app
2. **Upload**: Static files go to Cloudflare Pages
3. **Functions**: Server logic runs on Cloudflare Workers
4. **Routing**: Cloudflare handles routing between static and dynamic content

---

## 🔧 **Local Development**

### Test Cloudflare Build Locally

```bash
# Build for Cloudflare
npm run pages:build

# Preview with Wrangler
npm run pages:preview

# Or run Wrangler directly
npx wrangler pages dev .vercel/output/static --compatibility-date=2024-10-20
```

### Debug Build Issues

```bash
# Verbose build output
DEBUG=1 npm run pages:build

# Check what was generated
ls -la .vercel/output/
ls -la .vercel/output/static/
ls -la .vercel/output/functions/
```

---

## 🛠️ **Supported Next.js Features**

### ✅ Fully Supported

- **App Router** and **Pages Router**
- **Server-Side Rendering (SSR)**
- **Static Site Generation (SSG)**
- **Incremental Static Regeneration (ISR)**
- **API Routes** (both App and Pages router)
- **Middleware**
- **Dynamic Routes**
- **Image Optimization** (with Cloudflare)
- **Environment Variables**

### ⚠️ Partially Supported

- **Edge Runtime**: Recommended for API routes (`export const runtime = 'edge'`)
- **Streaming**: Basic support, may have limitations
- **Server Actions**: Basic support in App Router

### ❌ Not Supported

- **Custom Server**: Cloudflare uses its own runtime
- **Node.js-specific APIs**: Must use Web APIs or Cloudflare APIs
- **File System Access**: Use Cloudflare KV/R2 for storage

---

## 🚨 **Common Issues & Solutions**

### 1. Build Fails with "Module not found"

```bash
# Solution: Install missing dependencies
npm install --save-dev @cloudflare/next-on-pages wrangler
```

### 2. "output: export" Error

```javascript
// ❌ Remove this from next.config.js
module.exports = {
  output: 'export', // This breaks SSR!
}

// ✅ Use this instead (or remove the line entirely)
module.exports = {
  // No output specified = supports SSR
}
```

### 3. Functions Not Working

Check that your API routes use Edge Runtime:

```javascript
// pages/api/hello.js or app/api/hello/route.js
export const runtime = 'edge' // Add this line

export default function handler(req, res) {
  res.json({ message: 'Hello from Cloudflare!' })
}
```

### 4. Environment Variables Not Available

```javascript
// ✅ Use NEXT_PUBLIC_ prefix for client-side variables
NEXT_PUBLIC_API_URL=https://api.example.com

// ✅ Server-side variables work normally
DATABASE_URL=secret-value
```

---

## 📊 **Performance Optimization**

### 1. Use Edge Runtime

```javascript
// In API routes and route handlers
export const runtime = 'edge'
```

### 2. Configure Caching

```javascript
// next.config.js
module.exports = {
  async headers() {
    return [
      {
        source: '/(.*)',
        headers: [
          {
            key: 'Cache-Control',
            value: 'public, max-age=31536000, immutable'
          }
        ]
      }
    ]
  }
}
```

### 3. Optimize Images

```javascript
// Use Next.js Image component
import Image from 'next/image'

function MyComponent() {
  return (
    <Image
      src="/my-image.jpg"
      width={500}
      height={300}
      alt="Description"
    />
  )
}
```

---

## 🔐 **Security Best Practices**

### 1. Environment Variables

```yaml
# In GitHub repository secrets
CLOUDFLARE_API_TOKEN: your-token
CLOUDFLARE_ACCOUNT_ID: your-account-id
DATABASE_URL: your-database-url
```

### 2. API Route Protection

```javascript
// Validate requests in API routes
export default function handler(req) {
  // Add authentication/authorization logic
  const token = req.headers.authorization
  
  if (!isValidToken(token)) {
    return new Response('Unauthorized', { status: 401 })
  }
  
  // Handle request...
}
```

---

## 📚 **Additional Resources**

- **Cloudflare Docs**: [Pages Functions](https://developers.cloudflare.com/pages/functions/)
- **Next.js on Cloudflare**: [Official Guide](https://developers.cloudflare.com/pages/framework-guides/nextjs/)
- **@cloudflare/next-on-pages**: [GitHub Repository](https://github.com/cloudflare/next-on-pages)
- **Wrangler CLI**: [Documentation](https://developers.cloudflare.com/workers/wrangler/)

---

## 🆘 **Getting Help**

If you encounter issues:

1. **Check the build logs** in GitHub Actions
2. **Test locally** with `npm run pages:preview`
3. **Validate configuration** with `npx @cloudflare/next-on-pages --help`
4. **Review Cloudflare dashboard** for deployment status
5. **Contact DevOps** for organization secrets or account access