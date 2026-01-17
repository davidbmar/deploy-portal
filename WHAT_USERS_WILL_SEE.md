# What Users Will See - Updated Instructions

## 📋 Summary

After autonomous execution improvements, users will see clear guidance at **every touchpoint** about how the `/deploy` skill works.

---

## 1️⃣ In QUICKSTART.md (First Thing Users Read)

```markdown
#### Every Deployment - Three Steps

**Step 1**: Move this ZIP to your project folder
```bash
cp deployment-kit-my-app-20260117.zip ~/path/to/your-project/
```

**Step 2**: Open Claude Code in your project
```bash
cd ~/path/to/your-project
claude-code
```

**Step 3**: Type this command
```
/deploy
```

⚠️ **IMPORTANT: After typing `/deploy`, DO NOT manually execute deployment steps!**

The skill runs **AUTONOMOUSLY**. Just sit back and:
- Watch the progress
- Respond if asked for confirmations or secrets
- Let the skill handle everything else automatically

Done! The skill will:
- Find the deployment kit automatically
- **Check the ZIP's skill version** (auto-updates if newer)
- Deploy your app completely on its own
- Give you the live URL

**Do not try to "help" by running commands - the skill does it all!**
```

**Key Message**: "DO NOT manually execute" right after showing `/deploy` command

---

## 2️⃣ In CLAUDE_PROMPT.md (For Manual Troubleshooting)

### At the Very Top

```markdown
## ⚠️ IMPORTANT: Choose Your Deployment Method

You have **TWO** ways to deploy this application:

### Method 1: Automated Skill (RECOMMENDED) ✅

**Best for**: Normal deployments, updates, and first-time users

```bash
# In your project directory with the deployment-kit ZIP:
claude-code
# Then type: /deploy
```

**What happens:**
- The `/deploy` skill runs **AUTONOMOUSLY**
- You sit back and monitor progress
- Only respond when prompted (confirmations, secrets, choices)
- The skill handles all 11 steps automatically

⚠️ **CRITICAL**: If you invoke `/deploy`, do NOT manually execute the steps below.
Let the skill run autonomously. **STOP READING THIS FILE** and let the skill work.

---

### Method 2: Manual Deployment (Troubleshooting Only) 🔧

**Use only if:**
- The automated skill fails or errors
- You need to troubleshoot a specific step
- You want to understand the deployment process in detail

**If using the manual method, continue reading from Step 0 below.**

---
```

**Key Message**: Fork in the road - choose ONE method, not both

---

## 3️⃣ In deploy-skill.yaml (What AI Reads)

### Meta-Instructions at Top

```yaml
# ═══════════════════════════════════════════════════════════════════════
# META-INSTRUCTIONS FOR CLAUDE CODE AI
# ═══════════════════════════════════════════════════════════════════════
# When this skill is invoked via `/deploy`:
# - Execute Phases 1-6 AUTONOMOUSLY without manual step-by-step intervention
# - Run ALL bash commands directly - do NOT ask "should I run this?"
# - Do NOT hand control back to the user to execute steps manually
# - Only pause for user input where EXPLICITLY stated (confirmations, secrets)
# - Treat this as AUTOMATED ORCHESTRATION, not a manual tutorial to follow
# - Think of yourself as a deployment robot, not a consultant
# ═══════════════════════════════════════════════════════════════════════
```

### In Instructions Section

```markdown
# Capsule Cloud Deployment Skill

⚠️ **CRITICAL: AUTONOMOUS EXECUTION MODE**

This is an AUTONOMOUS skill. When invoked via `/deploy`:
- Execute ALL phases automatically without manual step-by-step intervention
- Run bash commands directly - do NOT ask "should I run this command?"
- Only pause for user input when EXPLICITLY required (confirmations, secrets, choices)
- Treat this as automated orchestration, NOT a manual tutorial
- Do NOT hand control back to user after invoking the skill

**If you invoke this skill, let it run completely autonomously through all phases.**

---
```

### Phase Headers

