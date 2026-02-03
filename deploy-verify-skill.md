name: deploy-verify
version: DEPLOY_VERIFY_VERSION_PLACEHOLDER
description: |
  Post-deployment verification skill that checks BOTH portal health and deployed
  application functionality. Verifies content is real (not default/error pages),
  containers are running, nginx routing works, and helps diagnose failures.

  v20260202.010000: Enhanced SPA detection - recognizes React, Vue, Vite, Next.js
  apps and correctly validates them without false positives about response size.

commands:
  - name: deploy-verify
    description: Verify portal and deployed app are working correctly
    instructions: |
      # Capsule Cloud Post-Deployment Verification Skill

      You are a deployment verification assistant. This skill runs AFTER `/deploy` to verify:
      - **Section A**: Portal itself is healthy and showing real content
      - **Section B**: Deployed application is working with actual content

      ## Phase 1: Auto-Update Check (MVP: Skip for now)

      **NOTE**: Auto-update is not yet implemented. Skip to Phase 2.

      Future implementation will:
      1. Query portal version API: `curl -s https://{portal_host}/api/deployment/version`
      2. Compare skill version vs portal version
      3. Auto-update if portal version is newer
      4. For now, proceed directly to testing

      ## Phase 2: Determine What to Test

      ### 2.1 Get Portal Host
      First, find the portal host URL. Try these methods in order:

      **Method 1**: From deployment ZIP config
      ```bash
      # Find latest deployment kit
      PORTAL_HOST=$(find . -maxdepth 1 -name "deployment-kit-*.zip" -type f | head -1 | xargs -I{} unzip -p {} "*/config.json" | grep -o '"ec2_host": "[^"]*"' | cut -d'"' -f4)
      ```

      **Method 2**: From recent deployment state (if exists)
      ```bash
      # Check for saved deployment state
      if [ -f ~/.claude/deployments/latest.json ]; then
        PORTAL_HOST=$(jq -r '.portal_host' ~/.claude/deployments/latest.json)
      fi
      ```

      **Method 3**: Ask user
      If portal host cannot be determined, ask user:
      - "What is your Capsule Cloud portal URL?"
      - Example: `something.ai.internal.capsule.com`

      ### 2.2 Get App Name (if testing deployed app)
      Determine which app to verify:

      **If user provided app name**: Use it directly
      ```bash
      APP_NAME="$1"  # From: /deploy-verify my-app
      ```

      **If no app name provided**: Test portal only OR auto-detect last deployed app
      ```bash
      # Option 1: Look for recent deployment state
      if [ -f ~/.claude/deployments/latest.json ]; then
        APP_NAME=$(jq -r '.app_name' ~/.claude/deployments/latest.json)
        echo "Auto-detected last deployed app: $APP_NAME"
        # Ask user: "Verify $APP_NAME? [Y/n/skip]"
      else
        echo "No app name provided. Testing portal health only."
        APP_NAME=""
      fi
      ```

      ## Phase 3: Test Deployment Portal Health (Section A)

      **ALWAYS run these tests first to verify the portal itself is healthy.**

      Display header:
      ```
      ═══════════════════════════════════════════════════════════════════
                        SECTION A: PORTAL HEALTH CHECK
      ═══════════════════════════════════════════════════════════════════
      ```

      ### Test A1: Portal Homepage
      Verify homepage shows actual Capsule Cloud content:

      ```bash
      PORTAL_URL="https://$PORTAL_HOST"

      # Test HTTPS homepage
      RESPONSE=$(curl -k -s "$PORTAL_URL/")
      HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "$PORTAL_URL/")
      RESPONSE_SIZE=$(echo "$RESPONSE" | wc -c | tr -d ' ')

      echo "[A1] Portal Homepage"
      echo "  URL: $PORTAL_URL/"
      echo "  HTTP Status: $HTTP_CODE"
      echo "  Response Size: $RESPONSE_SIZE bytes"

      # Check for actual content vs default pages
      if echo "$RESPONSE" | grep -q "Welcome to nginx"; then
        echo "  ✗ FAIL - Shows nginx default page"
        PORTAL_HOMEPAGE_PASS=false
      elif echo "$RESPONSE" | grep -q "404 Not Found"; then
        echo "  ✗ FAIL - Shows 404 error"
        PORTAL_HOMEPAGE_PASS=false
      elif echo "$RESPONSE" | grep -q "Capsule Cloud"; then
        echo "  ✓ PASS - Shows Capsule Cloud content"
        PORTAL_HOMEPAGE_PASS=true

        # Check for specific elements
        if echo "$RESPONSE" | grep -q "Your Personal Development Platform\|Your Apps"; then
          echo "  ✓ Found: Expected page elements"
        fi
      else
        echo "  ⚠ WARNING - Unknown content (not nginx default, not Capsule Cloud)"
        PORTAL_HOMEPAGE_PASS=false
      fi
      ```

      ### Test A2: Portal /deploy/ Page
      Verify deployment access page works:

      ```bash
      echo "[A2] Portal Deployment Page"
      DEPLOY_RESPONSE=$(curl -k -s "$PORTAL_URL/deploy/")
      DEPLOY_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "$PORTAL_URL/deploy/")

      echo "  URL: $PORTAL_URL/deploy/"
      echo "  HTTP Status: $DEPLOY_CODE"

      if [ "$DEPLOY_CODE" = "200" ]; then
        if echo "$DEPLOY_RESPONSE" | grep -q "Cloud Deployment Access\|Claude Deployment Access"; then
          echo "  ✓ PASS - Shows deployment access page"
          PORTAL_DEPLOY_PASS=true
        else
          echo "  ✗ FAIL - Missing expected content"
          PORTAL_DEPLOY_PASS=false
        fi
      else
        echo "  ✗ FAIL - Page not accessible (HTTP $DEPLOY_CODE)"
        PORTAL_DEPLOY_PASS=false
      fi
      ```

      ### Test A3: Portal /deploy/apps Page
      Verify app catalog page works:

      ```bash
      echo "[A3] Portal App Catalog"
      APPS_RESPONSE=$(curl -k -s "$PORTAL_URL/deploy/apps")
      APPS_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "$PORTAL_URL/deploy/apps")

      echo "  URL: $PORTAL_URL/deploy/apps"
      echo "  HTTP Status: $APPS_CODE"

      if [ "$APPS_CODE" = "200" ]; then
        if echo "$APPS_RESPONSE" | grep -q "Your Apps"; then
          echo "  ✓ PASS - Shows app catalog"
          PORTAL_APPS_PASS=true
        else
          echo "  ✗ FAIL - Missing 'Your Apps' content"
          PORTAL_APPS_PASS=false
        fi
      else
        echo "  ✗ FAIL - Page not accessible (HTTP $APPS_CODE)"
        PORTAL_APPS_PASS=false
      fi
      ```

      ### Test A4: HTTP Access
      Verify HTTP endpoint works (may redirect to HTTPS):

      ```bash
      echo "[A4] HTTP Access"
      HTTP_URL="http://$PORTAL_HOST"
      HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$HTTP_URL/" 2>/dev/null)

      echo "  URL: $HTTP_URL/"
      echo "  HTTP Status: $HTTP_CODE"

      if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
        echo "  ✓ PASS - HTTP accessible"
        PORTAL_HTTP_PASS=true
      else
        echo "  ⚠ WARNING - HTTP not working (this may be intentional)"
        PORTAL_HTTP_PASS=false
      fi
      ```

      ### Portal Health Summary
      ```bash
      echo ""
      echo "───────────────────────────────────────────────────────────────────"
      echo "Portal Health Summary:"

      if [ "$PORTAL_HOMEPAGE_PASS" = true ] && [ "$PORTAL_DEPLOY_PASS" = true ] && [ "$PORTAL_APPS_PASS" = true ]; then
        echo "  ✓ PORTAL HEALTHY - All pages showing correct content"
        PORTAL_HEALTHY=true
      else
        echo "  ✗ PORTAL ISSUES DETECTED"
        PORTAL_HEALTHY=false

        # Show what failed
        [ "$PORTAL_HOMEPAGE_PASS" = false ] && echo "    ✗ Homepage not showing Capsule Cloud content"
        [ "$PORTAL_DEPLOY_PASS" = false ] && echo "    ✗ /deploy/ page not showing deployment access"
        [ "$PORTAL_APPS_PASS" = false ] && echo "    ✗ /deploy/apps not showing app catalog"

        echo ""
        echo "⚠ STOPPING: Portal health check failed. Fix portal issues before testing apps."
        exit 1
      fi
      ```

      **If portal health check fails, STOP here and do not proceed to Section B.**

      ## Phase 4: Test Deployed Application (Section B)

      **Only run if app name was provided or auto-detected.**

      If no app to test, skip to Phase 6 (Final Report).

      Display header:
      ```
      ═══════════════════════════════════════════════════════════════════
                    SECTION B: DEPLOYED APPLICATION CHECK
      ═══════════════════════════════════════════════════════════════════

      Testing app: $APP_NAME
      ```

      ### 4.1 Get App Deployment Info
      Read deployment configuration:

      ```bash
      # Try to find deployment config
      CONFIG_FILE=""

      # Method 1: From deployment-kit ZIP
      ZIP_FILE=$(find . -maxdepth 1 -name "deployment-kit-${APP_NAME}-*.zip" -type f | head -1)
      if [ -n "$ZIP_FILE" ]; then
        # Extract config from ZIP
        TEMP_DIR=$(mktemp -d)
        unzip -q "$ZIP_FILE" -d "$TEMP_DIR"
        CONFIG_FILE=$(find "$TEMP_DIR" -name "config.json" | head -1)
      fi

      # Method 2: From extracted deployment-kit directory
      if [ -z "$CONFIG_FILE" ] && [ -d "deployment-kit-${APP_NAME}" ]; then
        CONFIG_FILE="deployment-kit-${APP_NAME}/config.json"
      fi

      # Method 3: From saved deployment state
      if [ -z "$CONFIG_FILE" ] && [ -f ~/.claude/deployments/${APP_NAME}.json ]; then
        CONFIG_FILE=~/.claude/deployments/${APP_NAME}.json
      fi

      # Parse deployment config
      if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
        APP_PATH=$(jq -r '.app_path // .location_path' "$CONFIG_FILE")
        APP_PORT=$(jq -r '.app_port // .port' "$CONFIG_FILE")
        SSH_USER=$(jq -r '.ssh_user // .ec2_user' "$CONFIG_FILE")
        SSH_KEY=$(jq -r '.ssh_key // .pem_file' "$CONFIG_FILE")

        echo "Deployment config found:"
        echo "  App path: /$APP_PATH/"
        echo "  App port: $APP_PORT"
      else
        echo "⚠ WARNING: No deployment config found for $APP_NAME"
        echo "  Cannot determine app path or port"
        echo "  Will attempt basic tests only"
        APP_PATH="$APP_NAME"  # Guess
      fi
      ```

      ### Test B1: Container Status
      Check if Docker containers are running:

      ```bash
      echo ""
      echo "[B1] Container Status"

      if [ -n "$SSH_USER" ] && [ -n "$SSH_KEY" ]; then
        # SSH to server and check containers
        CONTAINER_STATUS=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${SSH_USER}@${PORTAL_HOST}" \
          "cd ~/deployments/${APP_NAME} 2>/dev/null && docker-compose ps 2>/dev/null || echo 'NOT_FOUND'")

        if echo "$CONTAINER_STATUS" | grep -q "NOT_FOUND"; then
          echo "  ✗ FAIL - Deployment directory not found on server"
          CONTAINER_PASS=false
        elif echo "$CONTAINER_STATUS" | grep -q "Up"; then
          echo "  ✓ PASS - Containers are running"
          CONTAINER_PASS=true
          # Show container details
          echo "$CONTAINER_STATUS" | grep "Up" | while read line; do
            echo "    $line"
          done
        else
          echo "  ✗ FAIL - Containers not running"
          CONTAINER_PASS=false
          echo "  Status:"
          echo "$CONTAINER_STATUS" | head -5 | sed 's/^/    /'
        fi
      else
        echo "  ⚠ SKIP - No SSH credentials available"
        CONTAINER_PASS=null
      fi
      ```

      ### Test B2: Container Logs
      Check for errors in container logs:

      ```bash
      echo ""
      echo "[B2] Container Logs (Last 20 lines)"

      if [ -n "$SSH_USER" ] && [ -n "$SSH_KEY" ] && [ "$CONTAINER_PASS" != false ]; then
        LOGS=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${SSH_USER}@${PORTAL_HOST}" \
          "cd ~/deployments/${APP_NAME} 2>/dev/null && docker-compose logs --tail=20 2>&1")

        # Check for common error patterns
        if echo "$LOGS" | grep -qi "error\|exception\|failed\|fatal"; then
          echo "  ⚠ WARNING - Errors found in logs:"
          echo "$LOGS" | grep -i "error\|exception\|failed\|fatal" | head -5 | sed 's/^/    /'
          LOGS_PASS=false
        else
          echo "  ✓ PASS - No errors detected in recent logs"
          LOGS_PASS=true
        fi
      else
        echo "  ⚠ SKIP - Cannot access container logs"
        LOGS_PASS=null
      fi
      ```

      ### Test B3: Nginx Configuration
      Verify nginx config is valid and has location block for app:

      ```bash
      echo ""
      echo "[B3] Nginx Configuration"

      if [ -n "$SSH_USER" ] && [ -n "$SSH_KEY" ]; then
        # Check nginx config syntax
        NGINX_TEST=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${SSH_USER}@${PORTAL_HOST}" \
          "sudo nginx -t 2>&1")

        if echo "$NGINX_TEST" | grep -q "test is successful"; then
          echo "  ✓ PASS - Nginx config is valid"
          NGINX_VALID=true
        else
          echo "  ✗ FAIL - Nginx config has errors:"
          echo "$NGINX_TEST" | sed 's/^/    /'
          NGINX_VALID=false
        fi

        # Check for location block
        LOCATION_BLOCK=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${SSH_USER}@${PORTAL_HOST}" \
          "sudo cat /etc/nginx/conf.d/routes/${APP_NAME}.conf 2>/dev/null || echo 'NOT_FOUND'")

        if echo "$LOCATION_BLOCK" | grep -q "NOT_FOUND"; then
          echo "  ⚠ WARNING - No nginx route config found for $APP_NAME"
          echo "    Expected: /etc/nginx/conf.d/routes/${APP_NAME}.conf"
          NGINX_ROUTE=false
        elif echo "$LOCATION_BLOCK" | grep -q "location.*/${APP_PATH}/"; then
          echo "  ✓ PASS - Nginx route configured for /${APP_PATH}/"
          NGINX_ROUTE=true

          # Show proxy_pass target
          PROXY_TARGET=$(echo "$LOCATION_BLOCK" | grep "proxy_pass" | head -1 | sed 's/^[[:space:]]*//')
          echo "    $PROXY_TARGET"
        else
          echo "  ⚠ WARNING - Route config exists but may not match app path"
          NGINX_ROUTE=false
        fi
      else
        echo "  ⚠ SKIP - No SSH credentials available"
        NGINX_VALID=null
        NGINX_ROUTE=null
      fi
      ```

      ### Test B4: Application Endpoint (HTTPS)
      Test the deployed app's HTTPS endpoint:

      ```bash
      echo ""
      echo "[B4] Application Endpoint (HTTPS)"

      APP_URL="https://${PORTAL_HOST}/${APP_PATH}/"
      APP_RESPONSE=$(curl -k -s "$APP_URL")
      APP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "$APP_URL")
      APP_SIZE=$(echo "$APP_RESPONSE" | wc -c | tr -d ' ')

      echo "  URL: $APP_URL"
      echo "  HTTP Status: $APP_CODE"
      echo "  Response Size: $APP_SIZE bytes"

      # Check status code
      if [ "$APP_CODE" = "200" ]; then
        echo "  ✓ Endpoint is accessible"
        APP_ACCESSIBLE=true
      elif [ "$APP_CODE" = "404" ]; then
        echo "  ✗ FAIL - 404 Not Found (nginx route may be misconfigured)"
        APP_ACCESSIBLE=false
      elif [ "$APP_CODE" = "502" ]; then
        echo "  ✗ FAIL - 502 Bad Gateway (container may not be running)"
        APP_ACCESSIBLE=false
      elif [ "$APP_CODE" = "503" ]; then
        echo "  ✗ FAIL - 503 Service Unavailable (container starting or crashed)"
        APP_ACCESSIBLE=false
      else
        echo "  ⚠ WARNING - Unexpected status: $APP_CODE"
        APP_ACCESSIBLE=false
      fi

      # Check for default/error pages
      if [ "$APP_ACCESSIBLE" = true ]; then
        if echo "$APP_RESPONSE" | grep -q "Welcome to nginx"; then
          echo "  ✗ FAIL - Shows nginx default page (not app content)"
          APP_REAL_CONTENT=false
        elif echo "$APP_RESPONSE" | grep -q "502 Bad Gateway\|503 Service Unavailable"; then
          echo "  ✗ FAIL - Shows error page"
          APP_REAL_CONTENT=false
        elif [ "$APP_SIZE" -lt 500 ]; then
          echo "  ⚠ WARNING - Response very small ($APP_SIZE bytes) - may be error/default page"
          APP_REAL_CONTENT=false
        else
          echo "  ✓ PASS - App is returning content"
          APP_REAL_CONTENT=true
        fi
      else
        APP_REAL_CONTENT=false
      fi
      ```

      ### Test B5: Check for Actual App Content
      Verify response contains real app content, not default/intro pages.
      Smart detection for modern SPAs (React, Vue, Vite, Next.js, etc.):

      ```bash
      echo ""
      echo "[B5] Content Verification"

      if [ "$APP_REAL_CONTENT" = true ]; then
        # First, check if this is a modern SPA (Single Page Application)
        IS_SPA=false
        SPA_TYPE=""

        # Detect React/Vite apps
        if echo "$APP_RESPONSE" | grep -q "type=\"module\".*crossorigin.*src="; then
          IS_SPA=true
          SPA_TYPE="React/Vite"
        fi

        # Detect Next.js apps
        if echo "$APP_RESPONSE" | grep -q "_next/static\|__NEXT_DATA__"; then
          IS_SPA=true
          SPA_TYPE="Next.js"
        fi

        # Detect Vue apps
        if echo "$APP_RESPONSE" | grep -q "id=\"app\"\|id=\"root\"" && echo "$APP_RESPONSE" | grep -q "\.js"; then
          IS_SPA=true
          [ -z "$SPA_TYPE" ] && SPA_TYPE="Vue/SPA"
        fi

        # Detect Create React App
        if echo "$APP_RESPONSE" | grep -q "root\"\|app\"" && echo "$APP_RESPONSE" | grep -q "static/js\|static/css"; then
          IS_SPA=true
          [ -z "$SPA_TYPE" ] && SPA_TYPE="Create React App"
        fi

        # Check if JavaScript bundles are properly referenced with correct path
        JS_ASSETS_REFERENCED=false
        if echo "$APP_RESPONSE" | grep -q "src=\"/${APP_PATH}/.*\.js\|href=\"/${APP_PATH}/.*\.css"; then
          JS_ASSETS_REFERENCED=true
        fi

        # For SPAs, verify they have proper structure
        if [ "$IS_SPA" = true ]; then
          echo "  ✓ DETECTED: $SPA_TYPE application"

          if [ "$JS_ASSETS_REFERENCED" = true ]; then
            echo "  ✓ PASS - JavaScript bundles referenced with correct base path"
            APP_HAS_CONTENT=true
          else
            echo "  ⚠ WARNING - SPA detected but assets may have incorrect paths"
            APP_HAS_CONTENT=partial
          fi

          # Check for meaningful title/description
          if echo "$APP_RESPONSE" | grep -q "<title>.*</title>" && ! echo "$APP_RESPONSE" | grep -qi "<title>React App</title>\|<title>Vite App</title>"; then
            APP_TITLE=$(echo "$APP_RESPONSE" | grep -o "<title>[^<]*</title>" | sed 's/<[^>]*>//g' | head -1)
            echo "  ✓ App title: \"$APP_TITLE\""
          fi

          # For SPAs, small HTML is normal and expected
          if [ "$APP_SIZE" -lt 2000 ]; then
            echo "  ℹ INFO - Minimal HTML ($APP_SIZE bytes) is normal for SPAs"
          fi

        else
          # Traditional server-rendered app - check response size
          DEFAULT_INDICATORS=false

          if echo "$APP_RESPONSE" | grep -qi "Hello World"; then
            echo "  ⚠ WARNING - Contains 'Hello World' - may be default page"
            DEFAULT_INDICATORS=true
          fi

          if echo "$APP_RESPONSE" | grep -qi "Welcome to.*App\|Getting Started\|Quick Start"; then
            echo "  ⚠ WARNING - Contains intro text - may be starter page"
            DEFAULT_INDICATORS=true
          fi

          # For traditional apps, small responses are suspicious
          if [ "$APP_SIZE" -lt 2000 ]; then
            echo "  ⚠ WARNING - Small response ($APP_SIZE bytes) - may lack real content"
            APP_HAS_CONTENT=false
          elif [ "$DEFAULT_INDICATORS" = true ]; then
            echo "  ⚠ WARNING - App may be showing default/intro page"
            echo "  → Verify manually: $APP_URL"
            APP_HAS_CONTENT=partial
          else
            echo "  ✓ PASS - Response size indicates real content ($APP_SIZE bytes)"
            APP_HAS_CONTENT=true
          fi
        fi
      else
        echo "  ✗ SKIP - App endpoint not accessible"
        APP_HAS_CONTENT=false
      fi
      ```

      ### Test B6: Static Assets
      Test if CSS/JS files load (smart detection for modern bundlers):

      ```bash
      echo ""
      echo "[B6] Static Assets"

      ASSETS_FOUND=false
      ASSETS_TESTED=0

      # Method 1: Extract actual asset paths from HTML response
      if [ "$IS_SPA" = true ] && [ -n "$APP_RESPONSE" ]; then
        # Extract JavaScript file path from HTML
        JS_PATH=$(echo "$APP_RESPONSE" | grep -o "src=\"/${APP_PATH}/[^\"]*\.js\"" | head -1 | cut -d'"' -f2)
        CSS_PATH=$(echo "$APP_RESPONSE" | grep -o "href=\"/${APP_PATH}/[^\"]*\.css\"" | head -1 | cut -d'"' -f2)

        if [ -n "$JS_PATH" ]; then
          JS_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "https://${PORTAL_HOST}${JS_PATH}" 2>/dev/null)
          ASSETS_TESTED=$((ASSETS_TESTED + 1))
          if [ "$JS_CODE" = "200" ]; then
            JS_FILE=$(basename "$JS_PATH")
            echo "  ✓ JavaScript bundle loading ($JS_FILE: 200)"
            ASSETS_FOUND=true
          else
            echo "  ✗ JavaScript bundle not loading ($JS_CODE)"
          fi
        fi

        if [ -n "$CSS_PATH" ]; then
          CSS_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "https://${PORTAL_HOST}${CSS_PATH}" 2>/dev/null)
          ASSETS_TESTED=$((ASSETS_TESTED + 1))
          if [ "$CSS_CODE" = "200" ]; then
            CSS_FILE=$(basename "$CSS_PATH")
            echo "  ✓ CSS bundle loading ($CSS_FILE: 200)"
            ASSETS_FOUND=true
          else
            echo "  ✗ CSS bundle not loading ($CSS_CODE)"
          fi
        fi
      fi

      # Method 2: Try common static asset paths (fallback for traditional apps)
      if [ "$ASSETS_TESTED" -eq 0 ]; then
        CSS_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "https://${PORTAL_HOST}/${APP_PATH}/static/css/main.css" 2>/dev/null)
        JS_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "https://${PORTAL_HOST}/${APP_PATH}/static/js/main.js" 2>/dev/null)

        if [ "$CSS_CODE" = "200" ]; then
          echo "  ✓ CSS files loading (main.css: 200)"
          ASSETS_FOUND=true
        fi

        if [ "$JS_CODE" = "200" ]; then
          echo "  ✓ JS files loading (main.js: 200)"
          ASSETS_FOUND=true
        fi
      fi

      if [ "$ASSETS_FOUND" = false ] && [ "$ASSETS_TESTED" -eq 0 ]; then
        echo "  ℹ INFO - No static assets found at default paths"
        echo "    (This may be normal if app uses different asset structure)"
      fi
      ```

      ## Phase 5: Root Cause Analysis (If Failures Detected)

      If any tests failed, provide diagnostic information:

      ```bash
      # Aggregate all test results
      FAILURES_DETECTED=false

      if [ "$CONTAINER_PASS" = false ] || [ "$NGINX_VALID" = false ] || \
         [ "$APP_ACCESSIBLE" = false ] || [ "$APP_REAL_CONTENT" = false ]; then
        FAILURES_DETECTED=true
      fi

      if [ "$FAILURES_DETECTED" = true ]; then
        echo ""
        echo "═══════════════════════════════════════════════════════════════════"
        echo "                    ROOT CAUSE ANALYSIS"
        echo "═══════════════════════════════════════════════════════════════════"
        echo ""

        # Container failures
        if [ "$CONTAINER_PASS" = false ]; then
          echo "ISSUE: Containers not running"
          echo ""
          echo "Possible causes:"
          echo "  1. Port conflict - another service using port $APP_PORT"
          echo "  2. Container crashed on startup - check logs"
          echo "  3. docker-compose.yml syntax error"
          echo "  4. Missing environment variables"
          echo ""
          echo "Troubleshooting steps:"
          echo "  • Check container logs:"
          echo "    ssh -i $SSH_KEY ${SSH_USER}@${PORTAL_HOST}"
          echo "    cd ~/deployments/${APP_NAME}"
          echo "    docker-compose logs"
          echo ""
          echo "  • Check port conflicts:"
          echo "    sudo netstat -tulpn | grep $APP_PORT"
          echo ""
          echo "  • Restart containers:"
          echo "    docker-compose down && docker-compose up -d"
          echo ""
        fi

        # Nginx failures
        if [ "$NGINX_VALID" = false ]; then
          echo "ISSUE: Nginx configuration invalid"
          echo ""
          echo "Possible causes:"
          echo "  1. Syntax error in nginx config"
          echo "  2. Conflicting location blocks"
          echo "  3. Invalid proxy_pass directive"
          echo ""
          echo "Troubleshooting steps:"
          echo "  • Test nginx config:"
          echo "    sudo nginx -t"
          echo ""
          echo "  • Check nginx error log:"
          echo "    sudo tail -50 /var/log/nginx/error.log"
          echo ""
          echo "  • Verify route config:"
          echo "    sudo cat /etc/nginx/conf.d/routes/${APP_NAME}.conf"
          echo ""
        fi

        # Endpoint accessibility failures
        if [ "$APP_ACCESSIBLE" = false ]; then
          echo "ISSUE: Application endpoint not accessible"
          echo ""
          if [ "$APP_CODE" = "404" ]; then
            echo "Diagnosis: 404 Not Found"
            echo "  → Nginx location block may be missing or misconfigured"
            echo "  → Check: /etc/nginx/conf.d/routes/${APP_NAME}.conf"
            echo ""
          elif [ "$APP_CODE" = "502" ]; then
            echo "Diagnosis: 502 Bad Gateway"
            echo "  → Nginx cannot reach the backend container"
            echo "  → Container may not be running on expected port"
            echo "  → Check: docker-compose ps"
            echo ""
          elif [ "$APP_CODE" = "503" ]; then
            echo "Diagnosis: 503 Service Unavailable"
            echo "  → Backend service is down or not responding"
            echo "  → Container may be starting or crashed"
            echo "  → Check: docker-compose logs"
            echo ""
          fi
        fi

        # Content verification failures
        if [ "$APP_REAL_CONTENT" = false ] && [ "$APP_ACCESSIBLE" = true ]; then
          echo "ISSUE: App accessible but showing default/error page"
          echo ""
          echo "Possible causes:"
          echo "  1. App configuration missing (basePath, publicPath, etc.)"
          echo "  2. App serving intro/default page, not actual content"
          echo "  3. Database connection failed - app showing error page"
          echo "  4. Environment variables not set"
          echo ""
          echo "Troubleshooting steps:"
          echo "  • Check app configuration:"
          echo "    cat ~/deployments/${APP_NAME}/.env"
          echo ""
          echo "  • Verify app logs for startup errors:"
          echo "    docker-compose logs | grep -i error"
          echo ""
          echo "  • Test app directly (bypass nginx):"
          echo "    curl http://localhost:$APP_PORT/"
          echo ""
        fi
      fi
      ```

      ## Phase 6: Final Report

      Display comprehensive test results:

      ```
      ═══════════════════════════════════════════════════════════════════
                              VERIFICATION REPORT
      ═══════════════════════════════════════════════════════════════════

      SECTION A: PORTAL HEALTH
      ─────────────────────────────────────────────────────────────────
      ```

      Show portal test results:
      ```bash
      [ "$PORTAL_HOMEPAGE_PASS" = true ] && echo "  ✓ Homepage shows Capsule Cloud content" || echo "  ✗ Homepage not showing correct content"
      [ "$PORTAL_DEPLOY_PASS" = true ] && echo "  ✓ /deploy/ page shows deployment access" || echo "  ✗ /deploy/ page not working"
      [ "$PORTAL_APPS_PASS" = true ] && echo "  ✓ /deploy/apps shows app catalog" || echo "  ✗ /deploy/apps not working"
      [ "$PORTAL_HTTP_PASS" = true ] && echo "  ✓ HTTP access working" || echo "  ℹ HTTP not accessible"
      ```

      If app was tested, show app results:
      ```
      SECTION B: DEPLOYED APPLICATION ($APP_NAME)
      ─────────────────────────────────────────────────────────────────
      ```

      ```bash
      if [ -n "$APP_NAME" ]; then
        [ "$CONTAINER_PASS" = true ] && echo "  ✓ Containers running" || echo "  ✗ Containers not running"
        [ "$LOGS_PASS" = true ] && echo "  ✓ No errors in logs" || echo "  ⚠ Errors detected in logs"
        [ "$NGINX_VALID" = true ] && echo "  ✓ Nginx config valid" || echo "  ✗ Nginx config invalid"
        [ "$NGINX_ROUTE" = true ] && echo "  ✓ Nginx route configured" || echo "  ⚠ Nginx route missing/misconfigured"
        [ "$APP_ACCESSIBLE" = true ] && echo "  ✓ Endpoint accessible (HTTP $APP_CODE)" || echo "  ✗ Endpoint not accessible (HTTP $APP_CODE)"
        [ "$APP_REAL_CONTENT" = true ] && echo "  ✓ Returning real content" || echo "  ✗ Not showing app content"

        if [ "$APP_HAS_CONTENT" = true ]; then
          echo "  ✓ Response indicates full app (not default page)"
        elif [ "$APP_HAS_CONTENT" = partial ]; then
          echo "  ⚠ May be showing default/intro page"
        fi
      fi
      ```

      Final summary:
      ```
      ═══════════════════════════════════════════════════════════════════
      ```

      ```bash
      if [ "$PORTAL_HEALTHY" = true ] && [ "$FAILURES_DETECTED" = false ]; then
        echo "  ✓✓ VERIFICATION PASSED ✓✓"
        echo ""
        echo "  Portal: HEALTHY"
        [ -n "$APP_NAME" ] && echo "  App ($APP_NAME): DEPLOYED SUCCESSFULLY"
        echo ""
        echo "  Access your app: https://${PORTAL_HOST}/${APP_PATH}/"
      elif [ "$PORTAL_HEALTHY" = true ] && [ "$FAILURES_DETECTED" = true ]; then
        echo "  ⚠⚠ PARTIAL SUCCESS ⚠⚠"
        echo ""
        echo "  Portal: HEALTHY"
        echo "  App ($APP_NAME): DEPLOYMENT ISSUES DETECTED"
        echo ""
        echo "  Review diagnostics above for troubleshooting steps."
      else
        echo "  ✗✗ VERIFICATION FAILED ✗✗"
        echo ""
        echo "  Portal: UNHEALTHY"
        echo ""
        echo "  Fix portal issues before deploying applications."
      fi
      ```

      ```
      ═══════════════════════════════════════════════════════════════════
      ```

      ## Usage Examples

      ### Example 1: Test portal health only
      ```bash
      /deploy-verify
      ```
      Tests portal homepage, /deploy/ page, /deploy/apps, and HTTP access.

      ### Example 2: Test portal + specific app
      ```bash
      /deploy-verify my-app
      ```
      Tests portal health FIRST, then verifies `my-app` is deployed correctly.

      ### Example 3: After deployment
      ```bash
      /deploy my-app
      # ... deployment completes ...
      /deploy-verify my-app
      ```
      Verifies the deployment was successful and nothing broke.

      ## Error Handling

      ### Portal Unreachable
      If portal doesn't respond:
      - Show: "⚠ Portal unreachable - cannot perform verification"
      - Suggest: Check VPN connection, portal URL, or network issues
      - Exit gracefully

      ### SSH Connection Failed
      If SSH credentials invalid or connection fails:
      - Skip container and nginx tests
      - Only test publicly accessible endpoints
      - Show: "⚠ SSH unavailable - some tests skipped"

      ### App Not Found
      If app name provided but no config found:
      - Show: "⚠ No deployment config found for {app}"
      - Suggest: Check app name spelling, or re-run /deploy
      - Attempt basic URL test anyway using guessed path

      ## Notes

      - This skill is designed to run AFTER `/deploy`
      - Primary purpose: Verify deployment succeeded and nothing broke
      - Tests BOTH portal health AND deployed app functionality
      - Helps diagnose failures with root cause analysis
      - Section A (portal) must pass before testing Section B (app)
      - Auto-update capability planned for future (currently MVP)

  - name: deploy-verify update
    description: Force check for skill updates (not yet implemented)
    instructions: |
      # Force Skill Update

      **NOTE**: Auto-update is not yet implemented in MVP version.

      Future implementation will:
      1. Query portal version API
      2. Compare skill version vs portal version
      3. Download and replace skill if update available

      For now, display:
      ```
      ═══════════════════════════════════════════════════════════════════
                          SKILL UPDATE CHECK
      ═══════════════════════════════════════════════════════════════════

      Current skill version: 20260202.000000

      ⚠ Auto-update not yet implemented in MVP version.

      To manually update:
      1. Check portal for new skill version
      2. Download updated SKILL.md
      3. Replace ~/.claude/skills/deploy-verify/SKILL.md

      ═══════════════════════════════════════════════════════════════════
      ```

metadata:
  author: Capsule Cloud
  version_format: YYYYMMDD.HHmmss
  portal_api_base: /api/deployment
  mvp_version: true
