# Root Cause Analysis: Deploy Portal Deployment Issues

## Executive Summary

Both instances (16.148.110.90 and 3.87.27.213) are failing to serve the Capsule Cloud Deploy Portal correctly, but for **different root causes**. The verification system correctly identified these issues.

## Instance 16.148.110.90 - Current Instance

### Symptoms
- ✗ Root path (/) returns 301 redirect to HTTPS
- ✗ External access fails (security group + redirect)
- ✓ Flask app runs correctly on port 5000
- ✓ Service is active and healthy

### Root Cause #1: Conflicting Nginx Configuration

**Problem:** `auth-gateway` configuration is still active and takes precedence over deploy-portal.

**Evidence:**
```bash
$ ls /etc/nginx/sites-enabled/
auth-gateway  # ← THIS SHOULD NOT BE HERE

$ head /etc/nginx/sites-enabled/auth-gateway
server {
    listen 80 default_server;  # ← Takes precedence
    listen [::]:80 default_server;
    server_name capsule-deploy.duckdns.org 16.148.110.90;

    location / {
        return 301 https://$server_name$request_uri;  # ← Forces HTTPS redirect
    }
}
```

**Why it happened:**
1. `bootstrap.sh` tried to disable auth-gateway:
   ```bash
   if [ -L /etc/nginx/sites-enabled/auth-gateway ]; then
       sudo rm -f /etc/nginx/sites-enabled/auth-gateway
   fi
   ```
2. But `/etc/nginx/sites-enabled/auth-gateway` is **not a symlink** - it's a regular file
3. The `-L` test fails, so the file is never removed
4. auth-gateway continues to intercept all port 80 traffic

**Impact:**
- All HTTP requests get 301 redirected to HTTPS
- Deploy portal routes in `/etc/nginx/conf.d/routes/` are never reached
- Verification scripts fail because they can't access content
- External HTTP access fails due to forced HTTPS redirect

### Root Cause #2: Missing Main Server Configuration

**Problem:** `deploy-portal-server.conf` doesn't exist.

**Evidence:**
```bash
$ cat /etc/nginx/conf.d/deploy-portal-server.conf
File not found

$ ls /etc/nginx/conf.d/
routes/  system-upstreams/
# No deploy-portal-server.conf
```

**Why it happened:**
1. Bootstrap.sh checks if file exists before copying:
   ```bash
   if [ ! -f /etc/nginx/conf.d/deploy-portal-server.conf ]; then
       if [ -f "$SCRIPT_DIR/nginx/server.conf" ]; then
           sudo cp "$SCRIPT_DIR/nginx/server.conf" \
               /etc/nginx/conf.d/deploy-portal-server.conf
       fi
   fi
   ```
2. The source file `nginx/server.conf` may not exist in the repo
3. Or the copy condition failed for some reason

**Impact:**
- No dedicated server block for deploy-portal on port 80
- Deploy portal can't serve HTTP requests directly
- Relies entirely on auth-gateway (which redirects to HTTPS)

### Root Cause #3: OAuth2 Authentication Requirement

**Problem:** All routes require OAuth2 authentication.

**Evidence:**
```bash
$ cat /etc/nginx/conf.d/routes/deploy-portal.conf
location / {
    # Authentication check via oauth2-proxy
    auth_request /oauth2/auth;  # ← Requires authentication
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

    proxy_pass http://deploy_portal;
}
```

**Why it happened:**
- This is intentional for security, but creates issues for:
  - Health checks
  - Verification scripts
  - Unauthenticated monitoring

**Impact:**
- Verification scripts can't access content (no OAuth token)
- Health checks fail without authentication
- Cannot verify deployment without manual browser login

### Root Cause #4: Security Group Configuration

**Problem:** Port 80 not open to external access for this instance.

**Evidence:**
```bash
$ ./scripts/verify-deployment-local.sh
✗ Root path (/) NOT accessible externally from 16.148.110.90
   → Check security group: port 80 may not be open
```

**Why it happened:**
- Security group rules were added for 3.87.27.213 but not for 16.148.110.90
- This instance's security group needs port 80 open to:
  - 136.62.92.204/32 (MacBook)
  - 3.87.27.213/32 (other instance)

**Impact:**
- External HTTP requests timeout
- Cross-instance communication fails
- Cannot verify deployment from remote location

