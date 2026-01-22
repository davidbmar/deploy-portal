#!/bin/bash
# oauth2-proxy-register.sh - Manage oauth2_proxy skip_auth_routes
# For apps with auth_mode="none", this adds skip routes so they're publicly accessible

set -euo pipefail

OAUTH2_CONFIG="${OAUTH2_CONFIG:-/etc/oauth2-proxy/config.cfg}"
BASE_URL="${BASE_URL:-https://capsule-deploy.duckdns.org}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Usage information
usage() {
    cat << EOF
Usage: $0 <action> <app_name> <auth_mode>

Actions:
  add-skip-route     Add skip_auth_routes for no-auth app
  remove-skip-route  Remove skip_auth_routes for app
  test               Test if oauth2_proxy is configured correctly
  list               List all skip_auth_routes

Arguments:
  app_name           Name of the application
  auth_mode          Authentication mode: "none", "cognito", "internal"

Examples:
  $0 add-skip-route my-app none
  $0 remove-skip-route my-app none
  $0 test my-app none
  $0 list

EOF
    exit 1
}

# Check if oauth2_proxy config file exists
check_oauth2_config() {
    if [ ! -f "$OAUTH2_CONFIG" ]; then
        log_error "OAuth2 proxy config not found: $OAUTH2_CONFIG"
        return 1
    fi
    return 0
}

# Add skip_auth_routes section if it doesn't exist
ensure_skip_auth_routes_section() {
    if ! sudo grep -q "skip_auth_routes" "$OAUTH2_CONFIG"; then
        log_info "Adding skip_auth_routes section to oauth2_proxy config..."

        # Add skip_auth_routes section at the end of file
        sudo bash -c "cat >> $OAUTH2_CONFIG << 'EOF'

# Skip authentication for specific routes (no auth required)
skip_auth_routes = []
EOF"

        log_info "✅ Added skip_auth_routes section"
        return 0
    fi
    return 0
}

# Add skip route for an app
add_skip_route() {
    local app_name="$1"
    local auth_mode="$2"

    if [ "$auth_mode" != "none" ]; then
        log_info "Auth mode is '$auth_mode' - no skip route needed"
        return 0
    fi

    check_oauth2_config || return 1
    ensure_skip_auth_routes_section || return 1

    # Pattern to match in oauth2_proxy config (regex pattern)
    local pattern="^/${app_name}/.*"
    local quoted_pattern="\"${pattern}\""

    # Check if route already exists
    if sudo grep -q "$quoted_pattern" "$OAUTH2_CONFIG"; then
        log_warning "Skip route already exists for $app_name"
        return 0
    fi

    log_info "Adding skip_auth route for $app_name..."

    # Backup config
    sudo cp "$OAUTH2_CONFIG" "${OAUTH2_CONFIG}.backup-$(date +%s)"

    # Add the route pattern to the skip_auth_routes array
    # Find the line with skip_auth_routes = [ and add pattern on next line
    sudo sed -i "/skip_auth_routes = \[/a\  ${quoted_pattern}," "$OAUTH2_CONFIG"

    log_info "✅ Added skip_auth route: $pattern"

    # Restart oauth2-proxy service
    log_info "Restarting oauth2-proxy service..."
    if sudo systemctl restart oauth2-proxy; then
        log_info "✅ OAuth2-proxy restarted successfully"

        # Wait a moment for service to be ready
        sleep 2

        # Verify service is running
        if sudo systemctl is-active --quiet oauth2-proxy; then
            log_info "✅ OAuth2-proxy service is active"
        else
            log_error "OAuth2-proxy service failed to start"
            log_error "Check logs: sudo journalctl -u oauth2-proxy -n 50"
            return 1
        fi
    else
        log_error "Failed to restart oauth2-proxy"
        log_error "Restoring backup configuration..."
        sudo cp "${OAUTH2_CONFIG}.backup-$(date +%s)" "$OAUTH2_CONFIG"
        return 1
    fi

    return 0
}

