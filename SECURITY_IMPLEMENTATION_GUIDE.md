# Security Hardening Implementation Guide

Complete implementation of advanced security hardening for the deployment platform.

## Overview

This implementation adds four layers of security:

1. **AWS SSM** - Secure remote access without SSH port 22
2. **AppArmor** - Mandatory Access Control for system services
3. **seccomp** - Syscall filtering for services and containers
4. **Firecracker** - MicroVM isolation for user applications

## Quick Start

### Prerequisites

- Ubuntu 22.04 LTS
- Root/sudo access
- AWS credentials configured (for SSM)
- Docker installed (for container features)

### Installation Order

Follow this order for safe deployment:

```bash
# 1. SSM Integration (Week 1)
cd /home/ubuntu/src/deploy-portal

# Apply Terraform changes for IAM policies
cd /home/ubuntu/src/easy-cognito-nginx-gateway-auth/terraform
terraform plan
terraform apply

# Test SSM connection
bash /home/ubuntu/src/deploy-portal/scripts/ssm-connect.sh status

# 2. AppArmor Profiles (Week 2)
bash /home/ubuntu/src/deploy-portal/security/apparmor/load-profiles.sh

# Monitor for 48 hours
sudo ausearch -m AVC -ts recent

# Enforce after validation
bash /home/ubuntu/src/deploy-portal/security/apparmor/enforce-profiles.sh

# 3. seccomp for System Services (Week 2-3)
# Profiles are automatically applied to new deployments
# For existing services, restart them after systemd changes

# 4. seccomp for Docker (Week 3-4)
bash /home/ubuntu/src/deploy-portal/security/inject-seccomp.sh

# 5. Firecracker Setup (Week 4-6)
sudo bash /home/ubuntu/src/deploy-portal/firecracker/install-firecracker.sh
sudo bash /home/ubuntu/src/deploy-portal/firecracker/build-rootfs.sh

# 6. Enable Monitoring
bash /home/ubuntu/src/deploy-portal/monitoring/install-monitoring.sh
```

## Phase-by-Phase Implementation

### Phase 1: AWS SSM Integration

**Objective**: Replace SSH with Session Manager

**Changes Made**:
- `/home/ubuntu/src/easy-cognito-nginx-gateway-auth/terraform/modules/compute/main.tf` - Added SSM IAM permissions
- `/home/ubuntu/src/deploy-portal/scripts/ssm-connect.sh` - Connection wrapper

**Testing**:
```bash
# Check SSM agent
sudo systemctl status snap.amazon-ssm-agent.amazon-ssm-agent

# Test connection
bash /home/ubuntu/src/deploy-portal/scripts/ssm-connect.sh

# Port forwarding for debugging
bash /home/ubuntu/src/deploy-portal/scripts/ssm-connect.sh --forward 5000:5000
```

**Rollback**:
Re-enable port 22 in security group if needed.

---

### Phase 2: AppArmor Profiles

**Objective**: Mandatory Access Control for system services

**Profiles Created**:
- `oauth2-proxy` - Auth proxy restrictions
- `deploy-portal` - Deployment service with Docker access
- `ssh-helper` - Terminal access restrictions
- `website-cloner` - Git/clone operations
- `usr.sbin.nginx` - Web server restrictions

**Management**:
```bash
# Load in complain mode
bash /home/ubuntu/src/deploy-portal/security/apparmor/load-profiles.sh

# Check status
sudo aa-status

# View violations
sudo ausearch -m AVC -ts recent

# Enforce after validation
bash /home/ubuntu/src/deploy-portal/security/apparmor/enforce-profiles.sh

# Disable specific profile if needed
sudo aa-disable /etc/apparmor.d/profile-name
```

**Rollback**:
```bash
# Complain mode
sudo aa-complain /etc/apparmor.d/profile-name

# Disable
sudo aa-disable /etc/apparmor.d/profile-name
```

