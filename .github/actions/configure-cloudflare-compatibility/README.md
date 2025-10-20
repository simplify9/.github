# Configure Cloudflare Compatibility Action

This composite action configures the required compatibility flags for Next.js applications on Cloudflare Pages.

## What it does

- ✅ Sets `nodejs_compat` flag for Next.js SSR support
- ✅ Configures compatibility date for Workers runtime
- ✅ Updates both production and preview environments
- ✅ Handles API errors gracefully with manual instructions
- ✅ Supports custom compatibility flags

## Usage

```yaml
- name: Configure Next.js compatibility flags
  uses: simplify9/.github/.github/actions/configure-cloudflare-compatibility@main
  with:
    api-token: ${{ secrets.CLOUDFLARE_API_TOKEN }}
    account-id: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
    project-name: my-nextjs-app
    compatibility-date: '2024-10-20'              # Optional
    compatibility-flags: 'nodejs_compat'          # Optional
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `api-token` | Cloudflare API token | Yes | - |
| `account-id` | Cloudflare account ID | Yes | - |
| `project-name` | Name of the Cloudflare Pages project | Yes | - |
| `compatibility-date` | Cloudflare Workers compatibility date | No | `2024-10-20` |
| `compatibility-flags` | Comma-separated list of compatibility flags | No | `nodejs_compat` |

## Outputs

| Output | Description |
|--------|-------------|
| `configured` | Whether compatibility flags were successfully configured |
| `flags-applied` | List of flags that were applied |

## Compatibility Flags

### Default: `nodejs_compat`
Required for Next.js SSR to work on Cloudflare Workers.

### Custom Flags
You can specify multiple flags:
```yaml
compatibility-flags: 'nodejs_compat,streams_enable_constructors'
```

## API Operations

### What it does
1. **Fetches** current project configuration
2. **Updates** both production and preview environments
3. **Sets** compatibility flags and date
4. **Verifies** configuration was applied

### API Endpoints Used
- `GET /accounts/{account}/pages/projects/{project}` - Fetch project
- `PATCH /accounts/{account}/pages/projects/{project}` - Update config

## Error Handling

### Graceful Degradation
If API calls fail, the action:
- ❌ **Doesn't fail the workflow**
- ⚠️ **Provides manual instructions**
- 📖 **Shows exact steps to fix**

### Manual Setup Instructions
```
⚠️ Please manually set compatibility flags in Cloudflare dashboard:
   1. Go to Cloudflare Pages → my-nextjs-app
   2. Settings → Functions → Compatibility flags
   3. Add flags: nodejs_compat
   4. Set compatibility date: 2024-10-20
```

## Example Success Output

```
🔧 Setting up compatibility flags for Next.js SSR...
📋 Flags to apply: ["nodejs_compat"]
📅 Compatibility date: 2024-10-20
🔍 Fetching current project settings...
✅ Project found, updating compatibility flags...
🔄 Updating production environment...
✅ Compatibility flags configured successfully
🎯 Applied flags: nodejs_compat
🎯 Compatibility date: 2024-10-20
🎯 Environments: production, preview

🎉 Next.js is now properly configured for Cloudflare Pages!
🚀 Your SSR application should work correctly
```

## Why This is Needed

Without `nodejs_compat` flag, Next.js SSR applications show:
```
The page you've requested has been built using @cloudflare/next-on-pages, 
but hasn't been properly configured.

You should go to the Pages project's Compatibility Flags settings section 
and add the nodejs_compat flag to both your production and preview environments.
```

This action automates that configuration! 🎉