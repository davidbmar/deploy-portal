# Security Implementation - Learning Session

## Phase 1: AppArmor (COMPLETED)

### What We Learned:
1. **AppArmor** = Mandatory Access Control system in Linux
2. **Profiles** define what programs can/cannot do
3. **Two modes**:
   - **Complain mode**: Logs violations but allows them (safe for testing)
   - **Enforce mode**: Blocks violations (active protection)

### What We Activated:
- ✅ oauth2-proxy: Protected and enforced
- ✅ nginx: Protected and enforced  
- ⚠️  Python services: Conflict (need separate venvs or profile redesign)

### Current Status:
```bash
sudo aa-status | grep -E "(oauth2|nginx)"
```

### How to Monitor:
```bash
# Check for violations
sudo ausearch -m AVC -ts recent

# Check specific service
sudo journalctl -u oauth2-proxy | grep -i apparmor
```

### What AppArmor Protects Against:
- Unauthorized file access
- Privilege escalation
- Network access beyond what's needed
- System call abuse

---

## Next: Other Phases

### Phase 2: seccomp (Ready to activate)
- **What**: Syscall filtering
- **Benefit**: Blocks dangerous system calls like `reboot`, `mount`
- **Status**: Profiles exist, need to apply to services

### Phase 3: Firecracker (Optional)
- **What**: Hardware-level VM isolation
- **Benefit**: Stronger than Docker containers
- **Status**: Not installed yet

### Phase 4: Monitoring
- **What**: Automated security monitoring
- **Benefit**: Real-time alerts for violations
- **Status**: Scripts ready, needs activation

