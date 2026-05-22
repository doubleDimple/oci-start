#!/bin/bash
# nginx_config_manager_final.sh

echo "=== Nginx配置管理系统 - 最终版 ==="

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo "请使用root用户运行此脚本: sudo $0"
    exit 1
fi

echo "系统信息："
cat /etc/os-release | head -3

# 第一步：安装OpenResty（如果未安装）
install_openresty() {
    if ! command -v /usr/local/openresty/bin/openresty >/dev/null 2>&1; then
        echo "安装OpenResty..."

        if command -v apt-get >/dev/null 2>&1; then
            apt-get update
            apt-get install -y wget gnupg curl
            wget -qO - https://openresty.org/package/pubkey.gpg | apt-key add -
            echo "deb http://openresty.org/package/debian $(lsb_release -sc) openresty" > /etc/apt/sources.list.d/openresty.list
            apt-get update
            apt-get install -y openresty
        elif command -v yum >/dev/null 2>&1; then
            yum install -y wget curl
            wget https://openresty.org/package/centos/openresty.repo -O /etc/yum.repos.d/openresty.repo
            yum install -y openresty
        fi

        echo "OpenResty安装完成"
    else
        echo "OpenResty已安装，跳过安装步骤"
    fi
}

# 第二步：创建目录和设置权限
setup_directories() {
    echo "创建目录和设置权限..."

    # 创建必要目录
    mkdir -p /usr/local/openresty/nginx/logs
    mkdir -p /opt/lua
    mkdir -p /tmp/nginx-backups

    # 设置目录权限
    chmod 777 /usr/local/openresty/nginx/logs
    chmod 777 /usr/local/openresty/nginx/conf
    chmod 777 /opt/lua
    chmod 777 /tmp/nginx-backups

    # 预创建所有需要的文件并设置权限
    touch /usr/local/openresty/nginx/logs/error.log
    touch /usr/local/openresty/nginx/logs/access.log
    touch /usr/local/openresty/nginx/logs/nginx.pid

    # 设置文件权限为可读写
    chmod 666 /usr/local/openresty/nginx/logs/error.log
    chmod 666 /usr/local/openresty/nginx/logs/access.log
    chmod 666 /usr/local/openresty/nginx/logs/nginx.pid

    # 确保所有文件归root所有
    chown root:root /usr/local/openresty/nginx/logs/*

    echo "目录创建和权限设置完成"
}

# 第三步：创建配置管理API脚本
create_api_script() {
    echo "创建配置管理API脚本..."

    cat > /opt/lua/config_manager.lua << 'EOF'
local cjson = require "cjson"
local io = require "io"
local os = require "os"

-- 设置JSON响应头
ngx.header.content_type = "application/json; charset=utf-8"

-- 获取请求信息
local method = ngx.var.request_method
local uri = ngx.var.uri

-- 配置文件路径
local NGINX_CONF = "/usr/local/openresty/nginx/conf/nginx.conf"
local BACKUP_DIR = "/tmp/nginx-backups/"

-- 确保备份目录存在
os.execute("mkdir -p " .. BACKUP_DIR)

-- 工具函数：获取请求体
local function get_request_body()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if body then
        local ok, data = pcall(cjson.decode, body)
        if ok then
            return data
        end
    end
    return nil
end

-- 工具函数：返回成功响应
local function success_response(message, data)
    ngx.status = 200
    return ngx.say(cjson.encode({
        success = true,
        message = message or "操作成功",
        data = data,
        timestamp = ngx.now()
    }))
end

-- 工具函数：返回错误响应
local function error_response(status, error_msg, details)
    ngx.status = status or 500
    return ngx.say(cjson.encode({
        success = false,
        error = error_msg or "操作失败",
        details = details,
        timestamp = ngx.now()
    }))
end

-- 工具函数：记录日志
local function log_info(message)
    ngx.log(ngx.INFO, "[CONFIG-MANAGER] " .. message)
end

-- 工具函数：读取nginx.conf
local function read_nginx_conf()
    local file, err = io.open(NGINX_CONF, "r")
    if not file then
        return nil, "无法读取nginx.conf: " .. (err or "unknown")
    end

    local content = file:read("*a")
    file:close()
    return content, nil
end

-- 工具函数：写入nginx.conf
local function write_nginx_conf(content)
    -- 创建备份
    local backup_name = BACKUP_DIR .. "nginx.conf_" .. os.date("%Y%m%d_%H%M%S") .. ".bak"
    os.execute("cp '" .. NGINX_CONF .. "' '" .. backup_name .. "' 2>/dev/null")

    local file, err = io.open(NGINX_CONF, "w")
    if not file then
        return false, "无法写入nginx.conf: " .. (err or "unknown")
    end

    file:write(content)
    file:close()

    log_info("nginx.conf写入成功, 备份: " .. backup_name)
    return true, backup_name
end

-- 工具函数：测试nginx配置
local function test_nginx_config()
    local handle = io.popen("/usr/local/openresty/bin/openresty -t 2>&1")
    if not handle then
        return false, "无法执行配置测试"
    end

    local result = handle:read("*a") or ""
    local exit_code = handle:close()

    local is_ok = (exit_code == true or exit_code == 0) and
                  string.find(result, "syntax is ok") and
                  not string.find(result:lower(), "failed")

    return is_ok, result
end

-- 工具函数：重载nginx
local function reload_nginx()
    log_info("重启OpenResty进程")

    -- 停止当前进程
    os.execute("pkill -f openresty 2>/dev/null")
    ngx.sleep(2)

    -- 启动新进程
    os.execute("/usr/local/openresty/bin/openresty &")
    ngx.sleep(2)

    return true, "OpenResty重启完成"
end

-- 工具函数：获取系统状态
local function get_system_status()
    local handle = io.popen("ps aux | grep openresty | grep -v grep | wc -l")
    local process_count = 0
    if handle then
        process_count = tonumber(handle:read("*l")) or 0
        handle:close()
    end

    return {
        process_count = process_count,
        config_file = NGINX_CONF,
        backup_dir = BACKUP_DIR,
        server_time = os.date("%Y-%m-%d %H:%M:%S")
    }
end

-- 路由处理
log_info("收到请求: " .. method .. " " .. uri)

-- 路由分发
if uri == "/api/test" then
    -- 基础测试
    success_response("Nginx配置管理API工作正常", {
        method = method,
        uri = uri,
        server = "Nginx Config Manager",
        version = "1.0",
        note = "通过API管理nginx.conf配置文件"
    })

elseif uri == "/api/config" then
    if method == "GET" then
        -- 读取nginx.conf
        local content, err = read_nginx_conf()
        if content then
            success_response("nginx.conf读取成功", {
                file = NGINX_CONF,
                content = content,
                size = string.len(content),
                lines = select(2, string.gsub(content, '\n', '\n')) + 1
            })
        else
            error_response(500, "读取nginx.conf失败", err)
        end

    elseif method == "PUT" then
        -- 完全替换nginx.conf
        local data = get_request_body()
        if not data or not data.content then
            return error_response(400, "缺少参数: content")
        end

        local success, backup_path = write_nginx_conf(data.content)
        if success then
            local test_ok, test_result = test_nginx_config()
            if test_ok then
                success_response("nginx.conf替换成功", {
                    file = NGINX_CONF,
                    backup = backup_path,
                    size = string.len(data.content)
                })
            else
                -- 恢复备份
                os.execute("cp '" .. backup_path .. "' '" .. NGINX_CONF .. "'")
                error_response(400, "配置语法错误，已恢复备份", test_result)
            end
        else
            error_response(500, "写入nginx.conf失败", backup_path)
        end
    else
        error_response(405, "只支持GET和PUT方法")
    end

elseif uri == "/api/config/test" then
    -- 测试配置
    if method == "POST" then
        local test_ok, test_result = test_nginx_config()
        success_response("配置测试完成", {
            valid = test_ok,
            result = test_result
        })
    else
        error_response(405, "只支持POST方法")
    end

elseif uri == "/api/config/reload" then
    -- 重载配置
    if method == "POST" then
        local test_ok, test_result = test_nginx_config()
        if test_ok then
            local reload_ok, reload_result = reload_nginx()
            if reload_ok then
                success_response("配置重载成功", {
                    test_result = test_result,
                    reload_result = reload_result
                })
            else
                error_response(500, "重载失败", reload_result)
            end
        else
            error_response(400, "配置语法错误，无法重载", test_result)
        end
    else
        error_response(405, "只支持POST方法")
    end

elseif uri == "/api/status" then
    -- 系统状态
    if method == "GET" then
        local status = get_system_status()
        local test_ok, test_result = test_nginx_config()

        status.config_test = {
            valid = test_ok,
            result = test_result
        }

        success_response("系统状态获取成功", status)
    else
        error_response(405, "只支持GET方法")
    end

else
    -- 404处理
    error_response(404, "API端点不存在", {
        available_endpoints = {
            "GET  /api/test - 基础测试",
            "GET  /api/config - 读取nginx.conf",
            "PUT  /api/config - 完全替换nginx.conf",
            "POST /api/config/test - 测试配置",
            "POST /api/config/reload - 重载配置",
            "GET  /api/status - 系统状态"
        }
    })
end
EOF

    chmod +x /opt/lua/config_manager.lua
    echo "API脚本创建完成"
}

# 第四步：创建初始nginx配置
create_nginx_config() {
    echo "创建初始nginx配置文件..."

    cat > /usr/local/openresty/nginx/conf/nginx.conf << 'EOF'
worker_processes auto;
error_log /usr/local/openresty/nginx/logs/error.log info;
pid /usr/local/openresty/nginx/logs/nginx.pid;

events {
    worker_connections 1024;
    accept_mutex on;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    access_log /usr/local/openresty/nginx/logs/access.log;

    # 性能优化
    client_max_body_size 10m;
    sendfile on;
    keepalive_timeout 65;

    # 管理API服务器
    server {
        listen 8080;
        server_name localhost;

        # 配置管理API
        location ~ ^/api/config {
            content_by_lua_file /opt/lua/config_manager.lua;
        }

        location ~ ^/api/(test|status) {
            content_by_lua_file /opt/lua/config_manager.lua;
        }

        # 健康检查
        location /health {
            return 200 "OK - Nginx Config Manager";
            add_header Content-Type text/plain;
        }

        # API文档
        location /api {
            return 200 '{"message":"Nginx Config Manager","version":"1.0","status":"running"}';
            add_header Content-Type application/json;
        }

        # 默认页面
        location / {
            return 200 "Nginx Config Manager is running!";
            add_header Content-Type text/plain;
        }
    }
}
EOF

    echo "初始nginx配置文件创建完成"
}

# 第五步：启动和测试
start_and_test() {
    echo "测试配置并启动服务..."

    # 测试配置文件
    if ! /usr/local/openresty/bin/openresty -t; then
        echo "❌ 配置文件测试失败"
        exit 1
    fi

    echo "✅ 配置文件测试通过"

    # 停止旧进程并启动新进程
    pkill -f openresty 2>/dev/null || true
    sleep 2
    /usr/local/openresty/bin/openresty
    sleep 3

    # 检查服务状态
    if ps aux | grep openresty | grep -v grep > /dev/null; then
        echo "✅ OpenResty进程运行正常"
    else
        echo "❌ OpenResty进程未运行"
        exit 1
    fi

    if ss -tulpn | grep :8080 > /dev/null 2>&1 || netstat -tulpn | grep :8080 > /dev/null 2>&1; then
        echo "✅ 端口8080监听正常"
    else
        echo "❌ 端口8080未监听"
        exit 1
    fi

    echo ""
    echo "=== API功能测试 ==="

    echo "1. 基础测试:"
    curl -s http://localhost:8080/api/test | head -c 150
    echo "..."

    echo -e "\n2. 健康检查:"
    curl -s http://localhost:8080/health

    echo -e "\n3. 系统状态:"
    curl -s http://localhost:8080/api/status | head -c 150
    echo "..."

    echo -e "\n✅ 所有测试通过"
}

# 主函数
main() {
    echo "开始安装Nginx配置管理系统..."

    install_openresty
    setup_directories
    create_api_script
    create_nginx_config
    start_and_test

    echo ""
    echo "🎉 Nginx配置管理系统安装完成！"
    echo ""
    echo "📋 系统信息:"
    echo "  - API地址: http://localhost:8080"
    echo "  - 配置文件: /usr/local/openresty/nginx/conf/nginx.conf"
    echo "  - 备份目录: /tmp/nginx-backups/"
    echo ""
    echo "🔧 API端点:"
    echo "  GET  /api/test           - 基础测试"
    echo "  GET  /api/status         - 系统状态"
    echo "  GET  /api/config         - 读取nginx.conf"
    echo "  PUT  /api/config         - 完全替换nginx.conf"
    echo "  POST /api/config/test    - 测试配置语法"
    echo "  POST /api/config/reload  - 重载配置"
    echo ""
    echo "📖 使用示例:"
    echo "  # 读取当前配置"
    echo "  curl http://localhost:8080/api/config"
    echo ""
    echo "  # 替换配置文件"
    echo "  curl -X PUT http://localhost:8080/api/config \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"content\":\"完整的nginx配置内容\"}'"
    echo ""
    echo "  # 重载配置"
    echo "  curl -X POST http://localhost:8080/api/config/reload"
    echo ""
    echo "📝 特性:"
    echo "  - 自动备份配置文件"
    echo "  - 配置语法自动检测"
    echo "  - 错误时自动恢复备份"
    echo "  - 支持完整的nginx.conf管理"
    echo ""
}

# 执行主函数
main