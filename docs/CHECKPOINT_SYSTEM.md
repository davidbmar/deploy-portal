# Capsule Cloud Checkpoint System

## Overview

The Capsule Cloud checkpoint system provides portal-wide snapshots that enable instant rollback if deployments fail. Think of checkpoints as save points in a video game - you can always go back to a previous state.

## What Gets Checkpointed

Each checkpoint captures the **entire deployment portal state**:

- **All app deployments** in `/home/ubuntu/deployments/`
  - docker-compose.yml files
  - .env files (with secrets)
  - Port allocation files
  - App-specific configuration

- **Nginx configurations**
  - Route configurations in `/etc/nginx/conf.d/routes/`
  - Main server config (`deploy-portal-server.conf`)

- **Port registry**
  - `.registry.json` (tracks port allocations)

- **Metadata**
  - Timestamp, description, creator
  - Deployed apps list
  - Checkpoint size

## Quick Start

### Create a Checkpoint

```bash
# Simple checkpoint
/checkpoint save "Before major update"

# With custom label
/checkpoint save "Stable baseline" --label prod-v1
```

### List Checkpoints

```bash
/checkpoint list
```

Output:
```
Available Checkpoints:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LABEL                          TIMESTAMP            SIZE         DESCRIPTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
cp-abc123-20260203-060000      2026-02-03 06:00:00  45MB         Before major update [LATEST]
cp-xyz789-20260203-055000      2026-02-03 05:50:00  42MB         After deploying auth-service
prod-v1                        2026-02-02 10:00:00  40MB         Stable baseline
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total checkpoints: 3
```

### Restore from Checkpoint

**⚠️ WARNING**: Restore is destructive - current state will be replaced!

```bash
/checkpoint restore cp-abc123-20260203-060000
```

What happens:
1. Safety backup created automatically
2. All containers stopped
3. All files restored from checkpoint
4. Nginx reloaded
5. Containers restarted

### View Checkpoint Details

```bash
/checkpoint show cp-abc123-20260203-060000
```

## Checkpoint Labels

### Auto-Generated Labels

Format: `cp-{random}-{timestamp}`

Example: `cp-abc123-20260203-060000`

- **cp**: Checkpoint prefix
- **abc123**: Random string (uniqueness)
- **20260203-060000**: Timestamp (YYYYMMDD-HHMMSS)

### Custom Labels

Use `--label` flag for memorable names:

```bash
/checkpoint save "Production baseline" --label prod-baseline-v1
/checkpoint save "Before Black Friday" --label blackfriday-2026
/checkpoint save "Known good state" --label stable
```

**Best practices**:
- Use semantic versioning (v1, v2, v3)
- Include date for time-based checkpoints
- Use project milestones (launch, beta, prod)

## Automatic Checkpoints (via /deploy)

The `/deploy` skill automatically creates checkpoints:

### Phase 0: Pre-Deployment

Before **any** changes are made:

```
📸 PHASE 0: CREATING PRE-DEPLOYMENT CHECKPOINT
✅ Checkpoint created: cp-abc123-20260203-060000

💡 If deployment fails, restore with:
   /checkpoint restore cp-abc123-20260203-060000
```

### Phase 7: Post-Deployment

After successful deployment:

```
═══════════════════════════════════════════════════════════
        DEPLOYMENT COMPLETE - CHECKPOINT SUMMARY
═══════════════════════════════════════════════════════════

Deployment checkpoints created:

  📸 CHECKPOINT_0: Before deployment started
     Label: cp-abc123-20260203-060000
     Use case: Complete rollback to pre-deployment state

═══════════════════════════════════════════════════════════
                    ROLLBACK INSTRUCTIONS
═══════════════════════════════════════════════════════════

To rollback:
  /checkpoint restore cp-abc123-20260203-060000
```

## Storage & Cleanup

### Storage Location

Checkpoints stored at: `/home/ubuntu/.capsule-checkpoints/`

Structure:
```
/home/ubuntu/.capsule-checkpoints/
├── cp-abc123-20260203-060000/
│   ├── checkpoint-info.json
│   ├── deployments/
│   │   ├── app1/
│   │   ├── app2/
│   │   └── app3/
│   ├── nginx-routes/
│   └── registry.json
├── cp-xyz789-20260203-055000/
└── latest -> cp-abc123-20260203-060000
```

### Automatic Cleanup

By default, keeps last 20 checkpoints. Clean manually:

```bash
# Keep last 20 (default)
/checkpoint clean

# Keep last 10
/checkpoint clean --keep 10

# Keep last 5
/checkpoint clean --keep 5
```

### Disk Space Management

Check checkpoint sizes:
```bash
/checkpoint list  # Shows size column
```

Large checkpoints:
- Many apps deployed: 50-100MB per checkpoint
- Few apps: 10-30MB per checkpoint

Recommend:
- Clean old checkpoints weekly
- Keep 10-20 checkpoints (balance safety vs disk space)
- Monitor disk usage: `df -h /home/ubuntu/.capsule-checkpoints`

## Common Workflows

### Workflow 1: Safe Deployment

```bash
# 1. Create pre-deployment checkpoint
/checkpoint save "Before deploying payment-v2"
# Output: cp-abc123-20260203-060000

# 2. Deploy application
/deploy payment-service

# 3. If successful, create post-deployment checkpoint
/checkpoint save "After deploying payment-v2 successfully"

# 4. If failed, rollback
/checkpoint restore cp-abc123-20260203-060000
```

### Workflow 2: Major Update

```bash
# 1. Create baseline checkpoint
/checkpoint save "Production baseline before migration" --label baseline-pre-migration

# 2. Perform updates

# 3. If issues arise days later
/checkpoint list
/checkpoint restore baseline-pre-migration
```

