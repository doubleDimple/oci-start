#!/bin/bash
# enhanced_openresty_v4.sh
#
# OpenResty 一键安装 + 配置脚本
# 完整安装 OpenResty 并部署 Java 后端 NginxConfigServiceImpl 所需的全部 API 端点：
#   GET    /api/test
#   PUT    /api/config             — 写入代理配置文件
#   POST   /api/config/test        — 测试配置语法
#   POST   /api/config/reload      — 热重载 Nginx
#   POST   /api/ssl/certs          — 上传 SSL 证书
#   GET    /api/ssl/certs          — 列出所有证书
#   GET    /api/ssl/certs/{domain} — 获取指定域名证书信息
#   DELETE /api/ssl/certs/{domain} — 删除指定域名证书
#
# 安全说明：
#   - 管理 API 仅监听 127.0.0.1:8080，不暴露到公网
#   - 如果 OPENRESTY_API_TOKEN 环境变量已设置，所有 /api 请求需要带
#     X-API-Token: <token> 头才能调用
#
# 使用方式：
#   1) 裸机/同机部署(Java 与 OpenResty 同台机器):
#        sudo ./enhanced_openresty_v4.sh
#   2) 启用 token 鉴权(推荐):
#        sudo OPENRESTY_API_TOKEN=xxxx ./enhanced_openresty_v4.sh
#   3) Docker 场景(Java 在容器,OpenResty 装在宿主机)。同时把:
#        - Java 应用配置:  openresty.api.base-url=http://<宿主IP>:8080/api
#                          openresty.api.token=xxxx
#        - 启动脚本:
#        sudo OPENRESTY_API_TOKEN=xxxx \
#             API_LISTEN=0.0.0.0:8080 \
#             API_ALLOWED_CLIENTS="127.0.0.1,172.17.0.0/16" \
#             ./enhanced_openresty_v4.sh

set -euo pipefail

OPENRESTY_BIN="/usr/local/openresty/bin/openresty"
NGINX_USER="${NGINX_USER:-nobody}"   # OpenResty worker 运行用户
API_TOKEN="${OPENRESTY_API_TOKEN:-}"

# ─── Docker / 远程 Java 客户端访问支持 ─────────────────────────
# 默认行为(裸机/同机部署):API 仅监听 127.0.0.1:8080,只接受本机回环调用,最安全。
# 当 Java 应用跑在 Docker / 另一台机器时,需要把 API 暴露给这些网络:
#   API_LISTEN          监听的 host:port,默认 127.0.0.1:8080
#                       Docker 同宿主:    "0.0.0.0:8080"
#                       compose 服务网络: "0.0.0.0:8080"
#   API_ALLOWED_CLIENTS 允许调用 API 的客户端 IP/CIDR 列表,逗号分隔
#                       默认 "127.0.0.1,::1"
#                       Docker 同宿主常见: "127.0.0.1,172.17.0.0/16"
#                       自定义 docker 网络: 加上对应网段
# 强烈建议:开放给非 127.0.0.1 时务必同时设置 OPENRESTY_API_TOKEN!
API_LISTEN="${API_LISTEN:-127.0.0.1:8080}"
API_ALLOWED_CLIENTS="${API_ALLOWED_CLIENTS:-127.0.0.1,::1}"

LUA_DIR="/opt/lua"
SSL_DIR="/usr/local/openresty/nginx/ssl"
SITES_DIR="/usr/local/openresty/nginx/conf/sites"
LOG_DIR="/var/log/nginx"
NGINX_CONF="/usr/local/openresty/nginx/conf/nginx.conf"

echo "=== OpenResty 一键安装 + 配置 v4 ==="

# 必须 root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 请用 sudo 或 root 用户执行"
    exit 1
fi

