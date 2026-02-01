#!/bin/bash
# Configure client-side router for subpath deployment
# Detects router type and applies appropriate configuration

set -e

APP_NAME="${1}"
APP_DIR="${2:-/home/ubuntu/deployments/$APP_NAME}"

if [ -z "$APP_NAME" ]; then
    echo "Usage: $0 APP_NAME [APP_DIR]"
    echo "Example: $0 automated-speech-recognition"
    exit 1
fi

echo "🔍 Detecting router type for $APP_NAME..."

cd "$APP_DIR"

# Detect router from package.json
PACKAGE_JSON="package.json"
ROUTER_TYPE="unknown"

if [ -f "$PACKAGE_JSON" ]; then
    if grep -q '"react-router-dom"' "$PACKAGE_JSON"; then
        ROUTER_TYPE="react-router"
        echo "✅ Detected: React Router (react-router-dom)"
    elif grep -q '"wouter"' "$PACKAGE_JSON"; then
        ROUTER_TYPE="wouter"
        echo "✅ Detected: Wouter"
    elif grep -q '"@tanstack/react-router"' "$PACKAGE_JSON"; then
        ROUTER_TYPE="tanstack"
        echo "✅ Detected: TanStack Router"
    elif grep -q '"vue-router"' "$PACKAGE_JSON"; then
        ROUTER_TYPE="vue"
        echo "✅ Detected: Vue Router"
    else
        echo "⚠️  No supported router detected"
        echo "   Supported: react-router-dom, wouter, @tanstack/react-router, vue-router"
        exit 0
    fi
else
    echo "❌ No package.json found"
    exit 1
fi

# Find router configuration file
echo "🔍 Searching for router configuration..."

