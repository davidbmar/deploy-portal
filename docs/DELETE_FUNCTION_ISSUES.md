# Deployment Cleanup Analysis & Delete Function Requirements

**Date:** 2026-01-13
**Deployments Analyzed:** `my-app-01-test`, `myappsecondinstanceofjohnsapp`
**Server:** 52.43.35.1 (Ubuntu on EC2)

---

## Executive Summary

During deployment of two applications to the same server, multiple cleanup issues were encountered that prevented successful deployment. The existing delete function did not properly clean up Docker containers, nginx configurations, or port allocations, requiring extensive manual intervention.

---

## 1. Issues Encountered During Deployment

### Issue 1.1: Port Conflicts
**Problem:** Ports 3000, 8000, and 5432 were already in use when attempting to deploy the second application.

**Evidence:**
```
Error response from daemon: failed to bind host port for 0.0.0.0:3000:172.18.0.4:3000/tcp: address already in use
```

**Root Cause:** Previous deployment was not fully cleaned up, leaving Docker containers running and consuming ports.

**Impact:** Deployment failed during container startup. Required manual port reassignment to 3001, 8001, 5433.

---

### Issue 1.2: Docker Container Name Conflicts
**Problem:** Container names like `zendesk-ai-postgres`, `zendesk-ai-backend`, and `zendesk-ai-dashboard` were already in use.

**Evidence:**
```
Error response from daemon: Conflict. The container name "/zendesk-ai-postgres" is already in use by container "859074f907d56b2af9d493904e411b0c731923b424cf5cc95afe84baf6c1e8a7"
```

**Root Cause:** Previous deployment's containers were not removed, even though they appeared stopped.

**Impact:** Required manual container name changes (added "-2" suffix) to avoid conflicts.

---

### Issue 1.3: Nginx Configuration Accumulation
**Problem:** Nginx configuration file accumulated **5+ duplicate location blocks** for `my-app-01-test` from multiple deployment attempts.

**Evidence:**
```bash
$ sudo grep -c 'location /my-app-01-test/' /etc/nginx/sites-available/auth-gateway
5
```

**Duplicate Errors:**
```
nginx: [emerg] duplicate location "/my-app-01-test" in /etc/nginx/sites-enabled/auth-gateway:293
nginx: configuration file /etc/nginx/nginx.conf test failed
```

**Root Cause:**
- Each deployment attempt added new location blocks without removing old ones
- Failed deployments left partial configurations
- No cleanup between deployment attempts
- Delete function did not properly remove nginx entries

**Impact:**
- Nginx failed to reload with configuration errors
- Required manual identification and removal of all duplicate blocks
- Had to restore from clean backup (`auth-gateway.backup-pre-deploy`)

---

### Issue 1.4: Deployment Directory Not Cleaned
**Problem:** When checking for existing deployments, the `/home/ubuntu/deployments/` directory was empty, yet ports and containers were still active.

**Evidence:**
```bash
$ ls -la ~/deployments/
total 16
drwxrwxr-x  3 ubuntu ubuntu 4096 Jan 13 03:34 .
drwxr-x--x 15 ubuntu ubuntu 4096 Jan 13 03:32 ..
drwxrwxr-x  2 ubuntu ubuntu 4096 Jan 13 01:26 .backups
-rw-r--r--  1 ubuntu ubuntu    3 Jan 13 01:06 .registry.json
```

Yet Docker containers and nginx configs from previous deployments persisted.

**Root Cause:** Delete function removed the directory but not the running services or configurations.

**Impact:** Ghost deployments consuming resources without visible directories.

---

## 2. Leftover Files/Configurations That Blocked Deployment

### 2.1 Docker Resources (Critical)

#### Running Containers
```bash
# These should have been removed but weren't:
node        *:3000 (LISTEN)  # Some process on port 3000
docker-pr   *:5432 (LISTEN)  # Postgres proxy
docker-pr   *:8000 (LISTEN)  # Backend proxy
docker-pr   *:3001 (LISTEN)  # Frontend proxy
```

#### Docker Networks
- `my-app-01-test_default`
- `myappsecondinstanceofjohnsapp_default`

