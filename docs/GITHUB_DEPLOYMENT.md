# GitHub-based Deployment Guide

This guide explains how to deploy the portal system from GitHub repositories instead of using rsync from a source server.

## Overview

The GitHub deployment method:
- Clones repositories directly from GitHub
- No need for a source server with existing installation
- Faster deployment over long distances
- Easy version control (branches/tags)
- Simpler to replicate to multiple servers

## Prerequisites

1. **GitHub Repositories**
   - deploy-portal
   - ssh-helper
   - website-cloner
   - deploy-portal-security

2. **Target Server Requirements**
   - Ubuntu 22.04 or later
   - sudo access
   - Internet connectivity
   - EC2 instance with IAM role (for AWS features)

3. **Local Requirements** (for remote deployment)
   - SSH access to target server
   - SSH private key (.pem file)

## Quick Start

### Local Deployment (on the server itself)

```bash
# Clone the deploy-portal repository
git clone https://github.com/yourusername/deploy-portal.git
cd deploy-portal

# Run the GitHub deployment script
bash scripts/github-deploy.sh
```

### Remote Deployment (from your workstation)

```bash
# Copy the github-deploy.sh script to your workstation
scp -i your-key.pem ubuntu@target-server:/path/to/github-deploy.sh .

# Run it locally, it will prompt for remote server details
bash github-deploy.sh
```

## Deployment Process

The `github-deploy.sh` script will:

1. **Prompt for Configuration**
   - Deployment target (local or remote)
   - GitHub repository URLs
   - Branch names for each repository

2. **Clone Repositories**
   - Clones all four repositories to `~/src/`
   - Checks out specified branches

3. **Install Infrastructure**
   - Runs `infrastructure-install.sh`
   - Installs nginx, Node.js, Python, etc.

4. **Bootstrap Services**
   - Runs `bootstrap.sh` for each service
   - Creates systemd services
   - Installs dependencies

5. **Configure nginx**
   - Sets up reverse proxy configuration
   - Configures SSL if certificates available

6. **Configure AWS** (optional)
   - Prompts to run AWS configuration script
   - Sets up `.ec2-config.env` file

## Manual Steps

If you prefer to deploy manually:

### 1. Clone Repositories

```bash
mkdir -p ~/src
cd ~/src

git clone -b main https://github.com/yourusername/deploy-portal.git
git clone -b main https://github.com/yourusername/ssh-helper.git
git clone -b main https://github.com/yourusername/website-cloner.git
git clone -b main https://github.com/yourusername/deploy-portal-security.git
```

### 2. Install Infrastructure

```bash
cd ~/src/deploy-portal
bash scripts/infrastructure-install.sh
```

### 3. Bootstrap Services

```bash
# Deploy Portal
cd ~/src/deploy-portal
bash bootstrap.sh

# SSH Helper
cd ~/src/ssh-helper
bash bootstrap.sh

# Website Cloner
cd ~/src/website-cloner
bash bootstrap.sh

# Security Dashboard
cd ~/src/deploy-portal-security
bash bootstrap.sh
```

### 4. Configure nginx

```bash
cd ~/src/deploy-portal
sudo bash scripts/configure-nginx.sh
```

### 5. Configure AWS

```bash
bash ~/src/deploy-portal/scripts/configure-aws-config.sh
```

## AWS Configuration

After deployment, you must configure AWS settings for the portal to work.

### Required IAM Role

The EC2 instance needs an IAM role with these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeSecurityGroups",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress"
      ],
      "Resource": "*"
    }
  ]
}
```

### Configuration Script

Run the AWS configuration script:

```bash
bash ~/src/deploy-portal/scripts/configure-aws-config.sh
```

This will prompt for:
- AWS Region
- Security Group ID
- Public IP address
- SSH key path (optional)
- Cognito settings (optional)

The script will:
- Create `~/.ec2-config.env` file
- Set secure permissions (600)
- Update systemd services to load the file
- Test AWS connectivity
- Restart services

### Manual Configuration

Alternatively, copy the example file and edit it:

```bash
cp ~/src/deploy-portal/.ec2-config.env.example ~/.ec2-config.env
nano ~/.ec2-config.env
chmod 600 ~/.ec2-config.env
```

Then update systemd services:

```bash
# Add EnvironmentFile to services
sudo bash -c 'echo "EnvironmentFile=/home/ubuntu/.ec2-config.env" >> /etc/systemd/system/deploy-portal.service'
sudo bash -c 'echo "EnvironmentFile=/home/ubuntu/.ec2-config.env" >> /etc/systemd/system/ssh-helper.service'

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart deploy-portal ssh-helper
```

## Copying Configuration Between Servers

To copy AWS configuration from one server to another:

```bash
# On the source server or your workstation
bash ~/src/deploy-portal/scripts/copy-deployment-files.sh
```

This will:
- Copy `.ec2-config.env` to target server
- Update configuration for target's region/security group
- Copy SSH keys if needed
- Update systemd services
- Restart services

## Verification

### Check Services

```bash
# Check service status
sudo systemctl status deploy-portal
sudo systemctl status ssh-helper

