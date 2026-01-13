#!/bin/bash
# port-allocator.sh - Port Allocation for Deployments
# Finds available port in range 5001-5999

set -euo pipefail

PORT_START="${PORT_START:-5001}"
PORT_END="${PORT_END:-5999}"
REGISTRY_FILE="${REGISTRY_FILE:-/home/ubuntu/deployments/.registry.json}"

# Get all ports currently allocated in registry
get_allocated_ports() {
    if [[ -f "$REGISTRY_FILE" ]]; then
        jq -r '.[] | .port' "$REGISTRY_FILE" 2>/dev/null || true
    fi
}

# Check if port is listening
is_port_listening() {
    local port="$1"
    if netstat -tuln 2>/dev/null | grep -q ":$port " || \
       ss -tuln 2>/dev/null | grep -q ":$port "; then
        return 0
    else
        return 1
    fi
}

# Find first available port
find_available_port() {
    local allocated_ports=$(get_allocated_ports | sort -n)

    for port in $(seq "$PORT_START" "$PORT_END"); do
        # Check if port is in registry
        if echo "$allocated_ports" | grep -q "^$port$"; then
            continue
        fi

        # Check if port is actually listening
        if is_port_listening "$port"; then
            continue
        fi

        # Port is available
        echo "$port"
        return 0
    done

    # No ports available
    echo "Error: No available ports in range $PORT_START-$PORT_END" >&2
    return 1
}

# Allocate port for specific app (check registry first)
allocate_port() {
    local app_name="${1:-}"

    if [[ -z "$app_name" ]]; then
        find_available_port
        return $?
    fi

    # Check if app already has a port in registry
    if [[ -f "$REGISTRY_FILE" ]]; then
        local existing_port=$(jq -r ".\"$app_name\".port // empty" "$REGISTRY_FILE" 2>/dev/null || true)
        if [[ -n "$existing_port" && "$existing_port" != "null" ]]; then
            echo "$existing_port"
            return 0
        fi
    fi

    # Allocate new port
    find_available_port
}

# Main
case "${1:-allocate}" in
    allocate)
        allocate_port "${2:-}"
        ;;
    check)
        if is_port_listening "$2"; then
            echo "Port $2 is in use"
            exit 1
        else
            echo "Port $2 is available"
            exit 0
        fi
        ;;
    list-allocated)
        get_allocated_ports
        ;;
    *)
        echo "Usage: $0 {allocate [app_name]|check <port>|list-allocated}" >&2
        exit 1
        ;;
esac
