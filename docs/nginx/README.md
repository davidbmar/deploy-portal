# Nginx Modular Configuration System

## Overview

This directory contains the nginx configuration for the deployment portal and all deployed applications. The system uses a modular approach to prevent configuration errors and make it safe to add/remove applications.

## Architecture

### Main Configuration
- **Location**: `/etc/nginx/sites-available/auth-gateway`
- **Purpose**: Core nginx config with OAuth2 authentication, base services (deploy portal, SSH terminal, website cloner)
- **Includes**: 
  - `/etc/nginx/conf.d/upstreams/*.conf` - App-specific upstreams
  - `/etc/nginx/conf.d/apps/*.conf` - App-specific location blocks

### Modular App Configs

Each deployed application gets TWO files:

1. **Upstream Definition**: `/etc/nginx/conf.d/upstreams/[app-name]-upstream.conf`
   ```nginx
   upstream my_app_backend {
       server 127.0.0.1:3001;
   }
   ```

2. **Location Blocks**: `/etc/nginx/conf.d/apps/[app-name]-locations.conf`
   ```nginx
   # API endpoint (must come before main location)
   location /my-app/api/ {
       auth_request /oauth2/auth;
       rewrite ^/my-app/api/(.*)$ /api/$1 break;
       proxy_pass http://127.0.0.1:8001;
       # ... headers ...
   }
   
   # Frontend
   location /my-app/ {
       auth_request /oauth2/auth;
       proxy_pass http://my_app_backend;
       # ... headers ...
   }
   
   # Redirect without trailing slash
   location = /my-app {
       return 301 /my-app/;
   }
   ```

## Benefits

1. **No More Sed Editing**: Never use sed to modify the main config file
2. **Safe to Add/Remove**: Just add/remove files from the modular directories
3. **Core Config Protected**: Main page and base services can't be broken by app deployments
4. **Easy to Debug**: Each app's config is in its own file
5. **Version Control Friendly**: Clear diffs when apps are added/removed

## Adding a New Application

1. Create upstream file:
   ```bash
   sudo nano /etc/nginx/conf.d/upstreams/new-app-upstream.conf
   ```

2. Create locations file:
   ```bash
   sudo nano /etc/nginx/conf.d/apps/new-app-locations.conf
   ```

3. Test and reload:
   ```bash
   sudo nginx -t && sudo systemctl reload nginx
   ```

## Removing an Application

1. Remove both files:
   ```bash
   sudo rm /etc/nginx/conf.d/upstreams/app-name-upstream.conf
   sudo rm /etc/nginx/conf.d/apps/app-name-locations.conf
   ```

2. Test and reload:
   ```bash
   sudo nginx -t && sudo systemctl reload nginx
   ```

## Current Deployed Apps

See `examples/` directory for current configurations:
- `my-app-01-test-upstream.conf` + `my-app-01-test-locations.conf`
- `my-app-instance-02-upstream.conf` + `my-app-instance-02-locations.conf`

## Port Allocation

Keep track of ports in use:
- **3000**: website_cloner
- **3001**: my-app-01-test (frontend)
- **3002**: my-app-instance-02 (frontend)
- **4180**: oauth2-proxy
- **5000**: deploy_portal
- **8000**: (reserved)
- **8001**: my-app-01-test (backend API)
- **8002**: my-app-instance-02 (backend API)
- **8080**: ssh_terminal

## Important Notes

1. **Location Block Order**: API locations must come BEFORE frontend locations in the config
2. **Static Files**: Add locations without auth_request for CSS/JS/images
3. **OAuth Integration**: All protected routes use `auth_request /oauth2/auth`
4. **WebSocket Support**: Included in location configs for Next.js hot reload
5. **CORS Headers**: API locations include CORS headers for cross-origin requests

## Troubleshooting

### App Returns 404
- Check if both upstream and locations files exist
- Verify upstream name matches in both files
- Check nginx error log: `sudo tail -f /var/log/nginx/error.log`

### Changes Not Applied
- Always reload after changes: `sudo systemctl reload nginx`
- Use `sudo nginx -t` to test config before reloading

### Port Conflicts
- Check which ports are in use: `sudo lsof -i -P -n | grep LISTEN`
- Update port numbers in both docker-compose.yml and nginx configs
