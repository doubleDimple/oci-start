#!/usr/bin/env bash
# 一键启动：Spring Boot :9856 + Vue Vite :5173
#   ./start-dev.sh           启动（Ctrl+C 同时停）
#   ./start-dev.sh --stop    只停止
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
mkdir -p logs

BACKEND_PORT=9856
VITE_PORT=5173
BACKEND_URL="http://127.0.0.1:${BACKEND_PORT}"
VITE_URL="http://127.0.0.1:${VITE_PORT}"
BACKEND_LOG="$ROOT/logs/backend-dev.log"
VITE_LOG="$ROOT/logs/vite-dev.log"

started_backend=0
started_vite=0
backend_pid=""
vite_pid=""

port_pids() {
  lsof -t -nP -iTCP:"$1" -sTCP:LISTEN 2>/dev/null || true
}

kill_port() {
  local pids
  pids="$(port_pids "$1")"
  if [[ -z "$pids" ]]; then
    return 0
  fi
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true
  sleep 1
  pids="$(port_pids "$1")"
  if [[ -n "$pids" ]]; then
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null || true
  fi
}

http_up() {
  curl -sf -o /dev/null --max-time 2 "$1"
}

wait_http() {
  local url="$1" name="$2" tries="${3:-45}" pid="${4:-}"
  local i=0
  while ! http_up "$url"; do
    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
      echo "${name} 进程已退出"
      return 1
    fi
    i=$((i + 1))
    if [[ "$i" -ge "$tries" ]]; then
      echo "等待 ${name} 超时：${url}"
      return 1
    fi
    sleep 2
  done
}

pick_java() {
  local ver home
  if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
    ver="$("$JAVA_HOME/bin/java" -version 2>&1 | head -n 1 || true)"
    if echo "$ver" | grep -Eq '"1\.8|"11\.|"17\.'; then
      return 0
    fi
    echo "JAVA_HOME=${JAVA_HOME} 不是 JDK 8/11/17，自动改选…"
  fi
  if command -v /usr/libexec/java_home >/dev/null 2>&1; then
    for v in 1.8 17 11; do
      home="$(/usr/libexec/java_home -v "$v" 2>/dev/null || true)"
      if [[ -n "$home" ]]; then
        export JAVA_HOME="$home"
        return 0
      fi
    done
  fi
  echo "未找到 JDK 8/11/17。本项目是 Spring Boot 2.7 + JDK8，不要用 JDK 21/26。"
  exit 1
}

stop_all() {
  echo "停止 :${BACKEND_PORT} / :${VITE_PORT} …"
  kill_port "$VITE_PORT"
  kill_port "$BACKEND_PORT"
}

cleanup() {
  trap - EXIT INT TERM
  if [[ "$started_vite" -eq 1 ]]; then
    kill_port "$VITE_PORT"
  fi
  if [[ "$started_backend" -eq 1 ]]; then
    kill_port "$BACKEND_PORT"
  fi
}

if [[ "${1:-}" == "--stop" ]]; then
  stop_all
  echo "已停止"
  exit 0
fi

if [[ "${1:-}" == "--restart" ]]; then
  stop_all
  sleep 1
fi

pick_java
export PATH="$JAVA_HOME/bin:$PATH"

if ! command -v mvn >/dev/null 2>&1; then
  echo "找不到 mvn，请先安装 Maven 或加入 PATH"
  exit 1
fi
if ! command -v pnpm >/dev/null 2>&1; then
  echo "找不到 pnpm：npm install -g pnpm"
  exit 1
fi

if [[ ! -d "$ROOT/oci-start-web/node_modules" ]]; then
  echo "安装 Vue 依赖…"
  (cd "$ROOT/oci-start-web" && pnpm install --frozen-lockfile=false)
fi

trap cleanup EXIT INT TERM

if http_up "${BACKEND_URL}/login"; then
  echo "后端已在 ${BACKEND_URL}"
else
  if [[ -n "$(port_pids "$BACKEND_PORT")" ]]; then
    echo "端口 ${BACKEND_PORT} 已被占用，但 /login 无响应。先 ./start-dev.sh --stop 再试。"
    exit 1
  fi
  echo "启动后端（JDK $(java -version 2>&1 | head -n 1)）…"
  : >"$BACKEND_LOG"
  nohup mvn -pl oci-server -DskipTests spring-boot:run \
    -Dspring-boot.run.workingDirectory="$ROOT" \
    >>"$BACKEND_LOG" 2>&1 &
  backend_pid="$!"
  started_backend=1
  if ! wait_http "${BACKEND_URL}/login" "后端" 60 "$backend_pid"; then
    echo "---- 后端日志末尾 ----"
    tail -n 40 "$BACKEND_LOG" || true
    exit 1
  fi
  echo "后端就绪  ${BACKEND_URL}  (pid ${backend_pid})"
fi

if http_up "${VITE_URL}/"; then
  echo "Vue 已在 ${VITE_URL}"
else
  if [[ -n "$(port_pids "$VITE_PORT")" ]]; then
    echo "端口 ${VITE_PORT} 已被占用，但页面无响应。先 ./start-dev.sh --stop 再试。"
    exit 1
  fi
  echo "启动 Vue…"
  : >"$VITE_LOG"
  (cd "$ROOT/oci-start-web" && nohup pnpm dev >>"$VITE_LOG" 2>&1) &
  vite_pid="$!"
  started_vite=1
  if ! wait_http "${VITE_URL}/" "Vue" 30 "$vite_pid"; then
    echo "---- Vue 日志末尾 ----"
    tail -n 40 "$VITE_LOG" || true
    exit 1
  fi
  echo "Vue 就绪   ${VITE_URL}  (pid ${vite_pid})"
fi

echo
echo "打开这个地址开发：${VITE_URL}"
echo "登录页（旧 FTL）：${BACKEND_URL}/login"
echo "日志：logs/backend-dev.log  logs/vite-dev.log"
echo "Ctrl+C 停止本次拉起的进程；或 ./start-dev.sh --stop"
echo

if [[ "$(uname -s)" == "Darwin" ]]; then
  open "$VITE_URL" >/dev/null 2>&1 || true
fi

# 只要本次脚本拉起过进程，就挂起直到 Ctrl+C；否则立即退出（复用已有服务）
if [[ "$started_backend" -eq 1 || "$started_vite" -eq 1 ]]; then
  wait
fi
