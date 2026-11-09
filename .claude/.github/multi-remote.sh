#!/usr/bin/env bash
# ============================================================
# 工具名称: 多平台 Git 同步工具 (multi-remote.sh)
# 用途: 对 Gitee/GitHub/GitLab 多个远端执行 push/pull/sync/status 操作
# ============================================================

# 一、为什么需要这个脚本？
#     项目代码需要同时维护在 Gitee、GitHub、GitLab(私服) 三个平台，
#     手动逐个执行 git push/pull 容易遗漏或出错。本脚本提供统一的
#     交互式菜单，自动管理 remote 配置，支持批量推送到全部远端。

# 二、工具链与调用流程
#     用户运行脚本 -> 选择目标远端(Gitee/GitHub/GitLab/全部)
#         -> 选择操作(push/pull/sync/status)
#         -> 自动检查/添加 remote -> 执行 git 命令 -> 显示结果

# 三、脚本没有负责的事（刻意排除）
#     - 不处理分支创建/删除
#     - 不解决合并冲突（冲突时提示用户手动处理）
#     - 不管理 SSH 密钥（依赖用户本地已配置好 SSH 免密）

# 四、交互设计原则
#     两级菜单：第一级选远端，第二级选操作。
#     q 退出程序，b 返回上一级。
#     操作完成后暂停等待用户按 Enter，方便查看输出结果。
#     命令行直通模式：支持直接传参跳过交互。

# 五、分支策略说明（重要）
#     Push（上传）：推送全部本地分支 + 来源远程分支 + 所有标签
#         - git push --all  推送所有本地分支（包括分支上的全部内容/提交历史）
#         - 显式 refspec 推送 refs/remotes/${SOURCE_REMOTE}/* 到目标 refs/heads/*
#         - 排除 ${SOURCE_REMOTE}/HEAD，避免把远程 HEAD 指针当真实分支
#         - git push --tags 推送所有标签（轻量标签 + 附注标签）
#         - 推送后用 git ls-remote --heads --tags 验证目标分支/tag 数量
#         - 各步骤独立捕获退出码，任一失败即标记为失败
#     Pull（下载）：只拉取远端与当前同名的分支（git pull remote current_branch）
#     Sync（同步）：fetch 远端后 merge 当前同名分支到本地
#     Status（查看状态）：显示当前分支与远端的差异

# 六、自动提交策略（push 前自动执行）
#     每次 push 前，脚本会自动检查工作区是否有未提交的更改：
#         1. git add -A                   暂存所有更改（含新增/修改/删除）
#         2. git diff --staged --quiet    检查暂存区是否为空
#         3. 若有更改 → git commit -m "yyyyMMdd_HHmmss"（时间戳作为提交信息）
#         4. 若无更改 → 跳过提交，直接推送
#     设计要点：
#     - COMMIT_DONE 全局标记：选"全部远端"时遍历3个remote，自动提交只在
#       第一个remote的push前执行一次，后续跳过，避免重复提交
#     - 提交失败（如缺少 user.name/user.email）仅警告，不阻断后续推送
#     - 仅 push 操作触发自动提交，pull/sync/status 不触发

