#!/bin/bash
# 通过 Telegram / 网盘分发时，macOS 会给 App 打隔离标记；
# ad-hoc 签名没有「仍要打开」入口，必须先清隔离再启动。
# 用法：把 OciStart.app 拖到「应用程序」后，双击本脚本。

set -euo pipefail

APP_NAME="OciStart.app"
CANDIDATES=(
  "/Applications/${APP_NAME}"
  "$HOME/Applications/${APP_NAME}"
  "$(cd "$(dirname "$0")" && pwd)/${APP_NAME}"
)

APP=""
for p in "${CANDIDATES[@]}"; do
  if [ -d "$p" ]; then
    APP="$p"
    break
  fi
done

if [ -z "$APP" ]; then
  osascript -e 'display dialog "未找到 OciStart.app。\n\n请先把 OciStart.app 拖到「应用程序」文件夹，再双击本脚本。" buttons {"好"} default button 1 with icon stop with title "OCI Start"'
  exit 1
fi

# 清除隔离（TG/网盘下载几乎必有）
xattr -cr "$APP" 2>/dev/null || true
# 保险：主程序与内嵌 Java 执行位
chmod +x "$APP/Contents/MacOS/OciStart" 2>/dev/null || true
chmod +x "$APP/Contents/Resources"/jre-*/bin/* 2>/dev/null || true
chmod +x "$APP/Contents/Resources"/jre-*/lib/jspawnhelper 2>/dev/null || true

open "$APP"
exit 0
