#!/bin/bash

# Verification script for deploy-portal setup

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

warn() {
    echo -e "${YELLOW}!${NC} $1"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Deploy Portal Setup Verification"
echo "================================="
echo ""

# Check 1: Virtual environment
echo "Checking Python virtual environment..."
if [ -d "$PROJECT_ROOT/venv" ]; then
    pass "Virtual environment exists"

    if [ -f "$PROJECT_ROOT/venv/bin/python" ]; then
        pass "Python interpreter found"
        PYTHON_VERSION=$("$PROJECT_ROOT/venv/bin/python" --version)
        pass "Python version: $PYTHON_VERSION"
    else
        fail "Python interpreter not found in venv"
    fi
else
    fail "Virtual environment not found at $PROJECT_ROOT/venv"
fi

# Check 2: Required directories
echo "Checking required directories..."
for dir in data keys logs automation/scripts; do
    if [ -d "$PROJECT_ROOT/$dir" ]; then
        pass "Directory exists: $dir"
    else
        fail "Directory missing: $dir"
    fi
done

# Check 3: Deployment directories
echo "Checking deployment directories..."
DEPLOYMENT_ROOT="/home/ubuntu/deployments"
if [ -d "$DEPLOYMENT_ROOT" ]; then
    pass "Deployment root exists: $DEPLOYMENT_ROOT"

    if [ -f "$DEPLOYMENT_ROOT/.registry.json" ]; then
        pass "Registry file exists"
    else
        fail "Registry file missing"
    fi

    if [ -d "$DEPLOYMENT_ROOT/.backups" ]; then
        pass "Backup directory exists"
    else
        warn "Backup directory missing"
    fi
else
    fail "Deployment root missing: $DEPLOYMENT_ROOT"
fi

# Check 4: SSH key
echo "Checking SSH key..."
SSH_KEY="$PROJECT_ROOT/keys/deploy-key.pem"
if [ -f "$SSH_KEY" ]; then
    pass "SSH key exists"

    PERMS=$(stat -c "%a" "$SSH_KEY")
    if [ "$PERMS" = "600" ]; then
        pass "SSH key has correct permissions (600)"
    else
        warn "SSH key permissions are $PERMS (should be 600)"
    fi
else
    warn "SSH key not found at $SSH_KEY (may need manual setup)"
fi

# Check 5: Data files
echo "Checking data files..."
for file in app-registry.json port-registry.json; do
    if [ -f "$PROJECT_ROOT/data/$file" ]; then
        pass "Data file exists: $file"
    else
        fail "Data file missing: $file"
    fi
done

# Check 6: Systemd service
echo "Checking systemd service..."
if [ -f "/etc/systemd/system/deploy-portal.service" ]; then
    pass "Systemd service file exists"
else
    fail "Systemd service file not found"
fi

if systemctl is-enabled --quiet deploy-portal; then
    pass "deploy-portal service is enabled"
else
    fail "deploy-portal service is not enabled"
fi

if systemctl is-active --quiet deploy-portal; then
    pass "deploy-portal service is running"
else
    fail "deploy-portal service is not running"
fi

# Check 7: Nginx configuration
echo "Checking nginx configuration..."
if [ -f "/etc/nginx/conf.d/system-upstreams/deploy-portal.conf" ]; then
    pass "Nginx upstream config exists"
else
    fail "Nginx upstream config not found"
fi

if [ -f "/etc/nginx/conf.d/routes/deploy-portal.conf" ]; then
    pass "Nginx routes config exists"
else
    fail "Nginx routes config not found"
fi

# Check 8: Service connectivity
echo "Checking service connectivity..."
if curl -s http://localhost:5000/ > /dev/null; then
    pass "Deploy-portal responding on port 5000"
else
    fail "Deploy-portal not responding on port 5000"
fi

# Check 9: Python dependencies
echo "Checking Python dependencies..."
if [ -f "$PROJECT_ROOT/requirements.txt" ]; then
    if "$PROJECT_ROOT/venv/bin/pip" list --format=freeze | grep -q flask; then
        pass "Flask is installed"
    else
        fail "Flask is not installed"
    fi
else
    warn "requirements.txt not found"
fi

# Check 10: Activity log directory
echo "Checking activity log directory..."
ACTIVITY_LOG_DIR="/var/log/deploy-sessions"
if [ -d "$ACTIVITY_LOG_DIR" ]; then
    pass "Activity log directory exists"

    if [ -w "$ACTIVITY_LOG_DIR" ]; then
        pass "Activity log directory is writable"
    else
        warn "Activity log directory is not writable"
    fi
else
    fail "Activity log directory missing: $ACTIVITY_LOG_DIR"
fi

# Summary
echo ""
echo "================================="
echo "Verification Summary"
echo "================================="
echo -e "${GREEN}Passed:${NC} $PASSED"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed:${NC} $FAILED"
    echo ""
    echo "Please fix the failed checks before proceeding."
    exit 1
else
    echo -e "${GREEN}All checks passed!${NC}"
    echo ""
    echo "Deploy-portal is properly configured."
    echo ""
    echo "Useful commands:"
    echo "  - Check status: sudo systemctl status deploy-portal"
    echo "  - View logs: sudo journalctl -u deploy-portal -f"
    echo "  - Restart: sudo systemctl restart deploy-portal"
    exit 0
fi
