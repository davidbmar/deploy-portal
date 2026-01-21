# EC2 Deployment Infrastructure

## Overview

This directory contains shared automation tools for deploying vibe-coded apps to EC2 using a modular nginx configuration pattern.

**Key Features:**
- ✅ Modular nginx configs in `/etc/nginx/conf.d/routes/`
- ✅ Automatic OAuth2 authentication via auth-gateway
- ✅ Deployment verification tool (`check-app.sh`)
- ✅ Support for multi-service apps (frontend + backend)
- ✅ WebSocket and SSE support built-in

## Infrastructure Architecture

```
/home/ubuntu/
├── deployments/
│   ├── .automation/           # Symlink to this directory
│   ├── {app-name}/            # Individual app deployments
│   │   ├── docker-compose.yml
│   │   ├── .env
│   │   └── ...
│   └── .backups/              # Nginx config backups
│
├── src/
│   └── deploy-portal/
│       └── automation/        # This directory (version controlled)
│           ├── scripts/
│           ├── templates/
│           └── README.md (this file)
│
/etc/nginx/
├── nginx.conf                 # Includes conf.d/*.conf
├── sites-available/
│   └── auth-gateway           # Main auth gateway (includes routes)
├── conf.d/
│   ├── routes/                # App route configs (modular)
│   │   ├── app-1.conf
│   │   ├── app-2.conf
│   │   └── pydantic-ai-agent-evaluator-01.conf
│   └── system-upstreams/      # Upstream definitions
```

### How Nginx Works

1. **Main Config** (`/etc/nginx/nginx.conf`) includes `/etc/nginx/conf.d/*.conf`
2. **Auth Gateway** (`/etc/nginx/sites-available/auth-gateway`) is the main server block
3. **Auth Gateway** includes all routes from `/etc/nginx/conf.d/routes/*.conf`
4. **Each app** has its own config file in `conf.d/routes/{app-name}.conf`
5. **OAuth2 Proxy** handles authentication at `/oauth2/` before routing to apps

## Quick Start - Deploying a New App

### 1. Copy App to Server

```bash
# From local machine
rsync -avz --exclude 'node_modules' --exclude '.git' \
  -e "ssh -i /path/to/key.pem" \
  ./your-app ubuntu@16.148.110.90:/home/ubuntu/deployments/your-app/
```

### 2. Configure App

```bash
# SSH to server
ssh -i key.pem ubuntu@16.148.110.90

# Navigate to app directory
cd /home/ubuntu/deployments/your-app

# For Next.js apps: Configure basePath in next.config.js
# Example:
# module.exports = {
#   basePath: '/your-app',
#   assetPrefix: '/your-app',
#   ...
# }

# Configure .env with production settings
# Example:
# NEXT_PUBLIC_API_URL=https://16.148.110.90/your-app/api
# GOOGLE_REDIRECT_URI=https://16.148.110.90/your-app/auth/google/callback

# Build and start containers
sg docker -c 'docker-compose build'
sg docker -c 'docker-compose up -d'
```

### 3. Create Nginx Configuration

**Option A: Manual (Modular Pattern - Recommended)**

Create `/etc/nginx/conf.d/routes/your-app.conf`:

```nginx
# Static assets (no auth)
location /your-app/_next/static/ {
    proxy_pass http://127.0.0.1:PORT/_next/static/;
    proxy_http_version 1.1;
    proxy_cache_valid 200 60m;
    add_header Cache-Control "public, max-age=3600, immutable";
}

# Protected: Frontend
location /your-app/ {
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;
    
    auth_request_set $user $upstream_http_x_auth_request_user;
    auth_request_set $email $upstream_http_x_auth_request_email;
    auth_request_set $auth_cookie $upstream_http_set_cookie;
    add_header Set-Cookie $auth_cookie;
    
    proxy_pass http://127.0.0.1:PORT/your-app/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-User-Email $email;
    proxy_set_header X-Auth-Request-User $user;
    
    # WebSocket/SSE support
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 86400;
    proxy_buffering off;
    proxy_cache off;
}

# Redirect without trailing slash
location = /your-app {
    return 301 /your-app/;
}

# API endpoint (if multi-service)
location /your-app/api/ {
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;
    
    auth_request_set $user $upstream_http_x_auth_request_user;
    auth_request_set $email $upstream_http_x_auth_request_email;
    
    rewrite ^/your-app/api/(.*)$ /api/$1 break;
    proxy_pass http://127.0.0.1:BACKEND_PORT;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-User-Email $email;
    proxy_set_header X-Auth-Request-User $user;
    
    # WebSocket/SSE support
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 86400;
    proxy_buffering off;
    proxy_cache off;
}
```

Then reload nginx:
```bash
sudo nginx -t && sudo systemctl reload nginx
```

**Option B: Using Automation Script (Legacy - Modifies auth-gateway directly)**

> **Note:** The nginx-register.sh script currently modifies the auth-gateway file directly
> instead of creating modular configs. Consider using Option A for consistency with
> current infrastructure patterns.

