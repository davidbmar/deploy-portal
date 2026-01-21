#!/bin/bash
#
# Enforce AppArmor Profiles
# Switch profiles from complain mode to enforce mode after validation
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${YELLOW}=== Enforcing AppArmor Profiles ===${NC}\n"

# Check if AppArmor is running
if ! sudo systemctl is-active --quiet apparmor; then
    echo -e "${RED}Error: AppArmor service not running${NC}"
    exit 1
fi

# List of profiles to enforce
profiles=(
    "oauth2-proxy"
    "deploy-portal"
    "ssh-helper"
    "website-cloner"
    "usr.sbin.nginx"
)

echo -e "${YELLOW}This will switch profiles from complain mode to enforce mode.${NC}"
echo -e "${YELLOW}Make sure you have monitored for violations first!${NC}"
echo ""
read -p "Continue? (yes/no): " confirm

if [ "${confirm}" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo -e "${GREEN}Enforcing profiles:${NC}"

for profile in "${profiles[@]}"; do
    echo -n "  - ${profile}: "

    if [ -f "/etc/apparmor.d/${profile}" ]; then
        # Switch to enforce mode
        if sudo aa-enforce "/etc/apparmor.d/${profile}" 2>/dev/null; then
            echo -e "${GREEN}✓ enforced${NC}"
        else
            echo -e "${RED}✗ error${NC}"
        fi
    else
        echo -e "${RED}✗ profile file not found${NC}"
    fi
done

echo ""

# Reload profiles
echo -e "${YELLOW}Reloading AppArmor profiles...${NC}"
sudo systemctl reload apparmor

echo ""

# Show current status
echo -e "${YELLOW}=== Current AppArmor Status ===${NC}"
sudo aa-status | head -n 30

echo ""
echo -e "${GREEN}=== Profiles enforced ===${NC}"
echo -e "${YELLOW}Monitor for denials with:${NC}"
echo "  sudo ausearch -m AVC -ts recent"
echo "  sudo journalctl -xe | grep DENIED"
echo ""
echo -e "${YELLOW}To disable a profile if issues occur:${NC}"
echo "  sudo aa-disable /etc/apparmor.d/<profile-name>"
echo ""
echo -e "${YELLOW}To switch back to complain mode:${NC}"
echo "  sudo aa-complain /etc/apparmor.d/<profile-name>"
