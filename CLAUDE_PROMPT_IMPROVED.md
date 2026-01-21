# Deploy {{APP_NAME}} to Cloud

I need you to deploy this project to our cloud server with automated setup.

## Application Details

- **App Name**: {{APP_NAME}}
- **App Type**: {{APP_TYPE}}
- **Target Directory**: `/home/ubuntu/deployments/{{APP_NAME}}/`
- **Public URL**: `https://{{HOST}}/{{APP_NAME}}/` (after setup)

## Connection Details

- **Host**: {{HOST}}
- **User**: ubuntu
- **SSH Key**: Use the capsule-deploy.pem file in this directory

## Deployment Process

### Step 1: Fix SSH Key Permissions

```bash
chmod 600 capsule-deploy.pem
```

### Step 2: Analyze This Project

Before deploying, analyze:
1. What language/framework? (Node.js, Python, Go, etc.)
2. What's the start command? (npm start, python app.py, etc.)
3. Does it have dependencies? (package.json, requirements.txt, go.mod)
4. Any environment variables needed?
5. Does it have a Dockerfile or docker-compose.yml?
6. **NEW: Is this a Next.js app?** (Check for next.config.js)
7. **NEW: Does this app have a separate API backend?** (Check for multiple services)

### Step 3: Copy Project to Server

```bash
# From your local machine (in project directory)
rsync -avz --exclude 'node_modules' --exclude 'venv' --exclude '.git' --exclude '.next' --exclude '.env' -e "ssh -i capsule-deploy.pem" ./ ubuntu@{{HOST}}:~/deployments/{{APP_NAME}}/
```

**IMPORTANT:**
- DO NOT copy .env files with secrets
- DO NOT copy node_modules or venv directories
- DO NOT copy build artifacts (.next, dist, build)
- DO copy package.json, requirements.txt, go.mod, docker-compose.yml, etc.

### Step 4: Check Server Prerequisites

**NEW: Before deploying, ensure the server has required tools:**

```bash
ssh -i capsule-deploy.pem ubuntu@{{HOST}}

# Check Docker
docker --version

# Check Docker Compose (CRITICAL!)
docker-compose --version || docker compose version

# If docker-compose is missing, install it:
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-linux-aarch64" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Ensure ubuntu user is in docker group
sudo usermod -aG docker ubuntu
# Note: May need to reconnect SSH for group to take effect
```

### Step 5: Configure Application for Subpath Deployment

**NEW: For Next.js Applications with Separate Backend:**

If this is a Next.js dashboard with a separate API backend, you MUST configure it for subpath deployment:

```bash
# 1. Update next.config.js
cat > dashboard/next.config.js << 'EOF'
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  output: 'standalone',
  basePath: '/{{APP_NAME}}',
  assetPrefix: '/{{APP_NAME}}',
  // trailingSlash: false  // Default - only enable if app code handles it
}

module.exports = nextConfig
EOF

# 2. Update .env.local for dashboard
cat > dashboard/.env.local << 'EOF'
NEXT_PUBLIC_API_URL=https://{{HOST}}/{{APP_NAME}}/api
NEXT_PUBLIC_API_KEY={{DASHBOARD_API_KEY}}
EOF

# 3. Update docker-compose.yml build args
# Change:
#   - NEXT_PUBLIC_API_URL=http://localhost:8000/api
# To:
#   - NEXT_PUBLIC_API_URL=https://{{HOST}}/{{APP_NAME}}/api
```

**Why is this needed?**
- `basePath` tells Next.js the app is served from `/{{APP_NAME}}/` not `/`
- `assetPrefix` ensures static assets load from correct path
- `trailingSlash: false` (default) - only enable if app code handles trailing slash logic
- `NEXT_PUBLIC_API_URL` must use the public HTTPS URL, not localhost

### Step 6: Handle Port Conflicts

**NEW: Check for port conflicts before starting:**

```bash
# Check if ports are in use
sudo lsof -i :3000
sudo lsof -i :8000
sudo lsof -i :5432

# If port 3000 is in use, update docker-compose.yml:
# Change: "3000:3000"
# To: "3001:3000" (or next available port)
```

