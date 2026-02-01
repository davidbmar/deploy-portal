#!/bin/bash
# Configure nginx with SSL support
# Automatically adds HTTPS (443) server block if not present

set -e

NGINX_CONFIG="/etc/nginx/conf.d/deploy-portal-server.conf"

echo "🔧 Configuring nginx for SSL..."

# Check if SSL block already exists
if sudo grep -q "listen 443 ssl" "$NGINX_CONFIG"; then
    echo "ℹ️  SSL already configured in nginx"
    exit 0
fi

# Backup current config
sudo cp "$NGINX_CONFIG" "${NGINX_CONFIG}.backup-$(date +%Y%m%d-%H%M%S)"

# Create temporary file with SSL block
cat > /tmp/ssl-block.conf << 'EOF'

# HTTPS Server Block (SSL)
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;

    # SSL Certificate
    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;

    # SSL Configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_stapling off;  # Not applicable for self-signed
    ssl_stapling_verify off;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # ACME challenge (for future Let's Encrypt migration)
    location /.well-known/acme-challenge/ {
        root /var/www/html;
        default_type text/plain;
    }

    # Health check
    location /health {
        proxy_pass http://deploy_portal;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        access_log off;
    }

    # OAuth2 Proxy
    location /oauth2/ {
        proxy_pass http://127.0.0.1:4180;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Auth-Request-Redirect $scheme://$host$request_uri;
    }

    # Include all application routes
    include /etc/nginx/conf.d/routes/*.conf;
}
EOF

# Append SSL block to nginx config
sudo sh -c "cat /tmp/ssl-block.conf >> $NGINX_CONFIG"
rm /tmp/ssl-block.conf

# Validate nginx config
if sudo nginx -t; then
    echo "✅ Nginx configuration valid"
    sudo systemctl reload nginx
    echo "✅ Nginx reloaded with SSL support"
else
    echo "❌ Nginx configuration invalid, restoring backup"
    sudo cp "${NGINX_CONFIG}.backup-$(date +%Y%m%d-%H%M%S)" "$NGINX_CONFIG"
    exit 1
fi

# Verify port 443 listening
sleep 2
if sudo netstat -tlnp | grep ':443' > /dev/null; then
    echo "✅ Port 443 listening"
else
    echo "⚠️  Port 443 not listening (check firewall)"
fi

echo "🎉 SSL configuration complete"
