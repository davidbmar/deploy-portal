#!/bin/bash
# Capsule Deploy Infrastructure Installation Script
# Sets up deployment infrastructure on EC2 server for zero-touch deployments
#
# Usage: sudo ./install-infrastructure.sh [--skip-import]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INSTALL]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root (use sudo)"
fi

SKIP_IMPORT=false
if [ "${1:-}" = "--skip-import" ]; then
    SKIP_IMPORT=true
fi

echo "================================================"
echo "  Capsule Deploy Infrastructure Installation"
echo "================================================"
echo ""

# Section 1: Create Port Registry System
log "Section 1: Creating port registry system..."

mkdir -p /var/lib/capsule-deploy
chmod 755 /var/lib/capsule-deploy

if [ ! -f /var/lib/capsule-deploy/port-registry.json ]; then
    cat > /var/lib/capsule-deploy/port-registry.json << 'EOF'
{
  "meta": {
    "last_updated": "",
    "format_version": "1.0",
    "description": "Central registry of allocated ports for all deployed apps"
  },
  "allocations": {}
}
EOF
    chmod 644 /var/lib/capsule-deploy/port-registry.json
    log "Created port registry at /var/lib/capsule-deploy/port-registry.json"
else
    info "Port registry already exists, skipping creation"
fi

# Section 2: Install Nginx Manager
log "Section 2: Installing nginx manager..."

cp "$SCRIPT_DIR/bin/capsule-nginx-manager" /usr/local/bin/capsule-nginx-manager
chmod +x /usr/local/bin/capsule-nginx-manager
log "Installed capsule-nginx-manager to /usr/local/bin/"

# Section 3: Install Port Allocator
log "Section 3: Installing port allocator..."

cp "$SCRIPT_DIR/bin/capsule-port-allocator" /usr/local/bin/capsule-port-allocator
chmod +x /usr/local/bin/capsule-port-allocator
log "Installed capsule-port-allocator to /usr/local/bin/"

# Section 4: Configure Sudo Permissions
log "Section 4: Configuring sudo permissions..."

cp "$SCRIPT_DIR/config/sudoers-capsule-deploy" /etc/sudoers.d/capsule-deploy
chmod 440 /etc/sudoers.d/capsule-deploy

# Verify sudoers syntax
if visudo -c; then
    log "Sudo permissions configured successfully"
else
    error "Sudoers syntax check failed"
fi

# Section 5: Install Helper Scripts
log "Section 5: Installing helper scripts..."

HELPER_DIR="/home/ubuntu/deployments/.scripts"
mkdir -p "$HELPER_DIR"
chown ubuntu:ubuntu "$HELPER_DIR"

