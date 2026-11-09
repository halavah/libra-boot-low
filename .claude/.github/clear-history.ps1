#!/usr/bin/env pwsh

# ============================================================================
# Git History Cleanup Tool (可配置保留提交数量 - PowerShell)
# ============================================================================
# 功能说明：
#   清理 git 提交历史，仅保留最近的 N 次提交（可配置），删除所有旧提交
#
# 工作流程：
#   1. 备份 .gitignore 文件中列出的被忽略文件
#   2. 检测当前分支并暂存所有更改
#   3. 如果有更改，自动提交并推送
#   4. 用户选择要保留的提交数量（默认5，最少2，最多不超过实际数量）
#   5. 检查提交数量：
#      - ≤保留数量：不执行清理，直接退出
#      - >保留数量：继续清理流程
#   6. 创建备份分支（backup-before-cleanup）
#   7. 获取第N个提交的哈希值
#   8. 创建新的根提交（孤立分支）
#   9. 将最近N个提交 rebase 到新根上
#   10. 运行垃圾回收（gc --aggressive --prune=all）
#   11. 强制推送到远程（git push -f）
#   12. 恢复 .gitignore 文件
#   13. 删除备份分支
#
# 运行方式：
#   .\clear-history.ps1
#
# 备份机制：
#   - 自动备份 .gitignore 中列出的文件到临时目录
#   - Git 操作完成后自动恢复
#   - 防止被忽略的文件在历史清理过程中丢失
#   - 生成备份日志文件（backup_log.txt）
#
# 使用场景：
#   - 仓库体积过大，需要清理历史
#   - 保留最近的工作记录，删除早期提交
#   - 定期维护仓库，控制提交数量
#
# ⚠️ 警告：
#   - 此操作会永久删除旧提交，无法恢复
#   - 会执行强制推送（git push -f），改写远程历史
#   - 其他协作者需要重新克隆仓库或 reset
#   - 建议在执行前通知团队成员
#   - 脚本已自动确认，无需手动输入
#
# 注意事项：
#   - 保留的提交数量：可配置（默认5个，最少2个）
#   - 自动创建备份分支但最后会删除
#   - 会清理 reflog 和运行垃圾回收
#   - 整个过程可能需要几分钟时间
#   - 使用彩色输出提示操作状态
# ============================================================================

Write-Host "========================================"
Write-Host "    Git History Cleanup Tool"
Write-Host "========================================"
Write-Host ""

# Navigate to project root
Set-Location "$PSScriptRoot\.."

# Get current branch first (for commit count check)
$currentBranch = git branch --show-current
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($currentBranch)) {
    Write-Host "Failed to detect current branch." -ForegroundColor Red
    Start-Sleep -Seconds 3
    exit 1
}

# Check current commit count
Write-Host "Checking current commit count..." -ForegroundColor Cyan
$totalCommitCount = [int](git rev-list --count HEAD)
Write-Host "Current total commits: $totalCommitCount" -ForegroundColor Yellow
Write-Host ""

# Ask user for number of commits to keep
Write-Host "How many commits would you like to keep?" -ForegroundColor Cyan
Write-Host "  - Minimum: 1 commit" -ForegroundColor Yellow
Write-Host "  - Maximum: $totalCommitCount commits (current total)" -ForegroundColor Yellow
Write-Host "  - Default: 5 commits (press Enter to use default)" -ForegroundColor Yellow
Write-Host ""

$keepCommitsInput = Read-Host "Enter number of commits to keep [1-$totalCommitCount, default: 5]"

# Use default if empty
if ([string]::IsNullOrWhiteSpace($keepCommitsInput)) {
    $keepCommits = 5
    Write-Host "Using default: 5 commits" -ForegroundColor Green
} else {
    try {
        $keepCommits = [int]$keepCommitsInput

        # Validate input range
        if ($keepCommits -lt 1) {
            Write-Host "Error: Must keep at least 1 commit. Using minimum: 1" -ForegroundColor Red
            $keepCommits = 1
        } elseif ($keepCommits -gt $totalCommitCount) {
            Write-Host "Error: Cannot keep more than $totalCommitCount commits (current total). Using maximum: $totalCommitCount" -ForegroundColor Red
            $keepCommits = $totalCommitCount
        } else {
            Write-Host "Will keep: $keepCommits commits" -ForegroundColor Green
        }
    } catch {
        Write-Host "Invalid input. Using default: 5 commits" -ForegroundColor Yellow
        $keepCommits = 5
    }
}

Write-Host ""
Write-Host "WARNING: This will keep only the last $keepCommits commits!" -ForegroundColor Yellow
Write-Host "All older commits will be permanently deleted." -ForegroundColor Yellow
Write-Host ""

# Auto-confirm: skip user input
$confirm = "y"

if ($confirm -ne "yes" -and $confirm -ne "y") {
    Write-Host "Operation cancelled." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    exit 0
}

