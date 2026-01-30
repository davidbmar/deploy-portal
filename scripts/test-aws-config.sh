#!/bin/bash
# Quick test script to verify AWS configuration and connectivity

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CONFIG_FILE="$HOME/.ec2-config.env"

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  AWS Configuration Test${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Check if config file exists
echo -n "Checking configuration file... "
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}✗${NC}"
    echo -e "${RED}Configuration file not found: $CONFIG_FILE${NC}"
    echo ""
    echo "Create one using: bash scripts/configure-aws-config.sh"
    exit 1
fi
echo -e "${GREEN}✓${NC}"

# Check file permissions
echo -n "Checking file permissions... "
PERMS=$(stat -c "%a" "$CONFIG_FILE")
if [ "$PERMS" != "600" ]; then
    echo -e "${YELLOW}⚠${NC}"
    echo -e "${YELLOW}  Warning: Permissions are $PERMS, should be 600${NC}"
    echo "  Fix with: chmod 600 $CONFIG_FILE"
else
    echo -e "${GREEN}✓${NC}"
fi

# Source the config file
source "$CONFIG_FILE"

# Check required variables
echo -n "Checking required variables... "
MISSING=""
[ -z "$AWS_REGION" ] && MISSING="$MISSING AWS_REGION"
[ -z "$SECURITY_GROUP_ID" ] && MISSING="$MISSING SECURITY_GROUP_ID"
[ -z "$PUBLIC_IP" ] && MISSING="$MISSING PUBLIC_IP"

if [ -n "$MISSING" ]; then
    echo -e "${RED}✗${NC}"
    echo -e "${RED}  Missing variables:$MISSING${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC}"

# Display configuration
echo ""
echo -e "${BLUE}Configuration:${NC}"
echo "  AWS Region: $AWS_REGION"
echo "  Security Group: $SECURITY_GROUP_ID"
echo "  Public IP: $PUBLIC_IP"
if [ -n "$SSH_KEY_PATH" ]; then
    echo "  SSH Key: $SSH_KEY_PATH"
fi
echo ""

# Check IAM role
echo -n "Checking IAM role... "
if ROLE_NAME=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/iam/security-credentials/ 2>/dev/null); then
    if [ -n "$ROLE_NAME" ]; then
        echo -e "${GREEN}✓${NC}"
        echo "  IAM Role: $ROLE_NAME"
    else
        echo -e "${RED}✗${NC}"
        echo -e "${RED}  No IAM role attached${NC}"
        echo ""
        echo "An IAM role with EC2 permissions must be attached to this instance."
        exit 1
    fi
else
    echo -e "${YELLOW}⚠${NC}"
    echo "  Cannot access instance metadata (might be IMDSv2 or not on EC2)"
fi
echo ""