---

### Phase 3: seccomp for System Services

**Objective**: Syscall filtering for systemd services

**Files**:
- `/etc/seccomp/oauth2-proxy.json`
- `/etc/seccomp/deploy-portal.json`
- `/home/ubuntu/src/deploy-portal/automation/templates/systemd-service.tmpl` - Updated with security directives

**Security Directives Added**:
- `SystemCallFilter=@system-service`
- `RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX`
- `RestrictNamespaces=yes`
- `ProtectSystem=strict`
- `NoNewPrivileges=true`

**Testing**:
```bash
# Check service status
sudo systemctl status service-name

# View denied syscalls
sudo journalctl -u service-name | grep -i denied
```

**Rollback**:
Remove security directives from service files and restart services.

---

### Phase 4: seccomp for Docker

**Objective**: Default seccomp profile for all containers

**Files**:
- `/etc/seccomp/docker-default.json` - Container syscall whitelist
- `/home/ubuntu/src/deploy-portal/automation/templates/docker-compose-base.yml` - Template with security options

**Applying to Existing Deployments**:
```bash
# Inject seccomp into existing docker-compose files
bash /home/ubuntu/src/deploy-portal/security/inject-seccomp.sh
```

**Testing**:
```bash
# Test blocked syscall
docker run --rm --security-opt seccomp=/etc/seccomp/docker-default.json \
  ubuntu:22.04 reboot
# Should fail with "Operation not permitted"

# Normal operations should work
docker run --rm --security-opt seccomp=/etc/seccomp/docker-default.json \
  ubuntu:22.04 echo "test"
```

**Rollback**:
Restore from `docker-compose.yml.backup-*` files and recreate containers.

---

### Phase 5: Firecracker MicroVMs

**Objective**: Replace Docker with Firecracker for stronger isolation

**Installation**:
```bash
# Install Firecracker
sudo bash /home/ubuntu/src/deploy-portal/firecracker/install-firecracker.sh

# Build root filesystem
sudo bash /home/ubuntu/src/deploy-portal/firecracker/build-rootfs.sh
```

**VM Management**:
```bash
# Start VM
python3 /home/ubuntu/src/deploy-portal/firecracker/vm-manager.py start my-vm-id

# Stop VM
python3 /home/ubuntu/src/deploy-portal/firecracker/vm-manager.py stop my-vm-id

# Check status
python3 /home/ubuntu/src/deploy-portal/firecracker/vm-manager.py status my-vm-id
```

**Deploying with Firecracker**:
```bash
# New deployment
bash /home/ubuntu/src/deploy-portal/automation/deploy-app.sh my-app \
  --use-firecracker \
  --type docker

# Migrate existing app
bash /home/ubuntu/src/deploy-portal/migration/migrate-to-firecracker.sh my-app

# Rollback if needed
bash /home/ubuntu/src/deploy-portal/migration/rollback-firecracker.sh my-app
```

**Rollback**:
```bash
bash /home/ubuntu/src/deploy-portal/migration/rollback-firecracker.sh app-name
```

---

### Phase 6: Testing & Validation

**Security Tests**:
```bash
# Run full security test suite
bash /home/ubuntu/src/deploy-portal/tests/security-tests.sh
```

**Performance Benchmarks**:
```bash
# Measure performance impact
bash /home/ubuntu/src/deploy-portal/tests/performance-benchmark.sh
```

**Expected Results**:
- CPU overhead: <3%
- Memory overhead: <10MB per service
- Network latency: <5ms increase
- Firecracker boot: 125ms-1s (vs 2-5s Docker)

---

## Monitoring

### Installation

```bash
bash /home/ubuntu/src/deploy-portal/monitoring/install-monitoring.sh
```

This sets up a cron job that runs every 15 minutes to monitor:
- AppArmor violations
- seccomp violations
- Failed authentication attempts
- Firecracker VM status
- Network activity
- System resources
- Service status
- Container security
- File integrity

