<div align="center">

# OCI-Start

**基于 API 集成的 Oracle Cloud 实例创建与管理系统**

[![Stars](https://img.shields.io/github/stars/doubleDimple/oci-start?style=flat-square&logo=github&color=yellow)](https://github.com/doubleDimple/oci-start/stargazers)
[![License](https://img.shields.io/github/license/doubleDimple/oci-start?style=flat-square&color=blue)](LICENSE)
[![Issues](https://img.shields.io/github/issues/doubleDimple/oci-start?style=flat-square&color=orange)](https://github.com/doubleDimple/oci-start/issues)
[![Java](https://img.shields.io/badge/Java-8+-ED8B00?style=flat-square&logo=java&logoColor=white)](https://www.java.com)
[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED?style=flat-square&logo=docker&logoColor=white)](https://www.docker.com)

[English](./README.en.md) · [快速开始](#快速开始) · [部署](#部署) · [配置](#配置) · [截图](#截图)

</div>

---

> ⚠️ **使用须知**
> 本项目完全开源,请各位开发者遵守基本操守。**严禁** 修改功能后引导他人部署以盗取账号信息。勿以恶小而为之,勿以善小而不为。

---

## 功能特性

OCI-Start 提供完整的 Oracle Cloud 实例生命周期管理能力,涵盖创建、配置、监控到回收的全流程。

### 实例管理
- 多 API 多实例并发开机
- 实例启动 / 停止 / 同步 / 终止
- 实例流量实时监控
- 系统救援模式一键触发

### 网络与存储
- 一键创建附属 VNIC
- 引导卷名称及 VPU 修改
- IPv4 / IPv6 一键切换
- IP 质量自动检测与切换

### 账户与安全
- 多租户 API 管理
- 区域订阅与切换
- 安全规则可视化管理
- Admin 用户查询与添加

### 系统特性
- 私钥本地 H2 数据库存储,**不上传任何远端**
- Telegram 机器人仅推送抢机通知,不留存账号数据
- Web 可视化面板,直观操作

---

## 快速开始

### 环境要求

| 组件 | 版本 |
|------|------|
| Java | 8 或更高 |
| 系统 | Linux (推荐 Debian / Ubuntu) |
| Docker | 可选,用于容器化部署 |

Debian / Ubuntu 安装 JDK:

```bash
sudo apt update
sudo apt install default-jdk
```

---

## 部署

提供两种部署方式,任选其一。

### 方式一:脚本部署(推荐)

> 新版本会自动检测并安装 Redis,如本机已部署 Redis 请先评估冲突。

```bash
# 创建工作目录
mkdir -p oci-start && cd oci-start

# 下载安装脚本
wget -O oci-start.sh https://raw.githubusercontent.com/doubleDimple/shell-tools/master/oci-start.sh
chmod +x oci-start.sh

# 一键安装
./oci-start.sh install
```

常用命令:

```bash
./oci-start.sh start       # 启动
./oci-start.sh stop        # 停止
./oci-start.sh restart     # 重启
./oci-start.sh status      # 查看状态
./oci-start.sh update      # 升级
./oci-start.sh uninstall   # 卸载
```

### 方式二:Docker 部署

```bash
mkdir -p oci-start-docker && cd oci-start-docker

wget -O docker.sh https://raw.githubusercontent.com/doubleDimple/shell-tools/master/docker.sh
chmod +x docker.sh

./docker.sh install        # 安装
./docker.sh uninstall      # 卸载
```

容器运维:

```bash
docker ps -a               # 查看容器状态
docker logs oci-start      # 查看日志
docker logs -f oci-start   # 实时跟踪日志
```

部署完成后,浏览器访问 `http://your-ip:9856`,使用配置的用户名密码登录即可。

---

## 配置

### 基础配置

默认端口为 `9856`,如需修改:

```yaml
server:
  port: 9856
```

### Nginx 反向代理

如需通过域名访问,Nginx 需配置 WebSocket 转发(用于 VNC 控制台):

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

> 旧版本升级时,除 `security` 配置需完全删除外,其他配置项保持不变即可。

---

## 截图

<div align="center">

### 主控面板
<img width="900" alt="主界面" src="https://github.com/user-attachments/assets/23b9ab72-6212-42c3-a02c-3efa795ca9ea" />

### 实例管理
<img width="900" alt="实例管理" src="https://github.com/user-attachments/assets/af1ef632-84b9-4f08-a7d3-39480d518384" />

### 系统配置
<img width="900" alt="系统配置" src="https://github.com/user-attachments/assets/306f307b-61b7-4e7c-b786-3d9e39471c91" />

<details>
<summary><b>查看更多截图</b></summary>

<br>

<img width="900" alt="高级设置" src="https://github.com/user-attachments/assets/15994398-0bc9-4bef-aa81-7b44c75021fb" />
<img width="900" alt="功能页面" src="https://github.com/user-attachments/assets/bf98973a-d3f6-4f2a-836f-3698647b8f3f" />
<img width="900" alt="监控界面" src="https://github.com/user-attachments/assets/3e8c0ce8-6077-4748-bc39-fc1fa70da08e" />
<img width="900" alt="数据统计" src="https://github.com/user-attachments/assets/0794298d-702f-4af7-ad5b-6cb5c206fa54" />

</details>

</div>

---

## 贡献

欢迎提交 Issue 与 Pull Request。提交前请阅读 [CONTRIBUTING.md](./CONTRIBUTING.md) 了解开发流程、分支规范与 Commit 约定。

<a href="https://github.com/doubleDimple/oci-start/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=doubleDimple/oci-start" />
</a>

---

## 赞助商

感谢以下机构对本项目的持续支持:

<table>
  <tr>
    <td align="center" width="33%">
      <a href="https://yxvm.com/aff.php?aff=762">
        <b>YxVM</b><br>
        <sub>服务器资源</sub>
      </a>
    </td>
    <td align="center" width="33%">
      <a href="https://github.com/NodeSeekDev/NodeSupport">
        <b>NodeSeek</b><br>
        <sub>社区论坛</sub>
      </a>
    </td>
    <td align="center" width="33%">
      <a href="https://dartnode.com">
        <b>DartNode</b><br>
        <sub>VPS提供商</sub>
      </a>
    </td>
    <td align="center" width="33%">
      <a href="https://sponsorship.forztn.com/github/doubleDimple/oci-start ">
        <b>DartNode</b><br>
        <sub>感谢赞助商 - ForZTN</sub>
      </a>
    </td>
  </tr>
  <tr>
    <td align="center" colspan="3">
      <a href="https://edgeone.ai/zh?from=github">
        <img src="https://edgeone.ai/media/34fe3a45-492d-4ea4-ae5d-ea1087ca7b4b.png" width="280" alt="Tencent EdgeOne"/>
      </a>
      <br>
      <sub>CDN 加速与安全防护由 <b>Tencent EdgeOne</b> 提供</sub>
    </td>
  </tr>
</table>

---

## 捐赠

感谢每一位支持本项目的捐赠者。捐赠二维码可在程序"关于"页面查看,捐赠后如需上榜请联系维护者。

<details>
<summary><b>捐赠记录(展开查看)</b></summary>

<br>

| 捐赠者 | 金额 / 物品 | 日期 |
|:------|:-----------|:-----|
| 柯南 | GCP 账号 | 2025-07-15 |
| Riva Milne | GCP 账号 | 2025-07-15 |
| Ja3pez | ¥30 | 2025-07-15 |
| 匿名用户 | ¥50 | 2025-07-15 |
| 匿名用户 | ¥215 | 2025-07-14 |
| 匿名用户 | 云账号 | 2025-04-13 |
| 匿名用户 | 云账号 | 2025-04-13 |
| xdfaka | ¥68 | 2025-04-13 |
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

---

## Star 趋势

<div align="center">

[![Star History Chart](https://api.star-history.com/svg?repos=doubleDimple/oci-start&type=Date)](https://star-history.com/#doubleDimple/oci-start&Date)

</div>

---

## 免责声明

- 本项目及相关脚本**仅用于测试、学习与研究**,严禁用于商业用途。
- 不保证内容的合法性、准确性、完整性与有效性,使用前请自行判断。
- 使用者需先遵守所在地区法律法规,一切使用后果由使用者自行承担。
- 维护者对脚本可能引发的任何问题(包括但不限于数据损失)**概不负责**。
- 如任何单位或个人认为本项目侵犯其权利,请提供身份与权属证明,核实后将及时删除相关内容。
- 任何方式查看本项目或使用相关脚本的行为,均视为已仔细阅读并接受本声明。
- 维护者保留随时变更或补充本声明的权利。
- 下载后请于 **24 小时内** 完全删除相关内容。

---

<div align="center">

**Made with care by [@doubleDimple](https://github.com/doubleDimple)**

如果这个项目对你有帮助,欢迎点一个 Star ⭐

</div>
