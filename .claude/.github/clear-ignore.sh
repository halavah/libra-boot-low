#!/bin/bash
# ========================================================================
# clear-ignore.sh - Git 忽略文件清理工具
# ========================================================================
# 功能说明：
#   根据 .gitignore 内容，移除已被 Git 跟踪但应该被忽略的文件
#
# 工作流程：
#   1. 检查是否在 Git 仓库中
#   2. 检查 .gitignore 文件是否存在
#   3. 使用 Git 内置功能查找应该被忽略但被跟踪的文件
#   4. 移除这些文件的 Git 跟踪
#
# 运行方式：
#   ./clear-ignore.sh
#
# 注意事项：
#   - 只移除 Git 跟踪，不会删除本地文件系统中的文件
#   - 移除后需要提交更改才能生效
#   - 建议在执行前先提交当前更改
#   - 如需 .gitignore 模板参考，请查看 gitignore-template-*.txt
# ========================================================================

set -e

# 切换到脚本所在目录
cd "$(dirname "$0")"

# 切换到项目根目录
cd ..

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Git 忽略文件清理工具"
echo "═══════════════════════════════════════════════════════════"
echo ""

# 检查是否在 Git 仓库中
echo "🔍 检查 Git 仓库状态..."
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo ""
    echo "❌ 错误：当前目录不是 Git 仓库"
    echo ""
    read -p "按回车键退出"
    exit 1
fi
echo "✅ Git 仓库检查通过"
echo ""

# 检查 .gitignore 文件是否存在
echo "🔍 检查 .gitignore 文件..."
if [ ! -f ".gitignore" ]; then
    echo ""
    echo "❌ 错误：未找到 .gitignore 文件"
    echo ""
    echo "💡 提示：请先创建 .gitignore 文件"
    echo ""
    read -p "按回车键退出"
    exit 1
fi
echo "✅ 找到 .gitignore 文件"
echo ""

# ═══════════════════════════════════════════════════════════
# 开始清理 Git 跟踪
# ═══════════════════════════════════════════════════════════

echo "═══════════════════════════════════════════════════════════"
echo "  开始清理 Git 跟踪的忽略文件"
echo "═══════════════════════════════════════════════════════════"
echo ""

# 创建临时文件
TEMP_FILES=$(mktemp)

echo "📋 步骤 1/3：查找匹配 .gitignore 的被跟踪文件..."
echo ""

# 使用 Git 内置命令查找所有被跟踪但匹配 .gitignore 的文件
git ls-files -i -c --exclude-standard > "$TEMP_FILES" 2>/dev/null

echo "🔍 步骤 2/3：分析发现的文件..."
echo ""

# 检查是否有需要移除的文件
if [ -s "$TEMP_FILES" ]; then
    file_count=$(wc -l < "$TEMP_FILES" | tr -d ' ')
    echo "✅ 找到 $file_count 个文件匹配 .gitignore 规则但仍被 Git 跟踪"
    echo ""
    echo "这些文件将被从 Git 跟踪中移除（本地文件不会被删除）："
    echo "───────────────────────────────────────────────────────────"
    while IFS= read -r file; do
        echo "  $file"
    done < "$TEMP_FILES"
    echo "───────────────────────────────────────────────────────────"
    echo ""

    # 询问用户确认（--yes 跳过 / 10 秒超时默认 N）
    if [ "$1" = "--yes" ] || [ "$ASSUME_YES" = "1" ]; then
        REPLY="y"
    else
        read -t 10 -p "❓ 确定要移除这些文件的 Git 跟踪吗？(y/N，10秒默认N): " -n 1 -r
        echo
        echo
    fi

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🗑️  步骤 3/3：移除 Git 跟踪..."
        echo ""

        # 读取文件并移除跟踪
        success_count=0
        failed_count=0

        while IFS= read -r file; do
            if [ -n "$file" ]; then
                if git rm --cached -r --ignore-unmatch "$file" > /dev/null 2>&1; then
                    echo "✅ 移除跟踪: $file"
                    success_count=$((success_count + 1))
                else
                    echo "⚠️  警告：无法移除 $file"
                    failed_count=$((failed_count + 1))
                fi
            fi
        done < "$TEMP_FILES"

        echo ""
        echo "═══════════════════════════════════════════════════════════"
        echo "  ✅ 清理完成！"
        echo "═══════════════════════════════════════════════════════════"
        echo ""
        echo "📊 处理结果："
        echo "   成功移除：$success_count 个"
        if [ $failed_count -gt 0 ]; then
            echo "   失败：$failed_count 个"
        fi
        echo ""

        # 自动 commit + push（防"下次 git add -A 又加回来"导致看似不生效）
        if [ $success_count -gt 0 ]; then
            echo "🔄 自动提交并推送..."
            git add -A
            git commit -m "chore: remove ignored files from Git tracking" --no-empty 2>/dev/null \
                && echo "✅ 已 commit" \
                || echo "ℹ️  无变更需要 commit"
            git push origin HEAD 2>/dev/null \
                && echo "✅ 已推送" \
                || echo "⚠️  推送失败（请手动 git push）"
        fi

        echo ""
        echo "💡 提示："
        echo "   • 这些文件仍保留在本地文件系统中"
        echo "   • 它们不会再被 Git 跟踪"
    else
        echo "❌ 操作已取消"
    fi
else
    echo "✅ 太好了！没有找到需要移除的被跟踪文件"
    echo ""
    echo "这意味着："
    echo "   • 所有被 Git 跟踪的文件都不在 .gitignore 规则中"
    echo "   • 或者 .gitignore 规则已经正确生效"
fi

# 清理临时文件
rm -f "$TEMP_FILES"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  脚本执行完成"
echo "═══════════════════════════════════════════════════════════"
echo ""
read -p "按回车键退出"
