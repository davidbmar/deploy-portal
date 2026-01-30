# Deploy Portal - Deployment Guide

## Quick Start

### Fresh Installation
```bash
cd /home/ubuntu/src
git clone https://github.com/davidbmar/deploy-portal.git
cd deploy-portal
./bootstrap.sh
```

### Update Existing Installation
```bash
cd /home/ubuntu/src/deploy-portal
git stash  # Save any local changes
git pull
git stash pop  # Re-apply local changes (if any)
./bootstrap.sh
```

## What bootstrap.sh Does

1. **Creates Python virtual environment**
2. **Installs dependencies** from requirements.txt
3. **Creates required directories**
4. **Sets up SSH keys** (if not present)
5. **Installs systemd service**
6. **Configures nginx** (removes conflicts automatically)
7. **Fixes static file permissions** (for nginx access)
8. **Starts deploy-portal service**
9. **Verifies installation**

## Post-Deployment Verification

After running `./bootstrap.sh`, verify deployment with the comprehensive verification script:

### Quick Check
```bash
cd /home/ubuntu/src/deploy-portal
./scripts/verify-deployment-local.sh

# Or with your MacBook IP for specific security group testing:
USER_MACBOOK_IP=136.62.92.204 ./scripts/verify-deployment-local.sh
```

This script checks:
- ✅ Service status (deploy-portal running)
- ✅ Nginx configuration (valid, no conflicts)
- ✅ Internal access (localhost /, /deploy/, API)
- ✅ Static file permissions
- ✅ External access (public IP if available)
- ✅ Security group configuration (port 80/443)
- ✅ Port listening status

### Expected Output

```
=== Deploy Portal Verification ===

--- Instance Information ---
Instance ID: i-0a1b2c3d4e5f6g7h8
Public IP: 3.87.27.213
Private IP: 172.31.35.229

--- Service Status ---
✓ deploy-portal service is active

--- Nginx Configuration ---
✓ nginx config syntax is valid
✓ No nginx default_server conflicts (2 declarations)

--- Internal Access Tests ---
✓ Root path (/) accessible internally
✓ Deploy path (/deploy/) accessible internally
✓ Instance metadata API accessible internally
✓ Static files (CSS) accessible

--- External Access Tests ---
✓ Root path (/) accessible externally from 3.87.27.213
✓ Deploy path (/deploy/) accessible externally from 3.87.27.213
⚠ HTTPS (port 443) NOT accessible (may not be configured)

--- File Permissions ---
✓ /home/ubuntu directory permissions correct (755)
✓ Static directory permissions correct

--- Port Status ---
✓ Nginx listening on port 80
✓ Flask app listening on port 5000

--- Security Group Check ---
✓ Security group has port 80 rule configured

=== Verification Summary ===
Passed: 14
Failed: 0
Warnings: 1

✓ All critical tests passed!

Access your deployment at:
  → http://3.87.27.213/
  → http://3.87.27.213/deploy/
```

### Manual Verification

If the script fails, manually verify:

```bash
# 1. Service running
sudo systemctl status deploy-portal

# 2. Internal access
curl -I http://localhost/
curl -I http://localhost/deploy/

# 3. External access (replace with your public IP)
curl -I http://3.87.27.213/
curl -I http://3.87.27.213/deploy/

# 4. Security group (if external fails)
# Check in AWS Console → EC2 → Security Groups
# Ensure port 80 is open to your IP or 0.0.0.0/0
```

### Troubleshooting External Access Failures

If external access tests fail:

**Check Security Group:**
```bash
# Get instance ID
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/instance-id)

# Get security groups
aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].SecurityGroups'

# Check port 80 rules
aws ec2 describe-security-groups \
    --group-ids <YOUR_SG_ID> \
    --query 'SecurityGroups[0].IpPermissions[?ToPort==`80`]'
```

**Fix: Open port 80 in security group:**
```bash
aws ec2 authorize-security-group-ingress \
    --group-id <YOUR_SG_ID> \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0
```

**Or open to specific IP only:**
```bash
aws ec2 authorize-security-group-ingress \
    --group-id <YOUR_SG_ID> \
    --protocol tcp \
    --port 80 \
    --cidr YOUR_IP/32
```

### Quick Debug Script

If external access fails, run the debug script for detailed diagnostics:

```bash
./scripts/debug-access.sh
```

This will show:
- Instance information and public IP
- Internal vs external access status
- Nginx listening configuration
- Security group rules for port 80
- Specific troubleshooting steps

## Troubleshooting