# ─── 1. 安装 OpenResty ─────────────────────────────────────
install_openresty() {
    if [ -x "$OPENRESTY_BIN" ]; then
        echo ">> OpenResty 已安装,跳过安装步骤: $($OPENRESTY_BIN -v 2>&1 | head -1)"
        return 0
    fi

    echo ">> 检测到 OpenResty 未安装,开始安装..."

    if command -v apt-get >/dev/null 2>&1; then
        echo ">> 检测到 Debian/Ubuntu 系,使用 apt 安装"
        apt-get update -y
        apt-get install -y --no-install-recommends \
            wget gnupg ca-certificates lsb-release software-properties-common
        wget -qO - https://openresty.org/package/pubkey.gpg | apt-key add -
        codename="$(lsb_release -sc 2>/dev/null || echo bookworm)"
        if grep -qi ubuntu /etc/os-release; then
            echo "deb http://openresty.org/package/ubuntu $codename main" \
                > /etc/apt/sources.list.d/openresty.list
        else
            echo "deb http://openresty.org/package/debian $codename openresty" \
                > /etc/apt/sources.list.d/openresty.list
        fi
        apt-get update -y
        apt-get install -y openresty

    elif command -v yum >/dev/null 2>&1; then
        echo ">> 检测到 RHEL/CentOS 系,使用 yum 安装"
        yum install -y yum-utils wget
        wget -O /etc/yum.repos.d/openresty.repo \
            https://openresty.org/package/centos/openresty.repo
        yum check-update -y || true
        yum install -y openresty

    elif command -v dnf >/dev/null 2>&1; then
        echo ">> 检测到 Fedora 系,使用 dnf 安装"
        dnf install -y dnf-plugins-core
        dnf config-manager --add-repo https://openresty.org/package/centos/openresty.repo
        dnf install -y openresty

    else
        echo "❌ 不支持的发行版,请手动安装 OpenResty: https://openresty.org/en/installation.html"
        exit 1
    fi

    if [ ! -x "$OPENRESTY_BIN" ]; then
        echo "❌ OpenResty 安装失败"
        exit 1
    fi
    echo ">> OpenResty 安装完成"
}
install_openresty

# ─── 2. 准备目录 ───────────────────────────────────────────
echo ">> 创建目录..."
mkdir -p "$LUA_DIR" "$SSL_DIR" "$SITES_DIR" "$LOG_DIR"
chmod 755 "$LOG_DIR"
chmod 755 "$SSL_DIR"

# 让 OpenResty worker 用户能读写配置 / 证书
if id "$NGINX_USER" >/dev/null 2>&1; then
    chown -R "$NGINX_USER:$NGINX_USER" "$SITES_DIR" "$SSL_DIR" "$LUA_DIR" "$LOG_DIR"
fi

# ─── 3. 创建 Lua API 脚本 ──────────────────────────────────
echo ">> 创建 Lua API 脚本..."
tee "$LUA_DIR/api.lua" > /dev/null << 'LUA_EOF'
local cjson = require "cjson"

ngx.header.content_type = "application/json; charset=utf-8"

-- ─── 鉴权:1) IP/CIDR 白名单  2) 可选 token ──────────────────
-- 白名单从环境变量 API_ALLOWED_CLIENTS 读取,逗号分隔。支持:
--   单个 IP:    127.0.0.1
--   CIDR 段:    172.17.0.0/16   (常见 Docker bridge)
--   IPv6 单点:  ::1
local CLIENT_IP = ngx.var.remote_addr or ""

local function ip_to_int(ip)
    local a,b,c,d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return nil end
    return ((tonumber(a)*256 + tonumber(b))*256 + tonumber(c))*256 + tonumber(d)
end

local function ip_in_cidr(ip, cidr)
    local net, bits = cidr:match("^([%d%.]+)/(%d+)$")
    if not net then return ip == cidr end
    local ip_n, net_n = ip_to_int(ip), ip_to_int(net)
    if not ip_n or not net_n then return false end
    bits = tonumber(bits)
    if bits == 0 then return true end
    -- Lua 5.1/LuaJIT 没有按位运算,用除法替代
    local shift = 2 ^ (32 - bits)
    return math.floor(ip_n / shift) == math.floor(net_n / shift)
end

local raw_allow = os.getenv("API_ALLOWED_CLIENTS") or "127.0.0.1,::1"
local allowed = false
for entry in raw_allow:gmatch("[^,%s]+") do
    if CLIENT_IP == entry or ip_in_cidr(CLIENT_IP, entry) then
        allowed = true
        break
    end
end
if not allowed then
    ngx.status = 403
    ngx.say(cjson.encode({
        success = false,
        error   = "Forbidden: client IP not in API_ALLOWED_CLIENTS",
        client  = CLIENT_IP
    }))
    return
