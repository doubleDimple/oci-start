声明
本系统的机器人只用来执行抢机信息的发送,不存储任何数据。

API私钥在你部署的服务器上的h2数据库里，你可以随时关闭服务。

介意请千万勿使用，谢谢。

以下为 【免责条款】

本仓库发布的项目中涉及的任何脚本，仅用于测试和学习研究，禁止用于商业用途，不能保证其合法性，准确性，完整性和有效性，请根据情况自行判断.

所有使用者在使用项目的任何部分时，需先遵守法律法规。对于一切使用不当所造成的后果，需自行承担。对任何脚本问题概不负责，包括但不限于由任何脚本错误导致的任何损失或损害.

如果任何单位或个人认为该项目可能涉嫌侵犯其权利，则应及时通知并提供身份证明，所有权证明，我们将在收到认证文件后删除相关文件.

任何以任何方式查看此项目的人或直接或间接使用该项目的任何脚本的使用者都应仔细阅读此声明。本人保留随时更改或补充此免责声明的权利。一旦使用并复制了任何相关脚本或本项目的规则，则视为您已接受此免责声明.

您必须在下载后的24小时内从计算机或手机中完全删除以上内容.

您使用或者复制了本仓库且本人制作的任何脚本，则视为已接受此声明，请仔细阅读

一:说明:

    1.1主要功能:

        1.1.1
        使用api完成实例创建的程序,此程序支持多租户创建实例.
        
        1.1.2 
        使用面板执行多个api的创建,以及api数据查询
        

二:环境说明: 需要提前安装jdk8+版本

    2.1: Debian/Ubuntu
    
        sudo apt update
        sudo apt install default-jdk
        
    2.2: CentOS/RHEL (Red Hat Enterprise Linux)

        CentOS 7:
            sudo yum install java-1.8.0-openjdk-devel
            
        CentOS 8 及之后版本（使用 dnf）：
            sudo dnf install java-11-openjdk-devel

    

三:部署说明:
   一: 脚本部署

      3.1:登录linux服务器,切换到root用户下.
  
      3.2:创建文件夹 mkdir -p oci-start && cd oci-start
  
      3.3:下载部署包文件
  
        3.3.1:下载jar包
    
          wget https://github.com/doubleDimple/oci-start/releases/download/v-2.0.2/oci-start-release.jar
      
        3.3.2:下载运行脚本
    
          wget -N --no-check-certificate "https://github.com/doubleDimple/oci-start/releases/download/v-2.0.1/oci-start.sh" && chmod +x oci-start.sh
      
        3.3.3:下载配置文件模板
    
          wget https://github.com/doubleDimple/oci-start/releases/download/v-2.0.1/oci-start.yml
          
        3.3.4:下载探针脚本
    
          wget -N --no-check-certificate "https://github.com/doubleDimple/oci-start/releases/download/v-1.0.7/monitor.sh" && chmod +x monitor.sh
    二: docker部署

            # 0. 创建文件件
            mkdir oci-start-docker

            # 1. 进入指定目录
            cd oci-start-docker

            # 2. 创建数据和日志目录
            mkdir -p data logs

            # 3. 运行容器，使用绝对路径挂载
            docker stop oci-start || true && docker run -d \
                --pull always \
                --name oci-start \
                -p 9856:9856 \
                -v /root/oci-start-docker/data:/oci-start/data \
                -v /root/oci-start-docker/logs:/oci-start/logs \
                -e SERVER_PORT=9856 \
                -e DATA_PATH=/oci-start/data \
                -e LOG_HOME=/oci-start/logs \
                --rm \
                lovele/oci-start:latest

            # 查看容器状态
            docker ps -a

            # 查看容器日志
            docker logs oci-start

四:配置说明(对于已经部署之前的版本的,除了security配置完全删除外,其他配置可以暂时不要动,否则会导致找不到文件路径导致api失败):

    #端口自行指定(默认端口为9856如果不想改默认端口,不需要下载oci-start.yml)
    server:
      port: 9856

 
  


五:启动

  5.1:给oci-start.sh 执行权限添加
    chmod 777 oci-start.sh

  5.2:启动程序
    ./oci-start.sh start

  5.3:查看程序启动状态
    ./oci-start.sh status

  5.4:停止程序
    ./oci-start.sh stop

六:访问
    http://ip:port  访问应用,输入配置的用户名密码
    ![image](https://github.com/user-attachments/assets/84ca9ac9-d019-4f96-984c-892546441a61)





七:文件位置说明

    本系统默认的脚本根路径为/root/oci-start,如果想自己修改文件路径,请修改配置文件,脚本相关的路径即可

八:探针使用说明

    1:增加探针功能,下载monitor.sh脚本,执行chmod +x monitor.sh

    2:执行 ./monitor.sh start
    
    3:参数说明
        
        serverId (自定义的vps名称) 
        
        url http://ip:port/api/metrics/reportMetrics (ip:port替换成你实际部署oci-start的真实ip端口即可)


九: Star History

[![Star History Chart](https://api.star-history.com/svg?repos=doubleDimple/oci-start&type=Date)](https://star-history.com/#doubleDimple/oci-start&Date)
 
 
 
 
 

