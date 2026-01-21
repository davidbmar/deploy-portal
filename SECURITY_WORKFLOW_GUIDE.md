# Security Integration Workflow for VibeCode Deploy Kit

## Current Situation

Users deploy apps with:
```bash
bash deploy-app.sh my-app --type docker
```

This creates docker-compose.yml and deploys the app.

## Recommended Security Workflow

### Phase 1: Secure EXISTING Apps (One Time)
**Run ONCE today:**

```bash
# This secures the 26 existing containers (if any)
bash /home/ubuntu/src/deploy-portal/security/inject-seccomp.sh
```

**What happens:**
- Goes through existing deployed apps
- Adds security options to their docker-compose.yml
- Creates backups first
- Asks you to approve each restart
- Takes ~10-15 minutes for 26 apps

**Run this:** During maintenance window or when users aren't actively deploying

---

### Phase 2: Secure NEW Apps (Automatic Going Forward)

**Two deployment patterns to handle:**

#### Pattern A: Users Bring docker-compose.yml (Most Common)

User has this structure:
```
my-app/
├── src/
├── Dockerfile
└── docker-compose.yml  ← User creates this
```

**Solution:** Add a validation/enhancement step to deploy-app.sh

```bash
# In deploy-app.sh, after user uploads code:

# Check if docker-compose.yml exists
if [ -f "$APP_DIR/docker-compose.yml" ]; then
    echo "Enhancing docker-compose.yml with security options..."
    
    # Option 1: Automatically inject security (requires yq)
    bash /home/ubuntu/src/deploy-portal/security/inject-seccomp.sh --single "$APP_DIR"
    
    # Option 2: Validate and warn
    if ! grep -q "seccomp:" "$APP_DIR/docker-compose.yml"; then
        echo "⚠️  Warning: No seccomp profile detected"
        echo "   Recommendation: Add security_opt to your docker-compose.yml"
        echo "   See: /home/ubuntu/src/deploy-portal/automation/templates/docker-compose-base.yml"
    fi
fi
```

#### Pattern B: Deploy Kit Generates docker-compose.yml

If deploy-app.sh creates the docker-compose.yml:

```bash
# Use the secure template
cp /home/ubuntu/src/deploy-portal/automation/templates/docker-compose-base.yml \
   "$APP_DIR/docker-compose.yml"

# Then customize with user's app settings
sed -i "s/\${APP_NAME}/$APP_NAME/g" "$APP_DIR/docker-compose.yml"
sed -i "s/\${PORT}/$PORT/g" "$APP_DIR/docker-compose.yml"
```

---

## Timeline

### TODAY (Right Now)
✅ Security files are installed
✅ Monitoring is active (every 15 min)
✅ AppArmor protecting oauth2-proxy & nginx

### THIS WEEK (Optional)
□ Run inject-seccomp.sh on existing containers
□ Test that apps still work after hardening

### NEXT SPRINT (Recommended)
□ Integrate security into deploy-app.sh for new deployments
□ Update documentation for users
□ Add security validation to deploy kit

---

## Impact on User Experience

### Before Security:
```bash
# User deploys
bash deploy-app.sh my-app

# App runs (less secure)
✓ Deployed
```

### After Security:
```bash
# User deploys (same command!)
bash deploy-app.sh my-app

# App runs (more secure, no user changes needed)
✓ Deployed with seccomp protection
✓ Syscalls filtered
✓ Capabilities dropped
```

**User sees:** NO DIFFERENCE (works the same)
**System gets:** Much better security

---

## What Could Go Wrong?

### Scenario 1: App needs special capabilities
**Problem:** App uses raw sockets, needs CAP_NET_RAW
**Solution:** Add to cap_add in docker-compose.yml
```yaml
cap_add:
  - NET_BIND_SERVICE
  - CAP_NET_RAW  # Added for this specific app
```

### Scenario 2: App uses blocked syscall
**Problem:** App tries to use mount/ptrace/etc
**Solution:** 
- Option A: App is malicious/buggy (security working!)
- Option B: Legitimate need - create custom seccomp profile

### Scenario 3: Performance impact
**Problem:** Worried about overhead
**Reality:** <1% CPU overhead, negligible

---

## Decision Tree

```
New deployment arrives
    ↓
Does docker-compose.yml exist?
    ├─ YES → Inject security OR validate
    └─ NO  → Generate from secure template
    ↓
Deploy normally
    ↓
App runs with security ✓
```

---

## Testing Plan

Before rolling out to all users:

1. **Test with 1 app first**
   ```bash
   # Deploy a test app
   bash deploy-app.sh test-app
   
   # Apply security
   bash /home/ubuntu/src/deploy-portal/security/inject-seccomp.sh
   
   # Verify it works
   curl http://localhost:PORT
   ```

2. **Test with user's app**
   - Pick a non-critical app
   - Apply security
   - User tests functionality
   - If works → proceed
   - If breaks → investigate what's needed

3. **Gradual rollout**
   - Week 1: 5 apps
   - Week 2: All remaining apps
   - Monitor security logs

---

## Recommendation

**Do this in 3 steps:**

1. **Today:** 
   - Keep monitoring active (already done ✓)
   - Read SESSION_SUMMARY.md
   
2. **This Week:**
   - Run inject-seccomp.sh on 1-2 test apps
   - Verify they work fine
   - Run on remaining apps
   
3. **Next Sprint:**
   - Modify deploy-app.sh to auto-secure new deployments
   - Update user docs

**Don't rush it** - Security is important but so is not breaking things!

