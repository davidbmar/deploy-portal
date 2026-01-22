#!/bin/bash
# Pre-Deployment Validator - Run on server before deployment
# Validates project structure and configuration

set -e

APP_DIR="$1"
APP_NAME="$2"

if [ -z "$APP_DIR" ] || [ -z "$APP_NAME" ]; then
    echo "Usage: pre-deploy-validate.sh <app-dir> <app-name>"
    exit 1
fi

cd "$APP_DIR"

echo "=== Pre-Deployment Validation for $APP_NAME ==="

# Check framework type
if [ -f "frontend/next.config.js" ]; then
    FRAMEWORK="nextjs"
    echo "✅ Detected: Next.js"

    # Ensure public directory exists
    if [ ! -d "frontend/public" ]; then
        echo "⚠️  Missing frontend/public directory - creating..."
        mkdir -p frontend/public
        echo "✅ Created frontend/public"
    else
        echo "✅ frontend/public exists"
    fi
fi

# Validate docker-compose.yml
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ docker-compose.yml not found"
    exit 1
fi
echo "✅ docker-compose.yml exists"

# Check API URL format
if [ -f "frontend/.env.local" ]; then
    if grep -q "NEXT_PUBLIC_API_URL.*\/api$" frontend/.env.local; then
        echo "❌ ERROR: NEXT_PUBLIC_API_URL should NOT end with /api"
        echo "   Found in frontend/.env.local"
        exit 1
    fi
fi

if grep -q "NEXT_PUBLIC_API_URL.*\/api\"" docker-compose.yml; then
    echo "❌ ERROR: NEXT_PUBLIC_API_URL should NOT end with /api"
    echo "   Found in docker-compose.yml"
    exit 1
fi

echo "✅ API URL format correct"

echo ""
echo "✅ Pre-deployment validation passed!"
