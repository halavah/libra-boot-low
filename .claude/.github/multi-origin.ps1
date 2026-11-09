# ============================================================
# 工具名称: Git Origin / Branch 交互切换工具 (multi-origin.ps1)
# 用途: 交互式切换 origin URL，并切换或整理当前本地分支配置
# ============================================================
#
# 一、这个脚本负责什么？
#     1. 交互式切换 .git/config 里的 origin URL
#     2. 交互式指定目标分支名
#     3. 本地存在该分支时直接切换
#     4. 本地不存在该分支时，可选择“重命名当前分支”或“新建分支”
#     5. 直接写入 branch.<name>.remote / branch.<name>.merge 配置
#
# 二、这个脚本刻意不负责什么？
#     - 不校验远端分支是否真实存在
#     - 不自动 push / pull / sync
#     - 不处理合并冲突
#     - 不删除分支
#
# 三、适用场景
#     - 仓库在 Gitee / GitHub / GitLab 私服之间切换 origin
#     - 有的仓库默认分支叫 master，有的叫 main，需要手动指定
#     - 需要快速把本地分支配置“对齐到 origin/<branch>”但不依赖远端已存在

# ============================================================
# 用户配置区
# ============================================================
$SCRIPT_DIR_CONFIG = $PSScriptRoot
$PROJECT_DIR_CONFIG = (Resolve-Path (Join-Path $SCRIPT_DIR_CONFIG "..")).Path
$REPO_NAME = if ($env:REPO_NAME) { $env:REPO_NAME } else { (Split-Path $PROJECT_DIR_CONFIG -Leaf) }

$USERNAME = "halavah"
$GITLAB_NAMESPACE = "demo"

$REMOTE_GITEE = "git@gitee.com:${USERNAME}/${REPO_NAME}.git"
$REMOTE_GITHUB = "git@github.com:${USERNAME}/${REPO_NAME}.git"
$REMOTE_GITLAB = "http://192.168.3.200/${GITLAB_NAMESPACE}/${REPO_NAME}.git"
# ============================================================

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$SCRIPT_DIR = $PSScriptRoot
$PROJECT_DIR = (Resolve-Path (Join-Path $SCRIPT_DIR "..")).Path
Set-Location -Path $PROJECT_DIR

$gitDir = git rev-parse --git-dir 2>$null
if ($LASTEXITCODE -ne 0 -or -not $gitDir) {
    Write-Host "[ERROR] 当前目录不是 Git 仓库" -ForegroundColor Red
    exit 1
}

function Show-Divider {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor DarkCyan
}

function Get-CurrentBranch {
    return (git rev-parse --abbrev-ref HEAD).Trim()
}

function Get-OriginUrl {
    $url = git remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0) { return "" }
    return ($url | Out-String).Trim()
}

function Test-LocalBranchExists {
    param([string]$Branch)

    git show-ref --verify --quiet "refs/heads/$Branch"
    return ($LASTEXITCODE -eq 0)
}

function Ensure-Origin {
    param([string]$Url)

    git remote get-url origin *> $null
    if ($LASTEXITCODE -eq 0) {
        git remote set-url origin $Url
    } else {
        git remote add origin $Url
    }
}

function Set-BranchTracking {
    param([string]$Branch)

    git config "branch.$Branch.remote" "origin"
    git config "branch.$Branch.merge" "refs/heads/$Branch"
}

function Prompt-RemoteUrl {
    $currentOrigin = Get-OriginUrl

    Show-Divider
    Write-Host "当前项目: $REPO_NAME" -ForegroundColor Cyan
    Write-Host "当前 origin: $(if ($currentOrigin) { $currentOrigin } else { '<未配置>' })"
    Write-Host ""
    Write-Host "请选择要写入 origin 的地址："
    Write-Host "  1) Gitee   $REMOTE_GITEE"
    Write-Host "  2) GitHub  $REMOTE_GITHUB"
    Write-Host "  3) GitLab  $REMOTE_GITLAB"
    Write-Host "  4) 保持当前 origin 不变"
    Write-Host "  5) 手动输入自定义 URL"
    Write-Host "  q) 退出"

    $choice = Read-Host "请输入选项"
    switch ($choice) {
        "1" { return $REMOTE_GITEE }
        "2" { return $REMOTE_GITHUB }
        "3" { return $REMOTE_GITLAB }
        "4" {
            if ($currentOrigin) {
                return $currentOrigin
            }
            Write-Host "[WARN] 当前 origin 为空，请重新选择" -ForegroundColor Yellow
            return Prompt-RemoteUrl
        }
        "5" {
            $customUrl = Read-Host "请输入完整远端 URL"
            if ([string]::IsNullOrWhiteSpace($customUrl)) {
                Write-Host "[WARN] URL 不能为空，请重新选择" -ForegroundColor Yellow
                return Prompt-RemoteUrl
            }
            return $customUrl.Trim()
        }
        { $_ -in @("q", "Q") } {
            Write-Host "[INFO] 已退出" -ForegroundColor Yellow
            exit 0
        }
        default {
            Write-Host "[WARN] 无效选项，请重新选择" -ForegroundColor Yellow
            return Prompt-RemoteUrl
        }
    }
}