### Step 7: Deploy with Docker Compose

**For applications with docker-compose.yml:**

```bash
cd /home/ubuntu/deployments/{{APP_NAME}}

# Create .env file (DO NOT copy from local!)
cat > .env << 'EOF'
# Add your environment variables here
# Example:
API_KEY=your-api-key-here
DATABASE_URL=postgresql://user:pass@postgres:5432/dbname
EOF

# Start with docker group (handles permission issues)
sg docker -c 'docker-compose up -d --build'

# Check status
sg docker -c 'docker-compose ps'

# View logs
sg docker -c 'docker-compose logs -f'
```

**Common Docker Compose Issues:**
- If `docker-compose` command not found, use `docker compose` (newer versions)
- If permission denied, ensure user is in docker group: `sg docker -c 'docker-compose ...'`
- Check container logs if services fail to start: `docker-compose logs <service-name>`

### Step 8: Configure Nginx for Authenticated Access

**NEW: For multi-service apps (frontend + backend), you need TWO nginx locations:**

#### 8a. Create upstream definition

```bash
# Add to end of /etc/nginx/sites-available/auth-gateway
sudo bash -c 'cat >> /etc/nginx/sites-available/auth-gateway << EOF

# {{APP_NAME}} upstream
upstream {{APP_NAME}}_backend {
    server 127.0.0.1:{{FRONTEND_PORT}};
}
EOF'
```

#### 8b. Add frontend location block

```bash
# Add BEFORE the "# Health check endpoint" line
sudo bash -c 'cat > /tmp/{{APP_NAME}}-location.conf << "EOF"

    # Protected: {{APP_NAME}}
    location /{{APP_NAME}}/ {
        # Authentication check
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/start?rd=\$scheme://\$host\$request_uri;

        # Pass authentication headers
        auth_request_set \$user \$upstream_http_x_auth_request_user;
        auth_request_set \$email \$upstream_http_x_auth_request_email;
        auth_request_set \$auth_cookie \$upstream_http_set_cookie;
        add_header Set-Cookie \$auth_cookie;

        # Proxy to frontend
        proxy_pass http://{{APP_NAME}}_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-User-Email \$email;
        proxy_set_header X-Auth-Request-User \$user;

        # WebSocket and SSE support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
        proxy_buffering off;
        proxy_cache off;
    }

    # Redirect without trailing slash
    location = /{{APP_NAME}} {
        return 301 /{{APP_NAME}}/;
    }
EOF

sed -i "/# Health check endpoint/r /tmp/{{APP_NAME}}-location.conf" /etc/nginx/sites-available/auth-gateway'
```

#### 8c. **NEW: Add API location block (CRITICAL for frontend-backend apps)**

```bash
# Add API proxy location
sudo bash -c 'cat > /tmp/{{APP_NAME}}-api-location.conf << "EOF"

    # API endpoint for {{APP_NAME}}
    location /{{APP_NAME}}/api/ {
        # Authentication check
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/start?rd=\$scheme://\$host\$request_uri;

        # Pass authentication headers
        auth_request_set \$user \$upstream_http_x_auth_request_user;
        auth_request_set \$email \$upstream_http_x_auth_request_email;

        # Rewrite to remove /{{APP_NAME}} prefix
        rewrite ^/{{APP_NAME}}/api/(.*)\$ /api/\$1 break;

        # Proxy to backend API
        proxy_pass http://127.0.0.1:{{BACKEND_PORT}};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-User-Email \$email;
        proxy_set_header X-Auth-Request-User \$user;

        # CORS headers
        add_header Access-Control-Allow-Origin \$http_origin always;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Authorization, Content-Type, X-API-Key" always;
        add_header Access-Control-Allow-Credentials true always;

        if (\$request_method = OPTIONS) {
            return 204;
        }
    }
EOF

sed -i "/# Protected: {{APP_NAME}}/r /tmp/{{APP_NAME}}-api-location.conf" /etc/nginx/sites-available/auth-gateway'
```