#### Docker Volumes
- `my-app-01-test_postgres_data`
- `myappsecondinstanceofjohnsapp_postgres_data`

**Problem:** Even after directory removal, Docker resources persisted.

---

### 2.2 Nginx Configuration Files

#### Main Config File
**File:** `/etc/nginx/sites-available/auth-gateway`

**Issues Found:**
- 5+ duplicate location blocks for `/my-app-01-test/`
- 2+ duplicate upstream definitions for `my_app_01_test_backend`
- Inconsistent upstream naming (`my-app-01-test_backend` vs `my_app_01_test_backend`)
- Multiple API location blocks (`/my-app-01-test/api/`)

**Leftover Blocks:**
```nginx
# These accumulated from multiple failed deployments:

# Duplicate 1
location /my-app-01-test/ { ... }

# Duplicate 2 (different line number)
location /my-app-01-test/ { ... }

# Duplicate 3
location /my-app-01-test/ { ... }

# Multiple upstream definitions
upstream my-app-01-test_backend { server 127.0.0.1:3000; }
upstream my_app_01_test_backend { server 127.0.0.1:3001; }
```

#### Backup Files Created
The server had multiple nginx backup files that helped recovery:
```bash
-rw-r--r-- 1 root root 15223 Jan 13 03:43 /etc/nginx/sites-available/auth-gateway.backup
-rw-r--r-- 1 root root  3752 Jan 11 21:18 /etc/nginx/sites-available/auth-gateway.backup-1768166305
-rw-r--r-- 1 root root  8300 Jan 13 01:44 /etc/nginx/sites-available/auth-gateway.backup-20260113-014423
-rw-r--r-- 1 root root  5533 Jan 13 01:26 /etc/nginx/sites-available/auth-gateway.backup-before-myapp
-rw-r--r-- 1 root root  4191 Jan 11 21:25 /etc/nginx/sites-available/auth-gateway.backup-buffer-fix
-rw-r--r-- 1 root root  4193 Jan 13 00:31 /etc/nginx/sites-available/auth-gateway.backup-pre-deploy
```

**Critical:** The clean backup `auth-gateway.backup-pre-deploy` was essential for recovery.

---

### 2.3 Port Allocations

**Ports that were blocked:**
- `3000` - Frontend (previous deployment)
- `3001` - Frontend (another previous attempt)
- `8000` - Backend (previous deployment)
- `5432` - Postgres (previous deployment)
- `5433` - Postgres (attempted workaround)

**Detection Command Used:**
```bash
sudo lsof -i -P -n | grep LISTEN | grep -E ':(300[0-9]|800[0-9]|543[0-9])'
```

---

## 3. Manual Cleanup Steps Performed

### Step 3.1: Port Reassignment
```bash
# Modified docker-compose.yml on server to use different ports:
sed -i 's/"3000:3000"/"3001:3000"/g' docker-compose.yml
sed -i 's/"8000:8000"/"8001:8000"/g' docker-compose.yml
sed -i 's/"5432:5432"/"5433:5432"/g' docker-compose.yml
```

**Then later corrected to:**
```bash
# After checking port availability:
sed -i 's/"3001:3000"/"3002:3000"/g' docker-compose.yml
sed -i 's/"8001:8000"/"8002:8000"/g' docker-compose.yml
```

---

### Step 3.2: Docker Container Name Changes
```bash
# Modified docker-compose.yml to use unique container names:
sed -i 's/container_name: zendesk-ai-postgres/container_name: zendesk-ai-postgres-2/g' docker-compose.yml
sed -i 's/container_name: zendesk-ai-backend/container_name: zendesk-ai-backend-2/g' docker-compose.yml
sed -i 's/container_name: zendesk-ai-dashboard/container_name: zendesk-ai-dashboard-2/g' docker-compose.yml
```

---

### Step 3.3: Nginx Configuration Cleanup

#### Attempt 1: Remove specific patterns (Failed)
```bash
sudo sed -i '/# my-app-01-test upstream/,/^}/d' /etc/nginx/sites-available/auth-gateway
sudo sed -i '/# Protected: my-app-01-test/,/^    }/d' /etc/nginx/sites-available/auth-gateway
```
**Result:** Created syntax errors, broke nginx config.

