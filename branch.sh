#!/bin/bash

# ============================================
#  独立仓库批量创建脚本
#  将当前代码复制为 N 份，每份初始化为独立的 Git 仓库并提交
#  同时创建远程 GitHub 仓库并推送初始化代码
#  用法：在主仓库目录运行，输入数量即可创建对应仓库
# ============================================

if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "[ERROR] 当前目录不是 Git 仓库"
    exit 1
fi

# 检查 gh CLI 是否可用
if ! command -v gh &> /dev/null; then
    echo "[ERROR] 未找到 gh CLI，请先安装并登录: https://cli.github.com/"
    exit 1
fi

# 检查 gh 是否已登录
if ! gh auth status &> /dev/null; then
    echo "[ERROR] gh CLI 未登录，请先运行: gh auth login"
    exit 1
fi

ORIG_DIR="$(pwd)"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# 从远程 URL 提取仓库名作为基础名称
REMOTE_URL="$(git remote get-url origin 2>/dev/null || echo "")"
if [[ -n "$REMOTE_URL" ]]; then
    BASE_NAME="$(basename "$REMOTE_URL" .git)"
    BASE_NAME="${BASE_NAME##*/}"
else
    BASE_NAME="$(basename "$(pwd)")"
    echo "[WARN] 未找到远程 origin，使用目录名: $BASE_NAME"
fi

echo "远程仓库: $REMOTE_URL"
echo "基础名称: $BASE_NAME"
echo

read -p "请输入要创建的独立仓库数量: " COUNT

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [ "$COUNT" -le 0 ]; then
    echo "[ERROR] 请输入大于 0 的正整数"
    exit 1
fi

PARENT_DIR="$(dirname "$ORIG_DIR")"
TARGET_DIR="${PARENT_DIR}/git_${BASE_NAME}"

echo
echo "将创建 $COUNT 个独立仓库："
echo "============================================================"
echo "  存放目录: ${TARGET_DIR}/"
echo "  仓库命名: ${BASE_NAME}-1 ~ ${BASE_NAME}-${COUNT}"
echo "  模式: 创建本地仓库 + 远程 GitHub 仓库"
echo "============================================================"

read -p "确认开始？[Y/n] " CONFIRM
if [[ "$CONFIRM" =~ ^[Nn] ]]; then
    echo "已取消"
    exit 0
fi

# 创建存放目录
mkdir -p "$TARGET_DIR"

SUCCESS=0
FAIL=0
SKIP=0

for ((i=1; i<=COUNT; i++)); do
    NEW_REPO="${BASE_NAME}-${i}"
    NEW_DIR="${TARGET_DIR}/${NEW_REPO}"

    if [ -d "$NEW_DIR" ]; then
        # 目录已存在，检查是否已是 git 仓库
        if [ -d "$NEW_DIR/.git" ]; then
            echo "[SKIP] 仓库 '$NEW_REPO' 已存在且是 Git 仓库，跳过"
            ((SKIP++))
            continue
        else
            echo "[SKIP] 目录 '$NEW_DIR' 已存在但非 Git 仓库，删除后重建"
            rm -rf "$NEW_DIR"
        fi
    fi

    echo -n "[CREATE] $NEW_REPO ... "

    # 创建目录
    if ! mkdir -p "$NEW_DIR"; then
        echo "✗ 创建目录失败"
        ((FAIL++))
        continue
    fi

    # 复制所有代码文件，排除隐藏目录（含 .git）
    if ! rsync -a --exclude='.*/' --exclude='branch.sh' --exclude='git_*' "$ORIG_DIR/" "$NEW_DIR/"; then
        # 如果 rsync 不可用，回退到 cp 并清理隐藏目录
        cp -r "$ORIG_DIR/." "$NEW_DIR/" 2>/dev/null
        find "$NEW_DIR" -mindepth 1 -type d -name '.*' -prune -exec rm -rf {} +
        rm -f "$NEW_DIR/branch.sh"
    fi

    # 初始化 Git 仓库并提交
    (
        cd "$NEW_DIR" || exit 1
        git init -q -b main
        git config user.email "agent@example.com"
        git config user.name "Agent"
        git add -A
        git commit -q -m "Initial commit: ${NEW_REPO}"
    )

    if [ $? -ne 0 ]; then
        echo "✗ 初始化仓库失败"
        ((FAIL++))
        continue
    fi

    # 创建远程 GitHub 仓库并推送
    echo -n "✓ 本地仓库创建成功, 推送远程... "
    if (
        cd "$NEW_DIR" && \
        gh repo create "$NEW_REPO" --public --source=. --push 2>/dev/null
    ); then
        echo "✓ 远程仓库创建并推送成功"
        ((SUCCESS++))
    else
        echo "⚠ 远程仓库创建失败（本地仓库已创建，可手动推送）"
        ((FAIL++))
    fi
done

echo "============================================================"
echo "完成！成功: ${SUCCESS}, 跳过: ${SKIP}, 失败: ${FAIL}"
echo
echo "📂 仓库目录："
for ((i=1; i<=COUNT; i++)); do
    NEW_REPO="${BASE_NAME}-${i}"
    NEW_DIR="${TARGET_DIR}/${NEW_REPO}"
    if [ -d "$NEW_DIR/.git" ]; then
        echo "   $NEW_DIR/  (本地仓库)"
        # 检查是否有远程
        if git -C "$NEW_DIR" remote get-url origin &>/dev/null; then
            REMOTE="$(git -C "$NEW_DIR" remote get-url origin)"
            echo "      └─ 远程: $REMOTE"
        fi
    fi
done