# 七、关键技术决策记录
#
#     7.1 git fetch 不带分支名
#         原因：git fetch <remote> <branch> 只把数据下载到 FETCH_HEAD，
#         不会更新远程跟踪分支（如 gitee/master）。后续 git merge 和
#         git log 引用的是 remote/branch 跟踪分支，如果它没被更新，
#         比较结果就是空的或过时的。
#         方案：改为 git fetch <remote>（不带分支名），Git 会自动更新
#         该 remote 下所有分支的跟踪引用。
#
#     7.2 git --no-pager log
#         原因：Git 默认在输出超过一屏时调用 less/vim 等分页器（PAGER），
#         在脚本交互中会让用户卡在分页器里无法操作。
#         方案：使用 git --no-pager log 直接输出到终端，不进入分页器。
#
#     7.3 Bash 3.x 兼容（macOS）
#         原因：macOS 自带 /bin/bash 3.2.57，不支持 declare -A（关联数组）。
#         方案：使用前缀变量 + 间接引用 ${!var} 替代关联数组。
#         示例：REMOTE_URLS_gitee="..." → var="REMOTE_URLS_gitee" → echo ${!var}
#
#     7.4 退出码捕获
#         原因：set -e 环境下 git 命令失败会导致脚本退出，而 || true 会
#         让 $? 永远为0，丢失真实的退出码。
#         方案：初始化变量为0，使用 || var=$? 模式捕获真实退出码。
#
#     7.5 全部远端遍历输出
#         原因：选"全部远端"时三个remote的输出混在一起，难以区分。
#         方案：每个 remote 前后添加 ═══ 分隔线 + 远端名称标题。
#
#     7.6 .git/config 保护机制（完整还原）
#         脚本启动时拍快照，记录每个已有 remote 的名称 + URL。
#         ensure_remote 不仅检查名称是否存在，还会检查 URL 是否匹配：
#         - 名称不存在 → git remote add（新增）
#         - 名称存在但 URL 不同 → git remote set-url（修正）
#         退出时 (trap EXIT) 完整还原：
#         - 脚本新添加的 remote → git remote remove（删除）
#         - URL 被修改的 remote → git remote set-url（还原原始 URL）
#         原有的 origin 等完全不触碰（除非名称恰好是 gitee/github/gitlab）。
#         pull/sync/status 操作本身不会修改任何 git 配置。
#
#     7.7 远程连通性预检测（网络不通快速跳过）
#         执行任何操作前，先对目标 remote 执行 git ls-remote
#         快速探测（不带 --exit-code 和 HEAD，兼容空仓库）：
#         - 可达 → 正常执行操作
#         - 不可达 → 立即跳过并提示 [SKIP]，不卡等超时
#         全局设置 GIT_SSH_COMMAND 添加 ConnectTimeout=5，
#         确保所有 git 命令最多 5 秒连接超时，避免网络不通时卡死。
#
#     7.8 自动创建仓库（默认关闭）
#         当远端仓库不存在时（非网络问题），可根据全局开关决定行为：
#         AUTO_CREATE_REPO=false（默认）→ 跳过，保持原有行为
#         AUTO_CREATE_REPO=true         → 调用平台 API 创建私有仓库
#         需要在配置区填写对应平台的 API Token：
#           GitHub: Settings → Developer settings → Personal access tokens → repo 权限
#           Gitee:  设置 → 私人令牌 → projects 权限
#           GitLab: 设置 → Access Tokens → api 权限
#         创建成功后自动继续执行 push，无需手动干预。
#
#     7.9 全量迁移分支策略
#         git push --all 只推送本地分支，无法覆盖“只存在于来源远程跟踪引用”
#         的分支。因此 push 时会额外读取 refs/remotes/${SOURCE_REMOTE}/*，
#         用显式 refspec 推送到目标 refs/heads/*，并排除 ${SOURCE_REMOTE}/HEAD。
#         默认来源远程是 origin；如需从旧远程迁移，可执行：
#           SOURCE_REMOTE=old-origin ./multi-remote.sh --remote gitlab push

# 八、换行符与兼容性
#     本文件使用 LF 换行符，兼容 bash 和 zsh。

# ============================================================
# 用户配置区（修改以下变量即可适配其他仓库）
# ============================================================
# REPO_NAME 自动推导：从脚本所在目录的上级目录名获取（即项目根目录名）
# 如需手动指定，取消下行注释并修改值，注释掉自动推导行
# REPO_NAME="custom-repo-name"

