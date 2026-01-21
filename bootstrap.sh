#!/bin/bash
set -euo pipefail

# Deploy Portal Bootstrap Script
# Sets up the Flask deployment management application

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[DEPLOY-PORTAL]${NC} $1"
}

error() {
    echo -e "${RED}[DEPLOY-PORTAL ERROR]${NC} $1"
    exit 1
}

warn() {
    echo -e "${YELLOW}[DEPLOY-PORTAL WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[DEPLOY-PORTAL INFO]${NC} $1"
}

load_config() {
    log "Loading configuration..."

    # Try to load from global config first
    if [ -f "/home/ubuntu/.ec2-config.env" ]; then
        source "/home/ubuntu/.ec2-config.env"
        log "Loaded config from /home/ubuntu/.ec2-config.env"
    elif [ -f "$SCRIPT_DIR/config.env" ]; then
        source "$SCRIPT_DIR/config.env"
        log "Loaded config from $SCRIPT_DIR/config.env"
    else
        warn "No configuration file found, using defaults"
    fi

    # Set defaults if not provided
    AWS_REGION="${AWS_REGION:-us-east-1}"
    SECURITY_GROUP_ID="${SECURITY_GROUP_ID:-sg-0d6bbadbbd290b320}"
    SSH_KEY_NAME="${SSH_KEY_NAME:-deploy-key}"
    DEPLOYMENT_ROOT="${DEPLOYMENT_ROOT:-/home/ubuntu/deployments}"
    PORT_RANGE_START="${PORT_RANGE_START:-5001}"
    PORT_RANGE_END="${PORT_RANGE_END:-5999}"
    FLASK_PORT="${FLASK_PORT:-5000}"
    ACTIVITY_LOG_DIR="${ACTIVITY_LOG_DIR:-/var/log/deploy-sessions}"

    info "Configuration:"
    info "  AWS Region: $AWS_REGION"
    info "  Security Group: $SECURITY_GROUP_ID"
    info "  Deployment Root: $DEPLOYMENT_ROOT"
    info "  Port Range: $PORT_RANGE_START-$PORT_RANGE_END"
}

create_virtualenv() {
    log "Creating Python virtual environment..."

    if [ ! -d "$SCRIPT_DIR/venv" ]; then
        python3 -m venv "$SCRIPT_DIR/venv"
        log "Virtual environment created"
    else
        log "Virtual environment already exists"
    fi

    # Activate and install requirements
    source "$SCRIPT_DIR/venv/bin/activate"

    if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
        pip install --upgrade pip > /dev/null
        pip install -r "$SCRIPT_DIR/requirements.txt" > /dev/null
        log "Python dependencies installed"
    else
        warn "requirements.txt not found"
    fi

    deactivate
}

create_directories() {
    log "Creating required directories..."

    # Deployment directories
    mkdir -p "$DEPLOYMENT_ROOT"
    mkdir -p "$DEPLOYMENT_ROOT/.backups"

    # Data directories
    mkdir -p "$SCRIPT_DIR/data"
    mkdir -p "$SCRIPT_DIR/keys"
    mkdir -p "$SCRIPT_DIR/logs"

    # Activity log directory (requires sudo)
    if [ ! -d "$ACTIVITY_LOG_DIR" ]; then
        sudo mkdir -p "$ACTIVITY_LOG_DIR"
        sudo chown ubuntu:ubuntu "$ACTIVITY_LOG_DIR"
    fi

    # Automation scripts directory
    mkdir -p "$SCRIPT_DIR/automation/scripts"

    log "Directories created"
}

generate_ssh_key() {
    log "Checking SSH key..."

    local key_path="$SCRIPT_DIR/keys/${SSH_KEY_NAME}.pem"

    if [ ! -f "$key_path" ]; then
        warn "SSH key not found at $key_path"
        warn "Please copy your SSH key to $key_path"
        warn "Or generate a new one with: ssh-keygen -t rsa -b 4096 -f $key_path -N ''"
    else
        chmod 600 "$key_path"
        log "SSH key found and permissions set"
    fi
}

