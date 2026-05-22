#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 使用示例
# 1. 默认安装（将安装到 /root/oci-start-docker 目录）：
#    ./docker.sh install
#
# 2. 指定目录安装（三种方式）：
#    a. 一次性指定：
#       OCI_APP_DIR=/root/oci-start-docker ./docker.sh install
#
#    b. 临时指定（仅对当前终端有效）：
#       export OCI_APP_DIR=/root/oci-start-docker
#       ./docker.sh install
#
#    c. 永久指定（对当前用户永久有效）：
#       echo 'export OCI_APP_DIR=/root/oci-start-docker' >> ~/.bashrc
#       source ~/.bashrc
#       ./docker.sh install
#
# 3. 卸载应用：
#    ./docker.sh uninstall
# 4. 指定端口 ./docker.sh install -p 40000

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

# 配置变量
APP_DIR="${OCI_APP_DIR:-/root/oci-start-docker}"
APP_CONTAINER_NAME="oci-start"
SCRIPT_PATH=$(realpath "$0")
SYMLINK_PATH="/usr/local/bin/oci-start-docker"

# 检测并安装websockify
install_websockify() {
    log_info "检查websockify是否已安装..."

    # 检查websockify命令是否存在
    if command -v websockify &> /dev/null; then
        log_success "websockify已安装"
        websockify --version 2>/dev/null || log_info "websockify版本信息获取失败，但命令可用"
        return 0
    fi

    # 检查Python是否安装websockify模块
    if python3 -c "import websockify" &> /dev/null || python -c "import websockify" &> /dev/null; then
        log_success "websockify Python模块已安装"
        return 0
    fi

    log_warn "websockify未安装，开始安装..."

    # 尝试多种安装方式
    local install_success=false

    # 方式1: 使用apt包管理器安装
    if command -v apt &> /dev/null; then
        log_info "尝试使用apt安装websockify..."
        if apt update -y && apt install -y websockify; then
            if command -v websockify &> /dev/null; then
                log_success "通过apt成功安装websockify"
                install_success=true
            fi
        else
            log_warn "通过apt安装websockify失败"
        fi
    fi

    # 方式2: 使用yum包管理器安装 (CentOS/RHEL)
    if [ "$install_success" = false ] && command -v yum &> /dev/null; then
        log_info "尝试使用yum安装websockify..."
        if yum install -y python3-websockify || yum install -y websockify; then
            if command -v websockify &> /dev/null; then
                log_success "通过yum成功安装websockify"
                install_success=true
            fi
        else
            log_warn "通过yum安装websockify失败"
        fi
    fi

    # 方式3: 使用pip安装
    if [ "$install_success" = false ]; then
        log_info "尝试使用pip安装websockify..."

        # 首先确保pip已安装
        if ! command -v pip3 &> /dev/null && ! command -v pip &> /dev/null; then
            log_info "pip未安装，正在安装pip..."
            if command -v apt &> /dev/null; then
                apt install -y python3-pip
            elif command -v yum &> /dev/null; then
                yum install -y python3-pip
            fi
        fi

        # 使用pip安装websockify
        local pip_cmd=""
        if command -v pip3 &> /dev/null; then
            pip_cmd="pip3"
        elif command -v pip &> /dev/null; then
            pip_cmd="pip"
        fi

        if [ -n "$pip_cmd" ]; then
            log_info "使用 $pip_cmd 安装websockify..."
            if $pip_cmd install websockify; then
                # 检查安装是否成功
                if command -v websockify &> /dev/null || python3 -c "import websockify" &> /dev/null; then
                    log_success "通过pip成功安装websockify"
                    install_success=true
                fi
            else
                log_warn "通过pip安装websockify失败"
            fi
        fi
    fi

    # 方式4: 从源码安装
    if [ "$install_success" = false ]; then
        log_info "尝试从GitHub源码安装websockify..."

        # 确保git已安装
        if ! command -v git &> /dev/null; then
            log_info "安装git..."
            if command -v apt &> /dev/null; then
                apt install -y git
            elif command -v yum &> /dev/null; then
                yum install -y git
            fi
        fi

        if command -v git &> /dev/null; then
            local temp_dir="/tmp/websockify-install"
            rm -rf "$temp_dir"

            if git clone https://github.com/novnc/websockify "$temp_dir"; then
                cd "$temp_dir"
                if python3 setup.py install || python setup.py install; then
                    log_success "从源码成功安装websockify"
                    install_success=true
                fi
                cd - > /dev/null
                rm -rf "$temp_dir"
            else
                log_warn "从GitHub克隆websockify失败"
            fi
        fi
    fi

    # 最终检查
    if [ "$install_success" = true ]; then
        log_success "websockify安装完成"
        # 显示版本信息
        if command -v websockify &> /dev/null; then
            websockify --version 2>/dev/null || log_info "websockify命令可用"
        fi
        return 0
    else
        log_error "websockify安装失败，请手动安装"
        echo -e "${YELLOW}手动安装方法:${NC}"
        echo -e "1. 使用包管理器: ${GREEN}apt install websockify${NC} 或 ${GREEN}yum install websockify${NC}"
        echo -e "2. 使用pip: ${GREEN}pip3 install websockify${NC}"
        echo -e "3. 从源码安装: ${GREEN}git clone https://github.com/novnc/websockify && cd websockify && python3 setup.py install${NC}"
        return 1
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
            log_success "软链接创建成功，现在可以使用 'oci-start-docker' 命令"
        else
            log_warn "没有权限创建软链接，尝试使用sudo"
            if command -v sudo &>/dev/null; then
                sudo ln -sf "$SCRIPT_PATH" "$SYMLINK_PATH"
                log_success "软链接创建成功，现在可以使用 'oci-start-docker' 命令"
            else
                log_error "创建软链接失败，请确保有足够权限或手动创建"
            fi
        fi
    fi
}

