#!/bin/bash
# Fixed nginx configuration script with validation
# This replaces Step 8 of the deployment kit

set -e  # Exit on any error

APP_NAME="$1"
FRONTEND_PORT="$2"
BACKEND_PORT="$3"

if [ -z "$APP_NAME" ] || [ -z "$FRONTEND_PORT" ] || [ -z "$BACKEND_PORT" ]; then
    echo "Usage: $0 <app-name> <frontend-port> <backend-port>"
    echo "Example: $0 test-jan22-2026-network 3027 8027"
    exit 1
fi

echo "=== Configuring nginx for $APP_NAME ==="
echo "Frontend port: $FRONTEND_PORT"
echo "Backend port: $BACKEND_PORT"
echo ""

# Step 1: Add upstream definition
echo "Step 1: Adding upstream definition..."
sudo bash -c "cat >> /etc/nginx/sites-available/auth-gateway << EOF

# $APP_NAME upstream
upstream ${APP_NAME}_backend {
    server 127.0.0.1:$FRONTEND_PORT;
}
EOF"
echo "✓ Upstream definition added"

# Step 2: Create location blocks file
echo ""
echo "Step 2: Creating location blocks..."
cat > /tmp/${APP_NAME}-location.conf << EOF

    # Protected: $APP_NAME
    location /$APP_NAME/ {
        # Authentication check
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/start?rd=\$scheme://\$host\$request_uri;

        # Pass authentication headers
        auth_request_set \$user \$upstream_http_x_auth_request_user;
        auth_request_set \$email \$upstream_http_x_auth_request_email;
        auth_request_set \$auth_cookie \$upstream_http_set_cookie;
        add_header Set-Cookie \$auth_cookie;

        # Proxy to frontend
        proxy_pass http://${APP_NAME}_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-User-Email \$email;
        proxy_set_header X-Auth-Request-User \$user;

        # WebSocket and SSE support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
        proxy_buffering off;
        proxy_cache off;
    }

    # Redirect without trailing slash
    location = /$APP_NAME {
        return 301 /$APP_NAME/;
    }

    # API endpoint for $APP_NAME
    location /$APP_NAME/api/ {
        # Authentication check
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/start?rd=\$scheme://\$host\$request_uri;

        # Pass authentication headers
        auth_request_set \$user \$upstream_http_x_auth_request_user;
        auth_request_set \$email \$upstream_http_x_auth_request_email;

        # Rewrite to remove /$APP_NAME prefix
        rewrite ^/$APP_NAME/api/(.*)\$ /api/\$1 break;

        # Proxy to backend API
        proxy_pass http://127.0.0.1:$BACKEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-User-Email \$email;
        proxy_set_header X-Auth-Request-User \$user;

        # CORS headers
        add_header Access-Control-Allow-Origin \$http_origin always;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Authorization, Content-Type, X-API-Key" always;
        add_header Access-Control-Allow-Credentials true always;

        if (\$request_method = OPTIONS) {
            return 204;
        }

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
EOF
echo "✓ Location blocks file created"

# Step 3: Insert location blocks with validation
echo ""
echo "Step 3: Inserting location blocks into nginx config..."

# Check if "Health check endpoint" marker exists
if sudo grep -q "# Health check endpoint" /etc/nginx/sites-available/auth-gateway; then
    echo "Using 'Health check endpoint' marker method..."
    sudo sed -i "/# Health check endpoint/r /tmp/${APP_NAME}-location.conf" /etc/nginx/sites-available/auth-gateway
else
    echo "Marker not found, using fallback method..."
    # Find the last "location = /" redirect and insert after its closing brace
    LAST_REDIRECT=$(sudo grep -n "location = /" /etc/nginx/sites-available/auth-gateway | tail -1 | cut -d: -f1)
    if [ -z "$LAST_REDIRECT" ]; then
        echo "ERROR: Could not find insertion point in nginx config"
        exit 1
    fi
    
    # Find the next closing brace after the redirect
    NEXT_CLOSING=$(sudo awk "NR>$LAST_REDIRECT && /^    }/ {print NR; exit}" /etc/nginx/sites-available/auth-gateway)
    
    echo "Found insertion point at line $NEXT_CLOSING"
    sudo sed -i "${NEXT_CLOSING}r /tmp/${APP_NAME}-location.conf" /etc/nginx/sites-available/auth-gateway
fi

# Step 4: VALIDATE location blocks were added
echo ""
echo "Step 4: Validating location blocks were added..."
BLOCK_COUNT=$(sudo grep -c "location /$APP_NAME/" /etc/nginx/sites-available/auth-gateway)

if [ "$BLOCK_COUNT" -lt 2 ]; then
    echo "❌ ERROR: Location blocks were NOT added!"
    echo "Expected at least 2 location blocks for /$APP_NAME/, found $BLOCK_COUNT"
    echo ""
    echo "This usually means the nginx config structure is different than expected."
    echo "Please check /etc/nginx/sites-available/auth-gateway manually."
    exit 1
fi

echo "✓ Found $BLOCK_COUNT location blocks for /$APP_NAME/"

# Step 5: Test nginx configuration
echo ""
echo "Step 5: Testing nginx configuration..."
if ! sudo nginx -t; then
    echo "❌ ERROR: Nginx configuration test failed!"
    echo "The configuration has syntax errors. Rolling back..."
    # Attempt to restore from backup if available
    LATEST_BACKUP=$(sudo ls -t /home/ubuntu/deployments/.backups/auth-gateway-*.conf 2>/dev/null | head -1)
    if [ -n "$LATEST_BACKUP" ]; then
        sudo cp "$LATEST_BACKUP" /etc/nginx/sites-available/auth-gateway
        echo "Restored from backup: $LATEST_BACKUP"
    fi
    exit 1
fi
echo "✓ Nginx configuration is valid"

# Step 6: Reload nginx
echo ""
echo "Step 6: Reloading nginx..."
sudo systemctl reload nginx
echo "✓ Nginx reloaded successfully"

# Step 7: Verify the app is accessible
echo ""
echo "Step 7: Verifying deployment..."
HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://capsule-deploy.duckdns.org/$APP_NAME/ 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "200" ]; then
    echo "✓ App is accessible (HTTP $HTTP_CODE)"
    echo ""
    echo "════════════════════════════════════════════════════════"
    echo "✅ NGINX CONFIGURATION COMPLETE"
    echo "════════════════════════════════════════════════════════"
    echo ""
    echo "Your app is now available at:"
    echo "  https://capsule-deploy.duckdns.org/$APP_NAME/"
    echo ""
    echo "API endpoint:"
    echo "  https://capsule-deploy.duckdns.org/$APP_NAME/api/"
    echo ""
else
    echo "⚠️  Warning: App returned HTTP $HTTP_CODE"
    echo "This might be expected if authentication is required."
    echo "Try accessing: https://capsule-deploy.duckdns.org/$APP_NAME/"
fi

echo ""
echo "Cleanup: Removing temporary files..."
rm -f /tmp/${APP_NAME}-location.conf
echo "✓ Done"
