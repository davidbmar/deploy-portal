# Deploy Portal Setup Instructions for Claude Code

You are setting up a deployment portal on this EC2 instance. This portal allows authenticated users to provision SSH access so they can deploy applications from their local machine using Claude Code.

**Base Directory**: `/home/ubuntu/src/deploy-portal`
**User**: `ubuntu`

> **Note**: This will eventually become its own repository. Structure the code cleanly with this in mind - include a proper README.md, .gitignore, and keep configuration separate from code.

## Overview

You will build a Flask app that:
1. Runs behind the existing Cognito/nginx auth gateway
2. Detects the user's IP address
3. Whitelists their IP in the EC2 Security Group
4. Provides them with an SSH key and instructions
5. Shows activity logs of what happens on the server

## Architecture

```
User Browser (authenticated via Cognito)
     │
     ▼
┌─────────────────────────────────────────────────┐
│  Nginx (existing - easy-cognito-nginx-gateway)  │
│                                                 │
│  /oauth2/* → oauth2-proxy → Cognito            │
│  /deploy/* → localhost:5000 (new Flask app)    │
│                                                 │
└─────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────┐
│  Deploy Portal (Flask - port 5000)              │
│                                                 │
│  • Reads X-User-Email header from oauth2-proxy  │
│  • Updates Security Group via boto3             │
│  • Generates deployment kit (.pem + instructions)│
│  • Displays SSH session activity logs           │
│                                                 │
└─────────────────────────────────────────────────┘
```

## AWS Configuration

- **Security Group ID**: `sg-0d6bbadbbd290b320`
- **IAM Role**: `ssh-whitelist-role` (already attached to this EC2)
- **Region**: Determine from instance metadata

## Step 1: Create the Project Structure

Create the following directory structure:

```
/home/ubuntu/src/deploy-portal/
├── app.py                 # Main Flask application
├── config.py              # Configuration
├── requirements.txt       # Python dependencies
├── README.md              # Project documentation (for future repo)
├── .gitignore             # Git ignore file
├── templates/
│   ├── base.html          # Base template
│   ├── provision.html     # Main provisioning page
│   └── activity.html      # Activity log viewer
├── static/
│   └── style.css          # Minimal styling
├── keys/                  # SSH keys directory (create if not exists)
│   └── deploy-key.pem     # Shared SSH private key
└── logs/                  # Activity logs directory
```

First, create the directory structure:

```bash
mkdir -p /home/ubuntu/src/deploy-portal/{templates,static,keys,logs}
cd /home/ubuntu/src/deploy-portal
```

## Step 2: Create requirements.txt

```
flask==3.0.0
boto3==1.34.0
```

## Step 2a: Create .gitignore (for future repo)

```
# Python
__pycache__/
*.py[cod]
*$py.class
venv/
.env

# Keys - NEVER commit these
keys/
*.pem

# Logs
logs/
*.log

# IDE
.vscode/
.idea/

# OS
.DS_Store
```

## Step 2b: Create README.md (for future repo)

```markdown
# Deploy Portal

A self-service portal for provisioning SSH access to EC2 instances for cloud deployments.

## Features

- Cognito authentication (integrates with easy-cognito-nginx-gateway-auth)
- Automatic IP whitelisting in Security Groups
- SSH key distribution
- Claude Code deployment prompt generation
- Activity logging and monitoring

## Prerequisites

- EC2 instance with IAM role that can modify Security Groups
- Cognito User Pool configured
- nginx with oauth2-proxy (see easy-cognito-nginx-gateway-auth)

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/YOUR_ORG/deploy-portal.git
   cd deploy-portal
   ```

2. Install dependencies:
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```

3. Generate SSH key:
   ```bash
   mkdir -p keys
   ssh-keygen -t rsa -b 4096 -f keys/deploy-key -N ""
   mv keys/deploy-key keys/deploy-key.pem
   cat keys/deploy-key.pub >> ~/.ssh/authorized_keys
   ```

4. Configure nginx (add to existing auth-gateway config):
   ```nginx
   location /deploy/ {
       auth_request /oauth2/auth;
       # ... see full config in docs
   }
   ```

5. Start the service:
   ```bash
   sudo systemctl enable deploy-portal
   sudo systemctl start deploy-portal
   ```

## Configuration

Edit `config.py` to set:
- `SECURITY_GROUP_ID` - Your EC2 security group
- `SSH_KEY_PATH` - Path to the shared SSH key
- `EC2_USER` - SSH username (ubuntu, ec2-user, etc.)

## Usage

1. Navigate to `https://your-domain/deploy/`
2. Log in via Cognito
3. Click "Download Deployment Kit"
4. Extract the kit and use with Claude Code

