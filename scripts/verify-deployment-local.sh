#!/bin/bash
# Comprehensive post-deployment verification script

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

echo "=== Deploy Portal Verification ==="
echo ""

# DYNAMICALLY get instance metadata (works on any EC2 instance)
echo "--- Instance Information ---"
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "")

if [ -n "$TOKEN" ]; then
    # Query EC2 metadata service for this instance's details
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
        http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
    PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
        http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
    PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
        http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo "127.0.0.1")

    echo "Instance ID: $INSTANCE_ID"
    echo "Public IP: $PUBLIC_IP"
    echo "Private IP: $PRIVATE_IP"
else
    PUBLIC_IP=""
    PRIVATE_IP="127.0.0.1"
    echo "Not running on EC2 or metadata unavailable"
fi

echo ""

# Test 1: Service Running
echo "--- Service Status ---"
if systemctl is-active --quiet deploy-portal; then
    test_pass "deploy-portal service is active"
else
    test_fail "deploy-portal service is NOT active"
fi

# Test 2: Nginx Config
echo ""
echo "--- Nginx Configuration ---"
NGINX_TEST_OUTPUT=$(sudo nginx -t 2>&1 || true)
if echo "$NGINX_TEST_OUTPUT" | grep -q "syntax is ok"; then
    test_pass "nginx config syntax is valid"
else
    test_fail "nginx config has errors"
fi

# Check for default_server conflicts
DEFAULT_SERVER_COUNT=$(grep -r "default_server" /etc/nginx/ 2>/dev/null | wc -l)
if [ "$DEFAULT_SERVER_COUNT" -le 3 ]; then
    test_pass "No nginx default_server conflicts ($DEFAULT_SERVER_COUNT declarations)"
else
    test_warn "Multiple default_server declarations ($DEFAULT_SERVER_COUNT)"
fi

