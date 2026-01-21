# Deploy Portal (Capsule Cloud)

A self-service web portal for provisioning SSH access and deploying applications to an EC2 gateway instance protected by AWS Cognito authentication.

## 🌟 Features

- **🔐 Automatic IP Whitelisting**: Detects user's public IP and adds to EC2 Security Group
- **🔑 SSH Key Distribution**: Generates deployment kits with SSH keys and instructions
- **📦 One-Click Deployment**: Downloads deployment kit ready for use with Claude Code
- **📊 Application Catalog**: View all deployed applications with status and management
- **📈 Activity Monitoring**: Real-time logs of deployments and SSH access
- **🤖 Claude Code Integration**: Pre-formatted prompts for automated deployment
- **🎨 Modern Web UI**: Clean, responsive interface for all features
- **📚 Built-in Documentation**: Architecture diagrams and deployment guides

## 🏗️ Architecture

```
User Browser (Authenticated via Cognito)
         ↓
    nginx (:443) → oauth2-proxy (:4180)
         ↓
Deploy Portal Flask App (:5000)
         ↓
    ├── EC2 Security Group Management (boto3)
    ├── SSH Key Generation
    ├── Deployment Kit Creation
    └── Application Registry Management
```

The Deploy Portal:
- **Reads** `X-User-Email` header from nginx (trusted)
- **Manages** EC2 Security Group rules via boto3
- **Generates** SSH keys and deployment instructions
- **Tracks** deployed applications in JSON registry
- **Provides** automation scripts for nginx/systemd configuration

## 📋 Prerequisites

- EC2 instance with IAM role attached
- IAM role must have permissions for:
  - `ec2:DescribeSecurityGroups`
  - `ec2:AuthorizeSecurityGroupIngress`
  - `ec2:RevokeSecurityGroupIngress`
- nginx + oauth2-proxy + Cognito authentication gateway configured
- Python 3.8+
- Flask

## 🚀 Quick Start

### Installation

1. **Clone or navigate to the directory**:
   ```bash
   cd /home/ubuntu/src/deploy-portal
   ```

2. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Configure settings** (if needed):
   ```bash
   # Edit config.py to customize:
   # - Security Group ID
   # - AWS Region
   # - Port range for apps
   nano config.py
   ```

4. **Create required directories**:
   ```bash
   mkdir -p data keys logs automation/scripts
   ```

5. **Run the application**:
   ```bash
   python3 app.py
   ```

The app will start on `http://127.0.0.1:5000`

### Bootstrap Installation (Recommended)

For automated setup with systemd service and nginx configuration:

1. **Ensure auth gateway is set up first** (required for nginx includes)

2. **Copy configuration template** (optional):
   ```bash
   cp config.env.example config.env
   nano config.env
   ```

3. **Run bootstrap script**:
   ```bash
   ./bootstrap.sh
   ```

The bootstrap script will:
- Create Python virtual environment
- Install all dependencies
- Create required directories (data, keys, logs, automation/scripts)
- Generate SSH deployment key (if not exists)
- Initialize data files (app-registry.json, port-registry.json)
- Install systemd service for auto-start
- Copy nginx configurations to modular include directories
- Start the deploy-portal service

4. **Verify installation**:
   ```bash
   ./tests/verify-deployment.sh
   ```

5. **Check service status**:
   ```bash
   sudo systemctl status deploy-portal
   sudo journalctl -u deploy-portal -f
   ```

The deploy-portal will be accessible at `https://YOUR_IP/` (root path) or `https://YOUR_IP/deploy/`.

### nginx Configuration

Add this to your nginx config (`/etc/nginx/sites-available/auth-gateway`):

```nginx
location /deploy/ {
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

    auth_request_set $email $upstream_http_x_auth_request_email;
    auth_request_set $user $upstream_http_x_auth_request_user;

    proxy_set_header X-User-Email $email;
    proxy_set_header X-Auth-Request-User $user;

    rewrite ^/deploy/(.*)$ /$1 break;
    proxy_pass http://127.0.0.1:5000;

    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}

# Also handle root /docs, /apps, /status paths
location ~ ^/(docs|apps|status) {
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

    auth_request_set $email $upstream_http_x_auth_request_email;
    proxy_set_header X-User-Email $email;

    proxy_pass http://127.0.0.1:5000;
}
```

Reload nginx:
```bash
sudo nginx -t && sudo systemctl reload nginx
```

## 📂 Project Structure

