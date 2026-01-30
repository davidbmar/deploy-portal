#!/bin/bash
# GitHub-based deployment script
# Clones repositories from GitHub instead of using rsync

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default repository URLs (can be overridden)
DEFAULT_DEPLOY_PORTAL_REPO="https://github.com/yourusername/deploy-portal.git"
DEFAULT_SSH_HELPER_REPO="https://github.com/yourusername/ssh-helper.git"
DEFAULT_WEBSITE_CLONER_REPO="https://github.com/yourusername/website-cloner.git"
DEFAULT_SECURITY_REPO="https://github.com/yourusername/deploy-portal-security.git"

# Installation directory
INSTALL_DIR="$HOME/src"

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  GitHub-based Deployment Script${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "This script will clone repositories from GitHub and set up"
echo "the deployment portal and related services."
echo ""

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo -e "${RED}✗ git is not installed${NC}"
    echo "Install git with: sudo apt-get install -y git"
    exit 1
fi

# Check if target is local or remote
echo -e "${BLUE}Deployment Target${NC}"
echo "1. Local (this server)"
echo "2. Remote (via SSH)"
read -p "Select target [1]: " DEPLOY_TARGET
DEPLOY_TARGET=${DEPLOY_TARGET:-1}
echo ""

if [ "$DEPLOY_TARGET" = "2" ]; then
    read -p "Remote host (IP or hostname): " REMOTE_HOST
    read -p "Remote user [ubuntu]: " REMOTE_USER
    REMOTE_USER=${REMOTE_USER:-ubuntu}
    read -p "SSH key path: " SSH_KEY_PATH
    SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"

    if [ ! -f "$SSH_KEY_PATH" ]; then
        echo -e "${RED}✗ SSH key not found: $SSH_KEY_PATH${NC}"
        exit 1
    fi

    SSH_CMD="ssh -i $SSH_KEY_PATH $REMOTE_USER@$REMOTE_HOST"
    SCP_CMD="scp -i $SSH_KEY_PATH"

    echo -e "${GREEN}✓ Remote target: $REMOTE_USER@$REMOTE_HOST${NC}"
    echo ""

    # Test connection
    echo "Testing SSH connection..."
    if ! $SSH_CMD "echo 'Connection successful'" &> /dev/null; then
        echo -e "${RED}✗ Cannot connect to remote host${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ SSH connection verified${NC}"
    echo ""
else
    SSH_CMD=""
    REMOTE_HOST="localhost"
    echo -e "${GREEN}✓ Local deployment${NC}"
    echo ""
fi

# Function to execute commands (local or remote)
execute_cmd() {
    if [ -z "$SSH_CMD" ]; then
        bash -c "$1"
    else
        $SSH_CMD "$1"
    fi
}

# Get repository URLs
echo -e "${BLUE}Repository Configuration${NC}"
echo "Enter GitHub repository URLs (press Enter to use defaults)"
echo ""

read -p "Deploy Portal repo [$DEFAULT_DEPLOY_PORTAL_REPO]: " DEPLOY_PORTAL_REPO
DEPLOY_PORTAL_REPO=${DEPLOY_PORTAL_REPO:-$DEFAULT_DEPLOY_PORTAL_REPO}

read -p "SSH Helper repo [$DEFAULT_SSH_HELPER_REPO]: " SSH_HELPER_REPO
SSH_HELPER_REPO=${SSH_HELPER_REPO:-$DEFAULT_SSH_HELPER_REPO}

read -p "Website Cloner repo [$DEFAULT_WEBSITE_CLONER_REPO]: " WEBSITE_CLONER_REPO
WEBSITE_CLONER_REPO=${WEBSITE_CLONER_REPO:-$DEFAULT_WEBSITE_CLONER_REPO}

read -p "Security Dashboard repo [$DEFAULT_SECURITY_REPO]: " SECURITY_REPO
SECURITY_REPO=${SECURITY_REPO:-$DEFAULT_SECURITY_REPO}
echo ""

# Get branches
echo -e "${BLUE}Branch Selection${NC}"
read -p "Deploy Portal branch [main]: " DEPLOY_PORTAL_BRANCH
DEPLOY_PORTAL_BRANCH=${DEPLOY_PORTAL_BRANCH:-main}

read -p "SSH Helper branch [main]: " SSH_HELPER_BRANCH
SSH_HELPER_BRANCH=${SSH_HELPER_BRANCH:-main}

read -p "Website Cloner branch [main]: " WEBSITE_CLONER_BRANCH
WEBSITE_CLONER_BRANCH=${WEBSITE_CLONER_BRANCH:-main}

read -p "Security Dashboard branch [main]: " SECURITY_BRANCH
SECURITY_BRANCH=${SECURITY_BRANCH:-main}
echo ""

# Confirm
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Deployment Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "Target: $REMOTE_HOST"
echo "Install directory: $INSTALL_DIR"
echo ""
echo "Repositories:"
echo "  - Deploy Portal: $DEPLOY_PORTAL_REPO ($DEPLOY_PORTAL_BRANCH)"
echo "  - SSH Helper: $SSH_HELPER_REPO ($SSH_HELPER_BRANCH)"
echo "  - Website Cloner: $WEBSITE_CLONER_REPO ($WEBSITE_CLONER_BRANCH)"
echo "  - Security Dashboard: $SECURITY_REPO ($SECURITY_BRANCH)"
echo ""
read -p "Proceed with deployment? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled"
    exit 0
fi
echo ""

# Create installation directory
echo -e "${BLUE}Creating installation directory...${NC}"
execute_cmd "mkdir -p $INSTALL_DIR"
echo -e "${GREEN}✓ Directory created${NC}"
echo ""

# Clone repositories
echo -e "${BLUE}Cloning repositories...${NC}"

clone_repo() {
    local name=$1
    local repo=$2
    local branch=$3
    local target=$4

    echo "Cloning $name..."

    # Remove existing directory if present
    execute_cmd "rm -rf $INSTALL_DIR/$target"

    # Clone repository
    if [ -z "$SSH_CMD" ]; then
        git clone -b "$branch" "$repo" "$INSTALL_DIR/$target"
    else
        $SSH_CMD "git clone -b $branch $repo $INSTALL_DIR/$target"
    fi

    echo -e "${GREEN}✓ $name cloned${NC}"
}

clone_repo "Deploy Portal" "$DEPLOY_PORTAL_REPO" "$DEPLOY_PORTAL_BRANCH" "deploy-portal"
clone_repo "SSH Helper" "$SSH_HELPER_REPO" "$SSH_HELPER_BRANCH" "ssh-helper"
clone_repo "Website Cloner" "$WEBSITE_CLONER_REPO" "$WEBSITE_CLONER_BRANCH" "website-cloner"
clone_repo "Security Dashboard" "$SECURITY_REPO" "$SECURITY_BRANCH" "deploy-portal-security"
echo ""

# Run infrastructure install
echo -e "${BLUE}Installing infrastructure dependencies...${NC}"
if execute_cmd "cd $INSTALL_DIR/deploy-portal && bash scripts/infrastructure-install.sh"; then
    echo -e "${GREEN}✓ Infrastructure installed${NC}"
else
    echo -e "${YELLOW}⚠ Infrastructure install completed with warnings${NC}"
fi
echo ""

# Run bootstrap scripts
echo -e "${BLUE}Bootstrapping services...${NC}"

bootstrap_service() {
    local name=$1
    local path=$2

    echo "Bootstrapping $name..."

    if execute_cmd "cd $INSTALL_DIR/$path && bash bootstrap.sh"; then
        echo -e "${GREEN}✓ $name bootstrapped${NC}"
    else
        echo -e "${RED}✗ $name bootstrap failed${NC}"
        return 1
    fi
}

bootstrap_service "Deploy Portal" "deploy-portal"
bootstrap_service "SSH Helper" "ssh-helper"
bootstrap_service "Website Cloner" "website-cloner"
bootstrap_service "Security Dashboard" "deploy-portal-security"
echo ""

# Configure nginx
echo -e "${BLUE}Configuring nginx...${NC}"
if execute_cmd "cd $INSTALL_DIR/deploy-portal && sudo bash scripts/configure-nginx.sh"; then
    echo -e "${GREEN}✓ nginx configured${NC}"
else
    echo -e "${YELLOW}⚠ nginx configuration may need manual adjustment${NC}"
fi
echo ""

# Prompt for AWS configuration
echo -e "${BLUE}AWS Configuration${NC}"
echo "Do you want to configure AWS settings now?"
echo "(Required for deploy portal and SSH helper to work)"
read -p "Configure AWS now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -z "$SSH_CMD" ]; then
        bash "$INSTALL_DIR/deploy-portal/scripts/configure-aws-config.sh"
    else
        echo ""
        echo "Please run the following command on the remote server:"
        echo -e "${YELLOW}bash $INSTALL_DIR/deploy-portal/scripts/configure-aws-config.sh${NC}"
        echo ""
    fi
else
    echo ""
    echo -e "${YELLOW}⚠ Skipping AWS configuration${NC}"
    echo "Run this later: bash $INSTALL_DIR/deploy-portal/scripts/configure-aws-config.sh"
    echo ""
fi

# Display summary
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Deployment Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}✓ All repositories cloned and configured${NC}"
echo ""
echo "Services installed:"
echo "  - Deploy Portal: $INSTALL_DIR/deploy-portal"
echo "  - SSH Helper: $INSTALL_DIR/ssh-helper"
echo "  - Website Cloner: $INSTALL_DIR/website-cloner"
echo "  - Security Dashboard: $INSTALL_DIR/deploy-portal-security"
echo ""
echo "Next steps:"
echo ""
echo "1. Configure AWS settings (if not done already):"
echo "   ${YELLOW}bash $INSTALL_DIR/deploy-portal/scripts/configure-aws-config.sh${NC}"
echo ""
echo "2. Check service status:"
echo "   ${YELLOW}sudo systemctl status deploy-portal ssh-helper${NC}"
echo ""
echo "3. View logs:"
echo "   ${YELLOW}sudo journalctl -u deploy-portal -f${NC}"
echo "   ${YELLOW}sudo journalctl -u ssh-helper -f${NC}"
echo ""
echo "4. Access web interfaces:"
if [ "$REMOTE_HOST" = "localhost" ]; then
    PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "YOUR_IP")
    echo "   - Deploy Portal: http://$PUBLIC_IP/"
    echo "   - SSH Helper: http://$PUBLIC_IP/ssh"
else
    echo "   - Deploy Portal: http://$REMOTE_HOST/"
    echo "   - SSH Helper: http://$REMOTE_HOST/ssh"
fi
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