#### Attempt 2: Remove all matching lines (Failed)
```bash
sudo perl -i.bak2 -pe 's/.*my.*app.*01.*test.*//g' /etc/nginx/sites-available/auth-gateway
```
**Result:** Removed lines including structural elements, broke nginx.

#### Attempt 3: Restore clean backup (Success)
```bash
# Copy clean config from before any deployments:
sudo cp /etc/nginx/sites-available/auth-gateway.backup-pre-deploy /etc/nginx/sites-available/auth-gateway

# Verify syntax:
sudo nginx -t
# Output: syntax is ok

# Add configuration cleanly (only once):
# Created config file locally with proper syntax
# Uploaded via scp
# Appended to nginx config
sudo bash -c 'cat /tmp/my-app-01-test-nginx.conf >> /etc/nginx/sites-available/auth-gateway'

# Reload nginx:
sudo systemctl reload nginx
```

**Key Insight:** Restoring from a known-good backup was more reliable than trying to surgically remove duplicate entries.

---

### Step 3.4: Verification Steps
```bash
# 1. Check container status
sg docker -c 'docker-compose ps'

# 2. Test local endpoints
curl http://localhost:3001/my-app-01-test/  # Frontend
curl http://localhost:8001/docs             # Backend API

# 3. Test public HTTPS endpoint
curl -k -I https://52.43.35.1/my-app-01-test/
```

---

## 4. What The Delete Function SHOULD Have Done

### 4.1 Docker Cleanup (Critical - Not Done)

#### Stop and Remove Containers
```bash
# Navigate to deployment directory (if it exists)
cd /home/ubuntu/deployments/${APP_NAME}

# Stop all containers
sg docker -c 'docker-compose down'

# Alternative: Force stop if compose fails
sg docker -c "docker stop \$(docker ps -q --filter name=${APP_NAME})"

# Remove containers
sg docker -c "docker rm \$(docker ps -aq --filter name=${APP_NAME})"
```

**Why it failed:** Delete function likely didn't use `sg docker -c` wrapper for permission escalation.

---

#### Remove Docker Networks
```bash
# Remove project-specific network
sg docker -c "docker network rm ${APP_NAME}_default" 2>/dev/null || true
```

**Why it failed:** Networks persist after container removal if not explicitly deleted.

---

#### Remove Docker Volumes (Optional - Data Preservation)
```bash
# Option 1: Remove volumes (destroys data)
sg docker -c "docker volume rm ${APP_NAME}_postgres_data" 2>/dev/null || true

# Option 2: Backup then remove
sg docker -c "docker run --rm -v ${APP_NAME}_postgres_data:/data -v /home/ubuntu/deployments/.backups:/backup alpine tar czf /backup/${APP_NAME}-postgres-$(date +%Y%m%d-%H%M%S).tar.gz /data"
sg docker -c "docker volume rm ${APP_NAME}_postgres_data"
```

**Recommendation:** Backup volumes before deletion for data recovery.

---

### 4.2 Nginx Configuration Cleanup (Critical - Not Done)

#### Remove Upstream Definitions
```bash
# Identify the app's upstream block and remove it
sudo sed -i "/# ${APP_NAME} upstream/,/^}/d" /etc/nginx/sites-available/auth-gateway
```

#### Remove Location Blocks
```bash
# Remove all location blocks for this app (frontend, API, redirects)
sudo sed -i "/# Protected: ${APP_NAME}/,/^    }/d" /etc/nginx/sites-available/auth-gateway
sudo sed -i "/# API endpoint for ${APP_NAME}/,/^    }/d" /etc/nginx/sites-available/auth-gateway
sudo sed -i "/location = \/${APP_NAME} {/,/^    }/d" /etc/nginx/sites-available/auth-gateway
```

**Better Approach:**
```bash
# Create a backup first
sudo cp /etc/nginx/sites-available/auth-gateway /etc/nginx/sites-available/auth-gateway.backup-$(date +%s)

# Use awk to remove all blocks matching app name
sudo awk -v app="${APP_NAME}" '
  /upstream.*app.*backend/ { skip=1 }
  /location.*app/ { skip=1 }
  /^}/ && skip { skip=0; next }
  !skip
' /etc/nginx/sites-available/auth-gateway > /tmp/cleaned-gateway

# Verify syntax before replacing
sudo nginx -t -c /tmp/cleaned-gateway

# If valid, replace
sudo mv /tmp/cleaned-gateway /etc/nginx/sites-available/auth-gateway
```

