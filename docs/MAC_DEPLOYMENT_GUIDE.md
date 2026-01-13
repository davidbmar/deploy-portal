# Mac Deployment Guide - Step by Step

This guide explains **exactly** how to deploy applications from your Mac using the deployment kit and Claude Code.

## Overview

The deployment process has 3 simple steps:

1. **Download** the deployment kit from the web portal
2. **Extract** the files to a location Claude Code can access
3. **Use Claude Code** with the provided instructions to deploy

---

## Step 1: Get Your Deployment Kit

1. Open your web browser and go to the Deploy Portal:
   ```
   https://your-gateway.example.com/deploy/
   ```

2. Log in with your AWS Cognito credentials

3. Enter your app name (e.g., `my-app-01-test`)

4. Click **"Provision & Download Kit"**

5. A ZIP file will download with a name like:
   ```
   deployment-kit-my-app-01-test-1768271578672.zip
   ```

6. Note the download location (usually `~/Downloads/`)

---

## Step 2: Extract to the Correct Location

**IMPORTANT**: You need to extract the kit to a location that Claude Code can access.

### Option A: Extract to Documents (Recommended)

1. **Create a projects folder** (if you don't have one):
   ```bash
   mkdir -p ~/Documents/claude-projects
   ```

2. **Move the ZIP file** to your projects folder:
   ```bash
   mv ~/Downloads/deployment-kit-*.zip ~/Documents/claude-projects/
   ```

3. **Navigate to the folder**:
   ```bash
   cd ~/Documents/claude-projects
   ```

4. **Unzip the deployment kit**:
   ```bash
   unzip deployment-kit-*.zip
   ```

5. **You should now see** a folder structure like this:
   ```
   ~/Documents/claude-projects/
   └── my-app-01-test/
       ├── deploy-key.pem          ← SSH private key
       ├── DEPLOY_INSTRUCTIONS.md  ← Read this!
       ├── CLAUDE_PROMPT.txt       ← Copy this to Claude
       ├── app-config.json         ← App configuration
       └── README.md               ← Overview
   ```

### Option B: Extract to Desktop (Alternative)

If you prefer to see your project on the desktop:

1. **Move the ZIP to Desktop**:
   ```bash
   mv ~/Downloads/deployment-kit-*.zip ~/Desktop/
   ```

2. **Double-click the ZIP file** on your Desktop, or use terminal:
   ```bash
   cd ~/Desktop
   unzip deployment-kit-*.zip
   ```

3. **You'll see the folder** on your Desktop: `my-app-01-test/`

---

## Step 3: Deploy with Claude Code

Now you'll use Claude Code to deploy your application. Claude will handle all the SSH connection, file transfers, and deployment automation.

### 3.1: Open the Claude Prompt File

1. **Navigate to your extracted folder**:
   ```bash
   cd ~/Documents/claude-projects/my-app-01-test
   # or
   cd ~/Desktop/my-app-01-test
   ```

2. **Open the Claude prompt file**:
   ```bash
   cat CLAUDE_PROMPT.txt
   ```

3. **Copy the ENTIRE contents** to your clipboard:
   - On Mac: `cat CLAUDE_PROMPT.txt | pbcopy`
   - Or manually: Open in TextEdit and copy all

### 3.2: Start Claude Code

1. **Open Claude Code** in your terminal:
   ```bash
   # Make sure you're in the extracted folder
   cd ~/Documents/claude-projects/my-app-01-test

   # Start Claude Code
   claude-code
   ```

2. **Paste the prompt** you copied from `CLAUDE_PROMPT.txt`

3. **Press Enter**

### 3.3: Claude Will Deploy Your App

Claude Code will now:

1. ✅ **Connect via SSH** using the provided key (`deploy-key.pem`)
2. ✅ **Upload your application code** to the server
3. ✅ **Allocate a port** for your app (8000-8999 range)
4. ✅ **Register with nginx** to create the public URL path
5. ✅ **Create a systemd service** for auto-restart
6. ✅ **Start your application**
7. ✅ **Provide you the live URL**: `https://gateway.example.com/your-app/`

### 3.4: Example Claude Conversation

Here's what a typical deployment looks like:

```
You: [paste CLAUDE_PROMPT.txt contents]

Claude: I'll deploy your application "my-app-01-test" to the Capsule Cloud gateway.

Let me start by connecting via SSH...
[Connects using deploy-key.pem]

Connected successfully. Now I'll:
1. Create app directory: /home/ubuntu/apps/my-app-01-test
2. Upload your application files
3. Install dependencies
4. Allocate port: 8042
5. Register with nginx
6. Create systemd service
7. Start the application

[Performs all steps...]

✅ Deployment complete!

Your app is now live at:
https://52.43.35.1/my-app-01-test/

Service status:
• systemd: active (running)
• Port: 8042
• Health check: passing
```

---

## What's in the Deployment Kit?

Understanding the files helps you troubleshoot if needed:

### 📄 `deploy-key.pem`
- **SSH private key** for connecting to the server
- **IMPORTANT**: Keep this secure! Don't share it.
- Permissions are automatically set to `600` (read-only for you)

### 📄 `CLAUDE_PROMPT.txt`
- **Ready-to-paste instructions** for Claude Code
- Contains all connection details
- Includes your app name, server IP, and deployment steps

### 📄 `DEPLOY_INSTRUCTIONS.md`
- **Human-readable instructions** (this is what Claude reads)
- Explains what needs to be done
- Useful if you want to deploy manually

### 📄 `app-config.json`
- **Configuration file** with your app details:
  - App name: `my-app-01-test`
  - Your email: `you@example.com`
  - Server details
  - Port allocation
  - Nginx path: `/my-app-01-test/`

### 📄 `README.md`
- Overview of the deployment kit
- Quick reference links

---

## Troubleshooting

### Problem: "Permission denied (publickey)"

**Solution**: The SSH key file doesn't have the correct permissions.

```bash
cd ~/Documents/claude-projects/my-app-01-test
chmod 600 deploy-key.pem
```

### Problem: "Claude can't find the deployment kit files"

**Solution**: Make sure Claude Code is running from the correct directory.

```bash
# Navigate to the extracted folder FIRST
cd ~/Documents/claude-projects/my-app-01-test

# THEN start Claude Code
claude-code
```

### Problem: "Connection refused" or "Cannot connect to server"

**Possible causes**:
1. Your IP isn't whitelisted yet (the portal should have done this automatically)
2. The SSH key hasn't propagated yet (wait 30 seconds and retry)
3. The server is restarting (check portal status page)

**Solution**:
1. Go back to the Deploy Portal: `https://gateway.example.com/deploy/`
2. Check the **Status** page to see if all services are running
3. Wait 1-2 minutes and try again
4. If still failing, re-download a fresh deployment kit

### Problem: "Port already in use"

**Solution**: The port allocator might have assigned a port that's already taken.

Claude will automatically:
1. Detect the conflict
2. Request a new port from the allocator
3. Retry the deployment

If this fails multiple times, check the deployed apps in the portal.

### Problem: "App deployed but getting 502 Bad Gateway"

**Possible causes**:
1. App isn't running (check systemd status)
2. App is listening on wrong port
3. App crashed during startup

**Solution**: Ask Claude to:
```
Check the status of my app:
- systemctl status my-app-01-test
- journalctl -u my-app-01-test -n 50
- curl http://localhost:8042
```

---

## After Deployment

Once your app is deployed:

### View Your App
```
https://gateway.example.com/my-app-01-test/
```

### Check Logs
Go to the Deploy Portal → Activity page, or ask Claude:
```
Show me the logs for my-app-01-test
```

### Manage Your App
Go to the Deploy Portal → Apps page to:
- See all deployed apps
- View status (running/stopped)
- Check port assignments
- Delete apps (with confirmation)

### Update Your App
Just deploy again with the same app name. Claude will:
1. Stop the old version
2. Update the code
3. Restart with new code

---

## Advanced: Manual Deployment (Without Claude)

If you prefer to deploy manually without Claude Code:

1. **Connect via SSH**:
   ```bash
   ssh -i deploy-key.pem ubuntu@52.43.35.1
   ```

2. **Follow the instructions** in `DEPLOY_INSTRUCTIONS.md`

3. **Or use the automation scripts** on the server:
   ```bash
   # On the server
   cd /home/ubuntu/src/deploy-portal/automation
   ./deploy-app.sh my-app-01-test
   ```

But using Claude Code is **much easier** and handles everything automatically!

---

## Security Notes

### Keep Your SSH Key Safe

- **Never commit** `deploy-key.pem` to git
- **Don't share** the key with others
- **Delete** old keys when you're done with a project

The deployment kit includes a `.gitignore` that excludes `*.pem` files automatically.

### IP Whitelisting

Your IP is automatically whitelisted when you download the deployment kit. This access is:

- **Time-limited**: Usually 24 hours
- **Revocable**: You can remove it from the portal
- **Audited**: All access is logged

To extend your access, just download a new deployment kit.

---

## Quick Reference Commands

```bash
# Extract deployment kit
cd ~/Documents/claude-projects
unzip deployment-kit-*.zip
cd my-app-01-test

# Start Claude Code
claude-code
# Then paste contents of CLAUDE_PROMPT.txt

# Check SSH connection manually
ssh -i deploy-key.pem ubuntu@52.43.35.1

# View app logs remotely
ssh -i deploy-key.pem ubuntu@52.43.35.1 "journalctl -u my-app-01-test -n 50"

# Check if app is running
ssh -i deploy-key.pem ubuntu@52.43.35.1 "systemctl status my-app-01-test"

# Test app locally on server
ssh -i deploy-key.pem ubuntu@52.43.35.1 "curl http://localhost:8042"
```

---

## Summary

**The Process**:
1. 📥 Download kit from portal
2. 📂 Extract to `~/Documents/claude-projects/your-app-name/`
3. 💬 Paste `CLAUDE_PROMPT.txt` into Claude Code
4. ✅ App goes live at `https://gateway.example.com/your-app-name/`

**Key Points**:
- Extract to a location Claude can access (`~/Documents` or `~/Desktop`)
- Always `cd` into the extracted folder before starting Claude Code
- The entire prompt from `CLAUDE_PROMPT.txt` goes to Claude
- Your IP is automatically whitelisted for 24 hours
- Keep `deploy-key.pem` secure and private

**Need Help?**
- Check the Deploy Portal → Status page
- View logs in Deploy Portal → Activity
- Re-download a fresh deployment kit if something goes wrong

That's it! You're ready to deploy applications from your Mac using Claude Code. 🚀