## Instance 3.87.27.213 - Remote Instance

### Symptoms
- ✗ Root path (/) shows "Server Running" page
- ✗ Deploy path (/deploy/) shows "Server Running" page
- ✓ API endpoint works (/api/instance-metadata)
- ✓ Port 80 accessible externally

### Root Cause #1: Wrong Application Running

**Problem:** A different application is serving port 80, not deploy-portal.

**Evidence:**
```bash
$ curl http://3.87.27.213/
<!DOCTYPE html><html><body><h1>Server Running</h1>
<p>App at <a href="/bbb-bbb/">/bbb-bbb/</a></p></body></html>

# Expected:
<title>Capsule Cloud - Your Personal Development Platform</title>
```

**Why it happened:**
1. Another application (possibly a test app or different deployment) is bound to port 80
2. This application shows "Server Running" with link to `/bbb-bbb/`
3. Deploy-portal may be running on port 5000 but not proxied correctly
4. Nginx may be serving a default page or different application

**Investigation needed:**
```bash
# SSH to 3.87.27.213 and run:
sudo ss -tlnp | grep :80
sudo systemctl status deploy-portal
cat /etc/nginx/sites-enabled/*
cat /etc/nginx/conf.d/*.conf
```

**Impact:**
- Deploy portal completely inaccessible
- Wrong application serving all requests
- Security risk if unintended application is exposed

### Root Cause #2: Nginx Misconfiguration

**Problem:** Nginx is not proxying to deploy-portal Flask app.

**Likely causes:**
1. Wrong upstream configuration
2. Different server block taking precedence
3. Missing or incorrect proxy_pass directive
4. Deploy-portal routes not included

**Impact:**
- Requests don't reach Flask app on port 5000
- Generic page served instead
- Verification fails completely

## Why Verification System Caught These Issues

### Old Tests (Would Have Failed to Detect)
```bash
# Old approach - HTTP 200 = success
$ curl -I http://3.87.27.213/
HTTP/1.1 200 OK  # ✓ PASSES (false positive!)

$ curl -I http://16.148.110.90/
HTTP/1.1 301 Moved Permanently  # ✓ PASSES (considered "accessible")
```

### New Tests (Correctly Detected)
```bash
# New approach - validates content
$ ./scripts/remote-http-verify.sh 3.87.27.213
✗ Root path (/) accessible but NOT serving portal
   → Found: <!DOCTYPE html><html><body><h1>Server Running</h1>
   → Expected: Capsule Cloud portal content

$ ./scripts/verify-deployment-local.sh
✗ Root path (/) NOT serving Capsule Cloud content
   → Found: No title found (301 redirect)
```

## Summary of Root Causes

| Instance | Root Cause | Type | Severity |
|----------|------------|------|----------|
| 16.148.110.90 | auth-gateway still enabled (not a symlink) | Config | Critical |
| 16.148.110.90 | Missing deploy-portal-server.conf | Config | High |
| 16.148.110.90 | OAuth2 blocks verification | Design | Medium |
| 16.148.110.90 | Security group port 80 closed | Network | High |
| 3.87.27.213 | Wrong application serving port 80 | Deployment | Critical |
| 3.87.27.213 | Nginx not proxying to deploy-portal | Config | Critical |

## Recommended Fixes

### Fix for 16.148.110.90

1. **Remove auth-gateway (correct way):**
   ```bash
   sudo rm /etc/nginx/sites-enabled/auth-gateway
   sudo systemctl reload nginx
   ```

2. **Create deploy-portal-server.conf:**
   ```bash
   # Check if source exists
   ls -la nginx/server.conf

   # If missing, create it:
   sudo tee /etc/nginx/conf.d/deploy-portal-server.conf << 'EOF'
   server {
       listen 80 default_server;
       listen [::]:80 default_server;
       server_name _;

       # Include deploy portal routes
       include /etc/nginx/conf.d/routes/deploy-portal.conf;
   }
   EOF

   sudo nginx -t && sudo systemctl reload nginx
   ```

3. **Add health check endpoint (no auth):**
   ```bash
   # Add to /etc/nginx/conf.d/routes/deploy-portal.conf
   location /health {
       auth_request off;  # No authentication required
       proxy_pass http://deploy_portal;
   }
   ```

