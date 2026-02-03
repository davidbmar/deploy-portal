# Checkpoint Integration into deploy-skill.yaml

## Summary
Add 7 checkpoint creation points throughout deployment for granular rollback.

## Checkpoint Points

### Phase 0: Pre-Deployment Checkpoint (INSERT BEFORE PHASE 1)

Add new Phase 0 before line 16 ("## Phase 1: Pre-flight Checks"):

```yaml
      ## Phase 0: Pre-Deployment Checkpoint

      **CRITICAL**: Create checkpoint BEFORE any deployment changes.

      ```bash
      echo "════════════════════════════════════════════════════════════"
      echo "📸 PHASE 0: CREATING PRE-DEPLOYMENT CHECKPOINT"
      echo "════════════════════════════════════════════════════════════"
      echo ""
      
      # Create pre-deployment checkpoint
      CHECKPOINT_0=$(ssh -i {pem_file} {ssh_user}@{portal_host} \
        "/home/ubuntu/src/deploy-portal/scripts/capsule-checkpoint.sh save 'Phase 0: Before deploying {app_name}'" | tail -1)
      
      echo "✅ Checkpoint: $CHECKPOINT_0 (pre-deployment)"
      echo ""
      echo "💡 If deployment fails, restore with:"
      echo "   /checkpoint restore $CHECKPOINT_0"
      echo ""
      ```

### Checkpoint 1: After Phase 1 Complete (INSERT AFTER PHASE 1, BEFORE PHASE 2)

Add after Phase 1 (before line 208):

```yaml
      ### 1.6 Create Checkpoint After Preflight

      ```bash
      echo "📸 Creating checkpoint after preflight checks..."
      CHECKPOINT_1=$(ssh -i {pem_file} {ssh_user}@{portal_host} \
        "/home/ubuntu/src/deploy-portal/scripts/capsule-checkpoint.sh save 'Phase 1: Preflight checks passed for {app_name}'" | tail -1)
      echo "✅ Checkpoint: $CHECKPOINT_1 (preflight done)"
      ```

### Checkpoint 2: After Phase 2 Complete (INSERT AFTER PHASE 2, BEFORE PHASE 3)

Add after Phase 2 (before line 235):

```yaml
      ### 2.X Create Checkpoint After Version Management

      ```bash
      echo "📸 Creating checkpoint after version management..."
      CHECKPOINT_2=$(ssh -i {pem_file} {ssh_user}@{portal_host} \
        "/home/ubuntu/src/deploy-portal/scripts/capsule-checkpoint.sh save 'Phase 2: Version management complete for {app_name}'" | tail -1)
      echo "✅ Checkpoint: $CHECKPOINT_2 (version managed)"
      ```

### Checkpoint 3: After Phase 3 Complete (INSERT AFTER PHASE 3, BEFORE PHASE 4)

Add after Phase 3 (before line 264):

```yaml
      ### 3.X Create Checkpoint After ZIP Selection

      ```bash
      echo "📸 Creating checkpoint after ZIP selection..."
      CHECKPOINT_3=$(ssh -i {pem_file} {ssh_user}@{portal_host} \
        "/home/ubuntu/src/deploy-portal/scripts/capsule-checkpoint.sh save 'Phase 3: ZIP selected for {app_name}'" | tail -1)
      echo "✅ Checkpoint: $CHECKPOINT_3 (ZIP selected)"
      ```

### Checkpoint 4: After Phase 4 Complete (INSERT AFTER PHASE 4, BEFORE PHASE 5)

Add after Phase 4 (before line 304):

```yaml
      ### 4.X Create Checkpoint After Deployment Check

      ```bash
      echo "📸 Creating checkpoint after deployment check..."
      CHECKPOINT_4=$(ssh -i {pem_file} {ssh_user}@{portal_host} \
        "/home/ubuntu/src/deploy-portal/scripts/capsule-checkpoint.sh save 'Phase 4: Deployment check complete for {app_name}'" | tail -1)
      echo "✅ Checkpoint: $CHECKPOINT_4 (check done)"
      ```

### Checkpoint 5: After Phase 5 Complete (INSERT AFTER PHASE 5, BEFORE PHASE 6)

Add after Phase 5 (before line 603):

```yaml
      ### 5.X Create Checkpoint After Deployment Execution

      ```bash
      echo "📸 Creating checkpoint after deployment execution..."
      CHECKPOINT_5=$(ssh -i {pem_file} {ssh_user}@{portal_host} \
        "/home/ubuntu/src/deploy-portal/scripts/capsule-checkpoint.sh save 'Phase 5: Deployment executed for {app_name}'" | tail -1)
      echo "✅ Checkpoint: $CHECKPOINT_5 (deployed)"
      ```

### Checkpoint 6: After Phase 6 Complete (INSERT AFTER PHASE 6)

Add after Phase 6:

```yaml
      ### 6.X Create Checkpoint After Cleanup

      ```bash
      echo "📸 Creating checkpoint after cleanup..."
      CHECKPOINT_6=$(ssh -i {pem_file} {ssh_user}@{portal_host} \
        "/home/ubuntu/src/deploy-portal/scripts/capsule-checkpoint.sh save 'Phase 6: Cleanup complete for {app_name}'" | tail -1)
      echo "✅ Checkpoint: $CHECKPOINT_6 (cleanup done)"
      ```

### Phase 7: Rollback Guide (APPEND AT END)

Add new Phase 7 at the very end of the deployment instructions:

```yaml
      ## Phase 7: Rollback Guide

      Display all checkpoints created during this deployment for easy rollback:

      ```bash
      echo ""
      echo "═══════════════════════════════════════════════════════════"
      echo "           DEPLOYMENT CHECKPOINTS CREATED"
      echo "═══════════════════════════════════════════════════════════"
      echo ""
      echo "If you need to rollback, you can restore to any checkpoint:"
      echo ""
      echo "  $CHECKPOINT_0  - Before deployment (original state)"
      echo "  $CHECKPOINT_1  - After preflight checks"
      echo "  $CHECKPOINT_2  - After version management"
      echo "  $CHECKPOINT_3  - After ZIP selection"
      echo "  $CHECKPOINT_4  - After deployment check"
      echo "  $CHECKPOINT_5  - After deployment execution"
      echo "  $CHECKPOINT_6  - After cleanup (current state)"
      echo ""
      echo "To rollback to any checkpoint:"
      echo "  /checkpoint restore {label}"
      echo ""
      echo "To list all checkpoints:"
      echo "  /checkpoint list"
      echo ""
      echo "💡 TIP: If deployment caused issues, restore to \$CHECKPOINT_0"
      echo "   to return to the state before deployment started."
      echo "═══════════════════════════════════════════════════════════"
      ```

      **Why 7 Checkpoints?**
      
      - **Granular rollback**: Can restore to any point in deployment
      - **Debugging**: Know exactly where failure occurred
      - **Safety**: Always have CHECKPOINT_0 to return to original state
      - **Flexibility**: Can skip failed phase and continue from checkpoint
