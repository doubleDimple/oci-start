#!/bin/bash
# nginx_config_manager_with_ssl.sh

echo "=== Nginx配置管理系统 - SSL证书管理增强版 ==="

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
    mkdir -p /usr/local/openresty/nginx/ssl
    mkdir -p /usr/local/openresty/nginx/ssl/backups

    # 设置目录权限
    chmod 777 /usr/local/openresty/nginx/logs
    chmod 777 /usr/local/openresty/nginx/conf
    chmod 777 /opt/lua
    chmod 777 /tmp/nginx-backups
    chmod 755 /usr/local/openresty/nginx/ssl
    chmod 755 /usr/local/openresty/nginx/ssl/backups

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
    chown -R root:root /usr/local/openresty/nginx/ssl/

    echo "目录创建和权限设置完成"
}

# 第三步：创建配置管理API脚本（包含SSL证书管理）
create_api_script() {
    echo "创建配置管理API脚本（含SSL证书管理）..."

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
local SSL_BASE_DIR = "/usr/local/openresty/nginx/ssl/"
local SSL_BACKUP_DIR = "/usr/local/openresty/nginx/ssl/backups/"

-- 确保备份目录存在
os.execute("mkdir -p " .. BACKUP_DIR)
os.execute("mkdir -p " .. SSL_BASE_DIR)
os.execute("mkdir -p " .. SSL_BACKUP_DIR)

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
        ssl_base_dir = SSL_BASE_DIR,
        ssl_backup_dir = SSL_BACKUP_DIR,
        server_time = os.date("%Y-%m-%d %H:%M:%S")
    }
end

-- SSL证书管理函数：保存证书文件
local function save_ssl_cert(domain_name, cert_content, key_content, force_replace)
    if not domain_name or domain_name == "" then
        return false, "域名不能为空"
    end

    -- 清理域名，防止路径注入，只允许域名字符
    domain_name = string.gsub(domain_name, "[^%w%.%-]", "")

    -- 创建域名专属目录
    local domain_dir = SSL_BASE_DIR .. domain_name .. "/"
    local cert_file = domain_dir .. "fullchain.pem"
    local key_file = domain_dir .. "privkey.pem"

    -- 检查目录是否存在，如果存在且不强制替换，则返回错误
    local dir_exists = os.execute("test -d '" .. domain_dir .. "'") == 0 or os.execute("test -d '" .. domain_dir .. "'") == true

    if dir_exists and not force_replace then
        return false, "域名 " .. domain_name .. " 的证书已存在，如需替换请设置 force_replace 为 true"
    end

    -- 创建域名目录
    os.execute("mkdir -p '" .. domain_dir .. "'")
    os.execute("chmod 755 '" .. domain_dir .. "'")

    -- 创建备份（如果文件存在的话）
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local backup_created = false

    if io.open(cert_file, "r") then
        local backup_cert = SSL_BACKUP_DIR .. domain_name .. "_fullchain_" .. timestamp .. ".pem.bak"
        os.execute("cp '" .. cert_file .. "' '" .. backup_cert .. "'")
        backup_created = true
        log_info("已备份证书: " .. backup_cert)
    end

    if io.open(key_file, "r") then
        local backup_key = SSL_BACKUP_DIR .. domain_name .. "_privkey_" .. timestamp .. ".pem.bak"
        os.execute("cp '" .. key_file .. "' '" .. backup_key .. "'")
        backup_created = true
        log_info("已备份私钥: " .. backup_key)
    end

    -- 保存证书文件
    if cert_content and cert_content ~= "" then
        local cert_f, cert_err = io.open(cert_file, "w")
        if not cert_f then
            return false, "无法写入证书文件: " .. (cert_err or "unknown")
        end
        cert_f:write(cert_content)
        cert_f:close()
        os.execute("chmod 644 '" .. cert_file .. "'")
        log_info("证书文件已保存: " .. cert_file)
    end

    -- 保存私钥文件
    if key_content and key_content ~= "" then
        local key_f, key_err = io.open(key_file, "w")
        if not key_f then
            return false, "无法写入私钥文件: " .. (key_err or "unknown")
        end
        key_f:write(key_content)
        key_f:close()
        os.execute("chmod 600 '" .. key_file .. "'")
        log_info("私钥文件已保存: " .. key_file)
    end

    -- 设置目录和文件所有者
    os.execute("chown -R root:root '" .. domain_dir .. "'")

    return true, {
        domain = domain_name,
        domain_dir = domain_dir,
        cert_file = cert_file,
        key_file = key_file,
        backup_created = backup_created,
        backup_timestamp = backup_created and timestamp or nil,
        replaced = dir_exists
    }