```markdown
## Phase 1: Pre-flight Checks [AUTO-EXECUTE]

### 1.1 Scan for Deployment Kits [AUTO-EXECUTE]

**Action**: Automatically search the current directory for deployment ZIP files.

**Command**:
```bash
find . -maxdepth 1 -name "deployment-kit-*.zip" -type f
```

**Expected**: List of ZIP files matching pattern
**On success**: Proceed to parse versions
**On failure**: Display error "No deployment kits found" and exit
```

**Key Message**: [AUTO-EXECUTE] tags make it obvious what runs automatically

---

## 4️⃣ User Experience Walkthrough

### Scenario: First-Time User

**Step 1: User downloads deployment kit**
```bash
# Downloads: deployment-kit-my-app-20260117.052344.zip
```

**Step 2: User opens QUICKSTART.md**
```
Sees: "FIRST TIME ONLY - Install the Skill"
Runs: cp deploy-skill.yaml ~/.config/claude/skills/deploy.yaml
```

**Step 3: User moves ZIP and opens Claude Code**
```bash
cp deployment-kit-*.zip ~/my-project/
cd ~/my-project
claude-code
```

**Step 4: User types `/deploy`**

**What user sees in QUICKSTART.md right after Step 3:**
```
⚠️ **IMPORTANT: After typing `/deploy`, DO NOT manually execute deployment steps!**

The skill runs **AUTONOMOUSLY**. Just sit back and:
- Watch the progress
- Respond if asked for confirmations or secrets
- Let the skill handle everything else automatically
```

**User thinks**: "Ah, I should just watch and not interfere"

**Step 5: Skill executes autonomously**
```
Claude: Scanning for deployment kits...
Claude: Found: deployment-kit-my-app-20260117.052344.zip
Claude: Checking skill version... ✅ Versions match
Claude: Deploy my-app with version 20260117.052344? [Y/n]
User: Y
Claude: [Deployment proceeds automatically]
Claude: ✅ Deployment complete! https://server/my-app/
```

**User experience**: ✅ Smooth, autonomous, no manual intervention

---

### Scenario: User Opens CLAUDE_PROMPT.md Directly

**Step 1: User opens CLAUDE_PROMPT.md**

**First thing user sees:**
```markdown
## ⚠️ IMPORTANT: Choose Your Deployment Method

You have **TWO** ways to deploy:

### Method 1: Automated Skill (RECOMMENDED) ✅
[Instructions for /deploy]

⚠️ **CRITICAL**: If you invoke `/deploy`, do NOT manually execute the steps below.
Let the skill run autonomously. **STOP READING THIS FILE** and let the skill work.

---

### Method 2: Manual Deployment (Troubleshooting Only) 🔧
[Instructions for manual deployment]
```

**User decision tree**:
- If using `/deploy` → STOP READING, let skill work
- If troubleshooting → Continue reading manual steps

**Result**: ✅ No confusion between methods

---

### Scenario: MacBook Claude Invokes Skill

**Step 1: User types `/deploy` in Claude Code**

**Step 2: MacBook Claude reads skill file**

**First things Claude reads**:
```yaml
# META-INSTRUCTIONS FOR CLAUDE CODE AI
# - Execute Phases 1-6 AUTONOMOUSLY
# - Run ALL bash commands directly
# - Do NOT hand control back to the user
# - Think of yourself as a deployment robot
```

**Claude's understanding**: "I am a deployment robot, I execute autonomously"

**Step 3: Claude reads skill description**
```yaml
description: |
  AUTONOMOUS EXECUTION: This skill runs automatically when invoked with /deploy.
  Do not manually execute steps - let the skill handle everything.
```

**Claude's understanding**: "Confirmed - autonomous execution"

**Step 4: Claude reads instructions header**
```markdown
⚠️ **CRITICAL: AUTONOMOUS EXECUTION MODE**

This is an AUTONOMOUS skill. When invoked via `/deploy`:
- Execute ALL phases automatically
- Run bash commands directly - do NOT ask "should I run this?"
- Do NOT hand control back to user
```

**Claude's understanding**: "Crystal clear - I execute, I don't ask for permission"