initialize_data_files() {
    log "Initializing data files..."

    # Create empty registry file if it doesn't exist
    if [ ! -f "$DEPLOYMENT_ROOT/.registry.json" ]; then
        echo '{"deployments": {}, "ports": {}}' > "$DEPLOYMENT_ROOT/.registry.json"
        log "Created registry file"
    else
        log "Registry file already exists"
    fi

    # Create app registry if needed
    if [ ! -f "$SCRIPT_DIR/data/app-registry.json" ]; then
        echo '{}' > "$SCRIPT_DIR/data/app-registry.json"
        log "Created app registry"
    fi

    # Create port registry if needed
    if [ ! -f "$SCRIPT_DIR/data/port-registry.json" ]; then
        echo '{}' > "$SCRIPT_DIR/data/port-registry.json"
        log "Created port registry"
    fi
}

install_systemd_service() {
    log "Installing systemd service..."

    if [ ! -f "$SCRIPT_DIR/systemd/deploy-portal.service.template" ]; then
        error "Service template not found at $SCRIPT_DIR/systemd/deploy-portal.service.template"
    fi

    # Replace template variables
    sed "s|{{WORKING_DIRECTORY}}|$SCRIPT_DIR|g" \
        "$SCRIPT_DIR/systemd/deploy-portal.service.template" | \
        sudo tee /etc/systemd/system/deploy-portal.service > /dev/null

    sudo systemctl daemon-reload
    sudo systemctl enable deploy-portal

    log "Systemd service installed"
}

install_nginx_configs() {
    log "Installing nginx configurations..."

    # Check if nginx include directories exist
    if [ ! -d "/etc/nginx/conf.d/system-upstreams" ]; then
        error "Nginx include directory not found. Run auth gateway bootstrap first."
    fi

    # Copy upstream config
    sudo cp "$SCRIPT_DIR/nginx/upstream.conf" \
        /etc/nginx/conf.d/system-upstreams/deploy-portal.conf

    # Copy routes config
    sudo cp "$SCRIPT_DIR/nginx/routes.conf" \
        /etc/nginx/conf.d/routes/deploy-portal.conf

    log "Nginx configurations installed"
}

<<<<<<< HEAD
=======
fix_static_permissions() {
    log "Fixing static file permissions..."

    # Ensure nginx (www-data) can access files in /home/ubuntu/
    # Without this, nginx gets "permission denied" even if files are 755
    chmod 755 /home/ubuntu
    chmod 755 /home/ubuntu/src

    # Ensure static files are readable by nginx
    if [ -d "$SCRIPT_DIR/static" ]; then
        chmod -R 755 "$SCRIPT_DIR/static"
        log "Static file permissions fixed (including parent directories)"
    else
        warn "Static directory not found at $SCRIPT_DIR/static"
    fi
}

>>>>>>> e344ad0175ba9e6362c6f0326477971cf0eb0720
start_service() {
    log "Starting deploy-portal service..."

    sudo systemctl restart deploy-portal

    # Wait a moment for service to start
    sleep 2

    if systemctl is-active --quiet deploy-portal; then
        log "Deploy-portal service started successfully"
    else
        error "Failed to start deploy-portal service. Check logs with: sudo journalctl -u deploy-portal -n 50"
    fi
}

verify_installation() {
    log "Verifying installation..."

    # Check if service is running
    if ! systemctl is-active --quiet deploy-portal; then
        error "deploy-portal service is not running"
    fi

    # Check if app is responding
    if curl -s http://localhost:${FLASK_PORT}/ > /dev/null; then
        log "Deploy-portal is responding on port $FLASK_PORT"
    else
        warn "Deploy-portal is not responding on port $FLASK_PORT"
    fi

    log "Verification complete"
}

main() {
    log "Starting deploy-portal bootstrap..."

    load_config
    create_virtualenv
    create_directories
    generate_ssh_key
    initialize_data_files
    install_systemd_service
    install_nginx_configs
<<<<<<< HEAD
=======
    fix_static_permissions
>>>>>>> e344ad0175ba9e6362c6f0326477971cf0eb0720
    start_service
    verify_installation

    log "Deploy-portal bootstrap complete!"
    info ""
    info "Service status: sudo systemctl status deploy-portal"
    info "View logs: sudo journalctl -u deploy-portal -f"
    info "Access at: https://$(hostname -I | awk '{print $1}')/"
}

main "$@"
