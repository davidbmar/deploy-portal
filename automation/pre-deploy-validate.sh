#!/bin/bash
# pre-deploy-validate.sh - Validates project structure before deployment
# Checks for required files and directories, creates missing ones if needed

set -euo pipefail

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

echo "═══════════════════════════════════════════════════════════"
echo "  Pre-Deployment Validation"
echo "═══════════════════════════════════════════════════════════"
echo ""

ERRORS=0
WARNINGS=0
FIXES_APPLIED=0

# ═══════════════════════════════════════════════════════════
# Check Project Structure
# ═══════════════════════════════════════════════════════════
log_info "Checking project structure..."
echo "───────────────────────────────────────────────────────────"

# Check for docker-compose.yml
if [ -f "docker-compose.yml" ]; then
    log_success "✅ docker-compose.yml exists"
else
    log_error "❌ docker-compose.yml not found"
    ERRORS=$((ERRORS + 1))
fi

echo ""

# ═══════════════════════════════════════════════════════════
# Check Frontend Structure (Next.js)
# ═══════════════════════════════════════════════════════════
if [ -d "frontend" ]; then
    log_info "Checking frontend structure..."
    echo "───────────────────────────────────────────────────────────"

    log_success "✅ frontend/ directory exists"

    # Check for public directory (CRITICAL FIX #1)
    if [ ! -d "frontend/public" ]; then
        log_warning "⚠️  frontend/public/ missing - creating it"
        mkdir -p frontend/public
        touch frontend/public/.gitkeep
        log_success "✅ Created frontend/public/ directory"
        FIXES_APPLIED=$((FIXES_APPLIED + 1))
    else
        log_success "✅ frontend/public/ exists"
    fi

    # Check for next.config.js
    if [ -f "frontend/next.config.js" ]; then
        log_success "✅ frontend/next.config.js exists"

        # Check if basePath is configured
        if grep -q "basePath" frontend/next.config.js; then
            log_success "✅ basePath configured in next.config.js"
        else
            log_warning "⚠️  basePath not found in next.config.js"
            log_warning "   This may cause routing issues in subpath deployments"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        log_warning "⚠️  frontend/next.config.js not found"
        log_warning "   This may be a non-Next.js frontend"
        WARNINGS=$((WARNINGS + 1))
    fi

    # Check for package.json
    if [ -f "frontend/package.json" ]; then
        log_success "✅ frontend/package.json exists"
    else
        log_error "❌ frontend/package.json not found"
        ERRORS=$((ERRORS + 1))
    fi

    # Check for Dockerfile
    if [ -f "frontend/Dockerfile" ]; then
        log_success "✅ frontend/Dockerfile exists"

        # Check if Dockerfile copies public directory correctly
        if grep -q "COPY.*public" frontend/Dockerfile; then
            log_success "✅ Dockerfile copies public directory"
        fi
    else
        log_warning "⚠️  frontend/Dockerfile not found"
        WARNINGS=$((WARNINGS + 1))
    fi

    echo ""
else
    log_warning "⚠️  frontend/ directory not found"
    log_warning "   This may not be a frontend+backend app"
    WARNINGS=$((WARNINGS + 1))
    echo ""
fi

# ═══════════════════════════════════════════════════════════
# Check Backend Structure
# ═══════════════════════════════════════════════════════════
if [ -d "backend" ]; then
    log_info "Checking backend structure..."
    echo "───────────────────────────────────────────────────────────"

    log_success "✅ backend/ directory exists"

    # Check for main application file
    if [ -f "backend/main.py" ] || [ -f "backend/app.py" ] || [ -f "backend/server.py" ]; then
        log_success "✅ Backend application file found"
    else
        log_warning "⚠️  Backend application file not found (main.py, app.py, or server.py)"
        WARNINGS=$((WARNINGS + 1))
    fi

    # Check for requirements.txt (Python)
    if [ -f "backend/requirements.txt" ]; then
        log_success "✅ backend/requirements.txt exists"
    elif [ -f "backend/package.json" ]; then
        log_success "✅ backend/package.json exists (Node.js backend)"
    else
        log_warning "⚠️  No requirements.txt or package.json found"
        WARNINGS=$((WARNINGS + 1))
    fi

    # Check for Dockerfile
    if [ -f "backend/Dockerfile" ]; then
        log_success "✅ backend/Dockerfile exists"
    else
        log_warning "⚠️  backend/Dockerfile not found"
        WARNINGS=$((WARNINGS + 1))
    fi

    echo ""
else
    log_warning "⚠️  backend/ directory not found"
    log_warning "   This may be a frontend-only app"
    WARNINGS=$((WARNINGS + 1))
    echo ""
fi

# ═══════════════════════════════════════════════════════════
# Check Environment Configuration
# ═══════════════════════════════════════════════════════════
log_info "Checking environment configuration..."
echo "───────────────────────────────────────────────────────────"

if [ -f ".env.example" ]; then
    log_success "✅ .env.example exists"
else
    log_warning "⚠️  .env.example not found"
    log_warning "   Consider creating one for documentation"
    WARNINGS=$((WARNINGS + 1))
fi

if [ -f ".env" ]; then
    log_warning "⚠️  .env file exists in project root"
    log_warning "   This should not be committed to git"
    log_warning "   It should be created on the server during deployment"
fi

echo ""

