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

# ────────────────────────── 工具检查 ──────────────────────
check_tool() {
    if ! command -v "$1" &>/dev/null; then
        echo "❌ 缺少工具: $1  →  $2"
        exit 1
    fi
}

check_tool mvn  "请安装 Maven: https://maven.apache.org"
check_tool curl "请安装 Xcode Command Line Tools"
check_tool unzip "请安装 unzip（系统自带）"

if ! xcodebuild -version &>/dev/null 2>&1; then
    echo "❌ 需要完整 Xcode (非仅 CLT)"
    echo "   App Store 安装 Xcode 后运行:"
    echo "   sudo xcode-select --switch /Applications/Xcode.app"
    exit 1
fi

mkdir -p "$BUILD_DIR" "$CACHE_DIR"

# ────────────────────────── 版本号（每次打包自动 +patch） ──────────────────
# 读 project.yml 的 MARKETING_VERSION / CURRENT_PROJECT_VERSION，写回 yml + Info.plist。
# 环境变量：
#   SKIP_VERSION_BUMP=1   不递增，沿用当前版本
#   VERSION=1.2.0         指定对外版本（不再自动 +patch），构建号仍 +1
#   BUMP=patch|minor|major  默认 patch（1.0.0→1.0.1 / 1.0.0→1.1.0 / 1.0.0→2.0.0）
APP_MARKETING_VERSION=""
APP_BUILD_NUMBER=""

bump_app_version() {
    local yml="$MAC_DIR/project.yml"
    local plist="$MAC_DIR/OciStart/Info.plist"
    if [ ! -f "$yml" ]; then
        echo "❌ 找不到 $yml"
        exit 1
    fi

    local marketing build
    marketing=$(grep -E '[[:space:]]*MARKETING_VERSION:' "$yml" | head -1 \
        | sed -E 's/.*"([^"]+)".*/\1/' | tr -d '[:space:]')
    build=$(grep -E '[[:space:]]*CURRENT_PROJECT_VERSION:' "$yml" | head -1 \
        | sed -E 's/.*"([^"]+)".*/\1/' | tr -d '[:space:]')
    if [ -z "$marketing" ]; then marketing="1.0.0"; fi
    if [ -z "$build" ] || ! [[ "$build" =~ ^[0-9]+$ ]]; then build="0"; fi

    local old_marketing="$marketing"
    local old_build="$build"

    if [ "${SKIP_VERSION_BUMP:-0}" = "1" ]; then
        echo "ℹ️  SKIP_VERSION_BUMP=1，保持版本 $marketing ($build)"
    elif [ -n "${VERSION:-}" ]; then
        marketing="$VERSION"
        build=$((build + 1))
        echo "📌 指定版本 VERSION=$marketing，构建号 $old_build → $build"
    else
        local maj min pat
        maj=$(echo "$marketing" | cut -d. -f1)
        min=$(echo "$marketing" | cut -d. -f2)
        pat=$(echo "$marketing" | cut -d. -f3)
        maj=${maj:-0}; min=${min:-0}; pat=${pat:-0}
        [[ "$maj" =~ ^[0-9]+$ ]] || maj=0
        [[ "$min" =~ ^[0-9]+$ ]] || min=0
        [[ "$pat" =~ ^[0-9]+$ ]] || pat=0
        case "${BUMP:-patch}" in
            major) maj=$((maj + 1)); min=0; pat=0 ;;
            minor) min=$((min + 1)); pat=0 ;;
            patch|*) pat=$((pat + 1)) ;;
        esac
        marketing="${maj}.${min}.${pat}"
        build=$((build + 1))
        echo "📈 版本自动递增: $old_marketing ($old_build) → $marketing ($build)  [BUMP=${BUMP:-patch}]"
    fi

    # project.yml：settings + info.properties
    # macOS sed -i ''；兼容 GNU sed
    local sed_i=(sed -i)
    if sed --version >/dev/null 2>&1; then
        sed_i=(sed -i)
    else
        sed_i=(sed -i '')
    fi
    "${sed_i[@]}" -E "s/(MARKETING_VERSION:[[:space:]]*)\"[^\"]+\"/\1\"${marketing}\"/" "$yml"
    "${sed_i[@]}" -E "s/(CURRENT_PROJECT_VERSION:[[:space:]]*)\"[^\"]+\"/\1\"${build}\"/" "$yml"
    "${sed_i[@]}" -E "s/(CFBundleShortVersionString:[[:space:]]*)\"[^\"]+\"/\1\"${marketing}\"/" "$yml"
    "${sed_i[@]}" -E "s/(CFBundleVersion:[[:space:]]*)\"[^\"]+\"/\1\"${build}\"/" "$yml"

    if [ -f "$plist" ]; then
        if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
            /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${marketing}" "$plist" 2>/dev/null \
                || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${marketing}" "$plist"
            /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${build}" "$plist" 2>/dev/null \
                || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${build}" "$plist"
        else
            "${sed_i[@]}" -E "/CFBundleShortVersionString/{n;s#<string>[^<]*</string>#<string>${marketing}</string>#;}" "$plist"
            "${sed_i[@]}" -E "/CFBundleVersion/{n;s#<string>[^<]*</string>#<string>${build}</string>#;}" "$plist"
        fi
    fi

    APP_MARKETING_VERSION="$marketing"
    APP_BUILD_NUMBER="$build"
    echo "✅ 打包版本: v${marketing} (build ${build})"
    echo "   已写入: project.yml + Info.plist（随后 xcodegen 会同步进工程）"
}

