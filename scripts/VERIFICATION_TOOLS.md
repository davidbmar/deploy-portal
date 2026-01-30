# Verification Tools Guide

This directory contains several verification scripts for different use cases. Here's when to use each one:

## Local Verification (On the deployed instance)

### `verify-deployment-local.sh`
**Use when:** Running directly on the instance you just deployed
**Requires:** Local access to the instance
**Tests:** Service status, nginx config, internal access, external access, permissions, security groups

```bash
# SSH to the instance first
ssh ubuntu@3.87.27.213

# Then run local verification
cd /home/ubuntu/src/deploy-portal
./scripts/verify-deployment-local.sh

# With MacBook IP for specific security group testing
USER_MACBOOK_IP=136.62.92.204 ./scripts/verify-deployment-local.sh
```

**What it checks:**
- ✅ deploy-portal service running
- ✅ nginx configuration valid
- ✅ Internal access (localhost)
- ✅ External access (public IP)
- ✅ Security group configuration
- ✅ File permissions
- ✅ Port listening status

### `debug-access.sh`
**Use when:** Troubleshooting external access issues on the local instance
**Requires:** Local access to the instance
**Tests:** Quick diagnostics for connectivity problems

```bash
cd /home/ubuntu/src/deploy-portal
./scripts/debug-access.sh
```

**What it shows:**
- Instance metadata (ID, public IP)
- Internal vs external access status
- Nginx listening configuration
- Security group rules
- Specific troubleshooting commands

## Remote Verification (From a different instance)

### `remote-http-verify.sh` ⭐ NEW
**Use when:** Testing external accessibility of a remote instance without SSH
**Requires:** HTTP access only (no SSH needed)
**Tests:** External HTTP/HTTPS accessibility

```bash
# From any instance or your local machine
cd /home/ubuntu/src/deploy-portal

# Quick check
./scripts/remote-http-verify.sh 3.87.27.213

# With domain
./scripts/remote-http-verify.sh capsule-deploy.duckdns.org

# Fast mode (skip performance tests)
./scripts/remote-http-verify.sh 3.87.27.213 --quick
```

**What it checks:**
- ✅ HTTP root path accessible
- ✅ Deploy page accessible
- ✅ API endpoint accessible
- ✅ HTTPS configuration
- ✅ Response time
- ✅ Server headers

### `verify-deployment.sh` (SSH-based)
**Use when:** Need comprehensive remote verification with SSH access
**Requires:** SSH key and access to target instance
**Tests:** Full system check via SSH

```bash
./scripts/verify-deployment.sh \
    --target-host ubuntu@3.87.27.213 \
    --ssh-key ~/.ssh/deploy-key.pem \
    --domain capsule-deploy.duckdns.org
```

**What it checks:**
- System services (nginx, oauth2-proxy, deploy-portal)
- Configuration files
- File permissions
- Functionality tests
- Network and DNS
- SSL certificates

### `verify-all-instances.sh` ⭐ NEW
**Use when:** Managing multiple deployments and want to check them all at once
**Requires:** HTTP access to instances (no SSH needed)
**Tests:** Quick health check of multiple instances

```bash
# Create instances file
cat > instances.txt << EOF
3.87.27.213
16.148.110.90
capsule-deploy.duckdns.org
EOF

# Verify all
./scripts/verify-all-instances.sh instances.txt

# Or use default location
cp instances.txt data/instances.txt
./scripts/verify-all-instances.sh
```

**What it checks:**
- HTTP accessibility for each instance
- Deploy page status
- API endpoint status
- Summary of healthy vs unhealthy instances

## Decision Tree: Which Tool Should I Use?

```
┌─ Are you ON the deployed instance?
│
├─ YES → Use verify-deployment-local.sh
│        • Most comprehensive
│        • Tests internal AND external access
│        • Checks security groups
│        • Run this after ./bootstrap.sh
│
└─ NO → Are you checking one instance or multiple?
    │
    ├─ One instance → Do you have SSH access?
    │   │
    │   ├─ YES → Use verify-deployment.sh (SSH-based)
    │   │        • Full system verification
    │   │        • Checks services, config, SSL
    │   │
    │   └─ NO → Use remote-http-verify.sh
    │            • Simple HTTP checks
    │            • No SSH required
    │            • Fast and easy
    │
    └─ Multiple instances → Use verify-all-instances.sh
                           • Batch verification
                           • No SSH required
                           • Quick health overview
```

## Common Workflows

### Workflow 1: After Fresh Deployment
```bash
# On the instance
./bootstrap.sh
# Verification runs automatically

# Or manually
./scripts/verify-deployment-local.sh
```

### Workflow 2: Verify Remote Deployment
```bash
# From your control instance
./scripts/remote-http-verify.sh 3.87.27.213

# If issues found, SSH and debug
ssh ubuntu@3.87.27.213
cd /home/ubuntu/src/deploy-portal
./scripts/debug-access.sh
```

### Workflow 3: Check All Your Instances
```bash
# Create instances list
cat > data/instances.txt << EOF
3.87.27.213
16.148.110.90
44.244.76.51
EOF

# Verify all
./scripts/verify-all-instances.sh

# If any fail, investigate
./scripts/remote-http-verify.sh 3.87.27.213
```

### Workflow 4: Troubleshooting External Access
```bash
# On the instance with issues
./scripts/debug-access.sh

# Shows:
# - ✓ localhost/ works
# - ✗ PUBLIC_IP/ FAILS
# - Security group rules
# - Troubleshooting steps
```

## Files Created by This Guide

```
scripts/
├── verify-deployment-local.sh    # Local comprehensive verification
├── verify-deployment.sh          # SSH-based remote verification
├── remote-http-verify.sh         # HTTP-only remote verification (NEW)
├── verify-all-instances.sh       # Batch verification (NEW)
├── debug-access.sh               # Local debugging tool
└── VERIFICATION_TOOLS.md         # This guide
```

## Integration with bootstrap.sh

The `bootstrap.sh` script automatically calls `verify-deployment-local.sh` after installation:

```bash
./bootstrap.sh
# ...deployment steps...
# Automatically runs comprehensive verification
# Asks if you want to continue if tests fail
```

## Tips

1. **Always verify after deployment** - Run verification immediately after `./bootstrap.sh`

2. **Use quick remote checks** - `remote-http-verify.sh --quick` for fast health checks

3. **Keep an instances list** - Maintain `data/instances.txt` with all your deployments

4. **Debug locally first** - If remote checks fail, SSH to the instance and run local verification

5. **Check security groups** - Most external access failures are security group issues

6. **Use MacBook IP testing** - Set `USER_MACBOOK_IP` to test specific IP allowlists

## Security Group Issues

If external access tests fail, check security group:

```bash
# Get instance info
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/instance-id)

# Check security groups
aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].SecurityGroups'

# Check port 80 rules
aws ec2 describe-security-groups \
    --group-ids <SG_ID> \
    --query 'SecurityGroups[0].IpPermissions[?ToPort==`80`]'

# Open port 80 to your IP
aws ec2 authorize-security-group-ingress \
    --group-id <SG_ID> \
    --protocol tcp \
    --port 80 \
    --cidr YOUR_IP/32
```

## Exit Codes

All verification scripts return:
- `0` - All critical tests passed
- `1` - Some tests failed

Use in scripts:
```bash
if ./scripts/verify-deployment-local.sh; then
    echo "Deployment successful!"
else
    echo "Deployment has issues"
fi
```
