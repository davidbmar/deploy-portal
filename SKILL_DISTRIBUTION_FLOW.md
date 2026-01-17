# Deployment Skill Distribution Flow

## Complete Journey: From Server to Mac

```
┌─────────────────────────────────────────────────────────────────────┐
│                    DEPLOYMENT PORTAL (Server)                        │
│  /home/ubuntu/src/deploy-portal/                                    │
│                                                                      │
│  Files:                                                              │
│  ├── app.py                    (Flask application)                  │
│  ├── deploy-skill.yaml         (Skill template)                     │
│  └── config.py                 (Version constants)                  │
│                                                                      │
│  When user clicks "Download Kit":                                   │
│  1. Generates version: 20260116.143022                              │
│  2. Creates ZIP file with:                                          │
│     - capsule-deploy.pem                                            │
│     - README.md                                                     │
│     - CLAUDE_PROMPT.md                                              │
│     - config.json (includes version)                                │
│     - deploy-skill.yaml ← SKILL FILE INCLUDED!                      │
│     - automation scripts                                            │
│  3. Sends ZIP to user's browser                                     │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               │ Download
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         USER'S MAC                                   │
│  ~/Downloads/                                                        │
│  └── deployment-kit-my-app-20260116.143022.zip                     │
│                                                                      │
│  User extracts ZIP:                                                  │
│  $ cd ~/Downloads                                                    │
│  $ unzip deployment-kit-my-app-20260116.143022.zip                 │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               │ Extract
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│  ~/Downloads/deployment-kit-my-app-20260116.143022/                │
│  ├── capsule-deploy.pem                                             │
│  ├── README.md                                                      │
│  ├── CLAUDE_PROMPT.md                                               │
│  ├── config.json                                                    │
│  ├── deploy-skill.yaml      ← SKILL FILE IS HERE!                  │
│  └── automation/                                                    │
│                                                                      │
│  User installs skill:                                                │
│  $ cd ~/Downloads/deployment-kit-my-app-20260116.143022/           │
│  $ mkdir -p ~/.config/claude/skills                                 │
│  $ cp deploy-skill.yaml ~/.config/claude/skills/deploy.yaml        │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               │ Copy
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│  ~/.config/claude/skills/                                           │
│  └── deploy.yaml             ← SKILL INSTALLED!                     │
│                                                                      │
│  Claude Code can now use:                                           │
│  /deploy                                                             │
│  /deploy status                                                      │
│  /deploy update                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Step-by-Step: What Happens Where

### On the Server (Portal)

**Location**: `/home/ubuntu/src/deploy-portal/`

1. **Skill template exists**: `deploy-skill.yaml` with `DEPLOYMENT_VERSION_PLACEHOLDER`
2. **User requests kit**: Clicks "Download" button in web UI
3. **Portal generates version**: `20260116.143022` (current UTC timestamp)
4. **Portal loads skill**: Reads `deploy-skill.yaml` template
5. **Portal versions skill**: Replaces placeholder with actual version
6. **Portal creates ZIP**: Bundles all files including versioned skill
7. **ZIP downloaded**: Browser saves to `~/Downloads/`

**Key Code** (app.py:1153-1177):
```python
# Load and version the deployment skill
skill_path = os.path.join(os.path.dirname(__file__), Config.SKILL_FILE_PATH)
with open(skill_path, 'r') as f:
    skill_content = f.read()
# Replace version placeholder with actual version
skill_content = skill_content.replace('DEPLOYMENT_VERSION_PLACEHOLDER', version)

# Bundle into ZIP
with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zf:
    zf.writestr(f"{folder_name}/deploy-skill.yaml", skill_content)
```

---

### On the Mac (User's Machine)

**Step 1: Download**
```bash
# Browser downloads to:
~/Downloads/deployment-kit-my-app-20260116.143022.zip
```

**Step 2: Extract**
```bash
cd ~/Downloads
unzip deployment-kit-my-app-20260116.143022.zip

# Creates folder:
~/Downloads/deployment-kit-my-app-20260116.143022/
```

**Step 3: Verify Skill Exists**
```bash
cd ~/Downloads/deployment-kit-my-app-20260116.143022/
ls -la deploy-skill.yaml

# Should see:
-rw-r--r--  ... deploy-skill.yaml
```

**Step 4: Install Skill (One-Time)**
```bash
# Create Claude skills directory
mkdir -p ~/.config/claude/skills

# Copy skill to Claude's skills folder
cp deploy-skill.yaml ~/.config/claude/skills/deploy.yaml

# Verify installation
ls -la ~/.config/claude/skills/deploy.yaml
```

**Step 5: Move ZIP to Project**
```bash
# Move to your actual project directory
cp deployment-kit-my-app-20260116.143022.zip ~/my-project/

cd ~/my-project
```

**Step 6: Deploy**
```bash
# Start Claude Code
claude-code

# In Claude Code:
/deploy
```

---

## Common Questions

### Q: Where does the skill come from?
**A**: The skill is **bundled inside the ZIP file** the portal generates. It's not downloaded separately.

### Q: Do I need to download the skill from somewhere else?
**A**: No! The skill is already in the ZIP you downloaded. Just extract and copy it.

### Q: Why do I need to copy it to `~/.config/claude/skills/`?
**A**: That's where Claude Code looks for custom skills. It's like installing a browser extension - you put it in the right folder so the application can find it.

### Q: Do I need to install the skill every time I deploy?
**A**: No! It's a **one-time setup**. Once installed, you can use `/deploy` for any app. The skill will auto-update itself if the portal has a newer version.

### Q: What if I deploy a different app?
**A**: Same skill works for all apps! Just download the new app's kit, move the ZIP to your project, and run `/deploy`.

### Q: Can I update the skill manually?
**A**: Yes! You can run `/deploy update` to force a skill update, or just download a new deployment kit and copy its `deploy-skill.yaml` over the old one.

---

## Troubleshooting

### "I don't see deploy-skill.yaml in the extracted folder"

**Possible causes**:
1. You downloaded an old kit (before skill feature was added)
2. ZIP extraction failed or was incomplete
3. File permissions issue

**Solutions**:
```bash
# Re-download a fresh deployment kit from the portal
# Extract again and verify:
cd ~/Downloads/deployment-kit-*/
ls -la deploy-skill.yaml

# If still missing, the portal might need updating
```

### "Claude doesn't recognize /deploy command"

**Possible causes**:
1. Skill not installed in correct location
2. Wrong filename (must be `deploy.yaml`, not `deploy-skill.yaml`)

**Solutions**:
```bash
# Check if skill is installed
ls -la ~/.config/claude/skills/deploy.yaml

# If missing, install it:
cd ~/Downloads/deployment-kit-*/
cp deploy-skill.yaml ~/.config/claude/skills/deploy.yaml

# Restart Claude Code
```

### "Skill says it's outdated"

**This is normal and expected!** The skill will auto-update itself:

```
You: /deploy

Claude: Checking portal version... Portal has newer version!
Downloading skill update from portal...
✅ Skill updated from 20260115.120000 to 20260116.143022
Please run /deploy again to use the new version.

You: /deploy

Claude: [deployment proceeds with new version]
```

---

## Summary

**The skill file travels like this**:

1. 📦 **Server** → Skill bundled in ZIP
2. 💾 **Download** → ZIP to `~/Downloads/`
3. 📂 **Extract** → Skill visible in folder
4. 📋 **Copy** → Skill to `~/.config/claude/skills/deploy.yaml`
5. ✅ **Use** → `/deploy` command works!

**Key point**: The skill is **inside the ZIP you download**. You don't need to get it from anywhere else!