### Workflow 3: Debugging

```bash
# 1. List checkpoints
/checkpoint list

# 2. Show details
/checkpoint show cp-abc123-20260203-060000

# 3. Compare deployed apps
/checkpoint show cp-xyz789-20260203-055000

# 4. Restore to last known-good
/checkpoint restore cp-abc123-20260203-060000
```

## Troubleshooting

### Checkpoint creation failed

**Symptom**: Error creating checkpoint

**Solutions**:
```bash
# Check disk space
df -h /home/ubuntu/.capsule-checkpoints

# Check permissions
ls -la /home/ubuntu/.capsule-checkpoints

# Clean old checkpoints
/checkpoint clean --keep 5
```

### Restore failed

**Symptom**: Restore command fails

**Solutions**:
```bash
# Verify checkpoint exists
/checkpoint list

# Check for running containers
docker ps

# Manually stop containers
cd /home/ubuntu/deployments/app-name
docker-compose down

# Retry restore
/checkpoint restore cp-abc123-20260203-060000
```

### Nginx reload failed after restore

**Symptom**: "Nginx config test failed"

**Solutions**:
```bash
# SSH to server
ssh -i pem-file ubuntu@portal-host

# Test nginx config
sudo nginx -t

# Check error log
sudo tail -50 /var/log/nginx/error.log

# If config invalid, restore safety backup
/checkpoint restore safety-YYYYMMDD-HHMMSS
```

### Disk space issues

**Symptom**: "No space left on device"

**Solutions**:
```bash
# Check disk usage
df -h

# List checkpoint sizes
/checkpoint list

# Aggressively clean
/checkpoint clean --keep 3

# Remove specific old checkpoint
ssh to server
rm -rf /home/ubuntu/.capsule-checkpoints/cp-old-label
```

## Advanced Usage

### Manual Checkpoint Creation (via SSH)

```bash
ssh -i pem-file ubuntu@portal-host
cd /home/ubuntu/src/deploy-portal/scripts

# Create checkpoint
./capsule-checkpoint.sh save "Manual checkpoint"

# List checkpoints
./capsule-checkpoint.sh list

# Restore
./capsule-checkpoint.sh restore cp-abc123-20260203-060000
```

### Checkpoint Inspection

```bash
ssh -i pem-file ubuntu@portal-host

# View checkpoint contents
ls -lh /home/ubuntu/.capsule-checkpoints/cp-abc123-20260203-060000/

# View metadata
cat /home/ubuntu/.capsule-checkpoints/cp-abc123-20260203-060000/checkpoint-info.json | jq '.'

# List apps in checkpoint
ls /home/ubuntu/.capsule-checkpoints/cp-abc123-20260203-060000/deployments/
```

### Safety Backups

Every restore automatically creates a safety backup:

```
Creating safety backup of current state...
✅ Checkpoint created: safety-20260203-061234
```

Use this if restore caused unexpected issues:
```bash
/checkpoint restore safety-20260203-061234
```

## FAQs

### Q: Do checkpoints include secrets (.env files)?

**A**: Yes! Checkpoints include .env files with secrets. They are stored securely on the server and never checked into git.

### Q: How long does restore take?

**A**: Typically 10-30 seconds depending on:
- Number of apps
- Container startup time
- Checkpoint size

### Q: Can I restore an old checkpoint?

**A**: Yes! Checkpoints don't expire. Restore any checkpoint from the list.

### Q: What happens to running apps during restore?

**A**: All containers are stopped, files replaced, then containers restarted. Brief downtime expected (~10-30 seconds).

### Q: Can I checkpoint just one app?

**A**: No. Checkpoints are portal-wide to ensure consistency. Apps may depend on nginx routes, ports, etc.

### Q: Do checkpoints use a lot of disk space?

**A**: Moderate. Each checkpoint is ~10-100MB depending on number/size of apps. Clean old checkpoints to manage space.

### Q: Can I copy checkpoints to another server?

**A**: Yes! Checkpoints are just directories. Use rsync or scp:
```bash
rsync -avz /home/ubuntu/.capsule-checkpoints/cp-abc123/ user@other-server:/path/
```

### Q: What if checkpoint is corrupted?

**A**: Use a different checkpoint or the automatic safety backup. Always keep multiple checkpoints.

## Best Practices

1. **Checkpoint before risky operations**
   - Major deployments
   - Configuration changes
   - Database migrations
   - Nginx modifications

2. **Use descriptive labels**
   - Include date/version
   - Describe what changed
   - Note why checkpoint was created

3. **Keep recent checkpoints**
   - At least 5-10 checkpoints
   - Weekly cleanup
   - Don't delete baseline checkpoints

4. **Test restores periodically**
   - Verify restore works
   - Time the restore process
   - Practice rollback procedures

5. **Monitor disk space**
   - Check `/home/ubuntu/.capsule-checkpoints` size
   - Clean when approaching disk limits
   - Consider off-site checkpoint backups

6. **Document custom labels**
   - Keep a list of important checkpoints
   - Note what each represents
   - Share with team

## Integration with Other Skills

### With /deploy

```bash
# Deploy automatically creates checkpoints
/deploy my-app
# Creates: Phase 0 checkpoint (pre-deployment)
# Shows rollback instructions at end
```

### With /deploy-verify

```bash
# Verify after restore
/checkpoint restore cp-abc123
/deploy-verify my-app  # Verify app works
```

## Version History

- **v1.0.0** (2026-02-03): Initial release
  - Portal-wide checkpoints
  - Auto-generated and custom labels
  - Automatic cleanup
  - Integration with /deploy skill

---

**Questions?** See the main README or contact Capsule Cloud support.