### Service won't start
```bash
# Check logs
sudo journalctl -u deploy-portal -n 50

# Check Python errors
sudo journalctl -u deploy-portal --no-pager | grep -i error
```

### Nginx errors
```bash
# Test configuration
sudo nginx -t

# Check for conflicting default_server
grep -r "default_server" /etc/nginx/sites-enabled/ /etc/nginx/conf.d/

# Reload nginx
sudo systemctl reload nginx
```

### Static files not loading (403 errors)
```bash
# Re-run permission fix
chmod 755 /home/ubuntu
chmod 755 /home/ubuntu/src
chmod 755 /home/ubuntu/src/deploy-portal
chmod -R 755 /home/ubuntu/src/deploy-portal/static/

# Restart nginx
sudo systemctl restart nginx
```

### Port conflicts
```bash
# Check what's using port 5000
sudo ss -tlnp | grep :5000

# Check what's using port 80
sudo ss -tlnp | grep :80
```

## Architecture Notes

### Nginx Configuration
- Main server: `/etc/nginx/conf.d/deploy-portal-server.conf`
- Upstream: `/etc/nginx/conf.d/system-upstreams/deploy-portal.conf`
- Routes: `/etc/nginx/conf.d/routes/deploy-portal.conf`

**Important**: Deploy-portal owns port 80 as `default_server`. 
Any other nginx config trying to use `default_server` will conflict.

### Known Conflicts
- **auth-gateway**: Conflicts with deploy-portal (both want port 80)
  - Solution: Run on separate instances, OR
  - bootstrap.sh automatically disables auth-gateway

### Service Details
- **Service file**: `/etc/systemd/system/deploy-portal.service`
- **Working directory**: `/home/ubuntu/src/deploy-portal`
- **Python**: Uses venv at `./venv/bin/python`
- **User**: Runs as `ubuntu` user
- **Logs**: `sudo journalctl -u deploy-portal`

## For MacBook Claude Users

When using deployment kits to deploy apps:

### ✅ Safe Operations (Use These)
- Modify files in `/home/ubuntu/deployments/{your-app}/`
- Run automation scripts: `bash automation/auto-configure-nginx.sh`
- Use docker commands: `docker-compose up -d`
- View logs: `docker-compose logs`

### ❌ Dangerous Operations (Don't Do)
- Modify `/home/ubuntu/src/deploy-portal/` (infrastructure code)
- Edit `/etc/nginx/conf.d/deploy-portal-*` (infrastructure nginx)
- Run `systemctl restart deploy-portal` (infrastructure service)
- Manually edit nginx without automation scripts

### The Right Way
Instead of manual nginx edits, use the provided automation:
```bash
# Automatic setup (recommended)
bash automation/auto-configure-nginx.sh

# Manual if needed
bash automation/nginx-register.sh add-multiservice my-app 3000 8000
```

## Deployment Checklist

After running bootstrap.sh, verify:

- [ ] Service running: `systemctl is-active deploy-portal`
- [ ] Nginx valid: `sudo nginx -t`
- [ ] No conflicts: `grep -r "default_server" /etc/nginx/ | wc -l` (should be 2-3)
- [ ] Static files work: `curl -I http://localhost/deploy/static/style.css` (200 OK)
- [ ] Deploy page works: `curl -f http://localhost/deploy/` (200 OK)
- [ ] API works: `curl http://localhost/api/instance-metadata` (returns JSON)
- [ ] Permissions correct: `ls -ld /home/ubuntu | grep "drwxr-xr-x"`

## Emergency Rollback

If something breaks badly:

```bash
# Stop service
sudo systemctl stop deploy-portal

# Restore from git
cd /home/ubuntu/src/deploy-portal
git reset --hard origin/main

# Re-run bootstrap
./bootstrap.sh

# Check status
sudo systemctl status deploy-portal
curl -f http://localhost/deploy/
```

## Production Best Practices

1. **Always use git stash before pulling** to avoid merge conflicts
2. **Test locally first** with `curl http://localhost/`
3. **Check nginx config** with `sudo nginx -t` before reloading
4. **Review changes** with `git log` before deploying
5. **Keep backups** of working configurations

## Getting Help

If you encounter issues:
1. Check this guide's troubleshooting section
2. Review logs: `sudo journalctl -u deploy-portal -n 100`
3. Check nginx: `sudo nginx -t && sudo tail /var/log/nginx/error.log`
4. Verify permissions: `ls -la /home/ubuntu/src/deploy-portal/static/`
5. See lessons learned: `cat /home/ubuntu/DEPLOYMENT_LESSONS_LEARNED.md`
