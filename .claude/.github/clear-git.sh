#!/bin/bash
# ============================================================================
# Git Compression Tool (压缩优化 .git 目录)
# ============================================================================
# 功能说明：
#   优化和压缩 git 仓库，减小 .git 目录体积，提升性能
#
# 执行操作：
#   1. 清理 git reflog（git reflog expire --expire=now --all）
#   2. 运行激进垃圾回收（git gc --aggressive --prune=now）
#   3. 修剪不可达对象（git prune --expire=now）
#   4. 重新打包优化对象（git repack -a -d --depth=250 --window=250）
#   5. 最终垃圾回收（git gc --aggressive --prune=now）
#
# 运行方式：
#   ./clear-git.sh
#   需要手动确认：输入 yes/y 继续，其他任意键取消
#
# 效果展示：
#   - 操作前：显示 .git 目录大小和对象数量
#   - 操作后：显示优化后的大小和对象数量
#   - 显示节省的空间和优化效果
#
# 使用场景：
#   - .git 目录体积过大，需要压缩
#   - 仓库操作变慢，需要优化性能
#   - 克隆和拉取速度慢，需要减小仓库体积
#   - 定期维护，保持仓库健康状态
#
# 与 Clear History 的区别：
#   - Clear History：删除旧提交，保留最近5个
#   - Clear Git：压缩对象，保留所有提交历史
#
# 注意事项：
#   - 不会删除任何提交记录
#   - 不会改变仓库历史
#   - 不需要强制推送
#   - 操作可能需要较长时间（取决于仓库大小）
#   - 操作期间仓库可能暂时不可用
#   - 建议在非工作时间执行
# ============================================================================
echo "========================================"
echo "     Git Compression Tool"
echo "========================================"
echo ""
echo "This tool will:"
echo "1. Clear git reflog"
echo "2. Run aggressive garbage collection"
echo "3. Optimize and repack git objects"
echo "4. Reduce .git directory size"
echo ""
printf "Do you want to continue? (yes/y or no/n): "
read confirm
if [ "$confirm" != "yes" ] && [ "$confirm" != "y" ]; then
    echo "Operation cancelled."
    sleep 2
    exit 0
fi
cd "$(dirname "$0")/.."
echo ""
echo "Starting git compression and optimization..."
# Show current statistics
echo "Current repository statistics:"
current_size=$(du -sh .git 2>/dev/null | cut -f1)
current_objects=$(git count-objects 2>/dev/null | grep -o 'in-pack: [0-9]*' | cut -d' ' -f2)
echo "Current .git directory size: $current_size"
echo "Current git objects: $current_objects"
echo ""
echo "Step 1: Expiring git reflog..."
git reflog expire --expire=now --all
echo "[OK] Reflog expired"
echo ""
echo "Step 2: Running aggressive garbage collection..."
git gc --aggressive --prune=now
echo "[OK] Aggressive garbage collection completed"
echo ""
echo "Step 3: Pruning unreachable objects..."
git prune --expire=now
echo "[OK] Unreachable objects pruned"
echo ""
echo "Step 4: Repacking and optimizing git objects..."
git repack -a -d --depth=250 --window=250
echo "[OK] Git objects repacked and optimized"
echo ""
echo "Step 5: Final garbage collection..."
git gc --aggressive --prune=now
echo "[OK] Final garbage collection completed"
echo ""
echo "========================================"
echo "Git compression completed successfully!"
echo "========================================"
echo ""
# Show final statistics
echo "Final repository statistics:"
final_size=$(du -sh .git 2>/dev/null | cut -f1)
final_objects=$(git count-objects 2>/dev/null | grep -o 'in-pack: [0-9]*' | cut -d' ' -f2)
echo "Final .git directory size: $final_size"
echo "Final git objects: $final_objects"
echo "Active branches: $(git branch | wc -l | tr -d ' ')"
# Calculate and show space saved
if [ "$current_size" != "" ] && [ "$final_size" != "" ]; then
    echo ""
    echo "Space optimization results:"
    echo "Before: $current_size"
    echo "After:  $final_size"
fi
echo ""
echo "Your git repository is now fully optimized!"
echo "Note: This tool only compresses git objects and history."
echo "Use Clear History to manage commit count."
echo ""
sleep 5