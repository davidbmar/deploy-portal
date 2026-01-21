#!/bin/bash
#
# Security Monitoring Script
# Monitors for security violations and suspicious activity
# Designed to run as a cron job every 15 minutes
#

set -euo pipefail

# Configuration
LOG_FILE="${LOG_FILE:-/var/log/security-monitor.log}"
ALERT_THRESHOLD="${ALERT_THRESHOLD:-5}"  # Alert if more than 5 violations in 15 minutes
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Ensure log file exists and is writable
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/security-monitor.log"

log() {
    echo "[$TIMESTAMP] $*" | tee -a "$LOG_FILE"
}

alert() {
    echo "[$TIMESTAMP] [ALERT] $*" | tee -a "$LOG_FILE"
}

# Monitor 1: AppArmor Violations
log "=== Monitoring AppArmor violations ==="

if command -v ausearch &> /dev/null; then
    # Check for AppArmor denials in the last 15 minutes
    apparmor_violations=$(sudo ausearch -m AVC -ts recent 2>/dev/null | grep -c "apparmor=" || echo "0")

    if [ "$apparmor_violations" -gt 0 ]; then
        log "Found $apparmor_violations AppArmor violation(s)"

        if [ "$apparmor_violations" -gt "$ALERT_THRESHOLD" ]; then
            alert "HIGH: $apparmor_violations AppArmor violations (threshold: $ALERT_THRESHOLD)"

            # Get details of violations
            sudo ausearch -m AVC -ts recent 2>/dev/null | grep "apparmor=" | tail -5 >> "$LOG_FILE"
        fi
    else
        log "No AppArmor violations detected"
    fi
else
    log "WARNING: ausearch not available (install auditd)"
fi

# Monitor 2: seccomp Violations
log "=== Monitoring seccomp violations ==="

if command -v journalctl &> /dev/null; then
    # Check for seccomp denials in the last 15 minutes
    seccomp_violations=$(sudo journalctl -k --since "15 minutes ago" 2>/dev/null | grep -c "seccomp" || echo "0")

    if [ "$seccomp_violations" -gt 0 ]; then
        log "Found $seccomp_violations seccomp event(s)"

        if [ "$seccomp_violations" -gt "$ALERT_THRESHOLD" ]; then
            alert "HIGH: $seccomp_violations seccomp events (threshold: $ALERT_THRESHOLD)"

            # Get details
            sudo journalctl -k --since "15 minutes ago" 2>/dev/null | grep "seccomp" | tail -5 >> "$LOG_FILE"
        fi
    else
        log "No seccomp violations detected"
    fi
else
    log "WARNING: journalctl not available"
fi

# Monitor 3: Failed SSH/SSM Login Attempts
log "=== Monitoring authentication attempts ==="

if [ -f "/var/log/auth.log" ]; then
    failed_logins=$(grep "Failed" /var/log/auth.log 2>/dev/null | grep -c "$(date '+%b %d')" || echo "0")

    if [ "$failed_logins" -gt 0 ]; then
        log "Found $failed_logins failed authentication attempt(s) today"

        if [ "$failed_logins" -gt 10 ]; then
            alert "HIGH: $failed_logins failed authentication attempts today"
        fi
    else
        log "No failed authentication attempts"
    fi
fi

# Monitor 4: Firecracker VM Status
log "=== Monitoring Firecracker VMs ==="

if [ -d "/opt/firecracker/vms" ]; then
    vm_count=$(find /opt/firecracker/vms -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
    log "Active Firecracker VM directories: $vm_count"

    # Check for VMs with issues
    for vm_dir in /opt/firecracker/vms/*/; do
        if [ -d "$vm_dir" ]; then
            vm_id=$(basename "$vm_dir")

            if [ -f "$vm_dir/firecracker.pid" ]; then
                pid=$(cat "$vm_dir/firecracker.pid")

                if ! ps -p "$pid" > /dev/null 2>&1; then
                    alert "MEDIUM: Firecracker VM $vm_id has stale PID file (process not running)"
                fi
            fi
        fi
    done
else
    log "Firecracker not configured or no VMs directory"
fi

# Monitor 5: Unusual Network Activity
log "=== Monitoring network activity ==="

if command -v netstat &> /dev/null; then
    # Check for unexpected listening ports
    listening_ports=$(sudo netstat -tuln | grep LISTEN | wc -l)
    log "Listening ports: $listening_ports"

    # Alert if SSH port 22 is open (should be closed after SSM setup)
    if sudo netstat -tuln | grep -q ":22 "; then
        alert "MEDIUM: SSH port 22 is open (should be closed with SSM)"
    fi
fi

# Monitor 6: System Resources
log "=== Monitoring system resources ==="

# CPU usage
cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "0")
log "CPU usage: ${cpu_usage}%"

if [ "${cpu_usage%.*}" -gt 90 ]; then
    alert "HIGH: CPU usage at ${cpu_usage}%"
fi

# Memory usage
mem_usage=$(free | grep Mem | awk '{printf("%.0f"), $3/$2 * 100}')
log "Memory usage: ${mem_usage}%"

if [ "$mem_usage" -gt 90 ]; then
    alert "HIGH: Memory usage at ${mem_usage}%"
fi

# Disk usage
disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
log "Disk usage: ${disk_usage}%"

if [ "$disk_usage" -gt 85 ]; then
    alert "HIGH: Disk usage at ${disk_usage}%"
fi

# Monitor 7: Service Status
log "=== Monitoring critical services ==="

services=(
    "nginx"
    "oauth2-proxy"
    "deploy-portal"
    "apparmor"
)

for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        log "Service $service: running"
    else
        if systemctl list-unit-files "$service.service" &>/dev/null; then
            alert "MEDIUM: Service $service is not running"
        fi
    fi
done

# Monitor 8: Docker Container Security
log "=== Monitoring Docker containers ==="

if command -v docker &> /dev/null; then
    # Count running containers
    running_containers=$(docker ps -q 2>/dev/null | wc -l)
    log "Running containers: $running_containers"

    # Check for containers without seccomp
    if [ "$running_containers" -gt 0 ]; then
        containers_without_seccomp=$(docker ps --format '{{.Names}}' | while read name; do
            if ! docker inspect "$name" 2>/dev/null | grep -q "seccomp"; then
                echo "$name"
            fi
        done | wc -l)

        if [ "$containers_without_seccomp" -gt 0 ]; then
            log "WARNING: $containers_without_seccomp container(s) without seccomp profile"
        fi
    fi
fi

# Monitor 9: File Integrity
log "=== Monitoring critical file integrity ==="

critical_files=(
    "/etc/seccomp/docker-default.json"
    "/etc/apparmor.d/oauth2-proxy"
    "/etc/nginx/nginx.conf"
)

for file in "${critical_files[@]}"; do
    if [ -f "$file" ]; then
        log "File integrity OK: $file"
    else
        alert "HIGH: Critical file missing: $file"
    fi
done

# Summary
log "=== Monitoring cycle complete ==="
log ""

# Rotate log if too large (>10MB)
if [ -f "$LOG_FILE" ]; then
    log_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")

    if [ "$log_size" -gt 10485760 ]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        log "Log rotated (size: $log_size bytes)"
    fi
fi