# ═══════════════════════════════════════════════════════════
# Check Docker Compose Configuration
# ═══════════════════════════════════════════════════════════
if [ -f "docker-compose.yml" ]; then
    log_info "Checking docker-compose.yml configuration..."
    echo "───────────────────────────────────────────────────────────"

    # Check for services
    SERVICES=$(grep -c "^  [a-z]" docker-compose.yml || true)
    if [ "$SERVICES" -gt 0 ]; then
        log_success "✅ Found $SERVICES service(s) in docker-compose.yml"
    else
        log_error "❌ No services found in docker-compose.yml"
        ERRORS=$((ERRORS + 1))
    fi

    # Check for port mappings
    if grep -q "ports:" docker-compose.yml; then
        log_success "✅ Port mappings configured"
    else
        log_warning "⚠️  No port mappings found"
        WARNINGS=$((WARNINGS + 1))
    fi

    # Check for volumes
    if grep -q "volumes:" docker-compose.yml; then
        log_success "✅ Volumes configured"
    fi

    echo ""
fi

# ═══════════════════════════════════════════════════════════
# Check Git Configuration
# ═══════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════
# Check Next.js Environment Variables
# ═══════════════════════════════════════════════════════════
log_info "Checking Next.js environment variables..."
echo "───────────────────────────────────────────────────────────"

ENV_ISSUES=0

# Check frontend/.env.local
if [ -f "frontend/.env.local" ]; then
    log_info "Found frontend/.env.local"
    
    if grep -q "localhost" frontend/.env.local; then
        log_error "❌ frontend/.env.local contains localhost URLs"
        log_error "   This will OVERRIDE docker-compose.yml during build"
        log_error "   Causing 'Failed to fetch' errors in production"
        echo ""
        log_error "   Current content:"
        grep "NEXT_PUBLIC" frontend/.env.local | sed 's/^/   /'
        echo ""
        log_error "   FIX: Update to use HTTPS URL for cloud deployment"
        log_error "   Example: NEXT_PUBLIC_API_URL=https://your-domain.com/app-name"
        ERRORS=$((ERRORS + 1))
        ENV_ISSUES=$((ENV_ISSUES + 1))
    fi
fi

# Check NEXT_PUBLIC_API_URL format in docker-compose.yml
if [ -f "docker-compose.yml" ]; then
    API_URL=$(grep "NEXT_PUBLIC_API_URL=" docker-compose.yml | head -1 | cut -d'=' -f2-)
    
    if [ ! -z "$API_URL" ]; then
        log_info "Found NEXT_PUBLIC_API_URL: $API_URL"
        
        # Check for /api suffix (causes double prefix)
        if [[ "$API_URL" == *"/api"* ]]; then
            log_error "❌ NEXT_PUBLIC_API_URL should NOT end with /api"
            log_error "   Current: $API_URL"
            log_error "   Should be: ${API_URL%/api*}"
            log_error "   Frontend code automatically appends /api/"
            log_error "   This causes double /api/api/ prefix → 404 errors"
            ERRORS=$((ERRORS + 1))
            ENV_ISSUES=$((ENV_ISSUES + 1))
        fi
        
        # Check for HTTP (not HTTPS) in cloud deployment
        if [[ "$API_URL" == "http://"* ]] && [[ "$API_URL" != *"localhost"* ]]; then
            log_error "❌ NEXT_PUBLIC_API_URL uses HTTP (should be HTTPS)"
            log_error "   Current: $API_URL"
            log_error "   Should be: ${API_URL/http:/https:}"
            log_error "   Browsers block HTTP requests from HTTPS pages"
            ERRORS=$((ERRORS + 1))
            ENV_ISSUES=$((ENV_ISSUES + 1))
        fi
        
        if [ $ENV_ISSUES -eq 0 ]; then
            log_success "✅ NEXT_PUBLIC_API_URL format is valid"
        fi
    fi
fi

if [ $ENV_ISSUES -eq 0 ]; then
    log_success "✅ Environment variables validated"
else
    log_error "❌ Found $ENV_ISSUES environment issue(s) - fix before deploying"
fi

echo ""
log_info "Checking git configuration..."
echo "───────────────────────────────────────────────────────────"

if [ -d ".git" ]; then
    log_success "✅ Git repository initialized"

    # Check .gitignore
    if [ -f ".gitignore" ]; then
        log_success "✅ .gitignore exists"

        # Check if important files are ignored
        if grep -q ".env" .gitignore && grep -q "node_modules" .gitignore; then
            log_success "✅ .gitignore configured correctly"
        else
            log_warning "⚠️  .gitignore may be missing important entries"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        log_warning "⚠️  .gitignore not found"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    log_warning "⚠️  Not a git repository"
    WARNINGS=$((WARNINGS + 1))
fi

echo ""

# ═══════════════════════════════════════════════════════════
# Validation Summary
# ═══════════════════════════════════════════════════════════
echo "═══════════════════════════════════════════════════════════"
echo "  Validation Summary"
echo "═══════════════════════════════════════════════════════════"

if [ $FIXES_APPLIED -gt 0 ]; then
    log_success "✅ Applied $FIXES_APPLIED automatic fix(es)"
fi

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    log_success "✅ Pre-deployment validation passed!"
    log_success "   Ready to deploy"
    echo ""
    exit 0
elif [ $ERRORS -eq 0 ]; then
    log_warning "⚠️  Validation completed with $WARNINGS warning(s)"
    log_warning "   Deployment can proceed, but review warnings"
    echo ""
    exit 0
else
    log_error "❌ Validation failed with $ERRORS error(s) and $WARNINGS warning(s)"
    echo ""
    echo "Critical issues found. Please fix before deploying:"
    echo ""

    if [ ! -f "docker-compose.yml" ]; then
        echo "  • docker-compose.yml is missing"
    fi

    if [ -d "frontend" ] && [ ! -f "frontend/package.json" ]; then
        echo "  • frontend/package.json is missing"
    fi

    if [ -d "backend" ] && [ ! -f "backend/requirements.txt" ] && [ ! -f "backend/package.json" ]; then
        echo "  • backend/requirements.txt or package.json is missing"
    fi

    echo ""
    exit 1
fi