#### Test and Reload Nginx
```bash
# Always test before reloading
if sudo nginx -t; then
  sudo systemctl reload nginx
  echo "✅ Nginx configuration cleaned and reloaded"
else
  echo "❌ Nginx configuration has errors, restoring backup"
  sudo cp /etc/nginx/sites-available/auth-gateway.backup-$(ls -t /etc/nginx/sites-available/auth-gateway.backup-* | head -1 | cut -d- -f5) /etc/nginx/sites-available/auth-gateway
  sudo nginx -t && sudo systemctl reload nginx
fi
```

**Why it failed:** Delete function didn't have sudo access or didn't clean nginx configs at all.

---

### 4.3 Port Cleanup (Automatic)

Ports are freed automatically when containers are stopped, but should verify:

```bash
# Check if ports are still in use after cleanup
PORTS=(3000 8000 5432)  # List of ports used by app

for PORT in "${PORTS[@]}"; do
  if sudo lsof -i :$PORT > /dev/null 2>&1; then
    echo "⚠️  Port $PORT still in use after cleanup"
    sudo lsof -i :$PORT
  else
    echo "✅ Port $PORT freed"
  fi
done
```

---

### 4.4 Directory Cleanup (Partially Done)

```bash
# Remove deployment directory
rm -rf /home/ubuntu/deployments/${APP_NAME}

# Update registry
# (Assuming .registry.json tracks deployments)
# Remove app entry from registry
```

**Current State:** This was likely done, but BEFORE cleaning up Docker/nginx.

**Correct Order:**
1. Stop and remove containers
2. Clean nginx config
3. Remove directory
4. Update registry

---

### 4.5 Systemd Services (Not Applicable, But Check)

If the app registered systemd services:

```bash
# Check for systemd services
if systemctl list-units --all | grep -q ${APP_NAME}; then
  sudo systemctl stop ${APP_NAME}
  sudo systemctl disable ${APP_NAME}
  sudo rm /etc/systemd/system/${APP_NAME}.service
  sudo systemctl daemon-reload
fi
```

**Current State:** Not applicable to this deployment, but should be checked.

---

### 4.6 Error Handling Requirements

#### Idempotent Operations
Every cleanup step should be safe to run multiple times:

```bash
# Good - won't fail if already removed
sg docker -c 'docker-compose down' 2>/dev/null || true

# Good - handles missing directory
rm -rf /home/ubuntu/deployments/${APP_NAME} 2>/dev/null || true

# Bad - will fail if container doesn't exist
docker stop my-container
```

#### Logging
```bash
# Log all cleanup actions
CLEANUP_LOG="/home/ubuntu/deployments/.backups/cleanup-${APP_NAME}-$(date +%Y%m%d-%H%M%S).log"

{
  echo "=== Cleanup started: $(date) ==="
  echo "App: ${APP_NAME}"

  # ... cleanup commands with output ...

  echo "=== Cleanup completed: $(date) ==="
} 2>&1 | tee "$CLEANUP_LOG"
```

#### Partial Failure Recovery
```bash
# If Docker cleanup fails, still attempt nginx cleanup
if ! sg docker -c 'docker-compose down'; then
  echo "⚠️  Docker cleanup failed, continuing with nginx..." >&2
fi

# If nginx cleanup fails, still remove directory
if ! sudo nginx -t; then
  echo "⚠️  Nginx config has errors after cleanup" >&2
  # Restore backup
  sudo cp /etc/nginx/sites-available/auth-gateway.backup-pre-deploy /etc/nginx/sites-available/auth-gateway
fi

# Always attempt to remove directory as last step
rm -rf /home/ubuntu/deployments/${APP_NAME}
```

---

## 5. Recommended Delete Function Implementation

### 5.1 Complete Delete Function Script

