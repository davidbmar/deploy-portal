#!/bin/bash
# Post-Deployment Health Check
# Validates that deployment is healthy and accessible

set -e

APP_DIR="$1"
APP_NAME="$2"
HOST="${3:-16.148.110.90}"

if [ -z "$APP_DIR" ] || [ -z "$APP_NAME" ]; then
    echo "Usage: post-deploy-healthcheck.sh <app-dir> <app-name> [host]"
    exit 1
fi

cd "$APP_DIR"

echo "=== Post-Deployment Health Check for $APP_NAME ==="

# Check container health
echo "Checking containers..."
RUNNING_COUNT=$(docker-compose ps --format json 2>/dev/null | jq -r 'select(.State == "running")' | wc -l)
TOTAL_COUNT=$(docker-compose ps --format json 2>/dev/null | wc -l)

if [ "$RUNNING_COUNT" -eq "$TOTAL_COUNT" ] && [ "$RUNNING_COUNT" -gt 0 ]; then
    echo "✅ All $RUNNING_COUNT containers running"
else
    echo "❌ Only $RUNNING_COUNT of $TOTAL_COUNT containers running"
    docker-compose ps
    exit 1
fi

# Test local endpoints
FRONTEND_PORT=$(docker-compose ps --format json | jq -r 'select(.Service == "frontend") | .Publishers[0].PublishedPort' 2>/dev/null)
if [ -n "$FRONTEND_PORT" ] && [ "$FRONTEND_PORT" != "null" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$FRONTEND_PORT/$APP_NAME/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✅ Frontend responding on port $FRONTEND_PORT (HTTP $HTTP_CODE)"
    else
        echo "⚠️  Frontend returned HTTP $HTTP_CODE on port $FRONTEND_PORT"
    fi
fi

# Test HTTPS endpoint
echo "Testing HTTPS endpoint..."
HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://$HOST/$APP_NAME/ 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "200" ]; then
    echo "✅ HTTPS endpoint accessible (HTTP $HTTP_CODE)"
else
    echo "❌ HTTPS endpoint failed (HTTP $HTTP_CODE)"
    exit 1
fi

# Check for errors in logs
ERROR_COUNT=$(docker-compose logs --tail=50 2>&1 | grep -ci "error\|fatal\|exception" || true)
if [ "$ERROR_COUNT" -gt 5 ]; then
    echo "⚠️  Found $ERROR_COUNT error messages in logs"
else
    echo "✅ Minimal errors in logs ($ERROR_COUNT)"
fi

echo ""
echo "✅ Health check completed!"
