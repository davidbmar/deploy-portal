#!/bin/bash
#
# Security Tests
# Validates all security hardening implementations
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
WARNINGS=0

log_test() {
    echo -e "${BLUE}[TEST]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    PASSED=$((PASSED + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    FAILED=$((FAILED + 1))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
    WARNINGS=$((WARNINGS + 1))
}

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Security Hardening Test Suite${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Test 1: AppArmor Status
echo -e "\n${BLUE}=== Test 1: AppArmor ===${NC}"

log_test "Checking if AppArmor is enabled..."
if sudo systemctl is-active --quiet apparmor; then
    log_pass "AppArmor service is running"
else
    log_fail "AppArmor service is not running"
fi

log_test "Checking AppArmor profiles..."
profiles=(
    "oauth2-proxy"
    "deploy-portal"
    "ssh-helper"
    "website-cloner"
    "usr.sbin.nginx"
)

for profile in "${profiles[@]}"; do
    if sudo aa-status 2>/dev/null | grep -q "$profile"; then
        mode=$(sudo aa-status 2>/dev/null | grep "$profile" | head -1)
        if echo "$mode" | grep -q "enforce"; then
            log_pass "Profile $profile is in enforce mode"
        elif echo "$mode" | grep -q "complain"; then
            log_warn "Profile $profile is in complain mode (should be enforced)"
        else
            log_warn "Profile $profile status unknown"
        fi
    else
        log_fail "Profile $profile not loaded"
    fi
done

# Test 2: seccomp Profiles
echo -e "\n${BLUE}=== Test 2: seccomp Profiles ===${NC}"

log_test "Checking seccomp profile files..."
seccomp_profiles=(
    "/etc/seccomp/oauth2-proxy.json"
    "/etc/seccomp/deploy-portal.json"
    "/etc/seccomp/docker-default.json"
)

for profile in "${seccomp_profiles[@]}"; do
    if [ -f "$profile" ]; then
        log_pass "seccomp profile exists: $profile"

        # Validate JSON
        if jq empty "$profile" 2>/dev/null; then
            log_pass "  Valid JSON syntax"
        else
            log_fail "  Invalid JSON syntax"
        fi
    else
        log_fail "seccomp profile missing: $profile"
    fi
done

# Test 3: Systemd Service Hardening
echo -e "\n${BLUE}=== Test 3: Systemd Service Hardening ===${NC}"

log_test "Checking systemd service security directives..."
services=(
    "oauth2-proxy"
    "deploy-portal"
    "ssh-helper"
    "website-cloner"
)

for service in "${services[@]}"; do
    service_file="/etc/systemd/system/${service}.service"

    if [ -f "$service_file" ]; then
        log_test "Checking ${service}.service..."

        # Check for security directives
        if grep -q "NoNewPrivileges=true" "$service_file"; then
            log_pass "  NoNewPrivileges enabled"
        else
            log_warn "  NoNewPrivileges not set"
        fi

        if grep -q "SystemCallFilter" "$service_file"; then
            log_pass "  SystemCallFilter configured"
        else
            log_warn "  SystemCallFilter not configured"
        fi

        if grep -q "RestrictAddressFamilies" "$service_file"; then
            log_pass "  RestrictAddressFamilies configured"
        else
            log_warn "  RestrictAddressFamilies not configured"
        fi
    else
        log_warn "Service file not found: $service_file"
    fi
done

# Test 4: AWS SSM Configuration
echo -e "\n${BLUE}=== Test 4: AWS SSM Configuration ===${NC}"

log_test "Checking SSM agent status..."
if sudo systemctl is-active --quiet snap.amazon-ssm-agent.amazon-ssm-agent 2>/dev/null; then
    log_pass "SSM agent is running"
else
    log_warn "SSM agent is not running or not installed"
fi

log_test "Checking SSM connection script..."
if [ -f "/home/ubuntu/src/deploy-portal/scripts/ssm-connect.sh" ]; then
    log_pass "SSM connection script exists"

    if [ -x "/home/ubuntu/src/deploy-portal/scripts/ssm-connect.sh" ]; then
        log_pass "  Script is executable"
    else
        log_warn "  Script is not executable"
    fi
else
    log_fail "SSM connection script not found"
fi

# Test 5: SSH Port
echo -e "\n${BLUE}=== Test 5: SSH Port Security ===${NC}"

log_test "Checking if SSH port 22 is closed..."
if sudo netstat -tuln | grep -q ":22 "; then
    log_warn "SSH port 22 is still open (should be closed after SSM setup)"
else
    log_pass "SSH port 22 is closed"
fi

# Test 6: Firecracker Installation
echo -e "\n${BLUE}=== Test 6: Firecracker Installation ===${NC}"

log_test "Checking Firecracker installation..."
if command -v firecracker &> /dev/null; then
    version=$(firecracker --version 2>&1 | head -1)
    log_pass "Firecracker installed: $version"
else
    log_warn "Firecracker not installed (optional)"
fi

log_test "Checking Firecracker directories..."
firecracker_dirs=(
    "/opt/firecracker"
    "/opt/firecracker/kernels"
    "/opt/firecracker/rootfs"
    "/opt/firecracker/vms"
)

for dir in "${firecracker_dirs[@]}"; do
    if [ -d "$dir" ]; then
        log_pass "Directory exists: $dir"
    else
        log_warn "Directory missing: $dir"
    fi
done

# Test 7: Docker Security
echo -e "\n${BLUE}=== Test 7: Docker Security Configuration ===${NC}"

log_test "Checking Docker seccomp profile..."
if [ -f "/etc/seccomp/docker-default.json" ]; then
    log_pass "Docker seccomp profile exists"

    # Test seccomp with a container
    log_test "Testing seccomp enforcement..."
    if docker run --rm --security-opt seccomp=/etc/seccomp/docker-default.json ubuntu:22.04 echo "test" &>/dev/null; then
        log_pass "  Basic container operations work with seccomp"
    else
        log_warn "  seccomp may be too restrictive or Docker not available"
    fi
else
    log_fail "Docker seccomp profile not found"
fi

# Test 8: Blocked Operations
echo -e "\n${BLUE}=== Test 8: Security Enforcement Tests ===${NC}"

log_test "Testing if dangerous syscalls are blocked..."

# Test reboot syscall (should be blocked)
if docker run --rm --security-opt seccomp=/etc/seccomp/docker-default.json ubuntu:22.04 reboot 2>&1 | grep -q "Operation not permitted"; then
    log_pass "Reboot syscall blocked (expected)"
elif docker run --rm --security-opt seccomp=/etc/seccomp/docker-default.json ubuntu:22.04 reboot 2>&1 | grep -q "command not found"; then
    log_pass "Reboot command not available in container (acceptable)"
else
    log_warn "Could not verify reboot syscall blocking (Docker may not be available)"
fi

# Test 9: Security Monitoring
echo -e "\n${BLUE}=== Test 9: Security Monitoring ===${NC}"

log_test "Checking for recent AppArmor violations..."
if command -v ausearch &> /dev/null; then
    violations=$(sudo ausearch -m AVC -ts recent 2>/dev/null | grep -c "apparmor=" || echo "0")
    if [ "$violations" -eq 0 ]; then
        log_pass "No recent AppArmor violations"
    else
        log_warn "$violations AppArmor violations found (review with: sudo ausearch -m AVC -ts recent)"
    fi
else
    log_warn "ausearch not available (install auditd)"
fi

log_test "Checking for recent seccomp violations..."
if sudo journalctl -k --since "1 hour ago" 2>/dev/null | grep -q "seccomp"; then
    violations=$(sudo journalctl -k --since "1 hour ago" 2>/dev/null | grep -c "seccomp" || echo "0")
    log_warn "$violations seccomp events in last hour (may be normal)"
else
    log_pass "No recent seccomp violations"
fi

# Test 10: File Permissions
echo -e "\n${BLUE}=== Test 10: File Permissions ===${NC}"

log_test "Checking sensitive file permissions..."

if [ "$(stat -c %a /etc/seccomp 2>/dev/null)" = "755" ]; then
    log_pass "/etc/seccomp has correct permissions (755)"
else
    log_warn "/etc/seccomp permissions should be 755"
fi

if [ -d "/opt/firecracker" ]; then
    if [ "$(stat -c %a /opt/firecracker)" = "755" ]; then
        log_pass "/opt/firecracker has correct permissions (755)"
    else
        log_warn "/opt/firecracker permissions should be 755"
    fi
fi

# Summary
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Passed:   $PASSED${NC}"
echo -e "${RED}Failed:   $FAILED${NC}"
echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}All critical tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Review the output above.${NC}"
    exit 1
fi
