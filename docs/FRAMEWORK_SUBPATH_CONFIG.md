# Framework-Agnostic Subpath Deployment Configuration

This guide provides configuration instructions for deploying web applications to subpaths (e.g., `/app-name/`) across different frontend frameworks.

## Overview

When deploying applications to a subpath instead of the root path (`/`), frontend build tools need to know the base URL to generate correct asset paths. Without proper configuration, you'll see:

- ❌ Blank white page
- ❌ 404 errors for JavaScript and CSS files in browser console
- ❌ HTML loads but no styling or interactivity

This happens because the build tool generates asset paths like `/assets/main.js` instead of `/app-name/assets/main.js`.

## Quick Reference

| Framework | Config File | Property | Value | Trailing Slash? |
|-----------|-------------|----------|-------|-----------------|
| **Next.js** | `next.config.js` | `basePath` + `assetPrefix` | `'/app-name'` | No |
| **Vite** | `vite.config.ts` | `base` | `'/app-name/'` | **Yes** |
| **Angular** | `angular.json` | `baseHref` + `deployUrl` | `'/app-name/'` | Yes |
| **Webpack** | `webpack.config.js` | `output.publicPath` | `'/app-name/'` | Yes |
| **CRA** | `.env.production` | `PUBLIC_URL` | `'/app-name'` | No |

## Framework Detection

Run this on the server to auto-detect your framework:

```bash
cd /home/ubuntu/deployments/your-app-name

if [ -f "next.config.js" ] || [ -f "next.config.mjs" ] || [ -f "next.config.ts" ]; then
    echo "Framework: Next.js"
elif [ -f "vite.config.ts" ] || [ -f "vite.config.js" ]; then
    echo "Framework: Vite"
elif [ -f "angular.json" ]; then
    echo "Framework: Angular"
elif [ -f "webpack.config.js" ]; then
    echo "Framework: Webpack"
else
    echo "Framework: Unknown - check package.json"
fi
```

## Configuration by Framework

### Next.js

**File:** `next.config.js` or `dashboard/next.config.js`

```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  output: 'standalone',
  basePath: '/your-app-name',      // No trailing slash
  assetPrefix: '/your-app-name',   // No trailing slash
  trailingSlash: true,
}

module.exports = nextConfig
```

**Environment variables:**
```bash
NEXT_PUBLIC_API_URL=https://your-server/your-app-name/api
```

**Why it works:**
- `basePath` tells Next.js where the app is hosted
- `assetPrefix` ensures `_next/` static files load from correct path
- Next.js does NOT use trailing slash in basePath

---

### Vite (React/Vue/Svelte)

**File:** `vite.config.ts`

```typescript
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  base: '/your-app-name/',  // Trailing slash REQUIRED
  plugins: [react()],
  // ... rest of config
})
```

**Automated update:**
```bash
# Add base path using sed
sed -i '/export default defineConfig({/a\  base: "/your-app-name/",' vite.config.ts
```

**Environment variables:**
```bash
VITE_API_URL=https://your-server/your-app-name/api
```

**Why it works:**
- `base` option tells Vite to prepend this path to all assets
- Vite **requires trailing slash** in base path (unlike Next.js)

**Common mistake:**
```typescript
// ❌ Wrong: Missing trailing slash
base: '/your-app-name'

// ✅ Correct: Has trailing slash
base: '/your-app-name/'
```

---

### Angular

**File:** `angular.json`

```json
{
  "projects": {
    "your-project": {
      "architect": {
        "build": {
          "options": {
            "baseHref": "/your-app-name/",
            "deployUrl": "/your-app-name/"
          }
        }
      }
    }
  }
}
```

**Or use CLI flags:**
```bash
ng build --base-href=/your-app-name/ --deploy-url=/your-app-name/
```

**Why it works:**
- `baseHref` sets the `<base href>` tag in index.html
- `deployUrl` sets the URL prefix for asset loading

---

### Webpack (Custom Builds)

**File:** `webpack.config.js`

```javascript
module.exports = {
  output: {
    path: path.resolve(__dirname, 'dist'),
    publicPath: '/your-app-name/',  // Trailing slash required
  },
  // ... rest of config
}
```

**Why it works:**
- `publicPath` prepends this path to all asset URLs in the bundle

---

### Create React App (CRA)

**File:** `.env.production`

```bash
PUBLIC_URL=/your-app-name
```

**Or build command:**
```bash
PUBLIC_URL=/your-app-name npm run build
```

**Why it works:**
- CRA reads `PUBLIC_URL` environment variable during build
- Sets `<base>` tag and asset paths automatically

---

## Critical Timing: Configure THEN Build

**⚠️ MUST configure BEFORE building Docker containers!**

### Wrong Order (causes blank page):
```bash
❌ 1. docker-compose build
❌ 2. Update vite.config.ts
❌ 3. docker-compose up
```
Result: Old config baked into image → blank page