## Security

- All access requires Cognito authentication
- IPs are whitelisted per-user with audit trail
- SSH keys should be rotated periodically
- Activity is logged for compliance

## License

MIT
```

## Step 3: Create config.py

```python
import os

class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY', os.urandom(24).hex())
    SECURITY_GROUP_ID = 'sg-0d6bbadbbd290b320'
    SSH_KEY_PATH = '/home/ubuntu/src/deploy-portal/keys/deploy-key.pem'
    SSH_KEY_NAME = 'deploy-key'
    ACTIVITY_LOG_DIR = '/var/log/deploy-sessions'
    EC2_USER = 'ubuntu'
    
    # Get instance public IP from metadata
    @staticmethod
    def get_instance_ip():
        import urllib.request
        try:
            # IMDSv2
            token_request = urllib.request.Request(
                'http://169.254.169.254/latest/api/token',
                headers={'X-aws-ec2-metadata-token-ttl-seconds': '21600'},
                method='PUT'
            )
            token = urllib.request.urlopen(token_request, timeout=2).read().decode()
            ip_request = urllib.request.Request(
                'http://169.254.169.254/latest/meta-data/public-ipv4',
                headers={'X-aws-ec2-metadata-token': token}
            )
            return urllib.request.urlopen(ip_request, timeout=2).read().decode()
        except:
            return 'UNKNOWN'
```

## Step 4: Create app.py

```python
from flask import Flask, render_template, request, jsonify, send_file, Response
from config import Config
import boto3
import os
import io
import zipfile
from datetime import datetime
import glob
import time

app = Flask(__name__)
app.config.from_object(Config)

# Initialize AWS client
ec2_client = boto3.client('ec2')

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

@app.route('/deploy/')
def index():
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

@app.route('/deploy/download-kit')
def download_kit():
    email, ip = get_user_info()
    
    # Ensure IP is whitelisted first
    if not is_ip_whitelisted(ip):
        whitelist_ip(ip, email)
    
    zip_buffer, error = generate_deployment_kit(email, ip)
    
    if error:
        return jsonify({'error': error}), 500
    
    timestamp = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
    return send_file(
        zip_buffer,
        mimetype='application/zip',
        as_attachment=True,
        download_name=f'deployment-kit-{timestamp}.zip'
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

@app.route('/deploy/health')
def health():
    return jsonify({'status': 'healthy'})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000, debug=False)
```

## Step 5: Create templates/base.html

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{% block title %}Deploy Portal{% endblock %}</title>
    <link rel="stylesheet" href="/deploy/static/style.css">
</head>
<body>
    <nav>
        <div class="nav-brand">Deploy Portal</div>
        <div class="nav-links">
            <a href="/deploy/">Provision</a>
            <a href="/deploy/activity">Activity</a>
        </div>
        <div class="nav-user">{{ email }}</div>
    </nav>
    <main>
        {% block content %}{% endblock %}
    </main>
</body>
</html>
```

## Step 6: Create templates/provision.html