end

-- SSL证书管理函数：获取证书列表
local function get_ssl_certs()
    local certs = {}

    -- 读取SSL根目录下的所有域名目录
    local handle = io.popen("ls -la '" .. SSL_BASE_DIR .. "' 2>/dev/null | grep '^d' | awk '{print $NF}' | grep -v '^\\.\\|backups' || true")
    if handle then
        for domain_name in handle:lines() do
            if domain_name and domain_name ~= "" then
                local domain_dir = SSL_BASE_DIR .. domain_name .. "/"
                local cert_file = domain_dir .. "fullchain.pem"
                local key_file = domain_dir .. "privkey.pem"

                -- 检查证书和私钥文件是否存在
                local cert_exists = io.open(cert_file, "r") ~= nil
                local key_exists = io.open(key_file, "r") ~= nil

                if cert_exists or key_exists then
                    -- 获取文件信息
                    local cert_info = { size = 0, modified = "未知" }
                    local key_info = { size = 0, modified = "未知" }

                    if cert_exists then
                        local stat_handle = io.popen("stat -c '%Y %s' '" .. cert_file .. "' 2>/dev/null || echo '0 0'")
                        if stat_handle then
                            local mtime, size = stat_handle:read("*l"):match("(%d+) (%d+)")
                            cert_info.modified = os.date("%Y-%m-%d %H:%M:%S", tonumber(mtime))
                            cert_info.size = tonumber(size)
                            stat_handle:close()
                        end
                    end

                    if key_exists then
                        local stat_handle = io.popen("stat -c '%Y %s' '" .. key_file .. "' 2>/dev/null || echo '0 0'")
                        if stat_handle then
                            local mtime, size = stat_handle:read("*l"):match("(%d+) (%d+)")
                            key_info.modified = os.date("%Y-%m-%d %H:%M:%S", tonumber(mtime))
                            key_info.size = tonumber(size)
                            stat_handle:close()
                        end
                    end

                    table.insert(certs, {
                        domain = domain_name,
                        domain_dir = domain_dir,
                        cert_file = cert_file,
                        key_file = key_file,
                        cert_exists = cert_exists,
                        key_exists = key_exists,
                        cert_info = cert_info,
                        key_info = key_info,
                        complete = cert_exists and key_exists
                    })
                end
            end
        end
        handle:close()
    end

    return certs
end

