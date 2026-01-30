#!/bin/bash
#
# verify-deployment.sh
#
# Comprehensive verification of deploy-portal deployment
#
# Usage:
#   ./verify-deployment.sh \
#     --target-host ubuntu@44.244.76.51 \
#     --ssh-key /path/to/key.pem \
#     --domain capsule-product-deploy.duckdns.org

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Parameters
TARGET_HOST=""
SSH_KEY=""
DOMAIN=""

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_check() {
    echo -e "${BLUE}[CHECK]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_CHECKS++))
    ((TOTAL_CHECKS++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_CHECKS++))
    ((TOTAL_CHECKS++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNING_CHECKS++))
    ((TOTAL_CHECKS++))
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

Verify deploy-portal deployment and configuration.

Required Options:
  --target-host HOST     Target host (e.g., ubuntu@44.244.76.51)
  --ssh-key PATH         SSH key to connect to target
  --domain DOMAIN        Domain name to verify

Example:
  $0 \\
    --target-host ubuntu@44.244.76.51 \\
    --ssh-key ~/.ssh/my-key.pem \\
    --domain capsule-product-deploy.duckdns.org

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
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --help)
                usage
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done

    if [[ -z "$TARGET_HOST" || -z "$SSH_KEY" || -z "$DOMAIN" ]]; then
        echo "All parameters are required"
        usage
    fi

    SSH_KEY=$(realpath "$SSH_KEY")
}

# SSH helper
run_remote() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$TARGET_HOST" "$1" 2>/dev/null
}

# Verify system services
verify_services() {
    log_section "System Services"

    # Check nginx
    log_check "nginx service status"
    if run_remote "sudo systemctl is-active nginx" | grep -q "active"; then
        log_pass "nginx is active and running"
    else
        log_fail "nginx is not running"
    fi

    log_check "nginx listening on port 443"
    if run_remote "sudo netstat -tuln | grep ':443'" > /dev/null; then
        log_pass "nginx listening on port 443"
    else
        log_fail "nginx not listening on port 443"
    fi

    log_check "nginx auto-start enabled"
    if run_remote "sudo systemctl is-enabled nginx" | grep -q "enabled"; then
        log_pass "nginx auto-start enabled"
    else
        log_warning "nginx auto-start not enabled"
    fi

    # Check oauth2-proxy
    log_check "oauth2-proxy service status"
    if run_remote "sudo systemctl is-active oauth2-proxy" | grep -q "active"; then
        log_pass "oauth2-proxy is active and running"
    else
        log_fail "oauth2-proxy is not running"
    fi

    log_check "oauth2-proxy listening on port 4180"
    if run_remote "sudo netstat -tuln | grep ':4180'" > /dev/null; then
        log_pass "oauth2-proxy listening on port 4180"
    else
        log_fail "oauth2-proxy not listening on port 4180"
    fi

    # Check deploy-portal
    log_check "deploy-portal service status"
    if run_remote "sudo systemctl is-active deploy-portal" | grep -q "active"; then
        log_pass "deploy-portal is active and running"
    else
        log_fail "deploy-portal is not running"
    fi

    log_check "deploy-portal listening on port 5000"
    if run_remote "sudo netstat -tuln | grep ':5000'" > /dev/null; then
        log_pass "deploy-portal listening on port 5000"
    else
        log_fail "deploy-portal not listening on port 5000"
    fi

    log_check "deploy-portal auto-start enabled"
    if run_remote "sudo systemctl is-enabled deploy-portal" | grep -q "enabled"; then
        log_pass "deploy-portal auto-start enabled"
    else
        log_warning "deploy-portal auto-start not enabled"
    fi
}

