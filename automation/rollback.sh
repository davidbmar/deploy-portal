#!/bin/bash
# rollback.sh - Rollback a failed deployment
# Removes containers, nginx config, and oauth2_proxy configuration

set -euo pipefail

APP_NAME="${1:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

Rolls back a deployment by:
  1. Stopping and removing Docker containers
  2. Removing nginx configuration
  3. Removing oauth2_proxy skip routes
  4. Optionally removing deployment directory

Arguments:
  app_name  Name of the application to rollback

Examples:
  $0 my-app
  $0 pydantic-noauth-210

EOF
    exit 1
}

if [ -z "$APP_NAME" ]; then
    log_error "Missing app_name argument"
    usage
fi

echo "═══════════════════════════════════════════════════════════"
echo "  Rolling Back Deployment: $APP_NAME"
echo "═══════════════════════════════════════════════════════════"
echo ""

DEPLOYMENT_DIR="/home/ubuntu/deployments/$APP_NAME"

# ═══════════════════════════════════════════════════════════
# Step 1: Stop and Remove Containers
# ═══════════════════════════════════════════════════════════
log_info "Step 1: Stopping and removing containers..."
echo "───────────────────────────────────────────────────────────"

if [ -d "$DEPLOYMENT_DIR" ] && [ -f "$DEPLOYMENT_DIR/docker-compose.yml" ]; then
    cd "$DEPLOYMENT_DIR"

    # Check if any containers are running
    RUNNING=$(docker ps --filter "name=${APP_NAME}" --format "{{.Names}}" 2>/dev/null | wc -l)

    if [ "$RUNNING" -gt 0 ]; then
        log_info "Found $RUNNING running container(s)"

        # Stop containers
        if sg docker -c 'docker-compose down' 2>/dev/null; then
            log_success "✅ Containers stopped and removed"
        else
            log_warning "⚠️  Failed to stop containers with docker-compose"
            log_info "Attempting to stop containers individually..."

            # Try to stop containers individually
            docker ps --filter "name=${APP_NAME}" --format "{{.Names}}" | while read container; do
                docker stop "$container" 2>/dev/null || true
                docker rm "$container" 2>/dev/null || true
                log_info "   Stopped $container"
            done

            log_success "✅ Containers stopped individually"
        fi
    else
        log_info "No running containers found for $APP_NAME"
    fi

    # Remove any exited containers
    EXITED=$(docker ps -a --filter "name=${APP_NAME}" --filter "status=exited" --format "{{.Names}}" 2>/dev/null | wc -l)
    if [ "$EXITED" -gt 0 ]; then
        docker ps -a --filter "name=${APP_NAME}" --filter "status=exited" --format "{{.Names}}" | while read container; do
            docker rm "$container" 2>/dev/null || true
        done
        log_success "✅ Removed $EXITED exited container(s)"
    fi
else
    log_warning "⚠️  Deployment directory not found or missing docker-compose.yml"
    log_info "Checking for orphaned containers..."

    ORPHANED=$(docker ps -a --filter "name=${APP_NAME}" --format "{{.Names}}" 2>/dev/null | wc -l)
    if [ "$ORPHANED" -gt 0 ]; then
        docker ps -a --filter "name=${APP_NAME}" --format "{{.Names}}" | while read container; do
            docker stop "$container" 2>/dev/null || true
            docker rm "$container" 2>/dev/null || true
            log_info "   Removed $container"
        done
        log_success "✅ Removed $ORPHANED orphaned container(s)"
    else
        log_info "No containers found for $APP_NAME"
    fi
fi

echo ""

# ═══════════════════════════════════════════════════════════
# Step 2: Remove Nginx Configuration
# ═══════════════════════════════════════════════════════════
log_info "Step 2: Removing nginx configuration..."
echo "───────────────────────────────────────────────────────────"

NGINX_CONFIG="/etc/nginx/sites-available/auth-gateway"