# Test AWS CLI if available
if command -v aws &> /dev/null; then
    echo -n "Testing AWS CLI... "
    if aws sts get-caller-identity --region "$AWS_REGION" &> /dev/null; then
        echo -e "${GREEN}✓${NC}"
        IDENTITY=$(aws sts get-caller-identity --region "$AWS_REGION" 2>/dev/null)
        ACCOUNT=$(echo "$IDENTITY" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
        echo "  AWS Account: $ACCOUNT"
    else
        echo -e "${RED}✗${NC}"
        echo -e "${RED}  AWS CLI authentication failed${NC}"
    fi
else
    echo -e "${YELLOW}⚠ AWS CLI not installed${NC}"
fi
echo ""

# Test boto3 if available
if command -v python3 &> /dev/null; then
    if python3 -c "import boto3" &> /dev/null; then
        echo -n "Testing boto3 connectivity... "

        TEST_RESULT=$(python3 << 'PYEOF'
import boto3
import os
import sys

try:
    region = os.environ.get('AWS_REGION', 'us-east-1')
    sg_id = os.environ.get('SECURITY_GROUP_ID')

    # Create EC2 client
    ec2 = boto3.client('ec2', region_name=region)

    # Try to describe the security group
    response = ec2.describe_security_groups(GroupIds=[sg_id])
    sg = response['SecurityGroups'][0]

    print(f"SUCCESS|{sg['GroupName']}|{sg['VpcId']}|{len(sg['IpPermissions'])}")
    sys.exit(0)

except Exception as e:
    print(f"ERROR|{str(e)}")
    sys.exit(1)
PYEOF
)

        if [[ $TEST_RESULT == SUCCESS* ]]; then
            echo -e "${GREEN}✓${NC}"
            SG_NAME=$(echo "$TEST_RESULT" | cut -d'|' -f2)
            VPC_ID=$(echo "$TEST_RESULT" | cut -d'|' -f3)
            RULE_COUNT=$(echo "$TEST_RESULT" | cut -d'|' -f4)

            echo "  Security Group Name: $SG_NAME"
            echo "  VPC ID: $VPC_ID"
            echo "  Inbound Rules: $RULE_COUNT"
        else
            echo -e "${RED}✗${NC}"
            ERROR_MSG=$(echo "$TEST_RESULT" | cut -d'|' -f2)
            echo -e "${RED}  Error: $ERROR_MSG${NC}"
            echo ""
            echo -e "${YELLOW}Possible issues:${NC}"
            echo "  - IAM role lacks EC2 permissions"
            echo "  - Security group ID is incorrect"
            echo "  - Region mismatch"
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠ boto3 not installed${NC}"
        echo "  Install with: pip3 install boto3"
    fi
else
    echo -e "${YELLOW}⚠ python3 not found${NC}"
fi
echo ""

# Test SSH key if configured
if [ -n "$SSH_KEY_PATH" ]; then
    echo -n "Checking SSH key... "
    if [ -f "$SSH_KEY_PATH" ]; then
        KEY_PERMS=$(stat -c "%a" "$SSH_KEY_PATH")
        if [ "$KEY_PERMS" = "400" ] || [ "$KEY_PERMS" = "600" ]; then
            echo -e "${GREEN}✓${NC}"
            echo "  Key file: $SSH_KEY_PATH"
            echo "  Permissions: $KEY_PERMS"
        else
            echo -e "${YELLOW}⚠${NC}"
            echo "  Key has permissions $KEY_PERMS, should be 400 or 600"
            echo "  Fix with: chmod 400 $SSH_KEY_PATH"
        fi
    else
        echo -e "${RED}✗${NC}"
        echo -e "${RED}  SSH key not found: $SSH_KEY_PATH${NC}"
    fi
    echo ""
fi

# Check systemd services
echo -e "${BLUE}Systemd Services:${NC}"
SERVICES=("deploy-portal" "ssh-helper")

for SERVICE in "${SERVICES[@]}"; do
    SERVICE_FILE="/etc/systemd/system/${SERVICE}.service"

    echo -n "  $SERVICE: "

    if [ -f "$SERVICE_FILE" ]; then
        # Check if EnvironmentFile is configured
        if sudo grep -q "EnvironmentFile=$CONFIG_FILE" "$SERVICE_FILE" 2>/dev/null; then
            # Check if service is running
            if sudo systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
                echo -e "${GREEN}✓ Running (config loaded)${NC}"
            else
                echo -e "${YELLOW}⚠ Stopped (config loaded)${NC}"
            fi
        else
            echo -e "${YELLOW}⚠ EnvironmentFile not configured${NC}"
            echo "    Add to $SERVICE_FILE:"
            echo "    EnvironmentFile=$CONFIG_FILE"
        fi
    else
        echo -e "${YELLOW}⚠ Service not installed${NC}"
    fi
done
echo ""

# Summary
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Test Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}✓ Configuration file exists and is readable${NC}"
echo -e "${GREEN}✓ All required variables are set${NC}"

if [[ $TEST_RESULT == SUCCESS* ]]; then
    echo -e "${GREEN}✓ AWS connectivity is working${NC}"
    echo ""
    echo "Your AWS configuration is properly set up!"
else
    echo -e "${YELLOW}⚠ Could not verify AWS connectivity${NC}"
    echo ""
    echo "Configuration file is set up, but AWS access could not be verified."
fi

echo ""
echo "To use this configuration in scripts:"
echo "  ${YELLOW}source $CONFIG_FILE${NC}"
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
