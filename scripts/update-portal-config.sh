#!/bin/bash
#
# update-portal-config.sh
#
# Update deploy-portal configuration without full redeployment
#
# Usage:
#   ./update-portal-config.sh \
#     --target-host ubuntu@44.244.76.51 \
#     --ssh-key /path/to/key.pem \
#     --config-var SSH_KEY_PATH=/new/path \
#     --config-var AWS_REGION=us-west-2

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parameters
TARGET_HOST=""
SSH_KEY=""
declare -A CONFIG_VARS

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
}

# Usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Update deploy-portal configuration variables.

Required Options:
  --target-host HOST          Target host (e.g., ubuntu@44.244.76.51)
  --ssh-key PATH              SSH key to connect to target
  --config-var KEY=VALUE      Configuration variable to update (can be used multiple times)

Configuration Variables:
  SSH_KEY_PATH                Path to SSH key for deployment
  SSH_KEY_NAME                Name of SSH key
  AWS_REGION                  AWS region
  SECURITY_GROUP_ID           Security group ID
  PUBLIC_IP                   Public IP address
  COGNITO_POOL_ID             Cognito User Pool ID
  COGNITO_CLIENT_ID           Cognito Client ID
  COGNITO_CLIENT_SECRET       Cognito Client Secret
  COGNITO_REGION              Cognito region

Example:
  $0 \\
    --target-host ubuntu@44.244.76.51 \\
    --ssh-key ~/.ssh/my-key.pem \\
    --config-var SSH_KEY_PATH=/home/ubuntu/.ssh/new-key.pem \\
    --config-var SSH_KEY_NAME=new-key \\
    --config-var AWS_REGION=us-west-2

EOF
    exit 1
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --target-host)
                TARGET_HOST="$2"
                shift 2
                ;;
            --ssh-key)
                SSH_KEY="$2"
                shift 2
                ;;
            --config-var)
                local key="${2%%=*}"
                local value="${2#*=}"
                CONFIG_VARS["$key"]="$value"
                shift 2
                ;;
            --help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    if [[ -z "$TARGET_HOST" || -z "$SSH_KEY" || ${#CONFIG_VARS[@]} -eq 0 ]]; then
        log_error "Target host, SSH key, and at least one config variable are required"
        usage
    fi

    SSH_KEY=$(realpath "$SSH_KEY")
}

# SSH helper
run_remote() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$TARGET_HOST" "$1"
}

# Update configuration
update_config() {
    log_section "Configuration Update"

    # Check if .ec2-config.env exists
    if ! run_remote "test -f /home/ubuntu/.ec2-config.env"; then
        log_error ".ec2-config.env not found on target"
        exit 1
    fi

    log_info "Backing up current configuration..."
    run_remote "cp /home/ubuntu/.ec2-config.env /home/ubuntu/.ec2-config.env.backup.$(date +%Y%m%d_%H%M%S)"
    log_success "Configuration backed up"

    # Update each variable
    for key in "${!CONFIG_VARS[@]}"; do
        local value="${CONFIG_VARS[$key]}"
        log_info "Updating $key=$value"

        # Remove old line and add new one
        run_remote "
            sed -i '/^export $key=/d' /home/ubuntu/.ec2-config.env
            echo 'export $key=$value' >> /home/ubuntu/.ec2-config.env
        "

        log_success "$key updated"
    done

    # Show updated configuration
    log_info "Updated configuration:"
    for key in "${!CONFIG_VARS[@]}"; do
        local value=$(run_remote "grep '^export $key=' /home/ubuntu/.ec2-config.env | cut -d'=' -f2")
        echo "  $key=$value"
    done
}

# Restart service
restart_service() {
    log_section "Service Restart"

    if run_remote "sudo systemctl is-active deploy-portal" > /dev/null 2>&1; then
        log_info "Restarting deploy-portal service..."
        run_remote "sudo systemctl restart deploy-portal"

        # Wait for service to start
        sleep 3

        if run_remote "sudo systemctl is-active deploy-portal" > /dev/null 2>&1; then
            log_success "Service restarted successfully"
        else
            log_error "Service failed to restart"
            log_info "Recent logs:"
            run_remote "sudo journalctl -u deploy-portal -n 20 --no-pager"
            exit 1
        fi
    else
        log_error "deploy-portal service not found or not running"
        exit 1
    fi
}

# Verify new configuration
verify_config() {
    log_section "Configuration Verification"

    # Test that the service can read the new config
    log_info "Verifying configuration load..."

    for key in "${!CONFIG_VARS[@]}"; do
        local expected_value="${CONFIG_VARS[$key]}"

        # Try to read the value through Python config
        local loaded_value=$(run_remote "cd /home/ubuntu/src/deploy-portal && source venv/bin/activate && python3 -c \"
import sys
import os
sys.path.insert(0, '/home/ubuntu/src/deploy-portal')

# Load environment from .ec2-config.env
import subprocess
result = subprocess.run(['bash', '-c', 'source /home/ubuntu/.ec2-config.env && env'], capture_output=True, text=True)
for line in result.stdout.split('\n'):
    if '=' in line:
        k, v = line.split('=', 1)
        os.environ[k] = v

# Import config
from config import Config
config = Config()

# Try to get the value
if hasattr(config, '$key'):
    print(getattr(config, '$key'))
else:
    print(os.environ.get('$key', ''))
\" 2>/dev/null" || echo "")

        if [[ "$loaded_value" == "$expected_value" ]]; then
            log_success "$key verified: $loaded_value"
        else
            log_error "$key verification failed: expected '$expected_value', got '$loaded_value'"
        fi
    done

    # Test portal is responsive
    log_info "Testing portal responsiveness..."
    if run_remote "curl -s -o /dev/null -w '%{http_code}' http://localhost:5000" | grep -q "200\|302"; then
        log_success "Portal is responding"
    else
        log_error "Portal is not responding"
    fi
}

# Main
main() {
    parse_args "$@"

    log_section "Deploy Portal Configuration Update"
    log_info "Target: $TARGET_HOST"
    log_info "Variables to update: ${#CONFIG_VARS[@]}"
    echo ""

    # Test SSH connection
    log_info "Testing SSH connection..."
    if ! run_remote "echo 'Connection successful'" > /dev/null; then
        log_error "Cannot connect to $TARGET_HOST"
        exit 1
    fi
    log_success "SSH connection successful"

    # Update configuration
    update_config

    # Restart service
    restart_service

    # Verify
    verify_config

    log_section "Update Complete"
    echo "Configuration updated and service restarted successfully."
    echo ""
    echo "You can verify the deployment with:"
    echo "  ./verify-deployment.sh --target-host $TARGET_HOST --ssh-key $SSH_KEY --domain <your-domain>"
}

main "$@"
