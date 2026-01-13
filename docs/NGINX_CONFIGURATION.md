# Nginx Configuration for Capsule Cloud

## Overview

This document describes the nginx configuration for the Capsule Cloud gateway at `/etc/nginx/sites-available/auth-gateway`.

## Key Configuration Changes Made (2026-01-13)

### Issue Fixed
The root URL `/` was incorrectly routing to `ssh_terminal` instead of `deploy_portal`, causing the main page to show an SSH terminal instead of the application catalog.

### Changes Applied

1. **Added `deploy_portal` upstream:**
```nginx
upstream deploy_portal {
    server 127.0.0.1:5000;
}
```

2. **Fixed root location to proxy to deploy_portal:**
```nginx
location / {
    proxy_pass http://deploy_portal;  # Changed from ssh_terminal
    ...
}
```

3. **Added static files location (no auth required):**
```nginx
location /deploy/static/ {
    alias /home/ubuntu/src/deploy-portal/static/;
    expires 1h;
    add_header Cache-Control "public, immutable";
}
```

4. **Added deploy portal routes location:**
```nginx
location /deploy/ {
    auth_request /oauth2/auth;
    ...
    proxy_pass http://deploy_portal;
}
```

## Current Upstreams

```nginx
upstream oauth2_proxy {
    server 127.0.0.1:4180;
}

upstream deploy_portal {
    server 127.0.0.1:5000;  # Flask app - Deploy Portal
}

upstream ssh_terminal {
    server 127.0.0.1:8080;
}

upstream website_cloner {
    server 127.0.0.1:3000;
}

# Application-specific upstreams
upstream my_app_01_test_backend {
    server 127.0.0.1:3001;  # Next.js frontend for deployed app
}
```

## Location Block Order (Critical)

Nginx matches locations in a specific order. More specific paths must come BEFORE general paths:

