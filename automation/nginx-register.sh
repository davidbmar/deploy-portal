#!/bin/bash
# nginx-register.sh - Register app in nginx configuration  
# Uses separate route files in /etc/nginx/conf.d/routes/ (ROBUST METHOD)
# Supports both authenticated (Cognito) and no-auth deployments
# Auto-detects auth mode from config.json

set -euo pipefail

ROUTES_DIR="${ROUTES_DIR:-/etc/nginx/conf.d/routes}"
TEMPLATE_DIR="${TEMPLATE_DIR:-/opt/deployment-tools/templates}"
BACKUP_DIR="${BACKUP_DIR:-/home/ubuntu/deployments/.backups}"

# Ensure directories exist
mkdir -p "$BACKUP_DIR"
sudo mkdir -p "$ROUTES_DIR"

# Check if location block already exists
location_exists() {
    local app_name="$1"
    [[ -f "$ROUTES_DIR/${app_name}.conf" ]]
}

# Read auth_mode from config.json
detect_auth_mode() {
    local app_path="$1"
    local config_file="$app_path/config.json"

    if [[ -f "$config_file" ]] && command -v python3 &>/dev/null; then
        python3 -c "import json; print(json.load(open('$config_file'))['auth_mode'])" 2>/dev/null || echo "cognito"
    else
        echo "cognito"
    fi
}

# Generate multi-service location block from template
generate_multiservice_location_block() {
    local app_name="$1"
    local frontend_port="$2"
    local backend_port="$3"
    local auth_mode="${4:-cognito}"

    local template_file

    # Choose template based on auth_mode
    case "$auth_mode" in
        none|noauth|public)
            template_file="$TEMPLATE_DIR/nginx-location-multiservice-noauth.conf.tmpl"
            echo "📝 Using no-auth template for $app_name" >&2
            ;;
        cognito|oauth|auth)
            template_file="$TEMPLATE_DIR/nginx-location-multiservice.conf.tmpl"
            echo "📝 Using Cognito auth template for $app_name" >&2
            ;;
        *)
            echo "❌ Error: Unknown auth_mode '$auth_mode'. Use 'none' or 'cognito'" >&2
            return 1
            ;;
    esac

    if [[ ! -f "$template_file" ]]; then
        echo "❌ Error: Template not found: $template_file" >&2
        echo "Available templates:" >&2
        ls -la "$TEMPLATE_DIR"/ >&2
        return 1
    fi

    sed -e "s/{{APP_NAME}}/${app_name}/g" \
        -e "s/{{FRONTEND_PORT}}/${frontend_port}/g" \
        -e "s/{{BACKEND_PORT}}/${backend_port}/g" \
        "$template_file"
}

# Add multi-service location block
add_multiservice_location() {
    local app_name="$1"
    local frontend_port="$2"
    local backend_port="$3"
    local auth_mode="${4:-auto}"

    # Auto-detect from config.json if auth_mode is 'auto'
    if [[ "$auth_mode" == "auto" ]]; then
        local app_path="/home/ubuntu/deployments/$app_name"
        auth_mode=$(detect_auth_mode "$app_path")
        echo "🔍 Auto-detected auth_mode: $auth_mode" >&2
    fi

    # Check if already exists
    if location_exists "$app_name"; then
        echo "⚠️  Route file already exists: $ROUTES_DIR/${app_name}.conf" >&2
        echo "    Use 'remove' command first to update" >&2
        return 1
    fi

    # Generate location block
    local location_block=$(generate_multiservice_location_block "$app_name" "$frontend_port" "$backend_port" "$auth_mode")

    if [[ -z "$location_block" ]]; then
        echo "❌ Failed to generate location block" >&2
        return 1
    fi

    echo "📋 Adding multi-service nginx config for '$app_name' (auth: $auth_mode):" >&2
    echo "   • Frontend: port $frontend_port -> /$app_name/" >&2
    echo "   • Backend:  port $backend_port -> /$app_name/api/" >&2

    # Write to separate route file (ROBUST METHOD)
    sudo tee "$ROUTES_DIR/${app_name}.conf" > /dev/null <<< "$location_block"

    # Test nginx config
    if sudo nginx -t 2>&1 | grep -q "test is successful"; then
        echo "✅ Route file created: $ROUTES_DIR/${app_name}.conf" >&2
        return 0
    else
        echo "❌ Nginx config invalid, removing route file" >&2
        sudo rm -f "$ROUTES_DIR/${app_name}.conf"
        return 1
    fi
}

