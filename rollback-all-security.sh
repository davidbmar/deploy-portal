#!/bin/bash
#
# Emergency Rollback All Security Changes
# Reverts all security hardening implementations
# USE WITH CAUTION - Only for emergency situations
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_ROOT="${DEPLOYMENT_ROOT:-/home/ubuntu/deployments}"
REGISTRY_FILE="${REGISTRY_FILE:-$DEPLOYMENT_ROOT/.registry.json}"

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

echo -e "${RED}=========================================${NC}"
echo -e "${RED}EMERGENCY SECURITY ROLLBACK${NC}"
echo -e "${RED}=========================================${NC}"
echo ""
echo -e "${YELLOW}WARNING: This will rollback ALL security hardening!${NC}"
echo -e "${YELLOW}This includes:${NC}"
echo "  - AppArmor profiles"
echo "  - seccomp filtering"
echo "  - Firecracker VMs"
echo "  - SystemD security directives"
echo "  - Security monitoring"
echo ""
echo -e "${RED}Only use this in emergency situations!${NC}"
echo ""
read -p "Are you absolutely sure? (type 'YES' to confirm): " confirm

if [ "$confirm" != "YES" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
log_info "Starting emergency rollback..."

# Step 1: Disable AppArmor profiles
echo ""
log_info "Step 1/7: Disabling AppArmor profiles..."

if command -v aa-teardown &> /dev/null; then
    if sudo aa-teardown 2>/dev/null; then
        log_success "AppArmor profiles disabled"
    else
        log_warning "Failed to disable AppArmor (may not be active)"
    fi

    # Disable individual profiles
    profiles=(
        "oauth2-proxy"
        "deploy-portal"
        "ssh-helper"
        "website-cloner"
        "usr.sbin.nginx"
    )

    for profile in "${profiles[@]}"; do
        if [ -f "/etc/apparmor.d/$profile" ]; then
            sudo aa-disable "/etc/apparmor.d/$profile" 2>/dev/null || true
            log_info "  Disabled: $profile"
        fi
    done

    log_success "AppArmor rollback complete"
else
    log_warning "AppArmor tools not available"
fi

# Step 2: Remove seccomp from systemd services
echo ""
log_info "Step 2/7: Removing seccomp from systemd services..."

services=(
    "oauth2-proxy"
    "deploy-portal"
    "ssh-helper"
    "website-cloner"
)

for service in "${services[@]}"; do
    service_file="/etc/systemd/system/${service}.service"

    if [ -f "$service_file" ]; then
        log_info "  Processing: ${service}.service"

        # Backup original
        sudo cp "$service_file" "${service_file}.rollback-backup"

        # Remove security directives
        sudo sed -i '/SystemCallFilter/d' "$service_file"
        sudo sed -i '/RestrictAddressFamilies/d' "$service_file"
        sudo sed -i '/RestrictNamespaces/d' "$service_file"
        sudo sed -i '/ProtectSystem/d' "$service_file"
        sudo sed -i '/ProtectHome/d' "$service_file"
        sudo sed -i '/ReadWritePaths/d' "$service_file"
        sudo sed -i '/ProtectKernelTunables/d' "$service_file"
        sudo sed -i '/ProtectKernelModules/d' "$service_file"
        sudo sed -i '/ProtectControlGroups/d' "$service_file"
        sudo sed -i '/RestrictRealtime/d' "$service_file"
        sudo sed -i '/RestrictSUIDSGID/d' "$service_file"
        sudo sed -i '/LockPersonality/d' "$service_file"
        sudo sed -i '/CapabilityBoundingSet/d' "$service_file"
        sudo sed -i '/AmbientCapabilities/d' "$service_file"
        sudo sed -i '/AppArmorProfile/d' "$service_file"

        log_success "    Cleaned: ${service}.service"
    fi
done

# Reload systemd
sudo systemctl daemon-reload
log_success "Systemd services updated"

# Step 3: Restart services
echo ""
log_info "Step 3/7: Restarting services..."

for service in "${services[@]}"; do
    if systemctl is-active --quiet "${service}.service" 2>/dev/null; then
        log_info "  Restarting: ${service}.service"
        sudo systemctl restart "${service}.service" || log_warning "    Failed to restart $service"
    fi
done

log_success "Services restarted"

# Step 4: Rollback Firecracker deployments
echo ""
log_info "Step 4/7: Rolling back Firecracker deployments..."

if [ -f "$REGISTRY_FILE" ]; then
    # Find all apps using Firecracker
    firecracker_apps=$(jq -r 'to_entries[] | select(.value.isolation == "firecracker") | .key' "$REGISTRY_FILE" 2>/dev/null || echo "")

    if [ -n "$firecracker_apps" ]; then
        while IFS= read -r app_name; do
            if [ -n "$app_name" ]; then
                log_info "  Rolling back: $app_name"

                if [ -f "$SCRIPT_DIR/migration/rollback-firecracker.sh" ]; then
                    bash "$SCRIPT_DIR/migration/rollback-firecracker.sh" "$app_name" 2>/dev/null || log_warning "    Failed to rollback $app_name"
                else
                    log_warning "    Rollback script not found"
                fi
            fi
        done <<< "$firecracker_apps"

        log_success "Firecracker rollback complete"
    else
        log_info "No Firecracker deployments found"
    fi
else
    log_warning "Registry file not found"
fi

# Step 5: Remove Docker seccomp
echo ""
log_info "Step 5/7: Removing Docker seccomp profiles..."

# Find all docker-compose files with seccomp
compose_files=$(find "$DEPLOYMENT_ROOT" -name "docker-compose.yml" -o -name "docker-compose.yaml" 2>/dev/null || true)

if [ -n "$compose_files" ]; then
    while IFS= read -r compose_file; do
        if [ -f "$compose_file" ] && grep -q "seccomp:" "$compose_file"; then
            app_name=$(basename "$(dirname "$compose_file")")
            log_info "  Removing seccomp from: $app_name"

            # Look for backup
            backup_file=$(find "$(dirname "$compose_file")" -name "docker-compose.yml.backup-*" | sort -r | head -1)

            if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
                cp "$backup_file" "$compose_file"
                log_success "    Restored from backup"
            else
                log_warning "    No backup found, manual cleanup needed"
            fi
        fi
    done <<< "$compose_files"

    log_success "Docker seccomp profiles removed"
else
    log_info "No docker-compose files found"
fi

# Step 6: Disable monitoring
echo ""
log_info "Step 6/7: Disabling security monitoring..."

# Remove cron job
if crontab -l 2>/dev/null | grep -q "security-monitor.sh"; then
    crontab -l 2>/dev/null | grep -v "security-monitor.sh" | crontab - || true
    log_success "Monitoring cron job removed"
else
    log_info "No monitoring cron job found"
fi

# Step 7: Re-enable SSH (manual step)
echo ""
log_info "Step 7/7: SSH Port Information..."
log_warning "SSH port 22 status cannot be changed automatically"
log_warning "To re-enable SSH port 22:"
log_warning "  1. Update security group in AWS Console"
log_warning "  2. Add inbound rule: TCP 22 from your IP"
log_info "SSM access is still available if needed"

# Rollback complete
echo ""
log_success "========================================="
log_success "Emergency Rollback Complete!"
log_success "========================================="
echo ""
log_info "What was rolled back:"
log_success "  ✓ AppArmor profiles disabled"
log_success "  ✓ seccomp removed from systemd services"
log_success "  ✓ Firecracker VMs rolled back to Docker/systemd"
log_success "  ✓ Docker seccomp profiles removed"
log_success "  ✓ Security monitoring disabled"
echo ""
log_warning "Manual steps still required:"
log_warning "  - Re-enable SSH port 22 in security group (if needed)"
log_warning "  - Review and test all applications"
log_warning "  - Remove /etc/seccomp profiles (if desired)"
log_warning "  - Remove /etc/apparmor.d profiles (if desired)"
echo ""
log_info "Backup files created:"
log_info "  - Systemd services: /etc/systemd/system/*.rollback-backup"
log_info "  - Docker compose: docker-compose.yml.backup-*"
echo ""
log_warning "System is now in pre-hardening state"
log_warning "Re-harden when issues are resolved"
echo ""