```bash
# For multi-service apps (frontend + backend)
/home/ubuntu/deployments/.automation/nginx-register.sh add-multiservice your-app 3000 8000

# For single-service apps
/home/ubuntu/deployments/.automation/nginx-register.sh add your-app 3000

# Reload nginx
sudo systemctl reload nginx
```

### 4. Verify Deployment

```bash
/home/ubuntu/deployments/.automation/check-app.sh your-app
```

**Expected output:**
```
=== Deployment Verification for: your-app ===

1. App Directory:           ✅
2. Docker Containers:       ✅
3. Nginx Configuration:     ✅ (modular)
4. Nginx Syntax:            ✅
5. Config Loaded in Nginx:  ✅
6. Endpoint Test:           ✅ (HTTP 302)
7. Recent Container Errors: ✅
```

### 5. Test in Browser

Open: `https://16.148.110.90/your-app/`

You should be redirected to Cognito OAuth, then to your app after authentication.

## Available Tools

### check-app.sh

Verifies deployment health and diagnoses issues.

**Usage:**
```bash
/home/ubuntu/deployments/.automation/check-app.sh APP_NAME
```

**Checks:**
- ✅ App directory exists
- ✅ Docker containers running
- ✅ Nginx configuration exists (modular or legacy)
- ✅ Nginx syntax valid
- ✅ Config loaded in nginx
- ✅ Endpoint accessible
- ✅ No errors in logs

### nginx-register.sh (Legacy)

> **Note:** This script modifies auth-gateway directly. For new deployments, consider
> creating modular configs manually in `/etc/nginx/conf.d/routes/` instead.

**Usage:**
```bash
# Single service
./nginx-register.sh add APP_NAME PORT

# Multi-service (frontend + backend)
./nginx-register.sh add-multiservice APP_NAME FRONTEND_PORT BACKEND_PORT

# Remove app
./nginx-register.sh remove APP_NAME

# Test nginx config
./nginx-register.sh test

# Reload nginx
./nginx-register.sh reload
```

## Troubleshooting

### App Returns 404

**Symptoms:** Accessing `https://16.148.110.90/your-app/` returns 404 Not Found

**Diagnosis:**
```bash
# Run verification
/home/ubuntu/deployments/.automation/check-app.sh your-app

# Check if config exists
ls -la /etc/nginx/conf.d/routes/your-app.conf

# Check if config is loaded
sudo nginx -T | grep "location /your-app/"

# Check auth-gateway includes routes
sudo cat /etc/nginx/sites-available/auth-gateway | grep "include.*routes"
```

**Solutions:**
1. Ensure config exists in `/etc/nginx/conf.d/routes/your-app.conf`
2. Check auth-gateway includes: `include /etc/nginx/conf.d/routes/*.conf;`
3. Test nginx: `sudo nginx -t`
4. Reload nginx: `sudo systemctl reload nginx`

### CSS/JS Not Loading (MIME Type Errors)

**Symptoms:** Page loads but no styling, console shows MIME type errors

**Diagnosis:**
```bash
# Check if static assets location exists
sudo cat /etc/nginx/conf.d/routes/your-app.conf | grep "_next/static"

# Test static asset URL
curl -I https://16.148.110.90/your-app/_next/static/...
```

**Solutions:**
1. Ensure static assets location block exists (see template above)
2. Verify app is configured with correct basePath in next.config.js
3. Check Next.js is serving assets at `/_next/static/` not `/your-app/_next/static/`

### OAuth Redirect Fails

**Symptoms:** OAuth redirects to wrong URL or fails to return to app

**Diagnosis:**
```bash
# Check app's .env file
cat /home/ubuntu/deployments/your-app/.env | grep REDIRECT

# Check if redirect URL includes app path
# Should be: https://16.148.110.90/your-app/auth/google/callback
```

**Solutions:**
1. Update `GOOGLE_REDIRECT_URI` in app's `.env`
2. Rebuild and restart containers: `sg docker -c 'docker-compose up -d --force-recreate'`
3. Verify redirect URL in Google Cloud Console matches

### API Requests Fail (CORS, 502, 504)

**Symptoms:** Frontend loads but API calls fail

**Diagnosis:**
```bash
# Check backend container logs
sg docker -c 'docker logs your-app-backend'

# Test API endpoint directly
curl -k https://16.148.110.90/your-app/api/health

# Check API location block
sudo cat /etc/nginx/conf.d/routes/your-app.conf | grep -A 20 "location /your-app/api/"
```

**Solutions:**
1. Ensure backend container is running: `sg docker -c 'docker ps | grep your-app'`
2. Check API rewrite rule: `rewrite ^/your-app/api/(.*)$ /api/$1 break;`
3. Verify backend port in nginx config matches docker-compose
4. Check backend logs for errors
5. Increase proxy timeouts if slow API

### Config Not Loaded After Changes

**Symptoms:** Made changes to nginx config but app behavior unchanged

**Diagnosis:**
```bash
# Test nginx config
sudo nginx -t

# Check if config is actually loaded
sudo nginx -T | grep -c "location /your-app/"

# Check nginx error log
sudo tail -f /var/log/nginx/error.log
```

