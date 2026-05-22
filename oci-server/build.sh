#!/bin/bash

# 设置变量
REGISTRY="${REGISTRY:-docker.io}"
NAMESPACE="${NAMESPACE:-lovele}"
IMAGE_NAME="${IMAGE_NAME:-oci-start}"
IMAGE_REPO="${IMAGE_REPO:-${NAMESPACE}/${IMAGE_NAME}}"
VERSION="${1:-${VERSION:-5.7.70}}"
APPLICATION_YML="src/main/resources/application.yml"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: VERSION must be in x.y.z format, got: ${VERSION}"
    echo "Usage: VERSION=5.7.70 ./build.sh"
    echo "   or: ./build.sh 5.7.70"
    exit 1
fi

if [ ! -f "$APPLICATION_YML" ]; then
    echo "Error: ${APPLICATION_YML} not found. Please run this script from oci-server directory."
    exit 1
fi

echo "Syncing application version..."
sed -i.bak -E "s/^([[:space:]]*)version:[[:space:]]*.*/\\1version: ${VERSION}/" "$APPLICATION_YML"
sed -i.bak -E "s/^([[:space:]]*)ssh-version:[[:space:]]*.*/\\1ssh-version: v-${VERSION}/" "$APPLICATION_YML"
rm -f "${APPLICATION_YML}.bak"

echo "======================================"
echo "Starting build process..."
echo "Image: ${IMAGE_REPO}"
echo "Version: ${VERSION}"
echo "======================================"

# 确保使用 buildx
echo "Setting up buildx..."
docker buildx create --name ociStartBuilder --use || echo "Builder already exists"
docker buildx inspect --bootstrap

# 定义计时器函数
show_timer() {
    local start_time=$1
    while true; do
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        printf "\r运行时间: %02d:%02d:%02d" $((elapsed/3600)) $((elapsed%3600/60)) $((elapsed%60))
        sleep 1
    done
}

echo "======================================"
echo "Building multi-platform image..."
echo "Platforms: linux/amd64, linux/arm64"
echo "Tags: ${VERSION}, latest"
echo "======================================"

# 启动计时器（在后台运行）
start_time=$(date +%s)
show_timer $start_time &
timer_pid=$!

# 执行构建命令
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    -t ${IMAGE_REPO}:${VERSION} \
    -t ${IMAGE_REPO}:latest \
    --push . \
    --progress=plain

# 获取构建命令的退出状态
build_status=$?

# 停止 计时器
kill $timer_pid
wait $timer_pid 2>/dev/null

# 打印最终运行时间
end_time=$(date +%s)
total_elapsed=$((end_time - start_time))
echo -e "\n总运行时间: $(printf "%02d:%02d:%02d" $((total_elapsed/3600)) $((total_elapsed%3600/60)) $((total_elapsed%60)))"

# 检查构建结果
if [ $build_status -eq 0 ]; then
    echo "======================================"
    echo "Build and push successful!"
    echo "Image: ${IMAGE_REPO}"
    echo "Tags: ${VERSION}, latest"
    echo "Platforms: linux/amd64, linux/arm64"
    echo "======================================"
else
    echo "======================================"
    echo "Error: Build failed!"
    echo "======================================"
    exit 1
fi

# 显示可用的镜像
echo "Available images:"
docker images | grep ${IMAGE_NAME}

echo "Build script completed at $(date)"
