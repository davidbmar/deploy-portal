from flask import Flask, render_template, request, jsonify, send_file, Response
from config import Config
import boto3
import os
import io
import zipfile
from datetime import datetime
import glob
import time
import re
import json

app = Flask(__name__)
app.config.from_object(Config)

# Initialize AWS client
ec2_client = boto3.client('ec2', region_name=Config.get_region())

# Deployment version (generated at startup)
DEPLOYMENT_VERSION = datetime.utcnow().strftime(Config.DEPLOYMENT_VERSION_FORMAT)

# Active deployment sessions tracking
# Format: {user_email: {'app_name': str, 'started_at': datetime, 'version': str}}
active_deployments = {}

def get_user_info():
    """Extract user info from oauth2-proxy headers"""
    email = request.headers.get('X-User-Email', 'unknown@unknown.com')
    # Get real IP - check X-Forwarded-For first, then X-Real-IP, then remote_addr
    forwarded_for = request.headers.get('X-Forwarded-For', '')
    if forwarded_for:
        # X-Forwarded-For can contain multiple IPs, first is the client
        ip = forwarded_for.split(',')[0].strip()
    else:
        ip = request.headers.get('X-Real-IP', request.remote_addr)
    return email, ip

def validate_app_name(app_name):
    """Validate app name format and availability"""
    # Pattern validation
    if not re.match(r'^[a-z0-9][a-z0-9-]{0,30}[a-z0-9]$', app_name):
        return False, 'Invalid format. Use lowercase letters, numbers, and hyphens only.'

    # Length validation
    if len(app_name) < 2:
        return False, 'App name must be at least 2 characters.'

    if len(app_name) > 32:
        return False, 'App name must be 32 characters or less.'

    # Reserved names
    reserved = ['oauth2', 'health', 'deploy', 'cloner', 'static', 'api', 'admin']
    if app_name in reserved:
        return False, f'{app_name} is a reserved name.'

    return True, None

def is_ip_whitelisted(ip):
    """Check if IP is already in security group"""
    try:
        response = ec2_client.describe_security_groups(
            GroupIds=[Config.SECURITY_GROUP_ID]
        )
        for permission in response['SecurityGroups'][0].get('IpPermissions', []):
            if permission.get('FromPort') == 22 and permission.get('ToPort') == 22:
                for ip_range in permission.get('IpRanges', []):
                    if ip_range.get('CidrIp') == f"{ip}/32":
                        return True
        return False
    except Exception as e:
        print(f"Error checking security group: {e}")
        return False

def whitelist_ip(ip, email):
    """Add IP to security group for SSH access"""
    try:
        ec2_client.authorize_security_group_ingress(
            GroupId=Config.SECURITY_GROUP_ID,
            IpPermissions=[{
                'IpProtocol': 'tcp',
                'FromPort': 22,
                'ToPort': 22,
                'IpRanges': [{
                    'CidrIp': f"{ip}/32",
                    'Description': f"Deploy access for {email} - {datetime.utcnow().isoformat()}"
                }]
            }]
        )
        return True, "IP whitelisted successfully"
    except ec2_client.exceptions.ClientError as e:
        if 'InvalidPermission.Duplicate' in str(e):
            return True, "IP already whitelisted"
        return False, str(e)

def load_automation_scripts():
    """Load automation scripts from the automation directory"""
    automation_dir = os.path.join(os.path.dirname(__file__), 'automation')
    scripts = {}

    # Load shell scripts
    script_files = [
        'port-allocator.sh',
        'nginx-register.sh',
        'nginx-configure-with-validation.sh',
        'systemd-register.sh',
        'registry-manager.sh',
        'deploy-app.sh'
    ]

    for script_file in script_files:
        script_path = os.path.join(automation_dir, script_file)
        if os.path.exists(script_path):
            with open(script_path, 'r') as f:
                scripts[script_file] = f.read()

    # Load template files
    templates_dir = os.path.join(automation_dir, 'templates')
    template_files = [
        'nginx-location.conf.tmpl',
        'nginx-location-multiservice.conf.tmpl',
        'systemd-service.tmpl'
    ]

    for template_file in template_files:
        template_path = os.path.join(templates_dir, template_file)
        if os.path.exists(template_path):
            with open(template_path, 'r') as f:
                scripts[f'templates/{template_file}'] = f.read()

    return scripts

def detect_app_type(app_name):
    """Detect application type from project structure if it exists on server"""
    deployment_path = f"/home/{Config.EC2_USER}/deployments/{app_name}"

    app_characteristics = {
        'is_nextjs': False,
        'is_multi_service': False,
        'has_docker_compose': False,
        'frontend_port': None,
        'backend_port': None,
        'services': []
    }

    # This would be called after project is copied to server
    # For now, return defaults - can be enhanced later
    return app_characteristics

def parse_docker_compose_env(docker_compose_content):
    """Parse docker-compose.yml to extract environment variables"""
    # Simple parsing - could use PyYAML for more robust parsing
    env_vars = []

    # Look for environment: sections and extract variables
    lines = docker_compose_content.split('\n')
    in_env_section = False

    for line in lines:
        if 'environment:' in line:
            in_env_section = True
            continue
        if in_env_section:
            if line.strip().startswith('-'):
                # Extract variable name
                var = line.strip().lstrip('-').strip()
                if '=' in var:
                    var_name = var.split('=')[0]
                    env_vars.append(var_name)
            elif not line.strip().startswith(' ') and line.strip():
                in_env_section = False

    return env_vars

def generate_env_template(app_name, app_type, dashboard_api_key):
    """Generate a template .env file based on app type"""
    if app_type in ['nextjs', 'react', 'vue', 'angular']:
        # Frontend with possible backend
        return f"""# Environment Variables for {app_name}
# Generated by Deploy Portal

# API Configuration
API_KEY={dashboard_api_key}
NEXT_PUBLIC_API_KEY={dashboard_api_key}

# Database (if applicable)
DATABASE_URL=postgresql://user:password@postgres:5432/dbname

# Application Settings
NODE_ENV=production
PORT=3000

# Add your application-specific variables below:
# EXAMPLE_VAR=value
"""
    elif app_type in ['python', 'fastapi', 'flask', 'django']:
        # Python backend
        return f"""# Environment Variables for {app_name}
# Generated by Deploy Portal

# API Configuration
API_KEY={dashboard_api_key}

# Database
DATABASE_URL=postgresql://user:password@postgres:5432/dbname

# Application Settings
ENVIRONMENT=production
PORT=8000

# Add your application-specific variables below:
# EXAMPLE_VAR=value
"""
    else:
        # Generic template
        return f"""# Environment Variables for {app_name}
# Generated by Deploy Portal

# Add your application-specific variables below:
# API_KEY=your-api-key-here
# DATABASE_URL=postgresql://user:pass@postgres:5432/dbname
# PORT=5001
"""

