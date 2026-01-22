#!/bin/bash
# post-deploy-validate.sh - Validates deployment after completion
# Checks containers, nginx config, oauth2_proxy, and public access

set -euo pipefail

APP_NAME="${1:-}"
AUTH_MODE="${2:-}"
FRONTEND_PORT="${3:-}"
BACKEND_PORT="${4:-}"
BASE_URL="${BASE_URL:-https://capsule-deploy.duckdns.org}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Usage information
usage() {
    cat << EOF
Usage: $0 <app_name> <auth_mode> [frontend_port] [backend_port]

Arguments:
  app_name       Name of the application
  auth_mode      Authentication mode: "none", "cognito", or "internal"
  frontend_port  Frontend port number (optional, for local testing)
  backend_port   Backend port number (optional, for local testing)

Examples:
  $0 my-app none
  $0 my-app cognito 3002 8002
  $0 my-app internal 3001 8001

Environment Variables:
  BASE_URL       Base URL for public access (default: https://capsule-deploy.duckdns.org)

EOF
    exit 1
}

if [ -z "$APP_NAME" ] || [ -z "$AUTH_MODE" ]; then
    log_error "Missing required arguments"
    usage
fi

echo "═══════════════════════════════════════════════════════════"
echo "  Post-Deployment Validation for $APP_NAME"
echo "═══════════════════════════════════════════════════════════"
echo "Auth Mode: $AUTH_MODE"
echo "Base URL: $BASE_URL"
if [ -n "$FRONTEND_PORT" ]; then
    echo "Frontend Port: $FRONTEND_PORT"
fi
if [ -n "$BACKEND_PORT" ]; then
    echo "Backend Port: $BACKEND_PORT"
fi
echo "═══════════════════════════════════════════════════════════"
echo ""

ERRORS=0
WARNINGS=0

# ═══════════════════════════════════════════════════════════
# Check 1: Docker Containers
# ═══════════════════════════════════════════════════════════
log_info "Check 1: Docker Containers"
echo "───────────────────────────────────────────────────────────"

RUNNING=$(docker ps --filter "name=${APP_NAME}" --format "{{.Names}}" 2>/dev/null | wc -l)

if [ "$RUNNING" -ge 1 ]; then
    log_success "Found $RUNNING running container(s) for $APP_NAME"
    docker ps --filter "name=${APP_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""

    # Check if containers are healthy (not restarting)
    RESTARTING=$(docker ps --filter "name=${APP_NAME}" --format "{{.Status}}" | grep -c "Restarting" || true)
    if [ "$RESTARTING" -gt 0 ]; then
        log_error "$RESTARTING container(s) are restarting - check logs"
        ERRORS=$((ERRORS + 1))
    fi
else
    log_error "No running containers found for $APP_NAME"
    log_error "Check: docker ps -a --filter \"name=${APP_NAME}\""
    log_error "Check logs: docker logs ${APP_NAME}-<service>"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# ═══════════════════════════════════════════════════════════
# Check 2: Local Container Access
# ═══════════════════════════════════════════════════════════
if [ -n "$FRONTEND_PORT" ]; then
    log_info "Check 2: Local Frontend Access (localhost:${FRONTEND_PORT})"
    echo "───────────────────────────────────────────────────────────"

    FRONTEND_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${FRONTEND_PORT}/ 2>/dev/null || echo "000")

    if [ "$FRONTEND_CODE" = "200" ] || [ "$FRONTEND_CODE" = "404" ]; then
        log_success "Frontend responding: HTTP $FRONTEND_CODE"
    elif [ "$FRONTEND_CODE" = "000" ]; then
        log_error "Frontend not responding (connection refused)"
        log_error "Check if container is running and port is correct"
        ERRORS=$((ERRORS + 1))
    else
        log_warning "Frontend returned HTTP $FRONTEND_CODE"
        WARNINGS=$((WARNINGS + 1))
    fi

    echo ""
fi

