# ========================================================================
# git-undo-last.ps1 - 撤销最后一次提交
# ========================================================================
# 功能说明：
#   撤销当前仓库的最后一次提交，保留更改在工作区
#
# 操作说明：
#   使用 git reset --soft HEAD~ 撤销最后一次提交
#   提交的更改会保留在工作区，可以重新修改后再次提交
#
# 安全特性：
#   - 执行前会显示最后一次提交的信息
#   - 需要用户确认后才执行撤销
#   - 仅撤销提交，不删除任何代码更改
#
# 使用场景：
#   - 提交信息写错了
#   - 提交时漏掉了某些文件
#   - 需要修改最后一次提交的内容
#   - 想要合并多次提交
#
# 运行方式：
#   .\git-undo-last.ps1
#   或在项目根目录运行
#
# 注意事项：
#   ⚠️ 仅撤销最后一次提交，不会删除代码
#   ⚠️ 如果已经推送到远程，撤销后需要强制推送
#   ⚠️ 建议在未推送前使用此命令
#   💡 如果需要完全删除提交（包括更改），使用 git reset --hard HEAD~1
# ========================================================================

#Requires -Version 5.1

$ErrorActionPreference = "Stop"

# 获取当前目录
$currentDir = Get-Location
$gitDir = Join-Path $currentDir ".git"

# 检查是否是 Git 仓库
if (-not (Test-Path $gitDir)) {
    Write-Host ""
    Write-Host "❌ 错误: 当前目录不是 Git 仓库" -ForegroundColor Red
    Write-Host ""
    Read-Host "按回车键退出"
    exit 1
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  撤销最后一次提交" -ForegroundColor Cyan
Write-Host "  当前仓库: $currentDir" -ForegroundColor Gray
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""

# 获取最后一次提交信息
$lastCommit = git log -1 --pretty=format:"%H|%an|%ae|%ai|%s" 2>$null

if (-not $lastCommit) {
    Write-Host "❌ 错误: 无法获取提交信息，仓库可能没有任何提交" -ForegroundColor Red
    Write-Host ""
    Read-Host "按回车键退出"
    exit 1
}

# 解析提交信息
$parts = $lastCommit -split "\|"
$commitHash = $parts[0]
$authorName = $parts[1]
$authorEmail = $parts[2]
$commitDate = $parts[3]
$commitMessage = $parts[4]

# 显示最后一次提交信息
Write-Host "📝 最后一次提交信息:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  提交哈希: " -NoNewline -ForegroundColor Gray
Write-Host $commitHash -ForegroundColor Yellow
Write-Host "  作者: " -NoNewline -ForegroundColor Gray
Write-Host "$authorName <$authorEmail>" -ForegroundColor White
Write-Host "  提交时间: " -NoNewline -ForegroundColor Gray
Write-Host $commitDate -ForegroundColor White
Write-Host "  提交信息: " -NoNewline -ForegroundColor Gray
Write-Host $commitMessage -ForegroundColor White
Write-Host ""

# 获取当前分支
$currentBranch = git branch --show-current
Write-Host "🌿 当前分支: " -NoNewline -ForegroundColor Gray
Write-Host $currentBranch -ForegroundColor Cyan
Write-Host ""

# 检查是否有未推送的提交
$unpushedCommits = git log "@{u}"..HEAD 2>$null
if ($unpushedCommits) {
    Write-Host "⚠️  警告: 本地有未推送的提交" -ForegroundColor Yellow
    $unpushedCount = ($unpushedCommits | Select-String "commit " | Measure-Object).Count
    Write-Host "   未推送提交数: $unpushedCount 个" -ForegroundColor Yellow
    Write-Host ""
}

# 获取当前状态
$statusOutput = git status --porcelain 2>$null
Write-Host "📊 当前状态:" -ForegroundColor Cyan
if ($statusOutput) {
    $changedFiles = ($statusOutput | Measure-Object).Count
    Write-Host "   有未提交的更改: $changedFiles 个文件" -ForegroundColor Yellow
} else {
    Write-Host "   工作区干净" -ForegroundColor Green
}
Write-Host ""

# 警告提示
Write-Host "⚠️  操作说明:" -ForegroundColor Yellow
Write-Host "   此操作将撤销最后一次提交，但保留所有更改在工作区" -ForegroundColor Yellow
Write-Host "   你可以修改后重新提交" -ForegroundColor Yellow
Write-Host ""

# 询问确认
$confirmation = Read-Host "❓ 确认要撤销最后一次提交吗？(y/n)"

if ($confirmation -eq "y" -or $confirmation -eq "Y" -or $confirmation -eq "yes") {
    Write-Host ""
    Write-Host "🔄 正在撤销提交..." -ForegroundColor Cyan

    try {
        # 使用 --soft 保留更改在工作区
        git reset --soft HEAD~1

        Write-Host ""
        Write-Host "✅ 成功撤销最后一次提交" -ForegroundColor Green
        Write-Host ""
        Write-Host "📝 撤销后的状态:" -ForegroundColor Cyan

        # 显示撤销后的状态
        $newStatusOutput = git status --porcelain 2>$null
        if ($newStatusOutput) {
            $changedFiles = ($newStatusOutput | Measure-Object).Count
            Write-Host "   已暂存的文件: $changedFiles 个" -ForegroundColor Green

            # 列出已暂存的文件
            Write-Host ""
            Write-Host "   📁 已暂存的文件列表:" -ForegroundColor Gray
            foreach ($line in $newStatusOutput) {
                $status = $line.Substring(0, 1)
                $filePath = $line.Substring(3)

                $fileStatus = switch ($status) {
                    "M" { "已修改" }
                    "A" { "已添加" }
                    "D" { "已删除" }
                    "R" { "已重命名" }
                    default { "未知" }
                }

                Write-Host "     ${fileStatus}: $filePath" -ForegroundColor DarkGray
            }
        }

        Write-Host ""
        Write-Host "💡 提示: 使用 'git commit' 重新提交这些更改" -ForegroundColor Cyan
        Write-Host ""

    } catch {
        Write-Host ""
        Write-Host "❌ 错误: 撤销提交失败" -ForegroundColor Red
        Write-Host "   $_" -ForegroundColor Red
        Write-Host ""
    }
} else {
    Write-Host ""
    Write-Host "❌ 操作已取消" -ForegroundColor Red
    Write-Host ""
}

Read-Host "按回车键退出"
