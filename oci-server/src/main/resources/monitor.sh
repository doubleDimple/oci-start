#!/bin/bash

#################################
# 赋予执行权限
# chmod +x monitor.sh
# 启动服务
#./monitor.sh start

# 停止服务
#./monitor.sh stop

# 重启服务
#./monitor.sh restart

# 查看状态
#./monitor.sh status

# 直接运行（前台）
#./monitor.sh run

#查看日志
#tail -f logs/monitor.log
#################################

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 日志相关配置
LOG_DIR="logs"
LOG_FILE="$LOG_DIR/monitor.log"
LOG_DAYS=1

# 添加流量统计文件定义
TRAFFIC_STATS_FILE="traffic_stats.txt"

# 添加月度流量统计文件定义
MONTHLY_TRAFFIC_FILE="monthly_traffic_stats.txt"
CURRENT_MONTH_FILE="current_month.txt"

# 创建日志目录
mkdir -p $LOG_DIR

# 检测操作系统类型
detect_os() {
    case "$(uname -s)" in
        Darwin*)
            echo "MAC"
            ;;
        Linux*)
            echo "LINUX"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "WINDOWS"
            ;;
        *)
            echo "UNKNOWN"
            ;;
    esac
}

OS_TYPE=$(detect_os)

# 打印带颜色的信息
print_info() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[INFO]${NC} $timestamp $1" | tee -a "$LOG_FILE"
}

print_success() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[SUCCESS]${NC} $timestamp $1" | tee -a "$LOG_FILE"
}

print_error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[ERROR]${NC} $timestamp $1" | tee -a "$LOG_FILE"
}

# 清理旧日志文件
cleanup_logs() {
    find "$LOG_DIR" -name "monitor.log.*" -type f -mtime +$LOG_DAYS -delete
}

# 日志滚动
rotate_log() {
    local max_size=$((10 * 1024 * 1024)) # 10MB
    if [ -f "$LOG_FILE" ]; then
        local size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null)
        if [ $size -gt $max_size ]; then
            local timestamp=$(date +%Y%m%d-%H%M%S)
            mv "$LOG_FILE" "$LOG_FILE.$timestamp"
            touch "$LOG_FILE"
            cleanup_logs
        fi
    fi
}

