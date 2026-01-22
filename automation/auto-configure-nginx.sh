#!/bin/bash
# auto-configure-nginx.sh - Automatically configure nginx for a deployed app
# Reads app name and ports from deployment, configures nginx

set -euo pipefail

APP_DIR="${1:-.}"

# Change to app directory
cd "$APP_DIR"

# Get app name from config.json or directory name
if [[ -f config.json ]]; then
    APP_NAME=$(python3 -c "import json; print(json.load(open('config.json'))['app_name'])" 2>/dev/null || basename "$PWD")
else
    APP_NAME=$(basename "$PWD")
fi

echo "🔍 Detected app: $APP_NAME"

# Extract ports from docker-compose.yml
if [[ ! -f docker-compose.yml ]]; then
    echo "❌ Error: docker-compose.yml not found in $PWD" >&2
    exit 1
fi

# Find frontend port (mapping to internal 3000)
FRONTEND_PORT=$(grep -A3 'frontend:' docker-compose.yml | grep '\"[0-9]*:3000\"' | sed 's/[^0-9]*\([0-9]*\):.*/\1/' | head -1)

# Find backend port (mapping to internal 8000)
BACKEND_PORT=$(grep -A3 'backend:' docker-compose.yml | grep '\"[0-9]*:8000\"' | sed 's/[^0-9]*\([0-9]*\):.*/\1/' | head -1)

if [[ -z "$FRONTEND_PORT" ]] || [[ -z "$BACKEND_PORT" ]]; then
    echo "❌ Error: Could not detect ports from docker-compose.yml" >&2
    echo "   Looked for mappings like \"XXXX:3000\" and \"YYYY:8000\"" >&2
    exit 1
fi

echo "📋 Configuration:"
echo "   App Name: $APP_NAME"
echo "   Frontend Port: $FRONTEND_PORT"
echo "   Backend Port: $BACKEND_PORT"

# Check if already configured
if nginx-register exists "$APP_NAME"; then
    echo "⚠️  Nginx location already exists for $APP_NAME"
    echo "   To reconfigure, first run: nginx-register remove $APP_NAME"
    exit 1
fi

# Configure nginx (auto-detects auth mode from config.json)
echo ""
echo "🚀 Configuring nginx..."
nginx-register add-multiservice "$APP_NAME" "$FRONTEND_PORT" "$BACKEND_PORT"

echo ""
echo "🔄 Reloading nginx..."
nginx-register reload

echo ""
echo "✅ Nginx configuration complete!"
echo ""
echo "🌐 Your app should now be accessible at:"
echo "   https://$(hostname -f)/$APP_NAME/"
echo ""
echo "🔧 To test locally:"
echo "   curl -I http://localhost:$FRONTEND_PORT/$APP_NAME/"
echo "   curl http://localhost:$BACKEND_PORT/api/"
