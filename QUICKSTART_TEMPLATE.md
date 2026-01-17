# QUICKSTART - Deploy in 60 Seconds

## What You Have

You downloaded a ZIP file. Inside that ZIP is everything you need:
- **deploy-skill.yaml** ← This enables `/deploy` command
- **deployment-kit-{app_name}-{timestamp}.zip** ← Your deployment package
- SSH key, config, instructions

---

## First Time? Install the Skill (ONE TIME)

```bash
# 1. Extract the ZIP you downloaded
cd ~/Downloads
unzip deployment-kit-*.zip
cd deployment-kit-*/

# 2. Copy the skill file (one command)
cp deploy-skill.yaml ~/.config/claude/skills/deploy.yaml
```

**Done!** You only do this once. The skill stays installed forever and auto-updates.

---

## Deploy Your App (EVERY TIME)

```bash
# 1. Move the ZIP to your project
cp deployment-kit-*.zip ~/path/to/your-project/

# 2. Open Claude Code in your project
cd ~/path/to/your-project
claude-code

# 3. Type one command:
/deploy
```

**That's it!** Claude will:
- Find the deployment kit
- Deploy your app
- Give you the URL

---

## Next Time You Deploy

Just download a new kit and repeat the "Deploy Your App" steps above.

**No need to install the skill again** - it's already there and will auto-update.

---

## Where Does the Skill Come From?

**The skill is INSIDE the ZIP you downloaded.**

```
deployment-kit-my-app-20260116.143022.zip
├── deploy-skill.yaml          ← THE SKILL FILE
├── capsule-deploy.pem         ← SSH key
├── config.json                ← Configuration
├── README.md                  ← You're reading this
└── ... other files
```

When you extract the ZIP, the skill file is right there. You just copy it to `~/.config/claude/skills/`.

---

## Troubleshooting

**Q: I don't see deploy-skill.yaml**
```bash
# Make sure you extracted the ZIP first
cd ~/Downloads
unzip deployment-kit-*.zip
cd deployment-kit-*/
ls -la deploy-skill.yaml
```

**Q: Claude doesn't recognize /deploy**
```bash
# Check if skill is installed
ls -la ~/.config/claude/skills/deploy.yaml

# If missing, copy it again
cp deploy-skill.yaml ~/.config/claude/skills/deploy.yaml
```

**Q: Skill says it's outdated**

That's normal! Just run `/deploy` again. It auto-updates and then deploys.

---

## Visual Flow

```
┌─────────────────────────────────────────┐
│  1. Download ZIP from Portal            │
│     deployment-kit-*.zip → ~/Downloads  │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  2. Extract ZIP                         │
│     unzip deployment-kit-*.zip          │
│     → Creates folder with files inside  │
│       including deploy-skill.yaml       │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  3. Install Skill (ONE TIME)            │
│     cp deploy-skill.yaml                │
│        ~/.config/claude/skills/         │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  4. Move ZIP to Your Project            │
│     cp deployment-kit-*.zip             │
│        ~/my-project/                    │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  5. Run Claude Code                     │
│     cd ~/my-project                     │
│     claude-code                         │
│     Type: /deploy                       │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  6. ✅ App Deployed!                    │
│     Your app is live at:                │
│     https://your-server/your-app/       │
└─────────────────────────────────────────┘
```

---

## Summary

**The skill file is IN THE ZIP.** You extract it, copy it once, and you're done.

**One-time setup**: `cp deploy-skill.yaml ~/.config/claude/skills/deploy.yaml`

**Every deployment**: Move ZIP to project → Run `/deploy`

Simple as that!
