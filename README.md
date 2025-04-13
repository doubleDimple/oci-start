# OCI-Start

一个使用API集成创建和管理Oracle云基础设施实例的系统。
目前支持的功能
功能一:支持多个api多实例开机
功能二:同步租户下的已开实例
功能三:引导卷管理(执行名称修改,引导卷vpu修改)
功能四:安全规则管理
功能五:登录用户管理(查询,添加admin用户)
功能六:ipv4切换一键开启ipv6
功能七:终止实例
功能八:实例流量查询
功能九:ip质量检测,并自动切换ip

## 声明

本系统的机器人只用来执行抢机信息的发送，不存储任何数据。API私钥在你部署的服务器上的H2数据库里，你可以随时关闭服务。

**重要提示：如有介意请勿使用。**

### 免责条款

- 本仓库发布的项目中涉及的任何脚本，仅用于测试和学习研究，禁止用于商业用途。
- 不能保证其合法性，准确性，完整性和有效性，请根据情况自行判断。
- 所有使用者在使用项目的任何部分时，需先遵守法律法规。对于一切使用不当所造成的后果，需自行承担。
- 对任何脚本问题概不负责，包括但不限于由任何脚本错误导致的任何损失或损害。
- 如果任何单位或个人认为该项目可能涉嫌侵犯其权利，则应及时通知并提供身份证明，所有权证明，我们将在收到认证文件后删除相关文件。
- 任何以任何方式查看此项目的人或直接或间接使用该项目的任何脚本的使用者都应仔细阅读此声明。
- 本人保留随时更改或补充此免责声明的权利。一旦使用并复制了任何相关脚本或本项目的规则，则视为您已接受此免责声明。
- 您必须在下载后的24小时内从计算机或手机中完全删除以上内容。

## 功能特点

1. **主要功能**：
   - 使用API完成实例创建的程序，此程序支持多租户创建实例
   - 使用面板执行多个API的创建，以及API数据查询

## 环境要求

需要提前安装JDK 8+版本

### Debian/Ubuntu
```bash
sudo apt update
sudo apt install default-jdk
```

### CentOS/RHEL
```bash
# CentOS 7
sudo yum install java-1.8.0-openjdk-devel

# CentOS 8及之后版本（使用dnf）
sudo dnf install java-11-openjdk-devel
```

## 部署方法

### 方法一：脚本部署
*注意：新版本会检测安装Redis，之前安装了Redis的会有影响*

```bash
# 1. 切换到root用户下并创建文件夹
mkdir -p oci-start && cd oci-start

# 2. 下载执行脚本
wget -O oci-start.sh https://raw.githubusercontent.com/doubleDimple/shell-tools/master/oci-start.sh && chmod +x oci-start.sh

# 3. 直接运行脚本，即可自动安装部署

# 启动应用程序
./oci-start.sh start

# 停止应用程序
./oci-start.sh stop

# 重启应用程序
./oci-start.sh restart    

# 更新到最新版本
./oci-start.sh update

# 完全卸载应用
./oci-start.sh uninstall
```

### 方法二：Docker部署
```bash
mkdir -p oci-start-docker && cd oci-start-docker

# 1. 下载执行脚本
wget -O docker.sh https://raw.githubusercontent.com/doubleDimple/shell-tools/master/docker.sh && chmod +x docker.sh

# 2. 执行脚本
# 安装应用
./docker.sh install

# 卸载应用
./docker.sh uninstall
```

# 查看容器状态
docker ps -a

# 查看容器日志
docker logs oci-start
```

## 配置说明

对于已经部署之前版本的用户，除了security配置完全删除外，其他配置可以暂时不要动，否则会导致找不到文件路径导致API失败。

```yaml
# 端口自行指定（默认端口为9856，如果不想改默认端口，不需要下载oci-start.yml）
server:
  port: 9856
```

## 操作命令

```bash
# 给oci-start.sh执行权限添加
chmod 777 oci-start.sh

# 启动程序
./oci-start.sh start

# 查看程序启动状态
./oci-start.sh status

# 停止程序
./oci-start.sh stop
```

## 访问

通过 `http://ip:port` 访问应用，输入配置的用户名密码。


## Star历史

[![Star History Chart](https://api.star-history.com/svg?repos=doubleDimple/oci-start&type=Date)](https://star-history.com/#doubleDimple/oci-start&Date)

## 程序演示图片

<img width="1423" alt="2" src="https://github.com/user-attachments/assets/23b9ab72-6212-42c3-a02c-3efa795ca9ea" />

<img width="1420" alt="3" src="https://github.com/user-attachments/assets/af1ef632-84b9-4f08-a7d3-39480d518384" />

<img width="1211" alt="4" src="https://github.com/user-attachments/assets/306f307b-61b7-4e7c-b786-3d9e39471c91" />

<img width="1432" alt="5" src="https://github.com/user-attachments/assets/15994398-0bc9-4bef-aa81-7b44c75021fb" />

<img width="1420" alt="6" src="https://github.com/user-attachments/assets/bf98973a-d3f6-4f2a-836f-3698647b8f3f" />

<img width="1427" alt="7" src="https://github.com/user-attachments/assets/3e8c0ce8-6077-4748-bc39-fc1fa70da08e" />

<img width="1430" alt="8" src="https://github.com/user-attachments/assets/0794298d-702f-4af7-ad5b-6cb5c206fa54" />

<img width="1230" alt="9" src="https://github.com/user-attachments/assets/e40bded6-31d1-4ecc-9e31-0329f185ad3c" />

<img width="1415" alt="10" src="https://github.com/user-attachments/assets/7fa23938-d6b8-4ebf-9445-8a450446c8ea" />

<img width="1264" alt="11" src="https://github.com/user-attachments/assets/72a5c4da-35c6-4be2-a60c-5989aefb74af" />

# 感谢捐赠者

非常感谢所有支持本项目的捐赠者！您的慷慨支持对我们至关重要。

## 捐赠记录

| 序号 | 姓名 | 捐赠明细 | 日期 |
|:----:|:----:|:--------:|:----:|
| 14 | 匿名用户 | 云账号 | 2025-04-13 |
| 13 | 匿名用户 | 云账号 | 2025-04-13 |
| 12 | xdfaka | ¥68 | 2025-04-13 |
| 11 | 匿名用户 | 云账号 | 2025-04-07 |
| 10 | 匿名用户 | ¥50 | 2025-04-06 |
| 9 | 匿名用户 | ¥9.9 | 2025-04-01 |
| 8 | 匿名用户 | ¥10 | 2025-04-01 |
| 7 | 匿名用户 | 云账号 | 2025-03-25 |
| 6 | 柯南 | 云账号 | 2025-03-15 |
| 5 | 匿名用户 | 云账号(升级) | 2025-03-08 |
| 4 | 匿名用户 | ¥9.9 | 2025-03-06 |
| 3 | 柯南 | ¥100 | 2025-03-01 |
| 2 | 匿名用户 | ¥200 | 2025-02-15 |
| 1 | 匿名用户 | ¥50 | 2024-11-05 |

## 如何捐赠

如果您想支持我们的项目，可以通过oci-start的关于捐赠二维码

再次感谢您的支持！

*如需将您的名字添加到捐赠者名单中，请在捐赠后联系项目维护者。*

## 赞助
赞助说明
本项目大力感谢YxVM提供的服务器资源，也感谢NodeSeek论坛和社区的大力支持

YxVM服务器：https://yxvm.com/aff.php?aff=762

NodeSeek交流论坛提供的NodeSupport项目：https://github.com/NodeSeekDev/NodeSupport 赞助了本项目