if [ -n "$BACKEND_PORT" ]; then
    log_info "Check 3: Local Backend Access (localhost:${BACKEND_PORT})"
    echo "───────────────────────────────────────────────────────────"

    # Try /docs (FastAPI docs) and /api/health endpoints
    BACKEND_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${BACKEND_PORT}/docs 2>/dev/null || echo "000")

    if [ "$BACKEND_CODE" = "200" ]; then
        log_success "Backend API responding: HTTP $BACKEND_CODE"
    elif [ "$BACKEND_CODE" = "000" ]; then
        log_error "Backend not responding (connection refused)"
        log_error "Check if container is running and port is correct"
        ERRORS=$((ERRORS + 1))
    else
        log_warning "Backend /docs returned HTTP $BACKEND_CODE"
        # Try alternative endpoint
        ALT_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${BACKEND_PORT}/ 2>/dev/null || echo "000")
        if [ "$ALT_CODE" = "200" ] || [ "$ALT_CODE" = "404" ]; then
            log_success "Backend root endpoint responding: HTTP $ALT_CODE"
        else
            WARNINGS=$((WARNINGS + 1))
        fi
    fi

    echo ""
fi

# ═══════════════════════════════════════════════════════════
# Check 4: Public HTTPS Access
# ═══════════════════════════════════════════════════════════
log_info "Check 4: Public HTTPS Access"
echo "───────────────────────────────────────────────────────────"

PUBLIC_URL="${BASE_URL}/${APP_NAME}/"
PUBLIC_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "$PUBLIC_URL" 2>/dev/null || echo "000")

log_info "Testing: $PUBLIC_URL"
log_info "Response: HTTP $PUBLIC_CODE"

if [ "$AUTH_MODE" = "none" ]; then
    # For no-auth apps, expect HTTP 200
    if [ "$PUBLIC_CODE" = "200" ]; then
        log_success "Public frontend accessible (no auth): HTTP $PUBLIC_CODE"
    else
        log_error "Public frontend not accessible: HTTP $PUBLIC_CODE (expected 200)"

        if [ "$PUBLIC_CODE" = "302" ]; then
            log_error "App is being redirected to login page"
            log_error "OAuth2 proxy is blocking access"
            log_error "Fix: bash automation/oauth2-proxy-register.sh add-skip-route $APP_NAME none"
        elif [ "$PUBLIC_CODE" = "404" ]; then
            log_error "Nginx location blocks may not be configured"
            log_error "Check: sudo grep -n \"location /${APP_NAME}/\" /etc/nginx/sites-available/auth-gateway"
        fi

        ERRORS=$((ERRORS + 1))
    fi
else
    # For authenticated apps, expect HTTP 302 redirect to login
    if [ "$PUBLIC_CODE" = "302" ]; then
        log_success "Auth redirect working: HTTP $PUBLIC_CODE"
    elif [ "$PUBLIC_CODE" = "200" ]; then
        log_warning "App is accessible without auth (HTTP 200) but auth_mode=$AUTH_MODE"
        log_warning "This may be intentional or indicate a configuration issue"
        WARNINGS=$((WARNINGS + 1))
    else
        log_error "Unexpected response: HTTP $PUBLIC_CODE"

        if [ "$PUBLIC_CODE" = "404" ]; then
            log_error "Nginx location blocks may not be configured"
        fi

        ERRORS=$((ERRORS + 1))
    fi
fi

echo ""

# ═══════════════════════════════════════════════════════════
# Check 5: Static Asset Loading (Next.js)
# ═══════════════════════════════════════════════════════════
log_info "Check 5: Static Asset Loading"
echo "───────────────────────────────────────────────────────────"

STATIC_URL="${BASE_URL}/${APP_NAME}/_next/static/"
CSS_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "$STATIC_URL" 2>/dev/null || echo "000")

log_info "Testing: $STATIC_URL"
log_info "Response: HTTP $CSS_CODE"

if [ "$CSS_CODE" = "200" ] || [ "$CSS_CODE" = "403" ] || [ "$CSS_CODE" = "404" ]; then
    log_success "Static assets accessible: HTTP $CSS_CODE"
elif [ "$CSS_CODE" = "302" ]; then
    log_error "Static assets blocked by auth: HTTP 302"
    log_error "This will cause pages to load without CSS"
    log_error "Check nginx static location block (should be BEFORE main location)"
    ERRORS=$((ERRORS + 1))
else
    log_warning "Static asset response: HTTP $CSS_CODE"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""

