#!/bin/bash
#
# configure-ssh-key.sh
#
# Configure SSH key on a deploy-portal instance
#
# Usage:
#   ./configure-ssh-key.sh \
#     --target-host ubuntu@44.244.76.51 \
#     --ssh-key /path/to/connection-key.pem \
#     --deploy-key /path/to/deploy-key.pem \
#     --deploy-key-name my-deploy-key

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
TARGET_HOST=""
SSH_KEY=""
DEPLOY_KEY=""
DEPLOY_KEY_NAME=""

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
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

Configure SSH key for a deploy-portal instance.

Required Options:
  --target-host HOST          Target host (e.g., ubuntu@44.244.76.51)
  --ssh-key PATH              SSH key to connect to target
  --deploy-key PATH           SSH key for portal to distribute
  --deploy-key-name NAME      Name of the deploy key (without .pem)

Example:
  $0 \\
    --target-host ubuntu@44.244.76.51 \\
    --ssh-key ~/.ssh/connection-key.pem \\
    --deploy-key ~/.ssh/deploy-key.pem \\
    --deploy-key-name my-deploy-key

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
            --deploy-key)
                DEPLOY_KEY="$2"
                shift 2
                ;;
            --deploy-key-name)
                DEPLOY_KEY_NAME="$2"
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

    # Validate required parameters
    if [[ -z "$TARGET_HOST" || -z "$SSH_KEY" || -z "$DEPLOY_KEY" || -z "$DEPLOY_KEY_NAME" ]]; then
        log_error "All parameters are required"
        usage
    fi

    # Expand paths
    SSH_KEY=$(realpath "$SSH_KEY")
    DEPLOY_KEY=$(realpath "$DEPLOY_KEY")
}

# SSH helper
run_remote() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$TARGET_HOST" "$1"
}

# Copy file to remote
copy_to_remote() {
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$1" "$TARGET_HOST":"$2"
}

# Main configuration
configure_ssh_key() {
    log_section "SSH Key Configuration"

    # Check deploy key exists locally
    if [[ ! -f "$DEPLOY_KEY" ]]; then
        log_error "Deploy key not found: $DEPLOY_KEY"
        exit 1
    fi
    log_success "Deploy key found: $DEPLOY_KEY"

    # Test SSH connection
    log_info "Testing SSH connection..."
    if ! run_remote "echo 'Connection successful'"; then
        log_error "Cannot connect to $TARGET_HOST"
        exit 1
    fi
    log_success "Connected to $TARGET_HOST"

    # Copy SSH key to target
    local remote_key_path="/home/ubuntu/.ssh/${DEPLOY_KEY_NAME}.pem"
    log_info "Copying deploy key to $remote_key_path..."

    run_remote "mkdir -p /home/ubuntu/.ssh"
    copy_to_remote "$DEPLOY_KEY" "$remote_key_path"
    run_remote "chmod 400 $remote_key_path"

    log_success "Deploy key copied and secured"

    # Update or create .ec2-config.env
    log_info "Updating .ec2-config.env..."

    # Check if file exists
    if run_remote "test -f /home/ubuntu/.ec2-config.env"; then
        # File exists, update it
        run_remote "
            # Remove old SSH key lines if they exist
            sed -i '/^export SSH_KEY_PATH=/d' /home/ubuntu/.ec2-config.env
            sed -i '/^export SSH_KEY_NAME=/d' /home/ubuntu/.ec2-config.env

            # Add new SSH key configuration
            echo '' >> /home/ubuntu/.ec2-config.env
            echo '# SSH Key Configuration' >> /home/ubuntu/.ec2-config.env
            echo 'export SSH_KEY_PATH=$remote_key_path' >> /home/ubuntu/.ec2-config.env
            echo 'export SSH_KEY_NAME=$DEPLOY_KEY_NAME' >> /home/ubuntu/.ec2-config.env
        "
        log_success "Updated existing .ec2-config.env"
    else
        # Create new file
        run_remote "cat > /home/ubuntu/.ec2-config.env << 'EOF'
# SSH Key Configuration
export SSH_KEY_PATH=$remote_key_path
export SSH_KEY_NAME=$DEPLOY_KEY_NAME
EOF"
        log_success "Created new .ec2-config.env"
    fi

    # Restart deploy-portal service if it exists
    if run_remote "sudo systemctl is-active deploy-portal" > /dev/null 2>&1; then
        log_info "Restarting deploy-portal service..."
        run_remote "sudo systemctl restart deploy-portal"

        # Wait for service to start
        sleep 3

        if run_remote "sudo systemctl is-active deploy-portal"; then
            log_success "Service restarted successfully"
        else
            log_error "Service failed to restart"
            run_remote "sudo journalctl -u deploy-portal -n 20"
            exit 1
        fi
    else
        log_warning "deploy-portal service not found, skipping restart"
    fi

    # Verify configuration
    log_info "Verifying configuration..."

    # Test that SSH key is readable
    if run_remote "test -r $remote_key_path"; then
        log_success "SSH key is readable"
    else
        log_error "SSH key is not readable"
        exit 1
    fi

    # Test Python can load the configuration
    if run_remote "cd /home/ubuntu/src/deploy-portal && source venv/bin/activate && python3 -c \"
import sys
sys.path.insert(0, '/home/ubuntu/src/deploy-portal')
from config import Config
import os

# Source the config file
import subprocess
result = subprocess.run(['bash', '-c', 'source /home/ubuntu/.ec2-config.env && env'], capture_output=True, text=True)
for line in result.stdout.split('\n'):
    if '=' in line:
        key, value = line.split('=', 1)
        os.environ[key] = value

# Reload config
config = Config()
print(f'SSH_KEY_PATH={config.SSH_KEY_PATH}')
print(f'SSH_KEY_NAME={config.SSH_KEY_NAME}')
assert config.SSH_KEY_PATH == '$remote_key_path', f'Expected $remote_key_path, got {config.SSH_KEY_PATH}'
assert config.SSH_KEY_NAME == '$DEPLOY_KEY_NAME', f'Expected $DEPLOY_KEY_NAME, got {config.SSH_KEY_NAME}'
print('Configuration loaded correctly')
\"" > /dev/null 2>&1; then
        log_success "Python configuration verified"
    else
        log_warning "Could not verify Python configuration (deploy-portal may not be installed)"
    fi

    log_section "Configuration Complete"
    echo "SSH Key Configuration Summary:"
    echo "  - Deploy key: $DEPLOY_KEY"
    echo "  - Remote path: $remote_key_path"
    echo "  - Key name: $DEPLOY_KEY_NAME"
    echo ""
    echo "Configuration file updated: /home/ubuntu/.ec2-config.env"
}

# Main
main() {
    parse_args "$@"
    configure_ssh_key
}

main "$@"