end

local EXPECTED_TOKEN = os.getenv("OPENRESTY_API_TOKEN") or ""
if EXPECTED_TOKEN ~= "" then
    local hdr = ngx.req.get_headers()["X-API-Token"]
    if hdr ~= EXPECTED_TOKEN then
        ngx.status = 401
        ngx.say(cjson.encode({success=false, error="Unauthorized"}))
        return
    end
end

local method = ngx.var.request_method
local uri    = ngx.var.uri

local PROXY_CONF = "/usr/local/openresty/nginx/conf/sites/oci-proxy.conf"
local SSL_DIR    = "/usr/local/openresty/nginx/ssl"

-- ─── 工具函数 ───────────────────────────────────────────────
local function ok(message, data)
    ngx.say(cjson.encode({
        success   = true,
        message   = message or "OK",
        data      = data,
        timestamp = ngx.now()
    }))
end

local function fail(status, message, details)
    ngx.status = status or 500
    ngx.say(cjson.encode({
        success   = false,
        error     = message or "operation failed",
        details   = details,
        timestamp = ngx.now()
    }))
end

local function read_file(path)
    local f, err = io.open(path, "r")
    if not f then return nil, err end
    local content = f:read("*a")
    f:close()
    return content
end

local function write_file(path, content)
    local f, err = io.open(path, "w")
    if not f then return false, err end
    f:write(content)
    f:close()
    return true
end

local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

local function read_body_json()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body or body == "" then return nil, "empty body" end
    local ok2, data = pcall(cjson.decode, body)
    if not ok2 then return nil, "JSON parse error: " .. tostring(data) end
    return data
end

-- 执行 shell 命令,返回 (output, success)
local function exec(cmd)
    local handle = io.popen(cmd .. " 2>&1; echo __EXIT:$?")
    if not handle then return "", false end
    local raw = handle:read("*a")
    handle:close()
    local output = raw:gsub("\n?__EXIT:%d+\n?$", "")
    local code   = tonumber(raw:match("__EXIT:(%d+)")) or 1
    return output, (code == 0)
end

-- ─── 路由 ───────────────────────────────────────────────────

-- GET /api/test
if uri == "/api/test" and method == "GET" then
    ok("API working", { server = "Enhanced OpenResty API", version = "4.0" })

-- PUT /api/config
elseif uri == "/api/config" and method == "PUT" then
    local data, err = read_body_json()
    if not data then fail(400, err); return end
    if not data.content or data.content == "" then
        fail(400, "missing 'content'"); return
    end
    local written, write_err = write_file(PROXY_CONF, data.content)
    if not written then
        fail(500, "write config failed", write_err)
    else
        ok("config updated", { path = PROXY_CONF })
    end

-- POST /api/config/test
elseif uri == "/api/config/test" and method == "POST" then
    local data, err = read_body_json()
    if not data then fail(400, err); return end
    if not data.content then fail(400, "missing 'content'"); return end

    local bak_conf  = PROXY_CONF .. ".bak"
    local has_orig  = file_exists(PROXY_CONF)

    if has_orig then exec("cp '" .. PROXY_CONF .. "' '" .. bak_conf .. "'") end
    write_file(PROXY_CONF, data.content)
    local output, is_ok = exec("/usr/local/openresty/bin/openresty -t")
    if has_orig then
        exec("mv '" .. bak_conf .. "' '" .. PROXY_CONF .. "'")
    else
        os.remove(PROXY_CONF)
    end
    if is_ok then ok("config syntax ok", { output = output })
    else fail(400, "config syntax error", output) end

-- POST /api/config/reload
elseif uri == "/api/config/reload" and method == "POST" then
    local output, is_ok = exec("/usr/local/openresty/bin/openresty -s reload")
    if is_ok then ok("reloaded", { output = output })
    else fail(500, "reload failed", output) end

