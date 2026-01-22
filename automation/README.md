# Generic Deployment Tools

## Status: Production Ready ✅

**Tested and verified working** for both authenticated (Cognito) and non-authenticated apps.

**Key Fix Applied (2026-01-22)**: Templates no longer include `upstream` blocks which were invalid in server context (route files are included inside server block). All proxy_pass directives now use direct `http://127.0.0.1:PORT` syntax.

## Overview

This directory contains generic deployment automation tools that work for **any app** with or without authentication.

## Files

- `nginx-register.sh` - Generic nginx configuration script
- `auto-configure-nginx.sh` - Automatic nginx setup from docker-compose.yml
- `templates/` - Nginx configuration templates
  - `nginx-location-multiservice.conf.tmpl` - With Cognito auth
  - `nginx-location-multiservice-noauth.conf.tmpl` - No authentication
  - `nginx-location.conf.tmpl` - Single service
  - `systemd-service.tmpl` - Systemd service

## Quick Start

### After deploying an app with docker-compose:

```bash
cd /home/ubuntu/deployments/YOUR_APP_NAME

# Automatic configuration (detects everything)
auto-configure-nginx

# Or manual configuration
nginx-register add-multiservice YOUR_APP_NAME FRONTEND_PORT BACKEND_PORT

# Reload nginx
nginx-register reload
```

### For apps without authentication (auth_mode="none"):

```bash
# Auto-detect from config.json
nginx-register add-multiservice my-public-app 3001 8001

# Or explicitly set
nginx-register add-multiservice my-public-app 3001 8001 none
```

### For apps with Cognito authentication (auth_mode="cognito"):

```bash
# Auto-detect from config.json
nginx-register add-multiservice my-secure-app 3002 8002

# Or explicitly set
nginx-register add-multiservice my-secure-app 3002 8002 cognito
```

## How It Works

1. **Auto-detection**: Reads `config.json` to determine auth_mode
2. **Template selection**: Chooses appropriate template based on auth_mode
3. **Variable substitution**: Replaces {{APP_NAME}}, {{FRONTEND_PORT}}, {{BACKEND_PORT}}
4. **Nginx update**: Creates route file in /etc/nginx/conf.d/routes/
5. **Validation**: Tests nginx config validity before applying

## Commands

```bash
# Add nginx configuration
nginx-register add-multiservice APP_NAME FRONTEND_PORT BACKEND_PORT [AUTH_MODE]

# Remove nginx configuration
nginx-register remove APP_NAME

# Check if app is configured
nginx-register exists APP_NAME

# Test nginx configuration
nginx-register test

# Reload nginx
nginx-register reload

# Show help
nginx-register help
```

## Examples

### Example 1: Public app (no auth)

```bash
cd /home/ubuntu/deployments/my-public-app
auto-configure-nginx
# Result: App accessible publicly at https://hostname/my-public-app/
```

### Example 2: Secure app (Cognito auth)

```bash
cd /home/ubuntu/deployments/my-secure-app
auto-configure-nginx
# Result: App requires Cognito login at https://hostname/my-secure-app/
```

### Example 3: Manual configuration

```bash
# Public app on ports 3010/8010
nginx-register add-multiservice blog-app 3010 8010 none

# Secure app on ports 3011/8011
nginx-register add-multiservice admin-app 3011 8011 cognito

# Reload
nginx-register reload
```

## Troubleshooting

### Problem: "Template not found"

```bash
# Check templates exist
ls -la /opt/deployment-tools/templates/

# Should see both:
# - nginx-location-multiservice.conf.tmpl (with auth)
# - nginx-location-multiservice-noauth.conf.tmpl (no auth)
```

### Problem: "Location already exists"

```bash
# Remove existing configuration first
nginx-register remove APP_NAME
nginx-register add-multiservice APP_NAME FRONTEND_PORT BACKEND_PORT
nginx-register reload
```

### Problem: "Auth_mode not detected"

```bash
# Check config.json exists and has auth_mode field
cat config.json | python3 -m json.tool | grep auth_mode

# Or manually specify
nginx-register add-multiservice APP_NAME FRONTEND_PORT BACKEND_PORT none
```

## Verification

After configuration:

```bash
# Test nginx config is valid
nginx-register test

# Check route file was created
ls -la /etc/nginx/conf.d/routes/APP_NAME.conf

# Check app location exists in main config
sudo grep "include /etc/nginx/conf.d/routes/" /etc/nginx/sites-available/auth-gateway

# Test locally
curl -I http://localhost:FRONTEND_PORT/APP_NAME/
curl http://localhost:BACKEND_PORT/api/

# Test via nginx
curl -I https://$(hostname -f)/APP_NAME/
```

## Integration with Deployment Portal

The deployment portal should include these files in every deployment kit:

1. `automation/templates/nginx-location-multiservice.conf.tmpl`
2. `automation/templates/nginx-location-multiservice-noauth.conf.tmpl`
3. `automation/nginx-register.sh` (this generic version)
4. `config.json` with `auth_mode` field

Then deployment is simple:
```bash
cd /home/ubuntu/deployments/NEW_APP
auto-configure-nginx
```

Done! No manual nginx editing required.

## For New EC2 Servers

To set up this generic deployment system on a new EC2 server:

1. **Create directories**:
   ```bash
   sudo mkdir -p /opt/deployment-tools/templates
   sudo mkdir -p /etc/nginx/conf.d/routes
   ```

2. **Copy files from this server**:
   ```bash
   # On source server
   cd /opt/deployment-tools
   tar czf deployment-tools.tar.gz nginx-register.sh auto-configure-nginx.sh templates/

   # On new server
   cd /opt/deployment-tools
   sudo tar xzf deployment-tools.tar.gz
   sudo chmod +x nginx-register.sh auto-configure-nginx.sh
   sudo ln -sf /opt/deployment-tools/nginx-register.sh /usr/local/bin/nginx-register
   sudo ln -sf /opt/deployment-tools/auto-configure-nginx.sh /usr/local/bin/auto-configure-nginx
   ```

3. **Update nginx config** to include route files:
   ```bash
   # Add inside server block in /etc/nginx/sites-available/auth-gateway
   include /etc/nginx/conf.d/routes/*.conf;
   ```

4. **Test**:
   ```bash
   nginx-register --help
   auto-configure-nginx --help
   ```

Or use the deployment portal to generate kits that already include these tools.
