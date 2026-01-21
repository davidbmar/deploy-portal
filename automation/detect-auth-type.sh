#!/bin/bash
# detect-auth-type.sh - Detect if app has internal authentication
#
# Issue #5: OAuth2 blocking app's login page
# This script detects internal auth and determines which routes to exclude from OAuth2

set -euo pipefail

APP_DIR="${1:-.}"

echo "=== Detecting Authentication Type ==="
echo "App directory: $APP_DIR"
echo ""

HAS_INTERNAL_AUTH=false
AUTH_ROUTES=()

# Check for login pages
if find "$APP_DIR" -type f \( -name "*login*" -o -name "*auth*" \) 2>/dev/null | grep -q .; then
    echo "✅ Found authentication-related files"
    
    # Check for email/password auth patterns
    if grep -ri "email.*password\|username.*password\|login.*form" "$APP_DIR" 2>/dev/null | head -5 | grep -q .; then
        echo "✅ Detected internal authentication (email/password)"
        HAS_INTERNAL_AUTH=true
        
        # Find login routes
        if grep -r "route.*login\|path.*login\|/login" "$APP_DIR/frontend" "$APP_DIR/src" 2>/dev/null | grep -o "/login[^\"']*" | sort -u | head -5; then
            AUTH_ROUTES+=("/login" "/login/")
        fi
        
        # Check for auth API routes
        if grep -r "/auth\|/api/auth" "$APP_DIR" 2>/dev/null | grep -q "/api.*auth"; then
            AUTH_ROUTES+=("/api/")
        fi
    fi
fi

echo ""
if [ "$HAS_INTERNAL_AUTH" = true ]; then
    echo "==== RESULT ===="
    echo "Authentication: INTERNAL (email/password)"
    echo "Exclude from OAuth2: ${AUTH_ROUTES[*]}"
    echo "==============="
    exit 0
else
    echo "==== RESULT ===="
    echo "Authentication: EXTERNAL ONLY (OAuth2)"
    echo "All routes: Protected by OAuth2"
    echo "==============="
    exit 1
fi
