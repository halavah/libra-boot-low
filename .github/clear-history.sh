#!/bin/bash
# ============================================================================
# Git History Cleanup Tool (可配置保留提交数量)
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
#   ./clear-history.sh
#
# 备份机制：
#   - 自动备份 .gitignore 中列出的文件到临时目录
#   - Git 操作完成后自动恢复
#   - 防止被忽略的文件在历史清理过程中丢失
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
# ============================================================================
echo "========================================"
echo "    Git History Cleanup Tool"
echo "========================================"
echo ""
# Navigate to project root
cd "$(dirname "$0")/.."
# Get current branch first (for commit count check)
current_branch=$(git branch --show-current)
if [ $? -ne 0 ] || [ -z "$current_branch" ]; then
    echo "Failed to detect current branch."
    sleep 3
    exit 1
fi
# Check current commit count
echo "Checking current commit count..."
total_commit_count=$(git rev-list --count HEAD)
echo "Current total commits: $total_commit_count"
echo ""
# Ask user for number of commits to keep
echo "How many commits would you like to keep?"
echo "  - Minimum: 1 commit"
echo "  - Maximum: $total_commit_count commits (current total)"
echo "  - Default: 5 commits (press Enter to use default)"
echo ""
printf "Enter number of commits to keep [1-$total_commit_count, default: 5]: "
read keep_commits_input
# Use default if empty
if [ -z "$keep_commits_input" ]; then
    keep_commits=5
    echo "Using default: 5 commits"
else
    # Validate input is a number
    if ! [[ "$keep_commits_input" =~ ^[0-9]+$ ]]; then
        echo "Invalid input. Using default: 5 commits"
        keep_commits=5
    else
        keep_commits=$keep_commits_input
        # Validate input range
        if [ "$keep_commits" -lt 1 ]; then
            echo "Error: Must keep at least 1 commit. Using minimum: 1"
            keep_commits=1
        elif [ "$keep_commits" -gt "$total_commit_count" ]; then
            echo "Error: Cannot keep more than $total_commit_count commits (current total). Using maximum: $total_commit_count"
            keep_commits=$total_commit_count
        else
            echo "Will keep: $keep_commits commits"
        fi
    fi
fi
echo ""
echo "WARNING: This will keep only the last $keep_commits commits!"
echo "All older commits will be permanently deleted."
echo ""
# Auto-confirm: skip user input
confirm="y"
if [ "$confirm" != "yes" ] && [ "$confirm" != "y" ]; then
    echo "Operation cancelled."
    sleep 2
    exit 0
