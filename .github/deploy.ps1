#!/usr/bin/env pwsh

# ============================================================================
# Git Deploy Tool (自动提交推送 - PowerShell)
# ============================================================================
# 功能说明：
#   自动执行 git 工作流：暂存 -> 提交 -> 拉取 -> 推送
#
# 工作流程：
#   1. 检测当前分支
#   2. 暂存所有更改（git add .）
#   3. 检查是否有更改需要提交
#      - 有更改：使用时间戳提交 -> 拉取 -> 推送
#      - 无更改：检查是否有未推送的提交
#        * 有未推送提交：拉取 -> 推送
#        * 无未推送提交：仅拉取
#   4. 自动处理远程更新
#
# 运行方式：
#   .\deploy.ps1
#
# 提交信息格式：
#   时间戳格式：yyyyMMdd_HHmmss
#   示例：20250122_143052
#
# 使用场景：
#   - 快速保存和同步代码更改
#   - 自动化日常提交推送操作
#   - 确保本地和远程保持同步
#
# 注意事项：
#   - 会提交所有未暂存的更改
#   - 提交信息为时间戳，不包含详细描述
#   - 如果拉取失败，需要手动解决冲突后重新运行
#   - 不会执行强制推送，保证远程历史安全
#   - 执行失败时会暂停3秒供查看错误信息
# ============================================================================

# Navigate to project root
Set-Location "$PSScriptRoot\.."

# Get current branch
$currentBranch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($currentBranch)) {
    Write-Host "Failed to detect current branch." -ForegroundColor Red
    Start-Sleep -Seconds 3
    return
}
Write-Host "Current branch: $currentBranch" -ForegroundColor Yellow
Write-Host ""

# Stage all changes
Write-Host "Staging all changes..." -ForegroundColor Cyan
git add .
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to stage changes." -ForegroundColor Red
    Start-Sleep -Seconds 3
    return
}

# Check if there are changes to commit
git diff --staged --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host "No changes to commit." -ForegroundColor Green

    # Check if there are unpushed commits
    $unpushedCommits = git log origin/$currentBranch..$currentBranch 2>$null
    if ($unpushedCommits) {
        Write-Host "Found unpushed commits. Syncing with remote..." -ForegroundColor Yellow

        # Pull first
        Write-Host "Pulling latest changes from origin/$currentBranch..." -ForegroundColor Cyan
        git pull origin $currentBranch
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Failed to pull changes." -ForegroundColor Red
            Start-Sleep -Seconds 3
            return
        }

        # Push unpushed commits
        Write-Host "Pushing unpushed commits to origin/$currentBranch..." -ForegroundColor Cyan
        git push origin $currentBranch
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Failed to push changes." -ForegroundColor Red
            Start-Sleep -Seconds 3
            return
        }

        Write-Host "[OK] Unpushed commits successfully pushed." -ForegroundColor Green
        Start-Sleep -Seconds 3
        return
    }

    # If no changes and no unpushed commits, just pull
    Write-Host "Pulling latest changes from origin/$currentBranch..." -ForegroundColor Cyan
    git pull origin $currentBranch
    Start-Sleep -Seconds 3
    return
}

# Commit changes with timestamped message
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
Write-Host "Committing changes with timestamp: $timestamp..." -ForegroundColor Cyan
git commit -m "$timestamp"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to commit changes." -ForegroundColor Red
    Start-Sleep -Seconds 3
    return
}

# Pull latest changes from the remote repository
Write-Host "Pulling latest changes from origin/$currentBranch..." -ForegroundColor Cyan
git pull origin $currentBranch
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to pull changes. Resolve conflicts if any, and rerun the script." -ForegroundColor Red
    Start-Sleep -Seconds 3
    return
}

# Push changes to the repository
Write-Host "Pushing changes to origin/$currentBranch..." -ForegroundColor Cyan
git push origin $currentBranch
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to push changes." -ForegroundColor Red
    Start-Sleep -Seconds 3
    return
}

Write-Host ""
Write-Host "[OK] Changes successfully pulled, committed, and pushed." -ForegroundColor Green
Start-Sleep -Seconds 3
