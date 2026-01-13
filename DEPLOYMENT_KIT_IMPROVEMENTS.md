 Deployment Kit Improvements

Based on real-world deployment of an AI Application Support/IT Triaging Agent, here are critical improvements needed for the deployment kit generator.

## Summary of Issues Encountered

1. **Docker Compose Not Installed** - Server had Docker but not docker-compose
2. **Permission Issues** - User needed to be added to docker group
3. **Port Conflicts** - Port 3000 was already in use
4. **Next.js Base Path Configuration** - Not covered in instructions
5. **API Proxy Configuration** - Missing nginx config for backend API
6. **Environment Variables** - Build-time vs runtime vars for Next.js

## Required Changes to Deployment Kit Generator

### 1. Add Docker Compose Check to Instructions

**Current State:** Instructions assume docker-compose exists

**Needed Addition:**
```markdown
### Step 4: Check Server Prerequisites

Check and install docker-compose if missing:
```bash
# Check if docker-compose exists
docker-compose --version || docker compose version

# If missing, install:
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-linux-aarch64" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

### 2. Add Docker Group Permission Instructions

**Current State:** No mention of docker group permissions

**Needed Addition:**
```markdown
# Ensure ubuntu user is in docker group
sudo usermod -aG docker ubuntu

# Use sg docker -c '...' for immediate access
sg docker -c 'docker-compose up -d'
```

### 3. Add Next.js Subpath Configuration Section

**Current State:** No guidance for Next.js apps deployed to subpaths

**Needed Addition:** (See CLAUDE_PROMPT_IMPROVED.md Step 5)

Critical for Next.js apps:
- basePath configuration
- assetPrefix configuration
- trailingSlash setting
- NEXT_PUBLIC_* environment variables must use public URL

### 4. Add Dual Nginx Location Blocks

**Current State:** Only shows single nginx location block

**Problem:** Frontend-backend apps need TWO nginx locations:
- One for frontend UI
- One for API proxy

**Needed Addition:**
```nginx
# Frontend location
location /{{APP_NAME}}/ {
    proxy_pass http://{{APP_NAME}}_backend;
    # ... auth config ...
}

# API location (CRITICAL!)
location /{{APP_NAME}}/api/ {
    rewrite ^/{{APP_NAME}}/api/(.*)$ /api/$1 break;
    proxy_pass http://127.0.0.1:{{BACKEND_PORT}};
    # ... auth config ...
}
```

### 5. Add Port Conflict Handling

**Current State:** Instructions assume ports are available

**Needed Addition:**
```markdown
### Check for Port Conflicts

```bash
# Before starting, check if ports are in use
sudo lsof -i :3000
sudo lsof -i :8000
sudo lsof -i :5432

