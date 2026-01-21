#!/bin/bash
#
# Verify Security Implementation
# Checks that all files were created correctly
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

check_file() {
    local file="$1"
    local type="${2:-file}"

    if [ "$type" = "dir" ]; then
        if [ -d "$file" ]; then
            echo -e "${GREEN}✓${NC} Directory exists: $file"
            PASSED=$((PASSED + 1))
            return 0
        else
            echo -e "${RED}✗${NC} Directory missing: $file"
            FAILED=$((FAILED + 1))
            return 1
        fi
    else
        if [ -f "$file" ]; then
            if [ -x "$file" ] || [[ "$file" =~ \.(json|yml|yaml|md|tmpl)$ ]]; then
                echo -e "${GREEN}✓${NC} File exists: $file"
                PASSED=$((PASSED + 1))
                return 0
            else
                echo -e "${YELLOW}⚠${NC} File exists but not executable: $file"
                PASSED=$((PASSED + 1))
                return 0
            fi
        else
            echo -e "${RED}✗${NC} File missing: $file"
            FAILED=$((FAILED + 1))
            return 1
        fi
    fi
}

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Security Implementation Verification${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Check directories
echo -e "${BLUE}=== Checking Directories ===${NC}"
check_file "/home/ubuntu/src/deploy-portal/scripts" "dir"
check_file "/home/ubuntu/src/deploy-portal/security" "dir"
check_file "/home/ubuntu/src/deploy-portal/security/apparmor" "dir"
check_file "/home/ubuntu/src/deploy-portal/security/seccomp" "dir"
check_file "/home/ubuntu/src/deploy-portal/firecracker" "dir"
check_file "/home/ubuntu/src/deploy-portal/migration" "dir"
check_file "/home/ubuntu/src/deploy-portal/tests" "dir"
check_file "/home/ubuntu/src/deploy-portal/monitoring" "dir"
check_file "/etc/seccomp" "dir"

echo ""
echo -e "${BLUE}=== Checking Scripts ===${NC}"
check_file "/home/ubuntu/src/deploy-portal/scripts/ssm-connect.sh"
check_file "/home/ubuntu/src/deploy-portal/security/apparmor/load-profiles.sh"
check_file "/home/ubuntu/src/deploy-portal/security/apparmor/enforce-profiles.sh"
check_file "/home/ubuntu/src/deploy-portal/security/inject-seccomp.sh"
check_file "/home/ubuntu/src/deploy-portal/firecracker/install-firecracker.sh"
check_file "/home/ubuntu/src/deploy-portal/firecracker/build-rootfs.sh"
check_file "/home/ubuntu/src/deploy-portal/firecracker/vm-manager.py"
check_file "/home/ubuntu/src/deploy-portal/firecracker/docker-compose-fc.sh"
check_file "/home/ubuntu/src/deploy-portal/migration/migrate-to-firecracker.sh"
check_file "/home/ubuntu/src/deploy-portal/migration/rollback-firecracker.sh"
check_file "/home/ubuntu/src/deploy-portal/tests/security-tests.sh"
check_file "/home/ubuntu/src/deploy-portal/tests/performance-benchmark.sh"
check_file "/home/ubuntu/src/deploy-portal/monitoring/security-monitor.sh"
check_file "/home/ubuntu/src/deploy-portal/monitoring/install-monitoring.sh"
check_file "/home/ubuntu/src/deploy-portal/rollback-all-security.sh"

echo ""
echo -e "${BLUE}=== Checking Profiles ===${NC}"
check_file "/home/ubuntu/src/deploy-portal/security/apparmor/oauth2-proxy"
check_file "/home/ubuntu/src/deploy-portal/security/apparmor/deploy-portal"
check_file "/home/ubuntu/src/deploy-portal/security/apparmor/ssh-helper"
check_file "/home/ubuntu/src/deploy-portal/security/apparmor/website-cloner"
check_file "/home/ubuntu/src/deploy-portal/security/apparmor/usr.sbin.nginx"
check_file "/home/ubuntu/src/deploy-portal/security/seccomp/oauth2-proxy.json"
check_file "/home/ubuntu/src/deploy-portal/security/seccomp/deploy-portal.json"
check_file "/home/ubuntu/src/deploy-portal/security/seccomp/docker-default.json"
check_file "/etc/seccomp/oauth2-proxy.json"
check_file "/etc/seccomp/deploy-portal.json"
check_file "/etc/seccomp/docker-default.json"

echo ""
echo -e "${BLUE}=== Checking Templates ===${NC}"
check_file "/home/ubuntu/src/deploy-portal/automation/templates/systemd-service.tmpl"
check_file "/home/ubuntu/src/deploy-portal/automation/templates/docker-compose-base.yml"

echo ""
echo -e "${BLUE}=== Checking Documentation ===${NC}"
check_file "/home/ubuntu/src/deploy-portal/SECURITY_IMPLEMENTATION_GUIDE.md"
check_file "/home/ubuntu/src/deploy-portal/IMPLEMENTATION_COMPLETE.md"

echo ""
echo -e "${BLUE}=== Checking Modified Files ===${NC}"
if grep -q "ssm:" "/home/ubuntu/src/easy-cognito-nginx-gateway-auth/terraform/modules/compute/main.tf" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Terraform IAM policy updated"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗${NC} Terraform IAM policy not updated"
    FAILED=$((FAILED + 1))
fi

if grep -q "use-firecracker" "/home/ubuntu/src/deploy-portal/automation/deploy-app.sh" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} deploy-app.sh updated with Firecracker flag"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗${NC} deploy-app.sh not updated"
    FAILED=$((FAILED + 1))
fi

if grep -q "SystemCallFilter" "/home/ubuntu/src/deploy-portal/automation/templates/systemd-service.tmpl" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} systemd template updated with security directives"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗${NC} systemd template not updated"
    FAILED=$((FAILED + 1))
fi

# Summary
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Verification Summary${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}✓ All files verified successfully!${NC}"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Review SECURITY_IMPLEMENTATION_GUIDE.md"
    echo "2. Review IMPLEMENTATION_COMPLETE.md"
    echo "3. Start with Phase 1 (SSM Integration)"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some files are missing or incorrect${NC}"
    echo ""
    exit 1
fi