echo ""
echo "══════════════════════════════════════════"
echo " Step 0/6  更新版本号"
echo "══════════════════════════════════════════"
bump_app_version

# 解析 / 自动下载 xcodegen（路径写入 XCODEGEN_BIN，日志打 stderr/stdout 正常显示）
XCODEGEN_BIN=""
for candidate in \
    "/tmp/xcodegen_bin/xcodegen/bin/xcodegen" \
    "$CACHE_DIR/xcodegen/bin/xcodegen" \
    "$(command -v xcodegen 2>/dev/null || true)"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
        XCODEGEN_BIN="$candidate"
        break
    fi
done

if [ -z "$XCODEGEN_BIN" ]; then
    echo "⬇️  下载 XcodeGen $XCODEGEN_VER …"
    zip="$CACHE_DIR/xcodegen.zip"
    extract="$CACHE_DIR/xcodegen_extract"
    rm -rf "$extract" "$CACHE_DIR/xcodegen"
    mkdir -p "$extract"
    curl -L --progress-bar -o "$zip" \
        "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VER}/xcodegen.zip"
    unzip -q "$zip" -d "$extract"
    rm -f "$zip"

    if [ -x "$extract/bin/xcodegen" ]; then
        mv "$extract" "$CACHE_DIR/xcodegen"
    elif [ -x "$extract/xcodegen/bin/xcodegen" ]; then
        mv "$extract/xcodegen" "$CACHE_DIR/xcodegen"
        rm -rf "$extract"
    else
        found=$(find "$extract" -name xcodegen -type f | head -1 || true)
        if [ -n "$found" ]; then
            mkdir -p "$CACHE_DIR/xcodegen/bin"
            cp "$found" "$CACHE_DIR/xcodegen/bin/xcodegen"
            chmod +x "$CACHE_DIR/xcodegen/bin/xcodegen"
            rm -rf "$extract"
        else
            echo "❌ XcodeGen 压缩包结构异常"
            exit 1
        fi
    fi

    if [ ! -x "$CACHE_DIR/xcodegen/bin/xcodegen" ]; then
        echo "❌ XcodeGen 安装失败"
        exit 1
    fi
    XCODEGEN_BIN="$CACHE_DIR/xcodegen/bin/xcodegen"
    echo "✅ XcodeGen: $($XCODEGEN_BIN --version 2>/dev/null || echo $XCODEGEN_VER)"
fi

