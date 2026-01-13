#!/bin/bash
# deploy-app.sh - Master Deployment Orchestration Script
# Automates full deployment: port allocation, nginx config, systemd service

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_ROOT="${DEPLOYMENT_ROOT:-/home/ubuntu/deployments}"
PORT_START="${PORT_START:-5001}"
PORT_END="${PORT_END:-5999}"
REGISTRY_FILE="${REGISTRY_FILE:-$DEPLOYMENT_ROOT/.registry.json}"
LOCK_FILE="${LOCK_FILE:-$DEPLOYMENT_ROOT/.deployment.lock}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Usage
usage() {
    cat << EOF
Usage: $0 <app_name> [options]

Deploy an application with automated nginx and systemd setup.

Arguments:
    app_name        Name of the application to deploy (required)

Options:
    --port PORT         Use specific port instead of auto-allocation
    --type TYPE         App type: node, python, docker, go, other (default: other)
    --start-cmd CMD     Custom start command for systemd service
    --deployed-by EMAIL Email of person deploying (for tracking)
    --skip-nginx        Skip nginx configuration
    --skip-systemd      Skip systemd service creation
    --dry-run           Show what would be done without doing it

Examples:
    $0 my-app-01
    $0 my-app-01 --type node --deployed-by user@example.com
    $0 my-app-01 --port 5010 --start-cmd "npm start"

EOF
    exit 1
}

# Cleanup function for rollback
cleanup_on_error() {
    local app_name="$1"
    local step="$2"

    log_error "Deployment failed at step: $step"
    log_info "Rolling back changes..."

    # Remove from registry
    if bash "$SCRIPT_DIR/registry-manager.sh" check "$app_name" 2>/dev/null; then
        bash "$SCRIPT_DIR/registry-manager.sh" remove "$app_name" 2>/dev/null || true
        log_info "Removed from registry"
    fi

    # Remove nginx config
    if bash "$SCRIPT_DIR/nginx-register.sh" exists "$app_name" 2>/dev/null; then
        bash "$SCRIPT_DIR/nginx-register.sh" remove "$app_name" 2>/dev/null || true
        log_info "Removed nginx location block"
    fi

    # Remove systemd service
    if bash "$SCRIPT_DIR/systemd-register.sh" exists "$app_name" 2>/dev/null; then
        bash "$SCRIPT_DIR/systemd-register.sh" remove "$app_name" 2>/dev/null || true
        log_info "Removed systemd service"
    fi

    log_error "Rollback complete. Please fix the issue and try again."
    exit 1
}

# Parse arguments
APP_NAME=""
PORT=""
APP_TYPE="other"
START_CMD=""
DEPLOYED_BY="${USER}@$(hostname)"
SKIP_NGINX=false
SKIP_SYSTEMD=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --port)
            PORT="$2"
            shift 2
            ;;
        --type)
            APP_TYPE="$2"
            shift 2
            ;;
        --start-cmd)
            START_CMD="$2"
            shift 2
            ;;
        --deployed-by)
            DEPLOYED_BY="$2"
            shift 2
            ;;
        --skip-nginx)
            SKIP_NGINX=true
            shift
            ;;
        --skip-systemd)
            SKIP_SYSTEMD=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [[ -z "$APP_NAME" ]]; then
                APP_NAME="$1"
            else
                log_error "Unknown argument: $1"
                usage
            fi
            shift
            ;;
    esac
done

# Validate app name
if [[ -z "$APP_NAME" ]]; then
    log_error "App name is required"
    usage
fi

if [[ ! "$APP_NAME" =~ ^[a-z0-9][a-z0-9-]{0,30}[a-z0-9]$ ]]; then
    log_error "Invalid app name format. Use lowercase letters, numbers, and hyphens only (2-32 characters)"
    exit 1
fi

# Export configuration for subscripts
export PORT_START PORT_END REGISTRY_FILE DEPLOYMENT_ROOT

# Deployment directory
APP_DIR="$DEPLOYMENT_ROOT/$APP_NAME"

log_info "========================================="
log_info "Deploying: $APP_NAME"
log_info "Type: $APP_TYPE"
log_info "Deployed by: $DEPLOYED_BY"
if [[ -n "$PORT" ]]; then
    log_info "Port: $PORT (specified)"
fi
if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY RUN MODE - No changes will be made"
fi
log_info "========================================="

# Pre-flight checks
log_info "Running pre-flight checks..."

# Check if app already exists in registry
if bash "$SCRIPT_DIR/registry-manager.sh" check "$APP_NAME" 2>/dev/null; then
    log_error "App '$APP_NAME' already exists in deployment registry"
    log_info "Use a different app name or remove the existing deployment first"
    exit 1
