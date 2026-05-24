<div align="center">

# OCI-Start

**A powerful system for creating and managing Oracle Cloud instances via API integration**

[![Stars](https://img.shields.io/github/stars/doubleDimple/oci-start?style=flat-square&logo=github&color=yellow)](https://github.com/doubleDimple/oci-start/stargazers)
[![License](https://img.shields.io/github/license/doubleDimple/oci-start?style=flat-square&color=blue)](LICENSE)
[![Issues](https://img.shields.io/github/issues/doubleDimple/oci-start?style=flat-square&color=orange)](https://github.com/doubleDimple/oci-start/issues)
[![Java](https://img.shields.io/badge/Java-8+-ED8B00?style=flat-square&logo=java&logoColor=white)](https://www.java.com)
[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED?style=flat-square&logo=docker&logoColor=white)](https://www.docker.com)

[简体中文](./README.md) · [Quick Start](#quick-start) · [Deployment](#deployment) · [Configuration](#configuration) · [Screenshots](#screenshots)

</div>

---

> ⚠️ **Important Notice**
> This project is fully open source. Please respect basic developer ethics — **do not** fork this repository to modify its functionality and trick others into deploying it for the purpose of stealing their account credentials. Do no harm, however small.

---

## Features

OCI-Start provides end-to-end lifecycle management for Oracle Cloud instances, covering creation, configuration, monitoring, and termination.

### Instance Management
- Concurrent boot across multiple APIs and instances
- Start / stop / sync / terminate operations
- Real-time traffic monitoring
- One-click rescue mode

### Network & Storage
- Create secondary VNICs with a single click
- Boot volume rename and VPU adjustment
- Toggle between IPv4 and IPv6
- Automatic IP quality detection and switching

### Account & Security
- Multi-tenant API management
- Region subscription and switching
- Visual security rule management
- Admin user lookup and creation

### System
- API private keys stored locally in H2 database — **never uploaded**
- Telegram bot used only for snatch notifications; no account data retained
- Clean web-based dashboard for all operations

---

## Quick Start

### Requirements

| Component | Version |
|-----------|---------|
| Java | 8 or higher |
| OS | Linux (Debian / Ubuntu recommended) |
| Docker | Optional, for containerized deployment |

Install JDK on Debian / Ubuntu:

```bash
sudo apt update
sudo apt install default-jdk
```

---

## Deployment

Two deployment methods are available — pick whichever suits your environment.

### Option 1: Script Installation (Recommended)

> The new version auto-detects and installs Redis. If you already run Redis on this host, review for conflicts before proceeding.

```bash
# Create working directory
mkdir -p oci-start && cd oci-start

# Download installer
wget -O oci-start.sh https://raw.githubusercontent.com/doubleDimple/shell-tools/master/oci-start.sh
chmod +x oci-start.sh

# Install
./oci-start.sh install
```

Common commands:

```bash
./oci-start.sh start       # Start
./oci-start.sh stop        # Stop
./oci-start.sh restart     # Restart
./oci-start.sh status      # Check status
./oci-start.sh update      # Upgrade
./oci-start.sh uninstall   # Uninstall
```

### Option 2: Docker

```bash
mkdir -p oci-start-docker && cd oci-start-docker

wget -O docker.sh https://raw.githubusercontent.com/doubleDimple/shell-tools/master/docker.sh
chmod +x docker.sh

./docker.sh install        # Install
./docker.sh uninstall      # Uninstall
```

Container operations:

```bash
docker ps -a               # Container status
docker logs oci-start      # View logs
docker logs -f oci-start   # Follow logs
```

Once deployed, open `http://your-ip:9856` in your browser and sign in with your configured credentials.

---

## Configuration

### Basic

The default port is `9856`. To change it:

```yaml
server:
  port: 9856
```

### Nginx Reverse Proxy

To expose the dashboard via a domain, Nginx must forward WebSocket traffic (used by the VNC console):

```nginx
location ~ ^/websockify/(\d+)$ {
    proxy_pass http://your-backend-ip:$1;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_read_timeout 86400;
}
```

> When upgrading from older versions, remove the `security` block entirely. All other configuration entries can be kept as-is.

---

## Screenshots

<div align="center">

### Dashboard
<img width="900" alt="Dashboard" src="https://github.com/user-attachments/assets/23b9ab72-6212-42c3-a02c-3efa795ca9ea" />

### Instance Management
<img width="900" alt="Instance Management" src="https://github.com/user-attachments/assets/af1ef632-84b9-4f08-a7d3-39480d518384" />

### System Configuration
<img width="900" alt="System Configuration" src="https://github.com/user-attachments/assets/306f307b-61b7-4e7c-b786-3d9e39471c91" />

<details>
<summary><b>More screenshots</b></summary>

<br>

<img width="900" alt="Advanced Settings" src="https://github.com/user-attachments/assets/15994398-0bc9-4bef-aa81-7b44c75021fb" />
<img width="900" alt="Feature Page" src="https://github.com/user-attachments/assets/bf98973a-d3f6-4f2a-836f-3698647b8f3f" />
<img width="900" alt="Monitoring" src="https://github.com/user-attachments/assets/3e8c0ce8-6077-4748-bc39-fc1fa70da08e" />
<img width="900" alt="Analytics" src="https://github.com/user-attachments/assets/0794298d-702f-4af7-ad5b-6cb5c206fa54" />

</details>

</div>

---

## Contributing

Issues and pull requests are welcome. Please read [CONTRIBUTING.md](./CONTRIBUTING.md) for development workflow, branch naming, and commit conventions before submitting.

<a href="https://github.com/doubleDimple/oci-start/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=doubleDimple/oci-start" />
</a>

---

## Sponsors

Special thanks to the following organizations for their ongoing support:

<table>
  <tr>
    <td align="center" width="33%">
      <a href="https://yxvm.com/aff.php?aff=762">
        <b>YxVM</b><br>
        <sub>Server resources</sub>
      </a>
    </td>
    <td align="center" width="33%">
      <a href="https://github.com/NodeSeekDev/NodeSupport">
        <b>NodeSeek</b><br>
        <sub>Community & infrastructure</sub>
      </a>
    </td>
    <td align="center" width="33%">
      <a href="https://dartnode.com">
        <b>DartNode</b><br>
        <sub>Free VPS for open source</sub>
      </a>
    </td>
  </tr>
  <tr>
    <td align="center" colspan="3">
      <a href="https://edgeone.ai/?from=github">
        <img src="https://edgeone.ai/media/34fe3a45-492d-4ea4-ae5d-ea1087ca7b4b.png" width="280" alt="Tencent EdgeOne"/>
      </a>
      <br>
      <sub>CDN acceleration and security provided by <b>Tencent EdgeOne</b></sub>
    </td>
  </tr>
</table>

---

## Donations

Thanks to everyone who has supported this project. The donation QR code is available in the **About** page inside the app. If you'd like your name added to the list below, reach out to the maintainer after donating.

<details>
<summary><b>Donation history (click to expand)</b></summary>

<br>

| Donor | Amount / Item | Date |
|:------|:--------------|:-----|
| 柯南 | GCP account | 2025-07-15 |
| Riva Milne | GCP account | 2025-07-15 |
| Ja3pez | ¥30 | 2025-07-15 |
| Anonymous | ¥50 | 2025-07-15 |
| Anonymous | ¥215 | 2025-07-14 |
| Anonymous | Cloud account | 2025-04-13 |
| Anonymous | Cloud account | 2025-04-13 |
| xdfaka | ¥68 | 2025-04-13 |
| Anonymous | Cloud account | 2025-04-07 |
| Anonymous | ¥50 | 2025-04-06 |
| Anonymous | ¥9.9 | 2025-04-01 |
| Anonymous | ¥10 | 2025-04-01 |
| Anonymous | Cloud account | 2025-03-25 |
| 柯南 | Cloud account | 2025-03-15 |
| Anonymous | Cloud account (upgrade) | 2025-03-08 |
| Anonymous | ¥9.9 | 2025-03-06 |
| 柯南 | ¥100 | 2025-03-01 |
| Anonymous | ¥200 | 2025-02-15 |
| Anonymous | ¥50 | 2024-11-05 |

</details>

---

## Star History

<div align="center">

[![Star History Chart](https://api.star-history.com/svg?repos=doubleDimple/oci-start&type=Date)](https://star-history.com/#doubleDimple/oci-start&Date)

</div>

---

## Disclaimer

- This project and all related scripts are intended **strictly for testing, learning, and research**. Commercial use is prohibited.
- No guarantee is made regarding the legality, accuracy, completeness, or effectiveness of any content. Use at your own discretion.
- Users must comply with the laws and regulations of their jurisdiction. All consequences arising from use are the sole responsibility of the user.
- The maintainer is **not liable** for any issues caused by the scripts, including but not limited to data loss or damage.
- If any party believes this project infringes on their rights, please provide proof of identity and ownership. Relevant content will be removed upon verification.
- Viewing this project, in any way, or using any of its scripts — directly or indirectly — constitutes acceptance of this disclaimer.
- The maintainer reserves the right to modify or supplement this disclaimer at any time.
- You must completely delete the contents within **24 hours** of downloading.

---

<div align="center">

**Made with care by [@doubleDimple](https://github.com/doubleDimple)**

If this project helps you, consider giving it a Star ⭐

</div>