```
deploy-portal/
├── app.py                          # Main Flask application
├── config.py                       # Configuration settings
├── requirements.txt                # Python dependencies
├── README.md                       # This file
├── .gitignore                      # Git ignore patterns
│
├── templates/                      # HTML templates
│   ├── base.html                   # Base layout with navigation
│   ├── index.html                  # Landing page
│   ├── provision.html              # IP whitelisting & kit download
│   ├── apps_catalog.html           # Application management
│   ├── activity.html               # Activity logs viewer
│   ├── docs_index.html             # Documentation hub
│   └── docs_markdown.html          # Markdown document viewer
│
├── static/                         # CSS, JS, images
│   └── style.css                   # Main stylesheet
│
├── docs/                           # Documentation
│   ├── ARCHITECTURE.md             # Comprehensive architecture diagrams
│   └── MAC_DEPLOYMENT_GUIDE.md     # Step-by-step Mac deployment guide
│
├── automation/                     # Deployment automation scripts
│   ├── port-allocator.sh           # Allocate ports for apps
│   ├── nginx-register.sh           # Create nginx location blocks
│   ├── systemd-register.sh         # Create systemd services
│   ├── registry-manager.sh         # Update app registry
│   └── deploy-app.sh               # Full deployment orchestration
│
├── data/                           # Application data (not in git)
│   ├── app-registry.json           # Deployed applications registry
│   ├── port-registry.json          # Port allocation tracking
│   └── access-log.json             # SSH access audit log
│
├── keys/                           # SSH keys (not in git)
│   └── deploy-key.pem              # Shared SSH private key
│
└── logs/                           # Application logs (not in git)
    └── deploy-portal.log
```

## 🔧 Configuration

### config.py

Key configuration options:

```python
class Config:
    SECRET_KEY = 'generated-secret-key'
    SECURITY_GROUP_ID = 'sg-0d6bbadbbd290b320'  # Your security group
    PORT_RANGE_START = 8000  # Starting port for apps
    PORT_RANGE_END = 8999    # Ending port for apps

    @staticmethod
    def get_region():
        # Auto-detects region from EC2 metadata

    @staticmethod
    def get_instance_ip():
        # Auto-detects public IP from EC2 metadata
```

## 🌐 Web UI Routes

| Route | Description |
|-------|-------------|
| `/` | Landing page with overview |
| `/deploy/` | Provision SSH access & download kit |
| `/apps` | Application catalog and management |
| `/docs` | Documentation hub |
| `/docs/architecture` | Architecture diagrams |
| `/docs/mac-deployment` | Mac deployment guide |
| `/status` | System status and health checks |
| `/deploy/activity` | Activity logs viewer |

## 🔧 Nginx Configuration

This application uses a **modular nginx configuration architecture** where each app manages its own routing configuration. The deploy-portal repo contains two nginx files that are deployed to the gateway server.

### Configuration Files in this Repo

**nginx/upstream.conf** - Upstream definition:
```nginx
upstream deploy_portal {
    server 127.0.0.1:5000;
}
```