def generate_app_deployment_kit(email, ip, app_name, app_type, deploy_mode='new', auth_mode='cognito'):
    """Generate app-specific deployment kit with automation instructions"""
    instance_ip = Config.get_instance_ip()
    # Use deployment version format (lexicographically sortable)
    version = datetime.utcnow().strftime(Config.DEPLOYMENT_VERSION_FORMAT)
    timestamp = version  # For backward compatibility with template
    is_update = deploy_mode == 'update'

    # Read the SSH private key
    try:
        with open(Config.SSH_KEY_PATH, 'r') as f:
            ssh_key = f.read()
    except FileNotFoundError:
        return None, "SSH key not found. Please contact administrator."

    # App-specific README
    readme = f"""# Capsule Cloud Deployment Kit - {app_name}

Generated for: {email}
Generated at: {datetime.utcnow().isoformat()}Z
Your IP: {ip}
App Name: {app_name}
App Type: {app_type}
Kit Version: {version} UTC

## Quick Start

You have TWO options for deploying:

---

### ⭐ OPTION 1: One-Command Deployment (Recommended)

Deploy with a single `/deploy` command using the included skill.

#### FIRST TIME ONLY - Install the Skill (10 seconds)

The `deploy-skill.yaml` file is in THIS folder. Run ONE command:

```bash
cp deploy-skill.yaml ~/.config/claude/skills/deploy.yaml
```

That's it! Skill is installed. You never need to do this again.

#### Every Deployment - Three Steps

**Step 1**: Move this ZIP to your project folder
```bash
cp deployment-kit-{app_name}-{timestamp}.zip ~/path/to/your-project/
```

**Step 2**: Open Claude Code in your project
```bash
cd ~/path/to/your-project
claude-code
```

**Step 3**: Type this command
```
/deploy
```

⚠️ **IMPORTANT: After typing `/deploy`, DO NOT manually execute deployment steps!**

The skill runs **AUTONOMOUSLY**. Just sit back and:
- Watch the progress
- Respond if asked for confirmations or secrets
- Let the skill handle everything else automatically

Done! The skill will:
- Find the deployment kit automatically
- **Check the ZIP's skill version** (auto-updates if newer)
- Deploy your app completely on its own
- Give you the live URL

**Do not try to "help" by running commands - the skill does it all!**

**Next time you deploy**: Just download a new kit, move the ZIP to your project, and run `/deploy` again. The skill checks the ZIP and auto-updates itself if the ZIP has a newer version.

---

### OPTION 2: Manual Deployment (Traditional)

1. Open terminal in this directory

2. Fix key permissions:
   ```bash
   chmod 600 capsule-deploy.pem
   ```

3. Test SSH connection:
   ```bash
   ssh -i capsule-deploy.pem {Config.EC2_USER}@{instance_ip}
   ```

4. Open Claude Code in your project directory and give it the CLAUDE_PROMPT.md file

## Your App Will Be Deployed To

- Directory: `/home/{Config.EC2_USER}/deployments/{app_name}/`
- URL: `https://{instance_ip}/{app_name}/` (after nginx setup)

## Monitoring

View live activity at: https://{instance_ip}/deploy/activity

## Support

If you have issues connecting, ensure:
- Your IP ({ip}) hasn't changed
- The .pem file has correct permissions (chmod 600)
- You're using the correct username ({Config.EC2_USER})
"""

    # Generate API key for dashboard (if needed for multi-service apps)
    dashboard_api_key = os.urandom(32).hex()

    # Mode-specific header
    if is_update:
        mode_header = f"""# Update {app_name} on Cloud

I need you to **UPDATE** an existing deployment. The app is already running on the server.

## 🔄 UPDATE MODE - Quick Steps

1. Fix SSH key permissions: `chmod 600 capsule-deploy.pem`
2. Sync your changes to the server (rsync command below)
3. Rebuild and restart containers: `docker-compose up -d --build`

**This is an UPDATE** - nginx and other server configs are already set up. Just sync code and restart."""
    else:
        mode_header = f"""# Deploy {app_name} to Cloud

I need you to deploy this project to our cloud server with automated setup.

**This is a NEW DEPLOYMENT** - follow all steps including nginx configuration."""

    # App-specific CLAUDE_PROMPT.md with improved template
    claude_prompt = f"""{mode_header}

## ⚠️ IMPORTANT: Choose Your Deployment Method

You have **TWO** ways to deploy this application:

### Method 1: Automated Skill (RECOMMENDED) ✅

**Best for**: Normal deployments, updates, and first-time users

```bash
# In your project directory with the deployment-kit ZIP:
claude-code
# Then type: /deploy
```

**What happens:**
- The `/deploy` skill runs **AUTONOMOUSLY**
- You sit back and monitor progress
- Only respond when prompted (confirmations, secrets, choices)
- The skill handles all 11 steps automatically

⚠️ **CRITICAL**: If you invoke `/deploy`, do NOT manually execute the steps below. Let the skill run autonomously. **STOP READING THIS FILE** and let the skill work.

---

### Method 2: Manual Deployment (Troubleshooting Only) 🔧

**Use only if:**
- The automated skill fails or errors
- You need to troubleshoot a specific step
- You want to understand the deployment process in detail

**If using the manual method, continue reading from Step 0 below.**

---

## CRITICAL: Local vs Cloud Configuration Rules

**IMPORTANT**: This deployment kit is ONLY for deploying to the cloud. Your LOCAL source files should remain clean for local development.

### Rule 1: Local Files = Localhost URLs
| Context | API URL to Use |
|---------|----------------|
| **Local Development** (default) | `http://localhost:8000/api` |
| **Cloud Deployment** (only during deploy) | `https://{instance_ip}/{app_name}/api` |

### Rule 2: Container Names
| Context | Container Names |
|---------|-----------------|
| **Local Development** | Generic names or omit `container_name` entirely |
| **Cloud Deployment** | `{app_name}-backend`, `{app_name}-dashboard`, etc. |

### Rule 3: Deployment-Specific Changes = SERVER ONLY
**NEVER modify local source files with:**
- Cloud URLs (`https://{instance_ip}/...`)
- Deployment-specific container names (`{app_name}-backend`)
- Production basePath in next.config.js

**ALL deployment-specific changes are made ON THE SERVER after rsync.**

---

## ⚠️ PRE-FLIGHT CHECK: Detect Old Deployment References

**BEFORE deploying, check if local files have OLD deployment names:**

```bash
# Check for ANY deployment-specific names in local docker-compose.yml
grep -E "container_name:.*-backend|container_name:.*-dashboard|container_name:.*-postgres" docker-compose.yml
```

**If you find references to a DIFFERENT app name (not `{app_name}`), STOP and alert the user:**

> "⚠️ WARNING: Your local docker-compose.yml contains references to a previous deployment.
> Found: [old-app-name]-backend, [old-app-name]-dashboard
> Expected for this deployment: {app_name}
>
> Your LOCAL files should use generic names for local development.
> Should I clean up the local docker-compose.yml before proceeding?"

**To clean local docker-compose.yml for local development:**
1. Remove or genericize `container_name` lines
2. Change URLs back to `http://localhost:8000/api`
3. Remove basePath from next.config.js (or set to empty string)

---

## 🔄 STEP 0: Check and Update Deployment Skill (REQUIRED FIRST STEP)

**⚠️ CRITICAL: Always check for skill updates BEFORE deploying!**

This deployment kit includes a versioned `deploy-skill.yaml` file. Before proceeding with deployment, you MUST check if the skill in this ZIP is newer than your installed version and update if needed.

### Why This Matters

The skill version is synchronized with the deployment kit. Using an outdated skill may cause:
- Missing features or bug fixes
- Incompatible deployment steps
- Failed deployments

### Step 0.1: Check Current Skill Version

```bash
# Check if you have the skill installed
if [ -f ~/.config/claude/skills/deploy.yaml ]; then
    INSTALLED_VERSION=$(grep "^version:" ~/.config/claude/skills/deploy.yaml | awk '{{print $2}}')
    echo "Installed skill version: $INSTALLED_VERSION UTC"
else
    echo "No skill installed yet"
    INSTALLED_VERSION=""
fi
```

### Step 0.2: Check ZIP's Skill Version

```bash
# Get the skill version from this deployment kit
ZIP_VERSION=$(grep "^version:" deploy-skill.yaml | awk '{{print $2}}')
echo "Deployment kit skill version: $ZIP_VERSION UTC"
```

### Step 0.3: Compare and Update

```bash
# Compare versions (lexicographic comparison works because format is YYYYMMDD.HHmmss)
if [ -z "$INSTALLED_VERSION" ]; then
    echo "📦 First-time skill installation required"
    echo "Installing skill from deployment kit..."
    mkdir -p ~/.config/claude/skills
    cp deploy-skill.yaml ~/.config/claude/skills/deploy.yaml
    echo "✅ Skill installed: $ZIP_VERSION UTC"
    echo ""
    echo "🎯 TIP: Next time you deploy, just run '/deploy' in Claude Code!"
    echo "       The skill will auto-check for updates."
elif [[ "$ZIP_VERSION" > "$INSTALLED_VERSION" ]]; then
    echo "📦 Newer skill version found in deployment kit!"
    echo "   Current:   $INSTALLED_VERSION UTC"
    echo "   Available: $ZIP_VERSION UTC"
    echo ""
    echo "Backing up old skill..."
    mkdir -p ~/.config/claude/skills/.backups
    cp ~/.config/claude/skills/deploy.yaml \\
       ~/.config/claude/skills/.backups/deploy-${{INSTALLED_VERSION}}.yaml
    echo "Installing new skill..."
    cp deploy-skill.yaml ~/.config/claude/skills/deploy.yaml
    echo "✅ Skill updated from $INSTALLED_VERSION UTC to $ZIP_VERSION UTC"
    echo ""
    echo "🎯 TIP: Use '/deploy' command in Claude Code for easier deployments!"
elif [[ "$ZIP_VERSION" == "$INSTALLED_VERSION" ]]; then
    echo "✅ Skill version matches deployment kit ($ZIP_VERSION UTC)"
    echo "   No update needed. Proceeding with deployment..."
else
    echo "⚠️  ZIP skill version ($ZIP_VERSION UTC) is older than installed ($INSTALLED_VERSION UTC)"
    echo "   Keeping installed version (no downgrade)."
fi
```

### Step 0.4: Proceed to Deployment

Once the skill version check is complete, proceed to Step 1.

**📌 IMPORTANT**: If you prefer using the `/deploy` skill command (recommended), you can stop here! The skill will automatically perform all the following steps when you run `/deploy` in Claude Code.

To use the skill:
1. Open Claude Code in this directory: `claude-code`
2. Type: `/deploy`
3. The skill will handle everything automatically!

If you prefer manual deployment or need to troubleshoot, continue with Step 1 below.

---

## 📋 STEP 1: Display Pre-Deployment Summary & Get Confirmation

**BEFORE doing anything else**, analyze the project and display this summary to the user:

```
════════════════════════════════════════════════════════════════════════════════
                           DEPLOYMENT SUMMARY
════════════════════════════════════════════════════════════════════════════════

  App Name: {app_name}
  Deployment Mode: {'🔄 UPDATE (sync changes & restart)' if is_update else '🆕 NEW deployment (fresh install)'}
  App Type: {app_type}
  Auth Mode: {auth_mode.upper()}
  Generated: {timestamp}

────────────────────────────────────────────────────────────────────────────────
  SERVER DETAILS
────────────────────────────────────────────────────────────────────────────────

  • Host: {instance_ip}
  • User: {Config.EC2_USER}
  • SSH Key: capsule-deploy.pem (included in kit)
  • Deployment Path: /home/{Config.EC2_USER}/deployments/{app_name}/

────────────────────────────────────────────────────────────────────────────────
  URLs AFTER DEPLOYMENT
────────────────────────────────────────────────────────────────────────────────

  • Public URL: https://{instance_ip}/{app_name}/
  • API URL: https://{instance_ip}/{app_name}/api/
  • Monitor: https://{instance_ip}/deploy/activity

────────────────────────────────────────────────────────────────────────────────
  WHAT WILL BE DEPLOYED
────────────────────────────────────────────────────────────────────────────────

  [Analyze the project and fill in details like:]
  • Frontend: [framework] on port [port]
  • Backend: [framework] on port [port]
  • Database: [type] on port [port] (if applicable)
  • Authentication: {'OAuth2 protected via Cognito' if auth_mode == 'cognito' else 'Internal auth (app-managed login)' if auth_mode == 'internal' else 'No authentication (fully public)'}

────────────────────────────────────────────────────────────────────────────────
  CONFIGURATION REQUIREMENTS
────────────────────────────────────────────────────────────────────────────────

  1. Next.js Config Changes (if applicable):
     • basePath: '/{app_name}'
     • assetPrefix: '/{app_name}'
     • trailingSlash: true
     • NEXT_PUBLIC_API_URL → public HTTPS URL

  2. Environment Variables (ON SERVER ONLY):
     • NEXT_PUBLIC_API_URL=https://{instance_ip}/{app_name}/api
     • NEXT_PUBLIC_API_KEY={dashboard_api_key}
     • [Plus any app-specific variables]

  3. Nginx Configuration:
     • /{app_name}/ → Frontend
     • /{app_name}/api/ → Backend API

────────────────────────────────────────────────────────────────────────────────
  AUTOMATION SCRIPTS AVAILABLE
────────────────────────────────────────────────────────────────────────────────

  • automation/deploy-app.sh - Main deployment script
  • automation/nginx-register.sh - Nginx configuration
  • automation/nginx-configure-with-validation.sh - Validated nginx config (multi-service)
  • automation/systemd-register.sh - Systemd service setup
  • automation/port-allocator.sh - Port conflict detection
  • automation/registry-manager.sh - App registry management

────────────────────────────────────────────────────────────────────────────────
  PREREQUISITES
────────────────────────────────────────────────────────────────────────────────

  ✓ Server must have Docker & Docker Compose installed
  ✓ Ubuntu user must be in docker group
  ✓ Required ports must be available (or will be remapped)
  ✓ SSH key permissions must be 600

════════════════════════════════════════════════════════════════════════════════
```

**⚠️ ASK THE USER FOR CONFIRMATION BEFORE PROCEEDING:**

> "I've analyzed your project and prepared the deployment summary above.
> Should I proceed with the deployment to {instance_ip}?"

**Wait for user confirmation before continuing to Step 2.**

---

## 📋 STEP 2: Fix SSH Key Permissions

```bash
chmod 600 capsule-deploy.pem
```

---

## 📋 STEP 3: Copy Project to Server

```bash
# From your local machine (in project directory)
rsync -avz --exclude 'node_modules' --exclude 'venv' --exclude '.git' --exclude '.next' -e "ssh -i capsule-deploy.pem" ./ {Config.EC2_USER}@{instance_ip}:~/deployments/{app_name}/
```

**Notes:**
- .env files ARE copied (secrets are protected behind OAuth)
- node_modules/venv are excluded (will be rebuilt on server)
- Build artifacts (.next, dist, build) are excluded (will be rebuilt)

---

## 📋 STEP 4: Check Server Prerequisites

{'**⏭️ SKIP FOR UPDATES** - Prerequisites already verified.' if is_update else '**Before deploying, ensure the server has required tools:**'}

```bash
ssh -i capsule-deploy.pem {Config.EC2_USER}@{instance_ip}

# Check Docker
docker --version

# Check Docker Compose (CRITICAL!)
docker-compose --version || docker compose version

# If docker-compose is missing, install it:
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-linux-aarch64" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Ensure ubuntu user is in docker group
sudo usermod -aG docker {Config.EC2_USER}
# Note: May need to reconnect SSH for group to take effect
```

### Step 5: Configure Application for Subpath Deployment (ON SERVER ONLY)

{'**⏭️ SKIP FOR UPDATES** - Subpath configuration already done.' if is_update else '**For Next.js Applications with Separate Backend:**'}

⚠️ **CRITICAL ORDER FOR NEXT.JS APPS**: You MUST configure next.config.js BEFORE building Docker containers!

**Correct sequence (DO NOT SKIP OR REORDER):**
1. ✅ Rsync files to server (Step 3)
2. ✅ SSH to server
3. ✅ **Update next.config.js with basePath** ← MUST BE FIRST
4. ✅ Update .env.local with cloud URLs
5. ✅ Update docker-compose.yml
6. ✅ **THEN** run docker compose build (Step 7) ← MUST BE LAST

**Why this order is critical:**
- Docker bakes next.config.js into image during build
- If you build FIRST then change config = build uses OLD config
- Result: Page loads without CSS (looks like 1990s webpage)
- Fix requires slow rebuild: `sg docker -c 'docker compose build --no-cache dashboard'`

**⚠️ IMPORTANT: These changes are made ON THE SERVER after rsync, NOT on your local machine!**

SSH into the server first, then make these changes in the server's copy:

```bash
# SSH to server first
ssh -i capsule-deploy.pem {Config.EC2_USER}@{instance_ip}

# Navigate to the deployment directory
cd /home/{Config.EC2_USER}/deployments/{app_name}

# 1. Update next.config.js (ON SERVER) - DO THIS BEFORE DOCKER BUILD!
cat > dashboard/next.config.js << 'EOF'
/** @type {{import('next').NextConfig}} */
const nextConfig = {{
  reactStrictMode: true,
  output: 'standalone',
  basePath: '/{app_name}',
  assetPrefix: '/{app_name}',
  trailingSlash: true,
}}

module.exports = nextConfig
EOF

# 2. Update .env.local for dashboard (ON SERVER)
cat > dashboard/.env.local << 'EOF'
NEXT_PUBLIC_API_URL=https://{instance_ip}/{app_name}/api
NEXT_PUBLIC_API_KEY={dashboard_api_key}
EOF

# 3. Update docker-compose.yml build args (ON SERVER)
# Edit the SERVER's docker-compose.yml to use cloud URLs:
# Change:
#   - NEXT_PUBLIC_API_URL=http://localhost:8000/api
# To:
#   - NEXT_PUBLIC_API_URL=https://{instance_ip}/{app_name}/api
```

**Why is this needed?**
- `basePath` tells Next.js the app is served from `/{app_name}/` not `/`
- `assetPrefix` ensures static assets load from correct path
- `trailingSlash: true` ensures URLs work with trailing slashes (nginx standard)
- `NEXT_PUBLIC_API_URL` must use the public HTTPS URL, not localhost

**⚠️ DO NOT modify your local docker-compose.yml with cloud URLs! Keep it using localhost.**

### Step 6: Check for Port Conflicts (MANDATORY - DO THIS FIRST!)

{'**For UPDATES:** Check if your existing containers are still running, restart if needed.' if is_update else '**⚠️ CRITICAL: You MUST check for port conflicts BEFORE deploying!**'}

Default ports in docker-compose.yml:
- **Dashboard (Frontend):** 3000
- **Backend (API):** 8000
- **PostgreSQL (Database):** 5432

If other apps are already running on these ports, Docker will fail to start.

#### 6a. Check all running containers and their ports

```bash
ssh -i capsule-deploy.pem {Config.EC2_USER}@{instance_ip}

# See ALL containers and what ports they're using
docker ps --format "table {{{{.Names}}}}\t{{{{.Ports}}}}"

# Check specific ports
sudo lsof -i :3000
sudo lsof -i :8000
sudo lsof -i :5432
```

**Example output showing ports in use:**
```
NAMES                      PORTS
my-app-test-11-dashboard   0.0.0.0:3001->3000/tcp
my-app-test-11-backend     0.0.0.0:8000->8000/tcp
my-app-test-11-postgres    0.0.0.0:5432->5432/tcp
```

#### 6b. If ports are in use, update docker-compose.yml BEFORE deploying

```bash
cd /home/{Config.EC2_USER}/deployments/{app_name}

# Find available ports by incrementing from occupied ones
# If 3000 is used → try 3001, 3002, etc.
# If 8000 is used → try 8001, 8002, etc.
# If 5432 is used → try 5433, 5434, etc.

# Update ports in docker-compose.yml using sed
# Example: Use ports 3002, 8002, 5434
sed -i 's/"5432:5432"/"5434:5432"/g' docker-compose.yml
sed -i 's/"8000:8000"/"8002:8000"/g' docker-compose.yml
sed -i 's/"3000:3000"/"3002:3000"/g' docker-compose.yml

# Verify changes were applied
grep -E "ports:" -A1 docker-compose.yml
```

**⚠️ IMPORTANT: Port Mapping Format**
- Format: `"HOST_PORT:CONTAINER_PORT"`
- **Only change the LEFT number** (host port)
- **Never change the RIGHT number** (container internal port)
- Example: `"3002:3000"` means "map host port 3002 to container port 3000"

**📝 WRITE DOWN YOUR PORTS! You'll need them for nginx config in Step 8!**

```
My allocated ports for {app_name}:
- Dashboard: ______ (default 3000)
- Backend:  ______ (default 8000)
- Postgres: ______ (default 5432)
```

### Step 7: Deploy with Docker Compose

**For applications with docker-compose.yml:**

```bash
cd /home/{Config.EC2_USER}/deployments/{app_name}

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

{'**⏭️ SKIP THIS STEP FOR UPDATES** - Nginx is already configured for this app.' if is_update else '**For multi-service apps (frontend + backend), you need nginx location blocks:**'}

#### Option A: AUTOMATED (Recommended) - Smart Deploy

**Use the smart-deploy.sh script for automatic framework detection and auth configuration:**

```bash
# Copy automation scripts to server (if not already there)
rsync -avz -e "ssh -i capsule-deploy.pem" ./automation/ {Config.EC2_USER}@{instance_ip}:~/deployments/{app_name}/automation/

# SSH to server
ssh -i capsule-deploy.pem {Config.EC2_USER}@{instance_ip}

# Read auth mode from config.json (included in your deployment kit)
AUTH_MODE=$(python3 -c "import json; print(json.load(open('config.json'))['auth_mode'])")
echo "Auth Mode: $AUTH_MODE"

# Run smart deployment with your ports and auth mode
cd ~/deployments/{app_name}
bash automation/smart-deploy.sh {app_name} /home/{Config.EC2_USER}/deployments/{app_name} https://{instance_ip} FRONTEND_PORT BACKEND_PORT $AUTH_MODE

# Example with actual ports:
# bash automation/smart-deploy.sh {app_name} /home/{Config.EC2_USER}/deployments/{app_name} https://{instance_ip} 3000 8000 {auth_mode}
```

**What this does automatically:**
- Detects Next.js framework
- Selects the correct nginx template based on auth mode:
  * **cognito**: OAuth2 protection via Cognito (default)
  * **internal**: Your app handles login, bypasses OAuth2 for /login and /api routes
  * **none**: Fully public, no authentication required
- Configures CORS automatically
- Creates nginx location blocks for frontend and API
- Tests and reloads nginx
- Backs up existing config

**Auth Mode: {auth_mode.upper()}** - {'Cognito OAuth2 authentication required' if auth_mode == 'cognito' else 'Internal authentication (app-managed)' if auth_mode == 'internal' else 'No authentication (fully public)'}

---

#### Option B: MANUAL - Traditional nginx-register.sh

**If smart-deploy doesn't work, fall back to manual nginx registration:**

```bash
# SSH to server
ssh -i capsule-deploy.pem {Config.EC2_USER}@{instance_ip}

# Run the multi-service nginx registration
# Replace DASHBOARD_PORT and BACKEND_PORT with your actual ports from Step 6!
cd ~/deployments/{app_name}
bash automation/nginx-register.sh add-multiservice {app_name} DASHBOARD_PORT BACKEND_PORT

# Example with actual ports:
# bash automation/nginx-register.sh add-multiservice {app_name} 3002 8002

# Reload nginx
bash automation/nginx-register.sh reload
```

**Note:** Manual method always uses Cognito OAuth2 authentication.

---

#### Option C: VALIDATED NGINX CONFIG (Recommended for Multi-Service Apps)

**Use this automated script with built-in validation to ensure nginx is configured correctly:**

This script addresses a critical bug where nginx configuration could fail silently, causing 404 errors.

**⚠️ CRITICAL: Use YOUR allocated ports from Step 6!**

```bash
# SSH to server
ssh -i capsule-deploy.pem {Config.EC2_USER}@{instance_ip}

# Run the validated nginx configuration script
cd ~/deployments/{app_name}
bash automation/nginx-configure-with-validation.sh {app_name} FRONTEND_PORT BACKEND_PORT

# Example with actual ports:
# bash automation/nginx-configure-with-validation.sh {app_name} 3002 8002
```

**What this script does:**
- ✅ Adds nginx upstream definition
- ✅ Creates location blocks for frontend and API
- ✅ **VALIDATES** blocks were added (checks for common sed failures)
- ✅ Uses fallback method if config markers are missing
- ✅ Tests nginx config before reload
- ✅ Provides clear error messages if anything fails
- ✅ Attempts rollback on failure

**If the script succeeds, you'll see:**
```
✅ NGINX CONFIGURATION COMPLETE

Your app is now available at:
  https://{Config.DUCKDNS_DOMAIN}/{app_name}/
```

**If the script fails:**
- Check the error message for specific issues
- Nginx config will be rolled back to last backup
- You can try the manual method below as a fallback

---

#### Option D: MANUAL (Last Resort - If All Automation Fails)

**Only use this if Options A, B, and C all fail!**

**⚠️ IMPORTANT**: The manual steps below are provided as a last resort. They may fail silently if your nginx config doesn't have the expected markers. Prefer the validated script (Option C) which handles these edge cases.

If you must proceed manually, be aware that:
- `sed` commands may fail silently if markers don't exist
- You must manually verify location blocks were added
- No automatic rollback if configuration is invalid

<details>
<summary>Click to expand manual nginx configuration steps</summary>

#### 8a. Create upstream definition

**Replace FRONTEND_PORT with your actual frontend port from Step 6!**

```bash
sudo bash -c 'cat >> /etc/nginx/sites-available/auth-gateway << EOF

# {app_name} upstream
upstream {app_name}_backend {{
    server 127.0.0.1:FRONTEND_PORT;
}}
EOF'
```

#### 8b. Add frontend and API location blocks

```bash
# Create location blocks file
cat > /tmp/{app_name}-location.conf << "EOF"

    # Protected: {app_name}
    location /{app_name}/ {{
        # Authentication check
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/start?rd=\\$scheme://\\$host\\$request_uri;

        # Pass authentication headers
        auth_request_set \\$user \\$upstream_http_x_auth_request_user;
        auth_request_set \\$email \\$upstream_http_x_auth_request_email;
        auth_request_set \\$auth_cookie \\$upstream_http_set_cookie;
        add_header Set-Cookie \\$auth_cookie;

        # Proxy to frontend
        proxy_pass http://{app_name}_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \\$host;
        proxy_set_header X-Real-IP \\$remote_addr;
        proxy_set_header X-Forwarded-For \\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\$scheme;
        proxy_set_header X-User-Email \\$email;
        proxy_set_header X-Auth-Request-User \\$user;

        # WebSocket and SSE support
        proxy_set_header Upgrade \\$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
        proxy_buffering off;
        proxy_cache off;
    }}

    # Redirect without trailing slash
    location = /{app_name} {{
        return 301 /{app_name}/;
    }}

    # API endpoint for {app_name}
    location /{app_name}/api/ {{
        # Authentication check
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/start?rd=\\$scheme://\\$host\\$request_uri;

        # Pass authentication headers
        auth_request_set \\$user \\$upstream_http_x_auth_request_user;
        auth_request_set \\$email \\$upstream_http_x_auth_request_email;

        # Rewrite to remove /{app_name} prefix
        rewrite ^/{app_name}/api/(.*)\\$ /api/\\$1 break;

        # Proxy to backend API
        proxy_pass http://127.0.0.1:BACKEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \\$host;
        proxy_set_header X-Real-IP \\$remote_addr;
        proxy_set_header X-Forwarded-For \\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\$scheme;
        proxy_set_header X-User-Email \\$email;
        proxy_set_header X-Auth-Request-User \\$user;

        # CORS headers
        add_header Access-Control-Allow-Origin \\$http_origin always;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Authorization, Content-Type, X-API-Key" always;
        add_header Access-Control-Allow-Credentials true always;

        if (\\$request_method = OPTIONS) {{
            return 204;
        }}
    }}
EOF

# ⚠️ WARNING: This sed command may fail silently if marker doesn't exist!
sudo sed -i "/# Health check endpoint/r /tmp/{app_name}-location.conf" /etc/nginx/sites-available/auth-gateway

# CRITICAL: Manually verify the blocks were added!
echo "Verifying location blocks were added..."
BLOCK_COUNT=$(sudo grep -c "location /{app_name}/" /etc/nginx/sites-available/auth-gateway)
if [ "$BLOCK_COUNT" -lt 2 ]; then
    echo "❌ ERROR: Location blocks were NOT added! Found $BLOCK_COUNT blocks, expected at least 2."
    echo "This means the sed command failed. Try Option C (validated script) instead."
    exit 1
fi
echo "✓ Found $BLOCK_COUNT location blocks"
```

#### 8c. Test and reload nginx

```bash
# Test configuration
sudo nginx -t

# If test passes, reload
sudo systemctl reload nginx
```

</details>

### Step 9: Verify CSS Loading (CRITICAL FOR NEXT.JS)

After deployment, VERIFY that CSS loads correctly:

```bash
# Check nginx access log - CSS should return HTTP 200
sudo grep "_next/static/css" /var/log/nginx/access.log | tail -5

# Expected: HTTP 200 responses
# If HTTP 302: Static location block missing (go back to Step 8b)
# If HTTP 404: Next.js built without basePath (rebuild required)
```

**Troubleshooting: Page Loads Without CSS**

| Symptom | Fix |
|---------|-----|
| Browser shows HTTP 302 for CSS | Add static location block (Step 8b) |
| Browser shows HTTP 404 for CSS | Rebuild: `sg docker -c 'docker compose build --no-cache dashboard'` |
| Browser shows HTTP 200 but no CSS | Hard refresh: Cmd+Shift+R or Ctrl+Shift+F5 |

**Quick diagnostic script:**

```bash
cd /home/{Config.EC2_USER}/deployments/{app_name}

# 1. Check next.config.js has basePath
cat dashboard/next.config.js | grep -E "basePath|assetPrefix"

# 2. Check nginx has static location
sudo grep -A5 "{app_name}/_next/static" /etc/nginx/sites-available/auth-gateway

# 3. Check CSS requests in nginx log
sudo grep "_next/static" /var/log/nginx/access.log | tail -10
```

---

### Step 10: Verify Deployment

**⚠️ Use YOUR allocated ports from Step 6!**

```bash
# Check all containers are running
sg docker -c 'docker-compose ps'

# Test frontend locally (use YOUR dashboard port)
curl http://localhost:YOUR_DASHBOARD_PORT/{app_name}/

# Test backend API locally (use YOUR backend port)
curl http://localhost:YOUR_BACKEND_PORT/api/

# Test public HTTPS access (will redirect to auth)
curl -k -I https://{instance_ip}/{app_name}/

# Test API through nginx
curl -k https://{instance_ip}/{app_name}/api/
```

## Important Rules

1. **Permissions**
   - ASK ME before running sudo commands
   - Use `sg docker -c '...'` for docker commands if permission issues occur

2. **Documentation**
   - Document what you set up so I can maintain it later
   - Note any port changes, configuration modifications, etc.

---

## Quick Reference: Port Allocation Decision Tree

```
START
  ↓
Check running containers: docker ps --format "table {{{{.Ports}}}}"
  ↓
Are default ports (3000, 8000, 5432) free?
  ↓
YES → Use default ports, skip to Step 7 (Deploy)
  ↓
NO → Find next available ports (increment by 1)
  ↓
Update docker-compose.yml with sed commands
  ↓
📝 WRITE DOWN YOUR PORTS! You'll need them for nginx
  ↓
Continue to Step 7 (Deploy)
```

---

## Common Mistakes to Avoid

### ❌ Mistake 1: Forgetting to check ports
**Result:** Docker fails with "address already in use"
**Fix:** Always run `docker ps --format "table {{{{.Ports}}}}"` first

### ❌ Mistake 2: Using wrong port in nginx
**Result:** Frontend shows "Cannot connect to backend"
**Fix:** Use the ACTUAL ports from your docker-compose.yml, not example ports

### ❌ Mistake 3: Forgetting API location block
**Result:** Frontend loads but API calls fail with 404
**Fix:** Add BOTH frontend AND API location blocks to nginx

### ❌ Mistake 4: Changing container port (right side)
**Result:** Containers fail to communicate internally
**Fix:** Only change HOST port (left side): `"3002:3000"` not `"3000:3002"`

### ❌ Mistake 5: Not reloading nginx after changes
**Result:** Changes don't take effect
**Fix:** Always run `sudo systemctl reload nginx` after config changes

### ❌ Mistake 6: Modifying LOCAL files with cloud URLs
**Result:** Local development breaks after deployment
**Fix:** Only make cloud URL changes ON THE SERVER, keep local files using localhost

---

## Troubleshooting Guide

### ⚠️ Page loads without CSS (looks like 1990s webpage)

**Problem:** Next.js page loads but has NO styling - looks like plain HTML.

**Root Cause:** Static assets (_next/static/) require special nginx configuration without auth.

**Solution Checklist:**
1. ✅ Check if static location block exists:
   ```bash
   sudo grep -A5 "{app_name}/_next/static" /etc/nginx/sites-available/auth-gateway
   ```

2. ✅ If missing, add it (see Step 8b)

3. ✅ Check nginx logs for CSS requests:
   ```bash
   sudo grep "_next/static/css" /var/log/nginx/access.log | tail -5
   ```
   - HTTP 200 = Good
   - HTTP 302 = Missing static block (add Step 8b)
   - HTTP 404 = Wrong basePath in build (rebuild required)

4. ✅ If HTTP 404, rebuild with correct config:
   ```bash
   cd /home/{Config.EC2_USER}/deployments/{app_name}
   sg docker -c 'docker compose build --no-cache dashboard'
   sg docker -c 'docker compose up -d'
   ```

---

### "Cannot connect to backend" in dashboard

**Problem:** Frontend loads but shows offline/cannot connect to backend.

**Root Cause:** Usually the API location block is missing OR using wrong port in nginx.

**Solution Checklist:**
1. ✅ Check API location block exists in nginx:
   ```bash
   sudo grep -A10 "location /{app_name}/api/" /etc/nginx/sites-available/auth-gateway
   ```

2. ✅ Verify nginx backend port matches docker-compose.yml:
   ```bash
   # Check what port backend is actually using
   docker ps | grep backend
   # Compare with nginx config
   sudo grep "proxy_pass.*{app_name}" /etc/nginx/sites-available/auth-gateway
   ```

3. ✅ Check backend is accessible locally (use YOUR port):
   ```bash
   curl http://localhost:YOUR_BACKEND_PORT/api/
   ```

4. ✅ Rebuild dashboard if NEXT_PUBLIC_API_URL was wrong:
   ```bash
   docker-compose build dashboard && docker-compose up -d dashboard
   ```

### "Cannot GET /{app_name}/"

**Problem:** Nginx routes to app but app returns 404.

**Solution:**
1. For Next.js: Verify `basePath: '/{app_name}'` in next.config.js
2. Verify `trailingSlash: true` in next.config.js
3. Rebuild dashboard with correct basePath
4. Check nginx proxy_pass doesn't have trailing slash

### Port conflicts

**Problem:** `address already in use` error when starting Docker.

**Solution:**
1. Find what's using the port: `sudo lsof -i :PORT`
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
sudo usermod -aG docker {Config.EC2_USER}

# Use sg for immediate access (without logout)
sg docker -c 'docker-compose up -d'

# Or reconnect SSH session for group membership to take effect
```

## 🔄 Post-Deployment: Return to Localhost (MANDATORY)

**CRITICAL: Before ending this session, you MUST restore local files for local development!**

### Checklist - Verify ALL of these on LOCAL machine:

#### 1. docker-compose.yml - URLs must be localhost:
```yaml
# ✅ CORRECT for local development:
- NEXT_PUBLIC_API_URL=http://localhost:8000/api

# ❌ WRONG - this is for SERVER only:
- NEXT_PUBLIC_API_URL=https://{instance_ip}/{app_name}/api
```

#### 2. docker-compose.yml - Remove deployment-specific container names:
```yaml
# ✅ CORRECT for local development (generic or omitted):
container_name: backend
container_name: dashboard
# OR simply remove container_name lines entirely

# ❌ WRONG - deployment-specific names should be on SERVER only:
container_name: {app_name}-backend
container_name: {app_name}-dashboard
```

#### 3. next.config.js - Remove basePath for local dev:
```javascript
// ✅ CORRECT for local development:
const nextConfig = {{
  reactStrictMode: true,
  // No basePath or assetPrefix for local dev
}}

// ❌ WRONG - basePath is for SERVER only:
basePath: '/{app_name}',
assetPrefix: '/{app_name}',
```

### Quick Fix Commands (run on LOCAL machine):
```bash
# Check for deployment-specific names
grep -n "container_name:" docker-compose.yml

# Check for cloud URLs
grep -n "{instance_ip}" docker-compose.yml

# Check next.config.js
grep -n "basePath" dashboard/next.config.js
```

**⚠️ DO NOT end this session until local files are clean for local development!**

---

## 📋 FINAL STEP: Display Deployment Completion Summary

**After deployment is complete, display this summary to the user:**

```
════════════════════════════════════════════════════════════════════════════════
                        ✅ DEPLOYMENT COMPLETE
════════════════════════════════════════════════════════════════════════════════

  App Name: {app_name}
  Deployment Mode: {'🔄 UPDATE' if is_update else '🆕 NEW deployment'}
  Completed: [current timestamp]

────────────────────────────────────────────────────────────────────────────────
  WHAT WAS DEPLOYED
────────────────────────────────────────────────────────────────────────────────

  [Fill in actual values from deployment:]
  • Frontend: [framework] on port [actual port]
  • Backend: [framework] on port [actual port]
  • Database: [type] on port [actual port]
  • Total containers: [count]

────────────────────────────────────────────────────────────────────────────────
  ACCESS YOUR APPLICATION
────────────────────────────────────────────────────────────────────────────────

  🌐 Public URL:     https://{instance_ip}/{app_name}/
  🔌 API Endpoint:   https://{instance_ip}/{app_name}/api/
  📊 Monitor:        https://{instance_ip}/deploy/activity
  🔐 Auth:           OAuth2 (login required)

────────────────────────────────────────────────────────────────────────────────
  CONFIGURATION APPLIED (ON SERVER)
────────────────────────────────────────────────────────────────────────────────

  ✅ Next.js basePath: '/{app_name}'
  ✅ NEXT_PUBLIC_API_URL: https://{instance_ip}/{app_name}/api
  ✅ Nginx frontend location: /{app_name}/
  ✅ Nginx API location: /{app_name}/api/

────────────────────────────────────────────────────────────────────────────────
  LOCAL DEVELOPMENT STATUS (VERIFY THESE!)
────────────────────────────────────────────────────────────────────────────────

  Check local docker-compose.yml:
  ✅ NEXT_PUBLIC_API_URL=http://localhost:8000/api (NOT cloud URL)
  ✅ No deployment-specific container_name (or use generic names)
  ✅ No cloud URLs anywhere in local files
  ✅ next.config.js has NO basePath (or basePath: '')

  If any of these are wrong, fix them NOW before returning to local dev!

────────────────────────────────────────────────────────────────────────────────
  MANAGEMENT COMMANDS
────────────────────────────────────────────────────────────────────────────────

  # SSH to server
  ssh -i capsule-deploy.pem {Config.EC2_USER}@{instance_ip}

  # Check status
  cd /home/{Config.EC2_USER}/deployments/{app_name} && docker-compose ps

  # View logs
  docker-compose logs -f

  # Restart services
  sg docker -c 'docker-compose restart'

  # Stop services
  sg docker -c 'docker-compose down'

  # Start services
  sg docker -c 'docker-compose up -d'

────────────────────────────────────────────────────────────────────────────────
  ISSUES ENCOUNTERED
────────────────────────────────────────────────────────────────────────────────

  [List any issues and how they were resolved, or "None"]

════════════════════════════════════════════════════════════════════════════════
  Deployment Kit ID: {timestamp} UTC
  Generated for: {email}
════════════════════════════════════════════════════════════════════════════════
```

---

**Generated by Deploy Portal**
**Deployment Kit ID**: {timestamp} UTC
**For**: {email}
"""

    # Detect app framework and requirements
    is_nextjs = app_type in ['nextjs', 'node', 'docker'] and 'next' in app_type.lower()
    has_backend = app_type in ['docker', 'multi-service']

    # Enhanced config.json with app details
    config_json = json.dumps({
        'app_name': app_name,
        'app_type': app_type,
        'deploy_mode': deploy_mode,
        'auth_mode': auth_mode,
        'is_update': is_update,
        'ec2_host': instance_ip,
        'ec2_user': Config.EC2_USER,
        'ssh_key_file': 'capsule-deploy.pem',
        'deployment_path': f'/home/{Config.EC2_USER}/deployments/{app_name}',
        'url_path': f'/{app_name}/',
        'generated_for': email,
        'generated_at': datetime.utcnow().isoformat() + 'Z',
        'source_ip': ip,
        'timestamp': version,  # Use version format
        'deployment_version': version,
        'portal_version': DEPLOYMENT_VERSION,
        'dashboard_api_key': dashboard_api_key,
        # NEW FIELDS for framework detection
        'app_framework': f'{app_type}' if app_type else 'unknown',
        'has_separate_backend': has_backend,
        'requires_nginx_static_block': is_nextjs  # True for Next.js apps
    }, indent=2)

    # Generate QUICKSTART.md
    quickstart = f"""# QUICKSTART - Deploy {app_name}

## First Time: Unzip and Deploy

**Step 1:** Run this in your Downloads folder:
```bash
unzip deployment-kit-{app_name}-{timestamp}.zip && cd deployment-kit-{app_name}-{timestamp} && cp deploy-skill.yaml ~/.config/claude/skills/deploy.yaml && echo "✅ Skill installed!"
```

**Step 2:** Move ZIP to your project and deploy:
```bash
cp ~/Downloads/deployment-kit-{app_name}-{timestamp}.zip ~/your-project/
cd ~/your-project
claude-code
```

Then type: `/deploy`

Done! Your app is deployed. 🚀

---

## Future Deployments: Use Deploy Command

Download new kit → Move to project → Type `/deploy`

**What happens automatically:**
1. ✅ Skill checks the ZIP's version
2. ✅ If ZIP has newer skill → auto-updates itself
3. ✅ Asks you to run `/deploy` again
4. ✅ Deploys with the latest version

---

## Summary

- **First time**: Unzip and deploy (installs skill, then deploy)
- **Future**: Use deploy command (`/deploy` - auto-updates from ZIP if needed)

**Kit Version**: {version} UTC
**App URL**: https://{instance_ip}/{app_name}/
**Generated for**: {email}

---

## Troubleshooting: Page Without CSS

If page loads but has no styling (looks like plain HTML):

```bash
# Check nginx logs
sudo grep "_next/static/css" /var/log/nginx/access.log | tail -5

# If HTTP 302: Add static location block (see CLAUDE_PROMPT.md Step 8b)
# If HTTP 404: Rebuild dashboard
cd /home/{Config.EC2_USER}/deployments/{app_name}
sg docker -c 'docker compose build --no-cache dashboard'
sg docker -c 'docker compose up -d'
```

---

**Manual option**: See CLAUDE_PROMPT.md for step-by-step deployment.
"""

    # Load automation scripts
    automation_scripts = load_automation_scripts()

    # Generate environment template
    env_template = generate_env_template(app_name, app_type, dashboard_api_key)

    # Load and version the deployment skill
    skill_path = os.path.join(os.path.dirname(__file__), Config.SKILL_FILE_PATH)
    try:
        with open(skill_path, 'r') as f:
            skill_content = f.read()
        # Replace version placeholder with actual version
        skill_content = skill_content.replace('DEPLOYMENT_VERSION_PLACEHOLDER', version)
    except FileNotFoundError:
        skill_content = None  # Skill file optional for backward compatibility

    # Create zip file
    zip_buffer = io.BytesIO()
    folder_name = f"deployment-kit-{app_name}-{timestamp}"

    with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zf:
        # Core files
        zf.writestr(f"{folder_name}/capsule-deploy.pem", ssh_key)
        zf.writestr(f"{folder_name}/QUICKSTART.md", quickstart)  # Simple instructions first!
        zf.writestr(f"{folder_name}/README.md", readme)
        zf.writestr(f"{folder_name}/CLAUDE_PROMPT.md", claude_prompt)
        zf.writestr(f"{folder_name}/config.json", config_json)
        zf.writestr(f"{folder_name}/.env.example", env_template)

        # Add deployment skill if available
        if skill_content:
            zf.writestr(f"{folder_name}/{Config.SKILL_FILE_PATH}", skill_content)

        # Automation scripts
        for script_name, script_content in automation_scripts.items():
            file_path = f"{folder_name}/automation/{script_name}"
            zf.writestr(file_path, script_content)
            # Preserve execute permissions for .sh files
            if script_name.endswith('.sh'):
                info = zf.getinfo(file_path)
                info.external_attr = 0o755 << 16  # rwxr-xr-x

    zip_buffer.seek(0)
    return zip_buffer, None

