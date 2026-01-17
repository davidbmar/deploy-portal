# How the Deployment Skill Works - Simple Explanation

## The Big Picture

**Question**: How does the skill get from the server to my Mac?

**Answer**: It's bundled inside the ZIP file you download.

---

## Step-by-Step Flow

### 1. On the Server (Portal)

```
/home/ubuntu/src/deploy-portal/
├── app.py                  ← Flask app
├── deploy-skill.yaml       ← Skill template
└── config.py
```

When you click "Download Kit":
- Portal reads `deploy-skill.yaml`
- Replaces version placeholder with current version
- Creates ZIP file
- Bundles skill inside ZIP
- Sends ZIP to your browser

### 2. Download to Mac

```
~/Downloads/
└── deployment-kit-my-app-20260116.143022.zip  ← Downloaded file
```

### 3. Extract ZIP

```bash
cd ~/Downloads
unzip deployment-kit-my-app-20260116.143022.zip
```

Now you have:

```
~/Downloads/deployment-kit-my-app-20260116.143022/
├── QUICKSTART.md          ← READ THIS FIRST
├── deploy-skill.yaml      ← THE SKILL FILE IS HERE
├── capsule-deploy.pem     ← SSH key
├── README.md
├── CLAUDE_PROMPT.md
├── config.json
└── automation/
```

**The skill file is RIGHT THERE in the extracted folder.**

### 4. Install Skill (One Command)

```bash
cd ~/Downloads/deployment-kit-my-app-20260116.143022/
cp deploy-skill.yaml ~/.config/claude/skills/deploy.yaml
```

This copies the skill to where Claude Code looks for skills.

### 5. Use It

```bash
# Move ZIP to your project
cp deployment-kit-my-app-*.zip ~/my-project/

# Go to your project
cd ~/my-project

# Start Claude Code
claude-code

# Type one command
/deploy
```

---

## FAQs

### Why is the skill in the ZIP?

**Problem**: How do we get the skill to users' Macs?

**Options considered**:
1. ❌ Separate download → Users need to download two things
2. ❌ Git repository → Requires git, extra setup
3. ❌ npm package → Requires Node.js
4. ✅ **Bundle in ZIP** → Simple, works offline, one download

**We chose option 4**: Bundle it in the ZIP you already download.

### Do I need to install it every time?

**No!**

- **Install once**: When you first use the skill
- **Use forever**: Works for all future deployments
- **Auto-updates**: Skill updates itself when portal has newer version

### What happens when I run /deploy?

The skill:
1. Scans current directory for `deployment-kit-*.zip` files
2. Parses versions from filenames
3. Selects the latest one
4. Checks portal for version updates
5. Auto-updates itself if needed
6. Extracts ZIP and deploys your app

### Where does the skill live on my Mac?

```
~/.config/claude/skills/deploy.yaml
```

Claude Code looks in `~/.config/claude/skills/` for custom skills.

### Can I have multiple versions?

The skill manages this for you:
- You can have multiple deployment kit ZIPs
- Skill auto-selects the latest by version
- Skill auto-updates to match portal version

### What's in the skill file?

It's a YAML file with deployment instructions:

```yaml
name: deploy
version: 20260116.143022
description: Deploy applications to Capsule Cloud
commands:
  - name: deploy
    instructions: |
      [Detailed deployment workflow]
  - name: deploy status
    instructions: |
      [Check deployment status]
```

---

## Visual: Skill Journey

```
┌──────────────────────────────────────────────┐
│          SERVER                              │
│  deploy-skill.yaml (template)                │
│         ↓                                    │
│  Version it (20260116.143022)                │
│         ↓                                    │
│  Bundle into ZIP                             │
└──────────────────┬───────────────────────────┘
                   │
                   │ Download
                   ↓
┌──────────────────────────────────────────────┐
│          MAC                                 │
│  deployment-kit-*.zip                        │
│         ↓                                    │
│  Extract ZIP                                 │
│         ↓                                    │
│  deploy-skill.yaml (in folder)               │
│         ↓                                    │
│  cp deploy-skill.yaml                        │
│     ~/.config/claude/skills/deploy.yaml      │
│         ↓                                    │
│  ✅ Skill installed!                         │
└──────────────────────────────────────────────┘
```

---

## What's Actually in the ZIP?

When you extract `deployment-kit-my-app-20260116.143022.zip`:

```
deployment-kit-my-app-20260116.143022/
│
├── QUICKSTART.md              ← Start here!
│                                 Simple 3-step guide
│
├── deploy-skill.yaml          ← The skill file
│                                 Copy this to ~/.config/claude/skills/
│
├── capsule-deploy.pem         ← SSH key
│                                 Used to connect to server
│
├── README.md                  ← Overview and options
│
├── CLAUDE_PROMPT.md           ← Manual deployment instructions
│                                 For Option 2 (manual method)
│
├── config.json                ← Configuration
│                                 Contains version, app details
│
├── .env.example               ← Environment template
│
└── automation/                ← Deployment scripts
    ├── deploy-app.sh
    ├── nginx-register.sh
    ├── port-allocator.sh
    ├── registry-manager.sh
    └── systemd-register.sh
```

---

## Summary

**The skill is bundled in the ZIP you download.**

1. Download ZIP from portal
2. Extract ZIP → See `deploy-skill.yaml` file
3. Copy skill file to `~/.config/claude/skills/deploy.yaml`
4. Done! Use `/deploy` forever

**No separate downloads. No git clones. No npm installs.**

Just: Download → Extract → Copy → Deploy!