# View logs
sudo journalctl -u deploy-portal -n 50
sudo journalctl -u ssh-helper -n 50
```

### Test AWS Configuration

```bash
# Run the test script
bash ~/src/deploy-portal/scripts/test-aws-config.sh
```

Expected output:
- ✓ Configuration file exists
- ✓ IAM role is attached
- ✓ AWS connectivity works
- ✓ Security group is accessible

### Access Web Interfaces

```bash
# Get your public IP
curl http://169.254.169.254/latest/meta-data/public-ipv4
```

Then access:
- Deploy Portal: http://YOUR_IP/
- SSH Helper: http://YOUR_IP/ssh

## Troubleshooting

### "unable to locate credentials" Error

This means the AWS configuration is missing or incorrect.

**Solution:**
1. Verify IAM role is attached:
   ```bash
   curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
   ```

2. Check configuration file exists:
   ```bash
   ls -la ~/.ec2-config.env
   ```

3. Run the test script:
   ```bash
   bash scripts/test-aws-config.sh
   ```

4. Reconfigure if needed:
   ```bash
   bash scripts/configure-aws-config.sh
   ```

### Services Not Starting

Check the systemd service logs:

```bash
sudo journalctl -u deploy-portal -xe
sudo journalctl -u ssh-helper -xe
```

Common issues:
- Missing dependencies: Run `bash bootstrap.sh` again
- Port conflicts: Check if ports 5000, 8080 are in use
- Missing configuration: Run AWS configuration script

### nginx 502 Bad Gateway

This means nginx is running but the backend services are down.

```bash
# Check backend services
sudo systemctl status deploy-portal ssh-helper

# Restart services
sudo systemctl restart deploy-portal ssh-helper

# Check nginx configuration
sudo nginx -t
```

### AWS API Calls Failing

Verify:
1. IAM role is attached and has correct permissions
2. Region in `.ec2-config.env` matches instance region
3. Security group ID is correct
4. boto3 is installed: `pip3 install boto3`

Test manually:
```bash
source ~/.ec2-config.env
aws ec2 describe-security-groups --group-ids $SECURITY_GROUP_ID --region $AWS_REGION
```

## Updating Deployment

To update an existing deployment with new code:

```bash
cd ~/src/deploy-portal
git pull origin main

cd ~/src/ssh-helper
git pull origin main

# Restart services to load new code
sudo systemctl restart deploy-portal ssh-helper
```

## Complete Redeployment

To completely redeploy from scratch:

```bash
# Stop services
sudo systemctl stop deploy-portal ssh-helper

# Backup configuration
cp ~/.ec2-config.env ~/.ec2-config.env.backup

# Remove old installation
rm -rf ~/src/deploy-portal ~/src/ssh-helper ~/src/website-cloner ~/src/deploy-portal-security

# Run deployment script again
bash github-deploy.sh

# Restore configuration if needed
cp ~/.ec2-config.env.backup ~/.ec2-config.env
```

## Best Practices

1. **Use Branches for Versions**
   - Deploy from `main` for stable releases
   - Use `develop` or feature branches for testing
   - Tag releases: `v1.0.0`, `v1.1.0`, etc.

2. **Keep Configuration Separate**
   - Never commit `.ec2-config.env` to git
   - Use `.ec2-config.env.example` as template
   - Backup configuration before redeploying

3. **Test Before Production**
   - Deploy to a test server first
   - Verify all features work
   - Check AWS API access
   - Test IP whitelisting

4. **Monitor Services**
   - Set up CloudWatch or other monitoring
   - Check logs regularly
   - Monitor AWS API usage
   - Track failed authentication attempts

5. **Security**
   - Keep IAM policies minimal (least privilege)
   - Use security groups to restrict access
   - Enable HTTPS with valid SSL certificates
   - Rotate SSH keys periodically
   - Use AWS Cognito for authentication

## See Also

- [AWS Configuration Guide](../README.md#aws-configuration)
- [Infrastructure Install Script](../scripts/infrastructure-install.sh)
- [Bootstrap Scripts](../bootstrap.sh)
- [Deployment Runbook](/tmp/deployment-runbook.md)
