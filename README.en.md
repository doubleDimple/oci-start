<p align="right">
   <a href="./README.md">中文</a> | <strong>English</strong>
</p>

# 🚀 OCI-Start

<div align="center">

**A powerful system for creating and managing Oracle Cloud instances using API integration**

[![GitHub stars](https://img.shields.io/github/stars/doubleDimple/oci-start?style=flat-square&logo=github)](https://github.com/doubleDimple/oci-start)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)
[![Java](https://img.shields.io/badge/Java-8+-orange?style=flat-square&logo=java)](https://www.java.com)
[![Docker](https://img.shields.io/badge/Docker-Ready-blue?style=flat-square&logo=docker)](https://www.docker.com)

[![Deploy to EdgeOne](https://img.shields.io/badge/Deploy%20to-EdgeOne-1976d2?style=for-the-badge&logo=tencent-cloud&logoColor=white)](https://console.cloud.tencent.com/edgeone/pages/project?github=https://github.com/doubleDimple/oci-start)

</div>

---

## 📋 Table of Contents

- [Features](#-features)
- [Quick Start](#-quick-start)
- [Deployment Methods](#-deployment-methods)
- [Configuration](#️-configuration)
- [Usage Guide](#-usage-guide)
- [Screenshots](#-screenshots)
- [Sponsorship](#-sponsorship)
- [Disclaimer](#️-disclaimer)

---

## ✨ Features

<div align="center">

| 🎯 Feature | 📝 Description |
|---------|---------|
| **Multi-Instance Launch** | Support multiple APIs and instances launching simultaneously |
| **Instance Management** | Instance stop, start, and synchronization functionality |
| **Boot Volume Management** | Modify instance names and boot volume VPU |
| **Network Configuration** | One-click creation of secondary VNICs |
| **System Rescue** | One-click system rescue functionality |
| **Region Management** | Region subscription features |
| **Security Rules** | Comprehensive security rule management system |
| **User Management** | Query and add admin user functionality |
| **IPv6 Support** | One-click IPv4 to IPv6 switching |
| **Instance Termination** | Safe instance termination operations |
| **Traffic Monitoring** | Real-time instance traffic monitoring |
| **IP Quality Detection** | Automatic detection and switching to high-quality IPs |

</div>

### 🔥 Key Highlights

- 🌟 **Multi-tenant Support** - Complete instance creation using APIs with multi-tenant management
- 🎛️ **Visual Dashboard** - Intuitive web interface for managing multiple APIs
- 🔒 **Data Security** - API private keys stored in local H2 database
- 🤖 **Smart Bot** - Used only for grabbing machine notifications, no data storage
- 🛠️ **Instance Management** - Complete lifecycle management including start, stop, sync
- 🌐 **Network Enhancement** - One-click secondary VNIC creation with flexible network configuration
- 🚑 **System Rescue** - Quick system rescue to resolve instance failures
- 📍 **Region Subscription** - Intelligent region management for optimized resource allocation

---

## 🚀 Quick Start

### 📋 System Requirements

<div align="center">

![Java](https://img.shields.io/badge/Java-8+-ED8B00?style=for-the-badge&logo=java&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
![Docker](https://img.shields.io/badge/Docker-2CA5E0?style=for-the-badge&logo=docker&logoColor=white)

</div>

#### 🐧 Debian/Ubuntu Environment Setup
```bash
sudo apt update
sudo apt install default-jdk
```

---

## 🛠️ Deployment Methods

### Method 1: 📜 Script Deployment (Recommended)
```bash
# 1. 🗂️ Switch to root user and create folder
mkdir -p oci-start && cd oci-start

# 2. 📥 Download execution script
wget -O oci-start.sh https://raw.githubusercontent.com/doubleDimple/shell-tools/master/oci-start.sh && chmod +x oci-start.sh

# 3. 🎯 Run script directly for automatic installation and deployment
./oci-start.sh install
```

#### 🎮 Script Commands

```bash
# 🚀 Start application
./oci-start.sh start

# ⏹️ Stop application
./oci-start.sh stop

# 🔄 Restart application
./oci-start.sh restart    

# ⬆️ Update to latest version
./oci-start.sh update

# 🗑️ Complete uninstall
./oci-start.sh uninstall
```

### Method 2: 🐳 Docker Deployment

```bash
# 📁 Create working directory
mkdir -p oci-start-docker && cd oci-start-docker

# 📥 Download Docker script
wget -O docker.sh https://raw.githubusercontent.com/doubleDimple/shell-tools/master/docker.sh && chmod +x docker.sh

# 🔧 Execute script
./docker.sh install    # Install application
./docker.sh uninstall  # Uninstall application
```

#### 🐋 Docker Management Commands

```bash
# 📊 View container status
docker ps -a

# 📜 View container logs
docker logs oci-start
```

---

## ⚙️ Configuration

> 💡 **Upgrade Note**: For users with existing deployments, all configurations remain unchanged except security settings which need to be completely removed

### 📝 Basic Configuration

```yaml
# 🌐 Port configuration (default port is 9856)
server:
  port: 9856

# 🔗 Domain access configuration (requires nginx configuration)
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

## 📖 Usage Guide

### 🎯 Basic Operations

```bash
# 🔑 Add execution permissions
chmod 777 oci-start.sh

# 🚀 Start program
./oci-start.sh start

# 📊 Check startup status
./oci-start.sh status

# ⏹️ Stop program
./oci-start.sh stop
```

### 🌐 Access Method

Access through browser: `http://your-ip:port`

If it is the first deployment, you need to register the account and password yourself. The registration page will only appear during the first deployment.

---

## 📸 Screenshots

<div align="center">

### 🏠 Main Interface
<img width="1423" alt="Main Interface" src="https://github.com/user-attachments/assets/23b9ab72-6212-42c3-a02c-3efa795ca9ea" />

### 📊 Instance Management
<img width="1420" alt="Instance Management" src="https://github.com/user-attachments/assets/af1ef632-84b9-4f08-a7d3-39480d518384" />

### ⚙️ System Configuration
<img width="1211" alt="System Configuration" src="https://github.com/user-attachments/assets/306f307b-61b7-4e7c-b786-3d9e39471c91" />

### 🔧 Advanced Settings
<img width="1432" alt="Advanced Settings" src="https://github.com/user-attachments/assets/15994398-0bc9-4bef-aa81-7b44c75021fb" />

</div>

<details>
<summary>📱 More Screenshots</summary>

<img width="1420" alt="Features Page" src="https://github.com/user-attachments/assets/bf98973a-d3f6-4f2a-836f-3698647b8f3f" />

<img width="1427" alt="Monitor Interface" src="https://github.com/user-attachments/assets/3e8c0ce8-6077-4748-bc39-fc1fa70da08e" />

<img width="1430" alt="Data Statistics" src="https://github.com/user-attachments/assets/0794298d-702f-4af7-ad5b-6cb5c206fa54" />

</details>

---

## 💖 Sponsorship

<div align="center">

**Thank you very much to all donors supporting this project! Your generous support is crucial to us.**

</div>

### 🎉 Donation Records

Thanks to the following users for their generous support (in chronological order):

| 👤 Donor | 💰 Amount/Item | 📅 Date |
|:----------:|:------------:|:--------:|
| Anonymous | ¥30 | 2025-11-02 |
| @yuchenfan492 | ¥30 | 2025-10-26 |
| @ananitsme | ¥50 | 2025-10-25 |
| Conan(@KN_001) | ¥200 | 2025-10-25 |
| @xwbay | ¥88 | 2025-10-18 |
| Anonymous | ¥10 | 2025-09-21 |
| Conan(@KN_001) | ¥100 | 2025-09-13 |
| Conan(@KN_001) | GCP Account | 2025-07-15 |
| Riva Milne | GCP Account | 2025-07-15 |
| Ja3pez | ¥30 | 2025-07-15 |
| Anonymous | ¥50 | 2025-07-15 |
| Anonymous | ¥215 | 2025-07-14 |
| Anonymous | Cloud Account | 2025-04-13 |
| Anonymous | Cloud Account | 2025-04-13 |
| xdfaka | ¥68 | 2025-04-13 |

<details>
<summary>📜 View More Donation Records</summary>

| 👤 Donor | 💰 Amount/Item | 📅 Date |
|:----------:|:------------:|:--------:|
| Anonymous | Cloud Account | 2025-04-07 |
| Anonymous | ¥50 | 2025-04-06 |
| Anonymous | ¥9.9 | 2025-04-01 |
| Anonymous | ¥10 | 2025-04-01 |
| Anonymous | Cloud Account | 2025-03-25 |
| Conan | Cloud Account | 2025-03-15 |
| Anonymous | Cloud Account (Upgrade) | 2025-03-08 |
| Anonymous | ¥9.9 | 2025-03-06 |
| Conan | ¥100 | 2025-03-01 |
| Anonymous | ¥200 | 2025-02-15 |
| Anonymous | ¥50 | 2024-11-05 |

</details>

### 💝 How to Donate

If you would like to support our project, you can find the donation QR code on the About page of oci-start.

> 💌 If you want your name added to the donor list, please contact the project maintainer after donating.

---

## 🤝 Sponsors

<div align="center">

**This project greatly appreciates the support provided by the following sponsors!**

### 🏆 Main Sponsors

[![YxVM](https://img.shields.io/badge/YxVM-Server%20Resources-blue?style=for-the-badge&logo=server&logoColor=white)](https://yxvm.com/aff.php?aff=762)

[![NodeSeek](https://img.shields.io/badge/NodeSeek-Community%20Support-green?style=for-the-badge&logo=discourse&logoColor=white)](https://github.com/NodeSeekDev/NodeSupport)

[![DartNode](https://dartnode.com/branding/DN-Open-Source-sm.png)](https://dartnode.com "Powered by DartNode - Free VPS for Open Source")

### 🚀 CDN Acceleration Sponsors

<a href="https://edgeone.ai/zh?from=github" target="_blank">
  <img src="https://edgeone.ai/media/34fe3a45-492d-4ea4-ae5d-ea1087ca7b4b.png" alt="EdgeOne Logo" width="400"/>
</a>

**This project's CDN acceleration and security protection sponsored by [Tencent EdgeOne](https://edgeone.ai/zh?from=github)**

</div>

---

## 📊 Project Statistics

<div align="center">

### ⭐ Star History

[![Star History Chart](https://api.star-history.com/svg?repos=doubleDimple/oci-start&type=Date)](https://star-history.com/#doubleDimple/oci-start&Date)

</div>

---

## ⚖️ Disclaimer

<div align="center">

> ⚠️ **Important Notice: Please do not use if you have any objections**

</div>

### 📜 Disclaimer Terms

- 🔬 Any scripts involved in the projects released in this repository are **for testing and learning research only**, and commercial use is prohibited
- ⚖️ Cannot guarantee their legality, accuracy, completeness and effectiveness, please judge according to the situation
- 📋 All users need to comply with laws and regulations when using any part of the project. You are responsible for any consequences caused by improper use
- 🛡️ We are not responsible for any script issues, including but not limited to any loss or damage caused by any script errors
- 📄 If any unit or individual believes that the project may infringe their rights, they should notify promptly and provide identity proof and ownership proof, and we will delete relevant files after receiving the certification documents
- 👀 Anyone who views this project in any way or directly or indirectly uses any script of the project should read this statement carefully
- 🔄 I reserve the right to change or supplement this disclaimer at any time. Once you use and copy any related scripts or rules of this project, you are deemed to have accepted this disclaimer
- ⏰ You must completely delete the above content from your computer or phone within 24 hours after downloading

---

<div align="center">

**🎉 Thank you for using and supporting!**

Made with ❤️ by [doubleDimple](https://github.com/doubleDimple)

</div>