# Verify configuration
verify_configuration() {
    log_section "Configuration"

    # Check if .ec2-config.env exists
    log_check ".ec2-config.env file exists"
    if run_remote "test -f /home/ubuntu/.ec2-config.env"; then
        log_pass ".ec2-config.env exists"

        # Check SSH_KEY_PATH
        log_check "SSH_KEY_PATH configured"
        local ssh_key_path=$(run_remote "grep '^export SSH_KEY_PATH=' /home/ubuntu/.ec2-config.env | cut -d'=' -f2")
        if [[ -n "$ssh_key_path" ]]; then
            log_pass "SSH_KEY_PATH configured: $ssh_key_path"
        else
            log_fail "SSH_KEY_PATH not found in .ec2-config.env"
        fi

        # Check SSH_KEY_NAME
        log_check "SSH_KEY_NAME configured"
        local ssh_key_name=$(run_remote "grep '^export SSH_KEY_NAME=' /home/ubuntu/.ec2-config.env | cut -d'=' -f2")
        if [[ -n "$ssh_key_name" ]]; then
            log_pass "SSH_KEY_NAME configured: $ssh_key_name"
        else
            log_fail "SSH_KEY_NAME not found in .ec2-config.env"
        fi

        # Check AWS_REGION
        log_check "AWS_REGION configured"
        local aws_region=$(run_remote "grep '^export AWS_REGION=' /home/ubuntu/.ec2-config.env | cut -d'=' -f2")
        if [[ -n "$aws_region" ]]; then
            log_pass "AWS_REGION configured: $aws_region"
        else
            log_warning "AWS_REGION not found in .ec2-config.env"
        fi

        # Check SECURITY_GROUP_ID
        log_check "SECURITY_GROUP_ID configured"
        local sg_id=$(run_remote "grep '^export SECURITY_GROUP_ID=' /home/ubuntu/.ec2-config.env | cut -d'=' -f2")
        if [[ -n "$sg_id" ]]; then
            log_pass "SECURITY_GROUP_ID configured: $sg_id"
        else
            log_warning "SECURITY_GROUP_ID not found in .ec2-config.env"
        fi
    else
        log_fail ".ec2-config.env not found"
    fi

    # Check deploy-portal directory
    log_check "deploy-portal directory exists"
    if run_remote "test -d /home/ubuntu/src/deploy-portal"; then
        log_pass "deploy-portal directory exists"
    else
        log_fail "deploy-portal directory not found"
    fi

    # Check virtual environment
    log_check "Python virtual environment exists"
    if run_remote "test -d /home/ubuntu/src/deploy-portal/venv"; then
        log_pass "Python virtual environment exists"
    else
        log_fail "Python virtual environment not found"
    fi
}

# Verify file permissions
verify_permissions() {
    log_section "File Permissions"

    # Get SSH key path from config
    local ssh_key_path=$(run_remote "grep '^export SSH_KEY_PATH=' /home/ubuntu/.ec2-config.env 2>/dev/null | cut -d'=' -f2" || echo "")

    if [[ -n "$ssh_key_path" ]]; then
        log_check "SSH key file exists: $ssh_key_path"
        if run_remote "test -f $ssh_key_path"; then
            log_pass "SSH key file exists"

            log_check "SSH key has correct permissions (400)"
            local perms=$(run_remote "stat -c '%a' $ssh_key_path")
            if [[ "$perms" == "400" ]]; then
                log_pass "SSH key has 400 permissions"
            else
                log_fail "SSH key has incorrect permissions: $perms (expected 400)"
            fi

            log_check "SSH key readable by ubuntu user"
            if run_remote "test -r $ssh_key_path"; then
                log_pass "SSH key is readable"
            else
                log_fail "SSH key is not readable"
            fi
        else
            log_fail "SSH key file not found: $ssh_key_path"
        fi
    else
        log_warning "SSH_KEY_PATH not configured, skipping permission checks"
    fi

    # Check deploy-portal directory ownership
    log_check "deploy-portal directory ownership"
    if run_remote "test -O /home/ubuntu/src/deploy-portal"; then
        log_pass "deploy-portal directory owned by ubuntu"
    else
        log_warning "deploy-portal directory not owned by ubuntu"
    fi
}