**Step 5: Claude reads Phase 1**
```markdown
## Phase 1: Pre-flight Checks [AUTO-EXECUTE]

### 1.1 Scan for Deployment Kits [AUTO-EXECUTE]

**Action**: Automatically search for deployment ZIP files.
```

**Claude's behavior**: Immediately runs `find` command without asking

**Result**: ✅ Autonomous execution from start to finish

---

## 📊 Before vs After

### Before (Old Instructions)

**QUICKSTART.md**:
```
Step 3: Type /deploy

Done! The skill will deploy your app.
```
❌ **Problem**: No warning about manual execution

**CLAUDE_PROMPT.md**:
```
# Deployment Instructions

Step 0: Check skill version
Step 1: Display summary
...
```
❌ **Problem**: Reads like manual tutorial, no mention of /deploy skill

**deploy-skill.yaml**:
```yaml
## Phase 1: Pre-flight Checks

### 1.1 Scan for Deployment Kits
Search the current directory...

```bash
find . -name "*.zip"
```
```
❌ **Problem**: Reads like tutorial to follow, not automation directive

**Result**: Claude reads skill → thinks "manual tutorial" → takes over manually

---

### After (New Instructions)

**QUICKSTART.md**:
```
Step 3: Type /deploy

⚠️ **IMPORTANT: DO NOT manually execute deployment steps!**
The skill runs AUTONOMOUSLY. Just sit back and watch.
```
✅ **Solution**: Explicit warning right after /deploy command

**CLAUDE_PROMPT.md**:
```
## ⚠️ IMPORTANT: Choose Your Deployment Method

### Method 1: Automated Skill (RECOMMENDED) ✅
[/deploy instructions]
⚠️ If you invoke /deploy, STOP READING THIS FILE.

### Method 2: Manual (Troubleshooting Only) 🔧
[manual steps]
```
✅ **Solution**: Fork in the road, clear separation of methods

**deploy-skill.yaml**:
```yaml
# META-INSTRUCTIONS FOR CLAUDE CODE AI
# - Execute AUTONOMOUSLY
# - Do NOT hand control back to user

⚠️ **CRITICAL: AUTONOMOUS EXECUTION MODE**

## Phase 1: Pre-flight Checks [AUTO-EXECUTE]

### 1.1 Scan for Deployment Kits [AUTO-EXECUTE]

**Action**: Automatically search...
**Command**: find . -name "*.zip"
**Expected**: List of ZIPs
```
✅ **Solution**: Meta-instructions, warnings, [AUTO-EXECUTE] tags

**Result**: Claude reads skill → thinks "deployment robot" → executes autonomously

---

## 🎯 Key Improvements

| Location | Before | After |
|----------|--------|-------|
| **QUICKSTART.md** | No warning | ⚠️ DO NOT manually execute |
| **CLAUDE_PROMPT.md** | No skill mention | Fork: Automated vs Manual |
| **deploy-skill.yaml (top)** | No meta-instructions | META-INSTRUCTIONS section |
| **deploy-skill.yaml (header)** | Generic description | ⚠️ AUTONOMOUS EXECUTION MODE |
| **Phase headers** | No tags | [AUTO-EXECUTE] tags |
| **Language** | "Search for..." | "**Action**: Automatically search..." |

---

## ✅ Success Criteria

After these changes, users will:

1. ✅ **See clear warning** immediately after `/deploy` command
2. ✅ **Understand fork** between automated and manual methods
3. ✅ **Not try to "help"** by running commands manually
4. ✅ **Let skill run** autonomously from start to finish

After these changes, AI will:

1. ✅ **Read meta-instructions** before parsing skill
2. ✅ **Enter autonomous mode** immediately
3. ✅ **Execute phases** without asking permission
4. ✅ **Only pause** where marked [USER INTERACTION REQUIRED]
5. ✅ **Complete deployment** end-to-end without manual takeover

---

## 🚀 Summary

**The instructions now guide both humans and AI toward autonomous execution:**

- **Humans see**: "Don't interfere, let the skill work"
- **AI sees**: "You are a deployment robot, execute autonomously"

**Result**: Smooth, automated deployments with no manual takeover! ✅
