# Capsule Deploy Infrastructure

This directory contains the infrastructure setup scripts and tools for the Capsule Deploy system. These components enable zero-touch deployments on EC2 servers.

## Overview

The infrastructure consists of:

1. **Port Registry System** - Central registry to prevent port conflicts
2. **Nginx Management Service** - Automated nginx configuration
3. **Port Allocator** - Automatic port allocation for new apps
4. **Helper Scripts** - Pre/post deployment validation and health checks
5. **Sudo Configuration** - Passwordless sudo for deployment tools

## Directory Structure

```
infrastructure/
├── README.md                          # This file
├── install-infrastructure.sh          # Master installation script
├── bin/                               # System-level executables
│   ├── capsule-nginx-manager         # Nginx configuration manager
│   └── capsule-port-allocator        # Port allocation manager
├── helpers/                           # Deployment helper scripts
│   ├── pre-deploy-validate.sh        # Pre-deployment validation
│   └── post-deploy-healthcheck.sh    # Post-deployment health checks
├── config/                            # Configuration files
│   └── sudoers-capsule-deploy        # Sudo permissions
└── tests/
    └── verify-infrastructure.sh       # Verification tests
```

## Installation

### Quick Install

On a fresh EC2 server (or to update existing installation):

```bash
cd /home/ubuntu/src/deploy-portal/infrastructure
sudo ./install-infrastructure.sh
```

### Installation Options

```bash
# Standard installation (includes importing existing deployments)
sudo ./install-infrastructure.sh

# Skip importing existing deployments
sudo ./install-infrastructure.sh --skip-import
```

### What Gets Installed

The installation script will:

1. Create `/var/lib/capsule-deploy/port-registry.json` - Central port registry
2. Install `/usr/local/bin/capsule-nginx-manager` - Nginx management tool
3. Install `/usr/local/bin/capsule-port-allocator` - Port allocation tool
4. Configure `/etc/sudoers.d/capsule-deploy` - Sudo permissions
5. Install helper scripts to `~/deployments/scripts/`
6. Import existing port allocations (if found)
7. Run verification tests

## Installed Components

### 1. Port Registry (`/var/lib/capsule-deploy/port-registry.json`)

Central registry tracking all port allocations:

```json
{
  "meta": {
    "last_updated": "2026-01-22T00:00:00Z",
    "format_version": "1.0",
    "description": "Central registry of allocated ports for all deployed apps"
  },
  "allocations": {
    "app-name": {
      "frontend": 3001,
      "backend": 8001,
      "database": 5432
    }
  }
}
```

### 2. Capsule Nginx Manager (`/usr/local/bin/capsule-nginx-manager`)

Manages nginx configurations for deployed apps.

**Usage:**
```bash
# Add nginx configuration for an app
sudo capsule-nginx-manager add-multiservice myapp 3001 8001

# Remove nginx configuration
sudo capsule-nginx-manager remove myapp

# Reload nginx
sudo capsule-nginx-manager reload

# Test nginx configuration
sudo capsule-nginx-manager test
```

**What it does:**
- Creates upstream definitions in `/etc/nginx/conf.d/system-upstreams/`
- Creates route configurations in `/etc/nginx/conf.d/routes/`
- Configures OAuth2 protection
- Sets up API proxying
- Adds static asset caching for Next.js apps

### 3. Capsule Port Allocator (`/usr/local/bin/capsule-port-allocator`)

Automatically allocates available ports for new deployments.

**Usage:**
```bash
# Allocate ports for a new app
sudo capsule-port-allocator allocate myapp frontend backend database

# List all port allocations
sudo capsule-port-allocator list

# Free ports for an app
sudo capsule-port-allocator free myapp
```

**Port allocation strategy:**
- Frontend/Dashboard: Base port + 1
- Backend/API: Base port + 5000
- Database: Base port + 2000
- Other services: Base port + 100

### 4. Pre-Deploy Validator (`~/deployments/scripts/pre-deploy-validate.sh`)

Validates project structure before deployment.

**Usage:**
```bash
~/deployments/scripts/pre-deploy-validate.sh /path/to/app app-name
```

**Checks:**
- Framework detection (Next.js, etc.)
- Required directories exist
- docker-compose.yml is present
- API URL format is correct
- No common configuration errors

### 5. Post-Deploy Health Check (`~/deployments/scripts/post-deploy-healthcheck.sh`)

Validates deployment health after completion.

**Usage:**
```bash
~/deployments/scripts/post-deploy-healthcheck.sh /path/to/app app-name [host]
```

**Checks:**
- All containers are running
- Frontend responds on local port
- HTTPS endpoint is accessible
- No excessive errors in logs

## Verification

After installation, verify everything is working:

