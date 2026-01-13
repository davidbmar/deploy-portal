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

def generate_app_deployment_kit(email, ip, app_name, app_type):
    """Generate app-specific deployment kit with automation instructions"""
    instance_ip = Config.get_instance_ip()
    timestamp = datetime.utcnow().strftime('%Y%m%d-%H%M%S')

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

    # App-specific CLAUDE_PROMPT.md with improved template
    claude_prompt = f"""# Deploy {app_name} to Cloud

I need you to deploy this project to our cloud server with automated setup.

## Application Details

- **App Name**: {app_name}
- **App Type**: {app_type}
- **Target Directory**: `/home/{Config.EC2_USER}/deployments/{app_name}/`
- **Public URL**: `https://{instance_ip}/{app_name}/` (after setup)

## Connection Details

- **Host**: {instance_ip}
- **User**: {Config.EC2_USER}
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
rsync -avz --exclude 'node_modules' --exclude 'venv' --exclude '.git' --exclude '.next' --exclude '.env' -e "ssh -i capsule-deploy.pem" ./ {Config.EC2_USER}@{instance_ip}:~/deployments/{app_name}/
```

**IMPORTANT:**
- DO NOT copy .env files with secrets
- DO NOT copy node_modules or venv directories
- DO NOT copy build artifacts (.next, dist, build)
- DO copy package.json, requirements.txt, go.mod, docker-compose.yml, etc.

### Step 4: Check Server Prerequisites

**NEW: Before deploying, ensure the server has required tools:**

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

### Step 5: Configure Application for Subpath Deployment

**NEW: For Next.js Applications with Separate Backend:**

If this is a Next.js dashboard with a separate API backend, you MUST configure it for subpath deployment:

```bash
# 1. Update next.config.js
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

# 2. Update .env.local for dashboard
cat > dashboard/.env.local << 'EOF'
NEXT_PUBLIC_API_URL=https://{instance_ip}/{app_name}/api
NEXT_PUBLIC_API_KEY={dashboard_api_key}
EOF

# 3. Update docker-compose.yml build args
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

**NEW: For multi-service apps (frontend + backend), you need TWO nginx locations:**

#### 8a. Create upstream definition

```bash
# Add to end of /etc/nginx/sites-available/auth-gateway
sudo bash -c 'cat >> /etc/nginx/sites-available/auth-gateway << EOF

# {app_name} upstream
upstream {app_name}_backend {{
    server 127.0.0.1:3000;
}}
EOF'
```

#### 8b. Add frontend location block

```bash
# Add BEFORE the "# Health check endpoint" line
sudo bash -c 'cat > /tmp/{app_name}-location.conf << "EOF"

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
EOF

sed -i "/# Health check endpoint/r /tmp/{app_name}-location.conf" /etc/nginx/sites-available/auth-gateway'
```

#### 8c. **NEW: Add API location block (CRITICAL for frontend-backend apps)**

```bash
# Add API proxy location
sudo bash -c 'cat > /tmp/{app_name}-api-location.conf << "EOF"

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
        proxy_pass http://127.0.0.1:8000;
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

sed -i "/# Protected: {app_name}/r /tmp/{app_name}-api-location.conf" /etc/nginx/sites-available/auth-gateway'
```

#### 8d. Test and reload nginx

```bash
sudo nginx -t
sudo systemctl reload nginx
```

**Why do you need both locations?**
- `/{app_name}/` serves the frontend (Next.js dashboard)
- `/{app_name}/api/` proxies API requests to the backend
- Without the API location, the frontend will show "Cannot connect to backend"

### Step 9: Verify Deployment

```bash
# Check all containers are running
sg docker -c 'docker-compose ps'

# Test frontend locally
curl http://localhost:3000/{app_name}/

# Test backend API locally
curl http://localhost:8000/api/

# Test public HTTPS access (will redirect to auth)
curl -k -I https://{instance_ip}/{app_name}/

# Test API through nginx
curl -k https://{instance_ip}/{app_name}/api/
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
4. Check backend is accessible: `curl http://localhost:8000/api/`

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

## Post-Deployment Report

After deployment, report back:
1. ✅ Application URL: https://{instance_ip}/{app_name}/
2. ✅ Service status (all containers running)
3. ✅ Ports used (frontend, backend, database, etc.)
4. ✅ Backend connectivity verified (not showing "System Offline")
5. ❓ Any issues encountered and how they were resolved
6. 📝 Commands to manage the app:
   ```bash
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
   ```

---

**Generated by Deploy Portal**
**Deployment Kit ID**: {timestamp}
**For**: {email}
"""

    # Enhanced config.json with app details
    config_json = json.dumps({
        'app_name': app_name,
        'app_type': app_type,
        'ec2_host': instance_ip,
        'ec2_user': Config.EC2_USER,
        'ssh_key_file': 'capsule-deploy.pem',
        'deployment_path': f'/home/{Config.EC2_USER}/deployments/{app_name}',
        'url_path': f'/{app_name}/',
        'generated_for': email,
        'generated_at': datetime.utcnow().isoformat() + 'Z',
        'source_ip': ip,
        'timestamp': timestamp,
        'dashboard_api_key': dashboard_api_key
    }, indent=2)

    # Load automation scripts
    automation_scripts = load_automation_scripts()

    # Generate environment template
    env_template = generate_env_template(app_name, app_type, dashboard_api_key)

    # Create zip file
    zip_buffer = io.BytesIO()
    folder_name = f"deployment-kit-{app_name}-{timestamp}"

    with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zf:
        # Core files
        zf.writestr(f"{folder_name}/capsule-deploy.pem", ssh_key)
        zf.writestr(f"{folder_name}/README.md", readme)
        zf.writestr(f"{folder_name}/CLAUDE_PROMPT.md", claude_prompt)
        zf.writestr(f"{folder_name}/config.json", config_json)
        zf.writestr(f"{folder_name}/.env.example", env_template)

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
    config_json = f'''{{
    "ec2_host": "{instance_ip}",
    "ec2_user": "{Config.EC2_USER}",
    "ssh_key_file": "capsule-deploy.pem",
    "generated_for": "{email}",
    "generated_at": "{datetime.utcnow().isoformat()}Z",
    "source_ip": "{ip}"
}}'''

    # Create zip file in memory
    zip_buffer = io.BytesIO()
    timestamp = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
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
    deployment_path = os.path.join(Config.DEPLOYMENT_ROOT, app_name)

    if not os.path.exists(deployment_path):
        return False, f"App '{app_name}' not found"

    # Validate app name to prevent directory traversal
    if '..' in app_name or '/' in app_name:
        return False, "Invalid app name"

    try:
        # Step 1: Stop and remove docker containers
        docker_compose_path = os.path.join(deployment_path, 'docker-compose.yml')
        if os.path.exists(docker_compose_path):
            try:
                import subprocess
                # Stop and remove containers, networks, volumes
                subprocess.run(
                    ['docker-compose', 'down', '-v'],
                    cwd=deployment_path,
                    capture_output=True,
                    timeout=30
                )
            except Exception as e:
                print(f"Warning: Failed to stop docker containers: {e}")

        # Step 2: Remove from deployment registry
        registry_path = Config.REGISTRY_FILE
        if os.path.exists(registry_path):
            try:
                with open(registry_path, 'r') as f:
                    registry = json.load(f)
                if app_name in registry:
                    del registry[app_name]
                    with open(registry_path, 'w') as f:
                        json.dump(registry, f, indent=2)
            except Exception as e:
                print(f"Warning: Failed to update registry: {e}")

        # Step 3: Remove nginx configuration
        # Note: This requires manual nginx reload, we'll document what needs to be done
        nginx_cleanup_notes = f"""
To complete nginx cleanup, run on server:
sudo sed -i '/# {app_name} upstream/,/^$/d' /etc/nginx/sites-available/auth-gateway
sudo sed -i '/# Protected: {app_name}/,/location = \\/{app_name}/d' /etc/nginx/sites-available/auth-gateway
sudo nginx -t && sudo systemctl reload nginx
"""

        # Step 4: Stop systemd service if exists
        try:
            import subprocess
            subprocess.run(
                ['sudo', 'systemctl', 'stop', f'{app_name}.service'],
                capture_output=True,
                timeout=10
            )
            subprocess.run(
                ['sudo', 'systemctl', 'disable', f'{app_name}.service'],
                capture_output=True,
                timeout=10
            )
        except Exception as e:
            print(f"Warning: Failed to stop systemd service: {e}")

        # Step 5: Remove app directory
        import shutil
        shutil.rmtree(deployment_path)

        return True, f"App '{app_name}' deleted successfully. {nginx_cleanup_notes}"

    except Exception as e:
        return False, f"Failed to delete app: {str(e)}"

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
    """Check if app name is available"""
    data = request.get_json()
    app_name = data.get('app_name', '').lower().strip()

    valid, error = validate_app_name(app_name)

    if not valid:
        return jsonify({'available': False, 'error': error})

    return jsonify({'available': True})

@app.route('/deploy/download-kit', methods=['POST'])
def download_kit():
    email, ip = get_user_info()

    # Get form data
    app_name = request.form.get('app_name', '').lower().strip()
    app_type = request.form.get('app_type', 'other')

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
    zip_buffer, error = generate_app_deployment_kit(email, ip, app_name, app_type)

    if error:
        return jsonify({'error': error}), 500

    timestamp = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
    return send_file(
        zip_buffer,
        mimetype='application/zip',
        as_attachment=True,
        download_name=f'deployment-kit-{app_name}-{timestamp}.zip'
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

@app.route('/deploy/health')
def health():
    return jsonify({'status': 'healthy'})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000, debug=False)
