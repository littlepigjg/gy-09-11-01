#!/bin/bash
set -e  # 遇到错误立即退出

# ========== 配置区 ==========
# 建议从环境变量读取 API Key，避免硬编码在脚本中
API_KEY="sk-9-o1yyETITRqUtpk8Rttzg"   # 若未设置环境变量，请替换为实际 Key
IMAGE="adminfather/benzhi-claude-code"
CONTAINER_NAME="benzhi-claude-code"
# =============================

# 获取当前目录名作为题号（例如 gy-09-08-01-1）
PROJECT_NAME="$(basename "$PWD")"

echo "📁 项目名称: $PROJECT_NAME"
echo "🐳 容器名: $CONTAINER_NAME"

# 1. 检查容器是否存在
if docker ps -a --format '{{.Names}}' | grep -wq "$CONTAINER_NAME"; then
    echo "✅ 容器已存在"
    # 检查是否在运行，若未运行则启动
    if docker ps --format '{{.Names}}' | grep -wq "$CONTAINER_NAME"; then
        echo "⏳ 容器已在运行"
    else
        echo "⏳ 容器未运行，正在启动..."
        docker start "$CONTAINER_NAME"
    fi
else
    echo "🚀 容器不存在，正在创建并启动..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        -e "apikey=$API_KEY" \
        "$IMAGE"
    echo "✅ 容器已创建"
fi

# 2. 在容器内创建工作目录（对应题号）
echo "📂 创建/准备容器内工作目录: /workspace/$PROJECT_NAME"
docker exec "$CONTAINER_NAME" mkdir -p "/workspace/$PROJECT_NAME"

# 3. 将当前项目所有文件复制到容器的该目录下
#    注意：不会删除目标目录中已有的其他文件（只覆盖同名文件）
echo "📤 复制项目文件到容器..."
docker cp . "$CONTAINER_NAME:/workspace/$PROJECT_NAME/"

# 4. 修复文件权限，让容器内的 node 用户可写（重要！）
echo "🔧 修复文件权限（容器内 node 用户）..."
docker exec -u root "$CONTAINER_NAME" chown -R node:node "/workspace/$PROJECT_NAME"

# 5. 一切就绪，进入 Claude Code 对话
echo "💬 进入 Claude Code（题号: $PROJECT_NAME）"
docker exec -it "$CONTAINER_NAME" cc "$PROJECT_NAME"