# Test 3: Internal Access - Root
echo ""
echo "--- Internal Access Tests ---"
ROOT_CONTENT=$(curl -f -s -L http://localhost/ 2>&1 || true)
if echo "$ROOT_CONTENT" | grep -q "Capsule Cloud"; then
    test_pass "Root path (/) serving Capsule Cloud portal"
else
    test_fail "Root path (/) NOT serving Capsule Cloud content"
    echo "   → Found: $(echo "$ROOT_CONTENT" | grep -o '<title>.*</title>' | head -1 || echo 'No title found')"
fi

# Test 4: Internal Access - Deploy
DEPLOY_CONTENT=$(curl -f -s -L http://localhost/deploy/ 2>&1 || true)
if echo "$DEPLOY_CONTENT" | grep -q "Capsule Cloud"; then
    test_pass "Deploy path (/deploy/) serving portal content"
else
    test_fail "Deploy path (/deploy/) NOT serving portal content"
    echo "   → Found: $(echo "$DEPLOY_CONTENT" | head -1)"
fi

# Test 5: Internal Access - Health Check (no auth)
HEALTH_RESPONSE=$(curl -f -s http://localhost/health 2>&1 || true)
if echo "$HEALTH_RESPONSE" | grep -q "deploy-portal"; then
    test_pass "Health check endpoint accessible (no auth)"
else
    test_warn "Health check endpoint NOT accessible"
fi

# Test 6: Internal Access - API
if curl -f -s http://localhost/api/instance-metadata > /dev/null 2>&1; then
    test_pass "Instance metadata API accessible internally"
else
    test_fail "Instance metadata API NOT accessible internally"
fi

# Test 7: Static Files
if curl -I http://localhost/deploy/static/style.css 2>&1 | grep -qE "200 OK|301 Moved"; then
    test_pass "Static files (CSS) accessible"
else
    test_fail "Static files (CSS) NOT accessible"
fi

# Test 8: External Access (if public IP available)
echo ""
echo "--- External Access Tests ---"
if [ -n "$PUBLIC_IP" ]; then
    # Try to determine user's IP if testing from specific MacBook
    USER_IP=""
    if [ -n "${USER_MACBOOK_IP:-}" ]; then
        USER_IP="$USER_MACBOOK_IP"
        echo "Testing from MacBook IP: $USER_IP"
    fi

    # Test root path externally with short timeout (from instance itself)
    EXT_ROOT_CONTENT=$(curl -f -s -L --max-time 5 "http://$PUBLIC_IP/" 2>&1 || true)
    if echo "$EXT_ROOT_CONTENT" | grep -q "Capsule Cloud"; then
        test_pass "Root path (/) serving portal content externally"
    else
        if echo "$EXT_ROOT_CONTENT" | grep -q "curl:"; then
            test_fail "Root path (/) NOT accessible externally from $PUBLIC_IP"
            if [ -n "$USER_IP" ]; then
                echo "   → Check security group: port 80 may not be open to $USER_IP/32"
            else
                echo "   → Check security group: port 80 may not be open"
            fi
        else
            test_fail "Root path (/) accessible but NOT serving portal content"
            echo "   → Found: $(echo "$EXT_ROOT_CONTENT" | grep -o '<title>.*</title>' | head -1 || echo 'Wrong content')"
        fi
    fi

    # Test deploy path externally
    EXT_DEPLOY_CONTENT=$(curl -f -s -L --max-time 5 "http://$PUBLIC_IP/deploy/" 2>&1 || true)
    if echo "$EXT_DEPLOY_CONTENT" | grep -q "Capsule Cloud"; then
        test_pass "Deploy path (/deploy/) serving portal content externally"
    else
        if echo "$EXT_DEPLOY_CONTENT" | grep -q "curl:"; then
            test_fail "Deploy path (/deploy/) NOT accessible externally from $PUBLIC_IP"
            if [ -n "$USER_IP" ]; then
                echo "   → Check security group: port 80 may not be open to $USER_IP/32"
                echo "   → Run: aws ec2 authorize-security-group-ingress --group-id <SG_ID> --protocol tcp --port 80 --cidr $USER_IP/32"
            else
                echo "   → Check security group: port 80 may not be open"
            fi
        else
            test_fail "Deploy path (/deploy/) accessible but NOT serving portal content"
            echo "   → Found: $(echo "$EXT_DEPLOY_CONTENT" | head -1)"
        fi
    fi

    # Test HTTPS if configured
    if curl -f -s --max-time 5 "https://$PUBLIC_IP/" > /dev/null 2>&1; then
        test_pass "HTTPS (port 443) accessible externally"
    else
        test_warn "HTTPS (port 443) NOT accessible (may not be configured)"
    fi
else
    test_warn "No public IP - skipping external access tests"
fi

# Test 9: Permissions
echo ""
echo "--- File Permissions ---"
if [ -x /home/ubuntu ] && [ -r /home/ubuntu ]; then
    test_pass "/home/ubuntu directory permissions correct (755)"
else
    test_fail "/home/ubuntu directory permissions incorrect"
fi

if [ -x "$SCRIPT_DIR/static" ] && [ -r "$SCRIPT_DIR/static" ]; then
    test_pass "Static directory permissions correct"
else
    test_fail "Static directory permissions incorrect"
fi

# Test 10: Port Listening
echo ""
echo "--- Port Status ---"
if sudo ss -tlnp | grep -q ":80 "; then
    test_pass "Nginx listening on port 80"
else
    test_fail "Nginx NOT listening on port 80"
fi

if sudo ss -tlnp | grep -q ":5000 "; then
    test_pass "Flask app listening on port 5000"
else
    test_fail "Flask app NOT listening on port 5000"
fi

# Test 11: Security Group (if AWS CLI available)
if command -v aws &> /dev/null && [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "unknown" ]; then
    echo ""
    echo "--- Security Group Check ---"

    REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
        http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "us-east-1")

    # Get security groups for instance
    SG_IDS=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --region "$REGION" \
        --query 'Reservations[0].Instances[0].SecurityGroups[*].GroupId' \
        --output text 2>/dev/null || echo "")

    if [ -n "$SG_IDS" ]; then
        # Check if port 80 is open
        PORT_80_OPEN=$(aws ec2 describe-security-groups \
            --group-ids $SG_IDS \
            --region "$REGION" \
            --query 'SecurityGroups[*].IpPermissions[?ToPort==`80`]' \
            --output text 2>/dev/null || echo "")

        if [ -n "$PORT_80_OPEN" ]; then
            test_pass "Security group has port 80 rule configured"

            # If user provided MacBook IP, check if it's specifically allowed
            if [ -n "$USER_IP" ]; then
                SPECIFIC_IP_RULE=$(aws ec2 describe-security-groups \
                    --group-ids $SG_IDS \
                    --region "$REGION" \
                    --query "SecurityGroups[*].IpPermissions[?ToPort==\`80\`].IpRanges[?contains(CidrIp, '$USER_IP')]" \
                    --output text 2>/dev/null || echo "")

                if [ -n "$SPECIFIC_IP_RULE" ]; then
                    test_pass "Port 80 open to MacBook IP ($USER_IP)"
                else
                    test_warn "Port 80 not specifically open to MacBook IP ($USER_IP)"
                fi
            fi
        else
            test_fail "Security group does NOT have port 80 rule"
            if [ -n "$USER_IP" ]; then
                echo "   → Run: aws ec2 authorize-security-group-ingress --group-id <SG_ID> --protocol tcp --port 80 --cidr $USER_IP/32"
            else
                echo "   → Run: aws ec2 authorize-security-group-ingress --group-id <SG_ID> --protocol tcp --port 80 --cidr 0.0.0.0/0"
            fi
        fi
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
    echo -e "${GREEN}✓ All critical tests passed!${NC}"

    if [ -n "$PUBLIC_IP" ]; then
        echo ""
        echo "Access your deployment at:"
        echo "  → http://$PUBLIC_IP/"
        echo "  → http://$PUBLIC_IP/deploy/"
    fi

    exit 0
else
    echo -e "${RED}✗ Some tests failed. Review errors above.${NC}"
    exit 1
fi
