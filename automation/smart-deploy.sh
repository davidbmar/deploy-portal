#!/bin/bash
# smart-deploy.sh - Smart deployment with automatic fixes
#
# This script orchestrates all infrastructure fixes:
# - Issue #2: Auto-patch CORS
# - Issue #3: Generate framework-aware nginx config
# - Issue #5: Detect internal auth and configure OAuth2 exceptions

set -euo pipefail

APP_NAME="${1:-}"
APP_DIR="${2:-}"
PRODUCTION_HOST="${3:-}"
FRONTEND_PORT="${4:-3000}"
BACKEND_PORT="${5:-8000}"

if [ -z "$APP_NAME" ] || [ -z "$APP_DIR" ] || [ -z "$PRODUCTION_HOST" ]; then
    echo "Usage: $0 APP_NAME APP_DIR PRODUCTION_HOST [FRONTEND_PORT] [BACKEND_PORT]"
    echo "Example: $0 myapp /home/ubuntu/deployments/myapp https://16.148.110.90 3000 8000"
    exit 1
fi

echo "═══════════════════════════════════════════════════════════"
echo "  SMART DEPLOYMENT - Automatic Infrastructure Fixes"
echo "═══════════════════════════════════════════════════════════"
echo "App: $APP_NAME"
echo "Directory: $APP_DIR"
echo "Production: $PRODUCTION_HOST"
echo "Ports: Frontend=$FRONTEND_PORT, Backend=$BACKEND_PORT"
echo "═══════════════════════════════════════════════════════════"
echo ""

SCRIPT_DIR="$(dirname "$0")"

# Step 1: Auto-fix CORS
echo "━━━ Step 1: Auto-fix CORS Configuration ━━━"
"$SCRIPT_DIR/auto-fix-cors.sh" "$APP_DIR" "$PRODUCTION_HOST" || true
echo ""

# Step 2: Detect authentication type
echo "━━━ Step 2: Detect Authentication Type ━━━"
if "$SCRIPT_DIR/detect-auth-type.sh" "$APP_DIR"; then
    HAS_INTERNAL_AUTH=true
    echo "→ Will use internal-auth nginx template"
else
    HAS_INTERNAL_AUTH=false
    echo "→ Will use OAuth2-only nginx template"
fi
echo ""

# Step 3: Detect framework
echo "━━━ Step 3: Detect Framework ━━━"
FRAMEWORK="unknown"
if [ -f "$APP_DIR/next.config.js" ] || [ -f "$APP_DIR/frontend/next.config.js" ]; then
    FRAMEWORK="nextjs"
    echo "✅ Detected: Next.js"
elif [ -f "$APP_DIR/package.json" ] && grep -q "react" "$APP_DIR/package.json"; then
    FRAMEWORK="react"
    echo "✅ Detected: React"
elif [ -f "$APP_DIR/package.json" ] && grep -q "vue" "$APP_DIR/package.json"; then
    FRAMEWORK="vue"
    echo "✅ Detected: Vue"
else
    echo "⚠️  Framework unknown - using generic template"
fi
echo ""

# Step 4: Generate nginx config
echo "━━━ Step 4: Generate Nginx Configuration ━━━"
NGINX_CONFIG="/etc/nginx/conf.d/routes/${APP_NAME}.conf"

if [ "$FRAMEWORK" = "nextjs" ]; then
    if [ "$HAS_INTERNAL_AUTH" = true ]; then
        TEMPLATE="$SCRIPT_DIR/templates/nginx-nextjs-internal-auth.conf.tmpl"
    else
        TEMPLATE="$SCRIPT_DIR/templates/nginx-nextjs-oauth-only.conf.tmpl"
    fi
    
    echo "Using template: $(basename $TEMPLATE)"
    
    # Generate config from template
    sed -e "s/{{APP_NAME}}/$APP_NAME/g" \
        -e "s/{{FRONTEND_PORT}}/$FRONTEND_PORT/g" \
        -e "s/{{BACKEND_PORT}}/$BACKEND_PORT/g" \
        "$TEMPLATE" | sudo tee "$NGINX_CONFIG" > /dev/null
    
    echo "✅ Generated nginx config: $NGINX_CONFIG"
else
    echo "⚠️  Using existing nginx-register.sh for non-Next.js apps"
    "$SCRIPT_DIR/nginx-register.sh" add-multiservice "$APP_NAME" "$FRONTEND_PORT" "$BACKEND_PORT"
fi
echo ""

# Step 5: Test nginx config
echo "━━━ Step 5: Test Nginx Configuration ━━━"
if sudo nginx -t; then
    echo "✅ Nginx configuration valid"
    sudo systemctl reload nginx
    echo "✅ Nginx reloaded"
else
    echo "❌ Nginx configuration has errors!"
    exit 1
fi
echo ""

# Step 6: Verify deployment
echo "━━━ Step 6: Verify Deployment ━━━"
"$SCRIPT_DIR/check-app.sh" "$APP_NAME" || true
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "  SMART DEPLOYMENT COMPLETE"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "🌐 App URL: $PRODUCTION_HOST/$APP_NAME/"
echo ""
echo "Next steps:"
echo "  1. Visit $PRODUCTION_HOST/$APP_NAME/"
echo "  2. Complete OAuth if prompted"
echo "  3. Check logs: docker logs $APP_NAME-frontend -f"
echo ""
