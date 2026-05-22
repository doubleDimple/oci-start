#!/bin/bash

# ================= 动态配置区域 =================
# 这些变量将由 Java 后端动态替换
SERVER_URL="{{SERVER_URL}}"
TOKEN="{{TOKEN}}"
INTERVAL={{INTERVAL}}
DEBUG=false
# ===========================================

# 获取主网卡名称 (自动识别流量最大的网卡或默认路由网卡)
MAIN_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if [ -z "$MAIN_INTERFACE" ]; then
    MAIN_INTERFACE=$(cat /proc/net/dev | grep -v lo | head -n 2 | tail -n 1 | awk -F: '{print $1}' | sed 's/ //g')
fi

# 初始化变量 (用于计算速率)
PREV_CPU_TOTAL=0
PREV_CPU_IDLE=0
PREV_RX_BYTES=0
PREV_TX_BYTES=0

# 定义主逻辑函数
run_monitor() {
    echo "🔍 监控 Agent 已启动..."
    echo "📡 监听网卡: $MAIN_INTERFACE"
    echo "⏱ 上报间隔: ${INTERVAL}s"
    echo "🚀 上报地址: $SERVER_URL"
    echo "---------------------------------------------"

    while true; do
        # 1. === 系统信息 ===
        HOSTNAME=$(hostname)
        # 获取操作系统名称
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS_NAME=$PRETTY_NAME
        else
            OS_NAME=$(uname -s)
        fi
        KERNEL=$(uname -r)
        UPTIME=$(awk '{print int($1)}' /proc/uptime)

        # 2. === CPU 使用率计算 ===
        CPU_INFO=$(grep '^cpu ' /proc/stat)
        CPU_USER=$(echo $CPU_INFO | awk '{print $2}')
        CPU_NICE=$(echo $CPU_INFO | awk '{print $3}')
        CPU_SYS=$(echo $CPU_INFO | awk '{print $4}')
        CPU_IDLE=$(echo $CPU_INFO | awk '{print $5}')
        CPU_IOWAIT=$(echo $CPU_INFO | awk '{print $6}')
        CPU_IRQ=$(echo $CPU_INFO | awk '{print $7}')
        CPU_SOFTIRQ=$(echo $CPU_INFO | awk '{print $8}')

        CPU_TOTAL=$((CPU_USER + CPU_NICE + CPU_SYS + CPU_IDLE + CPU_IOWAIT + CPU_IRQ + CPU_SOFTIRQ))

        DIFF_TOTAL=$((CPU_TOTAL - PREV_CPU_TOTAL))
        DIFF_IDLE=$((CPU_IDLE - PREV_CPU_IDLE))

        if [ $DIFF_TOTAL -eq 0 ]; then
            CPU_USAGE=0
        else
            CPU_USAGE=$(awk -v total=$DIFF_TOTAL -v idle=$DIFF_IDLE 'BEGIN {printf "%.1f", (1 - idle/total)*100}')
        fi

        PREV_CPU_TOTAL=$CPU_TOTAL
        PREV_CPU_IDLE=$CPU_IDLE

        CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
        CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -n 1 | awk -F': ' '{print $2}')
        LOAD_AVG=$(awk '{print $1", "$2", "$3}' /proc/loadavg)

        # 3. === 内存信息 ===
        MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{printf "%d", $2/1024}')
        MEM_AVAIL=$(grep MemAvailable /proc/meminfo | awk '{printf "%d", $2/1024}')
        MEM_USED=$((MEM_TOTAL - MEM_AVAIL))
        SWAP_TOTAL=$(grep SwapTotal /proc/meminfo | awk '{printf "%d", $2/1024}')
        SWAP_FREE=$(grep SwapFree /proc/meminfo | awk '{printf "%d", $2/1024}')
        SWAP_USED=$((SWAP_TOTAL - SWAP_FREE))

        # 4. === 硬盘信息 ===
        DISK_INFO=$(df -m / | tail -n 1)
        DISK_TOTAL=$(echo $DISK_INFO | awk '{print $2}')
        DISK_USED=$(echo $DISK_INFO | awk '{print $3}')

        # 5. === 网络流量计算 ===
        NET_INFO=$(grep "$MAIN_INTERFACE:" /proc/net/dev)
        RX_BYTES=$(echo $NET_INFO | awk '{print $2}')
        TX_BYTES=$(echo $NET_INFO | awk '{print $10}')

        if [ $PREV_RX_BYTES -eq 0 ]; then
            RX_RATE=0
            TX_RATE=0
        else
            RX_RATE=$((RX_BYTES - PREV_RX_BYTES))
            TX_RATE=$((TX_BYTES - PREV_TX_BYTES))
            if [ $RX_RATE -lt 0 ]; then RX_RATE=0; fi
            if [ $TX_RATE -lt 0 ]; then TX_RATE=0; fi
        fi

        PREV_RX_BYTES=$RX_BYTES
        PREV_TX_BYTES=$TX_BYTES

        # 6. === 组装 JSON ===
        JSON_DATA=$(cat <<EOF
{
  "token": "$TOKEN",
  "host": {
    "name": "$HOSTNAME",
    "os": "$OS_NAME",
    "kernel": "$KERNEL",
    "uptime": $UPTIME
  },
  "cpu": {
    "cores": $CPU_CORES,
    "usage": $CPU_USAGE,
    "model": "$CPU_MODEL",
    "load": [$LOAD_AVG]
  },
  "memory": {
    "total": $MEM_TOTAL,
    "used": $MEM_USED,
    "swap_used": $SWAP_USED
  },
  "disk": {
    "total": $DISK_TOTAL,
    "used": $DISK_USED
  },
  "network": {
    "interface": "$MAIN_INTERFACE",
    "rx_rate": $RX_RATE,
    "tx_rate": $TX_RATE,
    "rx_total": $RX_BYTES,
    "tx_total": $TX_BYTES
  }
}
EOF
)

        # 7. === 发送 ===
        if [ "$DEBUG" = true ]; then
            echo "$JSON_DATA"
        else
            # -k 允许不安全HTTPS, -s 静默模式, --connect-timeout 设置超时
            curl -k -H "Content-Type: application/json" -X POST -d "$JSON_DATA" --connect-timeout 5 -m 5 -s "$SERVER_URL" > /dev/null
        fi

        sleep $INTERVAL
    done
}

# --- 自动安装 Systemd 服务 (实现开机自启) ---
if [ "$1" == "install" ]; then
    echo "🔧 开始安装监控探针..."

    # 1. 移动脚本
    cp "$0" /usr/local/bin/vps-agent.sh
    chmod +x /usr/local/bin/vps-agent.sh

    # 2. 写入 Systemd 服务文件
    cat > /etc/systemd/system/vps-agent.service <<EOF
[Unit]
Description=VPS Monitor Agent
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/vps-agent.sh
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    # 3. 启动服务
    systemctl daemon-reload
    systemctl enable vps-agent
    systemctl restart vps-agent

    echo "✅ 安装成功！监控服务已启动。"
    exit 0
fi

# 卸载逻辑
if [ "$1" == "uninstall" ]; then
    echo "🗑️ 正在卸载监控探针..."
    systemctl stop vps-agent
    systemctl disable vps-agent
    rm -f /etc/systemd/system/vps-agent.service
    rm -f /usr/local/bin/vps-agent.sh
    systemctl daemon-reload
    echo "✅ 卸载完成。"
    exit 0
fi

# 如果没有任何参数，直接运行（用于前台调试或Systemd调用）
run_monitor