# ────────────────────────── Maven settings ─────────────────────────────
# IDEA / 本机习惯使用 openSource/settings.xml（独立 localRepository），
# 终端默认会读 ~/.m2/settings.xml，镜像不一致会导致依赖解析失败。
# 优先级: MAVEN_SETTINGS 环境变量 > 常见路径探测
MVN_SETTINGS_ARGS=()
resolve_maven_settings() {
    local candidates=(
        "${MAVEN_SETTINGS:-}"
        "$HOME/IdeaProjects/openSource/settings.xml"
        "/Users/admin/IdeaProjects/openSouce/settings.xml"
        "$REPO_ROOT/../settings.xml"
        "$REPO_ROOT/settings.xml"
    )
    local p
    for p in "${candidates[@]}"; do
        if [ -n "$p" ] && [ -f "$p" ]; then
            echo "$p"
            return 0
        fi
    done
    return 1
}
if MVN_SETTINGS_FILE="$(resolve_maven_settings)"; then
    MVN_SETTINGS_ARGS=(-s "$MVN_SETTINGS_FILE")
    echo "📦 Maven settings: $MVN_SETTINGS_FILE"
else
    echo "⚠️  未找到项目 settings.xml，使用 Maven 默认 (~/.m2/settings.xml)"
    echo "   可设置: export MAVEN_SETTINGS=/path/to/settings.xml"
fi

# ────────────────────────── Step 1: Build JAR ────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo " Step 1/6  构建 Spring Boot JAR"
echo "══════════════════════════════════════════"
# --also-make 会自动先构建 oci-server 依赖的所有兄弟模块
cd "$REPO_ROOT"
mvn "${MVN_SETTINGS_ARGS[@]}" clean install -DskipTests -q --also-make -pl oci-server
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

# ────────────────────────── Step 2.1: JRE 瘦身 ───────────────────────────
# jlink 精简运行时；失败时退回删除 man/demo/src.zip 等非运行时文件。
# 跳过：SKIP_JLINK=1 ./build-dmg.sh
# 仅打本机架构：HOST_ARCH_ONLY=1 ./build-dmg.sh

echo ""
echo "══════════════════════════════════════════"
echo " Step 2.1  JRE 瘦身 (jlink)"
echo "══════════════════════════════════════════"

# Spring Boot 2.x / H2 / JDBC / JSch / 常见反射所需模块（可按需增删）
JLINK_MODULES="java.base,java.compiler,java.datatransfer,java.desktop,java.instrument,java.logging,java.management,java.management.rmi,java.naming,java.net.http,java.prefs,java.rmi,java.scripting,java.security.jgss,java.security.sasl,java.sql,java.sql.rowset,java.transaction.xa,java.xml,java.xml.crypto,jdk.charsets,jdk.crypto.cryptoki,jdk.crypto.ec,jdk.httpserver,jdk.jfr,jdk.localedata,jdk.management,jdk.management.agent,jdk.net,jdk.unsupported,jdk.xml.dom,jdk.zipfs"

strip_jre_files() {
    local home=$1
    rm -rf \
        "$home/man" \
        "$home/demo" \
        "$home/sample" \
        "$home/include" \
        "$home/lib/src.zip" \
        "$home/lib/*.diz" \
        2>/dev/null || true
    # 未 jlink 时保留 jmods 以便下次瘦身；已 jlink 的 runtime 本身无 jmods
}

