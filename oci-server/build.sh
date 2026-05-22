#!/bin/bash

# 设置变量
USERNAME="lovele"
IMAGE_NAME="oci-start"
VERSION="2.0.6"

echo "======================================"
echo "Starting build process..."
echo "Image: ${USERNAME}/${IMAGE_NAME}"
echo "Version: ${VERSION}"
echo "======================================"

# 确保使用 buildx
echo "Setting up buildx..."
docker buildx create --name ociStartBuilder206 --use || echo "Builder already exists"
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
    -t ${USERNAME}/${IMAGE_NAME}:${VERSION} \
    -t ${USERNAME}/${IMAGE_NAME}:latest \
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
    echo "Image: ${USERNAME}/${IMAGE_NAME}"
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