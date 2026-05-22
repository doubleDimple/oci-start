# https://app.docker.com/
# 使用 Maven 打包项目
mvn clean package -Dmaven.test.skip=true


# <=========部署使用==========>
# 拉取镜像
docker pull lovele/oci-start:2.0.1

# 使用步骤

# 0. 创建文件件
mkdir oci-start-docker

# 1. 进入指定目录
cd oci-start-docker

# 2. 创建数据和日志目录
mkdir -p data logs

# 拉取最新镜像 停止旧容器（如果存在）删除旧容器（如果存在）用最新镜像启动新容器
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

# 查看所有镜像
docker images

# 查看所有正在运行的容器:
docker ps

# 查看所有容器(包括已停止的):
docker ps -a

# 停止指定容器:
docker stop 容器ID或容器名称

# 删除指定容器:
docker rm 容器ID或容器名称

# 删除指定镜像:
docker rmi 镜像ID或镜像名:标签

# 停止所有运行中的容器:
docker stop $(docker ps -q)

# 删除所有容器:
docker rm $(docker ps -a -q)

# 删除所有镜像:
docker rmi $(docker images -q)


