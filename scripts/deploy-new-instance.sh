#!/bin/bash
#
# deploy-new-instance.sh
#
# Automated deployment of deploy-portal to a fresh EC2 instance
#
# Usage:
#   ./deploy-new-instance.sh \
#     --target-ip 44.244.76.51 \
#     --domain capsule-product-deploy.duckdns.org \
#     --ssh-key /path/to/connection-key.pem \
#     --cognito-pool-id us-east-1_xxxxx \
#     --cognito-client-id xxxxx \
#     --cognito-client-secret xxxxx \
#     [--deploy-ssh-key /path/to/deploy-key.pem] \
#     [--cognito-region us-east-1] \
#     [--aws-region us-west-2] \
#     [--security-group-id sg-xxxxx] \
#     [--skip-auth-gateway]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
COGNITO_REGION="us-east-1"
AWS_REGION="us-west-2"
DEPLOY_SSH_KEY=""
SECURITY_GROUP_ID=""
SKIP_AUTH_GATEWAY=false
TARGET_IP=""
TARGET_HOST=""
DOMAIN=""
SSH_KEY=""
COGNITO_POOL_ID=""
COGNITO_CLIENT_ID=""
COGNITO_CLIENT_SECRET=""

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

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy deploy-portal to a fresh EC2 instance with full automation.

Required Options:
  --target-ip IP              Target EC2 instance IP address
  --target-host HOST          Target EC2 hostname (alternative to --target-ip)
  --domain DOMAIN             Domain name for this portal instance
  --ssh-key PATH              SSH key to connect to target instance
  --cognito-pool-id ID        Cognito User Pool ID
  --cognito-client-id ID      Cognito Client ID
  --cognito-client-secret KEY Cognito Client Secret

Optional:
  --deploy-ssh-key PATH       SSH key for portal to distribute (default: same as --ssh-key)
  --cognito-region REGION     Cognito region (default: us-east-1)
  --aws-region REGION         AWS region for EC2 (default: us-west-2)
  --security-group-id ID      Security group ID (will auto-detect if not provided)
  --skip-auth-gateway         Skip auth gateway installation (if already installed)
  --help                      Show this help message

Example:
  $0 \\
    --target-ip 44.244.76.51 \\
    --domain capsule-product-deploy.duckdns.org \\
    --ssh-key ~/.ssh/my-key.pem \\
    --cognito-pool-id us-east-1_aVHSg58BS \\
    --cognito-client-id 46gdd9glnaetl44e2mtap51bkk \\
    --cognito-client-secret xxxxxxxxxxxxx

EOF
    exit 1
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --target-ip)
                TARGET_IP="$2"
                shift 2
                ;;
            --target-host)
                TARGET_HOST="$2"
                shift 2
                ;;
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --ssh-key)
                SSH_KEY="$2"
                shift 2
                ;;
            --deploy-ssh-key)
                DEPLOY_SSH_KEY="$2"
                shift 2
                ;;
            --cognito-pool-id)
                COGNITO_POOL_ID="$2"
                shift 2
                ;;
            --cognito-client-id)
                COGNITO_CLIENT_ID="$2"
                shift 2
                ;;
            --cognito-client-secret)
                COGNITO_CLIENT_SECRET="$2"
                shift 2
                ;;
            --cognito-region)
                COGNITO_REGION="$2"
                shift 2
                ;;
            --aws-region)
                AWS_REGION="$2"
                shift 2
                ;;
            --security-group-id)
                SECURITY_GROUP_ID="$2"
                shift 2
                ;;
            --skip-auth-gateway)
                SKIP_AUTH_GATEWAY=true
                shift
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

    # Set target host if only IP provided
    if [[ -n "$TARGET_IP" && -z "$TARGET_HOST" ]]; then
        TARGET_HOST="$TARGET_IP"
    fi

    # Use connection SSH key as deploy key if not specified
    if [[ -z "$DEPLOY_SSH_KEY" ]]; then
        DEPLOY_SSH_KEY="$SSH_KEY"
    fi

    # Validate required parameters
    if [[ -z "$TARGET_HOST" ]]; then
        log_error "Target host/IP is required (--target-ip or --target-host)"
        usage
    fi

    if [[ -z "$DOMAIN" ]]; then
        log_error "Domain is required (--domain)"
        usage
    fi

    if [[ -z "$SSH_KEY" ]]; then
        log_error "SSH key is required (--ssh-key)"
        usage
    fi

    if [[ -z "$COGNITO_POOL_ID" ]]; then
        log_error "Cognito Pool ID is required (--cognito-pool-id)"
        usage
    fi

    if [[ -z "$COGNITO_CLIENT_ID" ]]; then
        log_error "Cognito Client ID is required (--cognito-client-id)"
        usage
    fi

    if [[ -z "$COGNITO_CLIENT_SECRET" ]]; then
        log_error "Cognito Client Secret is required (--cognito-client-secret)"
        usage
    fi

    # Expand paths
    SSH_KEY=$(realpath "$SSH_KEY")
    DEPLOY_SSH_KEY=$(realpath "$DEPLOY_SSH_KEY")
}