# Remove location block
remove_location() {
    local app_name="$1"

    if ! location_exists "$app_name"; then
        echo "⚠️  Route file not found: $ROUTES_DIR/${app_name}.conf" >&2
        return 0
    fi

    # Backup before removing
    sudo cp "$ROUTES_DIR/${app_name}.conf" "$BACKUP_DIR/${app_name}.conf.backup-$(date +%s)"

    # Remove route file
    sudo rm -f "$ROUTES_DIR/${app_name}.conf"

    # Test nginx config
    if sudo nginx -t 2>&1 | grep -q "test is successful"; then
        echo "✅ Route file removed successfully" >&2
        return 0
    else
        echo "❌ Nginx config invalid after removal, restoring file" >&2
        sudo cp "$BACKUP_DIR/${app_name}.conf.backup-$(date +%s)" "$ROUTES_DIR/${app_name}.conf"
        return 1
    fi
}

# Reload nginx
reload_nginx() {
    if sudo nginx -t 2>&1 | grep -q "test is successful"; then
        sudo systemctl reload nginx
        echo "✅ Nginx reloaded successfully" >&2
        return 0
    else
        echo "❌ Cannot reload nginx - configuration test failed" >&2
        return 1
    fi
}

# Show help
show_help() {
    cat << EOF
Usage: $0 <command> [arguments]

Commands:
  add-multiservice <app_name> <frontend_port> <backend_port> [auth_mode]
      Add multi-service nginx location (frontend + API)
      Creates: $ROUTES_DIR/<app_name>.conf
      auth_mode: 'none', 'cognito', or 'auto' (default: auto-detect from config.json)

  remove <app_name>
      Remove nginx location for app

  exists <app_name>
      Check if location exists (exit 0 if exists, 1 if not)

  reload
      Reload nginx configuration

  test
      Test nginx configuration

Examples:
  # Auto-detect auth_mode from config.json
  $0 add-multiservice my-app 3002 8002

  # Explicitly set no authentication
  $0 add-multiservice public-app 3003 8003 none

  # Explicitly set Cognito authentication
  $0 add-multiservice secure-app 3004 8004 cognito

  # Remove app configuration
  $0 remove my-app

  # Reload nginx
  $0 reload

Routes Directory: $ROUTES_DIR
Template Directory: $TEMPLATE_DIR
Available templates:
$(ls -1 $TEMPLATE_DIR/*.tmpl 2>/dev/null | sed 's|.*/|  - |' || echo "  (none found)")
EOF
}

# Main command dispatcher
case "${1:-}" in
    add-multiservice)
        if [[ -z "${3:-}" ]]; then
            echo "❌ Error: add-multiservice requires at least 3 arguments" >&2
            show_help
            exit 1
        fi
        add_multiservice_location "$2" "$3" "$4" "${5:-auto}"
        ;;
    remove)
        if [[ -z "${2:-}" ]]; then
            echo "❌ Error: remove requires app_name" >&2
            show_help
            exit 1
        fi
        remove_location "$2"
        ;;
    exists)
        location_exists "$2"
        ;;
    reload)
        reload_nginx
        ;;
    test)
        sudo nginx -t
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "❌ Error: Unknown command '${1:-}'" >&2
        echo "" >&2
        show_help
        exit 1
        ;;
esac
