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

```bash
# Check service is running
sudo systemctl status deploy-portal

# Check nginx configuration
sudo nginx -t

# Test the application
curl -f http://localhost:5000/

# Test the deploy page
curl -f http://localhost/deploy/ | head -20

# Test instance metadata API
curl -f http://localhost/api/instance-metadata | jq
```

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