# 安装Docker
install_docker() {
    log_info "开始安装Docker..."

    # 使用一键安装脚本
    log_info "正在执行Docker一键安装..."
    if apt update -y && apt install -y curl && curl -fsSL https://get.docker.com | bash -s docker; then
        log_success "Docker安装脚本执行完成"
    else
        log_error "Docker一键安装失败"
        return 1
    fi

    # 启动Docker服务
    log_info "启动Docker服务..."
    systemctl start docker &> /dev/null || service docker start &> /dev/null

    # 设置Docker服务自启动
    systemctl enable docker &> /dev/null || true

    # 验证安装
    sleep 3  # 等待服务完全启动
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        log_success "Docker安装成功并已启动服务"

        # 显示Docker版本信息
        local docker_version=$(docker --version 2>/dev/null)
        log_info "Docker版本: $docker_version"

        return 0
    else
        log_error "Docker安装完成但服务未能正常启动"
        log_info "尝试手动启动Docker服务..."

        # 尝试不同的启动方式
        service docker start &> /dev/null || systemctl start docker &> /dev/null
        sleep 5

        if docker info &> /dev/null; then
            log_success "Docker服务手动启动成功"
            return 0
        else
            log_error "Docker服务启动失败，请检查系统日志"
            return 1
        fi
    fi
}

# 添加路径检查函数
check_script_path() {
    # 获取脚本真实路径
    SCRIPT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

    # 更新 APP_DIR 为脚本所在目录
    if [ -z "${OCI_APP_DIR}" ]; then
        APP_DIR="$SCRIPT_PATH"
        log_info "使用脚本所在目录作为应用目录: $APP_DIR"
    else
        log_info "使用配置的应用目录: $APP_DIR"
    fi

    # 默认端口
    PORT=9856

    # 参数解析（支持 -p 9000 / -p9000 / --port 9000 / --port=9000）
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

}

# 创建应用目录结构
create_app_structure() {
    log_info "创建应用目录结构..."
    mkdir -p $APP_DIR
    cd $APP_DIR || exit 1
    mkdir -p data logs
    log_success "目录结构创建完成"
}