# 自动推导：获取项目根目录名（脚本在 .github/ 子目录）
SCRIPT_DIR_CONFIG="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR_CONFIG="$(cd "${SCRIPT_DIR_CONFIG}/.." && pwd)"
REPO_NAME="${REPO_NAME:-$(basename "${PROJECT_DIR_CONFIG}")}"

USERNAME="halavah"              # 用户名（Gitee/GitHub）
GITLAB_NAMESPACE="demo"        # GitLab 命名空间（组名或用户名）

REMOTE_GITEE="git@gitee.com:${USERNAME}/${REPO_NAME}.git"
REMOTE_GITHUB="git@github.com:${USERNAME}/${REPO_NAME}.git"
REMOTE_GITLAB="http://192.168.3.200/${GITLAB_NAMESPACE}/${REPO_NAME}.git"

# API Token（自动创建仓库功能，需配合 AUTO_CREATE_REPO=true 开启）
# 获取方式：
#   GitHub: Settings → Developer settings → Personal access tokens → repo 权限
#   Gitee:  设置 → 私人令牌 → projects 权限
#   GitLab: 设置 → Access Tokens → api 权限
GITHUB_TOKEN=""
GITEE_TOKEN=""
GITLAB_TOKEN=""

# 全局开关：仓库不存在时是否自动创建私有仓库（默认关闭）
# true  = 仓库不存在时调用 API 自动创建私有仓库，然后继续推送
# false = 仓库不存在时直接跳过，保持原有行为
AUTO_CREATE_REPO=false

# 全量分支迁移的来源远程：默认读取 origin/*；旧仓库迁移时可临时设为 old-origin
SOURCE_REMOTE="${SOURCE_REMOTE:-origin}"
TARGET_BRANCH="${TARGET_BRANCH:-master}"
# ============================================================

set -e

# 全局 SSH 超时：所有 git 命令最多 5 秒连接超时，避免网络不通时卡死
export GIT_SSH_COMMAND="ssh -o ConnectTimeout=5 -o BatchMode=yes"

# 自动修复当前脚本的权限
if [ ! -x "$0" ]; then
    chmod +x "$0"
    echo "Fixed script permissions. Restarting..."
    exec "$0" "$@"
fi

# 锁定工作目录到脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 回到项目根目录（脚本在 .github/ 子目录，上级就是项目根）
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

# 检查是否在 git 仓库中，不是则自动初始化
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "[WARN] 当前目录不是 Git 仓库，正在自动初始化..."
    git init
    if [ $? -ne 0 ]; then
        echo "[ERROR] git init 失败"
        exit 1
    fi
    echo "[INFO] git init 完成"

    # 确保默认分支为 master
    git checkout -b master 2>/dev/null || true

    # 检查是否有 .gitignore
    if [ ! -f ".gitignore" ]; then
        echo "[INFO] 创建默认 .gitignore"
        cat > .gitignore << 'GITIGNORE'
node_modules/
dist/
.DS_Store
*.log
.env
.env.local
.env.*.local
.idea/
.vscode/
GITIGNORE
    fi

    # 暂存所有文件
    git add -A
    if git diff --staged --quiet; then
        echo "[WARN] 没有文件可提交"
    else
        local_ts=$(date +"%Y%m%d_%H%M%S")
        echo "[INFO] 创建初始提交: ${local_ts}"
        git commit -m "${local_ts}"
        if [ $? -ne 0 ]; then
            echo "[ERROR] 初始提交失败（可能缺少 user.name/user.email）"
            echo "  请运行: git config user.name 'Your Name' && git config user.email 'you@example.com'"
            exit 1
        fi
        echo "[OK] Git 仓库初始化并完成首次提交"
    fi
fi

# 拍快照：记录脚本启动前已有的 remote 名称 + URL（退出时完整还原）
EXISTING_REMOTES="$(git remote)"
EXISTING_REMOTE_SNAPSHOT="$(mktemp)"
for r in ${EXISTING_REMOTES}; do
    printf '%s\t%s\n' "${r}" "$(git remote get-url "${r}")" >> "${EXISTING_REMOTE_SNAPSHOT}"
