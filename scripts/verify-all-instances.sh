#!/bin/bash
# Verify multiple instances at once
# Useful for checking all your deployments

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=== Multi-Instance Verification ==="
echo ""

# Check if instances file exists
INSTANCES_FILE="${1:-$SCRIPT_DIR/../data/instances.txt}"

if [ ! -f "$INSTANCES_FILE" ]; then
    echo -e "${YELLOW}No instances file found at: $INSTANCES_FILE${NC}"
    echo ""
    echo "Create a file with one instance per line:"
    echo "  3.87.27.213"
    echo "  16.148.110.90"
    echo "  capsule-deploy.duckdns.org"
    echo ""
    echo "Usage:"
    echo "  $0 [instances-file]"
    echo ""
    echo "Example:"
    echo "  echo '3.87.27.213' > instances.txt"
    echo "  echo '16.148.110.90' >> instances.txt"
    echo "  $0 instances.txt"
    exit 1
fi

# Read instances
INSTANCES=()
while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    if [[ -n "$line" ]] && [[ ! "$line" =~ ^# ]]; then
        INSTANCES+=("$line")
    fi
done < "$INSTANCES_FILE"

if [ ${#INSTANCES[@]} -eq 0 ]; then
    echo -e "${RED}No instances found in file${NC}"
    exit 1
fi

echo "Found ${#INSTANCES[@]} instances to verify"
echo ""

# Track results
TOTAL=0
HEALTHY=0
UNHEALTHY=0

# Test each instance
for instance in "${INSTANCES[@]}"; do
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Testing: $instance${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    ((TOTAL++))

    # Quick HTTP test with content verification
    ROOT_CONTENT=$(curl -f -s -L --max-time 5 "http://$instance/" 2>&1 || true)
    if echo "$ROOT_CONTENT" | grep -q "Capsule Cloud"; then
        echo -e "${GREEN}✓ HTTP accessible and serving portal${NC}"

        # Test deploy path
        DEPLOY_CONTENT=$(curl -f -s -L --max-time 5 "http://$instance/deploy/" 2>&1 || true)
        if echo "$DEPLOY_CONTENT" | grep -q "Capsule Cloud"; then
            echo -e "${GREEN}✓ Deploy page serving portal content${NC}"
        else
            echo -e "${YELLOW}⚠ Deploy page NOT serving portal content${NC}"
        fi

        # Test API
        if curl -f -s --max-time 5 "http://$instance/api/instance-metadata" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ API accessible${NC}"
        else
            echo -e "${YELLOW}⚠ API NOT accessible${NC}"
        fi

        ((HEALTHY++))
        echo -e "${GREEN}Status: HEALTHY${NC}"
    else
        if echo "$ROOT_CONTENT" | grep -q "curl:"; then
            echo -e "${RED}✗ HTTP NOT accessible${NC}"
        else
            echo -e "${RED}✗ HTTP accessible but NOT serving portal${NC}"
            echo -e "   Found: $(echo "$ROOT_CONTENT" | head -1 | cut -c1-60)..."
        fi
        echo -e "${RED}Status: UNHEALTHY${NC}"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Check security group for $instance"
        echo "  2. Verify service is running: ssh ubuntu@$instance 'systemctl status deploy-portal'"
        echo "  3. Run local verification: ssh ubuntu@$instance 'cd /home/ubuntu/src/deploy-portal && ./scripts/verify-deployment-local.sh'"
        ((UNHEALTHY++))
    fi

    echo ""
done

# Final summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Total instances: $TOTAL"
echo -e "${GREEN}Healthy: $HEALTHY${NC}"
echo -e "${RED}Unhealthy: $UNHEALTHY${NC}"
echo ""

if [ $UNHEALTHY -eq 0 ]; then
    echo -e "${GREEN}✓ All instances are healthy!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some instances are unhealthy${NC}"
    exit 1
fi
