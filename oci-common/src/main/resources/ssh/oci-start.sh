#!/bin/bash

#使用指定端口: ./oci-start.sh -p40000
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${CYAN}[SUCCESS]${NC} $1"
}

# 获取脚本的实际路径(无论从哪里调用)
SCRIPT_REAL_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")

# 应用配置 - 使用绝对路径
JAR_PATH="/root/oci-start/oci-start-release.jar"
LOG_FILE="/dev/null"
JAR_DIR="$(dirname "$JAR_PATH")"
SCRIPT_PATH=$(readlink -f "$0")
SYMLINK_PATH="/usr/local/bin/oci-start"

# JVM参数
JVM_OPTS="-XX:+UseG1GC"

# 检测是否为国内IP
is_china_network() {
    log_info "正在检测网络环境..."

    # 尝试连接Google，超时设置为5秒
    if curl -s --connect-timeout 5 --max-time 5 https://google.com > /dev/null 2>&1; then
        log_info "检测到可访问Google，判断为国外网络环境"
        return 1  # 国外网络
    else
        log_info "检测到无法访问Google，判断为国内网络环境"
        return 0  # 国内网络
    fi
}

# 检查Java是否已安装
check_java() {
    if ! command -v java &> /dev/null; then
        log_warn "未检测到Java，准备安装JDK..."
        install_java
    else
        java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
        log_info "检测到Java版本: $java_version"
    fi
}

# 安装Java
install_java() {
    log_info "开始安装Java..."
    if command -v apt &> /dev/null; then
        # Debian/Ubuntu
        log_info "使用apt安装JDK..."
        apt update -y
        DEBIAN_FRONTEND=noninteractive apt install -y default-jdk
    elif command -v yum &> /dev/null; then
        # CentOS/RHEL
        log_info "使用yum安装JDK..."
        yum update -y
        yum install -y java-11-openjdk
    elif command -v dnf &> /dev/null; then
        # Fedora
        log_info "使用dnf安装JDK..."
        dnf update -y
        dnf install -y java-11-openjdk
    else
        log_error "不支持的操作系统，请手动安装Java"
        exit 1
    fi

    if ! command -v java &> /dev/null; then
        log_error "Java安装失败"
        exit 1
    else
        java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
        log_success "Java安装成功，版本: $java_version"
    fi
}

# 检查Websockify是否已安装
check_websockify() {
    if ! command -v websockify &> /dev/null; then
        log_warn "未检测到Websockify，准备安装..."
        install_websockify
    else
        websockify_version=$(websockify --help 2>&1 | head -1 | grep -o 'v[0-9.]*' || echo "未知版本")
    fi
}

# 安装Websockify
install_websockify() {
    log_info "开始安装Websockify..."

    # 首先检查Python是否已安装
    if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
        log_info "Python未安装，正在安装Python..."
        if command -v apt &> /dev/null; then
            # Debian/Ubuntu
            apt update -y
            DEBIAN_FRONTEND=noninteractive apt install -y python3 python3-pip
        elif command -v yum &> /dev/null; then
            # CentOS/RHEL
            yum update -y
            yum install -y python3 python3-pip
        elif command -v dnf &> /dev/null; then
            # Fedora
            dnf update -y
            dnf install -y python3 python3-pip
        else
            log_error "不支持的操作系统，请手动安装Python"
            exit 1
        fi
    fi

    # 确定使用的Python命令
    PYTHON_CMD=""
    if command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
    elif command -v python &> /dev/null; then
        PYTHON_CMD="python"
    else
        log_error "Python安装后仍无法找到，请检查安装"
        exit 1
    fi

    # 检查pip是否可用
    PIP_CMD=""
    if command -v pip3 &> /dev/null; then
        PIP_CMD="pip3"
    elif command -v pip &> /dev/null; then
        PIP_CMD="pip"
    elif $PYTHON_CMD -m pip --version &> /dev/null; then
        PIP_CMD="$PYTHON_CMD -m pip"
    else
        log_error "pip未找到，尝试安装pip..."
        if command -v apt &> /dev/null; then
            apt install -y python3-pip
            PIP_CMD="pip3"
        elif command -v yum &> /dev/null; then
            yum install -y python3-pip
            PIP_CMD="pip3"
        elif command -v dnf &> /dev/null; then
            dnf install -y python3-pip
            PIP_CMD="pip3"
        else
            log_error "无法安装pip，请手动安装"
            exit 1
        fi
    fi

    # 尝试通过包管理器安装websockify
    local installed_via_package=false
    if command -v apt &> /dev/null; then
        # Debian/Ubuntu - 尝试通过apt安装
        log_info "尝试通过apt安装websockify..."
        if apt install -y websockify 2>/dev/null; then
            installed_via_package=true
            log_success "通过apt成功安装websockify"
        else
            log_warn "apt安装websockify失败，将使用pip安装"
        fi
    elif command -v yum &> /dev/null; then
        # CentOS/RHEL - 通常需要EPEL源
        log_info "尝试通过yum安装websockify..."
        if yum install -y python3-websockify 2>/dev/null || yum install -y websockify 2>/dev/null; then
            installed_via_package=true
            log_success "通过yum成功安装websockify"
        else
            log_warn "yum安装websockify失败，将使用pip安装"
        fi
    elif command -v dnf &> /dev/null; then
        # Fedora
        log_info "尝试通过dnf安装websockify..."
        if dnf install -y python3-websockify 2>/dev/null; then
            installed_via_package=true
            log_success "通过dnf成功安装websockify"
        else
            log_warn "dnf安装websockify失败，将使用pip安装"
        fi
    fi

    # 如果包管理器安装失败，使用pip安装
    if [ "$installed_via_package" = false ]; then
        log_info "使用pip安装websockify..."
        if $PIP_CMD install websockify; then
            log_success "通过pip成功安装websockify"
        else
            log_error "pip安装websockify失败，尝试升级pip后重试..."
            $PIP_CMD install --upgrade pip
            if $PIP_CMD install websockify; then
                log_success "升级pip后成功安装websockify"
            else
                log_error "websockify安装失败，请手动安装"
                exit 1
            fi
        fi
    fi

    # 验证安装
    if ! command -v websockify &> /dev/null; then
        log_error "websockify安装失败，命令不可用"
        exit 1
    else
        websockify_version=$(websockify --help 2>&1 | head -1 | grep -o 'v[0-9.]*' || echo "未知版本")
        log_success "Websockify安装成功，版本: $websockify_version"
    fi
}

