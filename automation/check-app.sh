#\!/bin/bash
# check-app.sh - Generic deployment verification tool
# Usage: ./check-app.sh APP_NAME

set -euo pipefail

APP_NAME="${1:-}"
if [ -z "$APP_NAME" ]; then
    echo "Usage: $0 APP_NAME"
    exit 1
fi

APP_DIR="/home/ubuntu/deployments/$APP_NAME"
NGINX_CONFIG_ROUTES="/etc/nginx/conf.d/routes/${APP_NAME}.conf"
NGINX_CONFIG_SITES="/etc/nginx/sites-available/${APP_NAME}.conf"

echo "=== Deployment Verification for: $APP_NAME ==="
echo ""

# Check 1: App directory exists
echo "1. App Directory:"
if [ -d "$APP_DIR" ]; then
    echo "   ✅ Exists at $APP_DIR"
else
    echo "   ❌ NOT FOUND at $APP_DIR"
    exit 1
fi

# Check 2: Docker containers running
echo ""
echo "2. Docker Containers:"
if sg docker -c "docker ps --filter name=${APP_NAME} --format '{{.Names}}\t{{.Status}}' | grep -q ${APP_NAME}"; then
    sg docker -c "docker ps --filter name=${APP_NAME} --format '   ✅ {{.Names}}: {{.Status}}'"
else
    echo "   ❌ No containers running for $APP_NAME"
fi

# Check 3: Nginx configuration
echo ""
echo "3. Nginx Configuration:"
if [ -f "$NGINX_CONFIG_ROUTES" ]; then
    echo "   ✅ Config exists at $NGINX_CONFIG_ROUTES (modular)"
    
    # Check for required blocks
    echo "   Checking config contents:"
    grep -q "location /${APP_NAME}/_next/static/" "$NGINX_CONFIG_ROUTES" 2>/dev/null && echo "      ✅ Static assets block" || echo "      ⚠️  No static assets block"
    grep -q "location /${APP_NAME}/api/" "$NGINX_CONFIG_ROUTES" 2>/dev/null && echo "      ✅ API location" || echo "      ⚠️  No API location (ok for frontend-only apps)"
    grep -q "location /${APP_NAME}/" "$NGINX_CONFIG_ROUTES" 2>/dev/null && echo "      ✅ Frontend location" || echo "      ❌ No frontend location"
    grep -q "auth_request /oauth2/auth" "$NGINX_CONFIG_ROUTES" 2>/dev/null && echo "      ✅ OAuth2 authentication" || echo "      ⚠️  No OAuth2 auth (may be public)"
elif [ -f "$NGINX_CONFIG_SITES" ]; then
    echo "   ✅ Config exists at $NGINX_CONFIG_SITES (legacy)"
    echo "   ⚠️  Consider migrating to modular pattern: /etc/nginx/conf.d/routes/"
    
    # Check for required blocks
    echo "   Checking config contents:"
    grep -q "location /${APP_NAME}/_next/static/" "$NGINX_CONFIG_SITES" 2>/dev/null && echo "      ✅ Static assets block" || echo "      ⚠️  No static assets block"
    grep -q "location /${APP_NAME}/api/" "$NGINX_CONFIG_SITES" 2>/dev/null && echo "      ✅ API location" || echo "      ⚠️  No API location (ok for frontend-only apps)"
    grep -q "location /${APP_NAME}/" "$NGINX_CONFIG_SITES" 2>/dev/null && echo "      ✅ Frontend location" || echo "      ❌ No frontend location"
else
    echo "   ❌ Nginx config NOT FOUND"
    echo "      Expected at: $NGINX_CONFIG_ROUTES"
    echo "      Or: $NGINX_CONFIG_SITES"
fi

# Check 4: Nginx syntax
echo ""
echo "4. Nginx Syntax:"
if sudo nginx -t &>/dev/null; then
    echo "   ✅ Nginx configuration valid"
else
    echo "   ❌ Nginx configuration has errors"
    sudo nginx -t
fi

# Check 5: Nginx config is actually loaded
echo ""
echo "5. Config Loaded in Nginx:"
LOCATION_COUNT=$(sudo nginx -T 2>&1 | grep -c "location /${APP_NAME}/" || echo "0")
if [ "$LOCATION_COUNT" -gt 0 ]; then
    echo "   ✅ Config is loaded ($LOCATION_COUNT location blocks found)"
else
    echo "   ❌ Config NOT loaded in nginx"
    echo "      Check nginx includes or symlinks"
fi

# Check 6: Endpoint accessibility
echo ""
echo "6. Endpoint Test (from server):"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k "https://localhost/${APP_NAME}/" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    echo "   ✅ Endpoint accessible (HTTP $HTTP_CODE)"
elif [ "$HTTP_CODE" = "404" ]; then
    echo "   ❌ 404 Not Found - Nginx routing broken"
else
    echo "   ⚠️  HTTP $HTTP_CODE - Check logs"
fi

# Check 7: Container logs for errors
echo ""
echo "7. Recent Container Errors:"
if sg docker -c "docker logs ${APP_NAME}-frontend 2>&1 | tail -20 | grep -i error" 2>/dev/null; then
    echo "   ⚠️  Frontend errors found (see above)"
else
    echo "   ✅ No frontend errors in recent logs"
fi

echo ""
echo "=== Verification Complete ==="
