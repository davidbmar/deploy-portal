#!/bin/bash
# Simple HTTP-based remote verification (no SSH required)
# Tests external accessibility of a deployed instance

set -uo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
PASS=0
FAIL=0
WARN=0

test_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASS++))
}

test_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAIL++))
}

test_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARN++))
}

# Usage
if [ $# -lt 1 ]; then
    echo "Usage: $0 <target-ip-or-domain> [--quick]"
    echo ""
    echo "Examples:"
    echo "  $0 3.87.27.213"
    echo "  $0 capsule-deploy.duckdns.org"
    echo "  $0 3.87.27.213 --quick     # Fast check only"
    echo ""
    echo "This script tests external HTTP accessibility without requiring SSH."
    exit 1
fi

TARGET="$1"
QUICK_MODE=false

if [ "${2:-}" = "--quick" ]; then
    QUICK_MODE=true
fi

echo "=== Remote HTTP Verification ==="
echo "Target: $TARGET"
echo ""

# Test 1: HTTP Root Path
echo "--- HTTP Access Tests ---"
ROOT_CONTENT=$(curl -f -s -L --max-time 10 "http://$TARGET/" 2>&1 || true)
if echo "$ROOT_CONTENT" | grep -q "Capsule Cloud"; then
    test_pass "Root path (/) serving Capsule Cloud portal"
else
    if echo "$ROOT_CONTENT" | grep -q "curl:"; then
        test_fail "Root path (/) NOT accessible via HTTP"
        echo "   → Check: Security group may not allow port 80"
        echo "   → Check: Service may not be running"
    else
        test_fail "Root path (/) accessible but NOT serving portal"
        echo "   → Found: $(echo "$ROOT_CONTENT" | grep -o '<title>.*</title>' | head -1 || echo 'Wrong content')"
        echo "   → Expected: Capsule Cloud portal content"
    fi
fi

# Test 2: HTTP Deploy Path
DEPLOY_CONTENT=$(curl -f -s -L --max-time 10 "http://$TARGET/deploy/" 2>&1 || true)
if echo "$DEPLOY_CONTENT" | grep -q "Capsule Cloud"; then
    test_pass "Deploy path (/deploy/) serving portal content"
else
    if echo "$DEPLOY_CONTENT" | grep -q "curl:"; then
        test_fail "Deploy path (/deploy/) NOT accessible via HTTP"
    else
        test_fail "Deploy path (/deploy/) accessible but NOT serving portal"
        echo "   → Found: $(echo "$DEPLOY_CONTENT" | head -1 | cut -c1-80)"
    fi
fi

# Test 3: API Endpoint
if curl -f -s --max-time 10 "http://$TARGET/api/instance-metadata" > /dev/null 2>&1; then
    test_pass "API endpoint (/api/instance-metadata) accessible"
else
    test_fail "API endpoint NOT accessible"
fi

# Test 4: HTTPS
echo ""
echo "--- HTTPS Access Tests ---"
if curl -f -s --max-time 10 "https://$TARGET/" > /dev/null 2>&1; then
    test_pass "HTTPS root path accessible"
else
    test_warn "HTTPS NOT accessible (may not be configured)"
fi

if [ "$QUICK_MODE" = false ]; then
    # Test 5: Response Time
    echo ""
    echo "--- Performance Tests ---"
    START_TIME=$(date +%s%N)
    if curl -s --max-time 5 "http://$TARGET/" > /dev/null 2>&1; then
        END_TIME=$(date +%s%N)
        DURATION=$(( (END_TIME - START_TIME) / 1000000 ))

        if [ $DURATION -lt 1000 ]; then
            test_pass "Response time: ${DURATION}ms (excellent)"
        elif [ $DURATION -lt 3000 ]; then
            test_pass "Response time: ${DURATION}ms (good)"
        else
            test_warn "Response time: ${DURATION}ms (slow)"
        fi
    else
        test_warn "Could not measure response time"
    fi

    # Test 6: Check HTTP headers
    echo ""
    echo "--- Server Information ---"
    HEADERS=$(curl -I -s --max-time 5 "http://$TARGET/" 2>&1)

    if echo "$HEADERS" | grep -q "Server:"; then
        SERVER=$(echo "$HEADERS" | grep "Server:" | cut -d' ' -f2-)
        echo "Server: $SERVER"
    fi

    if echo "$HEADERS" | grep -q "HTTP/"; then
        STATUS=$(echo "$HEADERS" | head -1)
        echo "Status: $STATUS"
    fi
fi

# Summary
echo ""
echo "=== Verification Summary ==="
echo -e "${GREEN}Passed:${NC} $PASS"
echo -e "${RED}Failed:${NC} $FAIL"
echo -e "${YELLOW}Warnings:${NC} $WARN"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}✓ Remote instance is accessible!${NC}"
    echo ""
    echo "Access URLs:"
    echo "  → http://$TARGET/"
    echo "  → http://$TARGET/deploy/"
    exit 0
else
    echo -e "${RED}✗ Remote instance has accessibility issues.${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "1. Verify security group allows port 80 from your IP"
    echo "2. Check if service is running on target instance"
    echo "3. SSH to target and run: ./scripts/verify-deployment-local.sh"
    exit 1
fi