# Remove skip route for an app
remove_skip_route() {
    local app_name="$1"

    check_oauth2_config || return 1

    local pattern="^/${app_name}/.*"
    local quoted_pattern="\"${pattern}\""

    if ! sudo grep -q "$quoted_pattern" "$OAUTH2_CONFIG"; then
        log_warning "Skip route not found for $app_name"
        return 0
    fi

    log_info "Removing skip_auth route for $app_name..."

    # Backup config
    sudo cp "$OAUTH2_CONFIG" "${OAUTH2_CONFIG}.backup-$(date +%s)"

    # Remove the line containing the pattern
    sudo sed -i "/$quoted_pattern/d" "$OAUTH2_CONFIG"

    log_info "✅ Removed skip_auth route: $pattern"

    # Restart oauth2-proxy service
    log_info "Restarting oauth2-proxy service..."
    if sudo systemctl restart oauth2-proxy; then
        log_info "✅ OAuth2-proxy restarted successfully"
    else
        log_error "Failed to restart oauth2-proxy"
        return 1
    fi

    return 0
}

# Test if oauth2_proxy is configured correctly for the app
test_auth() {
    local app_name="$1"
    local auth_mode="$2"
    local app_url="${BASE_URL}/${app_name}/"

    log_info "Testing authentication for $app_name (auth_mode: $auth_mode)..."
    log_info "URL: $app_url"

    # Test HTTP response
    local http_code=$(curl -k -s -o /dev/null -w "%{http_code}" "$app_url" 2>/dev/null || echo "000")

    if [ "$auth_mode" = "none" ]; then
        # For no-auth apps, expect HTTP 200
        if [ "$http_code" = "200" ]; then
            log_info "✅ No-auth working: $app_url returns HTTP $http_code"
            return 0
        else
            log_error "No-auth FAILED: $app_url returns HTTP $http_code (expected 200)"

            if [ "$http_code" = "302" ]; then
                log_error "App is being redirected to login page"
                log_error "Check oauth2_proxy skip_auth_routes configuration:"
                echo ""
                sudo grep -A5 "skip_auth_routes" "$OAUTH2_CONFIG" || echo "skip_auth_routes section not found"
                echo ""
                log_error "To fix: bash $0 add-skip-route $app_name none"
            fi

            return 1
        fi
    else
        # For authenticated apps, expect HTTP 302 (redirect to login)
        if [ "$http_code" = "302" ]; then
            log_info "✅ Auth working: $app_url returns HTTP $http_code (redirect to login)"
            return 0
        elif [ "$http_code" = "200" ]; then
            log_warning "Auth bypass: $app_url returns HTTP 200 but auth_mode=$auth_mode"
            log_warning "App is accessible without authentication"
            return 0
        else
            log_error "Auth FAILED: $app_url returns HTTP $http_code (expected 302)"
            return 1
        fi
    fi
}

# List all skip_auth_routes
list_skip_routes() {
    check_oauth2_config || return 1

    log_info "Skip auth routes configured in oauth2_proxy:"
    echo ""

    if sudo grep -q "skip_auth_routes" "$OAUTH2_CONFIG"; then
        # Extract the skip_auth_routes section
        sudo awk '/skip_auth_routes = \[/,/\]/' "$OAUTH2_CONFIG"
    else
        log_warning "No skip_auth_routes section found in config"
    fi

    echo ""
    return 0
}

# Main command dispatcher
ACTION="${1:-}"
APP_NAME="${2:-}"
AUTH_MODE="${3:-}"

case "$ACTION" in
    add-skip-route)
        if [ -z "$APP_NAME" ] || [ -z "$AUTH_MODE" ]; then
            log_error "Missing arguments"
            usage
        fi
        add_skip_route "$APP_NAME" "$AUTH_MODE"
        ;;

    remove-skip-route)
        if [ -z "$APP_NAME" ]; then
            log_error "Missing app_name argument"
            usage
        fi
        remove_skip_route "$APP_NAME"
        ;;

    test)
        if [ -z "$APP_NAME" ] || [ -z "$AUTH_MODE" ]; then
            log_error "Missing arguments"
            usage
        fi
        test_auth "$APP_NAME" "$AUTH_MODE"
        ;;

    list)
        list_skip_routes
        ;;

    *)
        log_error "Unknown action: $ACTION"
        usage
        ;;
esac
