# Verify Cloudflare Build Action

This composite action validates the build output from `@cloudflare/next-on-pages` to ensure proper deployment structure.

## What it does

- ✅ Validates `.vercel/output/` directory structure
- ✅ Checks for static assets in correct location
- ✅ Detects Functions for SSR support
- ✅ Counts files and provides build summary
- ✅ Shows sample files for debugging

## Usage

```yaml
- name: Verify Cloudflare build output
  uses: simplify9/.github/.github/actions/verify-cloudflare-build@main
  with:
    build-directory: .vercel/output/static  # Optional
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `build-directory` | Directory where build output should be located | No | `.vercel/output/static` |

## Outputs

| Output | Description |
|--------|-------------|
| `build-valid` | Whether the build output is valid |
| `has-functions` | Whether Functions were generated (SSR detected) |
| `static-files-count` | Number of static files generated |

## Expected Structure

After `@cloudflare/next-on-pages` runs, it should create:

```
.vercel/output/
├── static/           # Static assets (HTML, CSS, JS, images)
│   ├── _next/        # Next.js built assets
│   ├── favicon.ico   # Static files
│   └── ...
├── functions/        # Server-side functions (if SSR/API routes)
│   └── index.js      # Main server function
└── config.json       # Deployment configuration
```

## What it validates

### Required Structure
- ✅ `.vercel/output/` directory exists
- ✅ `.vercel/output/static/` contains static assets
- ✅ Counts total static files

### Optional Features
- 🔍 Detects `.vercel/output/functions/` (indicates SSR)
- 🔍 Shows sample function files
- 🔍 Displays build configuration if present

### Debug Information
- 📄 Lists first 10 static files
- ⚡ Shows function files (up to 5)
- ⚙️ Displays config.json content (first 10 lines)

## Example Output

```
✅ Cloudflare build structure found:
📁 Static assets directory found:
   Found 42 static files
📄 Sample static files:
   .vercel/output/static/_next/static/chunks/main.js
   .vercel/output/static/_next/static/css/app.css
   .vercel/output/static/favicon.ico

⚡ Functions directory found:
   Found 3 function files
🔧 Function files:
   .vercel/output/functions/index.js
   .vercel/output/functions/api/hello.js

✅ Build output validation completed successfully
```

## Error Handling

```
❌ .vercel/output directory not found!
This suggests @cloudflare/next-on-pages didn't run properly.

Expected structure after @cloudflare/next-on-pages build:
  .vercel/output/static/    <- Static assets
  .vercel/output/functions/ <- Server functions (if any)
```