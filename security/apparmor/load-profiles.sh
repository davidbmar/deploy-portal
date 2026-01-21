#!/bin/bash
#
# Load AppArmor Profiles in Complain Mode
# This script loads all security profiles in complain mode for monitoring
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILES_DIR="${SCRIPT_DIR}"

echo -e "${YELLOW}=== Loading AppArmor Profiles in Complain Mode ===${NC}\n"

# Check if AppArmor is installed and running
if ! command -v aa-status &> /dev/null; then
    echo -e "${RED}Error: AppArmor utilities not installed${NC}"
    echo "Install with: sudo apt-get install apparmor-utils"
    exit 1
fi

if ! sudo systemctl is-active --quiet apparmor; then
    echo -e "${YELLOW}Starting AppArmor service...${NC}"
    sudo systemctl enable apparmor
    sudo systemctl start apparmor
fi

# Copy profiles to /etc/apparmor.d/
echo -e "${GREEN}Copying profiles to /etc/apparmor.d/${NC}"
for profile in oauth2-proxy deploy-portal ssh-helper website-cloner usr.sbin.nginx; do
    if [ -f "${PROFILES_DIR}/${profile}" ]; then
        echo "  - ${profile}"
        sudo cp "${PROFILES_DIR}/${profile}" /etc/apparmor.d/
    fi
done

echo ""

# Load profiles in complain mode
echo -e "${GREEN}Loading profiles in complain mode:${NC}"

profiles=(
    "oauth2-proxy"
    "deploy-portal"
    "ssh-helper"
    "website-cloner"
    "usr.sbin.nginx"
)

for profile in "${profiles[@]}"; do
    echo -n "  - ${profile}: "

    # Parse the profile to get the actual profile name
    if [ -f "/etc/apparmor.d/${profile}" ]; then
        # Load in complain mode
        if sudo aa-complain "/etc/apparmor.d/${profile}" 2>/dev/null; then
            echo -e "${GREEN}✓ loaded (complain mode)${NC}"
        else
            echo -e "${YELLOW}⚠ already loaded or error${NC}"
        fi
    else
        echo -e "${RED}✗ profile file not found${NC}"
    fi
done

echo ""

# Show current status
echo -e "${YELLOW}=== Current AppArmor Status ===${NC}"
sudo aa-status | head -n 20

echo ""
echo -e "${GREEN}=== Profiles loaded in complain mode ===${NC}"
echo -e "${YELLOW}Monitor for 48 hours with:${NC}"
echo "  sudo ausearch -m AVC -ts recent"
echo "  sudo journalctl -xe | grep apparmor"
echo ""
echo -e "${YELLOW}After validation, switch to enforce mode with:${NC}"
echo "  bash ${SCRIPT_DIR}/enforce-profiles.sh"
