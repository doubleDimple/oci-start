#!/usr/bin/env bash
# build-dmg.sh — 完整打包脚本 (Spring Boot JAR + JRE + macOS App → DMG)
# 依赖: 完整 Xcode, Maven, curl, unzip
set -euo pipefail

# ────────────────────────── 路径 ──────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_DIR="$REPO_ROOT/oci-server"
MAC_DIR="$SCRIPT_DIR"
BUILD_DIR="$MAC_DIR/.build"
CACHE_DIR="$BUILD_DIR/cache"

APP_NAME="OciStart"
JAR_FINAL_NAME="oci-start-release"
JAVA_VERSION=11          # Temurin 11 LTS — 兼容 Java 8 字节码

XCODEGEN_VER="2.45.4"
# 优先用上次已下载的，其次缓存目录
XCODEGEN_BIN=""
for candidate in \
    "/tmp/xcodegen_bin/xcodegen/bin/xcodegen" \
    "$CACHE_DIR/xcodegen/bin/xcodegen" \
    "$(which xcodegen 2>/dev/null)"; do
    if [ -x "$candidate" ]; then
        XCODEGEN_BIN="$candidate"
        break
    fi
done

# ────────────────────────── 工具检查 ──────────────────────
check_tool() {
    if ! command -v "$1" &>/dev/null; then
        echo "❌ 缺少工具: $1  →  $2"
        exit 1
    fi
}

check_tool mvn  "请安装 Maven: https://maven.apache.org"
check_tool curl "请安装 Xcode Command Line Tools"

if ! xcodebuild -version &>/dev/null 2>&1; then
    echo "❌ 需要完整 Xcode (非仅 CLT)"
    echo "   App Store 安装 Xcode 后运行:"
    echo "   sudo xcode-select --switch /Applications/Xcode.app"
    exit 1
fi

mkdir -p "$BUILD_DIR" "$CACHE_DIR"

# ────────────────────────── Step 1: Build JAR ────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo " Step 1/6  构建 Spring Boot JAR"
echo "══════════════════════════════════════════"
# --also-make 会自动先构建 oci-server 依赖的所有兄弟模块
cd "$REPO_ROOT"
mvn clean install -DskipTests -q --also-make -pl oci-server
JAR_PATH="$SERVER_DIR/target/${JAR_FINAL_NAME}.jar"
if [ ! -f "$JAR_PATH" ]; then
    echo "❌ JAR 未找到: $JAR_PATH"
    exit 1
fi
echo "✅ JAR: $JAR_PATH  ($(du -sh "$JAR_PATH" | cut -f1))"

# ────────────────────────── Step 2: 下载 JRE ─────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo " Step 2/6  下载 JRE (Amazon Corretto $JAVA_VERSION)"
echo "══════════════════════════════════════════"
# 使用 Amazon Corretto（AWS CDN，国内访问稳定）

prepare_jre() {
    local arch_label=$1    # arm64 | x86_64
    local corretto_arch=$2 # aarch64 | x64
    local dest="$CACHE_DIR/jre-$arch_label"

    if [ -f "$dest/bin/java" ]; then
        echo "✅ JRE $arch_label 已缓存，跳过"
        return
    fi

    # 优先：从本机已安装的 JDK 复制（避免网络下载）
    local sys_home
    sys_home=$(/usr/libexec/java_home -v "$JAVA_VERSION" -a "$arch_label" 2>/dev/null || true)
    if [ -n "$sys_home" ] && [ -f "$sys_home/bin/java" ]; then
        echo "📋 使用本机 JDK $arch_label: $sys_home"
        cp -R "$sys_home" "$dest"
        echo "✅ JRE $arch_label: $("$dest/bin/java" -version 2>&1 | head -1)"
        return
    fi

    # 备选：从本机任意版本 JDK 复制（只要 >= 8）
    sys_home=$(/usr/libexec/java_home -a "$arch_label" 2>/dev/null || true)
    if [ -n "$sys_home" ] && [ -f "$sys_home/bin/java" ]; then
        echo "📋 使用本机 JDK $arch_label ($(basename "$sys_home")): $sys_home"
        cp -R "$sys_home" "$dest"
        echo "✅ JRE $arch_label: $("$dest/bin/java" -version 2>&1 | head -1)"
        return
    fi

    # 最后：网络下载 Amazon Corretto
    echo "⬇️  下载 JRE $arch_label (Amazon Corretto $JAVA_VERSION) ..."
    local url="https://corretto.aws/downloads/latest/amazon-corretto-${JAVA_VERSION}-${corretto_arch}-macos-jdk.tar.gz"
    local tgz="$CACHE_DIR/jre-$arch_label.tar.gz"
    curl -L --progress-bar -o "$tgz" "$url"

    local tmp_extract="$CACHE_DIR/jre-${arch_label}-extract"
    rm -rf "$tmp_extract" && mkdir -p "$tmp_extract"
    tar -xzf "$tgz" -C "$tmp_extract"
    rm -f "$tgz"

    local java_bin
    java_bin=$(find "$tmp_extract" -name "java" -path "*/bin/java" -type f | head -1)
    if [ -z "$java_bin" ]; then
        echo "❌ 找不到 java 可执行文件，请手动下载 JRE 并放到: $dest"
        exit 1
    fi
    local home_dir
    home_dir="$(dirname "$(dirname "$java_bin")")"
    rm -rf "$dest"
    mv "$home_dir" "$dest"
    rm -rf "$tmp_extract"
    echo "✅ JRE $arch_label: $("$dest/bin/java" -version 2>&1 | head -1)"
}