# If port is in use, update docker-compose.yml
# Change "3000:3000" to "3001:3000"
```

### 6. Add Troubleshooting Section

**Current State:** No troubleshooting guidance

**Needed Addition:** See CLAUDE_PROMPT_IMPROVED.md "Troubleshooting Guide"

Common issues:
- "Cannot connect to backend" → Missing API nginx location
- "Cannot GET /app-name/" → Missing basePath in Next.js config
- "Permission denied" → Docker group issues
- "Address already in use" → Port conflicts

### 7. Improve Project Analysis Questions

**Current State:**
```markdown
2. What's the start command?
3. Does it have dependencies?
4. Does it have a Dockerfile?
```

**Needed Addition:**
```markdown
2. What's the start command?
3. Does it have dependencies?
4. Does it have a Dockerfile or docker-compose.yml?
5. **NEW: Is this a Next.js app?** (Check for next.config.js)
6. **NEW: Does this have separate frontend/backend?** (Check for multiple services)
7. **NEW: What ports does it expose?**
```

### 8. Add App Type Detection

**Recommendation:** Deployment kit generator should detect:

- **Simple App:** Single service, one port
  - Standard nginx location block
  - No special configuration needed

- **Next.js App:** Has next.config.js
  - Requires basePath configuration
  - Requires NEXT_PUBLIC_* URL updates
  - Requires rebuild after config changes

- **Frontend + Backend:** Has multiple services (docker-compose.yml)
  - Requires TWO nginx locations (frontend + API)
  - Requires API URL configuration
  - More complex environment variable handling

### 9. Update File Copy Instructions

**Current State:**
```bash
scp -i capsule-deploy.pem -r ./* ubuntu@HOST:~/deployments/app/
```

**Better Alternative:**
```bash
rsync -avz --exclude 'node_modules' --exclude 'venv' --exclude '.git' --exclude '.next' --exclude '.env' -e "ssh -i capsule-deploy.pem" ./ ubuntu@HOST:~/deployments/app/
```

**Why:** More explicit excludes, better for large projects

### 10. Add Environment Variable Template

**Current State:** "ASK ME for secret values"

**Needed Addition:** Generate app-specific .env template

```markdown
### Create .env file on server

Based on your app's requirements, create:

```bash
cat > .env << 'EOF'
# Required Variables
DATABASE_URL=postgresql://user:pass@postgres:5432/dbname
API_KEY=<ask-user-for-value>

# Optional Variables
DEBUG=false
LOG_LEVEL=info
EOF
```

## Implementation Checklist for Deploy Portal

- [ ] Add docker-compose installation check to generated instructions
- [ ] Add docker group permission instructions
- [ ] Detect Next.js apps (check for next.config.js)
- [ ] Detect multi-service apps (check docker-compose.yml)
- [ ] Generate app-type-specific instructions:
  - [ ] Simple app instructions (current default)
  - [ ] Next.js app instructions (with basePath config)
  - [ ] Multi-service app instructions (with dual nginx locations)
- [ ] Generate .env template based on docker-compose.yml env vars
- [ ] Add troubleshooting section with common issues
- [ ] Update nginx configuration generator to create dual locations for multi-service apps
- [ ] Add port conflict detection/resolution instructions
- [ ] Replace scp with rsync in instructions
- [ ] Add post-deployment verification steps specific to app type

## Template Variables Needed

The improved instructions use these template variables:

- `{{APP_NAME}}` - Application name
- `{{APP_TYPE}}` - App type (simple/nextjs/multi-service)
- `{{HOST}}` - Server hostname
- `{{FRONTEND_PORT}}` - Frontend service port
- `{{BACKEND_PORT}}` - Backend API port (if applicable)
- `{{DEPLOYMENT_KIT_ID}}` - Unique kit ID
- `{{USER_EMAIL}}` - User who requested deployment
- `{{DASHBOARD_API_KEY}}` - API key for dashboard

## Testing Recommendations

Before releasing improved deployment kit:

1. Test with simple single-service app
2. Test with Next.js app (standalone)
3. Test with multi-service app (frontend + backend + database)
4. Test on fresh server without docker-compose
5. Test with port conflicts
6. Verify all nginx configurations work with authentication

## Expected Outcome

With these improvements, Claude Code should be able to:

1. Successfully deploy any app type without manual intervention
2. Handle Next.js apps with proper subpath configuration
3. Configure multi-service apps with working API connectivity
4. Recover from common issues (permissions, ports, missing tools)
5. Generate working nginx configurations on first try

## Files to Update in Deploy Portal

1. **Template: CLAUDE_PROMPT.md**
   - Replace with CLAUDE_PROMPT_IMPROVED.md template
   - Add conditional sections based on app type

2. **App Analyzer:**
   - Add Next.js detection (next.config.js)
   - Add multi-service detection (docker-compose.yml with >1 service)
   - Parse docker-compose.yml for ports and services

3. **Nginx Config Generator:**
   - Generate dual location blocks for multi-service apps
   - Add API proxy location automatically
   - Include CORS headers for API locations

4. **.env Template Generator:**
   - Parse docker-compose.yml environment variables
   - Generate .env template with placeholders
   - Mark required vs optional variables

5. **Pre-flight Checks:**
   - Generate server prerequisite checks
   - Include docker-compose installation
   - Include port availability checks