fi

# Check if deployment directory exists
if [[ -d "$APP_DIR" ]]; then
    log_warning "Directory already exists: $APP_DIR"
    log_info "Contents will be used for deployment"
else
    log_error "Deployment directory does not exist: $APP_DIR"
    log_info "Please create the directory and add your application files first"
    log_info "Example: mkdir -p $APP_DIR && cp -r /path/to/your/app/* $APP_DIR/"
    exit 1
fi

# Check if required tools are available
for tool in jq netstat sed awk; do
    if ! command -v $tool &> /dev/null; then
        log_error "Required tool not found: $tool"
        exit 1
    fi
done

log_success "Pre-flight checks passed"

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Would proceed with deployment..."
    exit 0
fi

# Step 1: Allocate port
log_info "Step 1/4: Allocating port..."

if [[ -z "$PORT" ]]; then
    PORT=$(bash "$SCRIPT_DIR/port-allocator.sh" allocate "$APP_NAME")
    if [[ $? -ne 0 || -z "$PORT" ]]; then
        cleanup_on_error "$APP_NAME" "port_allocation"
    fi
    log_success "Allocated port: $PORT"
else
    # Verify specified port is available
    if ! bash "$SCRIPT_DIR/port-allocator.sh" check "$PORT" 2>/dev/null; then
        log_error "Specified port $PORT is already in use"
        exit 1
    fi
    log_success "Using specified port: $PORT"
fi

# Step 2: Register in deployment registry
log_info "Step 2/4: Registering in deployment registry..."

if ! bash "$SCRIPT_DIR/registry-manager.sh" add "$APP_NAME" "$PORT" "$DEPLOYED_BY" "$APP_TYPE"; then
    cleanup_on_error "$APP_NAME" "registry_registration"
fi

log_success "Registered in deployment registry"

# Step 3: Configure nginx
if [[ "$SKIP_NGINX" == "false" ]]; then
    log_info "Step 3/4: Configuring nginx..."

    if ! bash "$SCRIPT_DIR/nginx-register.sh" add "$APP_NAME" "$PORT"; then
        cleanup_on_error "$APP_NAME" "nginx_configuration"
    fi

    log_success "Nginx location block added"

    # Reload nginx
    log_info "Reloading nginx..."
    if ! bash "$SCRIPT_DIR/nginx-register.sh" reload; then
        cleanup_on_error "$APP_NAME" "nginx_reload"
    fi

    log_success "Nginx reloaded"
else
    log_warning "Skipping nginx configuration (--skip-nginx)"
fi

# Step 4: Create and start systemd service
if [[ "$SKIP_SYSTEMD" == "false" ]]; then
    log_info "Step 4/4: Creating systemd service..."

    # Create service
    if [[ -n "$START_CMD" ]]; then
        if ! bash "$SCRIPT_DIR/systemd-register.sh" create "$APP_NAME" "$PORT" "$START_CMD" "$APP_TYPE"; then
            cleanup_on_error "$APP_NAME" "systemd_creation"
        fi
    else
        if ! bash "$SCRIPT_DIR/systemd-register.sh" create "$APP_NAME" "$PORT" "" "$APP_TYPE"; then
            cleanup_on_error "$APP_NAME" "systemd_creation"
        fi
    fi

    log_success "Systemd service created: ${APP_NAME}.service"

    # Start service
    log_info "Starting service..."
    if ! bash "$SCRIPT_DIR/systemd-register.sh" start "$APP_NAME"; then
        log_warning "Service may have failed to start. Check logs with: journalctl -u ${APP_NAME}.service"
        log_info "You can manually start it later with: sudo systemctl start ${APP_NAME}.service"
    else
        log_success "Service started successfully"
    fi
else
    log_warning "Skipping systemd service creation (--skip-systemd)"
fi

# Deployment complete
log_success "========================================="
log_success "Deployment complete!"
log_success "========================================="
log_info ""
log_info "App Name:       $APP_NAME"
log_info "Port:           $PORT"
log_info "Directory:      $APP_DIR"
log_info "URL Path:       /$APP_NAME/"
log_info "Service:        ${APP_NAME}.service"
log_info ""
log_info "Next steps:"
log_info "  1. Verify service is running: sudo systemctl status ${APP_NAME}.service"
log_info "  2. Check logs: journalctl -u ${APP_NAME}.service -f"
log_info "  3. Test your app: curl http://localhost:$PORT/"
log_info "  4. Access via nginx: https://$(hostname -I | awk '{print $1}')/$APP_NAME/"
log_info ""
log_info "Deployment registry: $REGISTRY_FILE"
log_info "View all deployments: bash $SCRIPT_DIR/registry-manager.sh list"
log_info ""