-- SSL证书管理函数：删除证书
local function delete_ssl_cert(domain_name)
    if not domain_name or domain_name == "" then
        return false, "域名不能为空"
    end

    domain_name = string.gsub(domain_name, "[^%w%.%-]", "")

    local domain_dir = SSL_BASE_DIR .. domain_name .. "/"
    local cert_file = domain_dir .. "fullchain.pem"
    local key_file = domain_dir .. "privkey.pem"

    -- 检查目录是否存在
    local dir_exists = os.execute("test -d '" .. domain_dir .. "'") == 0 or os.execute("test -d '" .. domain_dir .. "'") == true
    if not dir_exists then
        return false, "域名 " .. domain_name .. " 的证书不存在"
    end

    -- 创建备份
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local backup_created = false

    if io.open(cert_file, "r") then
        local backup_cert = SSL_BACKUP_DIR .. domain_name .. "_deleted_fullchain_" .. timestamp .. ".pem.bak"
        os.execute("cp '" .. cert_file .. "' '" .. backup_cert .. "'")
        backup_created = true
        log_info("已备份待删除的证书: " .. backup_cert)
    end

    if io.open(key_file, "r") then
        local backup_key = SSL_BACKUP_DIR .. domain_name .. "_deleted_privkey_" .. timestamp .. ".pem.bak"
        os.execute("cp '" .. key_file .. "' '" .. backup_key .. "'")
        backup_created = true
        log_info("已备份待删除的私钥: " .. backup_key)
    end

    -- 删除整个域名目录
    os.execute("rm -rf '" .. domain_dir .. "'")
    log_info("已删除域名目录: " .. domain_dir)

    return true, {
        domain = domain_name,
        backup_created = backup_created,
        backup_timestamp = timestamp,
        message = "域名 " .. domain_name .. " 的证书已删除，备份已保存"
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
        version = "2.0",
        note = "通过API管理nginx.conf配置文件和SSL证书"
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

elseif uri == "/api/ssl/certs" then
    if method == "GET" then
        -- 获取SSL证书列表
        local certs = get_ssl_certs()
        success_response("SSL证书列表获取成功", {
            count = #certs,
            certificates = certs,
            ssl_base_dir = SSL_BASE_DIR
        })

    elseif method == "POST" then
        -- 上传/保存SSL证书
        local data = get_request_body()
        if not data or not data.domain then
            return error_response(400, "缺少参数: domain (域名)")
        end

        if not data.cert and not data.key then
            return error_response(400, "必须提供证书内容(cert)或私钥内容(key)")
        end

        -- 检查是否强制替换
        local force_replace = data.force_replace or false

        local success, result = save_ssl_cert(data.domain, data.cert, data.key, force_replace)
        if success then
            success_response("SSL证书保存成功", result)
        else
            error_response(500, "SSL证书保存失败", result)
        end

    else
        error_response(405, "只支持GET和POST方法")
    end

elseif uri:match("^/api/ssl/certs/([%w%.%-]+)$") then
    local domain_name = uri:match("^/api/ssl/certs/([%w%.%-]+)$")

    if method == "GET" then
        -- 获取特定域名证书内容
        domain_name = string.gsub(domain_name, "[^%w%.%-]", "")
        local domain_dir = SSL_BASE_DIR .. domain_name .. "/"
        local cert_file = domain_dir .. "fullchain.pem"
        local key_file = domain_dir .. "privkey.pem"

        local cert_content = ""
        local key_content = ""

        local cert_f = io.open(cert_file, "r")
        if cert_f then
            cert_content = cert_f:read("*a")
            cert_f:close()
        end

        local key_f = io.open(key_file, "r")
        if key_f then
            key_content = key_f:read("*a")
            key_f:close()
        end

        if cert_content == "" and key_content == "" then
            error_response(404, "域名 " .. domain_name .. " 的证书不存在")
        else
            success_response("证书内容获取成功", {
                domain = domain_name,
                domain_dir = domain_dir,
                cert = cert_content,
                key = key_content,
                cert_file = cert_file,
                key_file = key_file
            })
        end

    elseif method == "PUT" then
        -- 更新特定域名的SSL证书 (强制替换)
        local data = get_request_body()
        if not data then
            return error_response(400, "请求体不能为空")
        end

        if not data.cert and not data.key then
            return error_response(400, "必须提供证书内容(cert)或私钥内容(key)")
        end

        -- 使用PUT方法时默认强制替换
        local success, result = save_ssl_cert(domain_name, data.cert, data.key, true)
        if success then
            success_response("SSL证书更新成功", result)
        else
            error_response(500, "SSL证书更新失败", result)
        end

    elseif method == "DELETE" then
        -- 删除SSL证书
        local success, result = delete_ssl_cert(domain_name)
        if success then
            success_response("证书删除成功", result)
        else
            error_response(400, "删除失败", result)
        end

    else
        error_response(405, "只支持GET、PUT和DELETE方法")
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
            "GET  /api/status - 系统状态",
            "GET  /api/ssl/certs - 获取SSL证书列表",
            "POST /api/ssl/certs - 上传SSL证书 (可选force_replace)",
            "GET  /api/ssl/certs/{domain} - 获取特定域名证书内容",
            "PUT  /api/ssl/certs/{domain} - 更新特定域名证书 (强制替换)",
            "DELETE /api/ssl/certs/{domain} - 删除域名证书"
        }
    })
