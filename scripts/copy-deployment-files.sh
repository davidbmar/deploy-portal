#!/bin/bash
# Copy deployment files (config and SSH keys) to target server
# This script helps replicate AWS configuration to new servers

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Copy Deployment Files${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "This script copies AWS configuration and SSH keys to a target server"
echo ""

# Check if .ec2-config.env exists locally
if [ ! -f "$HOME/.ec2-config.env" ]; then
    echo -e "${RED}✗ Configuration file not found: $HOME/.ec2-config.env${NC}"
    echo ""
    echo "Create one first using:"
    echo "  bash scripts/configure-aws-config.sh"
    exit 1
fi

# Get target server details
read -p "Target host (IP or hostname): " TARGET_HOST
read -p "Target user [ubuntu]: " TARGET_USER
TARGET_USER=${TARGET_USER:-ubuntu}
read -p "SSH key path: " SSH_KEY_PATH
SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"

if [ ! -f "$SSH_KEY_PATH" ]; then
    echo -e "${RED}✗ SSH key not found: $SSH_KEY_PATH${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Target: $TARGET_USER@$TARGET_HOST${NC}"
echo ""

# Test SSH connection
echo "Testing SSH connection..."
if ! ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=5 "$TARGET_USER@$TARGET_HOST" "echo 'Connected'" &> /dev/null; then
    echo -e "${RED}✗ Cannot connect to $TARGET_HOST${NC}"
    exit 1
fi
echo -e "${GREEN}✓ SSH connection successful${NC}"
echo ""

# Get target server details for configuration update
echo -e "${BLUE}Target Server Configuration${NC}"
echo "Enter details for the target server (will update .ec2-config.env)"
echo ""

read -p "Target AWS Region [us-east-1]: " TARGET_REGION
TARGET_REGION=${TARGET_REGION:-us-east-1}

read -p "Target Security Group ID: " TARGET_SG
if [ -z "$TARGET_SG" ]; then
    echo -e "${RED}✗ Security Group ID is required${NC}"
    exit 1
fi

read -p "Target Public IP [$TARGET_HOST]: " TARGET_IP
TARGET_IP=${TARGET_IP:-$TARGET_HOST}

echo ""
echo -e "${GREEN}✓ Target Region: $TARGET_REGION${NC}"
echo -e "${GREEN}✓ Target Security Group: $TARGET_SG${NC}"
echo -e "${GREEN}✓ Target Public IP: $TARGET_IP${NC}"
echo ""

# Confirm
read -p "Proceed with file copy? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled"
    exit 0
fi
echo ""

# Create directories on target
echo -e "${BLUE}Creating directories on target...${NC}"
ssh -i "$SSH_KEY_PATH" "$TARGET_USER@$TARGET_HOST" "mkdir -p $HOME/.ssh $HOME/src/deploy-portal/keys"
echo -e "${GREEN}✓ Directories created${NC}"
echo ""

# Copy .ec2-config.env
echo -e "${BLUE}Copying configuration file...${NC}"
scp -i "$SSH_KEY_PATH" "$HOME/.ec2-config.env" "$TARGET_USER@$TARGET_HOST:$HOME/.ec2-config.env"
echo -e "${GREEN}✓ Configuration file copied${NC}"
echo ""

# Update configuration for target server
echo -e "${BLUE}Updating configuration for target server...${NC}"
ssh -i "$SSH_KEY_PATH" "$TARGET_USER@$TARGET_HOST" << ENDSSH
    # Update region
    sed -i 's|AWS_REGION=.*|AWS_REGION=$TARGET_REGION|' $HOME/.ec2-config.env

    # Update security group
    sed -i 's|SECURITY_GROUP_ID=.*|SECURITY_GROUP_ID=$TARGET_SG|' $HOME/.ec2-config.env

    # Update public IP
    sed -i 's|PUBLIC_IP=.*|PUBLIC_IP=$TARGET_IP|' $HOME/.ec2-config.env

    # Update SSH key path to the copied location
    sed -i 's|SSH_KEY_PATH=.*|SSH_KEY_PATH=$HOME/.ssh/deploy-key.pem|' $HOME/.ec2-config.env
    sed -i 's|SSH_KEY_NAME=.*|SSH_KEY_NAME=deploy-key|' $HOME/.ec2-config.env

    # Set permissions
    chmod 600 $HOME/.ec2-config.env
ENDSSH
echo -e "${GREEN}✓ Configuration updated for target${NC}"
echo ""

# Ask if user wants to copy SSH deployment key
echo -e "${BLUE}SSH Deployment Key${NC}"
echo "Do you want to copy an SSH key for deploying to other servers?"
read -p "Copy deployment key? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Find SSH key from local config
    source "$HOME/.ec2-config.env"

    if [ -n "$SSH_KEY_PATH" ] && [ -f "$SSH_KEY_PATH" ]; then
        LOCAL_KEY="$SSH_KEY_PATH"
    else
        read -p "Path to SSH deployment key: " LOCAL_KEY
        LOCAL_KEY="${LOCAL_KEY/#\~/$HOME}"
    fi

    if [ ! -f "$LOCAL_KEY" ]; then
        echo -e "${YELLOW}⚠ Key not found: $LOCAL_KEY${NC}"
        echo "Skipping key copy"
    else
        echo "Copying SSH key..."

        # Copy to .ssh directory
        scp -i "$SSH_KEY_PATH" "$LOCAL_KEY" "$TARGET_USER@$TARGET_HOST:$HOME/.ssh/deploy-key.pem"

        # Copy to deploy-portal keys directory
        scp -i "$SSH_KEY_PATH" "$LOCAL_KEY" "$TARGET_USER@$TARGET_HOST:$HOME/src/deploy-portal/keys/deploy-key.pem"

        # Set permissions
        ssh -i "$SSH_KEY_PATH" "$TARGET_USER@$TARGET_HOST" "chmod 400 $HOME/.ssh/deploy-key.pem $HOME/src/deploy-portal/keys/deploy-key.pem"

        echo -e "${GREEN}✓ SSH key copied and secured${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Skipping SSH key copy${NC}"
fi
echo ""

# Update systemd services on target
echo -e "${BLUE}Updating systemd services...${NC}"
ssh -i "$SSH_KEY_PATH" "$TARGET_USER@$TARGET_HOST" << 'ENDSSH'
    SERVICES=("deploy-portal" "ssh-helper")

    for SERVICE in "${SERVICES[@]}"; do
        SERVICE_FILE="/etc/systemd/system/${SERVICE}.service"

        if [ -f "$SERVICE_FILE" ]; then
            # Check if EnvironmentFile already exists
            if ! sudo grep -q "EnvironmentFile=" "$SERVICE_FILE"; then
                echo "Adding EnvironmentFile to $SERVICE.service"
                sudo sed -i '/\[Service\]/a EnvironmentFile=/home/ubuntu/.ec2-config.env' "$SERVICE_FILE"
            else
                echo "$SERVICE.service already has EnvironmentFile"
            fi
        else
            echo "⚠ $SERVICE_FILE not found, skipping"
        fi
    done

    # Reload systemd
    echo "Reloading systemd..."
    sudo systemctl daemon-reload

    # Restart services
    echo "Restarting services..."
    sudo systemctl restart deploy-portal ssh-helper 2>/dev/null || true
ENDSSH
echo -e "${GREEN}✓ Services updated and restarted${NC}"
echo ""

# Display verification commands
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Copy Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}✓ Configuration and keys copied to $TARGET_HOST${NC}"
echo ""
echo "Verify the deployment with these commands:"
echo ""
echo "1. Check configuration file:"
echo "   ${YELLOW}ssh -i $SSH_KEY_PATH $TARGET_USER@$TARGET_HOST 'cat ~/.ec2-config.env'${NC}"
echo ""
echo "2. Check service status:"
echo "   ${YELLOW}ssh -i $SSH_KEY_PATH $TARGET_USER@$TARGET_HOST 'sudo systemctl status deploy-portal ssh-helper'${NC}"
echo ""
echo "3. Test AWS connectivity:"
echo "   ${YELLOW}ssh -i $SSH_KEY_PATH $TARGET_USER@$TARGET_HOST 'source ~/.ec2-config.env && aws ec2 describe-security-groups --group-ids $TARGET_SG --region $TARGET_REGION'${NC}"
echo ""
echo "4. Access web interface:"
echo "   ${YELLOW}http://$TARGET_IP/${NC}"
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
