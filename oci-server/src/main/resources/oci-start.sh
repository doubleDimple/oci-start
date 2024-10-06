#!/bin/bash

JAR_PATH="/root/oci-start/oci-start-release.jar"
CONFIG_FILE="/root/oci-start/oci-start.properties"
LOG_FILE="/dev/null"
PID_FILE="oci-start.pid"

# 检查JAR包是否存在
if [ ! -f "$JAR_PATH" ]; then
  echo "Error: JAR file not found at $JAR_PATH"
  exit 1
fi

start() {
  # 检查JAR包是否已经在运行
  if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p $PID > /dev/null; then
      echo "Application is already running with PID: $PID"
      exit 0
    fi
  fi

  # 启动JAR包，指定外部配置文件，并将输出重定向到日志文件
  nohup java -jar "$JAR_PATH" --spring.config.location="file:$CONFIG_FILE" > "$LOG_FILE" 2>&1 &

  # 获取PID并输出
  PID=$!
  echo "Application started with PID: $PID"

  # 将PID保存到文件，方便管理（停止服务时使用）
  echo $PID > "$PID_FILE"
}

stop() {
  # 检查PID文件是否存在
  if [ ! -f "$PID_FILE" ]; then
    echo "PID file not found. Is the application running?"
    exit 1
  fi

  # 读取PID并停止进程
  PID=$(cat "$PID_FILE")
  if ps -p $PID > /dev/null; then
    echo "Stopping application with PID: $PID"
    kill $PID
    sleep 2
    if ps -p $PID > /dev/null; then
      echo "Application did not stop gracefully, forcing shutdown"
      kill -9 $PID
    fi
    echo "Application stopped."
    rm "$PID_FILE"
  else
    echo "No process found with PID: $PID"
    rm "$PID_FILE"
  fi
}

restart() {
  stop
  start
}

status() {
  if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p $PID > /dev/null; then
      echo "Application is running with PID: $PID"
    else
      echo "PID file found but no process is running with PID: $PID"
    fi
  else
    echo "Application is not running."
  fi
}

case "$1" in
  start)
    start
    ;;
  stop)
    stop
    ;;
  restart)
    restart
    ;;
  status)
    status
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac