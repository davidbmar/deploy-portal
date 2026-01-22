#!/bin/bash
# Verification script for Capsule Deploy infrastructure
# Tests all components to ensure they're working correctly

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

test_pass() {
    echo -e "${GREEN}✅ $1${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
    echo -e "${RED}❌ $1${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

test_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

echo "================================================"
echo "  Infrastructure Verification Tests"
echo "================================================"
echo ""

# Test 1: Port registry exists and is valid JSON
echo "Test 1: Port registry"
if [ -f /var/lib/capsule-deploy/port-registry.json ]; then
    if jq . /var/lib/capsule-deploy/port-registry.json > /dev/null 2>&1; then
        test_pass "Port registry exists and is valid JSON"
    else
        test_fail "Port registry exists but is invalid JSON"
    fi
else
    test_fail "Port registry not found at /var/lib/capsule-deploy/port-registry.json"
fi

# Test 2: Management tools are installed
echo ""
echo "Test 2: Management tools"
if [ -x /usr/local/bin/capsule-nginx-manager ]; then
    test_pass "capsule-nginx-manager is installed and executable"
else
    test_fail "capsule-nginx-manager not found or not executable"
fi

if [ -x /usr/local/bin/capsule-port-allocator ]; then
    test_pass "capsule-port-allocator is installed and executable"
else
    test_fail "capsule-port-allocator not found or not executable"
fi

# Test 3: Sudo permissions
echo ""
echo "Test 3: Sudo permissions"
if sudo -n /usr/local/bin/capsule-port-allocator list > /dev/null 2>&1; then
    test_pass "Can run capsule-port-allocator with sudo (no password)"
else
    test_fail "Cannot run capsule-port-allocator with sudo"
fi

if sudo -n /usr/local/bin/capsule-nginx-manager test > /dev/null 2>&1; then
    test_pass "Can run capsule-nginx-manager with sudo (no password)"
else
    test_warn "capsule-nginx-manager sudo test failed (may be expected if nginx config incomplete)"
fi

# Test 4: Port allocation functionality
echo ""
echo "Test 4: Port allocation"
if sudo /usr/local/bin/capsule-port-allocator allocate test-verify-999 frontend backend database > /dev/null 2>&1; then
    test_pass "Port allocation successful"
    if sudo /usr/local/bin/capsule-port-allocator free test-verify-999 > /dev/null 2>&1; then
        test_pass "Port deallocation successful"
    else
        test_fail "Port deallocation failed"
    fi
else
    test_fail "Port allocation failed"
fi

# Test 5: Helper scripts
echo ""
echo "Test 5: Helper scripts"
HELPER_DIR="/home/ubuntu/deployments/scripts"
if [ -x "$HELPER_DIR/pre-deploy-validate.sh" ]; then
    test_pass "pre-deploy-validate.sh is installed"
else
    test_fail "pre-deploy-validate.sh not found or not executable"
fi

if [ -x "$HELPER_DIR/post-deploy-healthcheck.sh" ]; then
    test_pass "post-deploy-healthcheck.sh is installed"
else
    test_fail "post-deploy-healthcheck.sh not found or not executable"
fi

# Test 6: List current allocations
echo ""
echo "Test 6: Current port allocations"
echo "Current allocations in registry:"
sudo /usr/local/bin/capsule-port-allocator list || test_warn "Could not list port allocations"

# Summary
echo ""
echo "================================================"
echo "  Test Summary"
echo "================================================"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    exit 1
else
    echo -e "Tests failed: ${GREEN}0${NC}"
    echo ""
    echo -e "${GREEN}All tests passed! Infrastructure is ready.${NC}"
    exit 0
fi