done

remote_existed_before_start() {
    printf '%s\n' "${EXISTING_REMOTES}" | grep -Fxq "$1"
}

get_saved_remote_url() {
    awk -F '\t' -v name="$1" '$1 == name {print $2; exit}' "${EXISTING_REMOTE_SNAPSHOT}"
}

# 退出时还原：删除脚本添加的 remote / 还原被修改的 URL
cleanup_remotes() {
    for remote in "${REMOTE_NAMES[@]}"; do
        if ! remote_existed_before_start "${remote}"; then
            # 脚本新添加的 remote → 删除
            if git remote | grep -q "^${remote}$"; then
                echo "[INFO] 清理 remote: ${remote}"
                git remote remove "${remote}" 2>/dev/null || true
            fi
        else
            # 脚本修改了 URL 的 remote → 还原原始 URL
            local saved_url
            saved_url="$(get_saved_remote_url "${remote}")"
            if [ -n "${saved_url}" ]; then
                local current_url
                current_url=$(git remote get-url "${remote}" 2>/dev/null || echo "")
                if [ -n "${current_url}" ] && [ "${current_url}" != "${saved_url}" ]; then
                    echo "[INFO] 还原 remote URL: ${remote} -> ${saved_url}"
                    git remote set-url "${remote}" "${saved_url}" 2>/dev/null || true
                fi
            fi
        fi
    done
    rm -f "${EXISTING_REMOTE_SNAPSHOT}"
}
trap cleanup_remotes EXIT

# 获取当前分支名
get_current_branch() {
    git rev-parse --abbrev-ref HEAD
}

# 全局标记：防止全部远端模式下重复提交
COMMIT_DONE=0

# 自动提交（如有未暂存更改）
auto_commit_if_needed() {
    if [ ${COMMIT_DONE} -eq 1 ]; then
        return 0
    fi
    git add -A
    if git diff --staged --quiet; then
        return 0
    fi
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    echo "[INFO] 发现未提交更改，自动提交: ${timestamp}"
    if ! git commit -m "${timestamp}"; then
        echo "[WARN] 自动提交失败，跳过（可能缺少 user.name/user.email）"
        return 0
    fi
    COMMIT_DONE=1
}

# 检查并添加/更新 remote（URL 不一致时自动修正）
ensure_remote() {
    local name="$1"
    local url="$2"
    if ! git remote | grep -q "^${name}$"; then
        echo "[INFO] 添加 remote: ${name} -> ${url}"
        git remote add "${name}" "${url}"
    else
        local current_url
        current_url=$(git remote get-url "${name}")
        if [ "${current_url}" != "${url}" ]; then
            echo "[INFO] 更新 remote URL: ${name} ${current_url} -> ${url}"
            git remote set-url "${name}" "${url}"
        fi
    fi
}

# 定义远端信息
REMOTE_NAMES=("gitee" "github" "gitlab")

REMOTE_URLS_gitee="${REMOTE_GITEE}"
REMOTE_URLS_github="${REMOTE_GITHUB}"
REMOTE_URLS_gitlab="${REMOTE_GITLAB}"

REMOTE_LABELS_gitee="Gitee"
REMOTE_LABELS_github="GitHub"
REMOTE_LABELS_gitlab="GitLab"

# Bash 3.x 兼容：间接引用获取远端 URL
get_remote_url() {
    local key="$1"
    local var="REMOTE_URLS_${key}"
    echo "${!var}"
}

# Bash 3.x 兼容：间接引用获取远端显示名
get_remote_label() {
    local key="$1"
    local var="REMOTE_LABELS_${key}"
    echo "${!var}"
}

# 预检查所有 remote
for remote in "${REMOTE_NAMES[@]}"; do
    ensure_remote "${remote}" "$(get_remote_url "${remote}")"