```bash
#!/bin/bash
# delete_deployment.sh - Comprehensive deployment cleanup
# Usage: ./delete_deployment.sh <app-name>

set -e  # Exit on error (but we'll handle errors explicitly)

APP_NAME="$1"
DEPLOYMENTS_DIR="/home/ubuntu/deployments"
BACKUP_DIR="${DEPLOYMENTS_DIR}/.backups"
NGINX_CONFIG="/etc/nginx/sites-available/auth-gateway"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)] ⚠️${NC} $1"; }
error() { echo -e "${RED}[$(date +%H:%M:%S)] ❌${NC} $1"; }

# Validate input
if [ -z "$APP_NAME" ]; then
  error "Usage: $0 <app-name>"
  exit 1
fi

log "Starting cleanup for: $APP_NAME"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Start logging
CLEANUP_LOG="${BACKUP_DIR}/cleanup-${APP_NAME}-${TIMESTAMP}.log"
exec > >(tee -a "$CLEANUP_LOG") 2>&1

log "Cleanup log: $CLEANUP_LOG"

# ============================================================================
# STEP 1: Docker Cleanup
# ============================================================================
log "Step 1: Cleaning up Docker resources..."

APP_DIR="${DEPLOYMENTS_DIR}/${APP_NAME}"

if [ -d "$APP_DIR" ]; then
  cd "$APP_DIR"

  # Stop and remove containers via docker-compose
  if [ -f "docker-compose.yml" ]; then
    log "Stopping containers via docker-compose..."
    if sg docker -c 'docker-compose down -v' 2>/dev/null; then
      log "✅ Containers stopped and removed via docker-compose"
    else
      warn "docker-compose down failed, trying manual cleanup..."

      # Manual container cleanup
      CONTAINERS=$(sg docker -c "docker ps -aq --filter name=${APP_NAME}" 2>/dev/null || true)
      if [ -n "$CONTAINERS" ]; then
        log "Stopping containers manually..."
        sg docker -c "docker stop $CONTAINERS" 2>/dev/null || true
        sg docker -c "docker rm $CONTAINERS" 2>/dev/null || true
        log "✅ Containers stopped manually"
      fi
    fi
  else
    warn "No docker-compose.yml found, checking for running containers..."

    CONTAINERS=$(sg docker -c "docker ps -aq --filter name=${APP_NAME}" 2>/dev/null || true)
    if [ -n "$CONTAINERS" ]; then
      log "Stopping containers..."
      sg docker -c "docker stop $CONTAINERS" 2>/dev/null || true
      sg docker -c "docker rm $CONTAINERS" 2>/dev/null || true
      log "✅ Containers stopped"
    else
      log "No running containers found"
    fi
  fi
else
  warn "Deployment directory not found: $APP_DIR"
  warn "Checking for orphaned containers..."

  CONTAINERS=$(sg docker -c "docker ps -aq --filter name=${APP_NAME}" 2>/dev/null || true)
  if [ -n "$CONTAINERS" ]; then
    log "Found orphaned containers, removing..."
    sg docker -c "docker stop $CONTAINERS" 2>/dev/null || true
    sg docker -c "docker rm $CONTAINERS" 2>/dev/null || true
    log "✅ Orphaned containers removed"
  fi
fi

# Remove Docker network
log "Removing Docker network..."
if sg docker -c "docker network rm ${APP_NAME}_default" 2>/dev/null; then
  log "✅ Docker network removed"
else
  log "No Docker network found (or already removed)"
fi

# Backup and remove volumes
log "Backing up Docker volumes..."
VOLUMES=$(sg docker -c "docker volume ls -q --filter name=${APP_NAME}" 2>/dev/null || true)
if [ -n "$VOLUMES" ]; then
  for VOLUME in $VOLUMES; do
    BACKUP_FILE="${BACKUP_DIR}/${VOLUME}-${TIMESTAMP}.tar.gz"
    log "Backing up volume $VOLUME to $BACKUP_FILE..."

    if sg docker -c "docker run --rm -v ${VOLUME}:/data -v ${BACKUP_DIR}:/backup alpine tar czf /backup/$(basename $BACKUP_FILE) -C /data ." 2>/dev/null; then
      log "✅ Volume backed up: $VOLUME"

      # Remove volume after backup
      if sg docker -c "docker volume rm ${VOLUME}" 2>/dev/null; then
        log "✅ Volume removed: $VOLUME"
      else
        warn "Failed to remove volume: $VOLUME"
      fi
    else
      warn "Failed to backup volume: $VOLUME"
    fi
  done
else
  log "No Docker volumes found"
fi

# ============================================================================
# STEP 2: Nginx Configuration Cleanup
# ============================================================================
log "Step 2: Cleaning up Nginx configuration..."

if [ -f "$NGINX_CONFIG" ]; then
  # Create backup
  NGINX_BACKUP="${NGINX_CONFIG}.backup-delete-${APP_NAME}-${TIMESTAMP}"
  sudo cp "$NGINX_CONFIG" "$NGINX_BACKUP"
  log "Nginx config backed up to: $NGINX_BACKUP"

  # Normalize app name for regex (replace hyphens with -)
  APP_NAME_PATTERN=$(echo "$APP_NAME" | sed 's/-/[-_]/g')

  # Create cleaned config by removing all blocks related to this app
  sudo awk -v app="$APP_NAME_PATTERN" '
    # Mark start of block to remove
    /upstream/ && $0 ~ app { in_block=1; block_depth=0 }
    /location/ && $0 ~ app { in_block=1; block_depth=0 }
    /#.*app/ && $0 ~ app { next }  # Remove comment lines

    # Track block depth
    /{/ && in_block { block_depth++ }
    /}/ && in_block {
      block_depth--
      if (block_depth <= 0) {
        in_block=0
        next
      }
    }

    # Print line if not in a block to remove
    !in_block { print }
  ' "$NGINX_CONFIG" > /tmp/cleaned-nginx-$APP_NAME

  # Test new configuration
  if sudo nginx -t -c /tmp/cleaned-nginx-$APP_NAME 2>/dev/null; then
    sudo mv /tmp/cleaned-nginx-$APP_NAME "$NGINX_CONFIG"
    sudo systemctl reload nginx
    log "✅ Nginx configuration cleaned and reloaded"
  else
    error "Nginx configuration test failed, keeping original"
    error "Manual cleanup may be required"
    sudo rm /tmp/cleaned-nginx-$APP_NAME

    # Attempt to restore backup if current config is broken
    if ! sudo nginx -t 2>/dev/null; then
      warn "Current nginx config is broken, attempting to restore from backup..."

      # Find most recent clean backup
      LATEST_BACKUP=$(ls -t ${NGINX_CONFIG}.backup-pre-deploy ${NGINX_CONFIG}.backup-before-* 2>/dev/null | head -1)

      if [ -n "$LATEST_BACKUP" ] && [ -f "$LATEST_BACKUP" ]; then
        sudo cp "$LATEST_BACKUP" "$NGINX_CONFIG"

        if sudo nginx -t 2>/dev/null; then
          sudo systemctl reload nginx
          log "✅ Nginx restored from clean backup: $LATEST_BACKUP"
        else
          error "Failed to restore nginx from backup"
        fi
      else
        error "No clean backup found to restore"
      fi
    fi
  fi
else
  warn "Nginx config not found: $NGINX_CONFIG"
fi

# ============================================================================
# STEP 3: Port Verification
# ============================================================================
log "Step 3: Verifying ports are freed..."

# Common ports used by deployments
COMMON_PORTS=(3000 3001 3002 8000 8001 8002 5432 5433)

for PORT in "${COMMON_PORTS[@]}"; do
  if sudo lsof -i :$PORT > /dev/null 2>&1; then
    warn "Port $PORT still in use:"
    sudo lsof -i :$PORT
  fi
done

log "✅ Port check complete"

# ============================================================================
# STEP 4: Directory Cleanup
# ============================================================================
log "Step 4: Removing deployment directory..."

if [ -d "$APP_DIR" ]; then
  # Create a final backup of the entire deployment
  DEPLOY_BACKUP="${BACKUP_DIR}/${APP_NAME}-final-${TIMESTAMP}.tar.gz"
  log "Creating final backup: $DEPLOY_BACKUP"

  tar czf "$DEPLOY_BACKUP" -C "$DEPLOYMENTS_DIR" "$APP_NAME" 2>/dev/null || warn "Failed to create final backup"

  # Remove directory
  rm -rf "$APP_DIR"
  log "✅ Deployment directory removed: $APP_DIR"
else
  log "Deployment directory already removed or doesn't exist"
fi

# ============================================================================
# STEP 5: Registry Cleanup
# ============================================================================
log "Step 5: Updating registry..."

REGISTRY_FILE="${DEPLOYMENTS_DIR}/.registry.json"

if [ -f "$REGISTRY_FILE" ]; then
  # Backup registry
  cp "$REGISTRY_FILE" "${REGISTRY_FILE}.backup-${TIMESTAMP}"

  # Remove app entry from registry (if using JSON)
  # This is a placeholder - adjust based on actual registry format
  log "Registry updated (manual verification may be needed)"
else
  log "No registry file found"
fi

# ============================================================================
# STEP 6: Systemd Services (if applicable)
# ============================================================================
log "Step 6: Checking for systemd services..."

if systemctl list-units --all | grep -q "$APP_NAME"; then
  log "Found systemd service for $APP_NAME, removing..."
  sudo systemctl stop "$APP_NAME" 2>/dev/null || true
  sudo systemctl disable "$APP_NAME" 2>/dev/null || true
  sudo rm "/etc/systemd/system/${APP_NAME}.service" 2>/dev/null || true
  sudo systemctl daemon-reload
  log "✅ Systemd service removed"
else
  log "No systemd services found"
fi

# ============================================================================
# Summary
# ============================================================================
log ""
log "==============================================="
log "Cleanup Summary for: $APP_NAME"
log "==============================================="
log "Timestamp: $TIMESTAMP"
log "Log file: $CLEANUP_LOG"
log ""
log "Backups created:"
[ -f "$NGINX_BACKUP" ] && log "  - Nginx config: $NGINX_BACKUP"
[ -f "$DEPLOY_BACKUP" ] && log "  - Deployment: $DEPLOY_BACKUP"
ls ${BACKUP_DIR}/*${APP_NAME}*${TIMESTAMP}* 2>/dev/null | while read backup; do
  log "  - $(basename $backup)"
done
log ""
log "✅ Cleanup completed successfully"
log "==============================================="
```