# 检查配置是否完整
check_config() {
    local config_file="monitor_config.conf"
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    source "$config_file"
    if [ -z "$SERVER_ID" ] || [ -z "$API_URL" ]; then
        return 1
    fi
    return 0
}
# 获取用户输入
get_config() {
    # 清除旧的配置变量
    unset SERVER_ID
    unset API_URL

    while true; do
        read -p "请输入服务器ID (例如: server-1): " SERVER_ID
        if [[ -n "$SERVER_ID" ]]; then
            break
        else
            print_error "服务器ID不能为空，请重新输入"
        fi
    done

    while true; do
        read -p "请输入API地址 (例如: http://192.168.1.100:8080/api/metrics/reportMetrics): " API_URL
        if [[ "$API_URL" =~ ^http[s]?:// ]]; then
            print_success "API地址格式正确"
            break
        else
            print_error "请输入有效的URL (必须以http://或https://开头)"
        fi
    done

    # 显示配置信息
    echo -e "\n=== 配置信息 ===" | tee -a "$LOG_FILE"
    echo "服务器ID: $SERVER_ID" | tee -a "$LOG_FILE"
    echo "API地址: $API_URL" | tee -a "$LOG_FILE"
    echo "操作系统: $OS_TYPE" | tee -a "$LOG_FILE"
    echo "=================" | tee -a "$LOG_FILE"

    read -p "确认以上信息正确吗？(y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "重新配置..."
        get_config
    fi
}

# 保存配置到文件
save_config() {
    local config_file="monitor_config.conf"
    echo "SERVER_ID='$SERVER_ID'" > "$config_file"
    echo "API_URL='$API_URL'" >> "$config_file"
    print_success "配置已保存到 $config_file"

    # 验证配置是否正确保存
    source "$config_file"
    if [ -z "$SERVER_ID" ] || [ -z "$API_URL" ]; then
        print_error "配置保存失败"
        exit 1
    fi
}

# 加载配置文件
load_config() {
    local config_file="monitor_config.conf"
    if [ -f "$config_file" ]; then
        print_info "检测到已有配置文件..."
        echo "当前配置:"
        cat "$config_file"
        read -p "是否使用已有配置？(y/n): " use_existing
        if [[ "$use_existing" =~ ^[Yy]$ ]]; then
            source "$config_file"
            return 0
        fi
    fi
    return 1
}

# 获取CPU核心数
get_cpu_cores() {
    local cpu_cores=0

    case $OS_TYPE in
        "LINUX")
            # 首选使用nproc
            if command -v nproc >/dev/null 2>&1; then
                cpu_cores=$(nproc)
            else
                # 备选方案：从/proc/cpuinfo获取
                cpu_cores=$(grep -c "processor" /proc/cpuinfo)
            fi
            ;;
        "MAC")
            # MacOS使用sysctl
            cpu_cores=$(sysctl -n hw.ncpu)
            ;;
        "WINDOWS")
            # Windows下使用wmic
            cpu_cores=$(wmic cpu get NumberOfCores | grep -v NumberOfCores | awk '{print $1}')
            ;;
        *)
            print_error "不支持的操作系统类型，默认设置为1核"
            cpu_cores=1
            ;;
    esac

    # 确保返回值为数字且大于0
    if ! [[ "$cpu_cores" =~ ^[0-9]+$ ]] || [ "$cpu_cores" -lt 1 ]; then
        print_error "CPU核心数获取失败，使用默认值1"
        cpu_cores=1
    fi

    echo $cpu_cores
}


# 获取总内存(GB)
get_total_memory() {
    local memory=0
    case $OS_TYPE in
        "LINUX")
            memory=$(free -g | grep Mem | awk '{print $2}')
            ;;
        "MAC")
            memory=$(sysctl -n hw.memsize | awk '{print $1/1024/1024/1024}')
            ;;
    esac
    echo "${memory:-0}"
}


# 获取总磁盘空间(GB)
get_total_disk() {
    local disk=0
    case $OS_TYPE in
        "LINUX")
            disk=$(df -B1G / | tail -1 | awk '{print $2}' | tr -d 'G')
            ;;
        "MAC")
            disk=$(df -g / | tail -1 | awk '{print $2}')
            ;;
    esac
    echo "${disk:-0}"
}

# 获取CPU使用率 - 确保返回数字
get_cpu_usage() {
    local cpu_usage=0
    case $OS_TYPE in
        "LINUX")
            cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F. '{print $1}')
            ;;
        "MAC")
            cpu_usage=$(top -l 1 | grep "CPU usage" | awk '{print $3}' | cut -d'%' -f1)
            ;;
        "WINDOWS")
            cpu_usage=$(wmic cpu get loadpercentage | grep -v LoadPercentage | awk '{print $1}')
            ;;
    esac
    # 确保返回的是数字
    if ! [[ "$cpu_usage" =~ ^[0-9]+$ ]]; then
        cpu_usage=0
    fi
    echo $cpu_usage
}

# 获取内存使用率 - 确保返回数字
get_memory_usage() {
    local memory_usage=0
    case $OS_TYPE in
        "LINUX")
            memory_usage=$(free | grep Mem | awk '{print int($3/$2 * 100)}')
            ;;
        "MAC")
            memory_usage=$(vm_stat | awk '
                BEGIN { total=0; used=0; }
                /free/     { free = $3 }
                /active/   { active = $3 }
                /inactive/ { inactive = $3 }
                /wired/    { wired = $4 }
                END {
                    total = free + active + inactive + wired
                    used = active + wired
                    print int(used * 100 / total)
                }
            ' | sed 's/\.//')
            ;;
        "WINDOWS")
            memory_usage=$(wmic OS get FreePhysicalMemory,TotalVisibleMemorySize /Value | awk -F'=' '
                /FreePhysicalMemory/ { free=$2 }
                /TotalVisibleMemorySize/ { total=$2 }
                END { print int((total-free)*100/total) }
            ')
            ;;
    esac
    # 确保返回的是数字
    if ! [[ "$memory_usage" =~ ^[0-9]+$ ]]; then
        memory_usage=0
    fi
    echo $memory_usage
}

