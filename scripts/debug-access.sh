#!/bin/bash
# Quick script to debug external access issues

set -euo pipefail

echo "=== Debug External Access ==="
echo ""

# Get public IP
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "")

if [ -n "$TOKEN" ]; then
    PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
        http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
        http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
else
    echo "Not on EC2 - cannot debug"
    exit 1
fi

echo "Public IP: $PUBLIC_IP"
echo "Instance ID: $INSTANCE_ID"
echo ""

# Test internal
echo "--- Internal Access ---"
if curl -f -s --max-time 2 http://localhost/ > /dev/null 2>&1; then
    echo "✓ localhost/ works"
else
    echo "✗ localhost/ FAILS"
fi

# Test external from instance itself
echo ""
echo "--- External Access (from instance) ---"
if curl -f -s --max-time 5 "http://$PUBLIC_IP/" > /dev/null 2>&1; then
    echo "✓ $PUBLIC_IP/ works from instance"
else
    echo "✗ $PUBLIC_IP/ FAILS from instance"
    echo ""
    echo "Possible issues:"
    echo "1. Security group doesn't have port 80 open"
    echo "2. Nginx not listening on public interface"
    echo "3. Route table misconfiguration"
fi

# Check if nginx is listening on all interfaces
echo ""
echo "--- Nginx Listening ---"
sudo ss -tlnp | grep :80

# Check security group
echo ""
echo "--- Security Group Info ---"
if command -v aws &> /dev/null; then
    REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
        http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "us-east-1")

    echo "Getting security groups for $INSTANCE_ID..."
    aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --region "$REGION" \
        --query 'Reservations[0].Instances[0].SecurityGroups' \
        --output table 2>/dev/null || echo "Failed to query AWS"

    echo ""
    echo "Getting port 80 rules..."
    SG_ID=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --region "$REGION" \
        --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "")

    if [ -n "$SG_ID" ]; then
        aws ec2 describe-security-groups \
            --group-ids "$SG_ID" \
            --region "$REGION" \
            --query 'SecurityGroups[0].IpPermissions[?ToPort==`80`]' \
            --output table 2>/dev/null || echo "No port 80 rules found"
    fi
else
    echo "AWS CLI not installed - install with: sudo apt install awscli"
fi

echo ""
echo "=== Next Steps ==="
echo "If external access fails:"
echo "1. Check AWS Console → EC2 → Security Groups"
echo "2. Ensure your security group allows port 80 from your IP"
echo "3. Try: aws ec2 authorize-security-group-ingress --group-id \$SG_ID --protocol tcp --port 80 --cidr YOUR_IP/32"