# 创建软链接
create_symlink() {
    if [ ! -L "$SYMLINK_PATH" ] || [ "$(readlink "$SYMLINK_PATH")" != "$SCRIPT_PATH" ]; then
        log_info "创建软链接: $SYMLINK_PATH -> $SCRIPT_PATH"
        # 确保目标目录存在
        mkdir -p "$(dirname "$SYMLINK_PATH")" 2>/dev/null
        # 尝试创建软链接，如果没有权限则提示使用sudo
        if ln -sf "$SCRIPT_PATH" "$SYMLINK_PATH" 2>/dev/null; then
            log_success "软链接创建成功，现在可以使用 'oci-start' 命令"
        else
            log_warn "没有权限创建软链接，尝试使用sudo"
            if command -v sudo &>/dev/null; then
                sudo ln -sf "$SCRIPT_PATH" "$SYMLINK_PATH"
                log_success "软链接创建成功，现在可以使用 'oci-start' 命令"
            else
                log_error "创建软链接失败，请确保有足够权限或手动创建"
            fi
        fi
    fi
}

# 检查并下载jar包
check_and_download_jar() {
    # 始终使用绝对路径操作
    if [ ! -f "$JAR_PATH" ]; then
        log_info "未找到JAR包，准备下载最新版本..."
        mkdir -p "$(dirname "$JAR_PATH")"
        update_latest
        if [ ! -f "$JAR_PATH" ]; then
            log_error "下载JAR包失败"
            exit 1
        fi
    fi
}

start() {

    # 切换到脚本所在目录，确保所有操作基于此目录
    cd "$SCRIPT_REAL_DIR" || {
        log_error "无法切换到脚本目录: $SCRIPT_REAL_DIR"
        exit 1
    }

    # 端口默认值（application.yml 对应里面的值）
    PORT=9856
    # 解析额外参数
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -p|--port)
                PORT="$2"
                shift
                ;;
            -p*)
                PORT="${1#-p}"
                ;;
            --port=*)
                PORT="${1#--port=}"
                ;;
        esac
        shift
    done
    # 检查Java安装，自动安装JDK
    check_java

    # 检查Websockify安装，自动安装Websockify
    check_websockify

    # 检查并下载jar包
    check_and_download_jar

    # 创建软链接
    create_symlink

    # 输出成功提示
    log_success "环境准备完成，现在可以使用 'oci-start' 命令"

    if pgrep -f "$JAR_PATH" > /dev/null; then
        log_warn "应用已经在运行中"
        exit 0
    fi

    log_info "正在启动应用..."

    # 启动应用 - 使用绝对路径
    #nohup java $JVM_OPTS -jar "$JAR_PATH" > "$LOG_FILE" 2>&1 &
    nohup java $JVM_OPTS -jar "$JAR_PATH" --server.port=$PORT > "$LOG_FILE" 2>&1 &

    # 等待几秒检查是否成功启动
    sleep 3
    if pgrep -f "$JAR_PATH" > /dev/null; then
        log_success "应用启动成功"

        # 获取系统IP地址
        IP=$(hostname -I | awk '{print $1}')
        if [ -z "$IP" ]; then
            IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
        fi

        # 输出访问地址
        echo -e "${BLUE}欢迎使用oci-start${NC}"
        echo -e "${CYAN}访问地址为: ${NC}http://${IP}:${PORT}"

    else
        log_error "应用启动失败"
        exit 1
    fi
}