# 获取磁盘使用率
get_disk_usage() {
    local disk_usage=0
    case $OS_TYPE in
        "LINUX"|"MAC")
            disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
            ;;
        "WINDOWS")
            disk_usage=$(wmic logicaldisk where "DeviceID='C:'" get Size,FreeSpace | awk '
                NR==2 {
                    free=$1
                    total=$2
                    print int((total-free)*100/total)
                }
            ')
            ;;
    esac
    echo ${disk_usage:-0}
}
# 修改获取网络流量函数
get_network_traffic() {
    local rx_speed=0
    local tx_speed=0
    local interface=""

    case $OS_TYPE in
        "LINUX")
            # 获取默认网络接口
            interface=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
            if [ -z "$interface" ]; then
                # 如果没有找到默认接口，尝试使用常见接口名
                for iface in eth0 ens3 ens4 eth1; do
                    if [ -e "/sys/class/net/$iface" ]; then
                        interface=$iface
                        break
                    fi
                done
            fi

            if [ -z "$interface" ]; then
                print_error "无法找到有效的网络接口"
                echo "0 0"
                return
            fi

            # 第一次读取
            if [ -f "/proc/net/dev" ]; then
                rx_bytes1=$(grep $interface /proc/net/dev | awk '{print $2}')
                tx_bytes1=$(grep $interface /proc/net/dev | awk '{print $10}')

                # 检查是否成功获取到值
                if [ -z "$rx_bytes1" ] || [ -z "$tx_bytes1" ]; then
                    print_error "无法读取网络流量数据"
                    echo "0 0"
                    return
                fi

                sleep 1

                rx_bytes2=$(grep $interface /proc/net/dev | awk '{print $2}')
                tx_bytes2=$(grep $interface /proc/net/dev | awk '{print $10}')

                # 计算速度并确保结果为数字
                if [ "$rx_bytes2" -ge "$rx_bytes1" ]; then
                    rx_speed=$(echo "scale=2; ($rx_bytes2 - $rx_bytes1)/1048576" | bc)
                else
                    rx_speed=0
                fi

                if [ "$tx_bytes2" -ge "$tx_bytes1" ]; then
                    tx_speed=$(echo "scale=2; ($tx_bytes2 - $tx_bytes1)/1048576" | bc)
                else
                    tx_speed=0
                fi
            else
                print_error "/proc/net/dev 文件不存在"
                echo "0 0"
                return
            fi
            ;;

        "MAC")
            interface=$(route get default 2>/dev/null | grep interface | awk '{print $2}')
            if [ -z "$interface" ]; then
                interface="en0"
            fi

            # 使用 netstat 获取数据
            stats1=$(netstat -I $interface -b 2>/dev/null | tail -1)
            if [ -z "$stats1" ]; then
                print_error "无法获取网络统计信息"
                echo "0 0"
                return
            fi

            rx_bytes1=$(echo $stats1 | awk '{print $7}')
            tx_bytes1=$(echo $stats1 | awk '{print $10}')

            sleep 1

            stats2=$(netstat -I $interface -b 2>/dev/null | tail -1)
            rx_bytes2=$(echo $stats2 | awk '{print $7}')
            tx_bytes2=$(echo $stats2 | awk '{print $10}')

            # 计算速度
            if [ "$rx_bytes2" -ge "$rx_bytes1" ]; then
                rx_speed=$(echo "scale=2; ($rx_bytes2 - $rx_bytes1)/1048576" | bc)
            else
                rx_speed=0
            fi

            if [ "$tx_bytes2" -ge "$tx_bytes1" ]; then
                tx_speed=$(echo "scale=2; ($tx_bytes2 - $tx_bytes1)/1048576" | bc)
            else
                tx_speed=0
            fi
            ;;

        *)
            print_error "不支持的操作系统类型: $OS_TYPE"
            echo "0 0"
            return
            ;;
    esac

    # 确保有值，如果为空则设为0
    rx_speed=${rx_speed:-0}
    tx_speed=${tx_speed:-0}

    echo "$rx_speed $tx_speed"
}