### Correct Order:
```bash
✅ 1. rsync code to server
✅ 2. Update vite.config.ts (or next.config.js, etc.)
✅ 3. docker-compose build
✅ 4. docker-compose up
```
Result: New config baked into image → works correctly

## Real-World Example: Vite + React

This example demonstrates the fix that resolved the automated-speech-recognition blank page issue.

### Problem
Application deployed to `https://3.87.27.213/automated-speech-recognition/` showed blank page.

**Root cause:** `vite.config.ts` was missing `base` property.

**HTML generated:**
```html
<script src="/assets/index-Czgeb_QI.js"></script>
```

**Attempted to load:** `https://3.87.27.213/assets/index-Czgeb_QI.js` → **404 error**

### Solution

1. **Added base path to vite.config.ts:**
```typescript
export default defineConfig({
  base: '/automated-speech-recognition/',  // Added this line
  plugins: [react()],
  // ... rest
})
```

2. **Rebuilt Docker container:**
```bash
sg docker -c 'docker-compose build --no-cache'
sg docker -c 'docker-compose up -d'
```

3. **Result:**
```html
<script src="/automated-speech-recognition/assets/index-Czgeb_QI.js"></script>
```

**Now loads:** `https://3.87.27.213/automated-speech-recognition/assets/index-Czgeb_QI.js` → **200 OK ✅**

## Verification

### Before Fix (Broken)
```bash
# Check HTML output
curl -s https://your-server/your-app/ | grep "assets"
# Output: <script src="/assets/main.js">  ← Missing subpath!

# Check asset
curl -I https://your-server/assets/main.js
# Output: HTTP 404  ← Not found!
```

### After Fix (Working)
```bash
# Check HTML output
curl -s https://your-server/your-app/ | grep "assets"
# Output: <script src="/your-app/assets/main.js">  ← Correct path!

# Check asset
curl -I https://your-server/your-app/assets/main.js
# Output: HTTP 200  ← Found!
```

## Troubleshooting

### Blank Page After Deployment

**Symptom:** Page loads but shows blank white page

**Diagnosis:**
```bash
# 1. Check browser console (F12)
# Look for 404 errors like:
# GET https://server/assets/main.js 404 (Not Found)

# 2. Check HTML source
curl -s https://your-server/your-app/ | grep "script\|link"
# If you see /assets/ instead of /your-app/assets/, config is missing

# 3. Verify config file was updated
ssh user@server
cd /home/ubuntu/deployments/your-app
grep "base:" vite.config.ts  # For Vite
grep "basePath:" next.config.js  # For Next.js
```

**Fix:**
1. Update config file with correct base path
2. Rebuild container: `docker-compose build --no-cache`
3. Restart: `docker-compose up -d`

### Assets Still Load from Wrong Path

**Cause:** Docker image was built before config was updated

**Fix:**
```bash
# Force rebuild without cache
cd /home/ubuntu/deployments/your-app
sg docker -c 'docker-compose down'
sg docker -c 'docker-compose build --no-cache'
sg docker -c 'docker-compose up -d'
```

### Config Changes Not Taking Effect

**Cause:** Old environment variables in running container

**Fix:**
```bash
# Remove containers and volumes
sg docker -c 'docker-compose down -v'
sg docker -c 'docker-compose up -d --build'
```

## Integration with Deploy Portal

The deploy-portal repository includes these framework-agnostic instructions in the deployment kit's `CLAUDE_PROMPT.md` file (Step 5).

When generating a deployment kit:
1. Portal detects application structure
2. Includes framework-specific instructions
3. User configures BEFORE building Docker containers
4. Deployment works first try without blank pages

## Best Practices

1. **Always configure before building**
   - Update config files first
   - Then run `docker-compose build`

2. **Use framework detection**
   - Auto-detect framework type
   - Apply correct configuration syntax

3. **Verify configuration**
   - Check config file before building
   - Test asset paths after deployment

4. **Document your framework**
   - Note which config file to update
   - Include in project README

5. **Keep local configs clean**
   - Only modify server copies
   - Local configs should use localhost

## Related Documentation

- [Deploy Portal SSL Setup](SSL_SETUP.md)
- [Deploy Portal Architecture](ARCHITECTURE.md)
- [Vite config.base](https://vitejs.dev/config/shared-options.html#base)
- [Next.js basePath](https://nextjs.org/docs/api-reference/next.config.js/basepath)
- [Angular deployment](https://angular.io/guide/deployment#base-tag)

## Contributing

Found a framework not listed here? Submit a PR with:
1. Framework name and config file
2. Configuration syntax with example
3. Real-world test case

## Version History

- **2026-02-01**: Initial version with Next.js, Vite, Angular, Webpack, CRA
- **2026-02-01**: Added real-world Vite example (automated-speech-recognition fix)