# ═══════════════════════════════════════════════════════════
# Check 6: Nginx Configuration
# ═══════════════════════════════════════════════════════════
log_info "Check 6: Nginx Configuration"
echo "───────────────────────────────────────────────────────────"

# Check location block
if sudo grep -q "location /${APP_NAME}/" /etc/nginx/sites-available/auth-gateway 2>/dev/null; then
    LOCATION_COUNT=$(sudo grep -c "location /${APP_NAME}/" /etc/nginx/sites-available/auth-gateway)
    log_success "Nginx location block(s) found: $LOCATION_COUNT"
else
    log_error "Nginx location block NOT found"
    log_error "Check: sudo grep -n \"location /${APP_NAME}/\" /etc/nginx/sites-available/auth-gateway"
    ERRORS=$((ERRORS + 1))
fi

# Check upstream
if sudo grep -q "upstream ${APP_NAME}_backend" /etc/nginx/sites-available/auth-gateway 2>/dev/null; then
    log_success "Nginx upstream defined"
else
    log_error "Nginx upstream NOT defined"
    log_error "Check: sudo grep -n \"upstream ${APP_NAME}_backend\" /etc/nginx/sites-available/auth-gateway"
    ERRORS=$((ERRORS + 1))
fi

# Test nginx syntax
if sudo nginx -t 2>&1 | grep -q "syntax is ok"; then
    log_success "Nginx configuration syntax valid"
else
    log_error "Nginx configuration has syntax errors"
    log_error "Check: sudo nginx -t"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# ═══════════════════════════════════════════════════════════
# Check 7: OAuth2 Proxy Configuration (for no-auth apps)
# ═══════════════════════════════════════════════════════════
if [ "$AUTH_MODE" = "none" ]; then
    log_info "Check 7: OAuth2 Proxy Configuration (No-Auth Mode)"
    echo "───────────────────────────────────────────────────────────"

    if sudo grep -q "skip_auth_routes" /etc/oauth2-proxy/config.cfg 2>/dev/null; then
        if sudo grep -q "^/${APP_NAME}/.*" /etc/oauth2-proxy/config.cfg 2>/dev/null; then
            log_success "OAuth2 skip route configured"
        else
            log_error "OAuth2 skip route NOT configured for $APP_NAME"
            log_error "This will cause HTTP 302 redirects instead of HTTP 200"
            log_error "Fix: bash automation/oauth2-proxy-register.sh add-skip-route $APP_NAME none"
            ERRORS=$((ERRORS + 1))
        fi
    else
        log_error "OAuth2 skip_auth_routes section not found"
        log_error "Fix: bash automation/oauth2-proxy-register.sh add-skip-route $APP_NAME none"
        ERRORS=$((ERRORS + 1))
    fi

    echo ""
fi

# ═══════════════════════════════════════════════════════════
# Validation Summary
# ═══════════════════════════════════════════════════════════
echo "═══════════════════════════════════════════════════════════"
echo "  Validation Summary"
echo "═══════════════════════════════════════════════════════════"

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    log_success "✅ All validation checks passed!"
    echo ""
    log_success "Deployment URL: $PUBLIC_URL"
    echo ""
    exit 0
elif [ $ERRORS -eq 0 ]; then
    log_warning "⚠️  Validation completed with $WARNINGS warning(s)"
    echo ""
    log_success "Deployment URL: $PUBLIC_URL"
    echo ""
    exit 0
else
    log_error "❌ Validation failed with $ERRORS error(s) and $WARNINGS warning(s)"
    echo ""
    echo "Common fixes:"
    echo "  • HTTP 302 on no-auth app:"
    echo "    bash automation/oauth2-proxy-register.sh add-skip-route $APP_NAME none"
    echo ""
    echo "  • HTTP 404 on public URL:"
    echo "    bash automation/nginx-configure-with-validation.sh $APP_NAME <frontend_port> <backend_port>"
    echo ""
    echo "  • Containers not running:"
    echo "    cd /home/ubuntu/deployments/$APP_NAME && docker-compose logs"
    echo ""
    echo "  • Rollback deployment:"
    echo "    bash automation/rollback.sh $APP_NAME"
    echo ""
    exit 1
fi
