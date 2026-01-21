#!/bin/bash
# auto-fix-cors.sh - Automatically patch CORS to include production origin
#
# Issue #2: CORS blocked (backend only allowed localhost)
# This script detects FastAPI/Flask/Express apps and patches CORS config

set -euo pipefail

APP_DIR="${1:-.}"
PRODUCTION_ORIGIN="${2:-}"

if [ -z "$PRODUCTION_ORIGIN" ]; then
    echo "Usage: $0 APP_DIR PRODUCTION_ORIGIN"
    echo "Example: $0 /home/ubuntu/deployments/myapp https://16.148.110.90"
    exit 1
fi

echo "=== Auto-patching CORS configuration ==="
echo "App directory: $APP_DIR"
echo "Production origin: $PRODUCTION_ORIGIN"
echo ""

# Detect backend type
if [ -d "$APP_DIR/backend" ]; then
    BACKEND_DIR="$APP_DIR/backend"
elif [ -d "$APP_DIR/api" ]; then
    BACKEND_DIR="$APP_DIR/api"
elif [ -d "$APP_DIR/server" ]; then
    BACKEND_DIR="$APP_DIR/server"
else
    echo "⚠️  No backend directory found"
    exit 0
fi

# Check for FastAPI (Python)
FASTAPI_MAIN=$(find "$BACKEND_DIR" -name "main.py" -o -name "app.py" | head -1)
if [ -n "$FASTAPI_MAIN" ] && grep -q "CORSMiddleware\|fastapi" "$FASTAPI_MAIN"; then
    echo "✅ Detected FastAPI backend: $FASTAPI_MAIN"
    
    # Check if production origin is already present
    if grep -q "$PRODUCTION_ORIGIN" "$FASTAPI_MAIN"; then
        echo "✅ Production origin already in CORS config"
    else
        echo "⚠️  Production origin NOT in CORS config - patching..."
        
        # Backup original
        cp "$FASTAPI_MAIN" "${FASTAPI_MAIN}.backup-$(date +%Y%m%d-%H%M%S)"
        
        # Patch: Find allow_origins line and add production origin
        # This is a simple sed approach - may need adjustment for complex configs
        if grep -q "allow_origins.*=.*\[" "$FASTAPI_MAIN"; then
            # Array format: allow_origins=["localhost", ...]
            sed -i "/allow_origins.*=.*\[/s/\[/[\"$PRODUCTION_ORIGIN\", /" "$FASTAPI_MAIN"
            echo "✅ Patched CORS configuration"
        else
            echo "⚠️  Could not auto-patch - manual intervention required"
            echo "   Add this to allow_origins: \"$PRODUCTION_ORIGIN\""
        fi
    fi
fi

# Check for Express (Node.js)
EXPRESS_MAIN=$(find "$BACKEND_DIR" -name "server.js" -o -name "index.js" -o -name "app.js" | head -1)
if [ -n "$EXPRESS_MAIN" ] && grep -q "cors\|express" "$EXPRESS_MAIN"; then
    echo "✅ Detected Express backend: $EXPRESS_MAIN"
    
    if grep -q "$PRODUCTION_ORIGIN" "$EXPRESS_MAIN"; then
        echo "✅ Production origin already in CORS config"
    else
        echo "⚠️  Production origin NOT in CORS config"
        echo "   Manual patch required: Add $PRODUCTION_ORIGIN to cors origin"
    fi
fi

echo ""
echo "=== CORS check complete ==="