# Backup current config
if [ -f "$NGINX_CONFIG" ]; then
    BACKUP_FILE="/etc/nginx/sites-available/auth-gateway.backup-rollback-$(date +%s)"
    sudo cp "$NGINX_CONFIG" "$BACKUP_FILE"
    log_info "Backed up nginx config to: $BACKUP_FILE"

    # Check if config contains the app
    if sudo grep -q "$APP_NAME" "$NGINX_CONFIG"; then
        # Create a temporary file for the cleaned config
        TEMP_FILE=$(mktemp)

        # Remove upstream definition
        sudo awk "/upstream ${APP_NAME}_backend/,/^}/ {next} {print}" "$NGINX_CONFIG" > "$TEMP_FILE"

        # Remove location blocks (handles multiple blocks)
        sudo awk "/location \/${APP_NAME}\//,/^    }/ {next} {print}" "$TEMP_FILE" > "${TEMP_FILE}.2"
        mv "${TEMP_FILE}.2" "$TEMP_FILE"

        # Remove redirect location block
        sudo awk "/location = \/${APP_NAME}$/,/^    }/ {next} {print}" "$TEMP_FILE" > "${TEMP_FILE}.2"
        mv "${TEMP_FILE}.2" "$TEMP_FILE"

        # Remove static assets location block
        sudo awk "/location \/${APP_NAME}\/_next\/static\//,/^    }/ {next} {print}" "$TEMP_FILE" > "${TEMP_FILE}.2"
        mv "${TEMP_FILE}.2" "$TEMP_FILE"

        # Apply the cleaned config
        sudo cp "$TEMP_FILE" "$NGINX_CONFIG"
        rm -f "$TEMP_FILE"

        # Test nginx configuration
        if sudo nginx -t 2>&1 | grep -q "syntax is ok"; then
            sudo systemctl reload nginx
            log_success "✅ Nginx configuration cleaned and reloaded"
        else
            log_error "❌ Nginx config invalid after cleanup - restoring backup"
            sudo cp "$BACKUP_FILE" "$NGINX_CONFIG"
            sudo systemctl reload nginx
            log_warning "⚠️  Restored original nginx config"
        fi
    else
        log_info "No nginx configuration found for $APP_NAME"
    fi
else
    log_warning "⚠️  Nginx config file not found"
fi

echo ""

# ═══════════════════════════════════════════════════════════
# Step 3: Remove OAuth2 Proxy Skip Route
# ═══════════════════════════════════════════════════════════
log_info "Step 3: Removing oauth2_proxy skip route..."
echo "───────────────────────────────────────────────────────────"

OAUTH2_CONFIG="/etc/oauth2-proxy/config.cfg"

if [ -f "$OAUTH2_CONFIG" ]; then
    # Backup config
    sudo cp "$OAUTH2_CONFIG" "${OAUTH2_CONFIG}.backup-rollback-$(date +%s)"

    # Check if skip route exists
    if sudo grep -q "^/${APP_NAME}/" "$OAUTH2_CONFIG"; then
        # Remove the skip route line
        sudo sed -i "/\"^\/${APP_NAME}\/.*\"/d" "$OAUTH2_CONFIG"

        # Restart oauth2-proxy
        if sudo systemctl restart oauth2-proxy; then
            log_success "✅ OAuth2 proxy skip route removed and service restarted"
        else
            log_warning "⚠️  Failed to restart oauth2-proxy service"
        fi
    else
        log_info "No oauth2_proxy skip route found for $APP_NAME"
    fi
else
    log_warning "⚠️  OAuth2 proxy config file not found"
fi

echo ""

# ═══════════════════════════════════════════════════════════
# Step 4: Remove Deployment Directory (Optional)
# ═══════════════════════════════════════════════════════════
log_info "Step 4: Deployment directory cleanup..."
echo "───────────────────────────────────────────────────────────"

if [ -d "$DEPLOYMENT_DIR" ]; then
    log_warning "Deployment directory exists: $DEPLOYMENT_DIR"

    # Check if directory has git repository
    if [ -d "$DEPLOYMENT_DIR/.git" ]; then
        log_warning "Directory contains a git repository"
    fi

    # Ask user if they want to remove it
    read -p "Remove deployment directory? (y/N) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$DEPLOYMENT_DIR"
        log_success "✅ Deployment directory removed"
    else
        log_info "Keeping deployment directory"
    fi
else
    log_info "Deployment directory does not exist"
fi

echo ""

# ═══════════════════════════════════════════════════════════
# Rollback Summary
# ═══════════════════════════════════════════════════════════
echo "═══════════════════════════════════════════════════════════"
echo "  Rollback Summary"
echo "═══════════════════════════════════════════════════════════"

log_success "✅ Rollback complete for $APP_NAME"
echo ""
log_info "What was cleaned up:"
log_info "  • Docker containers stopped and removed"
log_info "  • Nginx configuration cleaned"
log_info "  • OAuth2 proxy skip routes removed"
if [[ ${REPLY:-} =~ ^[Yy]$ ]]; then
    log_info "  • Deployment directory removed"
fi

echo ""
log_info "Backup files created:"
log_info "  • Nginx: $BACKUP_FILE"
log_info "  • OAuth2: ${OAUTH2_CONFIG}.backup-rollback-$(date +%s)"

echo ""
log_info "To verify cleanup:"
log_info "  • Check containers: docker ps -a | grep $APP_NAME"
log_info "  • Check nginx: sudo grep -n \"$APP_NAME\" /etc/nginx/sites-available/auth-gateway"
log_info "  • Check oauth2: sudo grep \"$APP_NAME\" /etc/oauth2-proxy/config.cfg"

echo ""
