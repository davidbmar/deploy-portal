#!/bin/bash
# Setup SSL for deployment portal
# Can be run on any new EC2 instance

set -e

echo "🔐 Setting up SSL for deployment portal..."

# Create SSL directory
sudo mkdir -p /etc/nginx/ssl
sudo chmod 755 /etc/nginx/ssl

# Check if certificate exists and is valid
REGENERATE=false

if [ ! -f /etc/nginx/ssl/selfsigned.crt ]; then
    echo "📜 No certificate found, will generate new one"
    REGENERATE=true
else
    # Check certificate expiration
    EXPIRY=$(sudo openssl x509 -in /etc/nginx/ssl/selfsigned.crt -noout -enddate | cut -d= -f2)
    EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))

    echo "ℹ️  Existing certificate expires in $DAYS_LEFT days"

    if [ $DAYS_LEFT -lt 30 ]; then
        echo "⚠️  Certificate expires soon, will regenerate"
        REGENERATE=true
    else
        echo "✅ Certificate is valid, no regeneration needed"
    fi
fi

# Generate/regenerate certificate if needed
if [ "$REGENERATE" = true ]; then
    echo "📜 Generating self-signed certificate (valid for 10 years)..."

    # Backup old certificate if exists
    if [ -f /etc/nginx/ssl/selfsigned.crt ]; then
        sudo mv /etc/nginx/ssl/selfsigned.crt /etc/nginx/ssl/selfsigned.crt.old
        sudo mv /etc/nginx/ssl/selfsigned.key /etc/nginx/ssl/selfsigned.key.old
    fi

    # Get server IP for CN field
    SERVER_IP=$(curl -s http://checkip.amazonaws.com || echo "localhost")

    sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout /etc/nginx/ssl/selfsigned.key \
      -out /etc/nginx/ssl/selfsigned.crt \
      -subj "/C=US/ST=State/L=City/O=DeploymentPortal/CN=$SERVER_IP"

    echo "✅ Certificate generated"
    sudo openssl x509 -in /etc/nginx/ssl/selfsigned.crt -text -noout | grep -A 2 "Validity"
fi

# Set proper permissions
sudo chmod 644 /etc/nginx/ssl/selfsigned.crt
sudo chmod 600 /etc/nginx/ssl/selfsigned.key

echo "✅ SSL setup complete"