# Verify functionality
verify_functionality() {
    log_section "Functionality Tests"

    # Test portal responds on localhost
    log_check "Portal responds on localhost:5000"
    if run_remote "curl -s -o /dev/null -w '%{http_code}' http://localhost:5000" | grep -q "200\|302"; then
        log_pass "Portal responds on localhost:5000"
    else
        log_fail "Portal not responding on localhost:5000"
    fi

    # Test Python can import config
    log_check "Python can import config.py"
    if run_remote "cd /home/ubuntu/src/deploy-portal && source venv/bin/activate && python3 -c 'from config import Config; print(Config.SSH_KEY_PATH)'" > /dev/null 2>&1; then
        log_pass "config.py imports successfully"
    else
        log_fail "config.py import failed"
    fi

    # Test config loads SSH key path
    log_check "Config loads SSH_KEY_PATH correctly"
    local loaded_path=$(run_remote "cd /home/ubuntu/src/deploy-portal && source venv/bin/activate && python3 -c 'from config import Config; print(Config.SSH_KEY_PATH)' 2>/dev/null" || echo "")
    if [[ -n "$loaded_path" ]]; then
        log_pass "SSH_KEY_PATH loaded: $loaded_path"
    else
        log_fail "Could not load SSH_KEY_PATH from config"
    fi
}

# Verify network and DNS
verify_network() {
    log_section "Network & DNS"

    # Test DNS resolution
    log_check "Domain DNS resolution"
    if host "$DOMAIN" > /dev/null 2>&1; then
        local resolved_ip=$(host "$DOMAIN" | grep "has address" | awk '{print $4}' | head -n1)
        log_pass "Domain resolves to: $resolved_ip"

        # Check if it resolves to target
        local target_ip=$(echo "$TARGET_HOST" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || run_remote "curl -s http://169.254.169.254/latest/meta-data/public-ipv4")
        if [[ "$resolved_ip" == "$target_ip" ]]; then
            log_pass "Domain resolves to correct IP"
        else
            log_warning "Domain resolves to $resolved_ip, expected $target_ip"
        fi
    else
        log_fail "Domain does not resolve: $DOMAIN"
    fi

    # Test HTTPS accessibility (from local machine)
    log_check "HTTPS accessibility (external)"
    if curl -s -k -o /dev/null -w '%{http_code}' "https://$DOMAIN" | grep -q "200\|302"; then
        log_pass "HTTPS accessible from external network"
    else
        log_warning "HTTPS not accessible (may need DNS propagation or SSL setup)"
    fi

    # Check SSL certificate
    log_check "SSL certificate presence"
    if run_remote "sudo test -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem"; then
        log_pass "Let's Encrypt certificate found"
    elif run_remote "sudo test -f /etc/nginx/ssl/nginx-selfsigned.crt"; then
        log_warning "Self-signed certificate in use (consider Let's Encrypt)"
    else
        log_warning "No SSL certificate found"
    fi
}

# Generate report
generate_report() {
    log_section "Verification Summary"

    echo "Total Checks: $TOTAL_CHECKS"
    echo -e "${GREEN}Passed: $PASSED_CHECKS${NC}"
    echo -e "${RED}Failed: $FAILED_CHECKS${NC}"
    echo -e "${YELLOW}Warnings: $WARNING_CHECKS${NC}"
    echo ""

    if [[ $FAILED_CHECKS -eq 0 ]]; then
        echo -e "${GREEN}All critical checks passed!${NC}"
        echo ""
        echo "Deployment is healthy and ready for use."
        echo "Access your portal at: https://$DOMAIN"
        return 0
    else
        echo -e "${RED}Some checks failed. Please review the output above.${NC}"
        echo ""
        echo "Common issues:"
        echo "  - DNS not propagated (wait a few minutes)"
        echo "  - SSL certificate not configured (run certbot)"
        echo "  - Services not started (check systemctl status)"
        echo "  - Firewall blocking ports (check security groups)"
        return 1
    fi
}

# Main
main() {
    parse_args "$@"

    log_section "Deploy Portal Verification"
    log_info "Target: $TARGET_HOST"
    log_info "Domain: $DOMAIN"
    echo ""

    # Test SSH connection first
    log_check "SSH connection"
    if run_remote "echo 'Connection successful'" > /dev/null; then
        log_pass "SSH connection successful"
    else
        log_fail "Cannot connect via SSH"
        exit 1
    fi

    # Run all verification steps
    verify_services
    verify_configuration
    verify_permissions
    verify_functionality
    verify_network

    # Generate final report
    generate_report
}

main "$@"