# 获取服务器IP
# 修改获取服务器IP函数
get_server_ip() {
    local ip=""
    case $OS_TYPE in
        "LINUX")
            ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -n1)
            ;;
        "MAC")
            ip=$(ifconfig | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | head -n1)
            ;;
        *)
            ip="unknown"
            ;;
    esac

    # 如果没有获取到IP，返回unknown
    if [ -z "$ip" ]; then
        ip="unknown"
    fi

    echo "$ip"
}

# 检查必要的命令
check_requirements() {
    local required_commands=()

    # 基础命令
    required_commands+=("curl" "awk" "grep")

    # 系统特定命令
    case $OS_TYPE in
        "LINUX")
            required_commands+=("free" "ip" "bc")
            ;;
        "MAC")
            required_commands+=("vm_stat" "netstat" "route" "bc")
            ;;
        "WINDOWS")
            required_commands+=("wmic" "powershell")
            ;;
    esac

    local missing_commands=()
    for cmd in "${required_commands[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            missing_commands+=($cmd)
        fi
    done

    if [ ${#missing_commands[@]} -ne 0 ]; then
        print_error "缺少以下命令: ${missing_commands[*]}"
        case $OS_TYPE in
            "LINUX")
                print_info "请安装所需命令: sudo apt-get update && sudo apt-get install ${missing_commands[*]}"
                ;;
            "MAC")
                print_info "请使用Homebrew安装所需命令: brew install ${missing_commands[*]}"
                ;;
            "WINDOWS")
                print_info "请确保Windows系统工具完整安装"
                ;;
        esac
        exit 1
    fi
}

# 启动后台服务
start_daemon() {
    print_info "正在启动监控服务..."

    # 获取配置信息
    get_config
    save_config

    # 检查进程是否已经在运行
    if [ -f "monitor.pid" ]; then
        pid=$(cat monitor.pid)
        if kill -0 $pid 2>/dev/null; then
            print_error "监控服务已经在运行 (PID: $pid)"
            exit 1
        else
            rm monitor.pid
        fi
    fi

    # 将输出重定向到日志文件
    nohup $0 run > "$LOG_FILE" 2>&1 &
    echo $! > monitor.pid
    print_success "监控服务已启动 (PID: $!)"
    print_info "日志文件: $(pwd)/$LOG_FILE"
}

# 停止服务
stop_daemon() {
    if [ -f "monitor.pid" ]; then
        pid=$(cat monitor.pid)
        if kill -0 $pid 2>/dev/null; then
            kill $pid
            rm monitor.pid
            print_success "监控服务已停止 (PID: $pid)"
        else
            print_error "监控服务未在运行"
            rm monitor.pid
        fi
    else
        print_error "找不到PID文件，服务可能未在运行"
    fi
}

# 重启服务
restart_daemon() {
    print_info "正在重启监控服务..."
    stop_daemon
    sleep 2
    start_daemon
}