cp "$SCRIPT_DIR/helpers/pre-deploy-validate.sh" "$HELPER_DIR/"
cp "$SCRIPT_DIR/helpers/post-deploy-healthcheck.sh" "$HELPER_DIR/"
chmod +x "$HELPER_DIR"/*.sh
chown ubuntu:ubuntu "$HELPER_DIR"/*.sh

log "Installed helper scripts to $HELPER_DIR/"

# Section 6: Import Existing Port Allocations (optional)
if [ "$SKIP_IMPORT" = false ]; then
    log "Section 6: Importing existing port allocations..."

    REGISTRY="/var/lib/capsule-deploy/port-registry.json"

    # Check for existing deployments
    FOUND_ANY=false

    if docker ps 2>/dev/null | grep -q "pydantic-ai-agent-evaluator-01"; then
        info "Found pydantic-ai-agent-evaluator-01"
        jq '.allocations["pydantic-ai-agent-evaluator-01"] = {"frontend": 3020, "backend": 8020, "database": 5435}' "$REGISTRY" > "${REGISTRY}.tmp"
        mv "${REGISTRY}.tmp" "$REGISTRY"
        FOUND_ANY=true
    fi

    if docker ps 2>/dev/null | grep -q "pydantic-ai-agent-evaluator-02"; then
        info "Found pydantic-ai-agent-evaluator-02"
        jq '.allocations["pydantic-ai-agent-evaluator-02"] = {"frontend": 3021, "backend": 8021, "database": 5436}' "$REGISTRY" > "${REGISTRY}.tmp"
        mv "${REGISTRY}.tmp" "$REGISTRY"
        FOUND_ANY=true
    fi

    if docker ps 2>/dev/null | grep -q "secure-app-01"; then
        info "Found secure-app-01"
        jq '.allocations["secure-app-01"] = {"frontend": 3001, "backend": 8000, "database": 5432}' "$REGISTRY" > "${REGISTRY}.tmp"
        mv "${REGISTRY}.tmp" "$REGISTRY"
        FOUND_ANY=true
    fi

    if [ "$FOUND_ANY" = true ]; then
        # Update timestamp
        jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.meta.last_updated = $ts' "$REGISTRY" > "${REGISTRY}.tmp"
        mv "${REGISTRY}.tmp" "$REGISTRY"
        log "Imported existing port allocations"
    else
        info "No existing deployments found to import"
    fi
else
    info "Skipping port allocation import (--skip-import flag)"
fi

# Section 7: Verification
echo ""
log "Running verification tests..."
echo ""

# Test 1: Port registry
info "Test 1: Port registry exists and is readable"
if [ -f /var/lib/capsule-deploy/port-registry.json ]; then
    jq . /var/lib/capsule-deploy/port-registry.json > /dev/null && echo "  ✅ Port registry valid"
else
    error "Port registry not found"
fi

# Test 2: Executables installed
info "Test 2: Checking installed executables"
[ -x /usr/local/bin/capsule-nginx-manager ] && echo "  ✅ capsule-nginx-manager installed" || error "capsule-nginx-manager not executable"
[ -x /usr/local/bin/capsule-port-allocator ] && echo "  ✅ capsule-port-allocator installed" || error "capsule-port-allocator not executable"

# Test 3: Helper scripts
info "Test 3: Checking helper scripts"
[ -x "$HELPER_DIR/pre-deploy-validate.sh" ] && echo "  ✅ pre-deploy-validate.sh installed" || warn "pre-deploy-validate.sh not found"
[ -x "$HELPER_DIR/post-deploy-healthcheck.sh" ] && echo "  ✅ post-deploy-healthcheck.sh installed" || warn "post-deploy-healthcheck.sh not found"

# Test 4: Sudo permissions
info "Test 4: Checking sudo permissions"
if sudo -u ubuntu sudo -n /usr/local/bin/capsule-port-allocator list > /dev/null 2>&1; then
    echo "  ✅ Sudo permissions working"
else
    warn "Sudo permissions may not be configured correctly"
fi

# Test 5: Port allocator functionality
info "Test 5: Testing port allocator"
if sudo -u ubuntu sudo /usr/local/bin/capsule-port-allocator allocate test-install-999 frontend backend database > /dev/null 2>&1; then
    sudo /usr/local/bin/capsule-port-allocator free test-install-999 > /dev/null 2>&1
    echo "  ✅ Port allocator functional"
else
    warn "Port allocator test failed"
fi

# Test 6: Nginx manager
info "Test 6: Testing nginx manager"
if /usr/local/bin/capsule-nginx-manager test > /dev/null 2>&1; then
    echo "  ✅ Nginx manager functional"
else
    warn "Nginx configuration test had warnings (may be expected)"
fi

echo ""
echo "================================================"
log "Infrastructure installation complete!"
echo "================================================"
echo ""
echo "Summary of installed components:"
echo "  📁 /var/lib/capsule-deploy/          - Port registry system"
echo "  🔧 /usr/local/bin/capsule-*          - Management tools"
echo "  📝 /etc/sudoers.d/capsule-deploy    - Sudo permissions"
echo "  🛠️  $HELPER_DIR/                     - Helper scripts"
echo ""
echo "Next steps:"
echo "  1. Review port allocations: sudo capsule-port-allocator list"
echo "  2. Test nginx manager: sudo capsule-nginx-manager test"
echo "  3. Deploy a new app using the automated deployment system"
echo ""