-- POST /api/ssl/certs
elseif uri == "/api/ssl/certs" and method == "POST" then
    local data, err = read_body_json()
    if not data then fail(400, err); return end
    if not data.domain or not data.cert or not data.key then
        fail(400, "missing fields: domain, cert, key"); return
    end
    -- 域名格式校验,防止路径注入
    if data.domain:match("[^%w%.%-_]") then
        fail(400, "invalid domain"); return
    end
    local domain_dir = SSL_DIR .. "/" .. data.domain
    local cert_path  = domain_dir .. "/fullchain.pem"
    local key_path   = domain_dir .. "/privkey.pem"
    if file_exists(cert_path) and not data.force_replace then
        fail(409, "cert exists, set force_replace=true to overwrite"); return
    end
    exec("mkdir -p '" .. domain_dir .. "'")
    local ok1, e1 = write_file(cert_path, data.cert)
    local ok2, e2 = write_file(key_path, data.key)
    if ok1 and ok2 then
        exec("chmod 600 '" .. key_path .. "'")
        exec("chmod 644 '" .. cert_path .. "'")
        ok("cert uploaded", { domain = data.domain, cert_path = cert_path, key_path = key_path })
    else
        fail(500, "cert write failed", (e1 or "") .. " / " .. (e2 or ""))
    end