monitor() {
    # 确保配置存在
    if [ ! -f "monitor_config.conf" ]; then
        print_error "配置文件不存在，请先配置"
        exit 1
    fi

    # 加载配置
    source monitor_config.conf

    # 验证配置
    if [ -z "$SERVER_ID" ] || [ -z "$API_URL" ]; then
        print_error "配置信息不完整，请重新配置"
        exit 1
    fi

    print_info "开始监控..."
    print_info "Server ID: $SERVER_ID"
    print_info "API URL: $API_URL"

    # 获取静态信息
    cpu_cores=$(get_cpu_cores)
    total_memory=$(get_total_memory)
    total_disk=$(get_total_disk)
    SERVER_IP=$(get_server_ip)

    local speed_test_interval=2592000  # 30天 = 30 * 24 * 60 * 60 = 2592000秒
    local last_speed_test=0

    while true; do
      current_time=$(date +%s)

      # 检查是否需要进行速度测试
      if [ "$current_month" != "$last_test_month" ] || [ $last_speed_test -eq 0 ]; then
                  print_info "执行月度网络速度测试..."
                  read download_speed upload_speed < <(test_network_speed)
                  last_speed_test=$current_time

                  # 保存测试结果和时间
                  echo "$current_time" > "last_speed_test.txt"
                  echo "$(date '+%Y-%m-%d %H:%M:%S') $download_speed $upload_speed" > "current_speed.txt"

                  print_info "网络速度测试完成 - 下载: ${download_speed} MB/s, 上传: ${upload_speed} MB/s"
              else
                  # 使用最近一次的测试结果
                  if [ -f "current_speed.txt" ]; then
                      read -r _ _ download_speed upload_speed < "current_speed.txt"
                  else
                      read download_speed upload_speed < <(test_network_speed)
                  fi
              fi

            # 获取系统指标
            local cpu_usage=$(get_cpu_usage)
            local memory_usage=$(get_memory_usage)
            local disk_usage=$(get_disk_usage)

            # 获取网络流量（确保是数字格式）
            local download_speed=0
            local upload_speed=0
            read download_speed upload_speed < <(get_network_traffic)

            # 格式化为两位小数
            download_speed=$(printf "%.2f" ${download_speed:-0})
            upload_speed=$(printf "%.2f" ${upload_speed:-0})

            # 更新流量统计
            update_traffic_stats "$download_speed" "$upload_speed"

            # 获取月度总流量（只获取数值）
            local monthly_download=0
            local monthly_upload=0
            read monthly_download monthly_upload < <(get_monthly_traffic)

            # 构建JSON数据（确保所有数值都是合适的格式）
            local json_data=$(cat <<EOF
    {
        "serverId": "${SERVER_ID}",
        "serverIp": "${SERVER_IP}",
        "cpuCores": $(printf '%.0f' ${cpu_cores:-1}),
        "totalMemory": $(printf '%.0f' ${total_memory:-0}),
        "totalDisk": $(printf '%.0f' ${total_disk:-0}),
        "cpuUsage": $(printf '%.0f' ${cpu_usage:-0}),
        "memoryUsage": $(printf '%.0f' ${memory_usage:-0}),
        "diskUsage": $(printf '%.0f' ${disk_usage:-0}),
        "uploadTraffic": ${upload_speed:-0.00},
        "downloadTraffic": ${download_speed:-0.00},
        "totalUploadTraffic": ${monthly_upload:-0.00},
        "totalDownloadTraffic": ${monthly_download:-0.00}
    }
EOF
    )
            # 测试API连接
            if ! curl -s --connect-timeout 5 -m 10 -o /dev/null -w "%{http_code}" "${API_URL%%/api*}" >/dev/null 2>&1; then
                print_error "无法连接到API服务器，请检查网络连接和API地址"
                sleep 60
                continue
            fi

            # 发送数据到API（添加超时设置）
            local response=$(curl -s -w "\n%{http_code}" \
                --connect-timeout 5 \
                -m 10 \
                -X POST "${API_URL}" \
                -H "Content-Type: application/json" \
                -d "$json_data")

            # 分离响应内容和状态码
            local http_code=$(echo "$response" | tail -n1)
            local response_body=$(echo "$response" | sed '$d')

            if [ "$http_code" = "200" ]; then
                print_success "数据上报成功"
                print_info "系统状态:"
                print_info "  CPU使用率: ${cpu_usage}%"
                print_info "  内存使用率: ${memory_usage}%"
                print_info "  磁盘使用率: ${disk_usage}%"
                print_info "网络状态:"
                print_info "  实时上传: ${upload_speed} MB/s"
                print_info "  实时下载: ${download_speed} MB/s"
                print_info "月度统计:"
                print_info "  总上传: ${monthly_upload} MB"
                print_info "  总下载: ${monthly_download} MB"
            else
                print_error "数据上报失败 (HTTP状态码: ${http_code})"
                if [ -n "$response_body" ]; then
                    print_error "错误信息: ${response_body}"
                fi
                # 输出调试信息
                print_error "API地址: ${API_URL}"
                print_error "发送的数据:"
                echo "$json_data" | sed 's/^/  /'
            fi

            print_info "-------------------------------------------"
            sleep 60
        done
}