# Function to backup .gitignore files
function Backup-GitIgnoreFiles {
    Write-Host "Backing up .gitignore files..." -ForegroundColor Cyan
    $backupDir = ".\temp-git-ignore-backup"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

    if (-not (Test-Path ".gitignore")) {
        Write-Host "No .gitignore file found." -ForegroundColor Yellow
        return
    }

    # Create a backup log
    $backupLog = Join-Path $backupDir "backup_log.txt"
    "Backup log for gitignore files:" | Out-File -FilePath $backupLog -Encoding UTF8
    "Created at: $(Get-Date)" | Out-File -FilePath $backupLog -Encoding UTF8 -Append
    "" | Out-File -FilePath $backupLog -Encoding UTF8 -Append

    # Read .gitignore and backup existing files/directories
    Get-Content ".gitignore" | ForEach-Object {
        $line = $_.Trim()

        # Skip empty lines and comments
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
            return
        }

        # Remove trailing spaces and handle patterns
        $pattern = $line.TrimEnd().TrimStart("/")

        if (-not [string]::IsNullOrWhiteSpace($pattern)) {
            # Check if the pattern is a directory pattern
            if ($pattern.EndsWith("/")) {
                # Directory pattern - remove trailing slash
                $dirPattern = $pattern.TrimEnd("/")
                $dirPath = ".\$dirPattern"

                if (Test-Path $dirPath -PathType Container) {
                    Write-Host "Backing up directory: $dirPattern" -ForegroundColor Green
                    "Directory: $dirPattern" | Out-File -FilePath $backupLog -Encoding UTF8 -Append

                    # Copy the entire directory to backup
                    Copy-Item -Path $dirPath -Destination $backupDir -Recurse -Force
                }
            } else {
                # File or exact pattern
                try {
                    $files = Get-ChildItem -Path ".\$pattern" -Recurse -Force -ErrorAction SilentlyContinue

                    foreach ($file in $files) {
                        if ($file.Exists) {
                            # Skip .git directory to avoid infinite nesting
                            if ($file.FullName -like "*\.git\*") {
                                continue
                            }

                            # Create relative path for backup
                            $relPath = $file.FullName.Replace((Get-Location).Path, "").TrimStart("\")
                            $backupPath = Join-Path $backupDir $relPath
                            $backupDirPath = Split-Path $backupPath -Parent

                            Write-Host "Backing up: $($file.FullName)" -ForegroundColor Green
                            "File: $relPath" | Out-File -FilePath $backupLog -Encoding UTF8 -Append

                            # Create backup directory structure
                            if ($backupDirPath) {
                                New-Item -ItemType Directory -Force -Path $backupDirPath | Out-Null
                            }

                            # Copy file or directory
                            if ($file.PSIsContainer) {
                                Copy-Item -Path $file.FullName -Destination $backupPath -Recurse -Force
                            } else {
                                Copy-Item -Path $file.FullName -Destination $backupPath -Force
                            }
                        }
                    }
                } catch {
                    # Silently continue if pattern doesn't match any files
                }
            }
        }
    }

    Write-Host "[OK] Backup completed. Backup directory: $backupDir" -ForegroundColor Green
    Write-Host ""
}

# Function to restore .gitignore files
function Restore-GitIgnoreFiles {
    Write-Host "Restoring .gitignore files..." -ForegroundColor Cyan
    $backupDir = ".\temp-git-ignore-backup"

    if (-not (Test-Path $backupDir)) {
        Write-Host "No backup directory found. Nothing to restore." -ForegroundColor Yellow
        return
    }

    # Check backup log
    $backupLog = Join-Path $backupDir "backup_log.txt"
    if (Test-Path $backupLog) {
        Write-Host "Found backup log, restoring files..." -ForegroundColor Green

        # Read backup log and restore files
        Get-Content $backupLog | ForEach-Object {
            if ($_ -match "^Directory: (.+)") {
                # Restore directory
                $dirName = $matches[1]
                $backupDirPath = Join-Path $backupDir $dirName
                $targetPath = ".\$dirName"

                if (Test-Path $backupDirPath -PathType Container) {
                    Write-Host "Restoring directory: $dirName" -ForegroundColor Green
                    # Remove existing directory and copy backup
                    if (Test-Path $targetPath) {
                        Remove-Item -Path $targetPath -Recurse -Force
                    }
                    Copy-Item -Path $backupDirPath -Destination "." -Recurse -Force
                }
            }
            elseif ($_ -match "^File: (.+)") {
                # Restore file
                $filePath = $matches[1]
                $backupFile = Join-Path $backupDir $filePath
                $targetFile = ".\$filePath"

                if (Test-Path $backupFile) {
                    Write-Host "Restoring: $filePath" -ForegroundColor Green
                    # Create parent directory if needed
                    $parentDir = Split-Path $targetFile -Parent
                    if ($parentDir -and -not (Test-Path $parentDir)) {
                        New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
                    }
                    # Restore file
                    Copy-Item -Path $backupFile -Destination $targetFile -Recurse -Force
                }
            }
        }
    } else {
        Write-Host "No backup log found. Copying all backup files..." -ForegroundColor Yellow
        # Fallback: copy everything from backup (excluding .git directory)
        Get-ChildItem -Path $backupDir | ForEach-Object {
            $itemName = $_.Name
            # Skip .git directory to avoid infinite loops
            if ($itemName -eq ".git") {
                Write-Host "Skipping .git directory in backup" -ForegroundColor Yellow
                return
            }
            Copy-Item -Path $_.FullName -Destination ".\" -Recurse -Force
        }
    }

    # Cleanup backup directory
    Remove-Item -Path $backupDir -Recurse -Force
    Write-Host "[OK] Restore completed. Backup directory cleaned up." -ForegroundColor Green
    Write-Host ""
}