```html
{% extends "base.html" %}

{% block title %}Provision Access - Deploy Portal{% endblock %}

{% block content %}
<div class="container">
    <h1>Cloud Deployment Access</h1>
    
    <div class="card">
        <h2>Your Information</h2>
        <dl>
            <dt>Email</dt>
            <dd>{{ email }}</dd>
            <dt>Your IP Address</dt>
            <dd>{{ ip }}</dd>
            <dt>Target Server</dt>
            <dd>{{ instance_ip }}</dd>
            <dt>SSH Status</dt>
            <dd>
                {% if whitelisted %}
                <span class="status status-ok">✅ Your IP is whitelisted</span>
                {% else %}
                <span class="status status-pending">⏳ IP not yet whitelisted</span>
                {% endif %}
            </dd>
        </dl>
    </div>

    <div class="card">
        <h2>Get Deployment Kit</h2>
        <p>Download everything you need to deploy your application:</p>
        <ul>
            <li>SSH private key (.pem file)</li>
            <li>Connection instructions</li>
            <li>Claude Code prompt template</li>
        </ul>
        
        <div class="actions">
            {% if not whitelisted %}
            <button id="provision-btn" class="btn btn-primary" onclick="provisionAccess()">
                Whitelist My IP
            </button>
            {% endif %}
            <a href="/deploy/download-kit" class="btn btn-success" id="download-btn">
                Download Deployment Kit
            </a>
        </div>
        
        <div id="status-message" class="message" style="display: none;"></div>
    </div>

    <div class="card">
        <h2>Quick Start</h2>
        <ol>
            <li>Click "Download Deployment Kit"</li>
            <li>Extract the zip file</li>
            <li>Run <code>chmod 600 capsule-deploy.pem</code></li>
            <li>Open Claude Code in your project directory</li>
            <li>Give Claude the CLAUDE_PROMPT.md file</li>
            <li>Watch the magic happen!</li>
        </ol>
    </div>
</div>

<script>
async function provisionAccess() {
    const btn = document.getElementById('provision-btn');
    const msg = document.getElementById('status-message');
    
    btn.disabled = true;
    btn.textContent = 'Provisioning...';
    
    try {
        const response = await fetch('/deploy/provision', { method: 'POST' });
        const data = await response.json();
        
        if (data.success) {
            msg.className = 'message message-success';
            msg.textContent = '✅ ' + data.message;
            msg.style.display = 'block';
            btn.style.display = 'none';
            // Reload to update status
            setTimeout(() => location.reload(), 1500);
        } else {
            msg.className = 'message message-error';
            msg.textContent = '❌ ' + data.message;
            msg.style.display = 'block';
            btn.disabled = false;
            btn.textContent = 'Whitelist My IP';
        }
    } catch (error) {
        msg.className = 'message message-error';
        msg.textContent = '❌ Error: ' + error.message;
        msg.style.display = 'block';
        btn.disabled = false;
        btn.textContent = 'Whitelist My IP';
    }
}
</script>
{% endblock %}
```

## Step 7: Create templates/activity.html

```html
{% extends "base.html" %}

{% block title %}Activity Log - Deploy Portal{% endblock %}

{% block content %}
<div class="container">
    <h1>Activity Log</h1>
    
    <div class="card">
        <div class="activity-header">
            <span class="live-indicator" id="live-indicator">● Live</span>
            <button class="btn btn-secondary" onclick="refreshLogs()">Refresh</button>
        </div>
        
        <div id="activity-log" class="activity-log">
            <div class="loading">Loading activity...</div>
        </div>
    </div>
</div>

<script>
let eventSource = null;

async function loadLogs() {
    try {
        const response = await fetch('/deploy/api/activity');
        const logs = await response.json();
        renderLogs(logs);
    } catch (error) {
        console.error('Error loading logs:', error);
    }
}

function renderLogs(logs) {
    const container = document.getElementById('activity-log');
    
    if (logs.length === 0) {
        container.innerHTML = '<div class="no-activity">No activity recorded yet</div>';
        return;
    }
    
    container.innerHTML = logs.map(log => `
        <div class="log-entry">
            <span class="log-time">${log.timestamp}</span>
            <span class="log-user">${log.user}</span>
            <span class="log-content">${escapeHtml(log.content)}</span>
        </div>
    `).join('');
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

function refreshLogs() {
    loadLogs();
}

function startLiveUpdates() {
    if (eventSource) {
        eventSource.close();
    }
    
    eventSource = new EventSource('/deploy/api/activity/stream');
    
    eventSource.onmessage = function(event) {
        const logs = JSON.parse(event.data);
        renderLogs(logs);
    };
    
    eventSource.onerror = function() {
        document.getElementById('live-indicator').textContent = '○ Disconnected';
        document.getElementById('live-indicator').style.color = '#999';
    };
    
    eventSource.onopen = function() {
        document.getElementById('live-indicator').textContent = '● Live';
        document.getElementById('live-indicator').style.color = '#22c55e';
    };
}

// Initial load
loadLogs();

// Start live updates
startLiveUpdates();

// Fallback polling if SSE fails
setInterval(loadLogs, 10000);
</script>
{% endblock %}
```

## Step 8: Create static/style.css