# 改进的停止函数 - 保持简洁但增加超时检查
stop() {
    # 切换到脚本所在目录
    cd "$SCRIPT_REAL_DIR" || {
        log_error "无法切换到脚本目录: $SCRIPT_REAL_DIR"
        exit 1
    }

    # 创建软链接，确保停止后仍然可以使用oci-start命令
    create_symlink

    PIDS=$(pgrep -f "$JAR_PATH")
    if [ -z "$PIDS" ]; then
        log_warn "应用未在运行"
        return 0
    fi

    log_info "正在停止应用... (PIDs: $PIDS)"

    # 发送TERM信号
    kill $PIDS 2>/dev/null

    # 等待进程停止，最多等待10秒
    local count=0
    while [ $count -lt 10 ]; do
        if ! pgrep -f "$JAR_PATH" > /dev/null; then
            log_success "应用已停止"
            return 0
        fi
        sleep 1
        count=$((count + 1))
        log_info "等待进程停止... ($count/10)"
    done

    # 如果还没停止，强制停止
    if pgrep -f "$JAR_PATH" > /dev/null; then
        log_warn "强制停止应用..."
        kill -9 $(pgrep -f "$JAR_PATH") 2>/dev/null
        sleep 2

        if pgrep -f "$JAR_PATH" > /dev/null; then
            log_error "无法停止应用"
            return 1
        else
            log_success "应用已强制停止"
            return 0
        fi
    fi

    log_success "应用已停止"
    return 0
}

restart() {
    # 切换到脚本所在目录
    cd "$SCRIPT_REAL_DIR" || {
        log_error "无法切换到脚本目录: $SCRIPT_REAL_DIR"
        exit 1
    }

    # 重启时也检查环境
    check_java
    check_websockify
    create_symlink
    stop
    start
}

status() {
    # 切换到脚本所在目录
    cd "$SCRIPT_REAL_DIR" || {
        log_error "无法切换到脚本目录: $SCRIPT_REAL_DIR"
        exit 1
    }

    # 在所有命令中都增加环境检查
    check_java
    check_websockify
    create_symlink

    if pgrep -f "$JAR_PATH" > /dev/null; then
        log_success "应用正在运行"
    else
        log_error "应用未运行"
    fi
}

