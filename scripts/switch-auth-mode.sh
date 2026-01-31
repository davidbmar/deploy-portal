#!/bin/bash
# Helper script to switch between authenticated and public access modes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[AUTH-MODE]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

show_usage() {
    echo "Usage: $0 <mode>"
    echo ""
    echo "Modes:"
    echo "  auth     - Enable OAuth2 authentication (requires oauth2-proxy)"
    echo "  no-auth  - Disable authentication (public access)"
    echo "  status   - Show current authentication mode"
    echo ""
    echo "Examples:"
    echo "  $0 auth       # Enable OAuth2"
    echo "  $0 no-auth    # Disable auth"
    echo "  $0 status     # Check current mode"
}

get_current_mode() {
    if [ -f /etc/nginx/conf.d/routes/deploy-portal.conf ]; then
        if grep -q "auth_request" /etc/nginx/conf.d/routes/deploy-portal.conf; then
            echo "auth"
        else
            echo "no-auth"
        fi
    else
        echo "unknown"
    fi
}

show_status() {
    log "Current Authentication Status"
    echo ""

    CURRENT_MODE=$(get_current_mode)

    if [ "$CURRENT_MODE" = "auth" ]; then
        echo "Mode: ✓ Authenticated (OAuth2 enabled)"

        if systemctl is-active --quiet oauth2-proxy; then
            echo "OAuth2-proxy: ✓ Running"
        else
            echo "OAuth2-proxy: ✗ NOT running (will cause 500 errors!)"
        fi
    elif [ "$CURRENT_MODE" = "no-auth" ]; then
        echo "Mode: ⚠ Public Access (no authentication)"
        echo "OAuth2-proxy: Not required"
    else
        echo "Mode: ✗ Unknown (routes config not found)"
    fi
}

switch_to_auth() {
    log "Switching to authenticated mode..."

    # Check if oauth2-proxy is running
    if ! systemctl is-active --quiet oauth2-proxy; then
        error "OAuth2-proxy is not running. Start it first: sudo systemctl start oauth2-proxy"
    fi

    # Check if auth routes config exists
    if [ ! -f "$SCRIPT_DIR/nginx/routes-with-auth.conf" ]; then
        error "routes-with-auth.conf not found in $SCRIPT_DIR/nginx/"
    fi

    # Install authenticated routes
    sudo cp "$SCRIPT_DIR/nginx/routes-with-auth.conf" \
        /etc/nginx/conf.d/routes/deploy-portal.conf

    # Test nginx config
    if ! sudo nginx -t > /dev/null 2>&1; then
        error "Nginx configuration test failed"
    fi

    # Reload nginx
    sudo systemctl reload nginx

    log "✓ Switched to authenticated mode"
    log "Deploy portal now requires OAuth2 authentication"
}

switch_to_no_auth() {
    warn "Switching to public access mode (NO AUTHENTICATION)..."

    # Check if no-auth routes config exists
    if [ ! -f "$SCRIPT_DIR/nginx/routes-no-auth.conf" ]; then
        error "routes-no-auth.conf not found in $SCRIPT_DIR/nginx/"
    fi

    # Install no-auth routes
    sudo cp "$SCRIPT_DIR/nginx/routes-no-auth.conf" \
        /etc/nginx/conf.d/routes/deploy-portal.conf

    # Test nginx config
    if ! sudo nginx -t > /dev/null 2>&1; then
        error "Nginx configuration test failed"
    fi

    # Reload nginx
    sudo systemctl reload nginx

    warn "✓ Switched to public access mode"
    warn "⚠ Deploy portal is now accessible WITHOUT authentication"
    warn "⚠ Anyone with network access can manage deployments"
}

# Main logic
if [ $# -eq 0 ]; then
    show_usage
    exit 1
fi

MODE=$1

case "$MODE" in
    auth)
        switch_to_auth
        ;;
    no-auth)
        switch_to_no_auth
        ;;
    status)
        show_status
        ;;
    *)
        echo "Unknown mode: $MODE"
        echo ""
        show_usage
        exit 1
        ;;
esac
