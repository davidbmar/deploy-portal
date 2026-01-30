#!/bin/bash
# Interactive AWS Configuration File Setup Script
# Note: Assumes IAM role is attached to EC2 instance for credentials
# This script only configures region, security group, and other environment settings

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration file location
CONFIG_FILE="$HOME/.ec2-config.env"
BACKUP_FILE="$HOME/.ec2-config.env.backup"

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  AWS Configuration File Setup${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "This script will create a .ec2-config.env file with AWS"
echo "configuration settings (region, security group, etc.)."
echo ""
echo -e "${YELLOW}Note:${NC} This script assumes an IAM role is attached to your EC2"
echo "instance for AWS credentials. It does NOT configure access keys."
echo ""

# Function to verify IAM role
verify_iam_role() {
    echo -e "${BLUE}Verifying IAM role attachment...${NC}"

    if ! ROLE_NAME=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/iam/security-credentials/ 2>/dev/null); then
        echo -e "${RED}✗ Unable to access instance metadata service${NC}"
        echo ""
        echo -e "${YELLOW}Warning:${NC} Could not verify IAM role. This might mean:"
        echo "  1. You're not running on an EC2 instance"
        echo "  2. IMDSv2 requires a token (this is normal)"
        echo "  3. No IAM role is attached"
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
        return
    fi

    if [ -z "$ROLE_NAME" ]; then
        echo -e "${RED}✗ No IAM role attached to this instance${NC}"
        echo ""
        echo "You must attach an IAM role with EC2 permissions before proceeding."
        echo "See AWS documentation: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role-ec2.html"
        echo ""
        exit 1
    fi

    echo -e "${GREEN}✓ IAM role found: ${ROLE_NAME}${NC}"
    echo ""
}