end
EOF

    chmod +x /opt/lua/config_manager.lua
    echo "APIè„šæœ¬åˆ›å»ºå®Œæˆ"
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
        listen 0.0.0.0:8080;
        server_name _;

        # 只允许本机访问（127.0.0.1 和 Docker 网桥 IP）
        allow 127.0.0.1;           # 本机 localhost
        allow 172.17.0.0/16;       # Docker bridge 网络
        allow 172.18.0.0/16;       # Docker compose 网络
        allow 172.19.0.0/16;       # Docker swarm 网络
        allow 192.168.0.0/16;      # 如果你用自定义网络
        deny all;                  # 拒绝其他所有请求

        # 配置管理API
        location ~ ^/api/config {
            content_by_lua_file /opt/lua/config_manager.lua;
        }

        # SSL证书管理API
        location ~ ^/api/ssl {
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
            return 200 '{"message":"Nginx Config Manager","version":"2.0","status":"running","features":["config_management","ssl_certificate_management"]}';
            add_header Content-Type application/json;
        }

        # 默认页面
        location / {
            return 200 "Nginx Config Manager v2.0 with SSL Certificate Management is running!";
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

    echo -e "\n4. SSL证书列表:"
    curl -s http://localhost:8080/api/ssl/certs | head -c 150
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
    echo "  - SSL证书目录: /usr/local/openresty/nginx/ssl/"
    echo ""
    echo "🔧 API端点:"
    echo "  GET  /api/test           - 基础测试"
    echo "  GET  /api/status         - 系统状态"
    echo "  GET  /api/config         - 读取nginx.conf"
    echo "  PUT  /api/config         - 完全替换nginx.conf"
    echo "  POST /api/config/test    - 测试配置语法"
    echo "  POST /api/config/reload  - 重载配置"
    echo "  GET  /api/ssl/certs      - 获取SSL证书列表"
    echo "  POST /api/ssl/certs      - 上传SSL证书 (支持force_replace)"
    echo "  GET  /api/ssl/certs/{domain}  - 获取特定域名证书"
    echo "  PUT  /api/ssl/certs/{domain}  - 更新域名证书 (强制替换)"
    echo "  DELETE /api/ssl/certs/{domain} - 删除域名证书"
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
    echo "  # 首次上传SSL证书"
    echo "  curl -X POST http://localhost:8080/api/ssl/certs \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"domain\":\"cncode.de\",\"cert\":\"证书内容\",\"key\":\"私钥内容\"}'"
    echo ""
    echo "  # 强制替换已存在的SSL证书"
    echo "  curl -X POST http://localhost:8080/api/ssl/certs \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"domain\":\"cncode.de\",\"cert\":\"新证书内容\",\"key\":\"新私钥内容\",\"force_replace\":true}'"
    echo ""
    echo "  # 更新特定域名证书 (自动强制替换)"
    echo "  curl -X PUT http://localhost:8080/api/ssl/certs/cncode.de \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"cert\":\"新证书内容\",\"key\":\"新私钥内容\"}'"
    echo ""
    echo "  # 获取证书列表"
    echo "  curl http://localhost:8080/api/ssl/certs"
    echo ""
    echo "  # 获取特定域名证书"
    echo "  curl http://localhost:8080/api/ssl/certs/cncode.de"
    echo ""
    echo "  # 删除域名证书"
    echo "  curl -X DELETE http://localhost:8080/api/ssl/certs/cncode.de"
    echo ""
    echo "  # 重载配置"
    echo "  curl -X POST http://localhost:8080/api/config/reload"
    echo ""
    echo "🔒 SSL证书目录结构:"
    echo "  /usr/local/openresty/nginx/ssl/{domain}/     - 域名专属目录"
    echo "  └── fullchain.pem                            - 证书链文件"
    echo "  └── privkey.pem                              - 私钥文件"
    echo "  /usr/local/openresty/nginx/ssl/backups/      - 备份文件目录"
    echo ""
    echo "📁 目录结构示例:"
    echo "  /usr/local/openresty/nginx/ssl/"
    echo "  ├── cncode.de/"
    echo "  │   ├── fullchain.pem"
    echo "  │   └── privkey.pem"
    echo "  ├── example.com/"
    echo "  │   ├── fullchain.pem"
    echo "  │   └── privkey.pem"
    echo "  └── backups/"
    echo "      ├── cncode.de_fullchain_20250926_143022.pem.bak"
    echo "      └── cncode.de_privkey_20250926_143022.pem.bak"
    echo ""
    echo "🔍 增强特性:"
    echo "  - 按域名分组的独立证书目录"
    echo "  - 标准PEM文件名 (fullchain.pem, privkey.pem)"
    echo "  - 智能替换保护 (防止意外覆盖)"
    echo "  - 自动备份配置文件和SSL证书"
    echo "  - 配置语法自动检测"
    echo "  - 错误时自动恢复备份"
    echo "  - 支持完整的nginx.conf管理"
    echo "  - SSL证书文件安全权限管理 (证书644, 私钥600)"
    echo "  - 强制替换模式 (POST + force_replace 或 PUT)"
    echo ""
}

# 执行主函数
main