# Preflight checks
preflight_checks() {
    log_section "Preflight Checks"

    # Check SSH keys exist
    if [[ ! -f "$SSH_KEY" ]]; then
        log_error "SSH key not found: $SSH_KEY"
        exit 1
    fi
    log_success "Connection SSH key found: $SSH_KEY"

    if [[ ! -f "$DEPLOY_SSH_KEY" ]]; then
        log_error "Deploy SSH key not found: $DEPLOY_SSH_KEY"
        exit 1
    fi
    log_success "Deploy SSH key found: $DEPLOY_SSH_KEY"

    # Test SSH connection
    log_info "Testing SSH connection to ubuntu@$TARGET_HOST..."
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$TARGET_HOST" "echo 'SSH connection successful'" > /dev/null 2>&1; then
        log_success "SSH connection successful"
    else
        log_error "Cannot connect via SSH to ubuntu@$TARGET_HOST"
        exit 1
    fi

    # Check if we can resolve target IP
    if [[ -z "$TARGET_IP" ]]; then
        log_info "Resolving target IP from host..."
        TARGET_IP=$(ssh -i "$SSH_KEY" ubuntu@"$TARGET_HOST" "curl -s http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null || echo "")
        if [[ -n "$TARGET_IP" ]]; then
            log_success "Resolved target IP: $TARGET_IP"
        else
            log_warning "Could not resolve target IP, will use hostname"
            TARGET_IP="$TARGET_HOST"
        fi
    fi
}

# SSH helper function
run_remote() {
    local cmd="$1"
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$TARGET_HOST" "$cmd"
}

# Copy file to remote
copy_to_remote() {
    local src="$1"
    local dst="$2"
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$src" ubuntu@"$TARGET_HOST":"$dst"
}

# System preparation
prepare_system() {
    log_section "System Preparation"

    log_info "Updating system packages..."
    run_remote "sudo apt-get update -qq"
    log_success "System packages updated"

    log_info "Installing dependencies..."
    run_remote "sudo apt-get install -y git nginx python3 python3-venv python3-pip nodejs npm curl jq > /dev/null 2>&1"
    log_success "Dependencies installed"

    log_info "Creating directory structure..."
    run_remote "mkdir -p /home/ubuntu/src /home/ubuntu/.ssh"
    log_success "Directory structure created"
}

# Deploy authentication gateway
deploy_auth_gateway() {
    if [[ "$SKIP_AUTH_GATEWAY" == true ]]; then
        log_section "Authentication Gateway (Skipped)"
        log_info "Skipping auth gateway installation as requested"
        return
    fi

    log_section "Authentication Gateway Deployment"

    # Check if auth gateway already exists
    if run_remote "test -d /home/ubuntu/src/easy-cognito-nginx-gateway-auth"; then
        log_warning "Auth gateway directory already exists, skipping clone"
    else
        log_info "Cloning easy-cognito-nginx-gateway-auth..."
        run_remote "cd /home/ubuntu/src && git clone https://github.com/davidbmar/easy-cognito-nginx-gateway-auth.git"
        log_success "Repository cloned"
    fi

    log_info "Installing authentication gateway..."

    # Extract Cognito domain from pool ID
    local cognito_domain_prefix=$(echo "$COGNITO_POOL_ID" | sed 's/.*_//')
    local cognito_domain="${cognito_domain_prefix}.auth.${COGNITO_REGION}.amazoncognito.com"

    run_remote "cd /home/ubuntu/src/easy-cognito-nginx-gateway-auth && sudo bash install.sh \
        --cognito-pool-id '$COGNITO_POOL_ID' \
        --cognito-client-id '$COGNITO_CLIENT_ID' \
        --cognito-client-secret '$COGNITO_CLIENT_SECRET' \
        --cognito-region '$COGNITO_REGION' \
        --cognito-domain '$cognito_domain' \
        --redirect-uri 'https://${DOMAIN}/oauth2/callback'"

    log_success "Authentication gateway installed"

    # Update Cognito callback URLs if AWS CLI is available
    if command -v aws &> /dev/null; then
        log_info "Updating Cognito callback URLs..."
        aws cognito-idp update-user-pool-client \
            --user-pool-id "$COGNITO_POOL_ID" \
            --client-id "$COGNITO_CLIENT_ID" \
            --callback-urls "https://${DOMAIN}/oauth2/callback" \
            --logout-urls "https://${DOMAIN}/" \
            --region "$COGNITO_REGION" > /dev/null 2>&1 || log_warning "Could not update Cognito URLs automatically"
    fi

    # Verify services
    if run_remote "sudo systemctl is-active nginx"; then
        log_success "nginx is running"
    else
        log_error "nginx is not running"
        exit 1
    fi

    if run_remote "sudo systemctl is-active oauth2-proxy"; then
        log_success "oauth2-proxy is running"
    else
        log_error "oauth2-proxy is not running"
        exit 1
    fi
}

# Deploy portal application
deploy_portal() {
    log_section "Deploy Portal Application"

    # Check if deploy-portal already exists
    if run_remote "test -d /home/ubuntu/src/deploy-portal"; then
        log_warning "Deploy-portal directory already exists, pulling latest..."
        run_remote "cd /home/ubuntu/src/deploy-portal && git pull"
    else
        log_info "Cloning deploy-portal repository..."
        run_remote "cd /home/ubuntu/src && git clone https://github.com/davidbmar/deploy-portal.git"
        log_success "Repository cloned"
    fi

    # Copy SSH key to target
    log_info "Copying SSH key to target server..."
    local deploy_key_name=$(basename "$DEPLOY_SSH_KEY" .pem)
    local remote_key_path="/home/ubuntu/.ssh/${deploy_key_name}.pem"

    copy_to_remote "$DEPLOY_SSH_KEY" "$remote_key_path"
    run_remote "chmod 400 $remote_key_path"
    log_success "SSH key copied and secured: $remote_key_path"

    # Auto-detect security group if not provided
    if [[ -z "$SECURITY_GROUP_ID" ]]; then
        log_info "Auto-detecting security group ID..."
        SECURITY_GROUP_ID=$(run_remote "curl -s -H 'X-aws-ec2-metadata-token: \$(curl -s -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600')' http://169.254.169.254/latest/meta-data/security-groups" | head -n1 || echo "")

        if [[ -n "$SECURITY_GROUP_ID" ]]; then
            log_success "Detected security group: $SECURITY_GROUP_ID"
        else
            log_warning "Could not auto-detect security group, using default"
            SECURITY_GROUP_ID="sg-0d485b4ffe8c8f886"
        fi
    fi

    # Create .ec2-config.env
    log_info "Creating configuration file..."
    run_remote "cat > /home/ubuntu/.ec2-config.env << 'EOF'
# AWS Cognito Configuration
export COGNITO_POOL_ID=$COGNITO_POOL_ID
export COGNITO_CLIENT_ID=$COGNITO_CLIENT_ID
export COGNITO_CLIENT_SECRET=$COGNITO_CLIENT_SECRET
export COGNITO_REGION=$COGNITO_REGION

# Public IP for THIS server
export PUBLIC_IP=$TARGET_IP

# AWS Configuration
export AWS_REGION=$AWS_REGION
export SECURITY_GROUP_ID=$SECURITY_GROUP_ID

# SSH Key Configuration
export SSH_KEY_PATH=$remote_key_path
export SSH_KEY_NAME=$deploy_key_name

# OAuth2 Proxy Port
export OAUTH2_PORT=4180

# Instance Domain
export INSTANCE_DOMAIN=$DOMAIN
EOF"
    log_success "Configuration file created"

    # Create Python virtual environment
    log_info "Creating Python virtual environment..."
    run_remote "cd /home/ubuntu/src/deploy-portal && python3 -m venv venv"
    log_success "Virtual environment created"

    # Install Python dependencies
    log_info "Installing Python dependencies..."
    run_remote "cd /home/ubuntu/src/deploy-portal && source venv/bin/activate && pip install -q --upgrade pip && pip install -q -r requirements.txt"
    log_success "Python dependencies installed"

    # Create activity log directory
    log_info "Creating activity log directory..."
    run_remote "sudo mkdir -p /var/log/deploy-sessions && sudo chown ubuntu:ubuntu /var/log/deploy-sessions"
    log_success "Activity log directory created"

    # Install systemd service
    log_info "Installing systemd service..."
    run_remote "cd /home/ubuntu/src/deploy-portal && sudo cp deploy-portal.service /etc/systemd/system/"
    run_remote "sudo systemctl daemon-reload"
    run_remote "sudo systemctl enable deploy-portal"
    run_remote "sudo systemctl restart deploy-portal"
    log_success "Systemd service installed and started"

    # Wait for service to start
    log_info "Waiting for service to start..."
    sleep 3

    # Verify service is running
    if run_remote "sudo systemctl is-active deploy-portal"; then
        log_success "deploy-portal service is running"
    else
        log_error "deploy-portal service failed to start"
        run_remote "sudo journalctl -u deploy-portal -n 50"
        exit 1
    fi
}

# Configure nginx
configure_nginx() {
    log_section "Nginx Configuration"

    log_info "Configuring nginx for deploy-portal..."

    # The auth gateway should have already configured nginx
    # We just need to verify it's working
    if run_remote "sudo nginx -t"; then
        log_success "Nginx configuration is valid"
    else
        log_error "Nginx configuration is invalid"
        exit 1
    fi

    log_info "Reloading nginx..."
    run_remote "sudo systemctl reload nginx"
    log_success "Nginx reloaded"
}

# Display next steps
show_next_steps() {
    log_section "Deployment Complete!"

    cat << EOF
${GREEN}Portal successfully deployed to:${NC}
  - Server: $TARGET_HOST ($TARGET_IP)
  - Domain: $DOMAIN

${YELLOW}Next Steps:${NC}

1. ${BLUE}Update DuckDNS:${NC}
   Update your DuckDNS domain to point to $TARGET_IP
   Visit: https://www.duckdns.org/

2. ${BLUE}Configure SSL (if needed):${NC}
   The portal is currently using self-signed certificates.
   To install Let's Encrypt certificates:
     ssh -i $SSH_KEY ubuntu@$TARGET_HOST
     sudo certbot --nginx -d $DOMAIN

3. ${BLUE}Test Portal Access:${NC}
   https://$DOMAIN

4. ${BLUE}Service Management:${NC}
   Start:   ssh -i $SSH_KEY ubuntu@$TARGET_HOST "sudo systemctl start deploy-portal"
   Stop:    ssh -i $SSH_KEY ubuntu@$TARGET_HOST "sudo systemctl stop deploy-portal"
   Restart: ssh -i $SSH_KEY ubuntu@$TARGET_HOST "sudo systemctl restart deploy-portal"
   Status:  ssh -i $SSH_KEY ubuntu@$TARGET_HOST "sudo systemctl status deploy-portal"
   Logs:    ssh -i $SSH_KEY ubuntu@$TARGET_HOST "sudo journalctl -u deploy-portal -f"

5. ${BLUE}Run Verification:${NC}
   $SCRIPT_DIR/verify-deployment.sh \\
     --target-host $TARGET_HOST \\
     --ssh-key $SSH_KEY \\
     --domain $DOMAIN

${GREEN}Configuration Summary:${NC}
  - AWS Region: $AWS_REGION
  - Security Group: $SECURITY_GROUP_ID
  - SSH Key: $(basename "$DEPLOY_SSH_KEY")
  - Cognito Pool: $COGNITO_POOL_ID
  - Cognito Region: $COGNITO_REGION

EOF
}

# Main execution
main() {
    log_section "Deploy Portal Instance - Automated Deployment"

    parse_args "$@"

    log_info "Deployment Configuration:"
    log_info "  Target: $TARGET_HOST"
    log_info "  Domain: $DOMAIN"
    log_info "  SSH Key: $SSH_KEY"
    log_info "  Deploy Key: $DEPLOY_SSH_KEY"
    log_info "  AWS Region: $AWS_REGION"
    log_info "  Cognito Region: $COGNITO_REGION"

    preflight_checks
    prepare_system
    deploy_auth_gateway
    deploy_portal
    configure_nginx
    show_next_steps

    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"