-- GET /api/ssl/certs
elseif uri == "/api/ssl/certs" and method == "GET" then
    local handle = io.popen("ls -1 '" .. SSL_DIR .. "' 2>/dev/null")
    local certs = {}
    if handle then
        for domain in handle:lines() do
            local cp = SSL_DIR .. "/" .. domain .. "/fullchain.pem"
            if file_exists(cp) then
                table.insert(certs, { domain = domain, cert_path = cp, key_path = SSL_DIR .. "/" .. domain .. "/privkey.pem" })
            end
        end
        handle:close()
    end
    ok("certs", { certs = certs, count = #certs })

-- /api/ssl/certs/{domain}
elseif string.match(uri, "^/api/ssl/certs/") then
    local domain = string.match(uri, "^/api/ssl/certs/([%w%.%-_]+)$")
    if not domain then fail(400, "invalid domain"); return end
    local domain_dir = SSL_DIR .. "/" .. domain
    local cert_path  = domain_dir .. "/fullchain.pem"
    if method == "GET" then
        if file_exists(cert_path) then
            ok("cert info", { domain = domain, cert_path = cert_path,
                              key_path = domain_dir .. "/privkey.pem", exists = true })
        else
            fail(404, "cert not found", domain)
        end
    elseif method == "DELETE" then
        if not file_exists(cert_path) then fail(404, "cert not found", domain); return end
        local output, is_ok = exec("rm -rf '" .. domain_dir .. "'")
        if is_ok then ok("cert deleted", { domain = domain })
        else fail(500, "cert delete failed", output) end
    else
        fail(405, "method not allowed")
    end

else
    fail(404, "endpoint not found", { uri = uri, method = method })
end
LUA_EOF

chown "$NGINX_USER:$NGINX_USER" "$LUA_DIR/api.lua" 2>/dev/null || true
echo ">> Lua API 脚本完成: $LUA_DIR/api.lua"

# ─── 4. 创建 nginx.conf ─────────────────────────────────────
# 不直接覆盖现有 nginx.conf,先备份
if [ -f "$NGINX_CONF" ] && [ ! -f "${NGINX_CONF}.bak.bootstrap" ]; then
    cp "$NGINX_CONF" "${NGINX_CONF}.bak.bootstrap"
    echo ">> 已把原 nginx.conf 备份到 ${NGINX_CONF}.bak.bootstrap"
fi

echo ">> 生成 nginx.conf..."
tee "$NGINX_CONF" > /dev/null << NGINX_EOF
worker_processes auto;
user $NGINX_USER;
error_log $LOG_DIR/error.log warn;
# 注意:pid 路径用 OpenResty 编译默认的位置,这样 \`openresty -s reload\` 才能找到
pid /usr/local/openresty/nginx/logs/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include       mime.types;
    default_type  application/json;

    access_log $LOG_DIR/access.log;

    sendfile        on;
    keepalive_timeout 65;

    # 把 token + 白名单 透传给 Lua,os.getenv 能读到
    env OPENRESTY_API_TOKEN;
    env API_ALLOWED_CLIENTS;

    # ── 管理 API 服务(默认仅 127.0.0.1:8080;Docker 场景可改 API_LISTEN)──
    server {
        listen $API_LISTEN;
        server_name localhost;

        # /api/* 路由交给 Lua,支持 GET/POST/PUT/DELETE
        location ~ ^/api {
            content_by_lua_file /opt/lua/api.lua;
        }

        location = /health {
            return 200 "OK\n";
            add_header Content-Type text/plain;
        }
        location / {
            return 200 "Enhanced OpenResty v4 is running\n";
            add_header Content-Type text/plain;
        }
    }

    # ── 动态代理站点(由 Java 后端写入 sites/*.conf)──────────────
    include /usr/local/openresty/nginx/conf/sites/*.conf;
}
NGINX_EOF

echo ">> nginx.conf 生成完成"

# ─── 5. 创建初始空的占位文件,避免 include 报错 ─────────────────
if [ ! -f "$SITES_DIR/oci-proxy.conf" ]; then
    echo ">> 创建空的代理配置占位文件..."
    touch "$SITES_DIR/oci-proxy.conf"
    chown "$NGINX_USER:$NGINX_USER" "$SITES_DIR/oci-proxy.conf" 2>/dev/null || true
fi

# ─── 6. 测试配置文件 ────────────────────────────────────────────
echo ">> 测试 nginx 配置..."
"$OPENRESTY_BIN" -t

# ─── 7. 启动/重载 OpenResty ─────────────────────────────────────
# 把环境变量统一拼起来,传给 OpenResty 主进程,Lua 才能 os.getenv 读到
ENV_PREFIX="API_ALLOWED_CLIENTS=$API_ALLOWED_CLIENTS"
if [ -n "$API_TOKEN" ]; then
    ENV_PREFIX="$ENV_PREFIX OPENRESTY_API_TOKEN=$API_TOKEN"
fi

PID_FILE="/usr/local/openresty/nginx/logs/nginx.pid"
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo ">> 检测到运行中的 OpenResty,先 stop 再以新环境变量启动(reload 不会刷新 env)..."
    "$OPENRESTY_BIN" -s stop
    sleep 1
    env $ENV_PREFIX "$OPENRESTY_BIN"
else
    echo ">> 启动 OpenResty..."
    env $ENV_PREFIX "$OPENRESTY_BIN"
fi

sleep 1

# ─── 8. 健康检查 ────────────────────────────────────────────────
echo ""
echo ">> 健康检查(本机回环):"
if curl -fsS http://127.0.0.1:${API_LISTEN##*:}/api/test \
        ${API_TOKEN:+-H "X-API-Token: $API_TOKEN"} 2>/dev/null; then
    echo ""
    echo "✅ Enhanced OpenResty v4 部署完成"
else
    echo ""
    echo "⚠️  API 健康检查失败,请检查日志: $LOG_DIR/error.log"
    echo "    - 监听地址: $API_LISTEN"
    echo "    - 白名单:   $API_ALLOWED_CLIENTS"
fi

echo ""
echo "目录结构:"
echo "  Lua API:      $LUA_DIR/api.lua"
echo "  SSL 证书:     $SSL_DIR/{domain}/fullchain.pem"
echo "                $SSL_DIR/{domain}/privkey.pem"
echo "  代理配置:     $SITES_DIR/oci-proxy.conf"
echo "  nginx.conf:   $NGINX_CONF"
echo ""
echo "API 端点(监听 $API_LISTEN,客户端白名单 $API_ALLOWED_CLIENTS):"
echo "  GET    /api/test                  - checkApiAvailable()"
echo "  PUT    /api/config                - updateNginxConfigViaApi()"
echo "  POST   /api/config/test           - testConfig()"
echo "  POST   /api/config/reload         - reloadNginx()"
echo "  POST   /api/ssl/certs             - uploadSslCertificateToOpenResty()"
echo "  GET    /api/ssl/certs             - listAllSslCertificates()"
echo "  GET    /api/ssl/certs/{domain}    - getSslCertificateByDomain()"
echo "  DELETE /api/ssl/certs/{domain}    - deleteSslCertificate()"
if [ -n "$API_TOKEN" ]; then
    echo ""
    echo "🔐 API Token 鉴权已启用。Java 后端调用时需带:"
    echo "   X-API-Token: $API_TOKEN"
    echo "   (在 application.yml 配置: openresty.api.token=...)"
fi
