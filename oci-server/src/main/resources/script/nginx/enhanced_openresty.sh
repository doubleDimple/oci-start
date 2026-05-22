#!/bin/bash
# enhanced_openresty.sh

echo "=== OpenResty 增强版配置 ==="

# 检查系统用户
echo "系统可用用户组："
cat /etc/group | grep -E "^(www-data|nginx|nobody)" || echo "需要使用root用户运行"

# 创建增强的API脚本
echo "创建增强的API脚本..."
sudo tee /opt/lua/simple_api.lua > /dev/null << 'EOF'
local cjson = require "cjson"
local io = require "io"

-- 设置JSON响应头
ngx.header.content_type = "application/json"

-- 获取请求信息
local method = ngx.var.request_method
local uri = ngx.var.uri

-- 配置文件路径
local NGINX_CONF = "/usr/local/openresty/nginx/conf/nginx.conf"
local CONF_DIR = "/etc/nginx/conf.d/"

-- 工具函数：返回成功响应
local function success_response(message, data)
    return cjson.encode({
        success = true,
        message = message or "操作成功",
        data = data,
        timestamp = ngx.now()
    })
end

-- 工具函数：返回错误响应
local function error_response(error_msg, details)
    ngx.status = 500
    return cjson.encode({
        success = false,
        error = error_msg or "操作失败",
        details = details,
        timestamp = ngx.now()
    })
end

-- 工具函数：读取文件内容
local function read_file(filepath)
    local file, err = io.open(filepath, "r")
    if not file then
        return nil, "无法读取文件: " .. filepath .. " - " .. (err or "unknown error")
    end

    local content = file:read("*a")
    file:close()
    return content, nil
end

-- 工具函数：检查文件是否存在
local function file_exists(filepath)
    local file = io.open(filepath, "r")
    if file then
        file:close()
        return true
    end
    return false
end

-- 工具函数：列出目录中的配置文件
local function list_config_files(dir)
    local handle = io.popen("find " .. dir .. " -name '*.conf' 2>/dev/null")
    if not handle then
        return {}
    end

    local files = {}
    for filepath in handle:lines() do
        local basename = string.match(filepath, "([^/]+)%.conf$")
        if basename then
            local stat = io.popen("stat -c '%Y %s' '" .. filepath .. "' 2>/dev/null")
            local stat_info = stat:read("*l")
            stat:close()

            local mtime, size = "unknown", "unknown"
            if stat_info then
                mtime, size = string.match(stat_info, "(%d+) (%d+)")
            end

            table.insert(files, {
                name = basename,
                path = filepath,
                size = tonumber(size) or 0,
                modified_time = tonumber(mtime) or 0
            })
        end
    end
    handle:close()
    return files
end

-- 工具函数：获取nginx进程信息
local function get_nginx_info()
    local handle = io.popen("ps aux | grep openresty | grep -v grep | wc -l")
    local process_count = 0
    if handle then
        process_count = tonumber(handle:read("*l")) or 0
        handle:close()
    end

    return {
        process_count = process_count,
        config_file = NGINX_CONF,
        config_dir = CONF_DIR
    }
end

-- 根据URI路由处理请求
if uri == "/api/test" then
    -- 基础测试接口
    local response = {
        method = method,
        uri = uri,
        server = "Enhanced OpenResty API",
        features = {
            "基础测试",
            "读取配置文件",
            "列出配置文件",
            "系统状态查询"
        }
    }

    ngx.say(success_response("API工作正常", response))

elseif uri == "/api/config/main" then
    -- 读取主配置文件
    if method == "GET" then
        if file_exists(NGINX_CONF) then
            local content, err = read_file(NGINX_CONF)
            if content then
                ngx.say(success_response("主配置文件读取成功", {
                    file = NGINX_CONF,
                    content = content,
                    size = string.len(content)
                }))
            else
                ngx.say(error_response("读取主配置文件失败", err))
            end
        else
            ngx.say(error_response("主配置文件不存在", NGINX_CONF))
        end
    else
        ngx.status = 405
        ngx.say(error_response("不支持的方法，请使用GET"))
    end

elseif uri == "/api/config/list" then
    -- 列出所有配置文件
    if method == "GET" then
        local files = list_config_files(CONF_DIR)

        -- 同时检查主配置文件
        if file_exists(NGINX_CONF) then
            local main_stat = io.popen("stat -c '%Y %s' '" .. NGINX_CONF .. "' 2>/dev/null")
            local stat_info = main_stat:read("*l")
            main_stat:close()

            local mtime, size = "unknown", "unknown"
            if stat_info then
                mtime, size = string.match(stat_info, "(%d+) (%d+)")
            end

            table.insert(files, 1, {
                name = "nginx.conf (main)",
                path = NGINX_CONF,
                size = tonumber(size) or 0,
                modified_time = tonumber(mtime) or 0
            })
        end

        ngx.say(success_response("配置文件列表获取成功", {
            files = files,
            count = #files,
            main_config = NGINX_CONF,
            config_dir = CONF_DIR
        }))
    else
        ngx.status = 405
        ngx.say(error_response("不支持的方法，请使用GET"))
    end

