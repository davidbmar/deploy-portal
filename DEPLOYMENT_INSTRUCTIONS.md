# Deployment Instructions for 3.87.27.213

## Current Status

**Instance 3.87.27.213:**
- ❌ Serving wrong application ("Server Running" page)
- ❌ Deploy portal not accessible
- ✅ Security group configured (port 80 open)
- ✅ Network accessible (129ms response time)

## To Deploy Fixed Version

Someone with SSH access to 3.87.27.213 needs to:

### 1. SSH to the instance
```bash
ssh ubuntu@3.87.27.213
```

### 2. Navigate to deploy-portal directory
```bash
cd /home/ubuntu/src/deploy-portal
```

### 3. Pull latest changes
```bash
git stash  # Save any local changes
git pull origin main
git stash pop  # Restore local changes if any
```

### 4. Run bootstrap.sh
```bash
./bootstrap.sh
```

This will:
- ✅ Remove any conflicting nginx configurations
- ✅ Install deploy-portal-server.conf
- ✅ Set up health check endpoint
- ✅ Configure OAuth2 proxy endpoints
- ✅ Start deploy-portal service
- ✅ Run verification automatically

### 5. Verify deployment
```bash
# On the instance:
./scripts/verify-deployment-local.sh

# From this instance (16.148.110.90):
./scripts/remote-http-verify.sh 3.87.27.213
```

### 6. Expected results after deployment
```
✓ Health check endpoint accessible
✓ Service running correctly
✓ Nginx configured properly
✓ Deploy portal serving correct content
```

## Alternative: Manual Verification from 16.148.110.90

```bash
# Test if instance is accessible
./scripts/remote-http-verify.sh 3.87.27.213

# Should show after successful deployment:
✓ Root path (/) serving Capsule Cloud portal
✓ Deploy path (/deploy/) serving portal content
✓ API endpoint accessible
✓ Response time: ~130ms (excellent)
```

## What Changed in This Update

1. **Fixed bootstrap.sh**
   - Now correctly removes auth-gateway (handles regular files, not just symlinks)
   - Validates nginx configuration before proceeding
   - Checks for conflicts automatically

2. **Added nginx/server.conf**
   - Main server block for deploy-portal
   - Includes health check endpoint (no auth)
   - Configures OAuth2 proxy endpoints

3. **Added /health endpoint**
   - Returns JSON status without authentication
   - Perfect for monitoring and verification

4. **Complete verification system**
   - Content validation (not just HTTP 200 checks)
   - Security group validation
   - Clear error messages with troubleshooting steps

## Commit Details

```
commit 56a06e7
Author: Ubuntu
Date: Fri Jan 30 23:31:42 2026

Fix deployment and add comprehensive verification system

12 files changed, 2238 insertions(+), 29 deletions(-)
```
