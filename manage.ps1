#!/usr/bin/env pwsh
# ========================================================================
# manage.ps1 - 项目管理菜单
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
#   .\manage.ps1
#   或在项目根目录运行
# ========================================================================

#Requires -Version 5.1

# 设置控制台编码
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

while ($true) {
    Clear-Host
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  项目管理菜单" -ForegroundColor White
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  0. 部署到 Git         (deploy.ps1)" -ForegroundColor Green
    Write-Host "     → 自动提交并推送代码到远程仓库" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  1. 清理 Git 跟踪      (clear-ignore.ps1)" -ForegroundColor Green
    Write-Host "     → 根据 .gitignore 移除已跟踪的文件" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  2. 压缩 Git 仓库      (clear-git.ps1)" -ForegroundColor Green
    Write-Host "     → 优化 .git 目录，减小体积（保留所有历史）" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  3. 清理 Git 历史      (clear-history.ps1)" -ForegroundColor Green
    Write-Host "     → 删除旧提交，仅保留最近 N 个（需谨慎）" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  4. 撤销最后一次提交   (git-undo-last.ps1)" -ForegroundColor Yellow
    Write-Host "     → 撤销最后一次提交，保留更改在工作区" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  5. 查看所有仓库状态   (git-status-all.ps1)" -ForegroundColor Green
    Write-Host "     → 显示所有仓库的分支、改动、同步状态" -ForegroundColor Gray
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  9. 退出" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    $choice = Read-Host "请选择操作 [0-5,9] (默认: 0)"

    if ($choice -eq "") {
        $choice = "0"
    }

    switch ($choice) {
        "0" {
            Clear-Host
            Write-Host ""
            Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host "  正在执行：部署到 Git" -ForegroundColor White
            Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host ""

            $scriptPath = Join-Path $PSScriptRoot ".github\deploy.ps1"
            if (Test-Path $scriptPath) {
                & $scriptPath
            } else {
                Write-Host "错误: 找不到脚本 $scriptPath" -ForegroundColor Red
            }

            Write-Host ""
            Read-Host "按 Enter 返回主菜单"
        }
        "1" {
            Clear-Host
            Write-Host ""
            Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host "  正在执行：清理 Git 跟踪" -ForegroundColor White
            Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host ""

            $scriptPath = Join-Path $PSScriptRoot ".github\clear-ignore.ps1"
            if (Test-Path $scriptPath) {
                & $scriptPath
            } else {
                Write-Host "错误: 找不到脚本 $scriptPath" -ForegroundColor Red
            }

            Write-Host ""
            Read-Host "按 Enter 返回主菜单"
        }
        "2" {
            Clear-Host
            Write-Host ""
            Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host "  正在执行：压缩 Git 仓库" -ForegroundColor White
            Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host ""

            $scriptPath = Join-Path $PSScriptRoot ".github\clear-git.ps1"
            if (Test-Path $scriptPath) {
                & $scriptPath
            } else {
                Write-Host "错误: 找不到脚本 $scriptPath" -ForegroundColor Red
            }

            Write-Host ""
            Read-Host "按 Enter 返回主菜单"
        }
        "3" {
            Clear-Host
            Write-Host ""
            Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host "  正在执行：清理 Git 历史" -ForegroundColor White
            Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host ""

            $scriptPath = Join-Path $PSScriptRoot ".github\clear-history.ps1"
            if (Test-Path $scriptPath) {
                & $scriptPath
            } else {
                Write-Host "错误: 找不到脚本 $scriptPath" -ForegroundColor Red
            }

            Write-Host ""
            Read-Host "按 Enter 返回主菜单"
        }
        "4" {
            Clear-Host
            Write-Host ""
            Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host "  正在执行：撤销最后一次提交" -ForegroundColor White
            Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host ""

            $scriptPath = Join-Path $PSScriptRoot ".github\git-undo-last.ps1"
            if (Test-Path $scriptPath) {
                & $scriptPath
            } else {
                Write-Host "错误: 找不到脚本 $scriptPath" -ForegroundColor Red
            }

            Write-Host ""
            Read-Host "按 Enter 返回主菜单"
        }
        "5" {
            Clear-Host
            Write-Host ""
            Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host "  正在执行：查看所有仓库状态" -ForegroundColor White
            Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host ""

            $scriptPath = Join-Path $PSScriptRoot ".github\git-status-all.ps1"
            if (Test-Path $scriptPath) {
                & $scriptPath
            } else {
                Write-Host "错误: 找不到脚本 $scriptPath" -ForegroundColor Red
            }

            Write-Host ""
            Read-Host "按 Enter 返回主菜单"
        }
        "9" {
            Write-Host ""
            Write-Host "感谢使用！再见！" -ForegroundColor Green
            Write-Host ""
            exit 0
        }
        default {
            Write-Host ""
            Write-Host "❌ 错误: 无效的选项，请重新选择" -ForegroundColor Red
            Write-Host ""
            Start-Sleep -Seconds 2
        }
    }
}