done

# 显示 Git 操作结果
show_result() {
    local op="$1"
    local remote="$2"
    local code="$3"
    if [ ${code} -eq 0 ]; then
        echo "[OK] ${op} 操作成功: $(get_remote_label "${remote}") (${remote})"
    else
        echo "[ERROR] ${op} 操作失败: $(get_remote_label "${remote}") (${remote}), 退出码: ${code}"
    fi
}

# 输出来源分支名：本地分支 + 来源远程跟踪分支，去掉 SOURCE_REMOTE/HEAD
list_source_branch_names() {
    git for-each-ref --format='%(refname:short)' refs/heads
    if git remote get-url "${SOURCE_REMOTE}" > /dev/null 2>&1; then
        git for-each-ref --format='%(refname)' "refs/remotes/${SOURCE_REMOTE}" | while IFS= read -r ref; do
            [ -z "${ref}" ] && continue
            [ "${ref}" = "refs/remotes/${SOURCE_REMOTE}/HEAD" ] && continue
            echo "${ref#refs/remotes/${SOURCE_REMOTE}/}"
        done
    fi
}

# 推送来源远程跟踪分支，覆盖 git push --all 无法处理的远程-only 分支
push_remote_tracking_branches() {
    local remote="$1"
    local refs_file ref branch
    local fetch_code=0 refspec_code=0 pushed_count=0

    if ! git remote get-url "${SOURCE_REMOTE}" > /dev/null 2>&1; then
        echo "[INFO] 来源远程 ${SOURCE_REMOTE} 不存在，跳过远程跟踪分支 refspec 推送"
        return 0
    fi

    echo "[INFO] 正在刷新来源远程 ${SOURCE_REMOTE} 的分支引用..."
    git fetch "${SOURCE_REMOTE}" --prune || fetch_code=$?
    if [ ${fetch_code} -ne 0 ]; then
        echo "[ERROR] fetch ${SOURCE_REMOTE} 失败，无法推送远程跟踪分支"
        return ${fetch_code}
    fi

    refs_file="$(mktemp)"
    git for-each-ref --format='%(refname)' "refs/remotes/${SOURCE_REMOTE}" > "${refs_file}"
    while IFS= read -r ref; do
        [ -z "${ref}" ] && continue
        [ "${ref}" = "refs/remotes/${SOURCE_REMOTE}/HEAD" ] && continue
        branch="${ref#refs/remotes/${SOURCE_REMOTE}/}"
        echo "[INFO] refspec 推送来源分支 ${SOURCE_REMOTE}/${branch} -> ${remote}/${branch}"
        git push "${remote}" "refs/remotes/${SOURCE_REMOTE}/${branch}:refs/heads/${branch}" || refspec_code=$?
        pushed_count=$((pushed_count + 1))
    done < "${refs_file}"
    rm -f "${refs_file}"

    echo "[INFO] 来源远程跟踪分支 refspec 推送完成: ${pushed_count} 个"
    return ${refspec_code}
}

# 推送后验证目标远程的分支/tag 数量
verify_remote_refs() {
    local remote="$1"
    local target_refs source_branch_count source_tag_count target_branch_count target_tag_count ls_code=0

    source_branch_count=$(list_source_branch_names | awk 'NF' | sort -u | wc -l | tr -d ' ')
    source_tag_count=$(git tag -l | awk 'NF' | wc -l | tr -d ' ')
    target_refs=$(git ls-remote --heads --tags "${remote}") || ls_code=$?
    if [ ${ls_code} -ne 0 ]; then
        echo "[ERROR] git ls-remote --heads --tags ${remote} 验证失败"
        return ${ls_code}
    fi

    target_branch_count=$(printf '%s\n' "${target_refs}" | awk '$2 ~ /^refs\/heads\// {c++} END {print c+0}')
    target_tag_count=$(printf '%s\n' "${target_refs}" | awk '$2 ~ /^refs\/tags\// && $2 !~ /\^\{\}$/ {c++} END {print c+0}')

    echo "[INFO] 验证远程引用: 来源分支=${source_branch_count}, 目标分支=${target_branch_count}; 来源tags=${source_tag_count}, 目标tags=${target_tag_count}"
    if [ "${source_branch_count}" = "${target_branch_count}" ] && [ "${source_tag_count}" = "${target_tag_count}" ]; then
        echo "[OK] 目标远程分支/tag 数量一致"
        return 0
    fi

    echo "[ERROR] 目标远程分支/tag 数量不一致，请检查 git ls-remote --heads --tags ${remote}"
    return 1
}

