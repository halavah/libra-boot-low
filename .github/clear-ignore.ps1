#!/usr/bin/env pwsh
# ========================================================================
# clear-ignore.ps1 - Git 忽略文件清理工具
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
#   .\clear-ignore.ps1
#
# 注意事项：
#   - 只移除 Git 跟踪，不会删除本地文件系统中的文件
#   - 移除后需要提交更改才能生效
#   - 建议在执行前先提交当前更改
#   - 如需 .gitignore 模板参考，请查看 .cursor/ 目录中的模板文件
# ========================================================================

#Requires -Version 5.1

# 设置控制台编码
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Git 忽略文件清理工具" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# 切换到项目根目录
Set-Location "$PSScriptRoot\.."

# 检查是否在 Git 仓库中
Write-Host "🔍 检查 Git 仓库状态..." -ForegroundColor Yellow
$gitDir = git rev-parse --git-dir 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "❌ 错误：当前目录不是 Git 仓库" -ForegroundColor Red
    Write-Host ""
    Read-Host "按回车键退出"
    exit 1
}
Write-Host "✅ Git 仓库检查通过" -ForegroundColor Green
Write-Host ""

# 检查 .gitignore 文件是否存在
Write-Host "🔍 检查 .gitignore 文件..." -ForegroundColor Yellow
if (-not (Test-Path ".gitignore")) {
    Write-Host ""
    Write-Host "❌ 错误：未找到 .gitignore 文件" -ForegroundColor Red
    Write-Host ""
    Write-Host "💡 提示：请先创建 .gitignore 文件" -ForegroundColor Cyan
    Write-Host ""
    Read-Host "按回车键退出"
    exit 1
}
Write-Host "✅ 找到 .gitignore 文件" -ForegroundColor Green
Write-Host ""

# ═══════════════════════════════════════════════════════════
# 开始清理 Git 跟踪
# ═══════════════════════════════════════════════════════════

Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  开始清理 Git 跟踪的忽略文件" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# 创建临时文件
$tempFile = Join-Path $env:TEMP "git_ignore_files.txt"
if (Test-Path $tempFile) {
    Remove-Item $tempFile -Force
}

Write-Host "📋 步骤 1/3：查找匹配 .gitignore 的被跟踪文件..." -ForegroundColor Yellow
Write-Host ""

# 使用 Git 内置命令查找所有被跟踪但匹配 .gitignore 的文件
git ls-files -i -c --exclude-standard 2>$null | Out-File -FilePath $tempFile -Encoding UTF8

Write-Host "🔍 步骤 2/3：分析发现的文件..." -ForegroundColor Yellow
Write-Host ""

# 检查是否有需要移除的文件
$fileContent = Get-Content $tempFile -ErrorAction SilentlyContinue
if ((Test-Path $tempFile) -and $fileContent -and $fileContent.Length -gt 0) {
    $files = $fileContent | Where-Object { $_.Trim() -ne "" }
    $fileCount = $files.Count

    if ($fileCount -gt 0) {
        Write-Host "✅ 找到 $fileCount 个文件匹配 .gitignore 规则但仍被 Git 跟踪" -ForegroundColor Green
        Write-Host ""
        Write-Host "这些文件将被从 Git 跟踪中移除（本地文件不会被删除）：" -ForegroundColor Cyan
        Write-Host "───────────────────────────────────────────────────────────" -ForegroundColor Gray
        $files | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
        Write-Host "───────────────────────────────────────────────────────────" -ForegroundColor Gray
        Write-Host ""

        # 询问用户确认
        $confirm = Read-Host "❓ 确定要移除这些文件的 Git 跟踪吗？(y/N，默认N)"
        Write-Host ""

        if ($confirm -eq "y" -or $confirm -eq "Y") {
            Write-Host "🗑️  步骤 3/3：移除 Git 跟踪..." -ForegroundColor Yellow
            Write-Host ""

            $successCount = 0
            $failedCount = 0

            # Remove files from git tracking
            foreach ($file in $files) {
                $filePath = $file.Trim()
                if (-not [string]::IsNullOrWhiteSpace($filePath)) {
                    git rm --cached -r --ignore-unmatch $filePath 2>$null | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "✅ 移除跟踪: $filePath" -ForegroundColor Green
                        $successCount++
                    } else {
                        Write-Host "⚠️  警告：无法移除 $filePath" -ForegroundColor Yellow
                        $failedCount++
                    }
                }
            }

            Write-Host ""
            Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host "  ✅ 清理完成！" -ForegroundColor Green
            Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "📊 处理结果：" -ForegroundColor Cyan
            Write-Host "   成功移除：$successCount 个" -ForegroundColor Green
            if ($failedCount -gt 0) {
                Write-Host "   失败：$failedCount 个" -ForegroundColor Yellow
            }
            Write-Host ""
            Write-Host "📌 下一步操作：" -ForegroundColor Cyan
            Write-Host "   1. 查看状态: " -NoNewline; Write-Host "git status" -ForegroundColor White
            Write-Host "   2. 查看更改: " -NoNewline; Write-Host "git diff --cached" -ForegroundColor White
            Write-Host "   3. 提交更改: " -NoNewline; Write-Host "git commit -m `"chore: remove ignored files from Git tracking`"" -ForegroundColor White
            Write-Host ""
            Write-Host "💡 提示：" -ForegroundColor Cyan
            Write-Host "   • 这些文件仍保留在本地文件系统中" -ForegroundColor Gray
            Write-Host "   • 它们不会再被 Git 跟踪" -ForegroundColor Gray
            Write-Host "   • 提交后，这些文件将从远程仓库中删除（但本地保留）" -ForegroundColor Gray
        } else {
            Write-Host "❌ 操作已取消" -ForegroundColor Yellow
        }
    } else {
        Write-Host "✅ 太好了！没有找到需要移除的被跟踪文件" -ForegroundColor Green
        Write-Host ""
        Write-Host "这意味着：" -ForegroundColor Cyan
        Write-Host "   • 所有被 Git 跟踪的文件都不在 .gitignore 规则中" -ForegroundColor Gray
        Write-Host "   • 或者 .gitignore 规则已经正确生效" -ForegroundColor Gray
    }
} else {
    Write-Host "✅ 太好了！没有找到需要移除的被跟踪文件" -ForegroundColor Green
    Write-Host ""
    Write-Host "这意味着：" -ForegroundColor Cyan
    Write-Host "   • 所有被 Git 跟踪的文件都不在 .gitignore 规则中" -ForegroundColor Gray
    Write-Host "   • 或者 .gitignore 规则已经正确生效" -ForegroundColor Gray
}

# 清理临时文件
if (Test-Path $tempFile) {
    Remove-Item $tempFile -Force
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  脚本执行完成" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Read-Host "按回车键退出"