# 改进的更新函数 - 基于原有逻辑但增加错误处理
update_latest() {
    # 切换到脚本所在目录
    cd "$SCRIPT_REAL_DIR" || {
        log_error "无法切换到脚本目录: $SCRIPT_REAL_DIR"
        exit 1
    }

    # 检查Java安装
    check_java

    # 检查Websockify安装
    check_websockify

    log_info "开始检查更新..."
    mkdir -p "$JAR_DIR"

    # 检查是否安装了curl
    if ! command -v curl &> /dev/null; then
        log_info "安装curl..."
        if command -v apt &> /dev/null; then
            apt update -y
            apt install -y curl
        elif command -v yum &> /dev/null; then
            yum install -y curl
        elif command -v dnf &> /dev/null; then
            dnf install -y curl
        else
            log_error "不支持的操作系统，请手动安装curl"
            exit 1
        fi
    fi

    # 使用原始的GitHub API获取版本信息
    local api_url="https://api.github.com/repos/doubleDimple/oci-start/releases/latest"

    # 获取版本信息
    log_info "获取最新版本信息..."
    local download_url=$(curl -s --connect-timeout 10 --max-time 30 "$api_url" | grep "browser_download_url.*jar" | cut -d '"' -f 4)

    if [ -z "$download_url" ]; then
        log_error "无法获取最新版本信息，请检查网络连接"
        return 1
    fi

    # 如果是国内网络，在下载链接前加上加速前缀
    if is_china_network; then
        download_url="https://speed.objboy.com/$download_url"
        log_info "使用国内加速下载地址"
    fi

    local latest_version=$(curl -s --connect-timeout 10 --max-time 30 "$api_url" | grep '"tag_name":' | cut -d '"' -f 4)
    log_info "找到最新版本: ${latest_version}"
    log_info "开始下载..."

    local temp_file="${JAR_PATH}.temp"
    local backup_file="${JAR_PATH}.${latest_version}.bak"

    # 下载文件
    log_info "下载文件到: $temp_file"
    if curl -L --connect-timeout 30 --max-time 300 -o "$temp_file" "$download_url"; then
        # 验证下载的文件
        if [ ! -f "$temp_file" ] || [ ! -s "$temp_file" ]; then
            log_error "下载的文件无效"
            rm -f "$temp_file"
            return 1
        fi

        # 检查文件类型（如果有file命令）
        if command -v file &> /dev/null; then
            if ! file "$temp_file" | grep -q "Java archive\|Zip archive"; then
                log_error "下载的文件不是有效的JAR文件"
                rm -f "$temp_file"
                return 1
            fi
        fi

        log_success "文件下载完成"

        # 停止应用
        log_info "停止当前应用..."
        if ! stop; then
            log_error "停止应用失败"
            rm -f "$temp_file"
            return 1
        fi

        # 备份原文件
        if [ -f "$JAR_PATH" ]; then
            if cp "$JAR_PATH" "$backup_file"; then
                log_info "原JAR包已备份为: $backup_file"
            else
                log_error "无法创建备份文件"
                rm -f "$temp_file"
                return 1
            fi
        fi

        # 替换文件
        if mv "$temp_file" "$JAR_PATH"; then
            chmod +x "$JAR_PATH"
            log_success "JAR包更新完成，版本：${latest_version}"

            # 启动应用
            log_info "启动新版本..."
            if start; then
                # 验证启动
                sleep 5
                if pgrep -f "$JAR_PATH" > /dev/null; then
                    log_success "新版本启动成功，清理备份文件..."
                    rm -f "$backup_file"
                    return 0
                else
                    log_error "新版本启动失败，恢复备份版本"
                    if [ -f "$backup_file" ]; then
                        mv "$backup_file" "$JAR_PATH"
                        log_info "已恢复备份版本"
                        start
                    fi
                    return 1
                fi
            else
                log_error "启动失败"
                return 1
            fi
        else
            log_error "文件替换失败"
            rm -f "$temp_file"
            return 1
        fi
    else
        log_error "下载失败，请检查网络连接"
        rm -f "$temp_file"
        return 1
    fi
}


uninstall() {
    # 切换到脚本所在目录
    cd "$SCRIPT_REAL_DIR" || {
        log_error "无法切换到脚本目录: $SCRIPT_REAL_DIR"
        exit 1
    }

    echo -e "${YELLOW}确认卸载说明:${NC}"
    echo -e "1. 将停止并删除所有应用相关文件"
    echo -e "2. 此操作不可逆，请确认"
    echo -ne "${YELLOW}确认继续卸载吗? [y/N]: ${NC}"
    read -r response

    case "$response" in
        [yY][eE][sS]|[yY])
            true
            ;;
        *)
            log_info "取消卸载操作"
            exit 0
            ;;
    esac

    log_info "开始卸载应用..."

    # 停止应用
    if pgrep -f "$JAR_PATH" > /dev/null; then
        log_info "正在停止应用进程..."
        stop
        sleep 2
    fi

    # 删除应用文件
    [ -f "$JAR_PATH" ] && rm -f "$JAR_PATH"

    # 清理其他文件
    find "$JAR_DIR" -name "*.bak" -o -name "*.backup" -o -name "*.temp" -o -name "*.log" -delete 2>/dev/null

    # 删除软链接
    if [ -L "$SYMLINK_PATH" ]; then
        log_info "正在删除软链接..."
        rm -f "$SYMLINK_PATH"
    fi

    # 检查是否清理完成
    if [ ! -f "$JAR_PATH" ] && [ ! -L "$SYMLINK_PATH" ]; then
        log_success "应用卸载完成"
        echo -e "${GREEN}如需重新安装应用，请使用 'start' 命令${NC}"
        echo -e "${YELLOW}注意: Java和Websockify未被卸载，如需卸载请手动操作${NC}"
    else
        log_error "卸载未完全成功，请检查日志"
    fi
}

# 主命令处理
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
    update)
        update_latest
        ;;
    uninstall)
        uninstall
        ;;
    *)
        echo -e "${YELLOW}Usage: $0 {start|stop|restart|status|update|uninstall}${NC}"
        exit 1
        ;;
esac