function Prompt-TargetBranch {
    $currentBranch = Get-CurrentBranch

    Show-Divider
    Write-Host "当前分支: $currentBranch" -ForegroundColor Cyan
    $branchInput = Read-Host "请输入目标分支名（直接回车默认使用当前分支）"
    if ([string]::IsNullOrWhiteSpace($branchInput)) {
        return $currentBranch
    }
    return $branchInput.Trim()
}

function Switch-BranchIfNeeded {
    param([string]$TargetBranch)

    $currentBranch = Get-CurrentBranch
    if ($currentBranch -eq $TargetBranch) {
        Write-Host "[INFO] 当前已经在分支 $TargetBranch" -ForegroundColor Green
        return
    }

    if (Test-LocalBranchExists -Branch $TargetBranch) {
        Write-Host "[INFO] 切换到已存在的本地分支: $TargetBranch" -ForegroundColor Cyan
        git checkout $TargetBranch
        return
    }

    Show-Divider
    Write-Host "本地分支 $TargetBranch 不存在。"
    Write-Host "请选择处理方式："
    if ($currentBranch -ne "HEAD") {
        Write-Host "  1) 把当前分支 $currentBranch 重命名为 $TargetBranch（推荐）"
    } else {
        Write-Host "  1) 当前为 detached HEAD，改为从当前提交新建 $TargetBranch"
    }
    Write-Host "  2) 基于当前提交新建分支 $TargetBranch"
    Write-Host "  q) 退出"

    $choice = Read-Host "请输入选项"
    switch ($choice) {
        "1" {
            if ($currentBranch -ne "HEAD") {
                git branch -m $TargetBranch
            } else {
                git checkout -b $TargetBranch
            }
        }
        "2" {
            git checkout -b $TargetBranch
        }
        { $_ -in @("q", "Q") } {
            Write-Host "[INFO] 已退出" -ForegroundColor Yellow
            exit 0
        }
        default {
            Write-Host "[WARN] 无效选项，请重新选择" -ForegroundColor Yellow
            Switch-BranchIfNeeded -TargetBranch $TargetBranch
        }
    }
}

function Show-Summary {
    $finalBranch = Get-CurrentBranch
    $finalOrigin = Get-OriginUrl
    $branchRemote = git config --get "branch.$finalBranch.remote" 2>$null
    $branchMerge = git config --get "branch.$finalBranch.merge" 2>$null

    Show-Divider
    Write-Host "[OK] 切换完成" -ForegroundColor Green
    Write-Host "项目目录: $PROJECT_DIR"
    Write-Host "当前分支: $finalBranch"
    Write-Host "origin 地址: $(if ($finalOrigin) { $finalOrigin } else { '<未配置>' })"
    Write-Host "branch.$finalBranch.remote = $(if ($branchRemote) { $branchRemote } else { '<未配置>' })"
    Write-Host "branch.$finalBranch.merge  = $(if ($branchMerge) { $branchMerge } else { '<未配置>' })"
    Write-Host ""
    git remote -v
    Write-Host ""
    git branch --list
}

$selectedRemoteUrl = Prompt-RemoteUrl
Ensure-Origin -Url $selectedRemoteUrl

$targetBranch = Prompt-TargetBranch
Switch-BranchIfNeeded -TargetBranch $targetBranch
Set-BranchTracking -Branch $targetBranch
Show-Summary

Read-Host "按 Enter 结束"
