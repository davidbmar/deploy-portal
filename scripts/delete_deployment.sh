#!/bin/bash
# delete_deployment.sh - Comprehensive deployment cleanup
# Usage: ./delete_deployment.sh <app-name>
# Based on: docs/DELETE_FUNCTION_ISSUES.md

set +e  # Don't exit on error - we want to continue cleanup even if steps fail

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
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)] ⚠️${NC} $1" >&2; }
error() { echo -e "${RED}[$(date +%H:%M:%S)] ❌${NC} $1" >&2; }

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
log "Backing up and removing Docker volumes..."
VOLUMES=$(sg docker -c "docker volume ls -q --filter name=${APP_NAME}" 2>/dev/null || true)
if [ -n "$VOLUMES" ]; then
  for VOLUME in $VOLUMES; do
    BACKUP_FILE="${BACKUP_DIR}/${VOLUME}-${TIMESTAMP}.tar.gz"
    log "Backing up volume $VOLUME..."

    if sg docker -c "docker run --rm -v ${VOLUME}:/data -v ${BACKUP_DIR}:/backup alpine tar czf /backup/$(basename $BACKUP_FILE) -C /data ." 2>/dev/null; then
      log "✅ Volume backed up: $VOLUME"

      # Remove volume after backup
      if sg docker -c "docker volume rm ${VOLUME}" 2>/dev/null; then
        log "✅ Volume removed: $VOLUME"
      else
        warn "Failed to remove volume: $VOLUME (may be in use)"
      fi
    else
      warn "Failed to backup volume: $VOLUME (attempting removal anyway)"
      sg docker -c "docker volume rm ${VOLUME}" 2>/dev/null || warn "Could not remove $VOLUME"
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

  # Use grep to remove all lines containing the app name, then clean up empty lines
  log "Removing nginx configuration for $APP_NAME..."

  # Create temp file without app-related lines
  sudo grep -v "$APP_NAME" "$NGINX_CONFIG" | sudo tee /tmp/cleaned-nginx-$APP_NAME > /dev/null

  # Test new configuration
  if sudo cp /tmp/cleaned-nginx-$APP_NAME "$NGINX_CONFIG" && sudo nginx -t 2>/dev/null; then
    sudo systemctl reload nginx
    log "✅ Nginx configuration cleaned and reloaded"
    sudo rm /tmp/cleaned-nginx-$APP_NAME
  else
    error "Nginx configuration test failed, restoring backup"
    sudo cp "$NGINX_BACKUP" "$NGINX_CONFIG"

    # Try to find and restore a known-good backup
    LATEST_CLEAN=$(ls -t ${NGINX_CONFIG}.backup-pre-deploy ${NGINX_CONFIG}.backup-before-* 2>/dev/null | head -1)

    if [ -n "$LATEST_CLEAN" ]; then
      warn "Attempting restore from clean backup: $LATEST_CLEAN"
      sudo cp "$LATEST_CLEAN" "$NGINX_CONFIG"

      if sudo nginx -t 2>/dev/null; then
        sudo systemctl reload nginx
        log "✅ Nginx restored from clean backup"
      else
        error "Failed to restore nginx - manual intervention required"
      fi
    fi

    sudo rm -f /tmp/cleaned-nginx-$APP_NAME
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
    sudo lsof -i :$PORT | tail -n +2
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
  log "✅ Registry backed up"
else
  log "No registry file found"
fi

# ============================================================================
# STEP 6: Systemd Services (if applicable)
# ============================================================================
log "Step 6: Checking for systemd services..."

if systemctl list-units --all 2>/dev/null | grep -q "$APP_NAME"; then
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
log "✅ Cleanup completed"
log "==============================================="

exit 0
