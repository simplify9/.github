# 📚 Next.js Cloudflare Workers Documentation Index

## 🎯 **Main Documentation**

### **Primary Guide** 
👉 **[NEXTJS_WORKERS_CI_USAGE.md](./NEXTJS_WORKERS_CI_USAGE.md)** - Complete usage guide with examples

### **Quick Reference**
👉 **[COMPLETE_CALLING_WORKFLOW_EXAMPLES.md](./COMPLETE_CALLING_WORKFLOW_EXAMPLES.md)** - Copy-paste workflow examples  
👉 **[CHEAT_SHEET.md](./CHEAT_SHEET.md)** - Quick reference section for Next.js

## 🔧 **Technical Deep Dives**

### **Next.js 15 Compatibility**
👉 **[NEXTJS_15_BUG_FIXES.md](./NEXTJS_15_BUG_FIXES.md)** - Next.js 15 compatibility fixes applied

### **CI/CD Domain Handling**
👉 **[CICD_DOMAIN_FIX.md](./CICD_DOMAIN_FIX.md)** - How we made domain setup CI/CD friendly

### **Template Enhancement Summary**
👉 **[ENHANCED_TEMPLATE_SUMMARY.md](./ENHANCED_TEMPLATE_SUMMARY.md)** - Complete transformation overview

## 🚀 **Template Features Overview**

### ✅ **Next.js 15 Compatible**
- Auto-detects modern `_worker.js/index.js` directory structure
- Falls back to legacy `_worker.js` single file structure
- Smart asset handling with @cloudflare/next-on-pages

### ✅ **CI/CD Friendly**
- Checks for existing domain routes before creation
- Graceful handling of "route already exists" scenarios
- Idempotent deployments (can run multiple times safely)

### ✅ **Package Manager Flexible**
- Supports npm, yarn, and pnpm
- Configurable install and build commands
- Proper dependency caching

### ✅ **Custom Domain Support**
- Automatic Cloudflare route creation
- Custom domain pattern support
- Multi-environment domain handling

### ✅ **Quality Gates**
- Optional linting and testing
- Configurable commands for different setups
- Build verification and validation

## 📝 **Usage Patterns**

### **Simple Setup (Recommended)**
```yaml
uses: simplify9/.github/.github/workflows/next-ci.yml@main
with:
  environment: 'production'
  package-manager: 'yarn'
  install-command: 'yarn install --frozen-lockfile'
secrets:
  CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
  CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
```

### **Advanced Configuration**
See [COMPLETE_CALLING_WORKFLOW_EXAMPLES.md](./COMPLETE_CALLING_WORKFLOW_EXAMPLES.md) for comprehensive examples.

## 🔄 **Migration from Old Templates**

The template has been completely rebuilt to:
1. ✅ Support Next.js 15 out-of-the-box
2. ✅ Handle modern @cloudflare/next-on-pages builds
3. ✅ Provide CI/CD friendly domain management
4. ✅ Maintain backward compatibility

**No breaking changes** - existing workflows will continue to work while gaining new capabilities.

## 🎯 **Next Steps**

1. **Start Here**: [NEXTJS_WORKERS_CI_USAGE.md](./NEXTJS_WORKERS_CI_USAGE.md)
2. **Copy Examples**: [COMPLETE_CALLING_WORKFLOW_EXAMPLES.md](./COMPLETE_CALLING_WORKFLOW_EXAMPLES.md)  
3. **Quick Reference**: [CHEAT_SHEET.md](./CHEAT_SHEET.md)
4. **Add Repository Secrets**: `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`
5. **Deploy**: Push to your branch and watch it work! 🚀