case $ROUTER_TYPE in
    "react-router")
        # Search for BrowserRouter in both common locations
        ROUTER_FILE=$(grep -rl "BrowserRouter" client/src/ --include="*.tsx" --include="*.jsx" 2>/dev/null | head -1)
        if [ -z "$ROUTER_FILE" ]; then
            ROUTER_FILE=$(grep -rl "BrowserRouter" src/ --include="*.tsx" --include="*.jsx" 2>/dev/null | head -1)
        fi

        if [ -z "$ROUTER_FILE" ]; then
            echo "⚠️  Could not find BrowserRouter usage"
            echo "   Please configure manually: <BrowserRouter basename='/$APP_NAME'>"
            exit 1
        fi

        echo "📝 Found router in: $ROUTER_FILE"

        # Check if basename already configured
        if grep -q "basename=" "$ROUTER_FILE"; then
            echo "✅ Router basename already configured"
            exit 0
        fi

        echo "🔧 Adding basename to BrowserRouter..."
        cp "$ROUTER_FILE" "${ROUTER_FILE}.backup"

        # Add basename prop to BrowserRouter
        # Handle both <BrowserRouter> and <BrowserRouter props>
        sed -i 's|<BrowserRouter>|<BrowserRouter basename="/'$APP_NAME'">|g' "$ROUTER_FILE"
        sed -i 's|<BrowserRouter \([^b]\)|<BrowserRouter basename="/'$APP_NAME'" \1|g' "$ROUTER_FILE"

        echo "✅ React Router configured with basename='/$APP_NAME'"
        echo "   Backup saved: ${ROUTER_FILE}.backup"
        ;;

    "wouter")
        # Search for wouter imports in both common locations
        ROUTER_FILE=$(grep -rl 'from "wouter"' client/src/ --include="*.tsx" --include="*.jsx" 2>/dev/null | head -1)
        if [ -z "$ROUTER_FILE" ]; then
            ROUTER_FILE=$(grep -rl 'from "wouter"' src/ --include="*.tsx" --include="*.jsx" 2>/dev/null | head -1)
        fi

        if [ -z "$ROUTER_FILE" ]; then
            echo "⚠️  Could not find wouter usage"
            echo "   Please configure manually: <Router base='/$APP_NAME'>"
            exit 1
        fi

        echo "📝 Found router in: $ROUTER_FILE"

        # Check if Router base already configured
        if grep -q '<Router base=' "$ROUTER_FILE"; then
            echo "✅ Wouter Router base already configured"
            exit 0
        fi

        echo "⚠️  Wouter configuration requires manual edit"
        echo "   File: $ROUTER_FILE"
        echo ""
        echo "   Steps:"
        echo "   1. Add Router to imports:"
        echo "      import { Router, Switch, Route } from \"wouter\";"
        echo ""
        echo "   2. Wrap your <Switch> component:"
        echo "      <Router base='/$APP_NAME'>"
        echo "        <Switch>"
        echo "          <Route path='/' component={Home} />"
        echo "        </Switch>"
        echo "      </Router>"
        echo ""
        echo "   Backup created: ${ROUTER_FILE}.backup"

        # Create backup
        cp "$ROUTER_FILE" "${ROUTER_FILE}.backup"

        # Try to add Router to imports (best effort)
        if grep -q 'import.*Switch.*from "wouter"' "$ROUTER_FILE"; then
            sed -i 's|import { Switch|import { Router, Switch|' "$ROUTER_FILE"
            echo "   ✓ Added Router to imports (verify manually)"
        fi
        ;;

    "tanstack")
        ROUTER_FILE=$(find client/src -name "*router*.tsx" -o -name "*router*.ts" 2>/dev/null | head -1)
        if [ -z "$ROUTER_FILE" ]; then
            ROUTER_FILE=$(find src -name "*router*.tsx" -o -name "*router*.ts" 2>/dev/null | head -1)
        fi

        if [ -z "$ROUTER_FILE" ]; then
            echo "⚠️  Could not find TanStack Router config"
            exit 1
        fi

        echo "📝 Found router in: $ROUTER_FILE"

        if grep -q "basepath:" "$ROUTER_FILE"; then
            echo "✅ TanStack Router basepath already configured"
            exit 0
        fi

        echo "⚠️  TanStack Router configuration requires manual edit"
        echo "   File: $ROUTER_FILE"
        echo "   Add to router config: basepath: '/$APP_NAME'"
        echo ""
        echo "   Example:"
        echo "   const router = createRouter({"
        echo "     routeTree,"
        echo "     basepath: '/$APP_NAME',  // Add this line"
        echo "   })"

        cp "$ROUTER_FILE" "${ROUTER_FILE}.backup"
        echo "   Backup created: ${ROUTER_FILE}.backup"
        ;;

    "vue")
        ROUTER_FILE=$(find src -name "*router*.ts" -o -name "*router*.js" 2>/dev/null | head -1)
        if [ -z "$ROUTER_FILE" ]; then
            echo "⚠️  Could not find Vue Router config"
            exit 1
        fi

        echo "📝 Found router in: $ROUTER_FILE"

        if grep -q "createWebHistory('/" "$ROUTER_FILE"; then
            echo "✅ Vue Router base path already configured"
            exit 0
        fi

        echo "🔧 Adding base path to Vue Router..."
        cp "$ROUTER_FILE" "${ROUTER_FILE}.backup"

        # Update createWebHistory to include base path
        sed -i "s|createWebHistory()|createWebHistory('/$APP_NAME')|g" "$ROUTER_FILE"
        sed -i "s|createWebHistory(import.meta.env.BASE_URL)|createWebHistory('/$APP_NAME')|g" "$ROUTER_FILE"

        echo "✅ Vue Router configured with base '/$APP_NAME'"
        echo "   Backup saved: ${ROUTER_FILE}.backup"
        ;;
esac

echo ""
echo "🎉 Router configuration complete!"
echo ""
echo "⚠️  IMPORTANT: Rebuild Docker container for changes to take effect"
echo "   Run: sg docker -c 'docker-compose build --no-cache && docker-compose up -d'"
