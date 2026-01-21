#!/bin/bash
#
# Install Security Monitoring
# Sets up cron job for continuous security monitoring
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_SCRIPT="$SCRIPT_DIR/security-monitor.sh"
CRON_SCHEDULE="*/15 * * * *"  # Every 15 minutes
LOG_FILE="/var/log/security-monitor.log"

echo -e "${YELLOW}=== Installing Security Monitoring ===${NC}\n"

# Check if monitor script exists
if [ ! -f "$MONITOR_SCRIPT" ]; then
    echo -e "${RED}Error: Monitor script not found: $MONITOR_SCRIPT${NC}"
    exit 1
fi

# Make script executable
chmod +x "$MONITOR_SCRIPT"
echo -e "${GREEN}✓ Monitor script is executable${NC}"

# Create log directory
sudo mkdir -p /var/log
sudo touch "$LOG_FILE"
sudo chown ubuntu:ubuntu "$LOG_FILE" 2>/dev/null || true
echo -e "${GREEN}✓ Log file created: $LOG_FILE${NC}"

# Add to crontab
echo -e "\n${YELLOW}Adding cron job...${NC}"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "security-monitor.sh"; then
    echo -e "${YELLOW}Cron job already exists, updating...${NC}"
    # Remove old entry
    crontab -l 2>/dev/null | grep -v "security-monitor.sh" | crontab - || true
fi

# Add new entry
(crontab -l 2>/dev/null || echo ""; echo "$CRON_SCHEDULE bash $MONITOR_SCRIPT >> $LOG_FILE 2>&1") | crontab -

echo -e "${GREEN}✓ Cron job added: $CRON_SCHEDULE${NC}"

# Verify cron job
echo -e "\n${YELLOW}Current crontab:${NC}"
crontab -l | grep "security-monitor"

# Run initial monitoring
echo -e "\n${YELLOW}Running initial security check...${NC}"
bash "$MONITOR_SCRIPT"

echo ""
echo -e "${GREEN}=== Monitoring Installation Complete ===${NC}"
echo ""
echo "Monitor script: $MONITOR_SCRIPT"
echo "Schedule:       Every 15 minutes"
echo "Log file:       $LOG_FILE"
echo ""
echo "View logs:      tail -f $LOG_FILE"
echo "Run manually:   bash $MONITOR_SCRIPT"
echo "Disable:        crontab -e (remove the line)"
echo ""