prepare_jre "arm64"  "aarch64"
prepare_jre "x86_64" "x64"

# ────────────────────────── Step 2.5: 生成图标 ───────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo " Step 2.5  生成应用图标"
echo "══════════════════════════════════════════"
cd "$MAC_DIR"
swift generate-icon.swift "OciStart/Assets.xcassets/AppIcon.appiconset"

# ────────────────────────── Step 3: xcodegen ─────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo " Step 3/6  生成 Xcode 工程"
echo "══════════════════════════════════════════"

if [ -z "$XCODEGEN_BIN" ]; then
    echo "❌ 找不到 xcodegen，请手动下载后放到以下任一位置："
    echo "   /tmp/xcodegen_bin/xcodegen/bin/xcodegen"
    echo "   $CACHE_DIR/xcodegen/bin/xcodegen"
    echo "   下载地址: https://github.com/yonaskolb/XcodeGen/releases/tag/$XCODEGEN_VER"
    exit 1
fi

cd "$MAC_DIR"
"$XCODEGEN_BIN" generate --project "$MAC_DIR" --quiet
echo "✅ Xcode 工程已生成"

# ────────────────────────── Step 4: 编译 App ─────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo " Step 4/6  编译 macOS App (arm64 + x86_64)"
echo "══════════════════════════════════════════"

ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
rm -rf "$ARCHIVE_PATH"

xcodebuild archive \
    -project  "$MAC_DIR/$APP_NAME.xcodeproj" \
    -scheme   "$APP_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    2>&1 | grep -E "error:|SUCCEEDED|FAILED" | head -20 || true

echo "✅ Archive 完成"

# ────────────────────────── Step 5: 组装 App Bundle ──────────────────────
echo ""
echo "══════════════════════════════════════════"
echo " Step 5/6  注入 JAR & JRE 到 App Bundle"
echo "══════════════════════════════════════════"

APP_IN_ARCHIVE="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
STAGED_APP="$BUILD_DIR/$APP_NAME.app"
rm -rf "$STAGED_APP"
cp -R "$APP_IN_ARCHIVE" "$STAGED_APP"

PLUGINS_DIR="$STAGED_APP/Contents/PlugIns"
RESOURCES_DIR="$STAGED_APP/Contents/Resources"
mkdir -p "$PLUGINS_DIR" "$RESOURCES_DIR"

# 注入 JRE
cp -R "$CACHE_DIR/jre-arm64"  "$PLUGINS_DIR/jre-arm64"
cp -R "$CACHE_DIR/jre-x86_64" "$PLUGINS_DIR/jre-x86_64"
chmod +x "$PLUGINS_DIR/jre-arm64/bin/java"
chmod +x "$PLUGINS_DIR/jre-x86_64/bin/java"
echo "✅ JRE 已注入 ($(du -sh "$PLUGINS_DIR" | cut -f1))"

# 注入 JAR
cp "$JAR_PATH" "$RESOURCES_DIR/server.jar"
echo "✅ server.jar 已注入 ($(du -sh "$RESOURCES_DIR/server.jar" | cut -f1))"

echo "📦 App bundle 总大小: $(du -sh "$STAGED_APP" | cut -f1)"

# ────────────────────────── Step 6: 制作 DMG ─────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo " Step 6/6  制作 DMG"
echo "══════════════════════════════════════════"

DMG_PATH="$BUILD_DIR/${APP_NAME}.dmg"
rm -f "$DMG_PATH"

if command -v create-dmg &>/dev/null; then
    # 优先用 create-dmg，界面更美观
    create-dmg \
        --volname   "$APP_NAME" \
        --window-pos  200 120 \
        --window-size 540 380 \
        --icon-size 128 \
        --icon "$APP_NAME.app" 130 180 \
        --hide-extension "$APP_NAME.app" \
        --app-drop-link  400 180 \
        "$DMG_PATH" \
        "$STAGED_APP" \
        2>/dev/null || true
else
    # 使用系统自带 hdiutil
    STAGE_DMG="$BUILD_DIR/dmg_stage"
    rm -rf "$STAGE_DMG"
    mkdir -p "$STAGE_DMG"
    cp -R "$STAGED_APP" "$STAGE_DMG/"
    ln -s /Applications "$STAGE_DMG/Applications"

    hdiutil create \
        -volname   "$APP_NAME" \
        -srcfolder "$STAGE_DMG" \
        -ov \
        -format    UDZO \
        "$DMG_PATH"
    rm -rf "$STAGE_DMG"
fi

echo ""
echo "════════════════════════════════════════════════════"
echo " ✅ 打包完成！"
echo "    DMG:  $DMG_PATH"
echo "    大小: $(du -sh "$DMG_PATH" | cut -f1)"
echo "════════════════════════════════════════════════════"
echo ""
echo "💡 App 数据目录（更新不丢失）:"
echo "   ~/Library/Application Support/OciStart/"
