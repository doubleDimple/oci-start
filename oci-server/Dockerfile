# 使用轻量级的 JRE 运行环境
#FROM --platform=$TARGETPLATFORM eclipse-temurin:17-jre-jammy
FROM eclipse-temurin:17-jre-jammy

WORKDIR /oci-start

# 创建必要的目录
RUN mkdir -p /oci-start/data \
    && mkdir -p /oci-start/logs

# 设置环境变量
ENV SERVER_PORT=9856
ENV DATA_PATH=/oci-start/data
ENV LOG_HOME=/oci-start/logs

# 直接复制本地已构建好的 jar
COPY target/oci-start-release.jar oci-start.jar

# JVM 配置 - 仅使用 G1 垃圾收集器
ENV JAVA_OPTS="-XX:+UseG1GC -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/oci-start/logs"

# 暴露端口（使用环境变量）
EXPOSE ${SERVER_PORT}

# 设置挂载卷
VOLUME ["/oci-start/data", "/oci-start/logs"]

# 启动命令
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS \
    -DSERVER_PORT=$SERVER_PORT \
    -DDATA_PATH=$DATA_PATH \
    -DLOG_HOME=$LOG_HOME \
    -jar oci-start.jar"]