def generate_deployment_kit(email, ip):
    """Generate a zip file with SSH key and instructions"""
    instance_ip = Config.get_instance_ip()

    # Read the SSH private key
    try:
        with open(Config.SSH_KEY_PATH, 'r') as f:
            ssh_key = f.read()
    except FileNotFoundError:
        return None, "SSH key not found. Please contact administrator."

    # Create README.md
    readme = f"""# Capsule Cloud Deployment Kit

Generated for: {email}
Generated at: {datetime.utcnow().isoformat()}Z
Your IP: {ip}

## Quick Start

1. Open terminal in this directory

2. Fix key permissions:
   ```bash
   chmod 600 capsule-deploy.pem
   ```

3. Test SSH connection:
   ```bash
   ssh -i capsule-deploy.pem {Config.EC2_USER}@{instance_ip}
   ```

4. Open Claude Code in your project directory and give it the CLAUDE_PROMPT.md file

## Monitoring

View live activity at: https://[your-domain]/deploy/activity

## Support

If you have issues connecting, ensure:
- Your IP ({ip}) hasn't changed
- The .pem file has correct permissions (chmod 600)
- You're using the correct username ({Config.EC2_USER})
"""

    # Create CLAUDE_PROMPT.md
    claude_prompt = f"""# Deploy My Application to Cloud

I need you to deploy this project to our cloud server.

## Connection Details

- **Host**: {instance_ip}
- **User**: {Config.EC2_USER}
- **SSH Key**: Use the capsule-deploy.pem file in this directory

## Setup Steps

First, fix the SSH key permissions:
```bash
chmod 600 /path/to/this/directory/capsule-deploy.pem
```

## Your Task

1. Analyze this project directory to understand:
   - What language/framework is it?
   - Does it have a Dockerfile?
   - What dependencies does it need?
   - What environment variables are required?

2. SSH into the server:
   ```bash
   ssh -i /path/to/capsule-deploy.pem {Config.EC2_USER}@{instance_ip}
   ```

3. Create a deployment directory:
   ```bash
   mkdir -p /home/{Config.EC2_USER}/deployments/[project-name]
   ```

4. Copy the project files using scp:
   ```bash
   scp -i /path/to/capsule-deploy.pem -r ./* {Config.EC2_USER}@{instance_ip}:~/deployments/[project-name]/
   ```

5. On the server, set up and run the application:
   - Install dependencies
   - Build if needed (docker build, npm build, etc.)
   - Configure environment variables (ASK ME about any secrets)
   - Start the application
   - Ensure it stays running (use docker, systemd, or screen/tmux)

6. Report back:
   - What URL/port is the app running on?
   - What commands do I need to start/stop it?
   - Any issues encountered?

## Important Rules

- **DO NOT** copy .env files containing secrets directly - ask me for secret values
- **DO** ask before running any sudo commands
- **DO** use Docker if a Dockerfile exists
- **DO** document what you set up so I can maintain it later

## What's in My Project?

[Claude: Analyze the current directory and describe what you find]
"""

    # Create config.json
    version = datetime.utcnow().strftime(Config.DEPLOYMENT_VERSION_FORMAT)
    config_json = f'''{{
    "ec2_host": "{instance_ip}",
    "ec2_user": "{Config.EC2_USER}",
    "ssh_key_file": "capsule-deploy.pem",
    "generated_for": "{email}",
    "generated_at": "{datetime.utcnow().isoformat()}Z",
    "source_ip": "{ip}",
    "deployment_version": "{version}",
    "portal_version": "{DEPLOYMENT_VERSION}"
}}'''

    # Create zip file in memory
    zip_buffer = io.BytesIO()
    timestamp = version  # Use version format for consistency
    folder_name = f"deployment-kit-{timestamp}"

    with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(f"{folder_name}/capsule-deploy.pem", ssh_key)
        zf.writestr(f"{folder_name}/README.md", readme)
        zf.writestr(f"{folder_name}/CLAUDE_PROMPT.md", claude_prompt)
        zf.writestr(f"{folder_name}/config.json", config_json)

    zip_buffer.seek(0)
    return zip_buffer, None

