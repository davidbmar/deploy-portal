#!/bin/bash
#
# Migrate Application to Firecracker
# Blue-Green migration from Docker/systemd to Firecracker microVM
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
Usage: $0 <app_name>

Migrate an application from Docker/systemd to Firecracker microVM

Arguments:
    app_name    Name of the application to migrate

Examples:
    $0 my-app-01

EOF
    exit 1
}

# Parse arguments
APP_NAME="${1:-}"

if [ -z "$APP_NAME" ]; then
    log_error "App name is required"
    usage
fi

APP_DIR="$DEPLOYMENT_ROOT/$APP_NAME"
BACKUP_DIR="$BACKUP_ROOT/$APP_NAME-$(date +%Y%m%d-%H%M%S)"

log_info "========================================="
log_info "Migrating: $APP_NAME to Firecracker"
log_info "========================================="

# Step 1: Pre-flight checks
log_info "Step 1/6: Pre-flight checks..."

if [ ! -d "$APP_DIR" ]; then
    log_error "Application directory not found: $APP_DIR"
    exit 1
fi

if [ ! -f "$FIRECRACKER_WRAPPER" ]; then
    log_error "Firecracker wrapper not found: $FIRECRACKER_WRAPPER"
    log_info "Run: bash firecracker/install-firecracker.sh"
    exit 1
fi

if ! command -v firecracker &> /dev/null; then
    log_error "Firecracker not installed"
    log_info "Run: bash firecracker/install-firecracker.sh"
    exit 1
fi

# Check if docker-compose.yml exists
if [ ! -f "$APP_DIR/docker-compose.yml" ]; then
    log_error "docker-compose.yml not found in $APP_DIR"
    log_info "Firecracker migration requires docker-compose.yml"
    exit 1
fi

log_success "Pre-flight checks passed"

# Step 2: Backup current deployment
log_info "Step 2/6: Backing up current deployment..."

mkdir -p "$BACKUP_DIR"
cp -r "$APP_DIR"/* "$BACKUP_DIR/"
cp "$REGISTRY_FILE" "$BACKUP_DIR/registry.json.backup"

log_success "Backup created: $BACKUP_DIR"

# Step 3: Get current deployment info
log_info "Step 3/6: Gathering deployment information..."

PORT=$(jq -r ".\"$APP_NAME\".port" "$REGISTRY_FILE" 2>/dev/null || echo "")
if [ -z "$PORT" ]; then
    log_error "Application not found in registry: $APP_NAME"
    exit 1
fi

CURRENT_TYPE=$(jq -r ".\"$APP_NAME\".type" "$REGISTRY_FILE" 2>/dev/null || echo "other")

log_info "  Port: $PORT"
log_info "  Type: $CURRENT_TYPE"

# Step 4: Deploy to Firecracker (Blue-Green)
log_info "Step 4/6: Deploying to Firecracker..."

if ! bash "$FIRECRACKER_WRAPPER" "$APP_NAME" up; then
    log_error "Failed to deploy to Firecracker"
    log_info "Backup available at: $BACKUP_DIR"
    exit 1
fi

log_success "Deployed to Firecracker"

# Step 5: Health check
log_info "Step 5/6: Running health checks..."

sleep 5

# Check if VM is running
if ! bash "$SCRIPT_DIR/../firecracker/vm-manager.py" status "vm-$APP_NAME" 2>/dev/null; then
    log_error "Firecracker VM is not running"
    log_info "Rolling back..."
    bash "$SCRIPT_DIR/rollback-firecracker.sh" "$APP_NAME"
    exit 1
fi

# Try to reach the application
if command -v curl &> /dev/null; then
    if curl -f -s -o /dev/null "http://localhost:$PORT/" 2>/dev/null || \
       curl -f -s -o /dev/null "http://localhost:$PORT/health" 2>/dev/null; then
        log_success "Health check passed"
    else
        log_warning "Health check failed, but VM is running"
        log_warning "Manual verification recommended"
    fi
else
    log_warning "curl not available, skipping health check"
fi

# Step 6: Stop old deployment
log_info "Step 6/6: Stopping old deployment..."

# Stop systemd service if exists
if systemctl is-active --quiet "${APP_NAME}.service" 2>/dev/null; then
    log_info "Stopping systemd service..."
    sudo systemctl stop "${APP_NAME}.service"
    sudo systemctl disable "${APP_NAME}.service"
    log_success "Systemd service stopped"
fi

# Stop Docker containers if running
if [ -f "$APP_DIR/docker-compose.yml" ]; then
    cd "$APP_DIR"
    if docker-compose ps -q 2>/dev/null | grep -q .; then
        log_info "Stopping Docker containers..."
        docker-compose down
        log_success "Docker containers stopped"
    fi
fi

# Step 7: Update registry
log_info "Updating registry..."

# Add isolation field
jq ".\"$APP_NAME\".isolation = \"firecracker\"" "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp"
mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"

log_success "Registry updated"

# Migration complete
log_success "========================================="
log_success "Migration complete!"
log_success "========================================="
log_info ""
log_info "App Name:       $APP_NAME"
log_info "Isolation:      Firecracker microVM"
log_info "Port:           $PORT"
log_info "Backup:         $BACKUP_DIR"
log_info ""
log_info "Verify deployment:"
log_info "  Status:  bash $FIRECRACKER_WRAPPER $APP_NAME status"
log_info "  Logs:    bash $FIRECRACKER_WRAPPER $APP_NAME logs"
log_info ""
log_info "Rollback if needed:"
log_info "  bash $SCRIPT_DIR/rollback-firecracker.sh $APP_NAME"
log_info ""