**nginx/routes.conf** - Location blocks for / and /deploy/* endpoints:
```nginx
# Static files for deploy portal (no auth needed for CSS/JS)
location /deploy/static/ {
    alias /home/ubuntu/src/deploy-portal/static/;
    expires 1h;
    add_header Cache-Control "public, immutable";
}

# Protected: Deploy Portal (root page and all /deploy/* routes)
location / {
    # Authentication check via oauth2-proxy
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/start?rd=$scheme://$host$request_uri;

    # Pass authentication headers from oauth2-proxy to backend
    auth_request_set $user $upstream_http_x_auth_request_user;
    auth_request_set $email $upstream_http_x_auth_request_email;
    auth_request_set $auth_cookie $upstream_http_set_cookie;
    add_header Set-Cookie $auth_cookie;

    # Proxy to deploy portal application (port 5000)
    proxy_pass http://deploy_portal;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # Pass authenticated user info to backend
    proxy_set_header X-User-Email $email;
    proxy_set_header X-Auth-Request-User $user;

    # WebSocket support for terminal functionality
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 86400;
}
```

### Deployment to Gateway Server

When deploying or updating the nginx configuration, copy these files to the gateway:

```bash
# Copy upstream configuration
sudo cp /home/ubuntu/src/deploy-portal/nginx/upstream.conf \
        /etc/nginx/conf.d/system-upstreams/deploy-portal.conf

# Copy routes configuration
sudo cp /home/ubuntu/src/deploy-portal/nginx/routes.conf \
        /etc/nginx/conf.d/routes/deploy-portal.conf

# Test and reload nginx
sudo nginx -t && sudo systemctl reload nginx
```

### Architecture Benefits

- **Separation of Concerns**: deploy-portal owns its routing configuration
- **Version Control**: nginx configs are versioned with application code
- **Easy Updates**: Modify routes without touching the central gateway config
- **No Conflicts**: Each app manages its own namespace (/ssh, /cloner, etc.)

### Routes Managed by this App

- `/` - Deploy portal main interface (port 5000)
- `/deploy/*` - All deploy portal routes
- `/docs/*` - Documentation pages
- `/deploy/static/` - Static assets (no auth required)

## 🔐 Security

### Authentication

- **No authentication code** in the application
- Trusts `X-User-Email` header from nginx
- nginx enforces Cognito authentication via oauth2-proxy
- Application never exposed directly to internet (listens on 127.0.0.1 only)

### AWS Permissions

The EC2 instance IAM role needs:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeSecurityGroups",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress"
      ],
      "Resource": "*"
    }
  ]
}
```

### SSH Key Management

- SSH keys stored in `keys/` directory (excluded from git)
- Keys have 600 permissions (read-only for owner)
- One shared key for all deployments (simplicity)
- Keys included in deployment kit ZIP files
- Users download keys via authenticated HTTPS only

### IP Whitelisting

- User's public IP automatically detected
- Added to Security Group with description including:
  - User email
  - Timestamp
  - Purpose (deployment access)
- Time-limited access (recommended: 24 hours)
- Audit log of all IP whitelist changes

## 📦 Deployment Kit

When a user provisions access, they receive a ZIP file containing:

```
deployment-kit-{app-name}-{timestamp}.zip
├── deploy-key.pem              # SSH private key (600 permissions)
├── CLAUDE_PROMPT.txt           # Ready-to-paste Claude Code prompt
├── DEPLOY_INSTRUCTIONS.md      # Human-readable deployment steps
├── app-config.json             # App configuration (name, email, server details)
└── README.md                   # Quick overview and links
```

### Using the Deployment Kit

**Option 1: With Claude Code (Recommended)**

1. Extract the ZIP file to `~/Documents/claude-projects/`
2. Open Claude Code: `cd ~/Documents/claude-projects/my-app && claude-code`
3. Paste the contents of `CLAUDE_PROMPT.txt`
4. Claude will deploy your app automatically

**Option 2: Manual Deployment**

1. Extract the ZIP file
2. Connect via SSH: `ssh -i deploy-key.pem ubuntu@SERVER_IP`
3. Follow instructions in `DEPLOY_INSTRUCTIONS.md`

## 🤖 Automation Scripts

The portal includes shell scripts for deployment automation:

### port-allocator.sh
Allocates available ports from the configured range (8000-8999).

```bash
./automation/port-allocator.sh allocate my-app
# Output: 8042
```

### nginx-register.sh
Creates nginx location block for the application.

```bash
./automation/nginx-register.sh my-app 8042 /my-app/
# Creates: /etc/nginx/sites-available/my-app
# Symlinks: /etc/nginx/sites-enabled/my-app
# Reloads: nginx
```

### systemd-register.sh
Creates and enables systemd service.

```bash
./automation/systemd-register.sh my-app 8042 /home/ubuntu/apps/my-app
# Creates: /etc/systemd/system/my-app.service
# Enables and starts the service
```

### registry-manager.sh
Updates application registry JSON files.

```bash
./automation/registry-manager.sh register my-app 8042 user@example.com
# Updates: data/app-registry.json
# Updates: data/port-registry.json
```

### deploy-app.sh
Full deployment orchestration (calls all above scripts).

```bash
./automation/deploy-app.sh my-app user@example.com
# Handles complete deployment workflow
```

## 🧪 Development

### Running in Development Mode

```bash
# Enable Flask debug mode
export FLASK_ENV=development
python3 app.py
```

### Running with Gunicorn (Production)

```bash
# Install gunicorn
pip install gunicorn

# Run with 4 workers
gunicorn -w 4 -b 127.0.0.1:5000 app:app
```

### Systemd Service

Create `/etc/systemd/system/deploy-portal.service`:

```ini
[Unit]
Description=Deploy Portal Flask App
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/src/deploy-portal
ExecStart=/usr/bin/python3 /home/ubuntu/src/deploy-portal/app.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable deploy-portal
sudo systemctl start deploy-portal
```

## 📊 API Endpoints

### POST /deploy/provision
Whitelist user's IP in Security Group.

**Response**:
```json
{
  "success": true,
  "message": "IP whitelisted successfully",
  "ip": "1.2.3.4",
  "email": "user@example.com"
}
```

### POST /deploy/check-name
Check if app name is available.

**Request**:
```json
{
  "app_name": "my-app-01"
}
```

**Response**:
```json
{
  "available": true
}
```

### POST /deploy/download-kit
Generate and download deployment kit.

**Request**:
```json
{
  "app_name": "my-app-01",
  "app_type": "node"
}
```

**Response**: ZIP file download

### GET /deploy/api/activity
Get activity logs as JSON.

**Response**:
```json
{
  "logs": [
    {
      "timestamp": "2026-01-13T02:45:00Z",
      "user": "user@example.com",
      "action": "provision",
      "details": "IP whitelisted: 1.2.3.4"
    }
  ]
}
```

## 🐛 Troubleshooting

### Issue: "Permission denied" when provisioning

**Cause**: IAM role missing EC2 permissions

**Solution**: Verify IAM role attached to EC2 instance has required permissions

```bash
# Check IAM role
aws sts get-caller-identity

# Test permissions
aws ec2 describe-security-groups --group-ids sg-0d6bbadbbd290b320
```

### Issue: SSH connection fails after downloading kit

**Possible causes**:
1. IP not whitelisted yet (wait 30 seconds)
2. Wrong Security Group ID in config
3. SSH key permissions too open

**Solution**:
```bash
# Fix key permissions
chmod 600 deploy-key.pem

# Verify IP is whitelisted
aws ec2 describe-security-groups --group-ids sg-0d6bbadbbd290b320 | grep "YourIP"

# Test SSH connection
ssh -i deploy-key.pem -v ubuntu@SERVER_IP
```

### Issue: Application not accessible after deployment

**Possible causes**:
1. App not running
2. Port allocation conflict
3. nginx not configured

**Solution**:
```bash
# Check app status
systemctl status my-app

# Check nginx configuration
sudo nginx -t
cat /etc/nginx/sites-enabled/my-app

# Test app locally
curl http://localhost:8042

# Check logs
journalctl -u my-app -n 50
```

## 📖 Documentation

Comprehensive documentation is available in the web UI:

- **Architecture Diagrams**: `/docs/architecture` - Visual diagrams of the entire system
- **Mac Deployment Guide**: `/docs/mac-deployment` - Step-by-step instructions for Mac users
- **Activity Logs**: `/deploy/activity` - Real-time deployment and access logs

Or view markdown files directly:
- `docs/ARCHITECTURE.md`
- `docs/MAC_DEPLOYMENT_GUIDE.md`

## 🔄 Version Control

### Preparing for GitHub

The repository is ready for version control:

```bash
# Initialize git (if not already)
git init

# Stage all files
git add .

# Check what will be committed
git status

# Create first commit
git commit -m "Initial commit: Deploy Portal"

# Add remote (when ready)
git remote add origin https://github.com/YOUR_USERNAME/deploy-portal.git
git push -u origin main
```

### What's Excluded from Git

The `.gitignore` excludes:
- `keys/` - SSH private keys
- `data/` - Application registry files
- `logs/` - Log files
- `__pycache__/` - Python bytecode
- `.env` - Environment variables

## 🤝 Contributing

When contributing:

1. **Never commit secrets**: Keys, credentials, or sensitive data
2. **Test thoroughly**: Ensure all features work after changes
3. **Update docs**: Keep README and docs/ in sync with code
4. **Follow patterns**: Match existing code style and structure

## 📄 License

MIT License (or your chosen license)

## 🙏 Acknowledgments

- Built to work with [easy-cognito-nginx-gateway-auth](https://github.com/YOUR_ORG/easy-cognito-nginx-gateway-auth)
- Integrates with [ssh-helper](https://github.com/YOUR_ORG/ssh-helper) and [website-cloner](https://github.com/YOUR_ORG/website-cloner)
- Designed for deployment automation with Claude Code

## 📞 Support

- **Documentation**: https://your-gateway.com/docs
- **System Status**: https://your-gateway.com/status
- **Activity Logs**: https://your-gateway.com/deploy/activity

---

**Built with ❤️ for seamless cloud deployment**