# 修改测试网络连接函数
test_api_connection() {
    local api_url=$1
    local base_url=${api_url%%/api*}  # 获取基础URL

    print_info "测试API连接: ${base_url}"

    local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 5 \
        -m 10 \
        "${base_url}")

    if [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
        print_success "API服务器连接正常"
        return 0
    else
        print_error "无法连接到API服务器 (HTTP状态码: ${http_code})"
        return 1
    fi
}


# 清理函数
cleanup() {
    print_info "停止监控..."
    exit 0
}


test_network_speed() {
    # 测试服务器列表（包含国内三网和国际线路）
    local test_servers=(
        # 中国电信
        "https://download.xiaoi.com/100M.zip|电信"
        "https://github.elemecdn.com/100MB.bin|电信"
        "http://speedtest1.sh.chinatelecom.cn:8080/download?size=100000000|电信"

        # 中国联通
        "https://download.chinacache.com/100MB.test|联通"
        "http://speedtest.unitacs.com:8080/download?size=100000000|联通"
        "https://mirrors.tuna.tsinghua.edu.cn/ubuntu-releases/22.04/ubuntu-22.04-desktop-amd64.iso.zsync|联通"

        # 中国移动
        "http://speedtest1.gd.chinamobile.com:8080/download?size=100000000|移动"
        "http://speedtest2.sz.chinamobile.com:8080/download?size=100000000|移动"
        "http://speedtest.371.sh.cn.chinamobile.com/speedtest/100mb.bin|移动"

        # 国际线路（作为备选）
        "http://speedtest.tokyo.linode.com/100MB-tokyo.bin|国际"
        "http://speedtest.singapore.linode.com/100MB-singapore.bin|国际"
        "http://cachefly.cachefly.net/100mb.test|国际"
    )

    local best_download_speed=0
    local best_upload_speed=0
    local best_isp=""
    local temp_file="/tmp/speedtest_$(date +%s)"
    local test_size=10485760  # 10MB for testing
    local timeout=10  # 测试超时时间（秒）

    print_info "开始网络速度测试..."

    # 测试下载速度
    for server in "${test_servers[@]}"; do
        local url=$(echo $server | cut -d'|' -f1)
        local isp=$(echo $server | cut -d'|' -f2)

        print_info "测试 ${isp} 线路: ${url}"

        # 使用 curl 测试下载速度，添加超时设置
        local speed=$(curl -r 0-${test_size} \
            --connect-timeout 5 \
            --max-time $timeout \
            -w "%{speed_download}" \
            -o "$temp_file" \
            "$url" 2>/dev/null)

        # 如果下载失败，继续下一个
        if [ $? -ne 0 ]; then
            print_error "${isp} 线路测试失败，尝试下一个..."
            continue
        fi

        # 转换为 MB/s
        local mb_speed=$(echo "scale=2; $speed/1024/1024" | bc)
        print_info "${isp} 下载速度: ${mb_speed} MB/s"

        # 更新最佳速度
        if (( $(echo "$mb_speed > $best_download_speed" | bc -l) )); then
            best_download_speed=$mb_speed
            best_isp=$isp
        fi

        # 如果速度足够好就提前结束
        if (( $(echo "$best_download_speed > 50" | bc -l) )); then
            print_success "获得理想速度，停止测试"
            break
        fi
    done

    print_success "最佳下载速度: ${best_download_speed} MB/s (${best_isp})"
    rm -f "$temp_file"

    # 测试上传速度
    print_info "开始测试上传速度..."
    # 创建测试文件
    dd if=/dev/urandom of="$temp_file" bs=1M count=10 2>/dev/null

    best_isp=""
    # 使用相同的服务器列表测试上传
    for server in "${test_servers[@]}"; do
        local url=$(echo $server | cut -d'|' -f1)
        local isp=$(echo $server | cut -d'|' -f2)

        print_info "测试 ${isp} 上传线路: ${url}"

        # 测试上传速度
        local speed=$(curl -T "$temp_file" \
            --connect-timeout 5 \
            --max-time $timeout \
            -w "%{speed_upload}" \
            "$url" 2>/dev/null)

        # 如果上传失败，继续下一个
        if [ $? -ne 0 ]; then
            print_error "${isp} 上传测试失败，尝试下一个..."
            continue
        fi

        # 转换为 MB/s
        local mb_speed=$(echo "scale=2; $speed/1024/1024" | bc)
        print_info "${isp} 上传速度: ${mb_speed} MB/s"

        # 更新最佳速度
        if (( $(echo "$mb_speed > $best_upload_speed" | bc -l) )); then
            best_upload_speed=$mb_speed
            best_isp=$isp
        fi

        # 如果速度足够好就提前结束
        if (( $(echo "$best_upload_speed > 20" | bc -l) )); then
            print_success "获得理想上传速度，停止测试"
            break
        fi
    done

    print_success "最佳上传速度: ${best_upload_speed} MB/s (${best_isp})"
    rm -f "$temp_file"

    # 保存测试结果到文件
    echo "$(date '+%Y-%m-%d %H:%M:%S') 下载: ${best_download_speed}MB/s 上传: ${best_upload_speed}MB/s" >> "speedtest_history.log"

    # 确保返回值是数字
    best_download_speed=$(printf "%.2f" ${best_download_speed:-0})
    best_upload_speed=$(printf "%.2f" ${best_upload_speed:-0})

    echo "$best_download_speed $best_upload_speed"
}