# Function to get current public IP
get_public_ip() {
    # Try multiple methods to get public IP
    PUBLIC_IP=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || \
                curl -s --connect-timeout 2 http://checkip.amazonaws.com 2>/dev/null || \
                curl -s --connect-timeout 2 https://api.ipify.org 2>/dev/null || \
                echo "")
    echo "$PUBLIC_IP"
}

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate security group ID
validate_security_group() {
    local sg=$1
    if [[ $sg =~ ^sg-[a-z0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate AWS region
validate_region() {
    local region=$1
    # Basic region format validation
    if [[ $region =~ ^[a-z]{2}-[a-z]+-[0-9]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Backup existing config if present
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}⚠ Existing configuration file found${NC}"
    echo "Creating backup at: $BACKUP_FILE"
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    echo ""
fi

# Verify IAM role
verify_iam_role

# Get AWS Region
echo -e "${BLUE}AWS Region${NC}"
echo "Enter the AWS region for this instance (e.g., us-east-1, us-west-2)"
read -p "AWS Region [us-east-1]: " AWS_REGION
AWS_REGION=${AWS_REGION:-us-east-1}

while ! validate_region "$AWS_REGION"; do
    echo -e "${RED}Invalid region format. Expected format: us-east-1${NC}"
    read -p "AWS Region: " AWS_REGION
done
echo -e "${GREEN}✓ Region: ${AWS_REGION}${NC}"
echo ""

# Get Security Group ID
echo -e "${BLUE}Security Group ID${NC}"
echo "Enter the security group ID to manage (e.g., sg-0123456789abcdef0)"
read -p "Security Group ID: " SECURITY_GROUP_ID

while ! validate_security_group "$SECURITY_GROUP_ID"; do
    echo -e "${RED}Invalid security group format. Expected format: sg-xxxxxxxxx${NC}"
    read -p "Security Group ID: " SECURITY_GROUP_ID
done
echo -e "${GREEN}✓ Security Group: ${SECURITY_GROUP_ID}${NC}"
echo ""

# Get Public IP
echo -e "${BLUE}Public IP Address${NC}"
AUTO_IP=$(get_public_ip)
if [ -n "$AUTO_IP" ]; then
    echo "Auto-detected IP: $AUTO_IP"
    read -p "Public IP [$AUTO_IP]: " PUBLIC_IP
    PUBLIC_IP=${PUBLIC_IP:-$AUTO_IP}
else
    read -p "Public IP: " PUBLIC_IP
fi

while ! validate_ip "$PUBLIC_IP"; do
    echo -e "${RED}Invalid IP address format${NC}"
    read -p "Public IP: " PUBLIC_IP
done
echo -e "${GREEN}✓ Public IP: ${PUBLIC_IP}${NC}"
echo ""

# SSH Key Configuration (optional)
echo -e "${BLUE}SSH Key Configuration (Optional)${NC}"
echo "If you need to deploy to other servers, provide SSH key details"
read -p "SSH Key Path (leave empty to skip): " SSH_KEY_PATH

if [ -n "$SSH_KEY_PATH" ]; then
    # Expand tilde
    SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"

    if [ ! -f "$SSH_KEY_PATH" ]; then
        echo -e "${YELLOW}⚠ Warning: SSH key file not found at $SSH_KEY_PATH${NC}"
    fi

    # Extract key name from path
    SSH_KEY_NAME=$(basename "$SSH_KEY_PATH" .pem)
    echo -e "${GREEN}✓ SSH Key: ${SSH_KEY_PATH}${NC}"
    echo -e "${GREEN}✓ SSH Key Name: ${SSH_KEY_NAME}${NC}"
fi
echo ""

# AWS Cognito Configuration (optional)
echo -e "${BLUE}AWS Cognito Configuration (Optional)${NC}"
echo "Configure Cognito for OAuth2 authentication (leave empty to skip)"
read -p "Cognito User Pool ID: " COGNITO_POOL_ID
if [ -n "$COGNITO_POOL_ID" ]; then
    read -p "Cognito Client ID: " COGNITO_CLIENT_ID
    read -p "Cognito Client Secret: " COGNITO_CLIENT_SECRET
    read -p "Cognito Region [$AWS_REGION]: " COGNITO_REGION
    COGNITO_REGION=${COGNITO_REGION:-$AWS_REGION}
    read -p "Cognito Domain: " COGNITO_DOMAIN
    echo -e "${GREEN}✓ Cognito configured${NC}"
fi
echo ""

# Create configuration file
echo -e "${BLUE}Creating configuration file...${NC}"

cat > "$CONFIG_FILE" << EOF
# AWS Configuration
# Generated by configure-aws-config.sh on $(date)

# AWS Region (must match instance region)
export AWS_REGION=$AWS_REGION

# AWS Security Group ID
export SECURITY_GROUP_ID=$SECURITY_GROUP_ID

# Public IP for THIS server
export PUBLIC_IP=$PUBLIC_IP

EOF

# Add SSH key configuration if provided
if [ -n "$SSH_KEY_PATH" ]; then
    cat >> "$CONFIG_FILE" << EOF
# SSH Key Configuration
export SSH_KEY_PATH=$SSH_KEY_PATH
export SSH_KEY_NAME=$SSH_KEY_NAME

EOF
fi

# Add Cognito configuration if provided
if [ -n "$COGNITO_POOL_ID" ]; then
    cat >> "$CONFIG_FILE" << EOF
# AWS Cognito Configuration
export COGNITO_POOL_ID=$COGNITO_POOL_ID
export COGNITO_CLIENT_ID=$COGNITO_CLIENT_ID
export COGNITO_CLIENT_SECRET=$COGNITO_CLIENT_SECRET
export COGNITO_REGION=$COGNITO_REGION
export COGNITO_DOMAIN=$COGNITO_DOMAIN

EOF
fi

# Add OAuth2 port
cat >> "$CONFIG_FILE" << EOF
# OAuth2 Proxy Port (default)
export OAUTH2_PORT=4180
EOF

# Set permissions
chmod 600 "$CONFIG_FILE"
echo -e "${GREEN}✓ Configuration file created at: ${CONFIG_FILE}${NC}"
echo -e "${GREEN}✓ Permissions set to 600 (user read/write only)${NC}"
echo ""

# Update systemd services
echo -e "${BLUE}Updating systemd services...${NC}"

SERVICES=("deploy-portal" "ssh-helper")
UPDATED_SERVICES=()

for SERVICE in "${SERVICES[@]}"; do
    SERVICE_FILE="/etc/systemd/system/${SERVICE}.service"

    if [ -f "$SERVICE_FILE" ]; then
        # Check if EnvironmentFile already exists
        if ! grep -q "EnvironmentFile=" "$SERVICE_FILE"; then
            echo "Adding EnvironmentFile to $SERVICE.service"
            sudo sed -i '/\[Service\]/a EnvironmentFile='"$CONFIG_FILE" "$SERVICE_FILE"
            UPDATED_SERVICES+=("$SERVICE")
        else
            echo "$SERVICE.service already has EnvironmentFile configured"
        fi
    fi
done

if [ ${#UPDATED_SERVICES[@]} -gt 0 ]; then
    echo -e "${GREEN}✓ Updated ${#UPDATED_SERVICES[@]} service(s)${NC}"
    echo ""
    echo "Reloading systemd daemon..."
    sudo systemctl daemon-reload
    echo -e "${GREEN}✓ Systemd reloaded${NC}"
else
    echo -e "${YELLOW}No services needed updating${NC}"
fi
echo ""

# Test AWS connectivity
echo -e "${BLUE}Testing AWS connectivity...${NC}"

# Source the config file
source "$CONFIG_FILE"

# Test with Python and boto3
if command -v python3 &> /dev/null; then
    if python3 -c "import boto3" &> /dev/null; then
        echo "Testing boto3 connection..."

        TEST_RESULT=$(python3 << 'PYEOF'
import boto3
import os
import sys

try:
    region = os.environ.get('AWS_REGION', 'us-east-1')
    sg_id = os.environ.get('SECURITY_GROUP_ID')

    ec2 = boto3.client('ec2', region_name=region)

    # Try to describe the security group
    response = ec2.describe_security_groups(GroupIds=[sg_id])
    sg_name = response['SecurityGroups'][0]['GroupName']

    print(f"SUCCESS|{sg_name}")
    sys.exit(0)

except Exception as e:
    print(f"ERROR|{str(e)}")
    sys.exit(1)
PYEOF
)

        if [[ $TEST_RESULT == SUCCESS* ]]; then
            SG_NAME=$(echo "$TEST_RESULT" | cut -d'|' -f2)
            echo -e "${GREEN}✓ AWS connectivity verified!${NC}"
            echo -e "${GREEN}✓ Security group found: ${SG_NAME}${NC}"
        else
            ERROR_MSG=$(echo "$TEST_RESULT" | cut -d'|' -f2)
            echo -e "${RED}✗ AWS connectivity test failed${NC}"
            echo -e "${RED}  Error: ${ERROR_MSG}${NC}"
            echo ""
            echo -e "${YELLOW}Possible issues:${NC}"
            echo "  1. IAM role lacks EC2 permissions"
            echo "  2. Security group ID is incorrect"
            echo "  3. Region mismatch"
            echo ""
            echo "The configuration file has been created, but AWS access is not working."
            echo "You may need to:"
            echo "  - Attach/update the IAM role with EC2 permissions"
            echo "  - Verify the security group ID"
            echo "  - Check the AWS region"
        fi
    else
        echo -e "${YELLOW}⚠ boto3 not installed, skipping connectivity test${NC}"
        echo "Install boto3 with: pip3 install boto3"
    fi
else
    echo -e "${YELLOW}⚠ python3 not found, skipping connectivity test${NC}"
fi
echo ""

# Display summary
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Configuration Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Configuration file: ${GREEN}${CONFIG_FILE}${NC}"
echo -e "AWS Region: ${GREEN}${AWS_REGION}${NC}"
echo -e "Security Group: ${GREEN}${SECURITY_GROUP_ID}${NC}"
echo -e "Public IP: ${GREEN}${PUBLIC_IP}${NC}"
if [ -n "$SSH_KEY_PATH" ]; then
    echo -e "SSH Key: ${GREEN}${SSH_KEY_PATH}${NC}"
fi
if [ -n "$COGNITO_POOL_ID" ]; then
    echo -e "Cognito: ${GREEN}Configured${NC}"
fi
echo ""

# Next steps
echo -e "${BLUE}Next Steps:${NC}"
echo ""
if [ ${#UPDATED_SERVICES[@]} -gt 0 ]; then
    echo "1. Restart services to load the new configuration:"
    echo "   ${YELLOW}sudo systemctl restart ${UPDATED_SERVICES[*]}${NC}"
    echo ""
fi
echo "2. Verify services are running:"
echo "   ${YELLOW}sudo systemctl status deploy-portal ssh-helper${NC}"
echo ""
echo "3. Test the web interfaces:"
echo "   - Deploy Portal: http://${PUBLIC_IP}/"
echo "   - SSH Helper: http://${PUBLIC_IP}/ssh"
echo ""
echo "4. To load configuration in a shell session:"
echo "   ${YELLOW}source ${CONFIG_FILE}${NC}"
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
