#!/bin/bash
#
# Install Firecracker MicroVM
# Downloads and installs Firecracker and Jailer binaries
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FIRECRACKER_VERSION="${FIRECRACKER_VERSION:-v1.6.0}"
ARCH="$(uname -m)"
INSTALL_DIR="/usr/local/bin"
TMP_DIR="/tmp/firecracker-install"

echo -e "${YELLOW}=== Installing Firecracker ${FIRECRACKER_VERSION} ===${NC}\n"

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}This script must be run with sudo${NC}"
    exit 1
fi

# Check architecture
if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "aarch64" ]; then
    echo -e "${RED}Unsupported architecture: $ARCH${NC}"
    exit 1
fi

# Create temp directory
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

# Download Firecracker
echo -e "${GREEN}Downloading Firecracker...${NC}"
RELEASE_URL="https://github.com/firecracker-microvm/firecracker/releases/download/${FIRECRACKER_VERSION}/firecracker-${FIRECRACKER_VERSION}-${ARCH}.tgz"

if ! curl -L -o firecracker.tgz "$RELEASE_URL"; then
    echo -e "${RED}Failed to download Firecracker${NC}"
    exit 1
fi

# Extract
echo -e "${GREEN}Extracting...${NC}"
tar -xzf firecracker.tgz

# Find and install binaries
if [ -f "release-${FIRECRACKER_VERSION}-${ARCH}/firecracker-${FIRECRACKER_VERSION}-${ARCH}" ]; then
    echo -e "${GREEN}Installing firecracker to ${INSTALL_DIR}${NC}"
    cp "release-${FIRECRACKER_VERSION}-${ARCH}/firecracker-${FIRECRACKER_VERSION}-${ARCH}" "${INSTALL_DIR}/firecracker"
    chmod +x "${INSTALL_DIR}/firecracker"
else
    echo -e "${RED}Firecracker binary not found in archive${NC}"
    exit 1
fi

if [ -f "release-${FIRECRACKER_VERSION}-${ARCH}/jailer-${FIRECRACKER_VERSION}-${ARCH}" ]; then
    echo -e "${GREEN}Installing jailer to ${INSTALL_DIR}${NC}"
    cp "release-${FIRECRACKER_VERSION}-${ARCH}/jailer-${FIRECRACKER_VERSION}-${ARCH}" "${INSTALL_DIR}/jailer"
    chmod +x "${INSTALL_DIR}/jailer"
else
    echo -e "${YELLOW}Warning: Jailer binary not found${NC}"
fi

# Verify installation
echo ""
echo -e "${GREEN}Verifying installation...${NC}"
if firecracker --version; then
    echo -e "${GREEN}✓ Firecracker installed successfully${NC}"
else
    echo -e "${RED}✗ Firecracker installation failed${NC}"
    exit 1
fi

if jailer --version; then
    echo -e "${GREEN}✓ Jailer installed successfully${NC}"
else
    echo -e "${YELLOW}⚠ Jailer not available${NC}"
fi

# Setup directories
echo ""
echo -e "${GREEN}Setting up Firecracker directories...${NC}"
mkdir -p /opt/firecracker/{kernels,rootfs,vms}
chmod 755 /opt/firecracker
echo -e "${GREEN}✓ Created /opt/firecracker/{kernels,rootfs,vms}${NC}"

# Download default kernel if not exists
KERNEL_PATH="/opt/firecracker/kernels/vmlinux.bin"
if [ ! -f "$KERNEL_PATH" ]; then
    echo ""
    echo -e "${GREEN}Downloading default kernel...${NC}"
    KERNEL_URL="https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/${ARCH}/kernels/vmlinux.bin"

    if curl -L -o "$KERNEL_PATH" "$KERNEL_URL"; then
        chmod 644 "$KERNEL_PATH"
        echo -e "${GREEN}✓ Kernel downloaded to $KERNEL_PATH${NC}"
    else
        echo -e "${YELLOW}⚠ Failed to download kernel. You'll need to provide your own.${NC}"
    fi
fi

# Cleanup
cd /
rm -rf "$TMP_DIR"

echo ""
echo -e "${GREEN}=== Installation Complete ===${NC}"
echo ""
echo "Firecracker: $(firecracker --version)"
echo "Install location: $INSTALL_DIR"
echo "Data directory: /opt/firecracker"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Build a root filesystem: bash build-rootfs.sh"
echo "  2. Create a VM config with vm-manager.py"
echo ""
