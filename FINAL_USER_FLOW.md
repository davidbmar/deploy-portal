# Final User Flow - Super Simple

## What Users See in QUICKSTART.md

```markdown
# QUICKSTART - Deploy my-app

## First Time: Unzip and Install Skill

Run this ONE command in your Downloads folder:

```bash
unzip deployment-kit-my-app-20260116.143022.zip && \
cd deployment-kit-my-app-20260116.143022 && \
cp deploy-skill.yaml ~/.config/claude/skills/deploy.yaml && \
echo "✅ Skill installed!"
```

Done! You only do this once EVER.

---

## Every Time: Use Skill

1. Move ZIP to your project:
   cp ~/Downloads/deployment-kit-*.zip ~/your-project/

2. Use skill:
   cd ~/your-project
   claude-code

Type: /deploy

Done! 🚀
```

---

## The Flow is Now

### First Time
```
Download ZIP → Unzip and install skill (one command)
```

### Every Time After
```
Use skill (/deploy)
```

---

## User Mental Model

**First time:**
"I run one command. It unzips and installs the skill. Done."

**Every deployment:**
"I type `/deploy`. Done."

---

## What the One Command Does

```bash
unzip deployment-kit-my-app-20260116.143022.zip && \
cd deployment-kit-my-app-20260116.143022 && \
cp deploy-skill.yaml ~/.config/claude/skills/deploy.yaml && \
echo "✅ Skill installed!"
```

**Step by step:**
1. `unzip deployment-kit-*.zip` → Extracts the ZIP
2. `cd deployment-kit-*/` → Goes into the folder
3. `cp deploy-skill.yaml ~/.config/claude/skills/deploy.yaml` → Installs skill
4. `echo "✅ Skill installed!"` → Confirms success

**User sees:**
```
Archive:  deployment-kit-my-app-20260116.143022.zip
  inflating: deployment-kit-my-app-20260116.143022/QUICKSTART.md
  inflating: deployment-kit-my-app-20260116.143022/deploy-skill.yaml
  ...
✅ Skill installed!
```

---

## Complete User Journey

### Day 1: First Deployment

```bash
# User downloads deployment-kit-my-app-20260116.143022.zip

# User runs one command
cd ~/Downloads
unzip deployment-kit-my-app-20260116.143022.zip && \
cd deployment-kit-my-app-20260116.143022 && \
cp deploy-skill.yaml ~/.config/claude/skills/deploy.yaml && \
echo "✅ Skill installed!"

# Output: ✅ Skill installed!

# User moves ZIP to project
cp ~/Downloads/deployment-kit-my-app-20260116.143022.zip ~/my-project/

# User deploys
cd ~/my-project
claude-code
# Types: /deploy

# Claude deploys the app
# Done!
```

### Day 2: Update Deployment

```bash
# User downloads NEW kit: deployment-kit-my-app-20260116.183045.zip

# User moves ZIP to project (skill already installed!)
cp ~/Downloads/deployment-kit-my-app-20260116.183045.zip ~/my-project/

# User deploys
cd ~/my-project
claude-code
# Types: /deploy

# Skill auto-updates (if needed)
# Claude deploys the update
# Done!
```

### Day 3: Deploy Different App

```bash
# User downloads: deployment-kit-other-app-20260116.190000.zip

# User moves ZIP to project (skill already installed!)
cp ~/Downloads/deployment-kit-other-app-20260116.190000.zip ~/other-project/

# User deploys
cd ~/other-project
claude-code
# Types: /deploy

# Same skill, different app
# Done!
```

---

## Framing Summary

| Action | First Time | Every Time |
|--------|-----------|------------|
| **What user does** | Unzip and install skill | Use skill |
| **Command** | One `unzip && cd && cp` | `/deploy` |
| **Takes** | 5 seconds | 2 seconds |
| **Result** | Skill installed | App deployed |

---

## Why This Works

**Simple language:**
- "Unzip and install skill" ✅
- "Use skill" ✅

**No confusion:**
- No mention of "where is the skill"
- No separate download steps
- No complex explanations

**One command:**
- Unzip → Install → Done
- All in one line

**Clear framing:**
- First time = setup
- Every time = just use it

---

## What Changed

### Before
```
"Install the deployment skill"
- Where is it?
- How do I get it?
- What do I do?
```

### After
```
"Unzip and install skill"
- Here's ONE command
- Copy/paste it
- Done
```

---

## Implementation Complete ✅

All files updated:
- ✅ QUICKSTART.md with one-command setup
- ✅ Clear "first time" vs "every time" framing
- ✅ No confusion about skill location
- ✅ Simple mental model

**User journey:**
1. First time: Unzip and install skill
2. Every time: Use skill

**That's it!** 🚀
