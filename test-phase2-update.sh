#!/bin/bash
# Test Script: Verify Phase 2 Update Implementation
# This script verifies that the pure ZIP-based version management works correctly

set -e

echo "=========================================="
echo "Phase 2 Update Verification Test"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test 1: Verify skill file exists
echo "Test 1: Verify deploy-skill.yaml exists"
if [ -f "/home/ubuntu/src/deploy-portal/deploy-skill.yaml" ]; then
    echo -e "${GREEN}✅ PASS${NC}: deploy-skill.yaml exists"
else
    echo -e "${RED}❌ FAIL${NC}: deploy-skill.yaml not found"
    exit 1
fi
echo ""

# Test 2: Verify version placeholder
echo "Test 2: Verify version placeholder in skill"
if grep -q "^version: DEPLOYMENT_VERSION_PLACEHOLDER" /home/ubuntu/src/deploy-portal/deploy-skill.yaml; then
    echo -e "${GREEN}✅ PASS${NC}: Version placeholder found"
else
    echo -e "${RED}❌ FAIL${NC}: Version placeholder not found"
    exit 1
fi
echo ""

# Test 3: Verify Phase 2 header updated
echo "Test 3: Verify Phase 2 header is updated"
if grep -q "Phase 2: Skill Version Management (ZIP-Based Auto-Update)" /home/ubuntu/src/deploy-portal/deploy-skill.yaml; then
    echo -e "${GREEN}✅ PASS${NC}: Phase 2 header updated correctly"
else
    echo -e "${RED}❌ FAIL${NC}: Phase 2 header not updated"
    exit 1
fi
echo ""

# Test 4: Verify portal fallback removed
echo "Test 4: Verify portal version fallback removed"
if grep -q "Optional: Check Portal Version (Fallback)" /home/ubuntu/src/deploy-portal/deploy-skill.yaml; then
    echo -e "${RED}❌ FAIL${NC}: Portal fallback still present (should be removed)"
    exit 1
else
    echo -e "${GREEN}✅ PASS${NC}: Portal fallback removed"
fi
echo ""

# Test 5: Verify no portal API calls mentioned
echo "Test 5: Verify 'No portal API calls needed' message present"
if grep -q "No portal API calls needed" /home/ubuntu/src/deploy-portal/deploy-skill.yaml; then
    echo -e "${GREEN}✅ PASS${NC}: Correct messaging about portal API"
else
    echo -e "${RED}❌ FAIL${NC}: Missing portal API messaging"
    exit 1
fi
echo ""

# Test 6: Verify new Phase 2.4 (downgrade handling)
echo "Test 6: Verify Phase 2.4 downgrade handling added"
if grep -q "2.4 If ZIP Skill is Older" /home/ubuntu/src/deploy-portal/deploy-skill.yaml; then
    echo -e "${GREEN}✅ PASS${NC}: Phase 2.4 downgrade handling present"
else
    echo -e "${RED}❌ FAIL${NC}: Phase 2.4 downgrade handling missing"
    exit 1
fi
echo ""

# Test 7: Verify Phase 1.3 portal version check removed
echo "Test 7: Verify Phase 1.3 'Check Portal Version' removed"
if grep -q "1.3 Check Portal Version" /home/ubuntu/src/deploy-portal/deploy-skill.yaml; then
    echo -e "${RED}❌ FAIL${NC}: Phase 1.3 portal check still present"
    exit 1
else
    echo -e "${GREEN}✅ PASS${NC}: Phase 1.3 portal check removed"
fi
echo ""

# Test 8: Verify Active Sessions renumbered to 1.3
echo "Test 8: Verify Active Sessions renumbered to 1.3"
if grep -q "1.3 Check Active Sessions" /home/ubuntu/src/deploy-portal/deploy-skill.yaml; then
    echo -e "${GREEN}✅ PASS${NC}: Active Sessions correctly renumbered to 1.3"
else
    echo -e "${RED}❌ FAIL${NC}: Active Sessions not at 1.3"
    exit 1
fi
echo ""

# Test 9: Verify config.py has SKILL_FILE_PATH
echo "Test 9: Verify config.py has SKILL_FILE_PATH"
if grep -q 'SKILL_FILE_PATH = "deploy-skill.yaml"' /home/ubuntu/src/deploy-portal/config.py; then
    echo -e "${GREEN}✅ PASS${NC}: config.py has correct SKILL_FILE_PATH"
else
    echo -e "${RED}❌ FAIL${NC}: config.py missing SKILL_FILE_PATH"
    exit 1
fi
echo ""

# Test 10: Verify app.py includes skill in ZIP
echo "Test 10: Verify app.py includes skill in deployment ZIP"
if grep -q "zf.writestr(f\"{folder_name}/{Config.SKILL_FILE_PATH}\", skill_content)" /home/ubuntu/src/deploy-portal/app.py; then
    echo -e "${GREEN}✅ PASS${NC}: app.py includes skill in ZIP"
else
    echo -e "${RED}❌ FAIL${NC}: app.py doesn't include skill in ZIP"
    exit 1
fi
echo ""

# Test 11: Verify service is running
echo "Test 11: Verify deploy-portal service is running"
if systemctl is-active --quiet deploy-portal; then
    echo -e "${GREEN}✅ PASS${NC}: deploy-portal service is running"
    SERVICE_VERSION=$(curl -s http://localhost:5000/api/deployment/version | jq -r '.version')
    echo "   Service version: ${SERVICE_VERSION}"
else
    echo -e "${RED}❌ FAIL${NC}: deploy-portal service not running"
    exit 1
fi
echo ""

# Test 12: Verify API returns version
echo "Test 12: Verify API /api/deployment/version works"
VERSION_RESPONSE=$(curl -s http://localhost:5000/api/deployment/version)
if echo "$VERSION_RESPONSE" | jq -e '.version' > /dev/null 2>&1; then
    echo -e "${GREEN}✅ PASS${NC}: API returns version correctly"
    echo "   Response: $(echo "$VERSION_RESPONSE" | jq -c .)"
else
    echo -e "${RED}❌ FAIL${NC}: API version endpoint failed"
    exit 1
fi
echo ""

# Summary
echo "=========================================="
echo -e "${GREEN}✅ ALL TESTS PASSED!${NC}"
echo "=========================================="
echo ""
echo "Phase 2 Update Status: COMPLETE ✅"
echo ""
echo "Next Steps:"
echo "1. Generate a test deployment kit"
echo "2. Verify deploy-skill.yaml is included in ZIP"
echo "3. Test auto-update flow with older skill"
echo "4. Test offline deployment (no network)"
echo ""
echo "Key Changes:"
echo "  - ✅ Removed portal API version checking"
echo "  - ✅ Pure ZIP-based skill versioning"
echo "  - ✅ Added explicit downgrade handling"
echo "  - ✅ Simplified Phase 2 logic"
echo "  - ✅ Self-updating deployment kits"
echo ""