**Solutions:**
1. Always test before reload: `sudo nginx -t`
2. Reload nginx after changes: `sudo systemctl reload nginx`
3. If syntax errors, check backup: `ls -lt /home/ubuntu/deployments/.backups/`
4. Restore backup if needed: `sudo cp backup.conf /etc/nginx/...`

## Common Patterns

### Next.js App with Backend API

**docker-compose.yml:**
```yaml
services:
  frontend:
    container_name: your-app-frontend
    ports:
      - "3000:3000"
    environment:
      - NEXT_PUBLIC_API_URL=https://16.148.110.90/your-app/api
  
  backend:
    container_name: your-app-backend
    ports:
      - "8000:8000"
```

**next.config.js:**
```javascript
module.exports = {
  basePath: '/your-app',
  assetPrefix: '/your-app',
  trailingSlash: true,
}
```

**Nginx config:**
- Frontend: `proxy_pass http://127.0.0.1:3000/your-app/;`
- Backend API: `proxy_pass http://127.0.0.1:8000;` with rewrite
- Static assets: `proxy_pass http://127.0.0.1:3000/_next/static/;`

### Single-Page Frontend Only

**docker-compose.yml:**
```yaml
services:
  frontend:
    container_name: your-app-frontend
    ports:
      - "3000:3000"
```

**Nginx config:**
- Frontend: `proxy_pass http://127.0.0.1:3000/your-app/;`
- Static assets: `proxy_pass http://127.0.0.1:3000/_next/static/;`
- No API location block needed

## Maintenance

### View All Deployed Apps

```bash
ls -d /home/ubuntu/deployments/*/ | grep -v ".automation\|.backups"
```

### View All Nginx Configs

```bash
# Modular configs
ls -la /etc/nginx/conf.d/routes/

# View specific config
sudo cat /etc/nginx/conf.d/routes/your-app.conf
```

### Backup Nginx Config Before Changes

```bash
sudo cp /etc/nginx/sites-available/auth-gateway \
  /home/ubuntu/deployments/.backups/auth-gateway-$(date +%Y%m%d-%H%M%S).conf
```

### Update Automation Scripts

```bash
# Pull latest changes from deploy-portal repo
cd /home/ubuntu/src/deploy-portal
git pull origin main

# Scripts are automatically available via symlink
ls -la /home/ubuntu/deployments/.automation/
```

## Infrastructure Initialization (For New Servers)

If setting up a new EC2 server from scratch:

```bash
# 1. Clone deploy-portal repo
cd /home/ubuntu/src
git clone <deploy-portal-repo-url>

# 2. Create deployments directory
mkdir -p /home/ubuntu/deployments

# 3. Create symlink to automation scripts
ln -sf /home/ubuntu/src/deploy-portal/automation /home/ubuntu/deployments/.automation

# 4. Create backups directory
mkdir -p /home/ubuntu/deployments/.backups

# 5. Make scripts executable
chmod +x /home/ubuntu/src/deploy-portal/automation/*.sh
chmod +x /home/ubuntu/src/deploy-portal/tests/*.sh

# 6. Verify infrastructure
ls -la /home/ubuntu/deployments/.automation/
```

## Infrastructure Improvements Needed

### TODO: Update nginx-register.sh

The current `nginx-register.sh` script modifies the auth-gateway file directly, but the
infrastructure now uses a modular pattern with separate files in `conf.d/routes/`.

**Improvement needed:**
- Modify `nginx-register.sh` to create files in `/etc/nginx/conf.d/routes/` instead
- This would allow automated config generation with the modular pattern
- Benefits: Version control, easier rollback, cleaner separation

## Quick Reference

```bash
# Deploy app nginx config (modular pattern)
sudo tee /etc/nginx/conf.d/routes/APP.conf << EOF
<paste config from template>
EOF
sudo nginx -t && sudo systemctl reload nginx

# Verify deployment
/home/ubuntu/deployments/.automation/check-app.sh APP

# Check all deployed apps
ls -d /home/ubuntu/deployments/*/

# View app nginx config
sudo cat /etc/nginx/conf.d/routes/APP.conf

# View auth-gateway main config
sudo cat /etc/nginx/sites-available/auth-gateway

# Test nginx config
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx

# View container logs
sg docker -c 'docker logs APP-frontend'
sg docker -c 'docker logs APP-backend'

# Restart containers
cd /home/ubuntu/deployments/APP
sg docker -c 'docker-compose restart'

# View OAuth2 proxy logs
sudo journalctl -u oauth2-proxy -f
```

## Support

For issues or improvements:
1. Check troubleshooting guide above
2. Run `check-app.sh` for diagnostics
3. Check container logs
4. Check nginx error logs: `sudo tail -f /var/log/nginx/error.log`

---

**Last Updated:** 2026-01-21  
**Infrastructure Version:** Modular (conf.d/routes pattern)  
**Verified Working:** pydantic-ai-agent-evaluator-01