def delete_app(app_name):
    """Delete a deployed app and clean up all configurations"""
    # Validate app name to prevent directory traversal and command injection
    if not app_name or '..' in app_name or '/' in app_name or not re.match(r'^[a-z0-9][a-z0-9-]{0,62}$', app_name):
        return False, "Invalid app name"

    try:
        import subprocess

        # Get path to cleanup script
        script_path = os.path.join(os.path.dirname(__file__), 'scripts', 'delete_deployment.sh')

        if not os.path.exists(script_path):
            return False, f"Cleanup script not found at {script_path}"

        # Execute comprehensive cleanup script
        result = subprocess.run(
            ['/bin/bash', script_path, app_name],
            capture_output=True,
            text=True,
            timeout=300  # 5 minute timeout
        )

        # Parse output
        stdout = result.stdout
        stderr = result.stderr

        if result.returncode == 0:
            # Extract log file path from output
            log_file = None
            for line in stdout.split('\n'):
                if 'Cleanup log:' in line:
                    log_file = line.split('Cleanup log:')[1].strip()
                    break

            success_msg = f"App '{app_name}' deleted successfully."
            if log_file:
                success_msg += f"\n\nCleanup log: {log_file}"

            # Show summary from script output
            if '===============================================' in stdout:
                summary_start = stdout.find('Cleanup Summary')
                if summary_start > 0:
                    summary = stdout[summary_start:]
                    success_msg += f"\n\n{summary}"

            return True, success_msg
        else:
            error_msg = f"Cleanup script failed (exit code {result.returncode})"
            if stderr:
                error_msg += f"\n\nErrors:\n{stderr}"
            if stdout:
                error_msg += f"\n\nOutput:\n{stdout[-500:]}"  # Last 500 chars
            return False, error_msg

    except subprocess.TimeoutExpired:
        return False, "Cleanup script timed out after 5 minutes"
    except Exception as e:
        return False, f"Failed to execute cleanup: {str(e)}"