---

### 5.2 Integration with Deploy Portal

The delete function should be callable from the deploy portal API:

```python
# In deploy portal backend
@app.post("/api/deployments/{app_name}/delete")
async def delete_deployment(app_name: str):
    """Delete a deployment and clean up all resources"""

    # Execute cleanup script on EC2 instance
    result = subprocess.run(
        ["ssh", "-i", "deploy-key.pem", "ubuntu@52.43.35.1",
         f"/home/ubuntu/src/deploy-portal/scripts/delete_deployment.sh {app_name}"],
        capture_output=True,
        text=True,
        timeout=300  # 5 minute timeout
    )

    if result.returncode == 0:
        return {
            "status": "success",
            "message": f"Deployment {app_name} deleted successfully",
            "log": result.stdout
        }
    else:
        return {
            "status": "error",
            "message": f"Cleanup failed for {app_name}",
            "error": result.stderr,
            "log": result.stdout
        }
```

---

## 6. Testing Requirements

Before deploying the delete function to production, test these scenarios:

### Test Case 1: Clean Deployment
1. Deploy app successfully
2. Verify all resources exist
3. Run delete function
4. Verify all resources removed
5. Deploy same app again successfully

### Test Case 2: Partial Deployment
1. Start deployment
2. Kill deployment mid-way (simulate failure)
3. Run delete function
4. Verify partial resources cleaned up