# 容器删除函数
remove_container() {
    local container_name="$1"
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        log_info "尝试停止容器 (尝试 $attempt/$max_attempts)..."

        # 尝试正常停止容器
        if docker stop "${container_name}" >/dev/null 2>&1; then
            log_success "容器已停止"
        else
            log_warn "无法正常停止容器，尝试强制停止"
            docker kill "${container_name}" >/dev/null 2>&1
        fi

        # 等待容器完全停止
        sleep 2

        # 检查容器状态
        if ! docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
            log_success "容器已成功删除"
            return 0
        fi

        # 尝试删除容器
        log_info "尝试删除容器..."
        if docker rm -f "${container_name}" >/dev/null 2>&1; then
            log_success "容器已成功删除"
            return 0
        fi

        # 如果删除失败，获取容器详细信息
        log_warn "删除失败，容器状态："
        docker inspect "${container_name}" --format='{{.State.Status}}' 2>/dev/null || echo "无法获取容器状态"

        attempt=$((attempt + 1))
        if [ $attempt -le $max_attempts ]; then
            log_info "等待 5 秒后重试..."
            sleep 5
        fi
    done

    # 如果所有尝试都失败了，提供详细信息和手动删除建议
    log_error "在 $max_attempts 次尝试后仍无法删除容器"
    echo -e "\n${YELLOW}请尝试以下步骤手动删除：${NC}"
    echo -e "1. 查看容器状态：${GREEN}docker ps -a | grep ${container_name}${NC}"
    echo -e "2. 强制停止容器：${GREEN}docker kill ${container_name}${NC}"
    echo -e "3. 强制删除容器：${GREEN}docker rm -f ${container_name}${NC}"
    echo -e "4. 如果还是无法删除，重启 Docker 服务：${GREEN}systemctl restart docker${NC}"
    return 1
}

# 部署应用
deploy_app() {
    log_info "开始部署Docker应用..."

    # 检查并处理已存在的容器
    if docker ps -a | grep -q "$APP_CONTAINER_NAME"; then
        log_warn "发现已存在的容器，正在停止和删除..."
        if ! remove_container "$APP_CONTAINER_NAME"; then
            return 1
        fi
        sleep 2
    fi

    # 检查并拉取最新镜像
    log_info "拉取最新镜像..."
    if ! docker pull lovele/oci-start:latest; then
        log_error "拉取镜像失败"
        return 1
    fi

    # 启动容器
    log_info "启动容器..."
    if docker run -d \
        --name "$APP_CONTAINER_NAME" \
        -p ${PORT}:9856 \
        -v "$APP_DIR/data:/oci-start/data" \
        -v "$APP_DIR/logs:/oci-start/logs" \
        -v "$APP_DIR/docker.sh:/oci-start/docker.sh" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v /usr/bin/docker:/usr/bin/docker \
        -e SERVER_PORT=9856 \
        -e OCI_APP_DIR=/oci-start \
        -e DATA_PATH=/oci-start/data \
        -e LOG_HOME=/oci-start/logs \
        --restart always \
        lovele/oci-start:latest; then

        log_success "Docker应用部署成功"

        # 等待容器启动
        sleep 5

        # 验证容器运行状态
        if ! docker ps | grep -q "$APP_CONTAINER_NAME"; then
            log_error "容器未能正常运行，请检查日志"
            docker logs "$APP_CONTAINER_NAME"
            return 1
        fi

        # 获取系统IP
        IP=$(hostname -I | awk '{print $1}')
        if [ -z "$IP" ]; then
            IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
        fi

        # 显示访问信息
        echo -e "${BLUE}欢迎使用oci-start${NC}"
        echo -e "${CYAN}访问地址为: ${NC}http://${IP}:${PORT}"

        # 显示容器日志
        echo -e "\n${YELLOW}容器启动日志:${NC}"
        docker logs --tail 10 "$APP_CONTAINER_NAME"
        return 0
    else
        log_error "Docker应用部署失败"
        return 1
    fi
}

