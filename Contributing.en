# Contributing to OCI-Start

Thanks for your interest in OCI-Start ❤️

This project aims to be a simpler, more efficient platform for Oracle Cloud management and automation. We welcome contributions in many forms:

- Bug fixes and new features
- Documentation and translations
- UI / UX improvements
- Performance optimization
- K8s / Docker / DevOps enhancements
- Cloud platform integrations

---

## Development Environment

| Tool | Required Version |
|------|------------------|
| JDK | 8+ |
| Maven | 3.6+ |
| Git | Latest |
| Docker | Optional |

---

## Local Development Workflow

### 1. Fork & Clone

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/oci-start.git
cd oci-start

# Add upstream remote
git remote add upstream https://github.com/doubleDimple/oci-start.git
git remote -v
```

### 2. Sync with Upstream

```bash
git checkout master
git pull upstream master
```

### 3. Create a Branch

**Do not commit directly to `master`.** Use the appropriate prefix for your branch:

| Type | Prefix | Example |
|------|--------|---------|
| New feature | `feature/` | `feature/k8s-install` |
| Bug fix | `fix/` | `fix/ssh-terminal-wrap` |
| Hotfix | `hotfix/` | `hotfix/auth-bypass` |
| Documentation | `docs/` | `docs/readme-en` |

```bash
git checkout -b feature/your-feature-name
```

---

## Commit Conventions

Follow the Conventional Commits style:

```
feat:     New feature
fix:      Bug fix
docs:     Documentation changes
style:    Formatting (no functional impact)
refactor: Code restructuring
perf:     Performance improvement
test:     Test-related changes
chore:    Build / tooling
```

Examples:

```
feat: add k8s install support
fix: repair websocket reconnect issue
refactor: optimize oci sdk client
docs: update deployment guide
```

---

## Submitting a Pull Request

### 1. Push Your Branch

```bash
git push origin feature/your-feature-name
```

### 2. Open a PR

When opening a PR on GitHub, make sure:

- The title is concise and conveys the core change
- The description includes: **context → solution → impact**
- UI changes include screenshots or a screen recording
- Breaking changes are clearly called out with compatibility notes

### 3. PR Checklist

- [ ] Code compiles and runs without errors
- [ ] No regression on existing functionality; tests added where appropriate
- [ ] Debug logs and commented-out code removed
- [ ] Naming follows project conventions
- [ ] No sensitive information (tokens, private keys, passwords)
- [ ] Documentation updated where relevant

---

## What Not to Commit

### General

- IDE config: `.idea/`, `.vscode/`
- Build output: `target/`, `build/`, `dist/`
- Dependencies: `node_modules/`
- Log files: `*.log`
- Any sensitive credentials

### Security Red Lines

The following will result in immediate PR closure if committed:

- OCI private keys / API keys
- Access tokens / refresh tokens
- Database connection strings (with passwords)
- Production configuration files

---

## Filing Issues

### Bug Reports

To help us reproduce and triage, please include:

- Operating system and version
- JDK version
- Docker version (if used)
- OCI region
- **Complete error log**
- **Steps to reproduce**

### Feature Requests

Suggestions are welcome around topics like:

- New OCI capabilities
- Multi-cloud support (AWS / GCP / Azure)
- K8s / Harbor integration
- SSH / VNC improvements
- Monitoring and alerting
- Automated deployment workflows

---

## Contact

- Repository: <https://github.com/doubleDimple/oci-start>
- Maintainer: [@doubleDimple](https://github.com/doubleDimple)

Thanks again for contributing — whether it's a single line of code, a documentation fix, or an issue report, every contribution makes OCI-Start better.
