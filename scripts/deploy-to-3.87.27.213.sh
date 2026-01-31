#!/bin/bash
# Quick deployment script for 3.87.27.213
# This script should be run ON the target instance (3.87.27.213)
# or by someone with SSH access to it

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deploy Portal Update for 3.87.27.213${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if we're on the right instance
CURRENT_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "unknown")
if [ "$CURRENT_IP" = "3.87.27.213" ]; then
    echo -e "${GREEN}✓ Running on correct instance (3.87.27.213)${NC}"
elif [ "$CURRENT_IP" = "unknown" ]; then
    echo -e "${YELLOW}⚠ Cannot verify instance (not on EC2 or metadata unavailable)${NC}"
    echo "Continue anyway? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo -e "${RED}✗ Wrong instance! This is $CURRENT_IP, not 3.87.27.213${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}This will:${NC}"
echo "  1. Pull latest code from GitHub"
echo "  2. Run bootstrap.sh to fix configurations"
echo "  3. Restart deploy-portal service"
echo "  4. Run comprehensive verification"
echo ""
echo -e "${YELLOW}Continue? (y/N)${NC}"
read -r response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled"
    exit 0
fi

echo ""
echo -e "${BLUE}Step 1: Navigating to deploy-portal directory${NC}"
cd /home/ubuntu/src/deploy-portal || {
    echo -e "${RED}✗ Directory not found: /home/ubuntu/src/deploy-portal${NC}"
    exit 1
}
echo -e "${GREEN}✓ In deploy-portal directory${NC}"

echo ""
echo -e "${BLUE}Step 2: Stashing any local changes${NC}"
git stash
echo -e "${GREEN}✓ Local changes stashed${NC}"

echo ""
echo -e "${BLUE}Step 3: Pulling latest code from GitHub${NC}"
git pull origin main
echo -e "${GREEN}✓ Latest code pulled${NC}"

echo ""
echo -e "${BLUE}Step 4: Running bootstrap.sh${NC}"
./bootstrap.sh
BOOTSTRAP_EXIT=$?

if [ $BOOTSTRAP_EXIT -eq 0 ]; then
    echo -e "${GREEN}✓ Bootstrap completed successfully${NC}"
else
    echo -e "${YELLOW}⚠ Bootstrap completed with warnings (exit code: $BOOTSTRAP_EXIT)${NC}"
fi

echo ""
echo -e "${BLUE}Step 5: Running comprehensive verification${NC}"
./scripts/verify-deployment-local.sh
VERIFY_EXIT=$?

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Deployment Summary${NC}"
echo -e "${BLUE}========================================${NC}"

if [ $VERIFY_EXIT -eq 0 ]; then
    echo -e "${GREEN}✓ Deployment successful!${NC}"
    echo ""
    echo "Deploy portal is now running with the latest fixes:"
    echo "  ✓ Auth-gateway conflicts resolved"
    echo "  ✓ Health check endpoint available"
    echo "  ✓ Nginx configured correctly"
    echo "  ✓ Service running properly"
    echo ""
    echo "Access the portal at:"
    echo "  → http://3.87.27.213/"
    echo "  → http://3.87.27.213/deploy/"
    echo "  → http://3.87.27.213/health (no auth)"
else
    echo -e "${YELLOW}⚠ Deployment completed but some verification checks failed${NC}"
    echo ""
    echo "Review the verification output above for details."
    echo "Common issues:"
    echo "  - OAuth2 authentication may require configuration"
    echo "  - Security group may need port 80 opened"
    echo "  - Some services may still be starting up"
    echo ""
    echo "To re-run verification:"
    echo "  ./scripts/verify-deployment-local.sh"
fi

echo ""
echo -e "${BLUE}To verify from remote instance:${NC}"
echo "  ./scripts/remote-http-verify.sh 3.87.27.213"
echo ""