```css
* {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background: #f5f5f5;
    color: #333;
    line-height: 1.6;
}

nav {
    background: #1a1a2e;
    color: white;
    padding: 1rem 2rem;
    display: flex;
    justify-content: space-between;
    align-items: center;
}

.nav-brand {
    font-weight: bold;
    font-size: 1.25rem;
}

.nav-links a {
    color: #a0a0a0;
    text-decoration: none;
    margin: 0 1rem;
}

.nav-links a:hover {
    color: white;
}

.nav-user {
    color: #a0a0a0;
    font-size: 0.875rem;
}

main {
    padding: 2rem;
    max-width: 900px;
    margin: 0 auto;
}

h1 {
    margin-bottom: 1.5rem;
    color: #1a1a2e;
}

h2 {
    margin-bottom: 1rem;
    color: #333;
    font-size: 1.25rem;
}

.container {
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
}

.card {
    background: white;
    border-radius: 8px;
    padding: 1.5rem;
    box-shadow: 0 1px 3px rgba(0,0,0,0.1);
}

dl {
    display: grid;
    grid-template-columns: 150px 1fr;
    gap: 0.5rem 1rem;
}

dt {
    font-weight: 600;
    color: #666;
}

dd {
    font-family: monospace;
}

.status {
    padding: 0.25rem 0.5rem;
    border-radius: 4px;
    font-size: 0.875rem;
}

.status-ok {
    background: #dcfce7;
    color: #166534;
}

.status-pending {
    background: #fef3c7;
    color: #92400e;
}

.actions {
    display: flex;
    gap: 1rem;
    margin-top: 1rem;
}

.btn {
    display: inline-block;
    padding: 0.75rem 1.5rem;
    border-radius: 6px;
    text-decoration: none;
    font-weight: 500;
    cursor: pointer;
    border: none;
    font-size: 1rem;
}

.btn-primary {
    background: #3b82f6;
    color: white;
}

.btn-primary:hover {
    background: #2563eb;
}

.btn-success {
    background: #22c55e;
    color: white;
}

.btn-success:hover {
    background: #16a34a;
}

.btn-secondary {
    background: #e5e7eb;
    color: #374151;
}

.btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
}

.message {
    margin-top: 1rem;
    padding: 1rem;
    border-radius: 6px;
}

.message-success {
    background: #dcfce7;
    color: #166534;
}

.message-error {
    background: #fee2e2;
    color: #991b1b;
}

ol, ul {
    margin-left: 1.5rem;
}

li {
    margin-bottom: 0.5rem;
}

code {
    background: #f3f4f6;
    padding: 0.125rem 0.375rem;
    border-radius: 4px;
    font-size: 0.875rem;
}

/* Activity Log */
.activity-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1rem;
}

.live-indicator {
    color: #22c55e;
    font-weight: 500;
}

.activity-log {
    background: #1a1a2e;
    border-radius: 6px;
    padding: 1rem;
    max-height: 500px;
    overflow-y: auto;
    font-family: monospace;
    font-size: 0.875rem;
}

.log-entry {
    padding: 0.25rem 0;
    border-bottom: 1px solid #2a2a3e;
    color: #e0e0e0;
}

.log-entry:last-child {
    border-bottom: none;
}

.log-time {
    color: #888;
    margin-right: 1rem;
}

.log-user {
    color: #60a5fa;
    margin-right: 1rem;
}

.log-content {
    color: #e0e0e0;
}

.no-activity, .loading {
    color: #888;
    text-align: center;
    padding: 2rem;
}
```

## Step 9: Generate SSH Key

If no shared SSH key exists yet, generate one:

```bash
# Create keys directory
mkdir -p /home/ubuntu/src/deploy-portal/keys

# Generate SSH key pair
ssh-keygen -t rsa -b 4096 -f /home/ubuntu/src/deploy-portal/keys/deploy-key -N ""

# Add public key to authorized_keys
cat /home/ubuntu/src/deploy-portal/keys/deploy-key.pub >> /home/ubuntu/.ssh/authorized_keys

# Set permissions
chmod 600 /home/ubuntu/src/deploy-portal/keys/deploy-key
chmod 644 /home/ubuntu/src/deploy-portal/keys/deploy-key.pub

# Rename private key to .pem
mv /home/ubuntu/src/deploy-portal/keys/deploy-key /home/ubuntu/src/deploy-portal/keys/deploy-key.pem
```

## Step 10: Set Up SSH Session Logging

Create the session logging script:

