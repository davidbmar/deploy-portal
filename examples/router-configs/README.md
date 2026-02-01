# Router Configuration Examples for Subpath Deployments

This directory contains correct router configuration examples for deploying SPAs to subpaths (e.g., `/app-name/`).

## Problem

When deploying to a subpath, the router needs to know the base path. Without this configuration, you'll see:
- "404 Page Not Found"
- "Did you forget to add the page to the router?"
- Routes don't match even though assets load correctly

## Examples

### Wouter
**File:** `wouter-app.tsx`

**Key Change:**
```tsx
import { Router, Switch, Route } from "wouter";

<Router base="/app-name">
  <Switch>...</Switch>
</Router>
```

### React Router
**File:** `react-router-app.tsx`

**Key Change:**
```tsx
<BrowserRouter basename="/app-name">
  <Routes>...</Routes>
</BrowserRouter>
```

## Quick Reference

| Router | Component | Prop Name | Example |
|--------|-----------|-----------|---------|
| Wouter | `<Router>` | `base` | `<Router base="/app-name">` |
| React Router | `<BrowserRouter>` | `basename` | `<BrowserRouter basename="/app-name">` |
| TanStack Router | `createRouter()` | `basepath` | `basepath: '/app-name'` |
| Vue Router | `createWebHistory()` | First param | `createWebHistory('/app-name')` |

## Testing

After updating your router configuration:

1. **Rebuild container:**
   ```bash
   sg docker -c 'docker-compose build --no-cache && docker-compose up -d'
   ```

2. **Test navigation:**
   - Root path: `https://server/app-name/`
   - Should load Dashboard, not 404
   - Click links should work
   - Browser back/forward should work

## Scanner Tool

Use the subpath-scanner to detect missing router configuration:

```bash
cd /home/ubuntu/src/deploy-portal/subpath-scanner
node dist/cli.js scan --dir=/path/to/your/app
```

## Documentation

See also:
- `../docs/FRAMEWORK_SUBPATH_CONFIG.md` - Complete framework configuration guide
- `../scripts/configure-client-router.sh` - Automated router detection script
- `app.py` Step 5.6 - Router configuration instructions in deployment kit
