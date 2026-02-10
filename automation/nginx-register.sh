#!/bin/bash
# nginx-register.sh - Register app in nginx configuration  
# Uses separate route files in /etc/nginx/conf.d/routes/ (ROBUST METHOD)
# Supports both authenticated (Cognito) and no-auth deployments
# Auto-detects auth mode from config.json
# VERSIONED: Creates versioned route files with format {app}-{version}-{timestamp}.conf

set -euo pipefail

ROUTES_DIR="${ROUTES_DIR:-/etc/nginx/conf.d/routes}"
TEMPLATE_DIR="${TEMPLATE_DIR:-/opt/deployment-tools/templates}"
BACKUP_DIR="${BACKUP_DIR:-/home/ubuntu/deployments/.backups}"

# Ensure directories exist
mkdir -p "$BACKUP_DIR"
sudo mkdir -p "$ROUTES_DIR"

# Check if location block already exists (checks for any version)
location_exists() {
    local app_name="$1"
    # Check if any .conf file for this app exists (not .disabled)
    compgen -G "$ROUTES_DIR/${app_name}-*.conf" >/dev/null 2>&1
}

# Get the active version file for an app
get_active_version() {
    local app_name="$1"
    ls -1t "$ROUTES_DIR/${app_name}"-*.conf 2>/dev/null | head -1 || echo ""
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
    local version="${5:-v1}"  # NEW: version parameter (default: v1)

    # Auto-detect from config.json if auth_mode is 'auto'
    if [[ "$auth_mode" == "auto" ]]; then
        local app_path="/home/ubuntu/deployments/$app_name"
        auth_mode=$(detect_auth_mode "$app_path")
        echo "🔍 Auto-detected auth_mode: $auth_mode" >&2
    fi

    # Generate versioned filename
    local timestamp=$(date -u +%Y%m%d-%H%M%S)
    local route_file="$ROUTES_DIR/${app_name}-${version}-${timestamp}.conf"

    # Check if there's already an active version
    local existing_version=$(get_active_version "$app_name")
    if [[ -n "$existing_version" ]]; then
        echo "⚠️  Active route file exists: $existing_version" >&2
        echo "    New version will be created. Disable old version after testing." >&2
    fi

    # Generate location block
    local location_block=$(generate_multiservice_location_block "$app_name" "$frontend_port" "$backend_port" "$auth_mode")

    if [[ -z "$location_block" ]]; then
        echo "❌ Failed to generate location block" >&2
        return 1
    fi

    echo "📋 Adding multi-service nginx config for '$app_name' v$version (auth: $auth_mode):" >&2
    echo "   • Frontend: port $frontend_port -> /$app_name/" >&2
    echo "   • Backend:  port $backend_port -> /$app_name/api/" >&2
    echo "   • Route file: $route_file" >&2

    # Write to versioned route file
    sudo tee "$route_file" > /dev/null <<< "$location_block"

    # Test nginx config
    if sudo nginx -t 2>&1 | grep -q "test is successful"; then
        echo "✅ Route file created: $route_file" >&2
        
        # If there was an existing version, remind to disable it
        if [[ -n "$existing_version" ]]; then
            echo "" >&2
            echo "📝 Note: Old version still active: $existing_version" >&2
            echo "   To disable old version after testing: sudo mv $existing_version $existing_version.disabled" >&2
        fi
        
        return 0
    else
        echo "❌ Nginx config invalid, removing route file" >&2
        sudo rm -f "$route_file"
        return 1
    fi
}

# Remove location block (disables all versions of an app)
remove_location() {
    local app_name="$1"

    if ! location_exists "$app_name"; then
        echo "⚠️  No route files found for: $app_name" >&2
        return 0
    fi

    # Find all versions of this app
    local route_files=$(ls -1 "$ROUTES_DIR/${app_name}"-*.conf 2>/dev/null || echo "")
    
    if [[ -z "$route_files" ]]; then
        echo "⚠️  No active route files found for: $app_name" >&2
        return 0
    fi

    # Backup and disable each version
    for route_file in $route_files; do
        echo "📦 Backing up and disabling: $route_file" >&2
        sudo cp "$route_file" "$BACKUP_DIR/$(basename $route_file).backup-$(date +%s)"
        sudo mv "$route_file" "$route_file.disabled"
    done

    # Test nginx config
    if sudo nginx -t 2>&1 | grep -q "test is successful"; then
        echo "✅ All versions of $app_name disabled successfully" >&2
        return 0
    else
        echo "❌ Nginx config invalid after removal, restoring files" >&2
        # Restore all files
        for route_file in $route_files; do
            sudo mv "$route_file.disabled" "$route_file"
        done
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
  add-multiservice <app_name> <frontend_port> <backend_port> [auth_mode] [version]
      Add multi-service nginx location (frontend + API)
      Creates: $ROUTES_DIR/<app_name>-<version>-<timestamp>.conf
      auth_mode: 'none', 'cognito', or 'auto' (default: auto-detect from config.json)
      version: version identifier (default: v1)

  remove <app_name>
      Remove (disable) all nginx location versions for app

  exists <app_name>
      Check if location exists (exit 0 if exists, 1 if not)

  reload
      Reload nginx configuration

  test
      Test nginx configuration

Examples:
  # Auto-detect auth_mode from config.json, version v1
  $0 add-multiservice my-app 3002 8002

  # Explicitly set no authentication, version v2
  $0 add-multiservice public-app 3003 8003 none v2

  # Explicitly set Cognito authentication, version prod
  $0 add-multiservice secure-app 3004 8004 cognito prod

  # Remove all versions of app configuration
  $0 remove my-app

  # Reload nginx
  $0 reload

Versioned Route Files:
  - Format: <app>-<version>-<timestamp>.conf
  - Example: my-app-v2-20260203-143000.conf
  - Disable: mv <file>.conf <file>.conf.disabled
  - Re-enable: mv <file>.conf.disabled <file>.conf

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
        add_multiservice_location "$2" "$3" "$4" "${5:-auto}" "${6:-v1}"
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
