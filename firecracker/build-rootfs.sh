#!/bin/bash
#
# Build Root Filesystem for Firecracker
# Creates a minimal Ubuntu rootfs with Docker installed
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ROOTFS_SIZE="${ROOTFS_SIZE:-2G}"
ROOTFS_PATH="${ROOTFS_PATH:-/opt/firecracker/rootfs/ubuntu-docker.ext4}"
MOUNT_POINT="/tmp/rootfs-build"
UBUNTU_RELEASE="${UBUNTU_RELEASE:-jammy}"

echo -e "${YELLOW}=== Building Firecracker Root Filesystem ===${NC}\n"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}This script must be run with sudo${NC}"
    exit 1
fi

# Check dependencies
for tool in debootstrap mkfs.ext4 qemu-nbd; do
    if ! command -v $tool &> /dev/null; then
        echo -e "${RED}Required tool not found: $tool${NC}"
        echo "Install with: sudo apt-get install debootstrap e2fsprogs qemu-utils"
        exit 1
    fi
done

# Create rootfs image
echo -e "${GREEN}Creating ${ROOTFS_SIZE} ext4 image...${NC}"
dd if=/dev/zero of="$ROOTFS_PATH" bs=1M count=$(numfmt --from=iec $ROOTFS_SIZE | awk '{print $1/1024/1024}') status=progress
mkfs.ext4 -F "$ROOTFS_PATH"

# Mount rootfs
echo -e "${GREEN}Mounting rootfs...${NC}"
mkdir -p "$MOUNT_POINT"
mount -o loop "$ROOTFS_PATH" "$MOUNT_POINT"

# Ensure cleanup on exit
cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    umount "$MOUNT_POINT" 2>/dev/null || true
    rm -rf "$MOUNT_POINT"
}
trap cleanup EXIT

# Bootstrap Ubuntu
echo -e "${GREEN}Bootstrapping Ubuntu $UBUNTU_RELEASE...${NC}"
debootstrap --arch=amd64 --variant=minbase "$UBUNTU_RELEASE" "$MOUNT_POINT" http://archive.ubuntu.com/ubuntu/

# Configure basic system
echo -e "${GREEN}Configuring system...${NC}"

# Set hostname
echo "firecracker-vm" > "$MOUNT_POINT/etc/hostname"

# Configure network
cat > "$MOUNT_POINT/etc/network/interfaces" << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

# Set up DNS
cat > "$MOUNT_POINT/etc/resolv.conf" << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

# Configure apt sources
cat > "$MOUNT_POINT/etc/apt/sources.list" << EOF
deb http://archive.ubuntu.com/ubuntu $UBUNTU_RELEASE main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $UBUNTU_RELEASE-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $UBUNTU_RELEASE-security main restricted universe multiverse
EOF

# Chroot and install packages
echo -e "${GREEN}Installing packages...${NC}"
chroot "$MOUNT_POINT" /bin/bash << 'CHROOT_EOF'
set -euo pipefail

# Update package lists
apt-get update

# Install essential packages
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    systemd \
    systemd-sysv \
    udev \
    openssh-server \
    curl \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
    init

# Install Docker
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-compose-plugin

# Enable Docker service
systemctl enable docker

# Set root password (change this!)
echo "root:firecracker" | chpasswd

# Enable SSH
systemctl enable ssh

# Cleanup
apt-get clean
rm -rf /var/lib/apt/lists/*

CHROOT_EOF

# Create init script for VM
cat > "$MOUNT_POINT/usr/local/bin/vm-init.sh" << 'EOF'
#!/bin/bash
# VM initialization script
# Runs on boot to configure networking and services

set -euo pipefail

# Configure network from kernel command line
if grep -q "ip=" /proc/cmdline; then
    IP=$(grep -oP 'ip=\S+' /proc/cmdline | cut -d= -f2)
    ifconfig eth0 $IP up
fi

# Start Docker if not running
if ! systemctl is-active --quiet docker; then
    systemctl start docker
fi

echo "VM initialized successfully"
EOF

chmod +x "$MOUNT_POINT/usr/local/bin/vm-init.sh"

# Create systemd service for init script
cat > "$MOUNT_POINT/etc/systemd/system/vm-init.service" << 'EOF'
[Unit]
Description=Firecracker VM Initialization
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/vm-init.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

chroot "$MOUNT_POINT" systemctl enable vm-init.service

echo ""
echo -e "${GREEN}=== Root Filesystem Built Successfully ===${NC}"
echo ""
echo "Location: $ROOTFS_PATH"
echo "Size: $(du -h $ROOTFS_PATH | cut -f1)"
echo "Mount point used: $MOUNT_POINT"
echo ""
echo -e "${YELLOW}Default credentials:${NC}"
echo "  Username: root"
echo "  Password: firecracker"
echo ""
echo -e "${RED}IMPORTANT: Change the root password in production!${NC}"
echo ""
