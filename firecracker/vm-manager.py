#!/usr/bin/env python3
"""
Firecracker VM Manager
Manages Firecracker microVM lifecycle: create, start, stop, destroy
"""

import json
import os
import subprocess
import socket
import time
from pathlib import Path
from typing import Dict, Optional


class FirecrackerVM:
    """Manages a single Firecracker microVM instance"""

    def __init__(
        self,
        vm_id: str,
        vcpu_count: int = 2,
        mem_size_mib: int = 512,
        kernel_path: str = "/opt/firecracker/kernels/vmlinux.bin",
        rootfs_path: str = "/opt/firecracker/rootfs/ubuntu-docker.ext4",
        tap_device: Optional[str] = None,
    ):
        self.vm_id = vm_id
        self.vcpu_count = vcpu_count
        self.mem_size_mib = mem_size_mib
        self.kernel_path = kernel_path
        self.rootfs_path = rootfs_path
        self.tap_device = tap_device or f"tap-{vm_id}"

        # Paths
        self.vm_dir = Path(f"/opt/firecracker/vms/{vm_id}")
        self.socket_path = self.vm_dir / "firecracker.sock"
        self.log_path = self.vm_dir / "firecracker.log"
        self.metrics_path = self.vm_dir / "metrics.json"
        self.config_path = self.vm_dir / "config.json"
        self.pid_file = self.vm_dir / "firecracker.pid"

        # VM state
        self.process: Optional[subprocess.Popen] = None

    def create_vm_config(self) -> Dict:
        """Generate Firecracker VM configuration"""
        config = {
            "boot-source": {
                "kernel_image_path": self.kernel_path,
                "boot_args": "console=ttyS0 reboot=k panic=1 pci=off ip=172.16.0.2::172.16.0.1:255.255.255.0::eth0:off",
            },
            "drives": [
                {
                    "drive_id": "rootfs",
                    "path_on_host": self.rootfs_path,
                    "is_root_device": True,
                    "is_read_only": False,
                }
            ],
            "machine-config": {
                "vcpu_count": self.vcpu_count,
                "mem_size_mib": self.mem_size_mib,
                "ht_enabled": False,
            },
            "network-interfaces": [
                {
                    "iface_id": "eth0",
                    "guest_mac": self._generate_mac(),
                    "host_dev_name": self.tap_device,
                }
            ],
            "logger": {
                "log_path": str(self.log_path),
                "level": "Info",
                "show_level": True,
                "show_log_origin": True,
            },
            "metrics": {
                "metrics_path": str(self.metrics_path),
            },
        }

        return config

    def setup_network(self) -> bool:
        """Setup TAP device and network bridge"""
        try:
            # Create TAP device
            subprocess.run(
                [
                    "sudo",
                    "ip",
                    "tuntap",
                    "add",
                    "dev",
                    self.tap_device,
                    "mode",
                    "tap",
                ],
                check=True,
                capture_output=True,
            )

            # Bring TAP device up
            subprocess.run(
                ["sudo", "ip", "link", "set", self.tap_device, "up"],
                check=True,
                capture_output=True,
            )

            # Add to bridge (create bridge if doesn't exist)
            bridge_name = "br-fc"
            if not self._bridge_exists(bridge_name):
                subprocess.run(
                    ["sudo", "ip", "link", "add", bridge_name, "type", "bridge"],
                    check=True,
                    capture_output=True,
                )
                subprocess.run(
                    ["sudo", "ip", "link", "set", bridge_name, "up"],
                    check=True,
                    capture_output=True,
                )
                subprocess.run(
                    ["sudo", "ip", "addr", "add", "172.16.0.1/24", "dev", bridge_name],
                    check=True,
                    capture_output=True,
                )

            # Add TAP to bridge
            subprocess.run(
                ["sudo", "ip", "link", "set", self.tap_device, "master", bridge_name],
                check=True,
                capture_output=True,
            )

            print(f"✓ Network configured: {self.tap_device} -> {bridge_name}")
            return True

        except subprocess.CalledProcessError as e:
            print(f"✗ Network setup failed: {e.stderr.decode()}")
            return False

    def start(self) -> bool:
        """Start the Firecracker VM"""
        # Create VM directory
        self.vm_dir.mkdir(parents=True, exist_ok=True)

        # Setup network
        if not self.setup_network():
            return False

        # Generate and save config
        config = self.create_vm_config()
        with open(self.config_path, "w") as f:
            json.dump(config, f, indent=2)

        # Remove old socket if exists
        if self.socket_path.exists():
            self.socket_path.unlink()

        # Start Firecracker process
        cmd = [
            "sudo",
            "firecracker",
            "--api-sock",
            str(self.socket_path),
            "--config-file",
            str(self.config_path),
        ]

        try:
            self.process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

            # Save PID
            with open(self.pid_file, "w") as f:
                f.write(str(self.process.pid))

            # Wait for VM to start
            time.sleep(2)

            if self.process.poll() is None:
                print(f"✓ VM started: {self.vm_id} (PID: {self.process.pid})")
                return True
            else:
                stdout, stderr = self.process.communicate()
                print(f"✗ VM failed to start:")
                print(stderr.decode())
                return False

        except Exception as e:
            print(f"✗ Failed to start VM: {e}")
            return False

    def stop(self) -> bool:
        """Stop the Firecracker VM"""
        if self.pid_file.exists():
            with open(self.pid_file, "r") as f:
                pid = int(f.read().strip())

            try:
                subprocess.run(["sudo", "kill", str(pid)], check=True)
                print(f"✓ VM stopped: {self.vm_id}")

                # Cleanup TAP device
                subprocess.run(
                    ["sudo", "ip", "link", "delete", self.tap_device],
                    check=False,
                    capture_output=True,
                )

                return True
            except subprocess.CalledProcessError:
                print(f"✗ Failed to stop VM (PID {pid} not found)")
                return False
        else:
            print(f"✗ PID file not found for {self.vm_id}")
            return False

    def is_running(self) -> bool:
        """Check if VM is running"""
        if not self.pid_file.exists():
            return False

        with open(self.pid_file, "r") as f:
            pid = int(f.read().strip())

        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False

    def _generate_mac(self) -> str:
        """Generate a MAC address for the VM"""
        # Use VM ID hash to generate consistent MAC
        vm_hash = hash(self.vm_id) % (2**32)
        return f"02:FC:00:{vm_hash >> 16:02x}:{(vm_hash >> 8) & 0xFF:02x}:{vm_hash & 0xFF:02x}"

    def _bridge_exists(self, bridge_name: str) -> bool:
        """Check if network bridge exists"""
        result = subprocess.run(
            ["ip", "link", "show", bridge_name],
            capture_output=True,
        )
        return result.returncode == 0