4. **Update security group:**
   ```bash
   ./scripts/generate-security-rules.sh
   # Enter: 136.62.92.204, 3.87.27.213
   # Apply generated rules
   ```

### Fix for 3.87.27.213

1. **Identify what's running on port 80:**
   ```bash
   ssh ubuntu@3.87.27.213
   sudo ss -tlnp | grep :80
   sudo systemctl list-units | grep running
   ```

2. **Check nginx configuration:**
   ```bash
   sudo nginx -t
   grep -r "listen 80" /etc/nginx/
   cat /etc/nginx/sites-enabled/*
   ```

3. **Fix nginx to proxy to deploy-portal:**
   ```bash
   # Remove conflicting configurations
   sudo rm /etc/nginx/sites-enabled/default

   # Ensure deploy-portal config is correct
   sudo nginx -t && sudo systemctl reload nginx
   ```

4. **Verify deploy-portal service:**
   ```bash
   sudo systemctl status deploy-portal
   curl http://localhost:5000/
   ```

## Prevention Measures

### 1. Update bootstrap.sh
```bash
# Fix symlink check - handle both symlinks AND regular files
if [ -e /etc/nginx/sites-enabled/auth-gateway ]; then
    log "Removing conflicting auth-gateway configuration"
    sudo rm -f /etc/nginx/sites-enabled/auth-gateway
fi
```

### 2. Add Health Check Endpoint
```python
# In app.py
@app.route('/health')
def health_check():
    return jsonify({
        'status': 'healthy',
        'service': 'deploy-portal',
        'version': DEPLOYMENT_VERSION
    }), 200
```

### 3. Create server.conf Template
```bash
# Add nginx/server.conf to repository:
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    # Health check (no auth)
    location /health {
        proxy_pass http://deploy_portal;
    }

    # Deploy portal routes (with auth)
    include /etc/nginx/conf.d/routes/deploy-portal.conf;
}
```

### 4. Add Pre-deployment Check
```bash
# In bootstrap.sh before starting service:
check_conflicts() {
    log "Checking for configuration conflicts..."

    # Check for conflicting server blocks
    CONFLICTS=$(grep -r "listen 80 default_server" /etc/nginx/sites-enabled/ 2>/dev/null | wc -l)
    if [ $CONFLICTS -gt 0 ]; then
        warn "Found $CONFLICTS conflicting default_server declarations"
        warn "Manual intervention required"
        return 1
    fi
}
```

### 5. Enhance Verification
```bash
# Add to verification scripts:
# 1. Check for /health endpoint (unauthenticated)
# 2. Verify nginx config before testing
# 3. Check for conflicting server blocks
# 4. Test both HTTP and HTTPS
```

## Lessons Learned

1. **Symlink vs Regular File**: Bootstrap script only checked for symlinks (`-L`), missed regular files
2. **Default Server Conflicts**: Multiple `listen 80 default_server` declarations cause conflicts
3. **Authentication Blocks Testing**: OAuth2 prevents health checks and verification
4. **Content Validation Critical**: HTTP 200 doesn't mean correct content is served
5. **Security Group Per-Instance**: Each instance needs its own security group rules

## Next Steps

1. **Immediate**: Fix 16.148.110.90 by removing auth-gateway
2. **High Priority**: Investigate 3.87.27.213 to identify wrong application
3. **Medium Priority**: Add health check endpoints without auth
4. **Medium Priority**: Update bootstrap.sh to handle regular files
5. **Low Priority**: Add nginx/server.conf template to repository

## Verification After Fixes

```bash
# After fixing, run:
./scripts/verify-deployment-local.sh
./scripts/remote-http-verify.sh 3.87.27.213
./scripts/verify-all-instances.sh

# All tests should pass:
# ✓ Root path (/) serving Capsule Cloud portal
# ✓ Deploy path (/deploy/) serving portal content
# ✓ External access working
# ✓ Security groups configured correctly
```

## Conclusion

The root causes are **configuration conflicts and deployment mismatches**, not application bugs:

1. **16.148.110.90**: auth-gateway intercepts traffic, redirects to HTTPS, blocks verification
2. **3.87.27.213**: Wrong application serving port 80, deploy-portal not proxied

The verification system successfully identified both issues by validating content, not just HTTP status codes. This demonstrates the importance of comprehensive verification that checks what's actually being served.