#### 8d. Test and reload nginx

```bash
sudo nginx -t
sudo systemctl reload nginx
```

**Why do you need both locations?**
- `/{{APP_NAME}}/` serves the frontend (Next.js dashboard)
- `/{{APP_NAME}}/api/` proxies API requests to the backend
- Without the API location, the frontend will show "Cannot connect to backend"

### Step 9: Verify Deployment

```bash
# Check all containers are running
sg docker -c 'docker-compose ps'

# Test frontend locally
curl http://localhost:{{FRONTEND_PORT}}/{{APP_NAME}}/

# Test backend API locally
curl http://localhost:{{BACKEND_PORT}}/api/

# Test public HTTPS access (will redirect to auth)
curl -k -I https://{{HOST}}/{{APP_NAME}}/

# Test API through nginx
curl -k https://{{HOST}}/{{APP_NAME}}/api/
```

## Important Rules

1. **Secrets Management**
   - DO NOT copy .env files directly
   - ASK ME for any secret values (API keys, database passwords, etc.)
   - Create .env files on the server with placeholder values first

2. **Permissions**
   - ASK ME before running sudo commands
   - Use `sg docker -c '...'` for docker commands if permission issues occur

3. **Documentation**
   - Document what you set up so I can maintain it later
   - Note any port changes, configuration modifications, etc.

## Troubleshooting Guide

### "Cannot connect to backend" in dashboard

**Problem:** Frontend loads but shows offline/cannot connect to backend.

**Solution:**
1. Verify API location block exists in nginx
2. Check `NEXT_PUBLIC_API_URL` in dashboard build uses public HTTPS URL
3. Rebuild dashboard: `docker-compose build dashboard && docker-compose up -d dashboard`
4. Check backend is accessible: `curl http://localhost:{{BACKEND_PORT}}/api/`

### "Cannot GET /{{APP_NAME}}/"

**Problem:** Nginx routes to app but app returns 404.

**Solution:**
1. For Next.js: Verify `basePath: '/{{APP_NAME}}'` in next.config.js
2. Verify Next.js config (basePath, assetPrefix) - DO NOT add trailingSlash unless app handles it
3. Rebuild dashboard with correct basePath
4. Check nginx proxy_pass doesn't have trailing slash

### Port conflicts

**Problem:** `address already in use` error when starting Docker.

**Solution:**
1. Find what's using the port: `sudo lsof -i :{{PORT}}`
2. Update docker-compose.yml to use different port
3. Update nginx upstream to point to new port

### Docker Compose not found

**Problem:** `docker-compose: command not found`

**Solution:**
```bash
# Install docker-compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-linux-aarch64" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
docker-compose --version
```

### Permission denied while connecting to Docker daemon

**Problem:** Cannot run docker commands.

**Solution:**
```bash
# Add user to docker group
sudo usermod -aG docker ubuntu

# Use sg for immediate access (without logout)
sg docker -c 'docker-compose up -d'

# Or reconnect SSH session for group membership to take effect
```

## Post-Deployment Report

After deployment, report back:
1. ✅ Application URL: https://{{HOST}}/{{APP_NAME}}/
2. ✅ Service status (all containers running)
3. ✅ Ports used (frontend, backend, database, etc.)
4. ✅ Backend connectivity verified (not showing "System Offline")
5. ❓ Any issues encountered and how they were resolved
6. 📝 Commands to manage the app:
   ```bash
   # Check status
   cd /home/ubuntu/deployments/{{APP_NAME}} && docker-compose ps

   # View logs
   docker-compose logs -f

   # Restart services
   sg docker -c 'docker-compose restart'

   # Stop services
   sg docker -c 'docker-compose down'

   # Start services
   sg docker -c 'docker-compose up -d'
   ```

---

**Generated by Deploy Portal**
**Deployment Kit ID**: {{DEPLOYMENT_KIT_ID}}
**For**: {{USER_EMAIL}}
