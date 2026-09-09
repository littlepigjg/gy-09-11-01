#!/bin/bash
set -e

# ========== 配置 ==========
CONTAINER_NAME="benzhi-claude-code"
PROJECT_NAME="$(basename "$PWD")"          # 当前目录名作为题号
CONTAINER_WORKSPACE="/workspace/$PROJECT_NAME"
CONTAINER_TRACES_DIR="/home/node/.claude/projects/-workspace-$PROJECT_NAME"
BACKUP_DIR="/tmp/docker-sync-$PROJECT_NAME-$$"  # 临时目录，$$ 为进程ID避免冲突
# ==========================

echo "📂 项目名称: $PROJECT_NAME"
echo "🐳 容器名: $CONTAINER_NAME"

# 1. 确保容器存在且运行
if ! docker ps --format '{{.Names}}' | grep -wq "$CONTAINER_NAME"; then
    if docker ps -a --format '{{.Names}}' | grep -wq "$CONTAINER_NAME"; then
        echo "⏳ 容器已存在但未运行，正在启动..."
        docker start "$CONTAINER_NAME"
    else
        echo "❌ 容器 $CONTAINER_NAME 不存在，请先运行 run.sh 创建容器。"
        exit 1
    fi
fi

# 2. 检查容器内工作目录是否存在
if ! docker exec "$CONTAINER_NAME" test -d "$CONTAINER_WORKSPACE"; then
    echo "❌ 容器内工作目录 $CONTAINER_WORKSPACE 不存在，请先运行 run.sh 复制代码。"
    exit 1
fi

# 3. 创建临时目录用于同步
rm -rf "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# 4. 从容器中复制整个项目到临时目录（保留所有文件）
echo "📤 从容器复制最新代码到临时目录..."
docker cp "$CONTAINER_NAME:$CONTAINER_WORKSPACE/." "$BACKUP_DIR/"

# 5. 使用 rsync 将临时目录同步到宿主机当前目录，并删除宿主机多余文件
#    -a: 归档模式，保留权限等；--delete: 删除宿主机中容器不存在的文件
echo "🔄 同步宿主机目录（删除多余文件，确保完全一致）..."
if command -v rsync >/dev/null 2>&1; then
    # 先复制隐藏文件（rsync 默认包含 . 开头的文件，但为了保险）
    rsync -a --delete "$BACKUP_DIR/" "$PWD/"
else
    echo "⚠️ rsync 未安装，使用替代方案：清空宿主机目录后复制..."
    # 删除宿主机当前目录下所有内容（排除脚本自身和临时目录），然后复制
    find "$PWD" -mindepth 1 -maxdepth 1 ! -name "$(basename "$0")" ! -name ".*" -exec rm -rf {} + 2>/dev/null || true
    # 复制临时目录内容（包括隐藏文件）
    cp -a "$BACKUP_DIR/." "$PWD/"
fi

# 6. 导出轨迹文件到宿主机项目目录下的 traces 子目录
echo "📋 导出轨迹文件到 ./traces ..."
mkdir -p "$PWD/traces"
docker cp "$CONTAINER_NAME:$CONTAINER_TRACES_DIR/." "$PWD/traces/" 2>/dev/null || {
    echo "⚠️ 轨迹目录不存在或为空，可能尚未产生对话记录。"
}

# 7. 清理临时目录
rm -rf "$BACKUP_DIR"

echo "✅ 同步完成！"
echo "   - 代码已与容器完全同步（包括删除的文件）。"
echo "   - 轨迹文件已保存到 ./traces/"
echo "   - Claude 会话仍在容器中运行，未受任何影响。"