#!/bin/bash
# registry-manager.sh - Deployment Registry Management
# Manages the deployment registry at /home/ubuntu/deployments/.registry.json

set -euo pipefail

REGISTRY_FILE="${REGISTRY_FILE:-/home/ubuntu/deployments/.registry.json}"
REGISTRY_DIR="$(dirname "$REGISTRY_FILE")"

# Ensure registry directory exists
mkdir -p "$REGISTRY_DIR"

# Initialize registry if it doesn't exist
init_registry() {
    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo "{}" > "$REGISTRY_FILE"
        chmod 644 "$REGISTRY_FILE"
    fi
}

# Check if app exists in registry
# Usage: registry_check <app_name>
# Returns: 0 if exists, 1 if not
registry_check() {
    local app_name="$1"
    init_registry

    if jq -e ".\"$app_name\"" "$REGISTRY_FILE" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Add app to registry
# Usage: registry_add <app_name> <port> <deployed_by> <app_type>
registry_add() {
    local app_name="$1"
    local port="$2"
    local deployed_by="$3"
    local app_type="${4:-other}"

    init_registry

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local deployment_path="/home/ubuntu/deployments/$app_name"
    local url_path="/$app_name/"
    local service_name="$app_name.service"

    # Use jq to add entry atomically
    local temp_file=$(mktemp)
    jq --arg name "$app_name" \
       --arg port "$port" \
       --arg path "$deployment_path" \
       --arg url "$url_path" \
       --arg by "$deployed_by" \
       --arg ts "$timestamp" \
       --arg svc "$service_name" \
       --arg type "$app_type" \
       '.[$name] = {
           app_name: $name,
           port: ($port | tonumber),
           path: $path,
           url_path: $url,
           deployed_by: $by,
           deployed_at: $ts,
           status: "active",
           service_name: $svc,
           app_type: $type
       }' "$REGISTRY_FILE" > "$temp_file"

    mv "$temp_file" "$REGISTRY_FILE"
    chmod 644 "$REGISTRY_FILE"
}

# Update app status in registry
# Usage: registry_update_status <app_name> <status>
registry_update_status() {
    local app_name="$1"
    local status="$2"

    init_registry

    if ! registry_check "$app_name"; then
        echo "Error: App '$app_name' not found in registry" >&2
        return 1
    fi

    local temp_file=$(mktemp)
    jq --arg name "$app_name" \
       --arg status "$status" \
       '.[$name].status = $status' "$REGISTRY_FILE" > "$temp_file"

    mv "$temp_file" "$REGISTRY_FILE"
    chmod 644 "$REGISTRY_FILE"
}

# Remove app from registry
# Usage: registry_remove <app_name>
registry_remove() {
    local app_name="$1"

    init_registry

    local temp_file=$(mktemp)
    jq --arg name "$app_name" \
       'del(.[$name])' "$REGISTRY_FILE" > "$temp_file"

    mv "$temp_file" "$REGISTRY_FILE"
    chmod 644 "$REGISTRY_FILE"
}

# List all deployments
# Usage: registry_list
registry_list() {
    init_registry
    jq -r 'to_entries[] | "\(.value.app_name)\t\(.value.port)\t\(.value.status)\t\(.value.deployed_at)"' "$REGISTRY_FILE"
}

# Get app info
# Usage: registry_get <app_name>
registry_get() {
    local app_name="$1"
    init_registry
    jq -r ".\"$app_name\"" "$REGISTRY_FILE"
}

# Get allocated port for app
# Usage: registry_get_port <app_name>
registry_get_port() {
    local app_name="$1"
    init_registry
    jq -r ".\"$app_name\".port // empty" "$REGISTRY_FILE"
}

# Main command dispatcher
case "${1:-}" in
    check)
        registry_check "$2"
        ;;
    add)
        registry_add "$2" "$3" "$4" "${5:-other}"
        ;;
    update-status)
        registry_update_status "$2" "$3"
        ;;
    remove)
        registry_remove "$2"
        ;;
    list)
        registry_list
        ;;
    get)
        registry_get "$2"
        ;;
    get-port)
        registry_get_port "$2"
        ;;
    *)
        echo "Usage: $0 {check|add|update-status|remove|list|get|get-port} [args...]" >&2
        exit 1
        ;;
esac
