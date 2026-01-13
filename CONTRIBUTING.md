# Contributing to Deploy Portal

Thank you for your interest in contributing! This document provides guidelines for contributing to the Deploy Portal project.

## 🚀 Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/deploy-portal.git
   cd deploy-portal
   ```
3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```
4. **Run locally**:
   ```bash
   python3 app.py
   ```

## 🌿 Branch Strategy

- `main` - Production-ready code
- `develop` - Development branch (merge here first)
- `feature/*` - New features
- `bugfix/*` - Bug fixes
- `docs/*` - Documentation updates

### Creating a Branch

```bash
git checkout -b feature/my-new-feature
```

## 📝 Making Changes

### Code Style

- **Python**: Follow PEP 8 style guide
- **HTML/CSS**: Use consistent indentation (2 spaces)
- **JavaScript**: Use ES6+ features, consistent semicolons

### Commit Messages

Use clear, descriptive commit messages:

```
Add feature: User can delete deployed apps from catalog

- Add DELETE endpoint for /apps/delete/<app_name>
- Add confirmation dialog in apps_catalog.html
- Update registry when app is deleted
- Add audit log entry for deletions
```

**Format**:
- First line: Brief summary (50 chars or less)
- Blank line
- Detailed explanation (if needed)
- List changes as bullet points

### Testing Your Changes

Before submitting:

1. **Test the UI**: Visit all routes and ensure they work
2. **Test API endpoints**: Use curl or Postman
3. **Check logs**: Ensure no errors in console
4. **Verify security**: No secrets in code, proper permissions

```bash
# Test basic functionality
curl http://localhost:5000/
curl http://localhost:5000/apps
curl http://localhost:5000/status

# Check for Python errors
python3 -m py_compile app.py config.py
```

## 🔐 Security Guidelines

### Never Commit Secrets

- SSH keys (*.pem)
- AWS credentials
- API keys or tokens
- User data or logs

### Follow Security Best Practices

- Validate all user input
- Use parameterized queries (if adding database)
- Keep dependencies updated
- Follow principle of least privilege
- Log security-relevant events

### Report Security Issues

DO NOT create public issues for security vulnerabilities.

Email security concerns to: security@yourproject.com

## 📚 Documentation

### Update Documentation When:

- Adding new routes or API endpoints
- Changing configuration options
- Adding new features
- Modifying automation scripts

### Documentation Files to Update:

- `README.md` - Main project documentation
- `docs/ARCHITECTURE.md` - If changing architecture
- `docs/MAC_DEPLOYMENT_GUIDE.md` - If changing deployment process
- Inline code comments - For complex logic

## 🧪 Pull Request Process

1. **Update your branch** with latest main:
   ```bash
   git checkout main
   git pull origin main
   git checkout feature/my-new-feature
   git rebase main
   ```

2. **Push your branch**:
   ```bash
   git push origin feature/my-new-feature
   ```

3. **Create Pull Request** on GitHub:
   - Use a clear, descriptive title
   - Reference any related issues
   - Describe what changed and why
   - Add screenshots for UI changes
   - Check the "Allow edits from maintainers" box

4. **Wait for Review**:
   - Address any feedback
   - Make requested changes
   - Push updates (they'll appear in the PR)

5. **After Approval**:
   - Maintainer will merge your PR
   - You can delete your feature branch

### Pull Request Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Breaking change

## Testing
- [ ] Tested locally
- [ ] All routes work correctly
- [ ] No console errors
- [ ] Security considerations addressed

## Screenshots (if applicable)
Add screenshots of UI changes

## Checklist
- [ ] Code follows project style
- [ ] Documentation updated
- [ ] No secrets committed
- [ ] .gitignore updated if needed
```

## 🐛 Bug Reports

### Before Reporting

1. Check existing issues
2. Try to reproduce on latest version
3. Gather relevant information

### Include in Bug Report

- **Description**: What happened vs what should happen
- **Steps to Reproduce**: Exact steps to trigger the bug
- **Environment**: OS, Python version, browser
- **Logs**: Relevant error messages or logs
- **Screenshots**: If applicable

### Bug Report Template

```markdown
**Describe the bug**
Clear description of the bug

**To Reproduce**
1. Go to '...'
2. Click on '...'
3. See error

**Expected behavior**
What should have happened

**Screenshots**
If applicable

**Environment**
- OS: [e.g. Ubuntu 22.04]
- Python: [e.g. 3.10]
- Browser: [e.g. Chrome 120]

**Logs**
```
paste relevant logs here
```
```

## ✨ Feature Requests

### Before Requesting

1. Check existing issues and PRs
2. Consider if it fits project scope
3. Think about implementation

### Include in Feature Request

- **Use Case**: Why is this needed?
- **Proposed Solution**: How should it work?
- **Alternatives**: Other approaches considered
- **Additional Context**: Mockups, examples, etc.

## 🏗️ Project Structure

### Key Files

- `app.py` - Main Flask application (routes, logic)
- `config.py` - Configuration settings
- `templates/` - HTML templates (Jinja2)
- `static/` - CSS, JavaScript, images
- `automation/` - Bash scripts for deployment
- `docs/` - Documentation files

### Adding New Routes

1. Add route handler in `app.py`
2. Create template in `templates/`
3. Update navigation in `templates/base.html`
4. Add documentation in README
5. Test thoroughly

### Adding New Features

1. Plan the feature (use issues for discussion)
2. Create feature branch
3. Implement with tests
4. Update documentation
5. Submit PR

## 📋 Code Review Checklist

Reviewers will check:

- [ ] Code is clean and readable
- [ ] No hardcoded secrets or credentials
- [ ] Error handling is appropriate
- [ ] User input is validated
- [ ] Documentation is updated
- [ ] .gitignore is updated if needed
- [ ] No unnecessary files committed
- [ ] Commit messages are clear
- [ ] PR description is complete

## 🤝 Community Guidelines

### Be Respectful

- Treat everyone with respect
- Welcome newcomers
- Be patient with questions
- Provide constructive feedback

### Be Collaborative

- Share knowledge
- Help others learn
- Accept feedback graciously
- Focus on what's best for the project

### Be Professional

- Keep discussions on-topic
- No spam or self-promotion
- Follow code of conduct
- Report violations privately

## 📞 Getting Help

- **Documentation**: Start with README.md and docs/
- **Issues**: Search existing issues first
- **Discussions**: Use GitHub Discussions for questions
- **Email**: maintainer@yourproject.com

## 🎉 Recognition

Contributors will be:
- Listed in CONTRIBUTORS.md
- Mentioned in release notes
- Credited in commit history

Thank you for contributing to Deploy Portal! 🚀