# 执行 push 操作（只推送指定分支到同名远端分支）
do_push() {
    local remote="$1"
    local push_code=0 verify_code=0
    local verify_refs=""
    auto_commit_if_needed
    if ! git show-ref --verify --quiet "refs/heads/${TARGET_BRANCH}"; then
        echo "[ERROR] 本地分支不存在: ${TARGET_BRANCH}"
        show_result "push" "${remote}" 1
        return 1
    fi
    echo "[INFO] 正在推送到 $(get_remote_label "${remote}") (${remote}) [仅分支: ${TARGET_BRANCH} -> ${TARGET_BRANCH}]..."
    git push "${remote}" "refs/heads/${TARGET_BRANCH}:refs/heads/${TARGET_BRANCH}" || push_code=$?
    if [ ${push_code} -eq 0 ]; then
        verify_refs=$(git ls-remote --heads "${remote}" "refs/heads/${TARGET_BRANCH}" 2>/dev/null || true)
        [ -n "${verify_refs}" ] || verify_code=1
    else
        verify_code=1
    fi
    if [ ${push_code} -eq 0 ] && [ ${verify_code} -eq 0 ]; then
        show_result "push" "${remote}" 0
    else
        show_result "push" "${remote}" 1
    fi
}

# 执行 pull 操作（只拉取当前同名分支）
do_pull() {
    local remote="$1"
    local branch
    local pull_code=0
    branch=$(get_current_branch)
    echo "[INFO] 正在从 $(get_remote_label "${remote}") (${remote}) 拉取 [当前同名分支: ${branch}]..."
    git pull "${remote}" "${branch}" || pull_code=$?
    show_result "pull" "${remote}" ${pull_code}
}

# 执行 sync 操作 (fetch + merge)
do_sync() {
    local remote="$1"
    local branch
    local fetch_code=0 merge_code=0
    branch=$(get_current_branch)
    echo "[INFO] 正在同步 $(get_remote_label "${remote}") (${remote}) [分支: ${branch}]..."
    git fetch "${remote}" || fetch_code=$?
    if [ ${fetch_code} -eq 0 ]; then
        git merge "${remote}/${branch}" --no-edit || merge_code=$?
    fi
    if [ ${fetch_code} -eq 0 ] && [ ${merge_code} -eq 0 ]; then
        show_result "sync" "${remote}" 0
    else
        show_result "sync" "${remote}" 1
    fi
}

# 执行 status 操作
do_status() {
    local remote="$1"
    local branch
    branch=$(get_current_branch)
    echo "[INFO] 查看 $(get_remote_label "${remote}") (${remote}) 状态 [分支: ${branch}]..."
    git fetch "${remote}" || true
    echo ""
    echo "--- 本地分支状态 ---"
    git status -sb
    echo ""
    echo "--- 与 $(get_remote_label "${remote}") 的差异 ---"
    git --no-pager log --oneline --left-right "HEAD...${remote}/${branch}" -- || true
    show_result "status" "${remote}" 0
}