# 卸载函数
uninstall() {
    local app_dir="${APP_DIR}"
    local container_name="$APP_CONTAINER_NAME"

    # 显示确认提示
    echo -e "${YELLOW}===== 卸载确认 =====${NC}"
    echo -e "即将执行以下操作:"
    echo -e "1. 停止并删除 Docker 容器"
    echo -e "2. 删除 Docker 镜像"
    echo -e "3. 保留数据目录: ${app_dir}/data"
    echo -e "\n${RED}注意: 此操作无法撤销${NC}"
    echo -ne "\n${YELLOW}是否继续? [y/N]: ${NC}"

    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            true
            ;;
        *)
            log_info "已取消卸载操作"
            return 0
            ;;
    esac

    # 处理Docker容器
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        log_info "发现正在运行的容器，准备清理..."
        if ! remove_container "${container_name}"; then
            log_error "容器清理失败"
            exit 1
        fi
    else
        log_info "未发现运行中的Docker容器"
    fi

    # 处理应用数据
    if [ -d "${app_dir}" ]; then
        log_info "处理应用目录..."
        # 保护数据目录
        if [ -d "${app_dir}/data" ]; then
            log_info "保护数据目录..."
            local temp_data_dir="/tmp/oci-start-data-backup"
            mv "${app_dir}/data" "${temp_data_dir}"

            if [ $? -ne 0 ]; then
                log_error "备份数据目录失败"
                return 1
            fi
        fi

        # 删除应用目录
        log_info "删除应用目录: ${app_dir}"
        rm -rf "${app_dir}"

        # 恢复数据目录
        if [ -d "${temp_data_dir}" ]; then
            log_info "恢复数据目录..."
            mkdir -p "${app_dir}"
            mv "${temp_data_dir}" "${app_dir}/data"
            if [ $? -eq 0 ]; then
                log_success "数据目录已恢复到: ${app_dir}/data"
            else
                log_error "恢复数据目录失败，备份在: ${temp_data_dir}"
                return 1
            fi
        fi
    else
        log_warn "应用目录不存在: ${app_dir}"
    fi

    # 清理Docker镜像
    log_info "清理Docker镜像..."
    if docker images | grep -q "lovele/oci-start"; then
        docker rmi "$(docker images lovele/oci-start -q)" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            log_success "Docker镜像已删除"
        else
            log_warn "Docker镜像删除失败，可能正被其他容器使用"
        fi
    else
        log_info "未发现相关Docker镜像"
    fi

    # 删除软链接
    if [ -L "$SYMLINK_PATH" ] && [ "$(readlink "$SYMLINK_PATH")" = "$SCRIPT_PATH" ]; then
        log_info "删除软链接: $SYMLINK_PATH"
        rm -f "$SYMLINK_PATH"
        log_success "软链接已删除"
    fi

    log_success "==========================="
    log_success "应用卸载已完成!"
    echo -e "\n${GREEN}保留的内容:${NC}"
    echo -e "1. 应用数据目录: ${app_dir}/data"
    echo -e "\n${YELLOW}如需重新安装应用，请使用:${NC}"
    echo -e "   ./docker.sh install\n"
}

# 检查Docker是否已安装
check_docker() {
    log_info "检查Docker是否已安装..."

    # 首先检查Docker是否已安装
    if command -v docker &> /dev/null; then
        # 检查Docker服务是否运行
        if docker info >/dev/null 2>&1; then
            log_success "Docker已安装并正常运行"

            # 显示Docker版本信息
            local docker_version=$(docker --version 2>/dev/null)
            log_info "Docker版本: $docker_version"

            return 0
        else
            log_warn "Docker已安装但服务未运行，尝试启动服务..."
            systemctl start docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1

            # 等待服务启动
            sleep 3

            if docker info >/dev/null 2>&1; then
                log_success "Docker服务已成功启动"
                return 0
            else
                log_warn "无法启动Docker服务，将重新安装Docker"
                # 继续执行安装流程
            fi
        fi
    else
        log_warn "Docker未安装，开始自动安装..."
    fi

    # 执行Docker安装
    if install_docker; then
        return 0
    else
        log_error "Docker安装失败"
        return 1
    fi
}

