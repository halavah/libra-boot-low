#!/bin/bash
# ========================================================================
# manage.sh - 项目管理菜单
# ========================================================================
# 功能说明：
#   统一管理所有 Git 工具脚本，提供交互式菜单界面
#
# 使用场景：
#   - 批量管理多个 Git 仓库
#   - 查看/检查仓库状态
#   - 维护和优化 Git 仓库
#
# 运行方式：
#   ./manage.sh
#   或在项目根目录运行
# ========================================================================

# 自动修复当前脚本的权限
if [ ! -x "$0" ]; then
    chmod +x "$0"
    echo "Fixed script permissions. Restarting..."
    exec "$0" "$@"
fi

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_DIR="$SCRIPT_DIR/.github"

# 主循环
while true; do
    clear
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  项目管理菜单"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "  0. 部署到 Git         (deploy.sh)"
    echo "     → 自动提交并推送代码到远程仓库"
    echo ""
    echo "  1. 清理 Git 跟踪      (clear-ignore.sh)"
    echo "     → 根据 .gitignore 移除已跟踪的文件"
    echo ""
    echo "  2. 压缩 Git 仓库      (clear-git.sh)"
    echo "     → 优化 .git 目录，减小体积（保留所有历史）"
    echo ""
    echo "  3. 清理 Git 历史      (clear-history.sh)"
    echo "     → 删除旧提交，仅保留最近 N 个（需谨慎）"
    echo ""
    echo "  4. 撤销最后一次提交   (git-undo-last.sh)"
    echo "     → 撤销最后一次提交，保留更改在工作区"
    echo ""
    echo "  5. 查看所有仓库状态   (git-status-all.sh)"
    echo "     → 显示所有仓库的分支、改动、同步状态"
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "  9. 退出"
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    printf "请选择操作 [0-5,9] (默认: 0): "
    read choice

    # 如果用户直接按回车，默认选择 0
    choice=${choice:-0}

    case "$choice" in
        0)
            clear
            echo ""
            echo "═══════════════════════════════════════════════════════════"
            echo "  正在执行：部署到 Git"
            echo "═══════════════════════════════════════════════════════════"
            echo ""
            bash "$GITHUB_DIR/deploy.sh"
            echo ""
            read -p "按 Enter 返回主菜单" dummy
            ;;
        1)
            clear
            echo ""
            echo "═══════════════════════════════════════════════════════════"
            echo "  正在执行：清理 Git 跟踪"
            echo "═══════════════════════════════════════════════════════════"
            echo ""
            bash "$GITHUB_DIR/clear-ignore.sh"
            echo ""
            read -p "按 Enter 返回主菜单" dummy
            ;;
        2)
            clear
            echo ""
            echo "═══════════════════════════════════════════════════════════"
            echo "  正在执行：压缩 Git 仓库"
            echo "═══════════════════════════════════════════════════════════"
            echo ""
            bash "$GITHUB_DIR/clear-git.sh"
            echo ""
            read -p "按 Enter 返回主菜单" dummy
            ;;
        3)
            clear
            echo ""
            echo "═══════════════════════════════════════════════════════════"
            echo "  正在执行：清理 Git 历史"
            echo "═══════════════════════════════════════════════════════════"
            echo ""
            bash "$GITHUB_DIR/clear-history.sh"
            echo ""
            read -p "按 Enter 返回主菜单" dummy
            ;;
        4)
            clear
            echo ""
            echo "═══════════════════════════════════════════════════════════"
            echo "  正在执行：撤销最后一次提交"
            echo "═══════════════════════════════════════════════════════════"
            echo ""
            bash "$GITHUB_DIR/git-undo-last.sh"
            echo ""
            read -p "按 Enter 返回主菜单" dummy
            ;;
        5)
            clear
            echo ""
            echo "═══════════════════════════════════════════════════════════"
            echo "  正在执行：查看所有仓库状态"
            echo "═══════════════════════════════════════════════════════════"
            echo ""
            bash "$GITHUB_DIR/git-status-all.sh"
            echo ""
            read -p "按 Enter 返回主菜单" dummy
            ;;
        9)
            echo ""
            echo "感谢使用！再见！"
            echo ""
            exit 0
            ;;
        *)
            echo ""
            echo "错误: 无效的选项"
            sleep 2
            ;;
    esac
done