slim_jre() {
    local arch_label=$1
    local home="$CACHE_DIR/jre-$arch_label"
    local marker="$home/.oci-jlink-v1"
    local before after

    if [ ! -f "$home/bin/java" ]; then
        echo "⚠️  跳过瘦身 $arch_label：未找到 $home/bin/java"
        return
    fi

    if [ -f "$marker" ]; then
        echo "✅ JRE $arch_label 已瘦身 ($(du -sh "$home" | cut -f1))，跳过"
        return
    fi

    before=$(du -sk "$home" | cut -f1)

    if [ "${SKIP_JLINK:-0}" = "1" ]; then
        echo "ℹ️  SKIP_JLINK=1，仅删除非运行时文件 ($arch_label)"
        strip_jre_files "$home"
        touch "$marker"
        after=$(du -sk "$home" | cut -f1)
        echo "✅ JRE $arch_label: ${before}KB → ${after}KB"
        return
    fi

    local jlink="$home/bin/jlink"
    local jmods="$home/jmods"
    if [ ! -x "$jlink" ] || [ ! -d "$jmods" ]; then
        echo "⚠️  $arch_label 无 jlink/jmods（可能是精简 JRE），仅做文件级清理"
        strip_jre_files "$home"
        touch "$marker"
        after=$(du -sk "$home" | cut -f1)
        echo "✅ JRE $arch_label: ${before}KB → ${after}KB"
        return
    fi

    local slim="$CACHE_DIR/jre-${arch_label}-slim"
    rm -rf "$slim"
    echo "🔧 jlink → $arch_label …"
    set +e
    "$jlink" \
        --module-path "$jmods" \
        --add-modules "$JLINK_MODULES" \
        --strip-debug \
        --no-man-pages \
        --no-header-files \
        --compress=2 \
        --output "$slim" 2>"$BUILD_DIR/jlink-${arch_label}.log"
    local jl=$?
    set -e

    if [ $jl -ne 0 ] || [ ! -x "$slim/bin/java" ]; then
        echo "⚠️  jlink 失败 ($arch_label)，日志: $BUILD_DIR/jlink-${arch_label}.log"
        rm -rf "$slim"
        strip_jre_files "$home"
        touch "$marker"
        after=$(du -sk "$home" | cut -f1)
        echo "✅ 回退文件清理 $arch_label: ${before}KB → ${after}KB"
        return
    fi

    # 冒烟：能打印版本即认为 runtime 可用
    if ! "$slim/bin/java" -version &>/dev/null; then
        echo "⚠️  瘦身后 java 不可用，回退 ($arch_label)"
        rm -rf "$slim"
        strip_jre_files "$home"
        touch "$marker"
        return
    fi

    rm -rf "$home"
    mv "$slim" "$home"
    touch "$marker"
    after=$(du -sk "$home" | cut -f1)
    echo "✅ jlink $arch_label: ${before}KB → ${after}KB  ($("$home/bin/java" -version 2>&1 | head -1))"
}

slim_jre "arm64"
slim_jre "x86_64"

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

cd "$MAC_DIR"
echo "   使用: $XCODEGEN_BIN"
"$XCODEGEN_BIN" generate --project "$MAC_DIR" --quiet
echo "✅ Xcode 工程已生成"

# ────────────────────────── Step 4: 编译 App ─────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo " Step 4/6  编译 macOS App (arm64 + x86_64)"
echo "══════════════════════════════════════════"

ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
rm -rf "$ARCHIVE_PATH"

# 支持系统：macOS Big Sur 11.7.11+（deploymentTarget 11.0）
# 注意：set -e 下必须保留 xcodebuild 的真实退出码，禁止 `|| true` 吞失败
set +e
xcodebuild archive \
    -project  "$MAC_DIR/$APP_NAME.xcodeproj" \
    -scheme   "$APP_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    2>&1 | tee "$BUILD_DIR/xcodebuild-archive.log" | grep -E "error:|warning:|SUCCEEDED|FAILED" | head -40
XCODE_STATUS=${PIPESTATUS[0]}
set -e

if [ "$XCODE_STATUS" -ne 0 ]; then
    echo "❌ xcodebuild archive 失败 (exit=$XCODE_STATUS)"
    echo "   完整日志: $BUILD_DIR/xcodebuild-archive.log"
    exit "$XCODE_STATUS"
fi

if [ ! -d "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" ]; then
    echo "❌ Archive 产物不存在: $ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
    exit 1
fi

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

RESOURCES_DIR="$STAGED_APP/Contents/Resources"
mkdir -p "$RESOURCES_DIR"

# 注入 JRE 到 Resources（不要放 PlugIns：否则 codesign 把 jre 当插件子包，注入后签名必坏）
HOST_ARCH="$(uname -m)"
if [ "$HOST_ARCH" = "arm64" ]; then
    HOST_JRE_ARCH="arm64"
else
    HOST_JRE_ARCH="x86_64"
fi

inject_jre() {
    local arch=$1
    local src="$CACHE_DIR/jre-$arch"
    local dest="$RESOURCES_DIR/jre-$arch"
    if [ ! -x "$src/bin/java" ]; then
        echo "❌ 缺少 JRE: $src"
        exit 1
    fi
    rm -rf "$dest"
    cp -R "$src" "$dest"
    # legal/ 等文本目录会干扰 codesign 子组件识别，运行不需要
    rm -rf "$dest/legal" 2>/dev/null || true
    chmod +x "$dest/bin/"* 2>/dev/null || true
    chmod +x "$dest/lib/jspawnhelper" 2>/dev/null || true
}