1. `/deploy/static/` (no auth) - **MUST come before /deploy/**
2. `/deploy/` (authenticated)
3. `/my-app-01-test/api/` (API routes) - **MUST come before /my-app-01-test/**
4. `/my-app-01-test/` (frontend)
5. `/` (root - deploy portal)

## Configuration Management

### Backup Before Changes

```bash
sudo cp /etc/nginx/sites-available/auth-gateway \
       /etc/nginx/sites-available/auth-gateway.backup-$(date +%s)
```

### Test Configuration

```bash
sudo nginx -t
```

### Apply Changes

```bash
sudo systemctl reload nginx
```

### View Active Configuration

```bash
sudo cat /etc/nginx/sites-available/auth-gateway
```

## Adding New Applications

When deploying a new application like `my-app-01-test`, add these blocks:

### 1. Upstream Definition (at end of file)

```nginx
upstream app_name_backend {
    server 127.0.0.1:PORT;
}
```

### 2. API Location (if applicable)

**Important:** Add BEFORE the frontend location!

```nginx
location /app-name/api/ {
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

    auth_request_set $user $upstream_http_x_auth_request_user;
    auth_request_set $email $upstream_http_x_auth_request_email;

    # Rewrite to remove app prefix
    rewrite ^/app-name/api/(.*)$ /api/$1 break;

    # Proxy to backend
    proxy_pass http://127.0.0.1:BACKEND_PORT;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-User-Email $email;
    proxy_set_header X-Auth-Request-User $user;

    # CORS headers
    add_header Access-Control-Allow-Origin $http_origin always;
    add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Authorization, Content-Type, X-API-Key" always;
    add_header Access-Control-Allow-Credentials true always;

    if ($request_method = OPTIONS) {
        return 204;
    }
}
```

### 3. Frontend Location

```nginx
location /app-name/ {
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

    auth_request_set $user $upstream_http_x_auth_request_user;
    auth_request_set $email $upstream_http_x_auth_request_email;
    auth_request_set $auth_cookie $upstream_http_set_cookie;
    add_header Set-Cookie $auth_cookie;

    proxy_pass http://app_name_backend;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-User-Email $email;
    proxy_set_header X-Auth-Request-User $user;

    # WebSocket and SSE support
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 86400;
    proxy_buffering off;
    proxy_cache off;
}
```

### 4. Redirect Block

```nginx
location = /app-name {
    return 301 /app-name/;
}
```

## Removing Applications

**See:** `docs/DELETE_FUNCTION_ISSUES.md` for comprehensive cleanup procedure.

### Quick Removal

```bash
APP_NAME="my-app-name"

# Backup first
sudo cp /etc/nginx/sites-available/auth-gateway \
       /etc/nginx/sites-available/auth-gateway.backup-before-delete-$(date +%s)

# Remove upstream
sudo sed -i "/upstream ${APP_NAME}/,/^}/d" /etc/nginx/sites-available/auth-gateway

# Remove all location blocks for this app
sudo sed -i "/location.*${APP_NAME}/,/^    }/d" /etc/nginx/sites-available/auth-gateway

# Test and reload
if sudo nginx -t; then
    sudo systemctl reload nginx
    echo "✅ Nginx reloaded successfully"
else
    echo "❌ Nginx config has errors, restoring backup"
    sudo cp /etc/nginx/sites-available/auth-gateway.backup-before-delete-* \
           /etc/nginx/sites-available/auth-gateway
fi
```

## Troubleshooting

### Issue: Duplicate Location Blocks

**Symptoms:**
```
nginx: [emerg] duplicate location "/app-name" in /etc/nginx/sites-enabled/auth-gateway:293
nginx: configuration file /etc/nginx/nginx.conf test failed
```

**Cause:** Multiple deployment attempts added duplicate configuration blocks.

**Solution:**
```bash
# Restore from clean backup
sudo cp /etc/nginx/sites-available/auth-gateway.backup-pre-deploy \
       /etc/nginx/sites-available/auth-gateway

# Re-add only the necessary configurations
# (Use the procedures in this document)

# Test and reload
sudo nginx -t && sudo systemctl reload nginx
```

### Issue: Static Files Not Loading (CSS/JS)

**Symptoms:**
- CSS returns 404 or 302 redirect
- Page displays as plain text (1990s style)

**Cause:**
- Static files location block missing
- Static files location has auth requirement
- Static files location comes AFTER authenticated location

**Solution:**
```nginx
# Ensure this location comes BEFORE /deploy/
location /deploy/static/ {
    alias /home/ubuntu/src/deploy-portal/static/;
    expires 1h;
    add_header Cache-Control "public, immutable";
}
```

### Issue: "Cannot connect to backend" in Frontend

**Symptoms:** Frontend loads but shows "System Offline" or cannot connect to backend.

**Cause:**
- API location block missing
- API location block comes AFTER frontend location (wrong order)
- Backend not running
- Wrong backend port in nginx

**Solution:**
1. Verify API location block exists and comes BEFORE frontend location
2. Check backend is running: `docker ps` or `curl http://localhost:BACKEND_PORT/`
3. Verify nginx proxy_pass points to correct port

### Issue: WebSocket Connection Fails

**Symptoms:** Real-time features don't work, WebSocket upgrade fails

**Cause:** Missing WebSocket headers

**Solution:** Add to location block:
```nginx
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_read_timeout 86400;
proxy_buffering off;
proxy_cache off;
```

### Issue: Main Page Shows SSH Terminal

**Symptoms:** Visiting `https://52.43.35.1/` shows SSH terminal instead of app catalog

**Cause:** Root location (`/`) proxying to wrong upstream

**Solution:**
```bash
# Fix root location to point to deploy_portal
sudo sed -i 's/proxy_pass http:\/\/ssh_terminal;/proxy_pass http:\/\/deploy_portal;/' \
    /etc/nginx/sites-available/auth-gateway

# Test and reload
sudo nginx -t && sudo systemctl reload nginx
```

## Checking Current Configuration

### List All Location Blocks

```bash
sudo grep 'location /' /etc/nginx/sites-available/auth-gateway | grep -v '#'
```

### Check Upstreams

```bash
sudo grep -E '^upstream' /etc/nginx/sites-available/auth-gateway
```

### Find App-Specific Configuration

```bash
APP_NAME="my-app-name"
sudo grep -n "$APP_NAME" /etc/nginx/sites-available/auth-gateway
```

### View Full Configuration

```bash
sudo cat /etc/nginx/sites-available/auth-gateway
```

## Testing After Changes

### Test Nginx Configuration

```bash
sudo nginx -t
```

### Test Local Endpoints

```bash
# Deploy portal root
curl -I http://localhost:5000/

# Static files
curl -I http://localhost/deploy/static/style.css

# Application frontend
curl -I http://localhost:3001/my-app-01-test/

# Application backend
curl -I http://localhost:8001/api/
```

### Test Public HTTPS Endpoints

```bash
# Main page (will redirect to auth)
curl -k -I https://52.43.35.1/

# Static files (should work without auth)
curl -k -I https://52.43.35.1/deploy/static/style.css

# Application (will redirect to auth)
curl -k -I https://52.43.35.1/my-app-01-test/
```

## Best Practices

1. **Always backup before changes:**
   ```bash
   sudo cp /etc/nginx/sites-available/auth-gateway \
          /etc/nginx/sites-available/auth-gateway.backup-$(date +%s)
   ```

2. **Always test before reloading:**
   ```bash
   sudo nginx -t && sudo systemctl reload nginx
   ```

3. **Keep a clean pre-deployment backup:**
   ```bash
   sudo cp /etc/nginx/sites-available/auth-gateway \
          /etc/nginx/sites-available/auth-gateway.backup-pre-deploy
   ```

4. **Order matters:** More specific paths must come before general paths

5. **Static files should not require authentication** (place before authenticated locations)

6. **API routes must come before frontend routes** for the same app

## Related Documentation

- [DELETE_FUNCTION_ISSUES.md](DELETE_FUNCTION_ISSUES.md) - Comprehensive cleanup and delete function design
- [DEPLOYMENT_STATUS.md](../DEPLOYMENT_STATUS.md) - Current deployment status
- [README.md](../README.md) - Main project documentation

## Nginx Configuration File Location

**File:** `/etc/nginx/sites-available/auth-gateway`

**Symlink:** `/etc/nginx/sites-enabled/auth-gateway` → `/etc/nginx/sites-available/auth-gateway`

**Backups:** `/etc/nginx/sites-available/auth-gateway.backup-*`

---

**Last Updated:** 2026-01-13
**Maintained By:** Capsule Cloud Team