Write-Host "Current branch: $currentBranch" -ForegroundColor Yellow
Write-Host ""

# Backup .gitignore files before Git operations
Backup-GitIgnoreFiles

# Stage all changes
Write-Host "Staging all changes..." -ForegroundColor Cyan
git add .
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to stage changes." -ForegroundColor Red
    Start-Sleep -Seconds 3
    exit 1
}

# Remove the backup directory from staging (should not be committed)
git rm --cached -r temp-git-ignore-backup 2>$null

# Check if there are changes to commit
git diff --staged --quiet
if ($LASTEXITCODE -ne 0) {
    # Commit changes with timestamped message
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    Write-Host "Committing changes with timestamp: $timestamp..." -ForegroundColor Cyan
    git commit -m "$timestamp"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to commit changes." -ForegroundColor Red
        Start-Sleep -Seconds 3
        exit 1
    }

    # Pull latest changes from the remote repository
    Write-Host "Pulling latest changes from origin/$currentBranch..." -ForegroundColor Cyan
    git pull --no-rebase origin $currentBranch
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to pull changes. Resolve conflicts if any, and rerun the script." -ForegroundColor Red
        Start-Sleep -Seconds 3
        exit 1
    }

    # Push changes to the repository
    Write-Host "Pushing changes to origin/$currentBranch..." -ForegroundColor Cyan
    git push origin $currentBranch
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to push changes." -ForegroundColor Red
        Start-Sleep -Seconds 3
        exit 1
    }

    Write-Host ""
    Write-Host "[OK] Changes successfully committed and pushed." -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "No changes to commit." -ForegroundColor Green
    Write-Host ""
}

Write-Host ""
Write-Host "Final check before cleanup..." -ForegroundColor Cyan
$commitCount = [int](git rev-list --count HEAD)
Write-Host "Current commits: $commitCount"
Write-Host "Commits to keep: $keepCommits"
Write-Host ""

if ($commitCount -le $keepCommits) {
    Write-Host "Only $commitCount commits exist. No cleanup needed (keeping $keepCommits)." -ForegroundColor Green
    Start-Sleep -Seconds 3
    exit 0
}

Write-Host "Will keep the last $keepCommits commits and delete $($commitCount - $keepCommits) old commits." -ForegroundColor Yellow
Write-Host ""

Write-Host "Creating backup branch..." -ForegroundColor Cyan
git branch backup-before-cleanup 2>$null

$nthCommitIndex = $keepCommits - 1
Write-Host "Getting commit hash for keeping last $keepCommits commits..." -ForegroundColor Cyan
$nthCommit = git rev-parse "HEAD~$nthCommitIndex"

Write-Host "Creating new root commit..." -ForegroundColor Cyan
git checkout --orphan temp $nthCommit
git commit -m "Truncated history root"

Write-Host "Rebasing last $keepCommits commits onto new root..." -ForegroundColor Cyan
git rebase --onto temp $nthCommit $currentBranch
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error during rebase. Aborting..." -ForegroundColor Red
    git rebase --abort
    git checkout $currentBranch
    git branch -D temp
    Start-Sleep -Seconds 3
    exit 1
}

Write-Host "Cleaning up temporary branch..." -ForegroundColor Cyan
git branch -D temp

Write-Host "Running garbage collection..." -ForegroundColor Cyan
git gc --aggressive --prune=all

Write-Host "Force pushing to remote..." -ForegroundColor Cyan
git push -f origin $currentBranch

Write-Host ""
Write-Host "Cleanup completed successfully!" -ForegroundColor Green
$newCount = (git rev-list --count HEAD)
Write-Host "New commit count: $newCount"
Write-Host ""

# Restore .gitignore files after Git operations
Restore-GitIgnoreFiles

Write-Host "Deleting backup branch..." -ForegroundColor Cyan
git branch -D backup-before-cleanup

Write-Host ""
Write-Host "[OK] Backup branch deleted." -ForegroundColor Green
Write-Host ""

Start-Sleep -Seconds 5