# 调用平台 API 创建私有仓库
create_repo() {
    local remote="$1"
    local token="" api_url="" result=""
    case "${remote}" in
        github)
            token="${GITHUB_TOKEN}"
            api_url="https://api.github.com/user/repos"
            if [ -z "${token}" ]; then
                echo "[SKIP] $(get_remote_label "${remote}") (${remote}) 未配置 GITHUB_TOKEN，无法创建仓库"
                return 1
            fi
            echo "[INFO] 尝试创建 GitHub 私有仓库: ${REPO_NAME}"
            result=$(curl -s -w "\n%{http_code}" -X POST "${api_url}" \
                -H "Authorization: token ${token}" \
                -H "Accept: application/vnd.github.v3+json" \
                -d "{\"name\":\"${REPO_NAME}\",\"private\":true}" 2>&1)
            ;;
        gitee)
            token="${GITEE_TOKEN}"
            api_url="https://gitee.com/api/v5/user/repos"
            if [ -z "${token}" ]; then
                echo "[SKIP] $(get_remote_label "${remote}") (${remote}) 未配置 GITEE_TOKEN，无法创建仓库"
                return 1
            fi
            echo "[INFO] 尝试创建 Gitee 私有仓库: ${REPO_NAME}"
            result=$(curl -s -w "\n%{http_code}" -X POST "${api_url}" \
                -d "access_token=${token}&name=${REPO_NAME}&private=true" 2>&1)
            ;;
        gitlab)
            token="${GITLAB_TOKEN}"
            api_url="http://192.168.3.200/api/v4/projects"
            if [ -z "${token}" ]; then
                echo "[SKIP] $(get_remote_label "${remote}") (${remote}) 未配置 GITLAB_TOKEN，无法创建仓库"
                return 1
            fi
            echo "[INFO] 尝试在 GitLab (${GITLAB_NAMESPACE}) 下创建仓库: ${REPO_NAME}"
            result=$(curl -s -w "\n%{http_code}" -X POST "${api_url}" \
                -H "PRIVATE-TOKEN: ${token}" \
                -d "name=${REPO_NAME}&namespace_path=${GITLAB_NAMESPACE}&visibility=private" 2>&1)
            ;;
        *)
            echo "[SKIP] 未知远端: ${remote}"
            return 1
            ;;
    esac
    local http_code
    http_code=$(echo "${result}" | tail -1)
    if [ "${http_code}" = "201" ] || [ "${http_code}" = "200" ]; then
        echo "[OK] 仓库创建成功: $(get_remote_label "${remote}") (${remote})"
        return 0
    else
        echo "[SKIP] $(get_remote_label "${remote}") (${remote}) 仓库创建失败 (HTTP ${http_code})"
        return 1
    fi
}

# 快速检测远端连通性（区分网络不通 / 仓库不存在）
check_remote() {
    local remote="$1"
    if git ls-remote "${remote}" > /dev/null 2>&1; then
        return 0
    fi

    # ls-remote 失败，区分原因
    local err_output
    err_output=$(git ls-remote "${remote}" 2>&1 || true)

    # 网络不通（超时/连接拒绝/无路由）
    if echo "${err_output}" | grep -qi "timed out\|connection refused\|no route\|network is unreachable\|could not resolve"; then
        echo "[SKIP] $(get_remote_label "${remote}") (${remote}) 网络不可达，跳过"
        return 1
    fi

    # 仓库不存在
    if [ "${AUTO_CREATE_REPO}" = "true" ]; then
        if create_repo "${remote}"; then
            return 0
        fi
        return 1
    fi

    echo "[SKIP] $(get_remote_label "${remote}") (${remote}) 仓库不存在或不可达，跳过"
    return 1
}

# 对单个远端执行操作
execute_operation() {
    local remote="$1"
    local op="$2"
    if ! check_remote "${remote}"; then
        return 0
    fi
    case "${op}" in
        push)   do_push "${remote}" ;;
        pull)   do_pull "${remote}" ;;
        sync)   do_sync "${remote}" ;;
        status) do_status "${remote}" ;;
    esac
}

