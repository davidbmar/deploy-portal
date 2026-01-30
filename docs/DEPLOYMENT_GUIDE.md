# Deploy Portal - Deployment Guide

This guide covers deploying deploy-portal instances to fresh EC2 servers with complete automation.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Detailed Usage](#detailed-usage)
5. [Configuration Updates](#configuration-updates)
6. [Verification](#verification)
7. [Troubleshooting](#troubleshooting)
8. [Architecture](#architecture)
9. [Lessons Learned](#lessons-learned)

## Overview

The deploy-portal deployment automation enables deploying multiple identical portal instances to different EC2 servers with different domain names. Each instance operates independently with its own:

- Domain name (e.g., capsule-operations-deploy.duckdns.org, capsule-product-deploy.duckdns.org)
- Authentication configuration
- SSH key for deployment kit distribution
- Configuration file (.ec2-config.env)

### What Gets Deployed

A complete deploy-portal stack includes:

1. **System Dependencies**: git, nginx, python3, nodejs, curl, etc.
2. **Authentication Gateway**: easy-cognito-nginx-gateway-auth (nginx + oauth2-proxy)
3. **Deploy Portal Application**: Python Flask application with systemd service
4. **Configuration**: .ec2-config.env with all settings
5. **SSH Key**: Copied and configured for deployment kit distribution

## Prerequisites

### On Your Local Machine

- SSH access to the target EC2 instance
- SSH private key for connecting to target (.pem file)
- SSH private key for deployment kit distribution (.pem file, can be the same)
- AWS Cognito User Pool credentials

### On Target EC2 Instance

- Fresh Ubuntu EC2 instance (20.04 or 22.04)
- Port 443 open in security group (for HTTPS)
- Port 22 open for SSH access
- ubuntu user with sudo access

### Required Information

Gather these before starting:

1. **Target Server**
   - IP address or hostname (e.g., 44.244.76.51)
   - SSH key to connect to the server

2. **Domain Configuration**
   - Domain name for this instance (e.g., capsule-product-deploy.duckdns.org)
   - DuckDNS token (to update DNS after deployment)

3. **AWS Cognito**
   - User Pool ID (e.g., us-east-1_aVHSg58BS)
   - Client ID (e.g., 46gdd9glnaetl44e2mtap51bkk)
   - Client Secret
   - Region (e.g., us-east-1)

4. **AWS Configuration**
   - EC2 region (e.g., us-west-2)
   - Security group ID (optional, will auto-detect)

## Quick Start

### Deploy to a New Server

```bash
cd /home/ubuntu/src/deploy-portal

./scripts/deploy-new-instance.sh \
  --target-ip 44.244.76.51 \
  --domain capsule-product-deploy.duckdns.org \
  --ssh-key ~/.ssh/my-connection-key.pem \
  --cognito-pool-id us-east-1_aVHSg58BS \
  --cognito-client-id 46gdd9glnaetl44e2mtap51bkk \
  --cognito-client-secret "your-secret-here" \
  --cognito-region us-east-1 \
  --aws-region us-west-2
```

### Update DNS

After deployment completes, update your DuckDNS domain:

```bash
curl "https://www.duckdns.org/update?domains=capsule-product-deploy&token=YOUR_TOKEN&ip=44.244.76.51"
```

### Verify Deployment

```bash
./scripts/verify-deployment.sh \
  --target-host ubuntu@44.244.76.51 \
  --ssh-key ~/.ssh/my-connection-key.pem \
  --domain capsule-product-deploy.duckdns.org
```

### Access Your Portal

Visit: `https://capsule-product-deploy.duckdns.org`

## Detailed Usage

### deploy-new-instance.sh

Main deployment script that orchestrates the entire deployment process.

#### Required Parameters

- `--target-ip IP` or `--target-host HOST`: Target EC2 instance
- `--domain DOMAIN`: Domain name for this portal
- `--ssh-key PATH`: SSH key to connect to target
- `--cognito-pool-id ID`: Cognito User Pool ID
- `--cognito-client-id ID`: Cognito Client ID
- `--cognito-client-secret SECRET`: Cognito Client Secret

#### Optional Parameters

- `--deploy-ssh-key PATH`: SSH key for portal to distribute (default: same as --ssh-key)
- `--cognito-region REGION`: Cognito region (default: us-east-1)
- `--aws-region REGION`: AWS EC2 region (default: us-west-2)
- `--security-group-id ID`: Security group ID (will auto-detect if not provided)
- `--skip-auth-gateway`: Skip auth gateway installation (if already installed)

#### Deployment Process

The script performs these steps:

1. **Preflight Checks**
   - Validates all parameters
   - Tests SSH connection
   - Verifies SSH keys exist

2. **System Preparation**
   - Updates system packages
   - Installs dependencies
   - Creates directory structure

3. **Authentication Gateway** (unless --skip-auth-gateway)
   - Clones easy-cognito-nginx-gateway-auth
   - Runs installation script
   - Configures nginx and oauth2-proxy
   - Starts services

4. **Deploy Portal**
   - Clones deploy-portal repository
   - Copies SSH key to target server
   - Creates .ec2-config.env with all settings
   - Creates Python virtual environment
   - Installs dependencies
   - Installs systemd service
   - Starts deploy-portal service

5. **Verification**
   - Checks all services are running
   - Verifies configuration
   - Tests endpoints

#### Example: Deploy to Product Server

```bash
./scripts/deploy-new-instance.sh \
  --target-ip 44.244.76.51 \
  --domain capsule-product-deploy.duckdns.org \
  --ssh-key /home/ubuntu/.ssh/david-capsule-vibecode-2026-01-17.pem \
  --cognito-pool-id us-east-1_aVHSg58BS \
  --cognito-client-id 46gdd9glnaetl44e2mtap51bkk \
  --cognito-client-secret "your-secret-here" \
  --cognito-region us-east-1 \
  --aws-region us-west-2
```

#### Example: Deploy to Server with Existing Auth Gateway

```bash
./scripts/deploy-new-instance.sh \
  --target-ip 52.38.109.75 \
  --domain capsule-operations-deploy.duckdns.org \
  --ssh-key ~/.ssh/my-key.pem \
  --cognito-pool-id us-east-1_aVHSg58BS \
  --cognito-client-id 46gdd9glnaetl44e2mtap51bkk \
  --cognito-client-secret "your-secret-here" \
  --skip-auth-gateway
```

### configure-ssh-key.sh

Configure or update SSH key on an existing deployment.

#### Usage

```bash
./scripts/configure-ssh-key.sh \
  --target-host ubuntu@44.244.76.51 \
  --ssh-key /path/to/connection-key.pem \
  --deploy-key /path/to/new-deploy-key.pem \
  --deploy-key-name new-deploy-key
```

#### What It Does

1. Copies new SSH key to target server
2. Sets correct permissions (400)
3. Updates .ec2-config.env with new key path
4. Restarts deploy-portal service
5. Verifies configuration

### verify-deployment.sh

Comprehensive verification of deployment health.

#### Usage

```bash
./scripts/verify-deployment.sh \
  --target-host ubuntu@44.244.76.51 \
  --ssh-key /path/to/key.pem \
  --domain capsule-product-deploy.duckdns.org
```

#### What It Checks

**System Services:**
- nginx status and port 443 listening
- oauth2-proxy status and port 4180 listening
- deploy-portal status and port 5000 listening
- Auto-start configuration for all services

**Configuration:**
- .ec2-config.env exists and contains required variables
- SSH_KEY_PATH and SSH_KEY_NAME configured
- AWS region and security group configured

**File Permissions:**
- SSH key exists with 400 permissions
- SSH key readable by ubuntu user
- Correct directory ownership

**Functionality:**
- Portal responds on localhost:5000
- Python can import config.py
- Configuration loads correctly

**Network & DNS:**
- Domain resolves correctly
- HTTPS accessible externally
- SSL certificate present

### update-portal-config.sh

Update configuration variables without full redeployment.

#### Usage

```bash
./scripts/update-portal-config.sh \
  --target-host ubuntu@44.244.76.51 \
  --ssh-key /path/to/key.pem \
  --config-var SSH_KEY_PATH=/new/path/to/key.pem \
  --config-var AWS_REGION=us-west-2
```

#### Supported Variables

- `SSH_KEY_PATH`: Path to SSH key
- `SSH_KEY_NAME`: SSH key name
- `AWS_REGION`: AWS region
- `SECURITY_GROUP_ID`: Security group ID
- `PUBLIC_IP`: Public IP address
- `COGNITO_POOL_ID`: Cognito User Pool ID
- `COGNITO_CLIENT_ID`: Cognito Client ID
- `COGNITO_CLIENT_SECRET`: Cognito Client Secret
- `COGNITO_REGION`: Cognito region

#### What It Does

1. Backs up current .ec2-config.env
2. Updates specified variables
3. Restarts deploy-portal service
4. Verifies new configuration loads correctly

## Configuration Updates

### Update SSH Key on Existing Deployment

```bash
# Copy new key and update configuration
./scripts/configure-ssh-key.sh \
  --target-host ubuntu@52.38.109.75 \
  --ssh-key ~/.ssh/connection-key.pem \
  --deploy-key ~/.ssh/new-deploy-key.pem \
  --deploy-key-name new-deploy-key

# Verify it worked
./scripts/verify-deployment.sh \
  --target-host ubuntu@52.38.109.75 \
  --ssh-key ~/.ssh/connection-key.pem \
  --domain capsule-operations-deploy.duckdns.org
```

### Update Multiple Configuration Variables

```bash
./scripts/update-portal-config.sh \
  --target-host ubuntu@44.244.76.51 \
  --ssh-key ~/.ssh/my-key.pem \
  --config-var AWS_REGION=us-west-2 \
  --config-var SECURITY_GROUP_ID=sg-12345678 \
  --config-var PUBLIC_IP=44.244.76.51
```

## Verification

### Check Service Status

```bash
ssh -i ~/.ssh/my-key.pem ubuntu@44.244.76.51 "sudo systemctl status deploy-portal"
ssh -i ~/.ssh/my-key.pem ubuntu@44.244.76.51 "sudo systemctl status nginx"
ssh -i ~/.ssh/my-key.pem ubuntu@44.244.76.51 "sudo systemctl status oauth2-proxy"
```

### View Logs

```bash
# Deploy portal logs
ssh -i ~/.ssh/my-key.pem ubuntu@44.244.76.51 "sudo journalctl -u deploy-portal -f"

# Nginx logs
ssh -i ~/.ssh/my-key.pem ubuntu@44.244.76.51 "sudo tail -f /var/log/nginx/error.log"

# OAuth2 proxy logs
ssh -i ~/.ssh/my-key.pem ubuntu@44.244.76.51 "sudo journalctl -u oauth2-proxy -f"
```

### Test Endpoints

```bash
# Test portal directly
ssh -i ~/.ssh/my-key.pem ubuntu@44.244.76.51 "curl -s http://localhost:5000"

# Test through nginx (external)
curl -k https://capsule-product-deploy.duckdns.org
```

### Run Full Verification

```bash
./scripts/verify-deployment.sh \
  --target-host ubuntu@44.244.76.51 \
  --ssh-key ~/.ssh/my-key.pem \
  --domain capsule-product-deploy.duckdns.org
```

## Troubleshooting

### Service Won't Start

**Symptoms:** systemctl status shows failed or inactive

**Solutions:**
1. Check logs: `sudo journalctl -u deploy-portal -n 50`
2. Verify Python dependencies: `cd /home/ubuntu/src/deploy-portal && source venv/bin/activate && pip list`
3. Check configuration: `cat /home/ubuntu/.ec2-config.env`
4. Test manually: `cd /home/ubuntu/src/deploy-portal && source venv/bin/activate && python app.py`

### SSH Key Not Found

**Symptoms:** Portal can't read SSH key, deployment kits fail

**Solutions:**
1. Verify key exists: `ls -la /home/ubuntu/.ssh/`
2. Check permissions: `stat -c '%a' /home/ubuntu/.ssh/your-key.pem` (should be 400)
3. Verify path in config: `grep SSH_KEY_PATH /home/ubuntu/.ec2-config.env`
4. Reconfigure key: Use `configure-ssh-key.sh` script

### Configuration Not Loading

**Symptoms:** Portal uses default values instead of .ec2-config.env

**Solutions:**
1. Verify file exists: `test -f /home/ubuntu/.ec2-config.env && echo "exists"`
2. Check file format: `cat /home/ubuntu/.ec2-config.env` (should have `export VAR=value`)
3. Test loading:
   ```python
   cd /home/ubuntu/src/deploy-portal
   source venv/bin/activate
   python3 -c "from config import Config; print(Config.SSH_KEY_PATH)"
   ```
4. Restart service: `sudo systemctl restart deploy-portal`

### DNS Not Resolving

**Symptoms:** Domain doesn't point to server

**Solutions:**
1. Check DNS: `host capsule-product-deploy.duckdns.org`
2. Update DuckDNS:
   ```bash
   curl "https://www.duckdns.org/update?domains=capsule-product-deploy&token=YOUR_TOKEN&ip=44.244.76.51"
   ```
3. Wait for propagation (can take 5-10 minutes)
4. Flush local DNS cache: `sudo systemd-resolve --flush-caches`

### SSL Certificate Issues

**Symptoms:** Browser shows certificate warnings

**Solutions:**
1. Check if self-signed: `sudo openssl x509 -in /etc/nginx/ssl/nginx-selfsigned.crt -text -noout`
2. Install Let's Encrypt:
   ```bash
   ssh -i ~/.ssh/my-key.pem ubuntu@44.244.76.51
   sudo apt-get install certbot python3-certbot-nginx
   sudo certbot --nginx -d capsule-product-deploy.duckdns.org
   ```
3. Verify certificate: `sudo certbot certificates`

### Port 443 Not Accessible

**Symptoms:** Cannot reach portal via HTTPS from external network

**Solutions:**
1. Check security group: Verify port 443 is open in AWS console
2. Check nginx is listening: `sudo netstat -tuln | grep :443`
3. Test locally first: `ssh -i ~/.ssh/my-key.pem ubuntu@44.244.76.51 "curl -k https://localhost"`
4. Check firewall: `sudo ufw status` (should be inactive or allow 443)

### Cognito Authentication Fails

**Symptoms:** Login redirects fail or show errors

**Solutions:**
1. Verify callback URLs in Cognito console match domain
2. Check oauth2-proxy logs: `sudo journalctl -u oauth2-proxy -n 50`
3. Verify Cognito credentials in .ec2-config.env
4. Test callback URL format: Should be `https://your-domain.duckdns.org/oauth2/callback`

## Architecture

### Deployment Flow

```
1. Preflight Checks
   ├─ Validate parameters
   ├─ Test SSH connection
   └─ Verify local files

2. System Preparation
   ├─ apt-get update
   ├─ Install dependencies
   └─ Create directories

3. Auth Gateway (optional)
   ├─ Clone repo
   ├─ Run install.sh
   ├─ Configure nginx
   ├─ Configure oauth2-proxy
   └─ Start services

4. Deploy Portal
   ├─ Clone repo
   ├─ Copy SSH key
   ├─ Create .ec2-config.env
   ├─ Setup Python venv
   ├─ Install dependencies
   ├─ Install systemd service
   └─ Start service

5. Verification
   ├─ Check services
   ├─ Test endpoints
   └─ Generate report
```

### Configuration Hierarchy

The deploy-portal uses a ConfigLoader class with this priority order:

1. **Environment variables** (highest priority)
2. **Config file** (~/.ec2-config.env)
3. **AWS metadata service**
4. **Hardcoded defaults** (lowest priority)

This means you can:
- Use .ec2-config.env for server-specific settings (recommended)
- Override specific values with environment variables
- Fall back to AWS metadata for dynamic values (IP, region)
- Use sensible defaults when nothing else is specified

### File Structure

```
deploy-portal/
├── app.py                          # Main Flask application
├── config.py                       # Configuration with ConfigLoader
├── requirements.txt                # Python dependencies
├── deploy-portal.service           # Systemd service file
├── scripts/
│   ├── deploy-new-instance.sh      # Main deployment automation
│   ├── configure-ssh-key.sh        # SSH key configuration
│   ├── verify-deployment.sh        # Deployment verification
│   └── update-portal-config.sh     # Configuration updates
├── templates/
│   └── ec2-config.env.template     # Configuration template
└── docs/
    └── DEPLOYMENT_GUIDE.md         # This guide

Target Server:
/home/ubuntu/
├── .ec2-config.env                 # Server-specific configuration
├── .ssh/
│   └── deploy-key.pem              # SSH key for deployment (400)
└── src/
    ├── deploy-portal/              # Portal application
    │   ├── venv/                   # Python virtual environment
    │   └── ...
    └── easy-cognito-nginx-gateway-auth/  # Auth gateway
        └── ...

/etc/systemd/system/
├── deploy-portal.service           # Portal service
├── oauth2-proxy.service            # Auth proxy service
└── nginx.service                   # Web server

/var/log/
└── deploy-sessions/                # Activity logs
```

## Lessons Learned

These automation scripts incorporate lessons learned from manual deployments:

### 1. SSH Key Configuration

**Problem:** Hardcoded SSH key paths in config.py caused failures when deploying to different servers.

**Solution:**
- Made SSH_KEY_PATH configurable via ConfigLoader
- Store server-specific path in .ec2-config.env
- Copy SSH key to consistent location with correct permissions (400)

### 2. Configuration Management

**Problem:** Manual SSH commands to update configuration were error-prone.

**Solution:**
- Centralize all configuration in .ec2-config.env
- Use templates for consistent setup
- Provide update script for changes without redeployment

### 3. Service Restart After Config Changes

**Problem:** Changes to .ec2-config.env weren't picked up until manual service restart.

**Solution:**
- All configuration scripts automatically restart the service
- Wait and verify service starts successfully
- Show logs immediately if restart fails

### 4. Verification is Critical

**Problem:** Deployments appeared successful but had subtle configuration issues.

**Solution:**
- Comprehensive verification script checks all components
- Test functional endpoints, not just service status
- Verify configuration loads correctly through Python

### 5. Directory Navigation in SSH

**Problem:** Complex SSH commands with cd and multiple steps were fragile.

**Solution:**
- Use simple, atomic SSH commands
- Use full paths instead of cd
- Chain commands with && only when necessary

### 6. Manual Steps Are Error-Prone

**Problem:** Deployments required many manual SSH commands in sequence.

**Solution:**
- Automate entire deployment in single script
- Break complex operations into modular functions
- Provide progress feedback at each step

### 7. Multiple Portal Instances

**Problem:** Need to deploy identical portals with different domains and configurations.

**Solution:**
- Parameterize domain name and server details
- Use per-server .ec2-config.env files
- Support multiple deployment without conflicts

## Additional Resources

- [Deploy Portal GitHub Repository](https://github.com/davidbmar/deploy-portal)
- [Easy Cognito Nginx Gateway Auth](https://github.com/davidbmar/easy-cognito-nginx-gateway-auth)
- [DuckDNS Documentation](https://www.duckdns.org/spec.jsp)
- [Let's Encrypt with Nginx](https://certbot.eff.org/instructions?ws=nginx&os=ubuntu-20)

## Support

For issues or questions:

1. Check the [Troubleshooting](#troubleshooting) section
2. Review logs on the target server
3. Run verification script for diagnostic information
4. Check GitHub issues for known problems

## Version History

- **v1.0** (2026-01-30): Initial release with full automation
  - Main deployment script
  - SSH key configuration module
  - Comprehensive verification
  - Configuration update utility
  - Complete documentation