# 初始化或读取流量统计
init_traffic_stats() {
    local stats_dir="traffic_stats"
    mkdir -p "$stats_dir"

    # 获取当前月份
    current_month=$(date +%Y%m)
    monthly_file="$stats_dir/${current_month}.stats"

    # 如果当月文件不存在，创建新文件
    if [ ! -f "$monthly_file" ]; then
        # 获取实际网络速度测试结果
        read download_speed upload_speed < <(test_network_speed)
        echo "0 0 $download_speed $upload_speed" > "$monthly_file"
        print_info "创建新月度流量统计文件: $monthly_file"
        print_info "网络测速结果 - 下载: ${download_speed}MB/s, 上传: ${upload_speed}MB/s"
    fi
}

# 读取累计流量
read_traffic_stats() {
    if [ -f "$TRAFFIC_STATS_FILE" ]; then
        read total_download total_upload < "$TRAFFIC_STATS_FILE"
    else
        total_download=0
        total_upload=0
    fi
    echo "$total_download $total_upload"
}

# 修改更新流量统计函数
update_traffic_stats() {
    local download_traffic=${1:-0}
    local upload_traffic=${2:-0}
    local stats_dir="traffic_stats"

    # 确保目录存在
    mkdir -p "$stats_dir"

    local current_month=$(date +%Y%m)
    local monthly_file="$stats_dir/${current_month}.stats"

    # 如果文件不存在，创建并初始化
    if [ ! -f "$monthly_file" ]; then
        echo "0 0" > "$monthly_file"
    fi

    # 读取当前累计流量
    local total_download=0
    local total_upload=0

    if [ -f "$monthly_file" ]; then
        read total_download total_upload < "$monthly_file"
    fi

    # 确保变量为数字
    total_download=${total_download:-0}
    total_upload=${total_upload:-0}

    # 计算新的总流量
    total_download=$(echo "scale=2; $total_download + ($download_traffic * 60)" | bc)
    total_upload=$(echo "scale=2; $total_upload + ($upload_traffic * 60)" | bc)

    # 保存更新后的统计
    echo "$total_download $total_upload" > "$monthly_file"

    print_info "已更新月度流量统计 - 下载: $(format_traffic $total_download), 上传: $(format_traffic $total_upload)"
}