### Logs

```bash
# View monitoring logs
tail -f /var/log/security-monitor.log

# Run manual check
bash /home/ubuntu/src/deploy-portal/monitoring/security-monitor.sh
```

### Alerts

Alerts are logged when:
- More than 5 violations in 15 minutes
- CPU usage > 90%
- Memory usage > 90%
- Disk usage > 85%
- Critical services down
- SSH port 22 open (after SSM migration)

---

## Emergency Rollback

**WARNING**: Only use in emergency situations!

```bash
# Rollback ALL security changes
bash /home/ubuntu/src/deploy-portal/rollback-all-security.sh
```

This will:
1. Disable AppArmor profiles
2. Remove seccomp from systemd services
3. Rollback Firecracker VMs to Docker
4. Remove Docker seccomp profiles
5. Disable security monitoring

Manual steps after rollback:
- Re-enable SSH port 22 in security group (if needed)
- Review and test all applications
- Plan corrective actions

---

## Directory Structure

```
/home/ubuntu/src/deploy-portal/
├── scripts/
│   └── ssm-connect.sh              # SSM connection wrapper
├── security/
│   ├── apparmor/
│   │   ├── oauth2-proxy            # AppArmor profiles
│   │   ├── deploy-portal
│   │   ├── ssh-helper
│   │   ├── website-cloner
│   │   ├── usr.sbin.nginx
│   │   ├── load-profiles.sh        # Load profiles (complain mode)
│   │   └── enforce-profiles.sh     # Switch to enforce mode
│   ├── seccomp/
│   │   ├── oauth2-proxy.json       # seccomp profiles (moved to /etc/seccomp)
│   │   ├── deploy-portal.json
│   │   └── docker-default.json
│   └── inject-seccomp.sh           # Apply seccomp to existing containers
├── firecracker/
│   ├── install-firecracker.sh      # Install Firecracker
│   ├── build-rootfs.sh             # Build VM root filesystem
│   ├── vm-manager.py               # VM lifecycle management
│   └── docker-compose-fc.sh        # Docker-compose compatibility wrapper
├── migration/
│   ├── migrate-to-firecracker.sh   # Migrate app to Firecracker
│   └── rollback-firecracker.sh     # Rollback app from Firecracker
├── tests/
│   ├── security-tests.sh           # Security validation tests
│   └── performance-benchmark.sh    # Performance measurements
├── monitoring/
│   ├── security-monitor.sh         # Security monitoring script
│   └── install-monitoring.sh       # Install monitoring cron job
└── rollback-all-security.sh        # Emergency rollback (all changes)

/etc/
├── seccomp/
│   ├── oauth2-proxy.json
│   ├── deploy-portal.json
│   └── docker-default.json
└── apparmor.d/
    ├── oauth2-proxy
    ├── deploy-portal
    ├── ssh-helper
    ├── website-cloner
    └── usr.sbin.nginx

/opt/firecracker/
├── kernels/
│   └── vmlinux.bin
├── rootfs/
│   └── ubuntu-docker.ext4
└── vms/
    └── vm-*/
```

---

## Troubleshooting

### AppArmor Issues

**Problem**: Service fails to start after enabling AppArmor

**Solution**:
```bash
# Switch to complain mode
sudo aa-complain /etc/apparmor.d/service-name

# Check denials
sudo ausearch -m AVC -ts recent

# Update profile based on denials
sudo vi /etc/apparmor.d/service-name

# Reload profile
sudo apparmor_parser -r /etc/apparmor.d/service-name
```

### seccomp Issues

**Problem**: Application fails with syscall errors

**Solution**:
```bash
# Check logs for blocked syscalls
sudo journalctl -u service-name | grep -i seccomp

# Add required syscalls to profile
sudo vi /etc/seccomp/service-name.json

# Restart service
sudo systemctl restart service-name
```

