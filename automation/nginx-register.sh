#!/bin/bash
# nginx-register.sh - Register app in nginx configuration
# Adds location block for new app with Cognito authentication

set -euo pipefail

NGINX_CONFIG="${NGINX_CONFIG:-/etc/nginx/sites-available/auth-gateway}"
BACKUP_DIR="${BACKUP_DIR:-/home/ubuntu/deployments/.backups}"
TEMPLATE_DIR="$(dirname "$0")/templates"

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Backup nginx config
backup_nginx_config() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="$BACKUP_DIR/auth-gateway-${timestamp}.conf"

    if [[ -f "$NGINX_CONFIG" ]]; then
        cp "$NGINX_CONFIG" "$backup_file"
        echo "Backed up nginx config to: $backup_file" >&2

        # Keep only last 10 backups
        ls -t "$BACKUP_DIR"/auth-gateway-*.conf | tail -n +11 | xargs -r rm -f
    fi
}

# Check if location block already exists
location_exists() {
    local app_name="$1"

    if grep -q "location /${app_name}/" "$NGINX_CONFIG" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Generate location block from template
generate_location_block() {
    local app_name="$1"
    local port="$2"
    local template_file="$TEMPLATE_DIR/nginx-location.conf.tmpl"

    if [[ ! -f "$template_file" ]]; then
        echo "Error: Template file not found: $template_file" >&2
        return 1
    fi

    sed -e "s/{{APP_NAME}}/${app_name}/g" \
        -e "s/{{PORT}}/${port}/g" \
        "$template_file"
}

# Generate multi-service location block from template (frontend + backend)
generate_multiservice_location_block() {
    local app_name="$1"
    local frontend_port="$2"
    local backend_port="$3"
    local template_file="$TEMPLATE_DIR/nginx-location-multiservice.conf.tmpl"

    if [[ ! -f "$template_file" ]]; then
        echo "Error: Multi-service template file not found: $template_file" >&2
        return 1
    fi

    sed -e "s/{{APP_NAME}}/${app_name}/g" \
        -e "s/{{FRONTEND_PORT}}/${frontend_port}/g" \
        -e "s/{{BACKEND_PORT}}/${backend_port}/g" \
        "$template_file"
}

# Add location block to nginx config
add_location() {
    local app_name="$1"
    local port="$2"

    # Check if already exists
    if location_exists "$app_name"; then
        echo "Error: Location block for '$app_name' already exists in nginx config" >&2
        return 1
    fi

    # Backup first
    backup_nginx_config

    # Generate location block
    local location_block=$(generate_location_block "$app_name" "$port")

    # Insert into nginx config
    insert_location_block "$location_block"
}

# Add multi-service location block (frontend + API) to nginx config
add_multiservice_location() {
    local app_name="$1"
    local frontend_port="$2"
    local backend_port="$3"

    # Check if already exists
    if location_exists "$app_name"; then
        echo "Error: Location block for '$app_name' already exists in nginx config" >&2
        return 1
    fi

    # Backup first
    backup_nginx_config

    # Generate multi-service location block
    local location_block=$(generate_multiservice_location_block "$app_name" "$frontend_port" "$backend_port")

    if [[ -z "$location_block" ]]; then
        echo "Error: Failed to generate multi-service location block" >&2
        return 1
    fi

    echo "Adding multi-service nginx config for '$app_name':" >&2
    echo "  - Frontend: port $frontend_port -> /$app_name/" >&2
    echo "  - Backend:  port $backend_port -> /$app_name/api/" >&2

    # Insert into nginx config
    insert_location_block "$location_block"
}

# Helper function to insert location block into nginx config
insert_location_block() {
    local location_block="$1"

    # Find the last upstream or location block before the closing brace
    # We'll insert before the last closing brace of the server block

    # Create temp file
    local temp_file=$(mktemp)

    # Find the last closing brace (end of server block) and insert before it
    awk -v block="$location_block" '
    /^}$/ && found == 0 {
        # This is likely the closing brace of the server block
        # Mark that we found it but dont print yet
        closing_brace = $0
        found = 1
        next
    }
    found == 0 {
        print
        next
    }
    found == 1 {
        # We already found the first closing brace
        # Print the location block before it
        print block
        print ""
        print closing_brace
        # Print rest of file
        print
        found = 2
        next
    }
    found == 2 {
        print
    }
    END {
        # If we only found one closing brace (found==1), print it now
        if (found == 1) {
            print block
            print ""
            print closing_brace
        }
    }
    ' "$NGINX_CONFIG" > "$temp_file"

    # Verify the new config is valid
    if ! sudo nginx -t -c /dev/null -p /etc/nginx/ 2>&1 | grep -q "test is successful" ; then
        # Test with the new config
        sudo cp "$temp_file" "$NGINX_CONFIG"
        if sudo nginx -t 2>&1 | grep -q "test is successful"; then
            echo "Nginx configuration updated successfully" >&2
            return 0
        else
            echo "Error: Generated nginx config is invalid, restoring backup" >&2
            # Restore latest backup
            local latest_backup=$(ls -t "$BACKUP_DIR"/auth-gateway-*.conf 2>/dev/null | head -n1)
            if [[ -n "$latest_backup" ]]; then
                sudo cp "$latest_backup" "$NGINX_CONFIG"
            fi
            rm -f "$temp_file"
            return 1
        fi
    else
        # Apply the new config
        sudo cp "$temp_file" "$NGINX_CONFIG"
        rm -f "$temp_file"

        # Test again
        if sudo nginx -t 2>&1 | grep -q "test is successful"; then
            echo "Nginx configuration updated successfully" >&2
            return 0
        else
            echo "Error: Generated nginx config is invalid" >&2
            return 1
        fi
    fi
}

