#!/bin/bash
# Guide to running inject-seccomp.sh safely

echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║           How to Run inject-seccomp.sh on All Containers             ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""

echo "STEP 1: Check what will be affected"
echo "────────────────────────────────────────────────────────────────────────"
echo "Command:"
echo "  find /home/ubuntu/deployments -name 'docker-compose.yml' -type f"
echo ""
echo "Current result: (none - you have 0 containers)"
echo ""

echo "STEP 2: Run the script (interactive)"
echo "────────────────────────────────────────────────────────────────────────"
echo "Command:"
echo "  cd /home/ubuntu/src/deploy-portal"
echo "  bash security/inject-seccomp.sh"
echo ""
echo "What happens:"
echo "  1. Script finds all docker-compose.yml files"
echo "  2. For EACH file:"
echo "     - Shows you the app name"
echo "     - Creates backup: docker-compose.yml.backup-TIMESTAMP"
echo "     - Adds security options"
echo "     - Asks: 'Recreate containers for app-name? (y/n):'"
echo "     - YOU DECIDE: Press 'y' to restart, 'n' to skip"
echo ""

echo "STEP 3: Example interaction"
echo "────────────────────────────────────────────────────────────────────────"
cat << 'EXAMPLE'

Processing: my-app-01
  File: /home/ubuntu/deployments/my-app-01/docker-compose.yml
  ✓ Backup created: docker-compose.yml.backup-20260119-050000
  Adding security options...
    - Service: app
      ✓ Security options added
  ✓ Updated successfully
  Recreate containers for my-app-01? (y/n): y    ← YOU TYPE 'y'
  Recreating containers...
  ✓ Containers recreated

EXAMPLE

echo ""
echo "STEP 4: If something goes wrong (unlikely)"
echo "────────────────────────────────────────────────────────────────────────"
echo "The script auto-restores backup if container fails to start"
echo ""
echo "Manual restore:"
echo "  cd /home/ubuntu/deployments/my-app-01"
echo "  cp docker-compose.yml.backup-TIMESTAMP docker-compose.yml"
echo "  docker-compose up -d"
echo ""

echo "STEP 5: Verify everything works"
echo "────────────────────────────────────────────────────────────────────────"
echo "After running script:"
echo "  docker ps                    # Check all containers running"
echo "  curl http://localhost:PORT   # Test each app"
echo ""

echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║                         CURRENT STATUS                                ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "You have: 0 containers"
echo "Action needed: NONE right now"
echo ""
echo "Run this script AFTER users deploy apps with the deploy kit"
echo ""
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║                      WHEN TO RUN THIS                                 ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Scenario 1: You have existing containers NOW"
echo "  → Run: bash /home/ubuntu/src/deploy-portal/security/inject-seccomp.sh"
echo "  → Time: 10-15 minutes for 26 apps"
echo "  → When: Maintenance window"
echo ""
echo "Scenario 2: Users will deploy apps LATER"
echo "  → Wait until after first deployment"
echo "  → Then run script on those containers"
echo "  → OR integrate into deploy-app.sh (better long-term)"
echo ""
echo "Scenario 3: You want to test FIRST"
echo "  → Deploy 1 test app"
echo "  → Run script on just that app"
echo "  → Verify it works"
echo "  → Then run on remaining apps"
echo ""

