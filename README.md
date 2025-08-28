# 🚀 OCI-Start

<div align="center">

**一个使用API集成创建和管理甲骨文云的强大系统**

[![GitHub stars](https://img.shields.io/github/stars/doubleDimple/oci-start?style=flat-square&logo=github)](https://github.com/doubleDimple/oci-start)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)
[![Java](https://img.shields.io/badge/Java-8+-orange?style=flat-square&logo=java)](https://www.java.com)
[![Docker](https://img.shields.io/badge/Docker-Ready-blue?style=flat-square&logo=docker)](https://www.docker.com)

[![Deploy to EdgeOne](https://img.shields.io/badge/Deploy%20to-EdgeOne-1976d2?style=for-the-badge&logo=tencent-cloud&logoColor=white)](https://console.cloud.tencent.com/edgeone/pages/project?github=https://github.com/doubleDimple/oci-start)

</div>

---

## 📋 目录

- [功能特性](#-功能特性)
- [快速开始](#-快速开始)
- [部署方法](#-部署方法)
- [配置说明](#️-配置说明)
- [使用指南](#-使用指南)
- [截图展示](#-截图展示)
- [赞助支持](#-赞助支持)
- [免责声明](#️-免责声明)

---

## ✨ 功能特性

<div align="center">

| 🎯 功能 | 📝 描述 |
|---------|---------|
| **多实例开机** | 支持多个API多实例同时开机 |
| **实例管理** | 实例停止、启动、同步功能 |
| **引导卷管理** | 执行名称修改，引导卷VPU修改 |
| **网络配置** | 一键创建附属VNIC |
| **系统救援** | 一键救援系统功能 |
| **区域管理** | 区域订阅功能 |
| **安全规则** | 完善的安全规则管理系统 |
| **用户管理** | 查询、添加admin用户功能 |
| **IPv6支持** | IPv4切换一键开启IPv6 |
| **实例终止** | 安全终止实例操作 |
| **流量查询** | 实时实例流量监控 |
| **IP质量检测** | 自动检测并切换优质IP |

</div>

### 🔥 主要亮点

- 🌟 **多租户支持** - 使用API完成实例创建，支持多租户管理
- 🎛️ **可视化面板** - 直观的Web界面管理多个API
- 🔒 **数据安全** - API私钥存储在本地H2数据库
- 🤖 **智能机器人** - 仅用于抢机信息发送，不存储任何数据
- 🛠️ **实例管理** - 支持实例启动、停止、同步等完整生命周期管理
- 🌐 **网络增强** - 一键创建附属VNIC，灵活配置网络
- 🚑 **系统救援** - 快速救援系统，解决实例故障
- 📍 **区域订阅** - 智能区域管理，优化资源分配

---

## 🚀 快速开始

### 📋 环境要求

<div align="center">

![Java](https://img.shields.io/badge/Java-8+-ED8B00?style=for-the-badge&logo=java&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![Docker](https://img.shields.io/badge/Docker-2CA5E0?style=for-the-badge&logo=docker&logoColor=white)

</div>

#### 🐧 Debian/Ubuntu 环境准备
```bash
sudo apt update
sudo apt install default-jdk
```

---

## 🛠️ 部署方法

### 方法一：📜 脚本部署（推荐）

> ⚠️ **注意**：新版本会检测安装Redis，之前安装了Redis的可能会有影响

```bash
# 1. 🗂️ 切换到root用户并创建文件夹
mkdir -p oci-start && cd oci-start

# 2. 📥 下载执行脚本
wget -O oci-start.sh https://raw.githubusercontent.com/doubleDimple/shell-tools/master/oci-start.sh && chmod +x oci-start.sh

# 3. 🎯 直接运行脚本，即可自动安装部署
./oci-start.sh install
```

#### 🎮 脚本操作命令

```bash
# 🚀 启动应用程序
./oci-start.sh start

# ⏹️ 停止应用程序
./oci-start.sh stop

# 🔄 重启应用程序
./oci-start.sh restart    

# ⬆️ 更新到最新版本
./oci-start.sh update

# 🗑️ 完全卸载应用
./oci-start.sh uninstall
```

### 方法二：🐳 Docker部署

```bash
# 📁 创建工作目录
mkdir -p oci-start-docker && cd oci-start-docker

# 📥 下载Docker脚本
wget -O docker.sh https://raw.githubusercontent.com/doubleDimple/shell-tools/master/docker.sh && chmod +x docker.sh

# 🔧 执行脚本
./docker.sh install    # 安装应用
./docker.sh uninstall  # 卸载应用
```

#### 🐋 Docker管理命令

```bash
# 📊 查看容器状态
docker ps -a

# 📜 查看容器日志
docker logs oci-start
```

---

## ⚙️ 配置说明

> 💡 **升级提示**：对于已部署旧版本的用户，除了security配置需完全删除外，其他配置暂时保持不变

### 📝 基础配置

```yaml
# 🌐 端口配置（默认端口为9856）
server:
  port: 9856

# 🔗 域名访问配置（需要在nginx上配置）
location ~ ^/websockify/(\d+)$ {
    proxy_pass http://yourIp:$1;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_read_timeout 86400;
}
```

---

## 📖 使用指南

### 🎯 基本操作

```bash
# 🔑 添加执行权限
chmod 777 oci-start.sh

# 🚀 启动程序
./oci-start.sh start

# 📊 查看启动状态
./oci-start.sh status

# ⏹️ 停止程序
./oci-start.sh stop
```

### 🌐 访问方式

通过浏览器访问：`http://your-ip:port`

输入配置的用户名和密码即可开始使用！

---

## 📸 截图展示

<div align="center">

### 🏠 主界面
<img width="1423" alt="主界面" src="https://github.com/user-attachments/assets/23b9ab72-6212-42c3-a02c-3efa795ca9ea" />

### 📊 实例管理
<img width="1420" alt="实例管理" src="https://github.com/user-attachments/assets/af1ef632-84b9-4f08-a7d3-39480d518384" />

### ⚙️ 系统配置
<img width="1211" alt="系统配置" src="https://github.com/user-attachments/assets/306f307b-61b7-4e7c-b786-3d9e39471c91" />

### 🔧 高级设置
<img width="1432" alt="高级设置" src="https://github.com/user-attachments/assets/15994398-0bc9-4bef-aa81-7b44c75021fb" />

</div>

<details>
<summary>📱 更多截图</summary>

<img width="1420" alt="功能页面" src="https://github.com/user-attachments/assets/bf98973a-d3f6-4f2a-836f-3698647b8f3f" />

<img width="1427" alt="监控界面" src="https://github.com/user-attachments/assets/3e8c0ce8-6077-4748-bc39-fc1fa70da08e" />

<img width="1430" alt="数据统计" src="https://github.com/user-attachments/assets/0794298d-702f-4af7-ad5b-6cb5c206fa54" />

</details>

---

## 💖 赞助支持

<div align="center">

**非常感谢所有支持本项目的捐赠者！您的慷慨支持对我们至关重要。**

</div>

### 🎉 捐赠记录

感谢以下用户的慷慨支持（按时间顺序）：

| 👤 捐赠者 | 💰 金额/物品 | 📅 日期 |
|:----------:|:------------:|:--------:|
| 柯南 | GCP账号 | 2025-07-15 |
| Riva Milne | GCP账号 | 2025-07-15 |
| Ja3pez | ¥30 | 2025-07-15 |
| 匿名用户 | ¥50 | 2025-07-15 |
| 匿名用户 | ¥215 | 2025-07-14 |
| 匿名用户 | 云账号 | 2025-04-13 |
| 匿名用户 | 云账号 | 2025-04-13 |
| xdfaka | ¥68 | 2025-04-13 |

<details>
<summary>📜 查看更多捐赠记录</summary>

| 👤 捐赠者 | 💰 金额/物品 | 📅 日期 |
|:----------:|:------------:|:--------:|
| 匿名用户 | 云账号 | 2025-04-07 |
| 匿名用户 | ¥50 | 2025-04-06 |
| 匿名用户 | ¥9.9 | 2025-04-01 |
| 匿名用户 | ¥10 | 2025-04-01 |
| 匿名用户 | 云账号 | 2025-03-25 |
| 柯南 | 云账号 | 2025-03-15 |
| 匿名用户 | 云账号(升级) | 2025-03-08 |
| 匿名用户 | ¥9.9 | 2025-03-06 |
| 柯南 | ¥100 | 2025-03-01 |
| 匿名用户 | ¥200 | 2025-02-15 |
| 匿名用户 | ¥50 | 2024-11-05 |

</details>

### 💝 如何捐赠

如果您想支持我们的项目，可以通过oci-start的关于页面找到捐赠二维码。

> 💌 如需将您的名字添加到捐赠者名单中，请在捐赠后联系项目维护者。

---

## 🤝 赞助商

<div align="center">

**本项目大力感谢以下赞助商提供的支持！**

### 🏆 主要赞助商

[![YxVM](https://img.shields.io/badge/YxVM-服务器资源-blue?style=for-the-badge&logo=server&logoColor=white)](https://yxvm.com/aff.php?aff=762)

[![NodeSeek](https://img.shields.io/badge/NodeSeek-社区支持-green?style=for-the-badge&logo=discourse&logoColor=white)](https://github.com/NodeSeekDev/NodeSupport)

[![DartNode](https://dartnode.com/branding/DN-Open-Source-sm.png)](https://dartnode.com "Powered by DartNode - Free VPS for Open Source")

### 🚀 CDN 加速赞助商

<a href="https://edgeone.ai/zh?from=github" target="_blank">
  <img src="https://edgeone.ai/media/34fe3a45-492d-4ea4-ae5d-ea1087ca7b4b.png" alt="EdgeOne Logo" width="400"/>
</a>

**本项目 CDN 加速及安全防护由 [Tencent EdgeOne](https://edgeone.ai/zh?from=github) 赞助**

</div>

---

## 📊 项目统计

<div align="center">

### ⭐ Star历史

[![Star History Chart](https://api.star-history.com/svg?repos=doubleDimple/oci-start&type=Date)](https://star-history.com/#doubleDimple/oci-start&Date)

</div>

---

## ⚖️ 免责声明

<div align="center">

> ⚠️ **重要提示：如有介意请勿使用**

</div>

### 📜 免责条款

- 🔬 本仓库发布的项目中涉及的任何脚本，**仅用于测试和学习研究**，禁止用于商业用途
- ⚖️ 不能保证其合法性，准确性，完整性和有效性，请根据情况自行判断
- 📋 所有使用者在使用项目的任何部分时，需先遵守法律法规。对于一切使用不当所造成的后果，需自行承担
- 🛡️ 对任何脚本问题概不负责，包括但不限于由任何脚本错误导致的任何损失或损害
- 📄 如果任何单位或个人认为该项目可能涉嫌侵犯其权利，则应及时通知并提供身份证明，所有权证明，我们将在收到认证文件后删除相关文件
- 👀 任何以任何方式查看此项目的人或直接或间接使用该项目的任何脚本的使用者都应仔细阅读此声明
- 🔄 本人保留随时更改或补充此免责声明的权利。一旦使用并复制了任何相关脚本或本项目的规则，则视为您已接受此免责声明
- ⏰ 您必须在下载后的24小时内从计算机或手机中完全删除以上内容

---

<div align="center">

**🎉 感谢您的使用和支持！**

Made with ❤️ by [doubleDimple](https://github.com/doubleDimple)

</div>
