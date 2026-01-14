#!/bin/bash

# Deployment Script for Remote EC2 Instance
# Usage: ./deploy-to-remote.sh <path-to-pem-file>
#
# Example: ./deploy-to-remote.sh ~/Downloads/eric-john-key-2026-01-08.pem

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
REMOTE_HOST="ec2-44-248-103-166.us-west-2.compute.amazonaws.com"
REMOTE_USER="ubuntu"
PEM_FILE="$1"

# Cognito Configuration (UPDATE THESE VALUES)
COGNITO_USER_POOL_ID="us-east-1_aVHSg58BS"
COGNITO_CLIENT_ID="46gdd9glnaetl44e2mtap51bkk"
COGNITO_CLIENT_SECRET="YOUR_SECRET_HERE"  # REPLACE WITH ACTUAL SECRET
COGNITO_REGION="us-east-1"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Remote EC2 Deployment Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if PEM file provided
if [ -z "$PEM_FILE" ]; then
    echo -e "${RED}Error: PEM file not specified${NC}"
    echo "Usage: $0 <path-to-pem-file>"
    echo "Example: $0 ~/Downloads/eric-john-key-2026-01-08.pem"
    exit 1
fi

# Check if PEM file exists
if [ ! -f "$PEM_FILE" ]; then
    echo -e "${RED}Error: PEM file not found: $PEM_FILE${NC}"
    exit 1
fi

# Set correct permissions on PEM file
chmod 400 "$PEM_FILE"

echo -e "${YELLOW}Target: $REMOTE_USER@$REMOTE_HOST${NC}"
echo -e "${YELLOW}PEM File: $PEM_FILE${NC}"
echo ""

# Function to run commands on remote server
run_remote() {
    ssh -i "$PEM_FILE" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "$@"
}

# Function to copy files to remote server
copy_to_remote() {
    scp -i "$PEM_FILE" -o StrictHostKeyChecking=no "$@" "$REMOTE_USER@$REMOTE_HOST":
}

echo -e "${GREEN}Step 1: Testing SSH connection...${NC}"
if run_remote "echo 'Connection successful'"; then
    echo -e "${GREEN}✅ SSH connection successful${NC}"
else
    echo -e "${RED}❌ SSH connection failed${NC}"
    exit 1
fi
echo ""

echo -e "${GREEN}Step 2: Getting remote instance IP...${NC}"
REMOTE_IP=$(run_remote "curl -s http://169.254.169.254/latest/meta-data/public-ipv4")
echo -e "${GREEN}Remote IP: $REMOTE_IP${NC}"
echo ""

echo -e "${GREEN}Step 3: Installing system dependencies...${NC}"
run_remote "sudo apt-get update && sudo apt-get install -y git curl nginx python3 python3-pip python3-venv nodejs npm"
echo -e "${GREEN}✅ System dependencies installed${NC}"
echo ""

echo -e "${GREEN}Step 4: Creating project directory...${NC}"
run_remote "mkdir -p /home/ubuntu/src"
echo ""

echo -e "${GREEN}Step 5: Cloning repositories...${NC}"
run_remote "cd /home/ubuntu/src && \
    git clone https://github.com/davidbmar/easy-cognito-nginx-gateway-auth-.git easy-cognito-nginx-gateway-auth 2>/dev/null || (cd easy-cognito-nginx-gateway-auth && git pull) && \
    git clone https://github.com/davidbmar/deploy-portal.git 2>/dev/null || (cd deploy-portal && git pull) && \
    git clone https://github.com/davidbmar/ssh-helper.git 2>/dev/null || (cd ssh-helper && git pull) && \
    git clone https://github.com/davidbmar/website-cloner.git 2>/dev/null || (cd website-cloner && git pull)"
echo -e "${GREEN}✅ Repositories cloned${NC}"
echo ""

echo -e "${GREEN}Step 6: Deploying Authentication Gateway...${NC}"
run_remote "cd /home/ubuntu/src/easy-cognito-nginx-gateway-auth && \
    sudo ./scripts/install.sh \
        --domain=$REMOTE_IP \
        --cognito-pool-id=$COGNITO_USER_POOL_ID \
        --cognito-client-id=$COGNITO_CLIENT_ID \
        --cognito-client-secret=$COGNITO_CLIENT_SECRET"
echo -e "${GREEN}✅ Authentication gateway deployed${NC}"
echo ""

