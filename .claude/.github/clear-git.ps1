#!/usr/bin/env pwsh

# ============================================================================
# Git Compression Tool (压缩优化 .git 目录 - PowerShell)
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
#   .\clear-git.ps1
#   需要手动确认：输入 yes/y 继续，其他任意键取消
#
# 效果展示：
#   - 操作前：显示 .git 目录大小（MB）和对象数量
#   - 操作后：显示优化后的大小和对象数量
#   - 显示节省的空间和优化效果
#   - 显示活跃分支数量
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
#   - 使用彩色输出提示操作进度
# ============================================================================

Write-Host "========================================"
Write-Host "     Git Compression Tool"
Write-Host "========================================"
Write-Host ""
Write-Host "This tool will:" -ForegroundColor Yellow
Write-Host "1. Clear git reflog"
Write-Host "2. Run aggressive garbage collection"
Write-Host "3. Optimize and repack git objects"
Write-Host "4. Reduce .git directory size"
Write-Host ""

$confirm = Read-Host "Do you want to continue? (yes/y or no/n)"

if ($confirm -ne "yes" -and $confirm -ne "y") {
    Write-Host "Operation cancelled." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    exit 0
}

Set-Location "$PSScriptRoot\.."

Write-Host ""
Write-Host "Starting git compression and optimization..." -ForegroundColor Cyan

# Show current statistics
Write-Host "Current repository statistics:" -ForegroundColor Cyan
try {
    $gitSize = (Get-ChildItem -Path ".git" -Recurse -Force | Measure-Object -Property Length -Sum).Sum
    if ($gitSize -gt 0) {
        $currentSizeFormatted = "{0:N2} MB" -f ($gitSize / 1MB)
        Write-Host "Current .git directory size: $currentSizeFormatted"
    } else {
        Write-Host "Current .git directory size: Cannot determine size"
    }
} catch {
    Write-Host "Current .git directory size: Cannot determine size"
}

try {
    $currentObjectCount = git count-objects 2>$null | Select-String "in-pack: (\d+)" | ForEach-Object { $_.Matches.Groups[1].Value }
    if ($currentObjectCount) {
        Write-Host "Current git objects: $currentObjectCount"
    } else {
        Write-Host "Current git objects: Cannot count objects"
    }
} catch {
    Write-Host "Current git objects: Cannot count objects"
}

Write-Host ""
Write-Host "Step 1: Expiring git reflog..." -ForegroundColor Cyan
git reflog expire --expire=now --all
Write-Host "[OK] Reflog expired" -ForegroundColor Green

Write-Host ""
Write-Host "Step 2: Running aggressive garbage collection..." -ForegroundColor Cyan
git gc --aggressive --prune=now
Write-Host "[OK] Aggressive garbage collection completed" -ForegroundColor Green

Write-Host ""
Write-Host "Step 3: Pruning unreachable objects..." -ForegroundColor Cyan
git prune --expire=now
Write-Host "[OK] Unreachable objects pruned" -ForegroundColor Green

Write-Host ""
Write-Host "Step 4: Repacking and optimizing git objects..." -ForegroundColor Cyan
git repack -a -d --depth=250 --window=250
Write-Host "[OK] Git objects repacked and optimized" -ForegroundColor Green

Write-Host ""
Write-Host "Step 5: Final garbage collection..." -ForegroundColor Cyan
git gc --aggressive --prune=now
Write-Host "[OK] Final garbage collection completed" -ForegroundColor Green

Write-Host ""
Write-Host "========================================"
Write-Host "Git compression completed successfully!" -ForegroundColor Green
Write-Host "========================================"
Write-Host ""

# Show final statistics
Write-Host "Final repository statistics:" -ForegroundColor Cyan
try {
    $finalGitSize = (Get-ChildItem -Path ".git" -Recurse -Force | Measure-Object -Property Length -Sum).Sum
    if ($finalGitSize -gt 0) {
        $finalSizeFormatted = "{0:N2} MB" -f ($finalGitSize / 1MB)
        Write-Host "Final .git directory size: $finalSizeFormatted"
    } else {
        Write-Host "Final .git directory size: Cannot determine size"
    }
} catch {
    Write-Host "Final .git directory size: Cannot determine size"
}

try {
    $finalObjectCount = git count-objects 2>$null | Select-String "in-pack: (\d+)" | ForEach-Object { $_.Matches.Groups[1].Value }
    if ($finalObjectCount) {
        Write-Host "Final git objects: $finalObjectCount"
    } else {
        Write-Host "Final git objects: Cannot count objects"
    }
} catch {
    Write-Host "Final git objects: Cannot count objects"
}

$branchCount = (git branch | Measure-Object).Count
Write-Host "Active branches: $branchCount"

# Calculate and show space saved
if ($gitSize -gt 0 -and $finalGitSize -gt 0) {
    Write-Host ""
    Write-Host "Space optimization results:" -ForegroundColor Yellow
    Write-Host "Before: $currentSizeFormatted"
    Write-Host "After:  $finalSizeFormatted"
}

Write-Host ""
Write-Host "Your git repository is now fully optimized!" -ForegroundColor Green
Write-Host "Note: This tool only compresses git objects and history." -ForegroundColor Gray
Write-Host "Use Clear History to manage commit count." -ForegroundColor Gray
Write-Host ""

Start-Sleep -Seconds 5