```bash
cd /home/ubuntu/src/deploy-portal/infrastructure
./tests/verify-infrastructure.sh
```

This will run comprehensive tests on all components.

## Usage in Deployments

The deployment automation scripts in `deploy-portal/automation/` use these infrastructure components automatically. You don't need to call them directly during normal deployment workflows.

However, you can use them manually when needed:

```bash
# Example: Manual deployment with infrastructure tools

# 1. Allocate ports
PORTS=$(sudo capsule-port-allocator allocate myapp frontend backend database)
FRONTEND_PORT=$(echo "$PORTS" | grep frontend | cut -d: -f2)
BACKEND_PORT=$(echo "$PORTS" | grep backend | cut -d: -f2)

# 2. Validate before deploying
~/deployments/scripts/pre-deploy-validate.sh ~/deployments/myapp myapp

# 3. Deploy your app (docker-compose, etc.)
# ... deployment steps ...

# 4. Configure nginx
sudo capsule-nginx-manager add-multiservice myapp $FRONTEND_PORT $BACKEND_PORT
sudo capsule-nginx-manager reload

# 5. Health check
~/deployments/scripts/post-deploy-healthcheck.sh ~/deployments/myapp myapp
```

## Troubleshooting

### Port registry locked

If you get a lock error:
```bash
sudo rm -f /var/lib/capsule-deploy/port-registry.lock
```

### Sudo permissions not working

Verify sudoers configuration:
```bash
sudo visudo -c
cat /etc/sudoers.d/capsule-deploy
```

### Nginx configuration test fails

Check nginx error logs:
```bash
sudo nginx -t
sudo tail -f /var/log/nginx/error.log
```

### Reset everything

To completely remove and reinstall:
```bash
# Remove installed components
sudo rm -f /usr/local/bin/capsule-nginx-manager
sudo rm -f /usr/local/bin/capsule-port-allocator
sudo rm -f /etc/sudoers.d/capsule-deploy
sudo rm -rf /var/lib/capsule-deploy
rm -rf ~/deployments/scripts

# Reinstall
cd /home/ubuntu/src/deploy-portal/infrastructure
sudo ./install-infrastructure.sh
```

## Integration with Deploy Portal

The Deploy Portal (`/home/ubuntu/src/deploy-portal/`) uses these infrastructure tools in its automation scripts (`automation/deploy-app.sh`, etc.). When you deploy through the portal, these tools are called automatically.

## Maintenance

### Backup port registry

```bash
sudo cp /var/lib/capsule-deploy/port-registry.json \
       /var/lib/capsule-deploy/port-registry.json.backup-$(date +%Y%m%d)
```

### Update infrastructure

To update to the latest version:
```bash
cd /home/ubuntu/src/deploy-portal
git pull
cd infrastructure
sudo ./install-infrastructure.sh
```

## Security Notes

- These tools run with elevated privileges (sudo)
- The sudoers configuration is restricted to specific commands only
- Port registry is world-readable but only writable by root
- All scripts validate input before execution
- Nginx configurations are tested before reload

## Contributing

When modifying infrastructure components:

1. Test changes locally first
2. Update this README if adding new features
3. Add tests to `tests/verify-infrastructure.sh`
4. Commit changes to git
5. Deploy to server using `install-infrastructure.sh`

## Version Control

This infrastructure is version-controlled in the `deploy-portal` repository. To deploy to a new server:

```bash
# On new server
git clone <repo> /home/ubuntu/src/deploy-portal
cd /home/ubuntu/src/deploy-portal/infrastructure
sudo ./install-infrastructure.sh
```

## Files Created by Installation

```
/var/lib/capsule-deploy/
├── port-registry.json          # Central port allocation registry
└── port-registry.lock          # Lock file for atomic updates

/usr/local/bin/
├── capsule-nginx-manager       # Nginx management tool
└── capsule-port-allocator      # Port allocation tool

/etc/sudoers.d/
└── capsule-deploy              # Sudo permissions

/home/ubuntu/deployments/scripts/
├── pre-deploy-validate.sh      # Pre-deployment validation
└── post-deploy-healthcheck.sh  # Post-deployment health check
```

## What This Enables

With this infrastructure in place, deployments can:

1. ✅ **Automatically allocate ports** - No manual port management
2. ✅ **Configure nginx automatically** - No manual nginx editing
3. ✅ **Validate before deploying** - Catch issues early
4. ✅ **Health check after deploying** - Verify success
5. ✅ **Track all deployments** - Central registry
6. ✅ **Prevent conflicts** - Port collision detection

## Support

For issues or questions:
- Check logs: `sudo journalctl -xe`
- Run verification: `./tests/verify-infrastructure.sh`
- Review nginx config: `sudo nginx -t`
- Check port registry: `sudo capsule-port-allocator list`