if [ "${HOST_ARCH_ONLY:-0}" = "1" ]; then
    echo "ℹ️  HOST_ARCH_ONLY=1，仅注入 $HOST_JRE_ARCH → Resources/"
    inject_jre "$HOST_JRE_ARCH"
else
    inject_jre "arm64"
    inject_jre "x86_64"
fi
echo "✅ JRE 已注入 Resources ($(du -sh "$RESOURCES_DIR"/jre-* 2>/dev/null | awk '{s+=$1} END{print s}') )"

# 注入 JAR
cp "$JAR_PATH" "$RESOURCES_DIR/server.jar"
echo "✅ server.jar 已注入 ($(du -sh "$RESOURCES_DIR/server.jar" | cut -f1))"

# 注入后必须重签，否则 Finder 会提示「已损坏 / 打不开」
echo ""
echo "🔏  注入后重新 ad-hoc 签名…"
ENTITLEMENTS_FILE="$MAC_DIR/OciStart/OciStart.entitlements"
RUNTIME_ENTS="$BUILD_DIR/runtime.entitlements"
cat > "$RUNTIME_ENTS" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<false/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.network.server</key>
	<true/>
	<key>com.apple.security.cs.disable-library-validation</key>
	<true/>
	<key>com.apple.security.cs.allow-jit</key>
	<true/>
	<key>com.apple.security.cs.allow-unsigned-executable-memory</key>
	<true/>
	<key>com.apple.security.cs.allow-dyld-environment-variables</key>
	<true/>
</dict>
</plist>
EOF

# 清掉 archive 旧签
rm -rf "$STAGED_APP/Contents/_CodeSignature"

# 嵌套 Mach-O（JRE / Frameworks）先签
sign_machos() {
    local root=$1
    [ -d "$root" ] || return 0
    find "$root" -type f 2>/dev/null | while read -r f; do
        case "$(file -b "$f" 2>/dev/null || true)" in
            *Mach-O*)
                codesign --force --sign - --options runtime \
                    --entitlements "$RUNTIME_ENTS" "$f" 2>/dev/null || true
                ;;
        esac
    done
}
sign_machos "$RESOURCES_DIR"
sign_machos "$STAGED_APP/Contents/Frameworks"

codesign --force --sign - --options runtime \
    --entitlements "$RUNTIME_ENTS" \
    "$STAGED_APP/Contents/MacOS/$APP_NAME"

codesign --force --sign - --options runtime \
    --entitlements "$RUNTIME_ENTS" \
    "$STAGED_APP"

if codesign --verify --verbose=2 "$STAGED_APP" 2>&1; then
    echo "✅ 签名校验通过"
else
    echo "⚠️  签名校验未完全通过（本机 ad-hoc 仍可能可开）；请用 xattr -cr 后 open 试"
fi

echo "📦 App bundle 总大小: $(du -sh "$STAGED_APP" | cut -f1)"

# ────────────────────────── Step 6: 制作 DMG ─────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo " Step 6/6  制作 DMG"
echo "══════════════════════════════════════════"

# 带版本号的 DMG，并保留 OciStart.dmg 副本方便习惯路径
VER_TAG="${APP_MARKETING_VERSION:-unknown}"
DMG_PATH="$BUILD_DIR/${APP_NAME}-${VER_TAG}.dmg"
DMG_LATEST="$BUILD_DIR/${APP_NAME}.dmg"
rm -f "$DMG_PATH" "$DMG_LATEST"

# 统一暂存：App + 首次打开脚本（TG 等渠道无 Developer 认证时用）
STAGE_DMG="$BUILD_DIR/dmg_stage"
rm -rf "$STAGE_DMG"
mkdir -p "$STAGE_DMG"
cp -R "$STAGED_APP" "$STAGE_DMG/"
ln -s /Applications "$STAGE_DMG/Applications"

OPEN_HELPER_SRC="$MAC_DIR/packaging/首次打开.command"
OPEN_HELPER_DST="$STAGE_DMG/首次打开.command"
if [ -f "$OPEN_HELPER_SRC" ]; then
    cp "$OPEN_HELPER_SRC" "$OPEN_HELPER_DST"
    chmod +x "$OPEN_HELPER_DST"