# Remove location block from nginx config
remove_location() {
    local app_name="$1"

    if ! location_exists "$app_name"; then
        echo "Warning: Location block for '$app_name' not found in nginx config" >&2
        return 0
    fi

    backup_nginx_config

    # Remove the location blocks and upstream for this app
    local temp_file=$(mktemp)

    awk -v app="$app_name" '
    # Start of upstream block for this app
    /upstream '"$app_name"'_backend/ {
        in_upstream = 1
        next
    }

    # End of upstream block
    in_upstream == 1 && /}/ {
        in_upstream = 0
        next
    }

    # Inside upstream block - skip lines
    in_upstream == 1 {
        next
    }

    # Start of location block for this app
    /location \/'"$app_name"'\// {
        in_location = 1
        next
    }

    # Start of redirect location for this app
    /location = \/'"$app_name"'$/ {
        in_redirect = 1
        next
    }

    # End of location block
    in_location == 1 && /}/ {
        in_location = 0
        next
    }

    # End of redirect location
    in_redirect == 1 && /}/ {
        in_redirect = 0
        next
    }

    # Inside location block - skip lines
    in_location == 1 || in_redirect == 1 {
        next
    }

    # Print all other lines
    {
        print
    }
    ' "$NGINX_CONFIG" > "$temp_file"

    sudo cp "$temp_file" "$NGINX_CONFIG"
    rm -f "$temp_file"

    # Test config
    if sudo nginx -t 2>&1 | grep -q "test is successful"; then
        echo "Location block removed successfully" >&2
        return 0
    else
        echo "Error: Nginx config invalid after removal, restoring backup" >&2
        local latest_backup=$(ls -t "$BACKUP_DIR"/auth-gateway-*.conf 2>/dev/null | head -n1)
        if [[ -n "$latest_backup" ]]; then
            sudo cp "$latest_backup" "$NGINX_CONFIG"
        fi
        return 1
    fi
}

# Reload nginx
reload_nginx() {
    if sudo nginx -t 2>&1 | grep -q "test is successful"; then
        sudo systemctl reload nginx
        echo "Nginx reloaded successfully" >&2
        return 0
    else
        echo "Error: Cannot reload nginx - configuration test failed" >&2
        return 1
    fi
}

# Main command dispatcher
case "${1:-}" in
    add)
        # Single service: add <app_name> <port>
        add_location "$2" "$3"
        ;;
    add-multiservice)
        # Multi-service (frontend + backend): add-multiservice <app_name> <frontend_port> <backend_port>
        if [[ -z "${4:-}" ]]; then
            echo "Error: add-multiservice requires 3 arguments: <app_name> <frontend_port> <backend_port>" >&2
            exit 1
        fi
        add_multiservice_location "$2" "$3" "$4"
        ;;
    remove)
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
    *)
        cat << EOF >&2
Usage: $0 <command> [arguments]

Commands:
  add <app_name> <port>                           Add single-service nginx location
  add-multiservice <app_name> <frontend> <backend> Add multi-service nginx location (frontend + API)
  remove <app_name>                               Remove nginx location for app
  exists <app_name>                               Check if location exists
  reload                                          Reload nginx configuration
  test                                            Test nginx configuration

Examples:
  $0 add my-app 5001                              # Single service on port 5001
  $0 add-multiservice my-app 3002 8002            # Frontend:3002, Backend:8002
  $0 remove my-app                                # Remove my-app config
  $0 reload                                       # Reload nginx
EOF
        exit 1
        ;;
esac