# 命令行直通模式
if [ $# -gt 0 ]; then
    case "$1" in
        --all|-a)
            op="${2:-push}"
            for remote in "${REMOTE_NAMES[@]}"; do
                execute_operation "${remote}" "${op}"
                echo ""
            done
            exit 0
            ;;
        --remote|-r)
            remote="$2"
            op="${3:-push}"
            if [ -z "${remote}" ]; then
                echo "[ERROR] 请指定远端名称: gitee/github/gitlab"
                exit 1
            fi
            execute_operation "${remote}" "${op}"
            exit 0
            ;;
        --help|-h)
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --all, -a [op]     对所有远端执行操作 (默认: push)"
            echo "  --remote, -r <n> [op] 对指定远端执行操作 (默认: push)"
            echo "  --help, -h         显示帮助"
            echo ""
            echo "操作: push, pull, sync, status"
            exit 0
            ;;
    esac
fi

# 主循环（第一级：选择远端）
while true; do
    clear
    echo "========================================"
    echo "    多平台 Git 同步工具"
    echo "========================================"
    echo ""
    echo "请选择目标远端:"
    echo "  1. Gitee    (${REMOTE_GITEE})"
    echo "  2. GitHub   (${REMOTE_GITHUB})"
    echo "  3. GitLab   (${REMOTE_GITLAB})"
    echo "  4. 全部远端 (依次操作所有平台)"
    echo ""
    echo "========================================"
    echo ""
    read -p "Enter number (1-4) [Enter 'q' to quit]: " remote_choice

    case "${remote_choice}" in
        q|Q|9)
            echo "Bye!"
            exit 0
            ;;
        1) selected_remote="gitee" ;;
        2) selected_remote="github" ;;
        3) selected_remote="gitlab" ;;
        4) selected_remote="all" ;;
        *)
            echo "[ERROR] 无效输入，请重试"
            sleep 1
            continue
            ;;
    esac

    # 第二级循环（选择操作）
    while true; do
        clear
        echo "========================================"
        echo "    多平台 Git 同步工具"
        echo "========================================"
        echo ""
        if [ "${selected_remote}" = "all" ]; then
            echo "已选择: 全部远端"
        else
            echo "已选择: $(get_remote_label "${selected_remote}") (${selected_remote})"
        fi
        echo ""
        echo "请选择操作:"
        echo "  1. 上传 (push)    -> 推送当前分支到远端"
        echo "  2. 下载 (pull)    -> 从远端拉取当前分支"
        echo "  3. 同步 (sync)    -> fetch + merge，合并远端更新"
        echo "  4. 查看状态       -> 显示当前分支与远端的差异"
        echo ""
        echo "========================================"
        echo ""
        read -p "Enter number (1-4) [Enter 'b' to go back]: " op_choice

        case "${op_choice}" in
            b|B)
                break
                ;;
            1) selected_op="push" ;;
            2) selected_op="pull" ;;
            3) selected_op="sync" ;;
            4) selected_op="status" ;;
            *)
                echo "[ERROR] 无效输入，请重试"
                sleep 1
                continue
                ;;
        esac

        clear
        echo "========================================"
        echo "    执行操作"
        echo "========================================"
        echo ""

        current_branch=$(get_current_branch)
        echo "[INFO] 当前分支: ${current_branch}"
        echo ""

        if [ "${selected_remote}" = "all" ]; then
            for remote in "${REMOTE_NAMES[@]}"; do
                echo "═══════════════════════════════════════"
                echo "  远端: $(get_remote_label "${remote}") (${remote})"
                echo "═══════════════════════════════════════"
                execute_operation "${remote}" "${selected_op}"
                echo ""
            done
        else
            execute_operation "${selected_remote}" "${selected_op}"
        fi

        echo ""
        echo "[OK] 操作完毕！"
        echo ""
        read -p "按 Enter 继续" dummy
    done
done
