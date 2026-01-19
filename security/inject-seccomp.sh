#!/bin/bash
#
# Inject seccomp profiles into existing Docker deployments
# Backs up existing compose files and adds security options
# Enhanced with automatic database container detection
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DEPLOYMENT_ROOT="${DEPLOYMENT_ROOT:-/home/ubuntu/deployments}"
SECCOMP_PROFILE="/etc/seccomp/docker-default.json"
BACKUP_SUFFIX=".backup-$(date +%Y%m%d-%H%M%S)"

echo -e "${YELLOW}=== Injecting seccomp profiles into Docker deployments ===${NC}\n"

# Check if yq is installed
if ! command -v yq &> /dev/null; then
    echo -e "${YELLOW}Installing yq (YAML processor)...${NC}"
    sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
    sudo chmod +x /usr/local/bin/yq
    echo -e "${GREEN}✓ yq installed${NC}"
fi

# Check if seccomp profile exists
if [ ! -f "$SECCOMP_PROFILE" ]; then
    echo -e "${RED}Error: seccomp profile not found: $SECCOMP_PROFILE${NC}"
    exit 1
fi

# Function to detect if a service is a database
is_database_service() {
    local service_name="$1"
    local compose_file="$2"
    
    # Check service name
    if echo "$service_name" | grep -qiE '^(postgres|postgresql|mysql|mariadb|mongo|mongodb|redis|cassandra|cockroach|timescale|couchdb|neo4j)'; then
        return 0
    fi
    
    # Check image name
    local image=$(yq eval ".services.$service_name.image" "$compose_file" 2>/dev/null || echo "")
    if echo "$image" | grep -qiE '(postgres|mysql|mariadb|mongo|redis|cassandra|cockroach|timescale|couchdb|neo4j|pgvector)'; then
        return 0
    fi
    
    return 1
}

# Find all docker-compose files
compose_files=$(find "$DEPLOYMENT_ROOT" -name "docker-compose.yml" -o -name "docker-compose.yaml" 2>/dev/null || true)

if [ -z "$compose_files" ]; then
    echo -e "${YELLOW}No docker-compose files found in $DEPLOYMENT_ROOT${NC}"
    exit 0
fi

count=0
updated=0

while IFS= read -r compose_file; do
    count=$((count + 1))
    app_name=$(basename "$(dirname "$compose_file")")

    echo -e "\n${YELLOW}Processing: $app_name${NC}"
    echo "  File: $compose_file"

    # Backup original file
    backup_file="${compose_file}${BACKUP_SUFFIX}"
    cp "$compose_file" "$backup_file"
    echo -e "  ${GREEN}✓ Backup created: $backup_file${NC}"

    # Check if seccomp is already configured
    if grep -q "seccomp:" "$compose_file" 2>/dev/null; then
        echo -e "  ${YELLOW}⚠ seccomp already configured, skipping${NC}"
        continue
    fi

    # Inject security options using yq
    echo "  Adding security options..."

    # Get all service names
    services=$(yq eval '.services | keys | .[]' "$compose_file")

    while IFS= read -r service; do
        if [ -n "$service" ]; then
            echo "    - Service: $service"

            # Add security_opt
            yq eval -i ".services.$service.security_opt = [
              \"seccomp=$SECCOMP_PROFILE\",
              \"no-new-privileges:true\"
            ]" "$compose_file"

            # Add cap_drop
            yq eval -i ".services.$service.cap_drop = [\"ALL\"]" "$compose_file"
            
            # Check if this is a database service
            if is_database_service "$service" "$compose_file"; then
                echo -e "      ${BLUE}→ Detected as database service${NC}"
                # Database services need additional capabilities
                yq eval -i ".services.$service.cap_add = [
                  \"NET_BIND_SERVICE\",
                  \"CHOWN\",
                  \"SETUID\",
                  \"SETGID\",
                  \"DAC_OVERRIDE\",
                  \"FOWNER\"
                ]" "$compose_file"
                echo -e "      ${GREEN}✓ Security options added (database profile)${NC}"
            else
                # Standard application services
                yq eval -i ".services.$service.cap_add = [
                  \"NET_BIND_SERVICE\",
                  \"CHOWN\",
                  \"SETUID\",
                  \"SETGID\"
                ]" "$compose_file"
                echo -e "      ${GREEN}✓ Security options added (standard profile)${NC}"
            fi
        fi
    done <<< "$services"

    updated=$((updated + 1))
    echo -e "  ${GREEN}✓ Updated successfully${NC}"

    # Ask to recreate containers
    read -p "  Recreate containers for $app_name? (y/n): " recreate
    if [ "$recreate" = "y" ] || [ "$recreate" = "Y" ]; then
        echo "  Recreating containers..."
        cd "$(dirname "$compose_file")"
        if docker-compose up -d --force-recreate; then
            echo -e "  ${GREEN}✓ Containers recreated${NC}"
        else
            echo -e "  ${RED}✗ Failed to recreate containers${NC}"
            echo -e "  ${YELLOW}Restoring backup...${NC}"
            cp "$backup_file" "$compose_file"
        fi
    else
        echo -e "  ${YELLOW}⚠ Skipped recreation. Apply changes with: docker-compose up -d --force-recreate${NC}"
    fi

done <<< "$compose_files"

echo ""
echo -e "${GREEN}=== Summary ===${NC}"
echo "Total docker-compose files found: $count"
echo "Files updated: $updated"
echo "Files skipped: $((count - updated))"
echo ""
echo -e "${YELLOW}Backup files created with suffix: $BACKUP_SUFFIX${NC}"
echo -e "${YELLOW}To revert, restore from backup files${NC}"
echo ""
echo -e "${BLUE}Database detection patterns:${NC}"
echo -e "  - Service names: postgres, mysql, mariadb, mongo, redis, cassandra, etc."
echo -e "  - Image names: postgres, pgvector, mysql, mariadb, mongo, redis, etc."
echo -e "  - Database services receive: DAC_OVERRIDE, FOWNER capabilities"