### Test Case 3: Orphaned Resources
1. Remove deployment directory manually
2. Leave containers/nginx config
3. Run delete function
4. Verify orphaned resources removed

### Test Case 4: Multiple Consecutive Deletes
1. Deploy app
2. Run delete function
3. Run delete function again (should be idempotent)
4. Verify no errors

### Test Case 5: Non-Existent Deployment
1. Run delete function on non-existent app
2. Verify graceful handling with appropriate message

---

## 7. Monitoring & Alerting

Add monitoring to detect cleanup failures:

```bash
# Check for orphaned containers
ORPHANED_CONTAINERS=$(sg docker -c "docker ps -a --filter status=exited --filter status=dead -q" | wc -l)

if [ $ORPHANED_CONTAINERS -gt 0 ]; then
  echo "⚠️  Warning: $ORPHANED_CONTAINERS orphaned containers found"
fi

# Check for duplicate nginx entries
DUPLICATE_LOCATIONS=$(sudo grep -c "location /.*/" /etc/nginx/sites-available/auth-gateway)

if [ $DUPLICATE_LOCATIONS -gt 10 ]; then
  echo "⚠️  Warning: Possible duplicate nginx location blocks detected"
fi

# Check for unused Docker volumes
UNUSED_VOLUMES=$(sg docker -c "docker volume ls -q" | wc -l)

if [ $UNUSED_VOLUMES -gt 5 ]; then
  echo "⚠️  Warning: $UNUSED_VOLUMES Docker volumes exist (possible orphans)"
fi
```