elseif string.match(uri, "^/api/config/file") then
    -- 读取指定的配置文件
    if method == "GET" then
        local args = ngx.req.get_uri_args()
        local filename = args.name

        if not filename then
            ngx.status = 400
            ngx.say(error_response("缺少参数: name"))
        else
            local filepath = CONF_DIR .. filename
            if not string.match(filename, "%.conf$") then
                filepath = filepath .. ".conf"
            end

            if file_exists(filepath) then
                local content, err = read_file(filepath)
                if content then
                    ngx.say(success_response("配置文件读取成功", {
                        filename = filename,
                        filepath = filepath,
                        content = content,
                        size = string.len(content)
                    }))
                else
                    ngx.say(error_response("读取配置文件失败", err))
                end
            else
                ngx.status = 404
                ngx.say(error_response("配置文件不存在", filepath))
            end
        end
    else
        ngx.status = 405
        ngx.say(error_response("不支持的方法，请使用GET"))
    end

elseif uri == "/api/status" then
    -- 系统状态
    if method == "GET" then
        local nginx_info = get_nginx_info()
        local config_valid = true
        local config_test_result = "OK"

        -- 测试配置文件
        local test_handle = io.popen("/usr/local/openresty/bin/openresty -t 2>&1")
        if test_handle then
            config_test_result = test_handle:read("*a") or "测试失败"
            local exit_code = test_handle:close()
            config_valid = exit_code == true or exit_code == 0
        end

        ngx.say(success_response("系统状态获取成功", {
            nginx_info = nginx_info,
            config_test = {
                valid = config_valid,
                result = config_test_result
            },
            server_time = os.date("%Y-%m-%d %H:%M:%S"),
            uptime = ngx.now()
        }))
    else
        ngx.status = 405
        ngx.say(error_response("不支持的方法，请使用GET"))
    end

else
    -- 404 处理
    ngx.status = 404
    ngx.say(error_response("API端点不存在", {
        available_endpoints = {
            "GET /api/test - 基础测试",
            "GET /api/config/main - 读取主配置文件",
            "GET /api/config/list - 列出所有配置文件",
            "GET /api/config/file?name=filename - 读取指定配置文件",
            "GET /api/status - 系统状态"
        }
    }))
end
EOF

# 确保目录存在
sudo mkdir -p /var/log/nginx
sudo mkdir -p /etc/nginx/conf.d
sudo chmod 755 /var/log/nginx

# 创建修正的配置文件
echo "创建修正的配置文件..."
sudo tee /usr/local/openresty/nginx/conf/nginx.conf > /dev/null << 'EOF'
worker_processes 1;
error_log /var/log/nginx/error.log info;
pid /var/run/openresty.pid;

events {
    worker_connections 1024;
}

http {
    access_log /var/log/nginx/access.log;

    server {
        listen 8080;
        server_name localhost;

        # 基础测试接口
        location /api/test {
            content_by_lua_file /opt/lua/simple_api.lua;
        }

        # 配置文件管理接口
        location ~ ^/api/config/(main|list|file) {
            content_by_lua_file /opt/lua/simple_api.lua;
        }

        # 系统状态接口
        location /api/status {
            content_by_lua_file /opt/lua/simple_api.lua;
        }

        # 健康检查
        location /health {
            return 200 "OK - Enhanced OpenResty\n";
            add_header Content-Type text/plain;
        }

        # API文档
        location /api {
            return 200 '{"message":"Enhanced OpenResty API","endpoints":{"/api/test":"基础测试","/api/config/main":"读取主配置","/api/config/list":"配置文件列表","/api/config/file?name=xxx":"读取指定配置","/api/status":"系统状态"}}';
            add_header Content-Type application/json;
        }

        # 根路径
        location / {
            return 200 "Enhanced OpenResty is running!\n";
            add_header Content-Type text/plain;
        }
    }
}
EOF

# 测试配置
echo "测试配置文件..."
sudo /usr/local/openresty/bin/openresty -t

if [ $? -eq 0 ]; then
    echo "✅ 配置文件OK"
else
    echo "❌ 配置文件有问题"
    exit 1
fi

# 停止旧进程
echo "停止旧进程..."
sudo pkill -f openresty || true
sudo pkill -f nginx || true

# 启动OpenResty
echo "启动OpenResty..."
sudo /usr/local/openresty/bin/openresty

# 等待启动
sleep 3

# 检查进程和端口
echo "检查进程："
ps aux | grep openresty | grep -v grep

echo "检查端口："
ss -tulpn | grep 8080

# 测试所有API接口
echo "测试所有API接口..."

echo ""
echo "1. 基础测试："
curl -s http://localhost:8080/api/test | jq . || curl -s http://localhost:8080/api/test

echo ""
echo "2. 系统状态："
curl -s http://localhost:8080/api/status | jq . || curl -s http://localhost:8080/api/status

echo ""
echo "3. 配置文件列表："
curl -s http://localhost:8080/api/config/list | jq . || curl -s http://localhost:8080/api/config/list

echo ""
echo "4. 主配置文件内容（前200字符）："
curl -s "http://localhost:8080/api/config/main" | jq -r '.data.content' | head -c 200 || echo "需要安装jq来格式化JSON"

echo ""
echo ""
echo "🎉 增强版OpenResty API部署完成！"
echo ""
echo "可用的API端点："
echo "  GET /api/test                    - 基础测试"
echo "  GET /api/status                  - 系统状态"
echo "  GET /api/config/main             - 读取主配置文件"
echo "  GET /api/config/list             - 列出所有配置文件"
echo "  GET /api/config/file?name=文件名  - 读取指定配置文件"
echo "  GET /health                      - 健康检查"
echo ""
echo "测试命令示例："
echo "  curl http://localhost:8080/api/config/main"
echo "  curl http://localhost:8080/api/config/list"
echo "  curl 'http://localhost:8080/api/config/file?name=test.conf'"