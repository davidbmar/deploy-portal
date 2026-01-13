#!/bin/bash
# systemd-register.sh - Register app as systemd service
# Creates and manages systemd service for deployed apps

set -euo pipefail

SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
TEMPLATE_DIR="$(dirname "$0")/templates"

# Check if service exists
service_exists() {
    local service_name="$1"

    if systemctl list-unit-files | grep -q "^${service_name} "; then
        return 0
    elif [[ -f "$SYSTEMD_DIR/$service_name" ]]; then
        return 0
    else
        return 1
    fi
}

# Detect start command based on app type and directory contents
detect_start_command() {
    local app_dir="$1"
    local port="$2"
    local app_type="${3:-other}"

    # If package.json exists, it's likely a Node.js app
    if [[ -f "$app_dir/package.json" ]]; then
        if grep -q '"start"' "$app_dir/package.json" 2>/dev/null; then
            echo "/usr/bin/npm start"
            return 0
        elif [[ -f "$app_dir/server.js" ]]; then
            echo "/usr/bin/node server.js"
            return 0
        elif [[ -f "$app_dir/index.js" ]]; then
            echo "/usr/bin/node index.js"
            return 0
        elif [[ -f "$app_dir/app.js" ]]; then
            echo "/usr/bin/node app.js"
            return 0
        fi
    fi

    # Python apps
    if [[ -f "$app_dir/app.py" || -f "$app_dir/main.py" || -f "$app_dir/wsgi.py" ]]; then
        if [[ -f "$app_dir/requirements.txt" ]] && grep -q "gunicorn" "$app_dir/requirements.txt" 2>/dev/null; then
            if [[ -f "$app_dir/wsgi.py" ]]; then
                echo "/usr/local/bin/gunicorn -w 4 -b 0.0.0.0:${port} wsgi:app"
                return 0
            elif [[ -f "$app_dir/app.py" ]]; then
                echo "/usr/local/bin/gunicorn -w 4 -b 0.0.0.0:${port} app:app"
                return 0
            fi
        elif [[ -f "$app_dir/app.py" ]]; then
            echo "/usr/bin/python3 app.py"
            return 0
        elif [[ -f "$app_dir/main.py" ]]; then
            echo "/usr/bin/python3 main.py"
            return 0
        fi
    fi

    # Docker apps
    if [[ -f "$app_dir/Dockerfile" || -f "$app_dir/docker-compose.yml" ]]; then
        echo "/usr/bin/docker-compose up"
        return 0
    fi

    # Go apps
    if [[ -f "$app_dir/go.mod" ]]; then
        # Look for built binary
        local binary=$(find "$app_dir" -maxdepth 1 -type f -executable -name "main" -o -name "app" -o -name "server" 2>/dev/null | head -n1)
        if [[ -n "$binary" ]]; then
            echo "$binary"
            return 0
        else
            echo "/usr/local/go/bin/go run ."
            return 0
        fi
    fi

    # Default: look for any executable
    local binary=$(find "$app_dir" -maxdepth 1 -type f -executable 2>/dev/null | head -n1)
    if [[ -n "$binary" ]]; then
        echo "$binary"
        return 0
    fi

    # Fallback
    echo "Error: Could not detect start command for app in $app_dir" >&2
    return 1
}

# Generate service file from template
generate_service_file() {
    local app_name="$1"
    local port="$2"
    local start_command="$3"
    local template_file="$TEMPLATE_DIR/systemd-service.tmpl"

    if [[ ! -f "$template_file" ]]; then
        echo "Error: Template file not found: $template_file" >&2
        return 1
    fi

    sed -e "s|{{APP_NAME}}|${app_name}|g" \
        -e "s|{{PORT}}|${port}|g" \
        -e "s|{{START_COMMAND}}|${start_command}|g" \
        "$template_file"
}

# Create and enable service
create_service() {
    local app_name="$1"
    local port="$2"
    local start_command="${3:-}"
    local app_type="${4:-other}"

    local service_name="${app_name}.service"
    local service_file="$SYSTEMD_DIR/$service_name"
    local app_dir="/home/ubuntu/deployments/$app_name"

    # Check if service already exists
    if service_exists "$service_name"; then
        echo "Error: Service '$service_name' already exists" >&2
        return 1
    fi

    # Detect start command if not provided
    if [[ -z "$start_command" ]]; then
        start_command=$(detect_start_command "$app_dir" "$port" "$app_type")
        if [[ $? -ne 0 ]]; then
            return 1
        fi
    fi

    echo "Detected start command: $start_command" >&2

    # Generate service file
    local service_content=$(generate_service_file "$app_name" "$port" "$start_command")

    # Write service file
    echo "$service_content" | sudo tee "$service_file" > /dev/null
    sudo chmod 644 "$service_file"

    # Reload systemd
    sudo systemctl daemon-reload

    # Enable service
    sudo systemctl enable "$service_name"

    echo "Service created: $service_name" >&2
    return 0
}

# Start service
start_service() {
    local app_name="$1"
    local service_name="${app_name}.service"

    if ! service_exists "$service_name"; then
        echo "Error: Service '$service_name' does not exist" >&2
        return 1
    fi

    sudo systemctl start "$service_name"
    echo "Service started: $service_name" >&2

    # Wait a moment and check status
    sleep 2
    if sudo systemctl is-active --quiet "$service_name"; then
        echo "Service is running" >&2
        return 0
    else
        echo "Warning: Service may have failed to start. Check logs with: journalctl -u $service_name" >&2
        return 1
    fi
}

# Stop service
stop_service() {
    local app_name="$1"
    local service_name="${app_name}.service"

    if ! service_exists "$service_name"; then
        echo "Warning: Service '$service_name' does not exist" >&2
        return 0
    fi

    sudo systemctl stop "$service_name"
    echo "Service stopped: $service_name" >&2
    return 0
}

# Remove service
remove_service() {
    local app_name="$1"
    local service_name="${app_name}.service"
    local service_file="$SYSTEMD_DIR/$service_name"

    if ! service_exists "$service_name"; then
        echo "Warning: Service '$service_name' does not exist" >&2
        return 0
    fi

    # Stop service if running
    if sudo systemctl is-active --quiet "$service_name"; then
        sudo systemctl stop "$service_name"
    fi

    # Disable service
    sudo systemctl disable "$service_name" 2>/dev/null || true

    # Remove service file
    sudo rm -f "$service_file"

    # Reload systemd
    sudo systemctl daemon-reload

    echo "Service removed: $service_name" >&2
    return 0
}

# Get service status
status_service() {
    local app_name="$1"
    local service_name="${app_name}.service"

    if ! service_exists "$service_name"; then
        echo "Service '$service_name' does not exist" >&2
        return 1
    fi

    sudo systemctl status "$service_name" --no-pager
}

# Main command dispatcher
case "${1:-}" in
    create)
        create_service "$2" "$3" "${4:-}" "${5:-other}"
        ;;
    start)
        start_service "$2"
        ;;
    stop)
        stop_service "$2"
        ;;
    remove)
        remove_service "$2"
        ;;
    status)
        status_service "$2"
        ;;
    exists)
        service_exists "$2.service"
        ;;
    detect-command)
        detect_start_command "$2" "$3" "${4:-other}"
        ;;
    *)
        echo "Usage: $0 {create <app> <port> [start_cmd] [type]|start <app>|stop <app>|remove <app>|status <app>|exists <app>|detect-command <dir> <port> [type]}" >&2
        exit 1
        ;;
esac