---

## 8. Rollback Plan

If the delete function fails catastrophically:

### Emergency Restore Procedure
```bash
# 1. Restore nginx from backup
sudo cp /etc/nginx/sites-available/auth-gateway.backup-pre-deploy /etc/nginx/sites-available/auth-gateway
sudo nginx -t && sudo systemctl reload nginx

# 2. List available volume backups
ls -lh /home/ubuntu/deployments/.backups/*postgres*.tar.gz

# 3. Restore specific volume
VOLUME_NAME="my-app-01-test_postgres_data"
BACKUP_FILE="/home/ubuntu/deployments/.backups/${VOLUME_NAME}-20260113-034500.tar.gz"

sg docker -c "docker volume create ${VOLUME_NAME}"
sg docker -c "docker run --rm -v ${VOLUME_NAME}:/data -v $(dirname $BACKUP_FILE):/backup alpine tar xzf /backup/$(basename $BACKUP_FILE) -C /data"

# 4. Restore deployment from backup
DEPLOY_BACKUP="/home/ubuntu/deployments/.backups/my-app-01-test-final-20260113-034500.tar.gz"
tar xzf "$DEPLOY_BACKUP" -C /home/ubuntu/deployments/

# 5. Restart deployment
cd /home/ubuntu/deployments/my-app-01-test
sg docker -c 'docker-compose up -d'
```

---

## 9. Key Takeaways

### What Worked
✅ Using `sg docker -c` wrapper for Docker commands
✅ Restoring nginx from clean backup
✅ Creating backups before destructive operations
✅ Port reassignment as a workaround

### What Didn't Work
❌ Manual removal of nginx location blocks
❌ Pattern-based sed/awk removal without backup
❌ Assuming directory removal = full cleanup
❌ Not checking for running containers before redeployment

### Critical Requirements for Delete Function
1. **Use `sg docker -c`** for all Docker operations
2. **Use `sudo`** for all nginx operations
3. **Create backups** before any destructive operation
4. **Test nginx config** before reloading
5. **Be idempotent** - safe to run multiple times
6. **Handle partial failures** - continue cleanup even if one step fails
7. **Log everything** - critical for debugging
8. **Verify ports freed** after cleanup

---

## Appendix A: Commands Reference

### Check Running Services
```bash
# Docker containers
sg docker -c 'docker ps -a'

# Ports in use
sudo lsof -i -P -n | grep LISTEN

# Nginx config test
sudo nginx -t

# Docker volumes
sg docker -c 'docker volume ls'

# Docker networks
sg docker -c 'docker network ls'
```

### Quick Cleanup (Emergency)
```bash
APP_NAME="my-app-01-test"

# Stop all containers
sg docker -c "docker stop \$(docker ps -aq --filter name=${APP_NAME})"

# Remove all containers
sg docker -c "docker rm \$(docker ps -aq --filter name=${APP_NAME})"

# Remove network
sg docker -c "docker network rm ${APP_NAME}_default"

# Restore nginx
sudo cp /etc/nginx/sites-available/auth-gateway.backup-pre-deploy /etc/nginx/sites-available/auth-gateway
sudo nginx -t && sudo systemctl reload nginx
```

---

**Document prepared by:** Claude (Sonnet 4.5)
**For:** Deploy Portal Development Team
**Purpose:** Improve delete function reliability and prevent deployment conflicts