echo -e "${GREEN}Step 7: Updating AWS Cognito callback URLs...${NC}"
echo "Updating Cognito with callback URL: https://$REMOTE_IP/oauth2/callback"
aws cognito-idp update-user-pool-client \
    --user-pool-id "$COGNITO_USER_POOL_ID" \
    --client-id "$COGNITO_CLIENT_ID" \
    --callback-urls "https://$REMOTE_IP/oauth2/callback" \
    --logout-urls "https://$REMOTE_IP/" \
    --region "$COGNITO_REGION" || echo -e "${YELLOW}⚠️  Warning: Cognito update failed (run manually if needed)${NC}"
echo ""

echo -e "${GREEN}Step 8: Deploying SSH Helper...${NC}"
run_remote "cd /home/ubuntu/src/ssh-helper && npm install"

run_remote "sudo tee /etc/systemd/system/ssh-helper.service > /dev/null << 'EOF'
[Unit]
Description=SSH Helper Web Terminal
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/src/ssh-helper
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment=NODE_ENV=production
Environment=PORT=8080

[Install]
WantedBy=multi-user.target
EOF"

run_remote "sudo systemctl daemon-reload && \
    sudo systemctl enable ssh-helper && \
    sudo systemctl start ssh-helper"
echo -e "${GREEN}✅ SSH Helper deployed${NC}"
echo ""

echo -e "${GREEN}Step 9: Deploying Deploy Portal...${NC}"
run_remote "cd /home/ubuntu/src/deploy-portal && \
    python3 -m venv venv && \
    source venv/bin/activate && \
    pip install -r requirements.txt"

run_remote "sudo tee /etc/systemd/system/deploy-portal.service > /dev/null << 'EOF'
[Unit]
Description=Deploy Portal
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/src/deploy-portal
Environment=PATH=/home/ubuntu/src/deploy-portal/venv/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/home/ubuntu/src/deploy-portal/venv/bin/python app.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF"

run_remote "sudo systemctl daemon-reload && \
    sudo systemctl enable deploy-portal && \
    sudo systemctl start deploy-portal"
echo -e "${GREEN}✅ Deploy Portal deployed${NC}"
echo ""

echo -e "${GREEN}Step 10: Deploying Website Cloner...${NC}"
run_remote "cd /home/ubuntu/src/website-cloner && npm install"

run_remote "sudo tee /etc/systemd/system/website-cloner.service > /dev/null << 'EOF'
[Unit]
Description=Website Cloner Web UI
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/src/website-cloner
ExecStart=/usr/bin/npm run ui
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF"

run_remote "sudo systemctl daemon-reload && \
    sudo systemctl enable website-cloner && \
    sudo systemctl start website-cloner"
echo -e "${GREEN}✅ Website Cloner deployed${NC}"
echo ""

echo -e "${GREEN}Step 11: Verifying all services...${NC}"
echo ""
echo "Service Status:"
run_remote "systemctl is-active nginx && echo '  nginx: ✅ Active' || echo '  nginx: ❌ Inactive'"
run_remote "systemctl is-active oauth2-proxy && echo '  oauth2-proxy: ✅ Active' || echo '  oauth2-proxy: ❌ Inactive'"
run_remote "systemctl is-active ssh-helper && echo '  ssh-helper: ✅ Active' || echo '  ssh-helper: ❌ Inactive'"
run_remote "systemctl is-active deploy-portal && echo '  deploy-portal: ✅ Active' || echo '  deploy-portal: ❌ Inactive'"
run_remote "systemctl is-active website-cloner && echo '  website-cloner: ✅ Active' || echo '  website-cloner: ❌ Inactive'"
echo ""

echo "Listening Ports:"
run_remote "sudo ss -tlnp | grep -E ':(443|4180|5000|8080|3000)' | awk '{print \"  \" \$4}'"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Access URLs:${NC}"
echo -e "  Gateway:        https://$REMOTE_IP/"
echo -e "  SSH Helper:     https://$REMOTE_IP/    (default root path)"
echo -e "  Website Cloner: https://$REMOTE_IP/cloner/"
echo -e "  Health Check:   https://$REMOTE_IP/health"
echo ""
echo -e "${YELLOW}Important Notes:${NC}"
echo -e "  - Using self-signed SSL certificate (browser will show warning)"
echo -e "  - First visit will redirect to AWS Cognito login"
echo -e "  - All services configured to auto-start on boot"
echo ""
echo -e "${YELLOW}Post-Deployment Tasks:${NC}"
echo -e "  1. Test authentication: Open https://$REMOTE_IP/ in browser"
echo -e "  2. Optional: Configure Let's Encrypt for production SSL"
echo -e "  3. Optional: Allocate Elastic IP to prevent IP changes"
echo ""
echo -e "${GREEN}Deployment successful! 🚀${NC}"