def main():
    """CLI interface for VM manager"""
    import argparse

    parser = argparse.ArgumentParser(description="Firecracker VM Manager")
    parser.add_argument("command", choices=["start", "stop", "status"], help="Command")
    parser.add_argument("vm_id", help="VM identifier")
    parser.add_argument("--vcpus", type=int, default=2, help="Number of vCPUs")
    parser.add_argument("--memory", type=int, default=512, help="Memory in MiB")
    parser.add_argument(
        "--kernel",
        default="/opt/firecracker/kernels/vmlinux.bin",
        help="Kernel path",
    )
    parser.add_argument(
        "--rootfs",
        default="/opt/firecracker/rootfs/ubuntu-docker.ext4",
        help="Root filesystem path",
    )

    args = parser.parse_args()

    vm = FirecrackerVM(
        vm_id=args.vm_id,
        vcpu_count=args.vcpus,
        mem_size_mib=args.memory,
        kernel_path=args.kernel,
        rootfs_path=args.rootfs,
    )

    if args.command == "start":
        if vm.start():
            print(f"\n✓ VM {args.vm_id} is running")
            print(f"  Config: {vm.config_path}")
            print(f"  Logs: {vm.log_path}")
            exit(0)
        else:
            print(f"\n✗ Failed to start VM {args.vm_id}")
            exit(1)

    elif args.command == "stop":
        if vm.stop():
            print(f"\n✓ VM {args.vm_id} stopped")
            exit(0)
        else:
            print(f"\n✗ Failed to stop VM {args.vm_id}")
            exit(1)

    elif args.command == "status":
        if vm.is_running():
            print(f"✓ VM {args.vm_id} is running")
            exit(0)
        else:
            print(f"✗ VM {args.vm_id} is not running")
            exit(1)


if __name__ == "__main__":
    main()
