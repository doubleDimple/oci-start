# Contributing to OCI-Start

感谢你对 OCI-Start 的关注 ❤️

本项目致力于打造更简单、更高效的 Oracle Cloud 管理与自动化平台。我们欢迎以下形式的贡献:

- Bug 修复 / 新功能开发
- 文档与翻译
- UI / UX 改进
- 性能优化
- K8s / Docker / DevOps 能力增强
- 云平台生态集成

---

## 开发环境

| 软件 | 版本要求 |
|------|---------|
| JDK | 8+ |
| Maven | 3.6+ |
| Git | 最新版 |
| Docker | 可选 |

---

## 本地开发流程

### 1. Fork 并克隆

```bash
# Fork 后克隆你自己的仓库
git clone https://github.com/YOUR_USERNAME/oci-start.git
cd oci-start

# 添加上游仓库
git remote add upstream https://github.com/doubleDimple/oci-start.git
git remote -v
```

### 2. 同步上游

```bash
git checkout master
git pull upstream master
```

### 3. 创建分支

**请勿直接向 `master` 提交代码。** 按用途使用对应前缀:

| 类型 | 分支前缀 | 示例 |
|------|---------|------|
| 新功能 | `feature/` | `feature/k8s-install` |
| Bug 修复 | `fix/` | `fix/ssh-terminal-wrap` |
| 紧急修复 | `hotfix/` | `hotfix/auth-bypass` |
| 文档 | `docs/` | `docs/readme-cn` |

```bash
git checkout -b feature/your-feature-name
```

---

## Commit 规范

使用约定式提交(Conventional Commits)风格:

```
feat:     新功能
fix:      Bug 修复
docs:     文档变更
style:    代码格式(不影响功能)
refactor: 重构
perf:     性能优化
test:     测试相关
chore:    构建 / 工具链
```

示例:

```
feat: add k8s install support
fix: repair websocket reconnect issue
refactor: optimize oci sdk client
docs: update deployment guide
```

---

## 提交 Pull Request

### 1. 推送分支

```bash
git push origin feature/your-feature-name
```

### 2. 创建 PR

前往 GitHub 提交 PR,请确保:

- 标题简洁清晰,能表达核心变更
- 描述包含:**问题背景 → 解决方案 → 影响范围**
- UI 变更附上截图或录屏
- 涉及破坏性变更请明确说明兼容性影响

### 3. PR 自查清单

- [ ] 代码可正常编译运行
- [ ] 不影响已有功能,必要时已补充测试
- [ ] 已清理调试日志、注释代码
- [ ] 命名风格与项目一致
- [ ] 无敏感信息(Token、私钥、密码等)
- [ ] 相关文档已同步更新

---

## 提交规范

### 不要提交以下内容

- IDE 配置文件: `.idea/`, `.vscode/`
- 编译产物: `target/`, `build/`, `dist/`
- 依赖目录: `node_modules/`
- 日志文件: `*.log`
- 任何敏感凭证: Token、API Key、私钥、生产配置

### 安全红线

**绝对禁止**提交以下内容,一经发现立即关闭 PR:

- OCI 私钥 / API Key
- Access Token / Refresh Token
- 数据库连接串(含密码)
- 生产环境配置文件

---

## 提交 Issue

### Bug 报告

请尽量包含以下信息,便于复现与定位:

- 操作系统及版本
- JDK 版本
- Docker 版本(如使用)
- OCI 区域
- **完整错误日志**
- **可复现的步骤**

### 功能建议

欢迎围绕以下方向提出建议:

- 新的 OCI 能力支持
- 多云平台集成(AWS / GCP / Azure)
- K8s / Harbor 集成
- SSH / VNC 体验优化
- 监控与告警
- 自动化部署能力

---

## 联系方式

- 仓库地址: <https://github.com/doubleDimple/oci-start>
- 维护者: [@doubleDimple](https://github.com/doubleDimple)

再次感谢你的贡献 —— 无论是一行代码、一处文档修复,还是一个 Issue,都让 OCI-Start 变得更好。