### Firecracker Issues

**Problem**: VM fails to start

**Solution**:
```bash
# Check Firecracker logs
cat /opt/firecracker/vms/vm-*/firecracker.log

# Verify TAP device
ip link show tap-*

# Check bridge
ip link show br-fc

# Recreate network
sudo ip link delete br-fc
python3 vm-manager.py start vm-id
```

### Docker seccomp Issues

**Problem**: Container operations blocked by seccomp

**Solution**:
```bash
# Run without seccomp temporarily to identify needed syscalls
docker run --security-opt seccomp=unconfined ...

# Use strace to identify syscalls
docker run --cap-add SYS_PTRACE ... strace -c command

# Add syscalls to /etc/seccomp/docker-default.json
```

---

## Performance Tuning

### AppArmor

- Use `deny` rules for explicit blocks
- Keep profiles as specific as possible
- Avoid wildcards in hot paths

### seccomp

- Whitelist only required syscalls
- Use `SCMP_ACT_ERRNO` for better performance than `SCMP_ACT_KILL`
- Profile syscalls with `strace -c` before creating filter

### Firecracker

- Adjust vCPU count based on workload
- Start with 512MB RAM, scale as needed
- Use read-only root filesystem when possible
- Enable boot timer for optimization

---

## Security Best Practices

1. **Progressive Rollout**
   - Deploy in stages
   - Monitor each phase for 48 hours
   - Keep rollback capability at each stage

2. **Monitoring**
   - Review security logs daily
   - Alert on violation thresholds
   - Automate log rotation

3. **Testing**
   - Run security tests after changes
   - Benchmark performance regularly
   - Test rollback procedures

4. **Documentation**
   - Document all custom profiles
   - Record violation patterns
   - Maintain runbooks for incidents

5. **Updates**
   - Keep Firecracker updated
   - Review AppArmor/seccomp profiles quarterly
   - Update root filesystem images regularly

---

## Success Criteria

✅ **Security**:
- Port 22 closed in security group
- 100% system services with AppArmor enforced
- 100% containers with seccomp profiles
- 100% SSM sessions logged
- 0 successful VM escapes

✅ **Performance**:
- App boot time < 2s (Firecracker)
- CPU overhead < 3%
- Memory overhead < 10MB per VM
- Network latency increase < 5ms

✅ **Operational**:
- Deployment success rate > 99%
- Rollback time < 5 minutes
- MTTD security violations < 1 minute
- MTTR < 15 minutes

---

## Support & Maintenance

### Regular Tasks

**Daily**:
- Review security monitoring logs
- Check for alerts

**Weekly**:
- Run security tests
- Review AppArmor/seccomp violations
- Check Firecracker VM health

**Monthly**:
- Run performance benchmarks
- Review and update profiles
- Test rollback procedures

**Quarterly**:
- Update Firecracker version
- Rebuild root filesystem images
- Review security policies

### Getting Help

1. Check logs first
2. Run diagnostic tests
3. Review this guide
4. Check GitHub issues

### Contributing

When modifying security profiles:
1. Test in complain mode first
2. Monitor for 48 hours minimum
3. Document changes
4. Update this guide

---

## References

- [AppArmor Documentation](https://gitlab.com/apparmor/apparmor/-/wikis/home)
- [seccomp Documentation](https://man7.org/linux/man-pages/man2/seccomp.2.html)
- [Firecracker Documentation](https://github.com/firecracker-microvm/firecracker/blob/main/docs/getting-started.md)
- [AWS SSM Documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)

---

## Changelog

### 2026-01-19 - Initial Implementation
- Created all security infrastructure
- Implemented SSM integration
- Added AppArmor profiles
- Created seccomp filters
- Set up Firecracker support
- Implemented monitoring
- Created testing suite
- Added rollback procedures

---

**Last Updated**: 2026-01-19
**Version**: 1.0.0
