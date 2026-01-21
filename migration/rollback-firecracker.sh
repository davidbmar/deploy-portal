#!/bin/bash
#
# Rollback from Firecracker to Previous Deployment
# Restores Docker/systemd deployment from backup
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_ROOT="${DEPLOYMENT_ROOT:-/home/ubuntu/deployments}"
BACKUP_ROOT="${BACKUP_ROOT:-/home/ubuntu/backups}"
REGISTRY_FILE="${REGISTRY_FILE:-$DEPLOYMENT_ROOT/.registry.json}"
FIRECRACKER_WRAPPER="$SCRIPT_DIR/../firecracker/docker-compose-fc.sh"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

usage() {
    cat << EOF
Usage: $0 <app_name> [backup_dir]

Rollback Firecracker deployment to previous Docker/systemd deployment

Arguments:
    app_name    Name of the application to rollback
    backup_dir  Specific backup directory to restore (optional, uses latest if not specified)

Examples:
    $0 my-app-01
    $0 my-app-01 /home/ubuntu/backups/my-app-01-20260119-120000

EOF
    exit 1
}

# Parse arguments
APP_NAME="${1:-}"
BACKUP_DIR="${2:-}"

if [ -z "$APP_NAME" ]; then
    log_error "App name is required"
    usage
fi

APP_DIR="$DEPLOYMENT_ROOT/$APP_NAME"

log_info "========================================="
log_info "Rolling back: $APP_NAME from Firecracker"
log_info "========================================="

# Step 1: Stop Firecracker VM
log_info "Step 1/4: Stopping Firecracker VM..."

if [ -f "$FIRECRACKER_WRAPPER" ]; then
    if bash "$FIRECRACKER_WRAPPER" "$APP_NAME" down 2>/dev/null; then
        log_success "Firecracker VM stopped"
    else
        log_warning "Failed to stop VM or VM not running"
    fi
else
    log_warning "Firecracker wrapper not found"
fi

# Step 2: Find or verify backup
log_info "Step 2/4: Locating backup..."

if [ -z "$BACKUP_DIR" ]; then
    # Find latest backup
    BACKUP_DIR=$(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "${APP_NAME}-*" | sort -r | head -n 1)

    if [ -z "$BACKUP_DIR" ]; then
        log_error "No backup found for $APP_NAME in $BACKUP_ROOT"
        log_info "Cannot rollback without backup"
        exit 1
    fi

    log_info "Using latest backup: $BACKUP_DIR"
else
    if [ ! -d "$BACKUP_DIR" ]; then
        log_error "Backup directory not found: $BACKUP_DIR"
        exit 1
    fi
    log_info "Using specified backup: $BACKUP_DIR"
fi

# Step 3: Restore from backup
log_info "Step 3/4: Restoring from backup..."

# Backup current state (in case rollback fails)
if [ -d "$APP_DIR" ]; then
    TEMP_BACKUP="$APP_DIR.rollback-temp-$(date +%Y%m%d-%H%M%S)"
    mv "$APP_DIR" "$TEMP_BACKUP"
    log_info "Current state backed up to: $TEMP_BACKUP"
fi

# Restore files
cp -r "$BACKUP_DIR" "$APP_DIR"

# Restore registry if backup exists
if [ -f "$BACKUP_DIR/registry.json.backup" ]; then
    cp "$BACKUP_DIR/registry.json.backup" "$REGISTRY_FILE"
    log_success "Registry restored"
fi

log_success "Files restored from backup"

# Step 4: Restart previous deployment
log_info "Step 4/4: Restarting previous deployment..."

# Get deployment info
PORT=$(jq -r ".\"$APP_NAME\".port" "$REGISTRY_FILE" 2>/dev/null || echo "")
APP_TYPE=$(jq -r ".\"$APP_NAME\".type" "$REGISTRY_FILE" 2>/dev/null || echo "other")

if [ -z "$PORT" ]; then
    log_warning "Could not determine port from registry"
fi

# Try to start systemd service
if [ -f "/etc/systemd/system/${APP_NAME}.service" ]; then
    log_info "Starting systemd service..."
    sudo systemctl start "${APP_NAME}.service"
    sudo systemctl enable "${APP_NAME}.service"

    if systemctl is-active --quiet "${APP_NAME}.service"; then
        log_success "Systemd service started"
    else
        log_error "Failed to start systemd service"
        log_info "Check logs: journalctl -u ${APP_NAME}.service"
    fi

# Try to start Docker containers
elif [ -f "$APP_DIR/docker-compose.yml" ]; then
    log_info "Starting Docker containers..."
    cd "$APP_DIR"
    if docker-compose up -d; then
        log_success "Docker containers started"
    else
        log_error "Failed to start Docker containers"
        log_info "Check logs: docker-compose logs"
    fi
else
    log_warning "No systemd service or docker-compose.yml found"
    log_info "Manual restart may be required"
fi

# Update registry to remove Firecracker isolation
if [ -f "$REGISTRY_FILE" ]; then
    jq "del(.\"$APP_NAME\".isolation)" "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp"
    mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
    log_info "Registry updated (removed Firecracker isolation)"
fi

# Rollback complete
log_success "========================================="
log_success "Rollback complete!"
log_success "========================================="
log_info ""
log_info "App Name:       $APP_NAME"
log_info "Restored from:  $BACKUP_DIR"
if [ -n "$PORT" ]; then
    log_info "Port:           $PORT"
fi
log_info ""
log_info "Verify deployment:"
log_info "  Systemd: sudo systemctl status ${APP_NAME}.service"
log_info "  Docker:  docker-compose ps"
log_info ""
