#!/bin/bash
# ========================================================================
# git-status-all.sh - 显示当前仓库的详细状态
# ========================================================================
# 功能说明：
#   查看当前 Git 仓库的详细状态信息
#
# 显示信息：
#   📁 项目路径
#   📊 仓库大小（.git 目录大小）
#   🌿 所有分支列表
#   📝 提交日志（每个分支）
#   ✅ 工作区状态
#   🔄 远程仓库信息
#
# 运行方式：
#   ./git-status-all.sh
#   或在项目根目录运行
# ========================================================================

# 设置语言环境
export LC_ALL=en_US.UTF-8

# 获取脚本所在目录的父目录（当前项目）
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE_PATH=$(dirname "$SCRIPT_DIR")

# 检查是否是 Git 仓库
GIT_DIR="$BASE_PATH/.git"
if [ ! -d "$GIT_DIR" ]; then
    echo ""
    echo -e "\033[31m❌ 错误: 当前目录不是 Git 仓库\033[0m"
    echo "路径: $BASE_PATH"
    echo ""
    read -p "按回车键退出..."
    exit 1
fi

cd "$BASE_PATH"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Git 仓库详细信息"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 基本信息
echo -e "\033[33m📁 项目路径\033[0m"
echo "   $BASE_PATH"
echo ""

# 计算仓库大小
echo -e "\033[33m📊 仓库大小\033[0m"
if command -v du &> /dev/null; then
    GIT_SIZE=$(du -sh "$GIT_DIR" 2>/dev/null | cut -f1)
    WORK_SIZE=$(du -sh --exclude=".git" "$BASE_PATH" 2>/dev/null | cut -f1)
    echo -e "   .git 目录: \033[36m$GIT_SIZE\033[0m"
    echo -e "   工作区大小: \033[36m$WORK_SIZE\033[0m"
else
    echo "   无法计算大小"
fi
echo ""

# 当前分支
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
echo -e "\033[33m🌿 当前分支\033[0m"
echo -e "   \033[32m$CURRENT_BRANCH\033[0m"
echo ""

# 所有分支
echo -e "\033[33m🌿 所有分支\033[0m"
BRANCHES=$(git branch -a 2>/dev/null)
if [ -n "$BRANCHES" ]; then
    while IFS= read -r branch; do
        branch_name=$(echo "$branch" | sed 's/^[* ] //;s/^[* ]//')
        if [ "$branch_name" = "$CURRENT_BRANCH" ]; then
            echo -e "   * \033[32m$branch_name (当前)\033[0m"
        elif [[ "$branch_name" == remotes/* ]]; then
            echo -e "     \033[90m$branch_name\033[0m"
        else
            echo "     $branch_name"
        fi
    done <<< "$BRANCHES"
else
    echo "   无分支"
fi
echo ""

# 远程仓库
echo -e "\033[33m🔄 远程仓库\033[0m"
REMOTES=$(git remote -v 2>/dev/null)
if [ -n "$REMOTES" ]; then
    while IFS= read -r remote; do
        echo -e "   \033[36m$remote\033[0m"
    done <<< "$REMOTES"
else
    echo "   无远程仓库"
fi
echo ""

# 工作区状态
echo -e "\033[33m📝 工作区状态\033[0m"
STATUS_OUTPUT=$(git status --porcelain 2>/dev/null)
if [ -n "$STATUS_OUTPUT" ]; then
    CHANGED_FILES=$(echo "$STATUS_OUTPUT" | wc -l)
    echo -e "   \033[33m有未提交的更改: $CHANGED_FILES 个文件\033[0m"
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            status=${line:0:1}
            filePath=${line:3}

            case "$status" in
                M) file_status="已修改"; color="\033[33m" ;;
                A) file_status="已添加"; color="\033[32m" ;;
                D) file_status="已删除"; color="\033[31m" ;;
                R) file_status="已重命名"; color="\033[37m" ;;
                \?\?) file_status="未跟踪"; color="\033[90m" ;;
                *) file_status="未知"; color="\033[37m" ;;
            esac

            echo -e "     \033[90m${file_status}:\033[0m ${color}${filePath}\033[0m"
        fi
    done <<< "$STATUS_OUTPUT"
else
    echo -e "   \033[32m工作区干净\033[0m"
fi
echo ""

# 提交日志（当前分支最近10条）
echo -e "\033[33m📜 提交日志 ($CURRENT_BRANCH)\033[0m"
LOG_OUTPUT=$(git log -10 --oneline --decorate 2>/dev/null)
if [ -n "$LOG_OUTPUT" ]; then
    while IFS= read -r log; do
        echo "   $log"
    done <<< "$LOG_OUTPUT"
else
    echo "   无提交记录"
fi
echo ""

# 统计信息
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "\033[33m📊 统计信息\033[0m"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TOTAL_COMMITS=$(git rev-list --count HEAD 2>/dev/null)
TOTAL_BRANCHES=$(git branch -a 2>/dev/null | wc -l)
TOTAL_REMOTES=$(git remote 2>/dev/null | wc -l)

echo -e "   总提交数: \033[36m$TOTAL_COMMITS\033[0m"
echo -e "   分支数: \033[36m$TOTAL_BRANCHES\033[0m"
echo -e "   远程仓库数: \033[36m$TOTAL_REMOTES\033[0m"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "按回车键退出..."