else
    # 兜底：脚本缺失时内联生成
    cat > "$OPEN_HELPER_DST" <<'HELPER'
#!/bin/bash
set -euo pipefail
APP="/Applications/OciStart.app"
if [ ! -d "$APP" ]; then
  APP="$(cd "$(dirname "$0")" && pwd)/OciStart.app"
fi
if [ ! -d "$APP" ]; then
  osascript -e 'display dialog "请先把 OciStart.app 拖到应用程序，再双击本脚本。" buttons {"好"} default button 1 with title "OCI Start"'
  exit 1
fi
xattr -cr "$APP" 2>/dev/null || true
chmod +x "$APP/Contents/MacOS/OciStart" 2>/dev/null || true
open "$APP"
HELPER
    chmod +x "$OPEN_HELPER_DST"
fi

cat > "$STAGE_DMG/使用说明.txt" <<'EOF'
OCI Start — 安装说明
========================================

本包未做 Apple 开发者公证（免费分发），下载后系统会拦截，
请按照以下方式操作

正确步骤：
  1. 打开 DMG
  2. 把 OciStart.app 拖到「应用程序」(Applications)
  3. 双击「首次打开.command」
     （会自动清除隔离标记并启动；首次可能提示「无法验证开发者」
      → 系统设置 → 隐私与安全性 → 仍要打开，或终端见下方）

若双击 App 仍提示「无法打开」，在「终端」执行一行即可：
  xattr -cr /Applications/OciStart.app && open /Applications/OciStart.app

之后日常可直接从启动台 / 应用程序打开，一般无需再清隔离。
EOF

if command -v create-dmg &>/dev/null; then
    # 优先用 create-dmg，界面更美观
    create-dmg \
        --volname   "$APP_NAME" \
        --window-pos  200 120 \
        --window-size 600 420 \
        --icon-size 110 \
        --icon "$APP_NAME.app" 120 160 \
        --hide-extension "$APP_NAME.app" \
        --app-drop-link  380 160 \
        --icon "首次打开.command" 120 300 \
        --icon "使用说明.txt" 380 300 \
        "$DMG_PATH" \
        "$STAGE_DMG" \
        2>/dev/null || true
fi

# create-dmg 失败或未安装时走 hdiutil
if [ ! -f "$DMG_PATH" ]; then
    hdiutil create \
        -volname   "$APP_NAME" \
        -srcfolder "$STAGE_DMG" \
        -ov \
        -format    UDZO \
        "$DMG_PATH"
fi
rm -rf "$STAGE_DMG"

# 同步一份无版本后缀的路径，兼容旧文档
if [ -f "$DMG_PATH" ]; then
    cp -f "$DMG_PATH" "$DMG_LATEST"
fi

echo ""
echo "════════════════════════════════════════════════════"
echo " ✅ 打包完成！"
echo "    版本: v${APP_MARKETING_VERSION} (build ${APP_BUILD_NUMBER})"
echo "    DMG:  $DMG_PATH"
echo "    副本: $DMG_LATEST"
echo "    大小: $(du -sh "$DMG_PATH" | cut -f1)"
echo "════════════════════════════════════════════════════"
echo ""
echo "💡 通过 TG 发给别人时，请告知对方："
echo "   1. 把 OciStart.app 拖到「应用程序」"
echo "   2. 双击 DMG 里的「首次打开.command」（清隔离并启动）"
echo "   或终端一行: xattr -cr /Applications/OciStart.app && open /Applications/OciStart.app"
echo ""
echo "💡 App 数据目录（更新不丢失）:"
echo "   ~/Library/Application Support/OciStart/"
echo ""
echo "📦 环境变量:"
echo "   SKIP_JLINK=1        跳过 jlink，仅删 man/demo/src"
echo "   HOST_ARCH_ONLY=1    仅打包本机 CPU 架构的 JRE"
echo "   SKIP_VERSION_BUMP=1 本次不改版本号"
echo "   VERSION=1.2.0       指定对外版本（构建号仍 +1）"
echo "   BUMP=patch|minor|major  默认 patch（1.0.0→1.0.1）"
echo ""
echo "🔏 可选：Developer ID + 公证后，对方可直接双击（需付费开发者账号）"
echo "   详见 oci-start-mac/README.md「签名与公证」"
