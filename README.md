1:说明:

    1.1主要功能:使用api完成实例创建的程序,此程序支持多租户创建实例.
  
    1.2此程序免费开源,仅可用于测试和学习,不可用于其他所有商业或者非法用途.

2:环境说明: 需要提前安装jdk8+版本

3:部署说明:
  3.1:登录linux服务器,切换到root用户下.
  
  3.2:创建文件夹 mkdir -p oci-start && cd oci-start
  
  3.3:下载部署包文件
  
    3.3.1:下载jar包
    
      wget https://github.com/doubleDimple/oci-start/releases/download/v-1.0.0/oci-start-release.jar
      
    3.3.2:下载运行脚本
    
      wget https://github.com/doubleDimple/oci-start/releases/download/v-1.0.0/oci-start.sh
      
    3.3.3:下载配置文件模板
    
      wget https://github.com/doubleDimple/oci-start/releases/download/v-1.0.0/oci-start.properties

4:配置说明:oci-start.properties文件里面的配置需要自行去修改,如果需要配置多个api进行通时创建实例,直接将  ###oracle抢机配置下的内容复制一份,将里面的user1全部修改为user2即可
  以此类推,配置多个api
 
  ###基本配置
  
    server.port=23125(端口号,请自行指定)
  
    telegram.token=(tg的token,用户实例创建提醒,目前必须配置)
  
    telegram.chatId=(tg的chatid,用户实例创建提醒,目前必须配置)
  
  ###oracle抢机配置
    oracle.users.user1.userId=oracle租户名
  
    oracle.users.user1.userName=当前自定义的名称,当配置多个租户的api的时候不可重复
  
    oracle.users.user1.fingerprint=oracle的fingerprint
  
    oracle.users.user1.tenancy=oracle的tenancy
  
    oracle.users.user1.region=oracle的region
  
    oracle.users.user1.keyFile=oracle的keyFile,上传后的真实路径
  
    oracle.users.user1.ocpus=1(cpu大小)
  
    oracle.users.user1.memory=1(内存大小)
  
    oracle.users.user1.disk=50(磁盘大小)
  
    oracle.users.user1.architecture=AMD(oracle的架构类型,ARM或者AMD)
  
    oracle.users.user1.operationSystem=Ubuntu(系统类型,目前只支持Ubuntu)
  
    oracle.users.user1.interval=50(创建实例循环时间,单位为秒)
  
    oracle.users.user1.rootPassword=实例的root用户密码
  
    spring.application.name=oci-server

5:启动

  5.1:给oci-start.sh 执行权限添加
    chmod 777 oci-start.sh

  5.2:启动程序
    ./oci-start.sh start

  5.3:查看程序启动状态
    ./oci-start.sh status

  5.4:停止程序
    ./oci-start.sh stop
  
    

 
 
 
 
 

