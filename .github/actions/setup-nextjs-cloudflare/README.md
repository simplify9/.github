# Setup Next.js for Cloudflare Action

This composite action validates and prepares a Next.js application for deployment to Cloudflare Pages.

## What it does

- ✅ Verifies `@cloudflare/next-on-pages` is installed
- ✅ Installs `wrangler` if missing
- ✅ Validates Next.js configuration for Cloudflare compatibility
- ✅ Checks for required package.json scripts
- ✅ Provides helpful error messages and recommendations

## Usage

```yaml
- name: Setup Next.js for Cloudflare
  uses: simplify9/.github/.github/actions/setup-nextjs-cloudflare@main
  with:
    package-manager: npm  # Optional: npm, yarn, or pnpm
    validate-config: true # Optional: validate Next.js config
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `package-manager` | Package manager to use (npm, yarn, pnpm) | No | `npm` |
| `validate-config` | Whether to validate Next.js configuration | No | `true` |

## Outputs

| Output | Description |
|--------|-------------|
| `dependencies-installed` | Whether required dependencies were found/installed |
| `config-valid` | Whether Next.js configuration is valid for Cloudflare |

## What it checks

### Dependencies
- `@cloudflare/next-on-pages` - Required for SSR conversion
- `wrangler` - Auto-installs if missing

### Configuration
- Detects `output: 'export'` in Next.js config (incompatible with SSR)
- Validates config files (next.config.js, next.config.mjs, next.config.ts)
- Checks for `pages:build` script in package.json

### Error Handling
- Provides clear error messages with solutions
- Exits with helpful installation commands
- Suggests configuration fixes

## Example Error Messages

```
❌ @cloudflare/next-on-pages is not installed!
Please install it with: npm install --save-dev @cloudflare/next-on-pages

❌ Found 'output: export' in Next.js config. This is for static sites only!
For SSR on Cloudflare, remove 'output: export' or set it to 'standalone'

⚠️ 'pages:build' script not found in package.json
💡 Recommended: Add this script to package.json:
   "pages:build": "next-on-pages"
```