fi
# Function to backup .gitignore files
backup_gitignore_files() {
    echo "Backing up .gitignore files..."
    BACKUP_DIR="./temp-git-ignore-backup"
    mkdir -p "$BACKUP_DIR"
    if [ ! -f ".gitignore" ]; then
        echo "No .gitignore file found."
        return 0
    fi
    # Create a backup log
    echo "Backup log for gitignore files:" > "$BACKUP_DIR/backup_log.txt"
    echo "Created at: $(date)" >> "$BACKUP_DIR/backup_log.txt"
    echo "" >> "$BACKUP_DIR/backup_log.txt"
    # Read .gitignore and backup existing files/directories
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -z "$line" || "$line" == \#* ]]; then
            continue
        fi
        # Remove trailing spaces and handle patterns
        pattern=$(echo "$line" | sed 's/[[:space:]]*$//' | sed 's/^\///')
        if [[ -n "$pattern" ]]; then
            # Check if the pattern is a directory pattern
            if [[ "$pattern" == */ ]]; then
                # Directory pattern - remove trailing slash
                dir_pattern="${pattern%/}"
                if [ -d "./$dir_pattern" ]; then
                    echo "Backing up directory: $dir_pattern"
                    echo "Directory: $dir_pattern" >> "$BACKUP_DIR/backup_log.txt"
                    # Copy the entire directory to backup
                    cp -r "./$dir_pattern" "$BACKUP_DIR/"
                fi
            else
                # File or exact pattern
                # Use find to locate files matching the pattern
                while IFS= read -r -d '' file; do
                    if [ -e "$file" ] || [ -L "$file" ]; then
                        # Skip .git directory to avoid infinite nesting
                        if [[ "$file" == .git/* ]]; then
                            continue
                        fi
                        # Create relative path for backup
                        rel_path="${file#./}"
                        backup_path="$BACKUP_DIR/$rel_path"
                        backup_dir=$(dirname "$backup_path")
                        echo "Backing up: $file"
                        echo "File: $rel_path" >> "$BACKUP_DIR/backup_log.txt"
                        # Create backup directory structure
                        mkdir -p "$backup_dir"
                        # Copy file or directory
                        if [ -d "$file" ]; then
                            cp -r "$file" "$backup_path"
                        elif [ -f "$file" ] || [ -L "$file" ]; then
                            cp -r "$file" "$backup_path"
                        fi
                    fi
                done < <(find . -path "./$pattern" -print0 2>/dev/null)
            fi
        fi
    done < ".gitignore"
    echo "[OK] Backup completed. Backup directory: $BACKUP_DIR"
    echo ""
}
# Function to restore .gitignore files
restore_gitignore_files() {
    echo "Restoring .gitignore files..."
    BACKUP_DIR="./temp-git-ignore-backup"
    if [ ! -d "$BACKUP_DIR" ]; then
        echo "No backup directory found. Nothing to restore."
        return 0
    fi
    # Check backup log
    if [ -f "$BACKUP_DIR/backup_log.txt" ]; then
        echo "Found backup log, restoring files..."
        # Read backup log and restore files
        while IFS= read -r line; do
            if [[ "$line" =~ ^Directory: ]]; then
                # Restore directory
                dir_name=$(echo "$line" | sed 's/^Directory: //')
                backup_dir="$BACKUP_DIR/$dir_name"
                if [ -d "$backup_dir" ]; then
                    echo "Restoring directory: $dir_name"
                    # Remove existing directory and copy backup
                    rm -rf "./$dir_name" 2>/dev/null
                    cp -r "$backup_dir" "./"
                fi
            elif [[ "$line" =~ ^File: ]]; then
                # Restore file
                file_path=$(echo "$line" | sed 's/^File: //')
                backup_file="$BACKUP_DIR/$file_path"
                if [ -e "$backup_file" ]; then
                    echo "Restoring: $file_path"
                    # Create parent directory if needed
                    mkdir -p "$(dirname "./$file_path")"
                    # Restore file
                    cp -r "$backup_file" "./$file_path"
                fi
            fi
        done < "$BACKUP_DIR/backup_log.txt"
    else
        echo "No backup log found. Copying all backup files..."
        # Fallback: copy everything from backup (excluding .git directory)
        (cd "$BACKUP_DIR" && find . -mindepth 1 -not -name ".git" -exec cp -r {} "../" \;)
    fi
    # Cleanup backup directory
    rm -rf "$BACKUP_DIR"
    echo "[OK] Restore completed. Backup directory cleaned up."
    echo ""
}
echo "Current branch: $current_branch"
echo ""
# Backup .gitignore files before Git operations
backup_gitignore_files
# Stage all changes
echo "Staging all changes..."
git add .
if [ $? -ne 0 ]; then
    echo "Failed to stage changes."
    sleep 3
    exit 1
fi

# Remove the backup directory from staging (should not be committed)
git rm --cached -r temp-git-ignore-backup 2>/dev/null

# Check if there are changes to commit
git diff --staged --quiet
if [ $? -ne 0 ]; then
    # Commit changes with timestamped message
    timestamp=$(date +"%Y%m%d_%H%M%S")
    echo "Committing changes with timestamp: $timestamp..."
    git commit -m "$timestamp"
    if [ $? -ne 0 ]; then
        echo "Failed to commit changes."
        sleep 3
        exit 1
    fi
    # Pull latest changes from the remote repository
    echo "Pulling latest changes from origin/$current_branch..."
    git pull --no-rebase origin $current_branch
    if [ $? -ne 0 ]; then
        echo "Failed to pull changes. Resolve conflicts if any, and rerun the script."
        sleep 3
        exit 1
    fi
    # Push changes to the repository
    echo "Pushing changes to origin/$current_branch..."
    git push origin $current_branch
    if [ $? -ne 0 ]; then
        echo "Failed to push changes."
        sleep 3
        exit 1
    fi
    echo ""
    echo "[OK] Changes successfully committed and pushed."
    echo ""
else
    echo "No changes to commit."
    echo ""
fi
echo ""
echo "Final check before cleanup..."
commit_count=$(git rev-list --count HEAD)
echo "Current commits: $commit_count"
echo "Commits to keep: $keep_commits"
echo ""
if [ "$commit_count" -le "$keep_commits" ]; then
    echo "Only $commit_count commits exist. No cleanup needed (keeping $keep_commits)."
    sleep 3
    exit 0
fi
echo "Will keep the last $keep_commits commits and delete $((commit_count - keep_commits)) old commits."
echo ""
echo "Creating backup branch..."
git branch backup-before-cleanup 2>/dev/null
nth_commit_index=$((keep_commits - 1))
echo "Getting commit hash for keeping last $keep_commits commits..."
nth_commit=$(git rev-parse HEAD~$nth_commit_index)
echo "Creating new root commit..."
git checkout --orphan temp $nth_commit
git commit -m "Truncated history root"
echo "Rebasing last $keep_commits commits onto new root..."
git rebase --onto temp $nth_commit $current_branch
if [ $? -ne 0 ]; then
    echo "Error during rebase. Aborting..."
    git rebase --abort
    git checkout $current_branch
    git branch -D temp
    sleep 3
    exit 1
fi
echo "Cleaning up temporary branch..."
git branch -D temp
echo "Running garbage collection..."
git gc --aggressive --prune=all
echo "Force pushing to remote..."
git push -f origin $current_branch
echo ""
echo "Cleanup completed successfully!"
new_count=$(git rev-list --count HEAD)
echo "New commit count: $new_count"
echo ""
# Restore .gitignore files after Git operations
restore_gitignore_files
echo "Deleting backup branch..."
git branch -D backup-before-cleanup
echo ""
echo "[OK] Backup branch deleted."
echo ""
sleep 5