def scan_deployed_apps():
    """Scan the deployments directory and return info about all deployed apps"""
    apps = []
    deployment_root = Config.DEPLOYMENT_ROOT

    if not os.path.exists(deployment_root):
        return apps

    # Get all subdirectories in deployments folder
    for app_name in os.listdir(deployment_root):
        app_path = os.path.join(deployment_root, app_name)

        # Skip hidden files and non-directories
        if app_name.startswith('.') or not os.path.isdir(app_path):
            continue

        app_info = {
            'name': app_name,
            'path': app_path,
            'status': 'unknown',
            'url': f'https://{Config.get_instance_ip()}/{app_name}/',
            'services': [],
            'ports': [],
            'has_docker_compose': False,
            'created_at': None,
            'last_modified': None
        }

        # Get creation and modification times
        try:
            stat_info = os.stat(app_path)
            app_info['created_at'] = datetime.fromtimestamp(stat_info.st_ctime).strftime('%Y-%m-%d %H:%M')
            app_info['last_modified'] = datetime.fromtimestamp(stat_info.st_mtime).strftime('%Y-%m-%d %H:%M')
        except:
            pass

        # Check for docker-compose.yml
        docker_compose_path = os.path.join(app_path, 'docker-compose.yml')
        if os.path.exists(docker_compose_path):
            app_info['has_docker_compose'] = True

            # Try to parse docker-compose.yml for services and ports
            try:
                with open(docker_compose_path, 'r') as f:
                    content = f.read()

                    # Extract service names (simple parsing)
                    if 'services:' in content:
                        lines = content.split('\n')
                        in_services = False
                        for line in lines:
                            if 'services:' in line:
                                in_services = True
                                continue
                            if in_services and line and not line.startswith(' '):
                                break
                            if in_services and line.strip() and ':' in line and line.startswith('  '):
                                service_name = line.strip().split(':')[0]
                                if service_name not in ['environment', 'volumes', 'ports', 'depends_on', 'build']:
                                    app_info['services'].append(service_name)

                    # Extract ports
                    import re
                    port_pattern = r'"(\d+):\d+"'
                    ports = re.findall(port_pattern, content)
                    app_info['ports'] = ports
            except:
                pass

            # Check docker-compose status
            try:
                import subprocess
                result = subprocess.run(
                    ['docker-compose', 'ps', '-q'],
                    cwd=app_path,
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                if result.returncode == 0 and result.stdout.strip():
                    app_info['status'] = 'running'
                else:
                    app_info['status'] = 'stopped'
            except:
                app_info['status'] = 'unknown'

        apps.append(app_info)

    # Sort by creation time (newest first)
    apps.sort(key=lambda x: x['created_at'] or '', reverse=True)

    return apps

def get_activity_logs(limit=100):
    """Read recent activity from SSH session logs"""
    logs = []
    log_dir = Config.ACTIVITY_LOG_DIR

    if not os.path.exists(log_dir):
        return logs

    # Get all log files, sorted by modification time (newest first)
    log_files = glob.glob(os.path.join(log_dir, '*.log'))
    log_files.sort(key=os.path.getmtime, reverse=True)

    for log_file in log_files[:20]:  # Check last 20 log files
        try:
            filename = os.path.basename(log_file)
            # Parse filename: YYYYMMDD-HHMMSS-USER-IP.log
            parts = filename.replace('.log', '').split('-')
            if len(parts) >= 4:
                date_str = f"{parts[0]}-{parts[1]}"
                user = parts[2] if len(parts) > 2 else 'unknown'
                ip = parts[3] if len(parts) > 3 else 'unknown'
            else:
                date_str = datetime.fromtimestamp(os.path.getmtime(log_file)).strftime('%Y%m%d-%H%M%S')
                user = 'unknown'
                ip = 'unknown'

            # Read last N lines of the file
            with open(log_file, 'r', errors='ignore') as f:
                lines = f.readlines()[-50:]  # Last 50 lines per file

            for line in lines:
                line = line.strip()
                if line and not line.startswith('\x1b'):  # Skip ANSI escape sequences
                    logs.append({
                        'timestamp': date_str,
                        'user': user,
                        'ip': ip,
                        'content': line[:200]  # Truncate long lines
                    })
        except Exception as e:
            print(f"Error reading log file {log_file}: {e}")

    return logs[:limit]

# Routes

@app.route('/')
def landing_page():
    """Capsule landing page"""
    email, _ = get_user_info()

    # Count deployed apps
    deployed_count = 0
    registry_path = Config.REGISTRY_FILE
    if os.path.exists(registry_path):
        try:
            with open(registry_path, 'r') as f:
                registry = json.load(f)
                deployed_count = len([app for app in registry.values() if app.get('status') == 'active'])
        except:
            pass

    # Get recent activity (last 5 entries)
    recent_activity = []
    try:
        activity_logs = get_activity_logs(limit=5)
        for log in activity_logs:
            recent_activity.append({
                'time': log['timestamp'],
                'user': log['user'],
                'content': log['content']
            })
    except:
        pass

    return render_template('index.html',
                         email=email,
                         deployed_count=deployed_count,
                         recent_activity=recent_activity)

@app.route('/deploy/apps')
def apps_catalog():
    """App catalog page - show all deployed apps"""
    email, _ = get_user_info()

    # Scan for deployed apps
    apps = scan_deployed_apps()

    # Calculate stats
    running_count = sum(1 for app in apps if app['status'] == 'running')
    stopped_count = sum(1 for app in apps if app['status'] == 'stopped')

    return render_template('apps_catalog.html',
                         email=email,
                         apps=apps,
                         running_count=running_count,
                         stopped_count=stopped_count)
@app.route('/deploy/apps/security-review/<app_name>')
def security_review_page(app_name):
    """Security review page for an app"""
    email, _ = get_user_info()

    # Validate app exists
    app_path = os.path.join('/home/ubuntu/deployments', app_name)
    if not os.path.isdir(app_path):
        return "App not found", 404

    # Scan app for services (initialize reviews if needed)
    try:
        import sys
        sys.path.insert(0, '/home/ubuntu/src/deploy-portal-security')
        from security_review_api import get_app_services
        import database

        services = get_app_services(app_name)
        for service in services:
            existing = database.get_review(app_name, service)
            if not existing:
                database.create_or_update_review(
                    app_name=app_name,
                    service_name=service,
                    status='pending'
                )

        # Update app security score
        database.update_app_security_score(app_name)
    except Exception as e:
        print(f"Error initializing security reviews: {e}")

    # Render template from deploy-portal-security
    security_template_path = '/home/ubuntu/src/deploy-portal-security/security_dashboard/templates/security_review.html'

    try:
        with open(security_template_path, 'r') as f:
            template_content = f.read()

        # Simple template rendering (replace variables)
        from flask import render_template_string
        return render_template_string(template_content, email=email, app_name=app_name)
    except Exception as e:
        print(f"Error loading security review template: {e}")
        return f"Error loading security review page: {str(e)}", 500


@app.route('/status')
def system_status():
    """System status page - placeholder for Phase 5"""
    email, _ = get_user_info()

    return render_template('system_status.html', email=email) if os.path.exists(
        os.path.join(app.template_folder, 'system_status.html')
    ) else (
        f"<html><body><h1>System Status</h1><p>Coming in Phase 5</p><a href='/'>Back to Home</a></body></html>",
        200,
        {'Content-Type': 'text/html'}
    )

@app.route('/docs')
def docs_hub():
    """Documentation hub"""
    email, _ = get_user_info()
    return render_template('docs_index.html', email=email)

@app.route('/docs/architecture')
def docs_architecture():
    """Architecture documentation with visual diagrams"""
    email, _ = get_user_info()

    # Read the architecture markdown file
    docs_path = os.path.join(os.path.dirname(__file__), 'docs', 'ARCHITECTURE.md')

    try:
        with open(docs_path, 'r') as f:
            content = f.read()

        return render_template('docs_markdown.html',
                             email=email,
                             title='Architecture Overview',
                             content=content,
                             breadcrumbs=[
                                 {'name': 'Docs', 'url': '/docs'},
                                 {'name': 'Architecture', 'url': None}
                             ])
    except FileNotFoundError:
        return "Architecture documentation not found", 404

@app.route('/docs/mac-deployment')
def docs_mac_deployment():
    """Mac deployment guide"""
    email, _ = get_user_info()

    # Read the Mac deployment guide
    docs_path = os.path.join(os.path.dirname(__file__), 'docs', 'MAC_DEPLOYMENT_GUIDE.md')

    try:
        with open(docs_path, 'r') as f:
            content = f.read()

        return render_template('docs_markdown.html',
                             email=email,
                             title='Mac Deployment Guide',
                             content=content,
                             breadcrumbs=[
                                 {'name': 'Docs', 'url': '/docs'},
                                 {'name': 'Mac Deployment', 'url': None}
                             ])
    except FileNotFoundError:
        return "Mac deployment guide not found", 404

@app.route('/deploy/')
def deploy_provision():
    email, ip = get_user_info()
    whitelisted = is_ip_whitelisted(ip)
    instance_ip = Config.get_instance_ip()

    return render_template('provision.html',
                         email=email,
                         ip=ip,
                         whitelisted=whitelisted,
                         instance_ip=instance_ip)

@app.route('/deploy/provision', methods=['POST'])
def provision():
    email, ip = get_user_info()
    success, message = whitelist_ip(ip, email)

    return jsonify({
        'success': success,
        'message': message,
        'ip': ip,
        'email': email
    })

@app.route('/deploy/check-name', methods=['POST'])
def check_app_name():
    """Check if app name is available or exists for update"""
    data = request.get_json()
    app_name = data.get('app_name', '').lower().strip()

    valid, error = validate_app_name(app_name)

    if not valid:
        return jsonify({'available': False, 'exists': False, 'error': error})

    # Check if app already exists in deployments
    deployment_path = os.path.join(Config.DEPLOYMENT_ROOT, app_name)
    app_exists = os.path.isdir(deployment_path)

    return jsonify({
        'available': True,
        'exists': app_exists,
        'deployment_path': deployment_path if app_exists else None
    })

@app.route('/deploy/download-kit', methods=['POST'])
def download_kit():
    email, ip = get_user_info()

    # Get form data
    app_name = request.form.get('app_name', '').lower().strip()
    app_type = request.form.get('app_type', 'other')
    deploy_mode = request.form.get('deploy_mode', 'new')  # 'new' or 'update'
    auth_mode = request.form.get('auth_mode', 'cognito')  # 'cognito', 'internal', or 'none'

    # Validate app name
    if not app_name:
        return jsonify({'error': 'App name is required'}), 400

    valid, error = validate_app_name(app_name)
    if not valid:
        return jsonify({'error': error}), 400

    # Ensure IP is whitelisted first
    if not is_ip_whitelisted(ip):
        whitelist_ip(ip, email)

    # Generate app-specific deployment kit
    zip_buffer, error = generate_app_deployment_kit(email, ip, app_name, app_type, deploy_mode, auth_mode)

    if error:
        return jsonify({'error': error}), 500

    # Use version format for ZIP filename
    version = datetime.utcnow().strftime(Config.DEPLOYMENT_VERSION_FORMAT)
    return send_file(
        zip_buffer,
        mimetype='application/zip',
        as_attachment=True,
        download_name=f'deployment-kit-{app_name}-{version}.zip'
    )

@app.route('/deploy/activity')
def activity():
    email, ip = get_user_info()
    return render_template('activity.html', email=email)

@app.route('/deploy/api/activity')
def api_activity():
    logs = get_activity_logs(limit=100)
    return jsonify(logs)

@app.route('/deploy/api/activity/stream')
def activity_stream():
    """Server-sent events for live activity updates"""
    def generate():
        last_count = 0
        while True:
            logs = get_activity_logs(limit=10)
            current_count = len(logs)
            if current_count != last_count:
                yield f"data: {jsonify(logs).get_data(as_text=True)}\n\n"
                last_count = current_count
            time.sleep(2)

    return Response(generate(), mimetype='text/event-stream')

@app.route('/deploy/apps/delete/<app_name>', methods=['POST'])
def delete_app_endpoint(app_name):
    """Delete a deployed app"""
    email, _ = get_user_info()

    # Perform deletion
    success, message = delete_app(app_name)

    return jsonify({
        'success': success,
        'message': message,
        'app_name': app_name
    })

def cleanup_stale_sessions():
    """Remove sessions older than SESSION_TIMEOUT_MINUTES"""
    from datetime import timedelta
    now = datetime.utcnow()
    timeout = timedelta(minutes=Config.SESSION_TIMEOUT_MINUTES)

    stale_users = [
        user for user, session in active_deployments.items()
        if now - session['started_at'] > timeout
    ]

    for user in stale_users:
        del active_deployments[user]

    return len(stale_users)

@app.route('/api/deployment/version')
def api_deployment_version():
    """Return current deployment system version"""
    return jsonify({
        'version': DEPLOYMENT_VERSION,
        'version_display': f'{DEPLOYMENT_VERSION} UTC',
        'format': Config.DEPLOYMENT_VERSION_FORMAT,
        'timezone': 'UTC',
        'generated_at': DEPLOYMENT_VERSION
    })

@app.route('/api/deployment/active-sessions')
def api_active_sessions():
    """List active deployment sessions for current user or all users"""
    email, _ = get_user_info()

    # Cleanup stale sessions first
    cleanup_stale_sessions()

    # Return sessions for current user
    user_sessions = []
    for user, session in active_deployments.items():
        if user == email:
            user_sessions.append({
                'user': user,
                'app_name': session['app_name'],
                'started_at': session['started_at'].isoformat() + 'Z',
                'version': session['version']
            })

    return jsonify({
        'sessions': user_sessions,
        'count': len(user_sessions)
    })

@app.route('/api/deployment/register-session', methods=['POST'])
def api_register_session():
    """Register a new deployment session"""
    email, _ = get_user_info()
    data = request.get_json()

    app_name = data.get('app_name')
    version = data.get('version', DEPLOYMENT_VERSION)

    if not app_name:
        return jsonify({'error': 'app_name is required'}), 400

    # Cleanup stale sessions first
    cleanup_stale_sessions()

    # Register session
    active_deployments[email] = {
        'app_name': app_name,
        'started_at': datetime.utcnow(),
        'version': version
    }

    return jsonify({
        'success': True,
        'message': f'Session registered for {app_name}',
        'session': {
            'user': email,
            'app_name': app_name,
            'version': version
        }
    })

@app.route('/api/deployment/unregister-session', methods=['POST'])
def api_unregister_session():
    """Unregister a deployment session"""
    email, _ = get_user_info()

    if email in active_deployments:
        session = active_deployments[email]
        del active_deployments[email]
        return jsonify({
            'success': True,
            'message': f'Session unregistered for {session["app_name"]}'
        })

    return jsonify({
        'success': False,
        'message': 'No active session found'
    }), 404

@app.route('/api/deployment/skill')
def api_deployment_skill():
    """Download the latest deployment skill file"""
    skill_path = os.path.join(os.path.dirname(__file__), Config.SKILL_FILE_PATH)

    if not os.path.exists(skill_path):
        return jsonify({'error': 'Skill file not found'}), 404

    return send_file(
        skill_path,
        mimetype='text/yaml',
        as_attachment=True,
        download_name=Config.SKILL_FILE_PATH
    )

@app.route('/deploy/health')
def health():
    return jsonify({'status': 'healthy'})


# Security Dashboard (password protected)
@app.route("/security")
def security_dashboard():
    """Security dashboard - password protected"""
    # Check for password in cookie or query param
    password = request.cookies.get("security_auth") or request.args.get("password")
    
    if password != "Admin1234!":
        return render_template("security_login.html", email=get_user_info()[0])
    
    # Get security status
    import subprocess
    
    # Check AppArmor status
    try:
        apparmor_output = subprocess.check_output(["sudo", "aa-status"], text=True)
        apparmor_profiles = len([l for l in apparmor_output.split("\n") if "enforce" in l])
    except:
        apparmor_profiles = 0
    
    # Check seccomp profiles
    seccomp_profiles = len(glob.glob("/etc/seccomp/*.json"))
    
    # Check containers
    try:
        containers_output = subprocess.check_output(["docker", "ps", "-q"], text=True)
        containers_count = len([l for l in containers_output.strip().split("\n") if l])
    except:
        containers_count = 0
    
    # Check monitoring
    try:
        cron_output = subprocess.check_output(["crontab", "-l"], text=True)
        monitoring_active = "security-monitor" in cron_output
    except:
        monitoring_active = False
    
    email, ip = get_user_info()
    
    # Create data structures expected by template
    apparmor_status = {
        "enforced": apparmor_profiles,
        "complain": 0  # Could enhance this later
    }
    
    # Check containers with seccomp
    seccomp_active = 0
    deployment_root = "/home/ubuntu/deployments"
    if os.path.exists(deployment_root):
        for app_name in os.listdir(deployment_root):
            docker_compose_path = os.path.join(deployment_root, app_name, "docker-compose.yml")
            if os.path.exists(docker_compose_path):
                try:
                    with open(docker_compose_path, "r") as f:
                        dc_content = f.read()
                        if "seccomp:" in dc_content or "seccomp=" in dc_content:
                            seccomp_active += 1
                except:
                    pass
    
    seccomp_status = {
        "total": seccomp_profiles,
        "active": seccomp_active
    }
    
    container_status = {
        "secured": seccomp_active,
        "total": containers_count
    }
    
    monitoring_status = "Active" if monitoring_active else "Inactive"
    
    response = app.make_response(render_template("security.html",
        email=email,
        apparmor_status=apparmor_status,
        seccomp_status=seccomp_status,
        container_status=container_status,
        monitoring_status=monitoring_status
    ))
    
    # Set cookie
    response.set_cookie("security_auth", "Admin1234!", max_age=3600)
    return response

@app.route("/security/run-tests", methods=["GET", "POST"])
def security_run_tests():
    """Run security tests"""
    password = request.cookies.get("security_auth")
    if password != "Admin1234!":
        return jsonify({"error": "Unauthorized"}), 401
    
    import subprocess
    import re
    
    def strip_ansi(text):
        ansi_escape = re.compile(r'\x1b\[[0-9;]*m')
        return ansi_escape.sub('', text)
    
    try:
        output = subprocess.check_output(
            ["bash", "/home/ubuntu/src/deploy-portal/tests/security-tests.sh"],
            text=True,
            stderr=subprocess.STDOUT,
            timeout=30
        )
        clean_output = strip_ansi(output)
        return jsonify({"success": True, "message": clean_output})
    except subprocess.CalledProcessError as e:
        clean_output = strip_ansi(e.output)
        return jsonify({"success": False, "message": f"Tests completed with errors:\n\n{clean_output}"})
    except subprocess.TimeoutExpired:
        return jsonify({"success": False, "message": "Tests timed out after 30 seconds"})
    except Exception as e:
        return jsonify({"success": False, "message": f"Error running tests: {str(e)}"})


@app.route("/security/apps")
def security_apps():
    """List all apps with seccomp status"""
    #     password = request.cookies.get("security_auth")
    #     if password != "Admin1234!":
    #         return jsonify({"error": "Unauthorized"}), 401
    
    import subprocess
    import yaml
    
    apps = []
    deployment_root = "/home/ubuntu/deployments"
    
    if os.path.exists(deployment_root):
        for app_name in os.listdir(deployment_root):
            app_path = os.path.join(deployment_root, app_name)
            if not os.path.isdir(app_path):
                continue
            
            docker_compose_path = os.path.join(app_path, "docker-compose.yml")
            if not os.path.exists(docker_compose_path):
                continue
            
            # Check if seccomp is enabled
            seccomp_enabled = False
            seccomp_profile = None
            has_backup = False
            
            try:
                with open(docker_compose_path, "r") as f:
                    content = f.read()
                    if "seccomp:" in content or "seccomp=" in content:
                        seccomp_enabled = True
                        # Extract profile path
                        import re
                        match = re.search(r"seccomp[=:]\s*([^\s\n]+)", content)
                        if match:
                            seccomp_profile = match.group(1)
                
                # Check for backups
                backup_files = glob.glob(os.path.join(app_path, "docker-compose.yml.backup-*"))
                has_backup = len(backup_files) > 0
                
                # Get last modified time
                last_updated = datetime.fromtimestamp(os.path.getmtime(docker_compose_path)).strftime("%Y-%m-%d %H:%M")
            except:
                last_updated = None
            
            apps.append({
                "name": app_name,
                "seccomp_enabled": seccomp_enabled,
                "seccomp_profile": seccomp_profile,
                "has_backup": has_backup,
                "last_updated": last_updated
            })
    
    return jsonify({"apps": apps})

@app.route("/security/apps/<app_name>/seccomp", methods=["POST"])
def security_toggle_seccomp(app_name):
    """Enable or disable seccomp for an app"""
    #     password = request.cookies.get("security_auth")
    #     if password != "Admin1234!":
    #     return jsonify({"error": "Unauthorized"}), 401
    
    data = request.get_json()
    enable = data.get("enable", True)
    
    app_path = os.path.join("/home/ubuntu/deployments", app_name)
    docker_compose_path = os.path.join(app_path, "docker-compose.yml")
    
    if not os.path.exists(docker_compose_path):
        return jsonify({"success": False, "message": "App not found"}), 404
    
    import subprocess
    
    if enable:
        # Run inject-seccomp.sh for this specific app
        try:
            result = subprocess.run(
                ["bash", "/home/ubuntu/src/deploy-portal/security/inject-seccomp.sh", app_path],
                capture_output=True,
                text=True,
                timeout=60
            )
            
            if result.returncode == 0:
                return jsonify({"success": True, "message": f"seccomp enabled for {app_name}"})
            else:
                return jsonify({"success": False, "message": f"Failed to enable seccomp: {result.stderr}"}), 500
        except Exception as e:
            return jsonify({"success": False, "message": str(e)}), 500
    else:
        # Disable by removing security_opt from docker-compose.yml
        try:
            # Create backup first
            backup_path = f"{docker_compose_path}.backup-{datetime.utcnow().strftime("%Y%m%d-%H%M%S")}"
            subprocess.run(["cp", docker_compose_path, backup_path], check=True)
            
            # Read and modify docker-compose.yml to remove seccomp
            with open(docker_compose_path, "r") as f:
                lines = f.readlines()
            
            new_lines = []
            skip_next = False
            for line in lines:
                if "security_opt:" in line:
                    skip_next = True
                    continue
                if skip_next and ("seccomp:" in line or "seccomp=" in line or "no-new-privileges" in line):
                    continue
                else:
                    skip_next = False
                new_lines.append(line)
            
            with open(docker_compose_path, "w") as f:
                f.writelines(new_lines)
            
            # Recreate containers
            subprocess.run(["docker-compose", "up", "-d", "--force-recreate"], cwd=app_path, check=True)
            
            return jsonify({"success": True, "message": f"seccomp disabled for {app_name}"})
        except Exception as e:
            return jsonify({"success": False, "message": str(e)}), 500

@app.route("/security/apps/<app_name>/rollback", methods=["POST"])
def security_rollback_app(app_name):
    """Rollback app to previous configuration"""
    #     password = request.cookies.get("security_auth")
    #     if password != "Admin1234!":
    #     return jsonify({"error": "Unauthorized"}), 401
    
    app_path = os.path.join("/home/ubuntu/deployments", app_name)
    docker_compose_path = os.path.join(app_path, "docker-compose.yml")
    
    if not os.path.exists(docker_compose_path):
        return jsonify({"success": False, "message": "App not found"}), 404
    
    # Find latest backup
    backup_files = sorted(glob.glob(os.path.join(app_path, "docker-compose.yml.backup-*")), reverse=True)
    
    if not backup_files:
        return jsonify({"success": False, "message": "No backup found"}), 404
    
    latest_backup = backup_files[0]
    
    try:
        import subprocess
        
        # Restore backup
        subprocess.run(["cp", latest_backup, docker_compose_path], check=True)
        
        # Recreate containers
        subprocess.run(["docker-compose", "up", "-d", "--force-recreate"], cwd=app_path, check=True)
        
        return jsonify({"success": True, "message": f"Rolled back {app_name} to {os.path.basename(latest_backup)}"})
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500

@app.route("/security/logs")
def security_logs():
    """View security logs"""
    password = request.cookies.get("security_auth")
    if password != "Admin1234!":
        return jsonify({"error": "Unauthorized"}), 401
    
    log_file = "/var/log/security-monitor.log"
    
    if not os.path.exists(log_file):
        return "<h1>Security Logs</h1><p>No logs found yet.</p>"
    
    try:
        with open(log_file, "r") as f:
            lines = f.readlines()[-100:]  # Last 100 lines
        
        log_content = "".join(lines)
        return f"<html><head><title>Security Logs</title><style>body {{font-family: monospace; padding: 20px;}}</style></head><body><h1>Security Monitor Logs</h1><pre>{log_content}</pre></body></html>"
    except Exception as e:
        return f"<h1>Error</h1><p>{str(e)}</p>"


@app.route("/security/docs")
def security_docs():
    """Security documentation"""
    password = request.cookies.get("security_auth")
    if password != "Admin1234!":
        return jsonify({"error": "Unauthorized"}), 401

    try:
        with open("/home/ubuntu/src/deploy-portal/SECURITY_IMPLEMENTATION_GUIDE.md", "r") as f:
            md_content = f.read()

        # Better markdown to HTML conversion
        import re

        # Split into lines for processing
        lines = md_content.split('\n')
        html_lines = []
        in_code_block = False
        code_block = []
        in_list = False
        list_items = []
        list_type = None

        for i, line in enumerate(lines):
            # Handle code blocks
            if line.startswith('```'):
                if in_code_block:
                    # End code block
                    html_lines.append('<pre><code>' + '\n'.join(code_block) + '</code></pre>')
                    code_block = []
                    in_code_block = False
                else:
                    # Start code block
                    in_code_block = True
                continue

            if in_code_block:
                code_block.append(line)
                continue

            # Handle lists
            numbered_match = re.match(r'^(\d+)\.\s+(.+)$', line)
            bullet_match = re.match(r'^[-*]\s+(.+)$', line)

            if numbered_match or bullet_match:
                if not in_list:
                    in_list = True
                    list_type = 'ol' if numbered_match else 'ul'
                    list_items = []

                item_text = numbered_match.group(2) if numbered_match else bullet_match.group(1)
                # Process inline formatting
                item_text = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', item_text)
                item_text = re.sub(r'`([^`]+)`', r'<code>\1</code>', item_text)
                list_items.append(f'<li>{item_text}</li>')
            else:
                # End list if we were in one
                if in_list:
                    html_lines.append(f'<{list_type}>')
                    html_lines.extend(list_items)
                    html_lines.append(f'</{list_type}>')
                    in_list = False
                    list_items = []
                    list_type = None

                # Skip empty lines but preserve some spacing
                if not line.strip():
                    if html_lines and html_lines[-1] != '<br>':
                        html_lines.append('<br>')
                    continue

                # Headers
                if line.startswith('####'):
                    html_lines.append(f'<h4>{line[5:].strip()}</h4>')
                elif line.startswith('###'):
                    html_lines.append(f'<h3>{line[4:].strip()}</h3>')
                elif line.startswith('##'):
                    html_lines.append(f'<h2>{line[3:].strip()}</h2>')
                elif line.startswith('#'):
                    html_lines.append(f'<h1>{line[2:].strip()}</h1>')
                else:
                    # Regular paragraph
                    processed = line
                    # Inline formatting
                    processed = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', processed)
                    processed = re.sub(r'`([^`]+)`', r'<code>\1</code>', processed)
                    html_lines.append(f'<p>{processed}</p>')

        # Close any remaining list
        if in_list:
            html_lines.append(f'<{list_type}>')
            html_lines.extend(list_items)
            html_lines.append(f'</{list_type}>')

        html_content = '\n'.join(html_lines)

        html_template = """<!DOCTYPE html>
<html>
<head>
    <title>Security Implementation Guide</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', sans-serif;
            line-height: 1.7;
            color: #333;
            background: #f5f7fa;
            padding: 20px;
        }}
        .container {{
            max-width: 900px;
            margin: 0 auto;
            background: white;
            padding: 50px;
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }}
        .back-link {{
            display: inline-block;
            margin-bottom: 30px;
            padding: 10px 20px;
            background: #3498db;
            color: white;
            text-decoration: none;
            border-radius: 5px;
            font-weight: 500;
            transition: background 0.3s;
        }}
        .back-link:hover {{
            background: #2980b9;
        }}
        h1 {{
            color: #1a1a1a;
            font-size: 2.5em;
            margin: 30px 0 20px 0;
            padding-bottom: 15px;
            border-bottom: 4px solid #3498db;
        }}
        h2 {{
            color: #2c3e50;
            font-size: 1.8em;
            margin: 40px 0 15px 0;
            padding-bottom: 10px;
            border-bottom: 2px solid #ecf0f1;
        }}
        h3 {{
            color: #34495e;
            font-size: 1.4em;
            margin: 30px 0 12px 0;
        }}
        h4 {{
            color: #7f8c8d;
            font-size: 1.1em;
            margin: 20px 0 10px 0;
            font-weight: 600;
        }}
        p {{
            margin: 12px 0;
            line-height: 1.8;
        }}
        br {{
            display: block;
            margin: 8px 0;
            content: "";
        }}
        code {{
            background: #f8f9fa;
            padding: 3px 8px;
            border-radius: 4px;
            font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
            font-size: 0.9em;
            color: #e74c3c;
            border: 1px solid #e1e4e8;
        }}
        pre {{
            background: #2d3748;
            color: #e2e8f0;
            padding: 20px;
            border-radius: 6px;
            overflow-x: auto;
            margin: 20px 0;
            border-left: 4px solid #3498db;
        }}
        pre code {{
            background: none;
            color: #e2e8f0;
            padding: 0;
            border: none;
            font-size: 0.95em;
            line-height: 1.5;
        }}
        ul, ol {{
            margin: 15px 0 15px 30px;
            line-height: 1.8;
        }}
        ol {{
            counter-reset: item;
            list-style-type: none;
            padding-left: 0;
        }}
        ol > li {{
            counter-increment: item;
            margin: 10px 0;
            padding-left: 35px;
            position: relative;
        }}
        ol > li:before {{
            content: counter(item) ".";
            position: absolute;
            left: 0;
            font-weight: 700;
            color: #3498db;
            font-size: 1.1em;
        }}
        ul {{
            list-style-type: none;
        }}
        ul > li {{
            margin: 10px 0;
            padding-left: 25px;
            position: relative;
        }}
        ul > li:before {{
            content: "•";
            position: absolute;
            left: 0;
            color: #3498db;
            font-size: 1.3em;
            line-height: 1.2;
        }}
        li {{
            margin: 8px 0;
        }}
        strong {{
            color: #2c3e50;
            font-weight: 600;
        }}
        .content {{
            animation: fadeIn 0.5s;
        }}
        @keyframes fadeIn {{
            from {{ opacity: 0; transform: translateY(20px); }}
            to {{ opacity: 1; transform: translateY(0); }}
        }}
    </style>
</head>
<body>
    <div class='container'>
        <a href='/security' class='back-link'>← Back to Security Dashboard</a>
        <div class='content'>
            {content}
        </div>
    </div>
</body>
</html>"""

        return html_template.format(content=html_content)

    except Exception as e:
        import traceback
        return f"<h1>Error</h1><p>Could not load documentation: {str(e)}</p><pre>{traceback.format_exc()}</pre>"


# Import and register security review API
try:
    import sys
    sys.path.insert(0, "/home/ubuntu/src/deploy-portal-security")
    from security_review_api import security_review_bp
    app.register_blueprint(security_review_bp)
    print("Security Review API registered successfully")
except ImportError as e:
    print(f"Security Review API not installed: {e}")
except Exception as e:
    print(f"Error loading Security Review API: {e}")

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000, debug=False)