# 修改格式化流量函数
format_traffic() {
    local bytes=$1

    # 确保输入是数字，否则返回0
    if ! [[ "$bytes" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        echo "0.00"
        return
    fi

    # 简化格式化，只返回数值
    if [ $(echo "$bytes < 1024" | bc) -eq 1 ]; then
        printf "%.2f" $bytes
    elif [ $(echo "$bytes < 1048576" | bc) -eq 1 ]; then
        printf "%.2f" $(echo "scale=2; $bytes/1024" | bc)
    else
        printf "%.2f" $(echo "scale=2; $bytes/1048576" | bc)
    fi
}


# 获取月度流量统计
get_monthly_traffic() {
    local stats_dir="traffic_stats"
    mkdir -p "$stats_dir"

    local current_month=$(date +%Y%m)
    local monthly_file="$stats_dir/${current_month}.stats"

    # 如果文件不存在，返回默认值
    if [ ! -f "$monthly_file" ]; then
        echo "0.00 0.00"
        return
    fi

    # 读取流量数据
    local total_download=0
    local total_upload=0
    read total_download total_upload < "$monthly_file"

    # 确保有值
    total_download=${total_download:-0}
    total_upload=${total_upload:-0}

    # 格式化流量（只返回数值）
    echo "$(format_traffic $total_download) $(format_traffic $total_upload)"
}

# 修正JSON数据构建
build_json_data() {
    local cpu_cores=$1
    local total_memory=$2
    local total_disk=$3
    local cpu_usage=$4
    local memory_usage=$5
    local disk_usage=$6
    local upload_traffic=$7
    local download_traffic=$8
    local total_upload=$9
    local total_download=${10}
    local server_ip=${11}

    # 构建格式化的JSON数据
    cat << EOF
{
    "serverId": "${SERVER_ID}",
    "serverIp": "${server_ip}",
    "cpuCores": ${cpu_cores},
    "totalMemory": ${total_memory},
    "totalDisk": ${total_disk},
    "cpuUsage": ${cpu_usage},
    "memoryUsage": ${memory_usage},
    "diskUsage": ${disk_usage},
    "uploadTraffic": ${upload_traffic},
    "downloadTraffic": ${download_traffic},
    "totalUploadTraffic": "${total_upload}",
    "totalDownloadTraffic": "${total_download}"
}
EOF
}



# 主函数
main() {
    echo "=== 跨平台服务器监控脚本 ==="
    echo "当前操作系统: $OS_TYPE"

    case "${1:-}" in
        "start")
            # 检查必要命令
            check_requirements
            # 启动服务（会提示输入配置）
            start_daemon
            ;;
        "stop")
            stop_daemon
            ;;
        "restart")
            restart_daemon
            ;;
        "status")
            if [ -f "monitor.pid" ]; then
                pid=$(cat monitor.pid)
                if kill -0 $pid 2>/dev/null; then
                    print_success "监控服务正在运行 (PID: $pid)"
                else
                    print_error "监控服务未在运行"
                    rm monitor.pid
                fi
            else
                print_error "监控服务未在运行"
            fi
            ;;
        "run")
            # 检查必要命令
            check_requirements
            # 设置清理函数
            trap cleanup SIGINT SIGTERM
            # 开始监控
            monitor
            ;;
        *)
            echo "使用方法: $0 {start|stop|restart|status|run}"
            echo "  start   - 启动监控服务（后台运行）"
            echo "  stop    - 停止监控服务"
            echo "  restart - 重启监控服务"
            echo "  status  - 查看服务状态"
            echo "  run     - 直接运行（前台运行）"
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"