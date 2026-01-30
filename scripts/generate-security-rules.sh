#!/bin/bash
# Generate security group rules for deploy-portal instances
# Avoids using 0.0.0.0/0 by specifying exact IPs

set -uo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== Deploy Portal Security Group Rules Generator ==="
echo ""

# Get current instance info
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "")

if [ -n "$TOKEN" ]; then
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
        http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
    PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
        http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
    REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
        http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "us-east-1")

    echo "Current Instance:"
    echo "  Instance ID: $INSTANCE_ID"
    echo "  Public IP: $PUBLIC_IP"
    echo "  Region: $REGION"
else
    echo "Not running on EC2"
    INSTANCE_ID="i-xxxxxxxxx"
    PUBLIC_IP="YOUR_INSTANCE_IP"
    REGION="us-east-1"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Required Security Group Rules${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Define allowed IPs
echo "Enter the IPs that should have access (one per line, press Enter on empty line to finish):"
echo "Examples:"
echo "  136.62.92.204      # Your MacBook"
echo "  16.148.110.90      # Engineering server"
echo "  3.87.27.213        # Another instance"
echo ""

ALLOWED_IPS=()
while true; do
    read -p "IP address (or Enter to finish): " ip
    if [ -z "$ip" ]; then
        break
    fi
    ALLOWED_IPS+=("$ip")
done

if [ ${#ALLOWED_IPS[@]} -eq 0 ]; then
    echo ""
    echo -e "${YELLOW}No IPs provided. Using common defaults:${NC}"
    ALLOWED_IPS=(
        "136.62.92.204"    # David's MacBook
        "16.148.110.90"    # Engineering server
        "3.87.27.213"      # Other instance
    )
fi

echo ""
echo -e "${GREEN}Generating rules for ${#ALLOWED_IPS[@]} IP(s)${NC}"
echo ""

# Get security group ID
if command -v aws &> /dev/null && [ "$INSTANCE_ID" != "unknown" ] && [ "$INSTANCE_ID" != "i-xxxxxxxxx" ]; then
    SG_ID=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --region "$REGION" \
        --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "")

    if [ -n "$SG_ID" ]; then
        echo "Detected Security Group: $SG_ID"
        echo ""
    fi
else
    SG_ID="sg-xxxxxxxxx"
    echo "Security Group ID: $SG_ID (replace with actual)"
    echo ""
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}AWS CLI Commands${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

for ip in "${ALLOWED_IPS[@]}"; do
    # Determine description based on IP
    DESC="Access from $ip"
    if [ "$ip" = "136.62.92.204" ]; then
        DESC="David's MacBook"
    elif [ "$ip" = "16.148.110.90" ]; then
        DESC="Engineering server in playground"
    elif [ "$ip" = "3.87.27.213" ]; then
        DESC="Capsule deploy instance"
    fi

    echo "# Allow HTTP from $ip ($DESC)"
    echo "aws ec2 authorize-security-group-ingress \\"
    echo "    --group-id $SG_ID \\"
    echo "    --protocol tcp \\"
    echo "    --port 80 \\"
    echo "    --cidr $ip/32 \\"
    echo "    --region $REGION \\"
    echo "    --description \"$DESC\""
    echo ""

    echo "# Allow HTTPS from $ip ($DESC)"
    echo "aws ec2 authorize-security-group-ingress \\"
    echo "    --group-id $SG_ID \\"
    echo "    --protocol tcp \\"
    echo "    --port 443 \\"
    echo "    --cidr $ip/32 \\"
    echo "    --region $REGION \\"
    echo "    --description \"$DESC\""
    echo ""

    echo "# Allow SSH from $ip ($DESC)"
    echo "aws ec2 authorize-security-group-ingress \\"
    echo "    --group-id $SG_ID \\"
    echo "    --protocol tcp \\"
    echo "    --port 22 \\"
    echo "    --cidr $ip/32 \\"
    echo "    --region $REGION \\"
    echo "    --description \"$DESC\""
    echo ""
    echo "# ─────────────────────────────────────────"
    echo ""
done

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}One-liner (all rules at once)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Generate a script
SCRIPT_FILE="/tmp/apply-security-rules-$INSTANCE_ID.sh"
cat > "$SCRIPT_FILE" << 'SCRIPT_HEADER'
#!/bin/bash
# Auto-generated security group rules
# Created by generate-security-rules.sh

set -e

SCRIPT_HEADER

echo "SG_ID=\"$SG_ID\"" >> "$SCRIPT_FILE"
echo "REGION=\"$REGION\"" >> "$SCRIPT_FILE"
echo "" >> "$SCRIPT_FILE"

for ip in "${ALLOWED_IPS[@]}"; do
    DESC="Access from $ip"
    if [ "$ip" = "136.62.92.204" ]; then
        DESC="David's MacBook"
    elif [ "$ip" = "16.148.110.90" ]; then
        DESC="Engineering server in playground"
    elif [ "$ip" = "3.87.27.213" ]; then
        DESC="Capsule deploy instance"
    fi

    cat >> "$SCRIPT_FILE" << SCRIPT_BODY
# $DESC - HTTP
aws ec2 authorize-security-group-ingress \\
    --group-id \$SG_ID \\
    --protocol tcp --port 80 \\
    --cidr $ip/32 \\
    --region \$REGION \\
    --description "$DESC" 2>/dev/null || echo "Port 80 rule for $ip already exists"

# $DESC - HTTPS
aws ec2 authorize-security-group-ingress \\
    --group-id \$SG_ID \\
    --protocol tcp --port 443 \\
    --cidr $ip/32 \\
    --region \$REGION \\
    --description "$DESC" 2>/dev/null || echo "Port 443 rule for $ip already exists"

# $DESC - SSH
aws ec2 authorize-security-group-ingress \\
    --group-id \$SG_ID \\
    --protocol tcp --port 22 \\
    --cidr $ip/32 \\
    --region \$REGION \\
    --description "$DESC" 2>/dev/null || echo "Port 22 rule for $ip already exists"

SCRIPT_BODY
done

echo "" >> "$SCRIPT_FILE"
echo "echo 'Security group rules applied successfully!'" >> "$SCRIPT_FILE"

chmod +x "$SCRIPT_FILE"

echo "Generated script: $SCRIPT_FILE"
echo ""
echo "To apply all rules at once:"
echo -e "${GREEN}bash $SCRIPT_FILE${NC}"
echo ""

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Security Group: $SG_ID"
echo "Allowed IPs: ${#ALLOWED_IPS[@]}"
for ip in "${ALLOWED_IPS[@]}"; do
    echo "  → $ip/32"
done
echo ""
echo "Ports opened:"
echo "  → 80 (HTTP)"
echo "  → 443 (HTTPS)"
echo "  → 22 (SSH)"
echo ""
echo -e "${YELLOW}Note: This avoids using 0.0.0.0/0 for better security${NC}"
