# ========================================================================
# git-status-all.ps1 - 显示当前仓库的详细状态
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
#   .\git-status-all.ps1
#   或在项目根目录运行
# ========================================================================

#Requires -Version 5.1

$ErrorActionPreference = "SilentlyContinue"

# 获取脚本所在目录的父目录（当前项目）
$scriptPath = $PSScriptRoot
if (-not $scriptPath) {
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$basePath = Split-Path -Parent $scriptPath

# 检查是否是 Git 仓库
$gitDir = Join-Path $basePath ".git"
if (-not (Test-Path $gitDir)) {
    Write-Host ""
    Write-Host "❌ 错误: 当前目录不是 Git 仓库" -ForegroundColor Red
    Write-Host "路径: $basePath" -ForegroundColor Gray
    Write-Host ""
    Read-Host "按回车键退出"
    exit 1
}

Push-Location $basePath

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  Git 仓库详细信息" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""

# 基本信息
Write-Host "📁 项目路径" -ForegroundColor Yellow
Write-Host "   $basePath" -ForegroundColor White
Write-Host ""

# 计算仓库大小
Write-Host "📊 仓库大小" -ForegroundColor Yellow
try {
    $gitSize = (Get-ChildItem -Path $gitDir -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
    $gitSizeStr = if ($gitSize) { "{0:N2} MB" -f $gitSize } else { "0 MB" }
    Write-Host "   .git 目录: $gitSizeStr" -ForegroundColor Cyan

    # 计算工作区大小
    $workSize = (Get-ChildItem -Path $basePath -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notlike "*\.git*" } | Measure-Object -Property Length -Sum).Sum / 1MB
    $workSizeStr = if ($workSize) { "{0:N2} MB" -f $workSize } else { "0 MB" }
    Write-Host "   工作区大小: $workSizeStr" -ForegroundColor Cyan
} catch {
    Write-Host "   无法计算大小" -ForegroundColor Red
}
Write-Host ""

# 当前分支
$currentBranch = git branch --show-current 2>$null
Write-Host "🌿 当前分支" -ForegroundColor Yellow
Write-Host "   $currentBranch" -ForegroundColor Green
Write-Host ""

# 所有分支
Write-Host "🌿 所有分支" -ForegroundColor Yellow
$branches = git branch -a 2>$null
if ($branches) {
    foreach ($branch in $branches) {
        $branchName = $branch.Trim().TrimStart('*').Trim()
        if ($branchName -eq $currentBranch) {
            Write-Host "   * $branchName (当前)" -ForegroundColor Green
        } elseif ($branchName -like "remotes/*") {
            Write-Host "     $branchName" -ForegroundColor DarkGray
        } else {
            Write-Host "     $branchName" -ForegroundColor White
        }
    }
} else {
    Write-Host "   无分支" -ForegroundColor Gray
}
Write-Host ""

# 远程仓库
Write-Host "🔄 远程仓库" -ForegroundColor Yellow
$remotes = git remote -v 2>$null
if ($remotes) {
    foreach ($remote in $remotes) {
        Write-Host "   $remote" -ForegroundColor Cyan
    }
} else {
    Write-Host "   无远程仓库" -ForegroundColor Gray
}
Write-Host ""

# 工作区状态
Write-Host "📝 工作区状态" -ForegroundColor Yellow
$statusOutput = git status --porcelain 2>$null
if ($statusOutput) {
    $changedFiles = ($statusOutput | Measure-Object).Count
    Write-Host "   有未提交的更改: $changedFiles 个文件" -ForegroundColor Yellow
    foreach ($line in $statusOutput) {
        $status = $line.Substring(0, 1)
        $filePath = $line.Substring(3)

        $fileStatus = switch ($status) {
            "M" { "已修改" }
            "A" { "已添加" }
            "D" { "已删除" }
            "R" { "已重命名" }
            "??" { "未跟踪" }
            default { "未知" }
        }

        $color = switch ($status) {
            "M" { "Yellow" }
            "A" { "Green" }
            "D" { "Red" }
            "??" { "DarkGray" }
            default { "White" }
        }

        Write-Host "     ${fileStatus}: " -NoNewline -ForegroundColor Gray
        Write-Host $filePath -ForegroundColor $color
    }
} else {
    Write-Host "   工作区干净" -ForegroundColor Green
}
Write-Host ""

# 提交日志（当前分支最近10条）
Write-Host "📜 提交日志 ($currentBranch)" -ForegroundColor Yellow
$logOutput = git log -10 --oneline --decorate 2>$null
if ($logOutput) {
    foreach ($log in $logOutput) {
        Write-Host "   $log" -ForegroundColor White
    }
} else {
    Write-Host "   无提交记录" -ForegroundColor Gray
}
Write-Host ""

# 统计信息
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "📊 统计信息" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

$totalCommits = git rev-list --count HEAD 2>$null
$totalBranches = (git branch -a 2>$null | Measure-Object).Count
$totalRemotes = (git remote 2>$null | Measure-Object).Count

Write-Host "   总提交数: $totalCommits" -ForegroundColor Cyan
Write-Host "   分支数: $totalBranches" -ForegroundColor Cyan
Write-Host "   远程仓库数: $totalRemotes" -ForegroundColor Cyan

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""

Pop-Location

Read-Host "按回车键退出"