```bash
# Create log directory
sudo mkdir -p /var/log/deploy-sessions
sudo chown ec2-user:ec2-user /var/log/deploy-sessions
sudo chmod 755 /var/log/deploy-sessions

# Create the logging wrapper script
sudo tee /usr/local/bin/log-session.sh << 'EOF'
#!/bin/bash
LOG_DIR="/var/log/deploy-sessions"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
CLIENT_IP="${SSH_CLIENT%% *}"
LOG_FILE="${LOG_DIR}/${TIMESTAMP}-${USER}-${CLIENT_IP}.log"

echo "=== Session started: $(date) ===" >> "$LOG_FILE"
echo "User: $USER" >> "$LOG_FILE"
echo "Client: $SSH_CLIENT" >> "$LOG_FILE"
echo "===" >> "$LOG_FILE"

# If a command was passed (scp, etc), run it directly
if [ -n "$SSH_ORIGINAL_COMMAND" ]; then
    echo "Command: $SSH_ORIGINAL_COMMAND" >> "$LOG_FILE"
    eval "$SSH_ORIGINAL_COMMAND" 2>&1 | tee -a "$LOG_FILE"
else
    # Interactive session - use script for full logging
    script -q -f "$LOG_FILE" -c "$SHELL"
fi

echo "=== Session ended: $(date) ===" >> "$LOG_FILE"
EOF

sudo chmod +x /usr/local/bin/log-session.sh
```

**Note**: To enable logging for all SSH sessions, you would add `ForceCommand /usr/local/bin/log-session.sh` to `/etc/ssh/sshd_config`. However, this is optional for MVP - the activity page will work without it, just showing less detail.

## Step 11: Update Nginx Configuration

Add the deploy portal location to your existing nginx config. Edit `/etc/nginx/sites-available/auth-gateway` (or wherever your config is):

```nginx
# Add this inside your server block, alongside existing locations

location /deploy/ {
    auth_request /oauth2/auth;
    error_page 401 = /oauth2/sign_in;
    
    # Pass auth info to the app
    auth_request_set $user   $upstream_http_x_auth_request_user;
    auth_request_set $email  $upstream_http_x_auth_request_email;
    proxy_set_header X-User        $user;
    proxy_set_header X-User-Email  $email;
    
    # Pass real IP
    proxy_set_header X-Real-IP       $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    
    proxy_pass http://127.0.0.1:5000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    
    # For SSE streaming
    proxy_buffering off;
    proxy_cache off;
}

location /deploy/static/ {
    alias /home/ubuntu/src/deploy-portal/static/;
}
```

After editing:
```bash
sudo nginx -t
sudo systemctl reload nginx
```

## Step 12: Create Systemd Service

Create a systemd service to run the Flask app:

```bash
sudo tee /etc/systemd/system/deploy-portal.service << EOF
[Unit]
Description=Deploy Portal Flask App
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu/src/deploy-portal
ExecStart=/usr/bin/python3 /home/ubuntu/src/deploy-portal/app.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable deploy-portal
sudo systemctl start deploy-portal
```

## Step 13: Install Dependencies and Start

```bash
cd /home/ubuntu/src/deploy-portal

# Create virtual environment (optional but recommended)
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Start the service
sudo systemctl restart deploy-portal

# Check status
sudo systemctl status deploy-portal

# View logs if needed
sudo journalctl -u deploy-portal -f
```

## Step 14: Test Everything

1. **Test Flask app directly**:
   ```bash
   curl http://127.0.0.1:5000/deploy/health
   # Should return: {"status":"healthy"}
   ```

2. **Test through nginx** (from browser):
   - Visit `https://[your-domain]/deploy/`
   - You should be redirected to Cognito login
   - After login, you should see the provision page

3. **Test IP whitelisting**:
   - Click "Download Deployment Kit"
   - Check Security Group in AWS console - your IP should be listed

4. **Test SSH access**:
   - Extract the deployment kit
   - Run `chmod 600 capsule-deploy.pem`
   - SSH to the server using the provided command

## Verification Checklist

- [ ] Flask app runs on port 5000
- [ ] Nginx proxies /deploy/* to Flask
- [ ] Authentication works via Cognito
- [ ] IP detection shows correct public IP
- [ ] Security Group gets updated with new IP
- [ ] Deployment kit downloads with valid .pem
- [ ] SSH works with downloaded key
- [ ] Activity page loads (even if empty)

## Troubleshooting

**Flask won't start:**
```bash
sudo journalctl -u deploy-portal -n 50
```

**Nginx errors:**
```bash
sudo nginx -t
sudo tail -f /var/log/nginx/error.log
```

**Security Group update fails:**
- Check IAM role has `ec2:AuthorizeSecurityGroupIngress` permission
- Check Security Group ID is correct

**Can't SSH after provisioning:**
- Verify IP in Security Group matches your actual IP
- Check `~/.ssh/authorized_keys` has the public key
- Verify key permissions: `chmod 600 capsule-deploy.pem`
