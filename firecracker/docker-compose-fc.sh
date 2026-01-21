#!/bin/bash
#
# Docker Compose Firecracker Wrapper
# Provides docker-compose compatibility for Firecracker VMs
# Usage: docker-compose-fc.sh <app_name> <command>
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_MANAGER="$SCRIPT_DIR/vm-manager.py"

# Parse arguments
APP_NAME="${1:-}"
COMMAND="${2:-up}"

if [ -z "$APP_NAME" ]; then
    echo -e "${RED}Error: App name required${NC}"
    echo "Usage: $0 <app_name> <command>"
    exit 1
fi

VM_ID="vm-$APP_NAME"
DEPLOYMENT_DIR="/home/ubuntu/deployments/$APP_NAME"
COMPOSE_FILE="$DEPLOYMENT_DIR/docker-compose.yml"

# Check if VM manager exists
if [ ! -f "$VM_MANAGER" ]; then
    echo -e "${RED}Error: VM manager not found: $VM_MANAGER${NC}"
    exit 1
fi

# Function to wait for VM SSH
wait_for_vm() {
    local vm_ip="172.16.0.2"
    local max_attempts=30
    local attempt=0

    echo -e "${YELLOW}Waiting for VM to be ready...${NC}"

    while [ $attempt -lt $max_attempts ]; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 "root@$vm_ip" "echo ready" 2>/dev/null; then
            echo -e "${GREEN}✓ VM is ready${NC}"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    echo -e "${RED}✗ VM failed to become ready${NC}"
    return 1
}

# Function to copy files to VM
copy_to_vm() {
    local vm_ip="172.16.0.2"
    echo -e "${YELLOW}Copying application files to VM...${NC}"

    # Create directory in VM
    ssh -o StrictHostKeyChecking=no "root@$vm_ip" "mkdir -p /app/$APP_NAME"

    # Copy files
    if scp -o StrictHostKeyChecking=no -r "$DEPLOYMENT_DIR"/* "root@$vm_ip:/app/$APP_NAME/"; then
        echo -e "${GREEN}✓ Files copied${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to copy files${NC}"
        return 1
    fi
}

# Main command handler
case "$COMMAND" in
    up)
        echo -e "${GREEN}Starting Firecracker VM for $APP_NAME${NC}"

        # Check if VM is already running
        if python3 "$VM_MANAGER" status "$VM_ID" 2>/dev/null; then
            echo -e "${YELLOW}VM already running${NC}"
        else
            # Start VM
            if ! python3 "$VM_MANAGER" start "$VM_ID" --vcpus 2 --memory 512; then
                echo -e "${RED}Failed to start VM${NC}"
                exit 1
            fi
        fi

        # Wait for VM
        if ! wait_for_vm; then
            exit 1
        fi

        # Copy files to VM
        if ! copy_to_vm; then
            exit 1
        fi

        # Run docker-compose inside VM
        echo -e "${YELLOW}Starting docker-compose inside VM...${NC}"
        if ssh -o StrictHostKeyChecking=no "root@172.16.0.2" "cd /app/$APP_NAME && docker-compose up -d"; then
            echo -e "${GREEN}✓ Application started in Firecracker VM${NC}"
        else
            echo -e "${RED}✗ Failed to start application${NC}"
            exit 1
        fi
        ;;

    down)
        echo -e "${YELLOW}Stopping application in Firecracker VM${NC}"

        if python3 "$VM_MANAGER" status "$VM_ID" 2>/dev/null; then
            # Stop docker-compose
            ssh -o StrictHostKeyChecking=no "root@172.16.0.2" "cd /app/$APP_NAME && docker-compose down" || true

            # Stop VM
            if python3 "$VM_MANAGER" stop "$VM_ID"; then
                echo -e "${GREEN}✓ VM stopped${NC}"
            else
                echo -e "${RED}✗ Failed to stop VM${NC}"
                exit 1
            fi
        else
            echo -e "${YELLOW}VM not running${NC}"
        fi
        ;;

    restart)
        echo -e "${YELLOW}Restarting application in Firecracker VM${NC}"
        "$0" "$APP_NAME" down
        sleep 2
        "$0" "$APP_NAME" up
        ;;

    status)
        if python3 "$VM_MANAGER" status "$VM_ID" 2>/dev/null; then
            echo -e "${GREEN}✓ VM is running${NC}"

            # Check docker-compose status
            if ssh -o StrictHostKeyChecking=no "root@172.16.0.2" "cd /app/$APP_NAME && docker-compose ps" 2>/dev/null; then
                echo ""
            fi
        else
            echo -e "${RED}✗ VM is not running${NC}"
        fi
        ;;

    logs)
        if python3 "$VM_MANAGER" status "$VM_ID" 2>/dev/null; then
            ssh -o StrictHostKeyChecking=no "root@172.16.0.2" "cd /app/$APP_NAME && docker-compose logs -f"
        else
            echo -e "${RED}✗ VM is not running${NC}"
            exit 1
        fi
        ;;

    *)
        echo -e "${RED}Unknown command: $COMMAND${NC}"
        echo "Supported commands: up, down, restart, status, logs"
        exit 1
        ;;
esac