# 修复更新函数 - 拉取最新镜像并重新创建容器
update() {
    # 确保软链接存在
    create_symlink

    log_info "开始更新Docker应用..."

    # 检查容器是否存在
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${APP_CONTAINER_NAME}$"; then
        log_error "未找到容器 ${APP_CONTAINER_NAME}，请先安装应用"
        return 1
    fi

    # 获取当前镜像ID
    local old_image_id=$(docker inspect "$APP_CONTAINER_NAME" --format='{{.Image}}' 2>/dev/null)
    log_info "当前镜像ID: $old_image_id"

    # 拉取最新镜像
    log_info "拉取最新镜像..."
    if ! docker pull lovele/oci-start:latest; then
        log_error "拉取镜像失败"
        return 1
    fi

    # 获取新镜像ID
    local new_image_id=$(docker images lovele/oci-start:latest --format='{{.ID}}' | head -n1)
    log_info "新镜像ID: $new_image_id"

    # 检查镜像是否有更新
    if [ "$old_image_id" = "$new_image_id" ]; then
        log_info "镜像已是最新版本，无需更新"
        return 0
    fi

    log_info "检测到新版本，开始更新容器..."

    # 停止并删除旧容器
    log_info "停止并删除旧容器..."
    if ! remove_container "$APP_CONTAINER_NAME"; then
        log_error "删除旧容器失败"
        return 1
    fi

    # 等待容器完全删除
    sleep 3

    # 使用新镜像重新创建容器
    log_info "使用新镜像创建容器..."
    if docker run -d \
        --name "$APP_CONTAINER_NAME" \
        -p 9856:9856 \
        -v "$APP_DIR/data:/oci-start/data" \
        -v "$APP_DIR/logs:/oci-start/logs" \
        -v "$APP_DIR/docker.sh:/oci-start/docker.sh" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v /usr/bin/docker:/usr/bin/docker \
        -e SERVER_PORT=9856 \
        -e OCI_APP_DIR=/oci-start \
        -e DATA_PATH=/oci-start/data \
        -e LOG_HOME=/oci-start/logs \
        --network host \
        --restart always \
        lovele/oci-start:latest; then

        log_success "容器创建成功"

        # 等待容器启动
        sleep 5

        # 验证容器运行状态
        if docker ps | grep -q "$APP_CONTAINER_NAME"; then
            log_success "Docker应用更新完成并已成功启动！"

            # 清理旧镜像（如果存在且不同于新镜像）
            if [ -n "$old_image_id" ] && [ "$old_image_id" != "$new_image_id" ]; then
                log_info "清理旧镜像..."
                docker rmi "$old_image_id" >/dev/null 2>&1 || true
            fi

            # 获取系统IP
            IP=$(hostname -I | awk '{print $1}')
            if [ -z "$IP" ]; then
                IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
            fi

            # 显示访问信息
            echo -e "${BLUE}应用已更新完成${NC}"
            echo -e "${CYAN}访问地址为: ${NC}http://${IP}:9856"

            return 0
        else
            log_error "容器创建后未能正常运行"
            docker logs "$APP_CONTAINER_NAME"
            return 1
        fi
    else
        log_error "创建新容器失败"
        return 1
    fi
}

# 显示使用帮助
show_help() {
    echo -e "${YELLOW}使用方法:${NC}"
    echo -e "  $0 ${GREEN}install${NC}    安装并部署应用"
    echo -e "  $0 ${RED}uninstall${NC}  卸载应用(保留数据)"
    echo -e "  $0 ${BLUE}update${NC}     更新Docker镜像并重新创建容器"
}

# 主流程
main() {
    # 首先检查和设置路径
    check_script_path

    # 确保是最新路径
    SCRIPT_PATH=$(realpath "$0")

    # 检查Docker安装状态
    if ! check_docker; then
        exit 1
    fi

    # 默认端口（容器外暴露的端口）
    PORT=9856

    # 解析 -p 参数（支持 -p 40000、--port 40000、-p40000、--port=40000）
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


    # 检查websockify安装状态
    if ! install_websockify; then
        log_warn "websockify安装失败，但脚本将继续执行"
    fi

    case "$1" in
        "install")
            # 创建软链接
            create_symlink

            # 创建应用目录结构
            create_app_structure

            # 部署应用
            deploy_app

            if [ $? -eq 0 ]; then
                log_success "全部部署完成！"
                echo -e "${GREEN}现在可以使用 'oci-start-docker' 命令来管理应用${NC}"
            else
                log_error "部署过程中出现错误，请检查以上日志"
                exit 1
            fi
            ;;
        "uninstall")
            uninstall
            ;;
        "update")
            update
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
}

# 检查是否以root权限运行
if [ "$(id -u)" != "0" ]; then
    log_error "此脚本需要root权限运行"
    exit 1
fi

# 执行主流程
main "$@"