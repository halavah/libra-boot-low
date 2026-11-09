#!/bin/bash

# ==============================================================================
# 脚本名称: fix-permissions.sh
# 功能描述: 自动修复 .github 目录及项目根目录下所有 Shell/PowerShell 脚本的执行权限
# 使用方法: 直接将此脚本拖入终端运行，或使用命令 sh fix-permissions.sh
# ==============================================================================

# 1. 获取脚本文件所在的绝对路径
# 即使通过软链接或在不同目录下调用，也能正确定位
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 2. 获取项目根目录 (.agent/.github -> .agent -> demo)
PROJECT_ROOT="$(dirname "$(dirname "$CURRENT_DIR")")"

echo "========================================================"
echo "          开始修复脚本执行权限 (递归扫描)"
echo "========================================================"
echo "当前脚本目录: $CURRENT_DIR"
echo "项目根目录:   $PROJECT_ROOT"
echo "--------------------------------------------------------"

# 3. 递归赋予权限
grant_permissions_recursive() {
    local target_dir="$1"

    if [ -d "$target_dir" ]; then
        echo "正在扫描目录: $target_dir"

        # 查找所有 .sh 和 .ps1 文件，排除 node_modules, .git, dist, target, .idea
        find "$target_dir" -type d \( -name "node_modules" -o -name ".git" -o -name "dist" -o -name "target" -o -name ".idea" \) -prune -o -type f \( -name "*.sh" -o -name "*.ps1" \) -print0 | xargs -0 chmod -v +x

        echo "  -> 权限修复完成"
    else
        echo "警告: 目录不存在 $target_dir"
    fi
}

# 4. 执行权限修复
grant_permissions_recursive "$PROJECT_ROOT"

echo "--------------------------------------------------------"
echo "✅ 项目下所有 .sh/.ps1 脚本权限已修复！"
echo "========================================================"
echo "按 [回车] 键立即关闭，或等待 3 秒自动退出..."

if read -t 3; then
    :
else
    echo
fi
