#!/usr/bin/env bash
# ============================================================
# 工具名称: Git Origin / Branch 交互切换工具 (multi-origin.sh)
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
SCRIPT_DIR_CONFIG="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR_CONFIG="$(cd "${SCRIPT_DIR_CONFIG}/.." && pwd)"
REPO_NAME="${REPO_NAME:-$(basename "${PROJECT_DIR_CONFIG}")}"

USERNAME="halavah"
GITLAB_NAMESPACE="demo"

REMOTE_GITEE="git@gitee.com:${USERNAME}/${REPO_NAME}.git"
REMOTE_GITHUB="git@github.com:${USERNAME}/${REPO_NAME}.git"
REMOTE_GITLAB="http://192.168.3.200/${GITLAB_NAMESPACE}/${REPO_NAME}.git"
# ============================================================

set -e

if [ ! -x "$0" ]; then
    chmod +x "$0"
    exec "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "[ERROR] 当前目录不是 Git 仓库"
    exit 1
fi

print_divider() {
    printf '\n============================================================\n'
}

get_current_branch() {
    git rev-parse --abbrev-ref HEAD
}

get_origin_url() {
    git remote get-url origin 2>/dev/null || true
}

branch_exists_local() {
    git show-ref --verify --quiet "refs/heads/$1"
}

ensure_origin() {
    local url="$1"
    if git remote get-url origin >/dev/null 2>&1; then
        git remote set-url origin "$url"
    else
        git remote add origin "$url"
    fi
}

set_branch_tracking() {
    local branch="$1"
    git config "branch.${branch}.remote" "origin"
    git config "branch.${branch}.merge" "refs/heads/${branch}"
}

prompt_remote_url() {
    local current_origin custom_url choice
    current_origin="$(get_origin_url)"

    print_divider
    echo "当前项目: ${REPO_NAME}"
    echo "当前 origin: ${current_origin:-<未配置>}"
    echo
    echo "请选择要写入 origin 的地址："
    echo "  1) Gitee   ${REMOTE_GITEE}"
    echo "  2) GitHub  ${REMOTE_GITHUB}"
    echo "  3) GitLab  ${REMOTE_GITLAB}"
    echo "  4) 保持当前 origin 不变"
    echo "  5) 手动输入自定义 URL"
    echo "  q) 退出"
    printf "请输入选项: "
    read -r choice

    case "${choice}" in
        1) SELECTED_REMOTE_URL="${REMOTE_GITEE}" ;;
        2) SELECTED_REMOTE_URL="${REMOTE_GITHUB}" ;;
        3) SELECTED_REMOTE_URL="${REMOTE_GITLAB}" ;;
        4)
            if [ -n "${current_origin}" ]; then
                SELECTED_REMOTE_URL="${current_origin}"
            else
                echo "[WARN] 当前 origin 为空，请重新选择"
                prompt_remote_url
                return
            fi
            ;;
        5)
            printf "请输入完整远端 URL: "
            read -r custom_url
            if [ -z "${custom_url}" ]; then
                echo "[WARN] URL 不能为空，请重新选择"
                prompt_remote_url
                return
            fi
            SELECTED_REMOTE_URL="${custom_url}"
            ;;
        q|Q)
            echo "[INFO] 已退出"
            exit 0
            ;;
        *)
            echo "[WARN] 无效选项，请重新选择"
            prompt_remote_url
            ;;
    esac
}

prompt_target_branch() {
    local current_branch input_branch
    current_branch="$(get_current_branch)"

    print_divider
    echo "当前分支: ${current_branch}"
    printf "请输入目标分支名（直接回车默认使用当前分支）: "
    read -r input_branch

    if [ -z "${input_branch}" ]; then
        TARGET_BRANCH_NAME="${current_branch}"
    else
        TARGET_BRANCH_NAME="${input_branch}"
    fi
}

switch_branch_if_needed() {
    local current_branch target choice
    target="$1"
    current_branch="$(get_current_branch)"

    if [ "${current_branch}" = "${target}" ]; then
        echo "[INFO] 当前已经在分支 ${target}"
        return
    fi

    if branch_exists_local "${target}"; then
        echo "[INFO] 切换到已存在的本地分支: ${target}"
        git checkout "${target}"
        return
    fi

    print_divider
    echo "本地分支 ${target} 不存在。"
    echo "请选择处理方式："
    if [ "${current_branch}" != "HEAD" ]; then
        echo "  1) 把当前分支 ${current_branch} 重命名为 ${target}（推荐）"
    else
        echo "  1) 当前为 detached HEAD，改为从当前提交新建 ${target}"
    fi
    echo "  2) 基于当前提交新建分支 ${target}"
    echo "  q) 退出"
    printf "请输入选项: "
    read -r choice

    case "${choice}" in
        1)
            if [ "${current_branch}" != "HEAD" ]; then
                git branch -m "${target}"
            else
                git checkout -b "${target}"
            fi
            ;;
        2)
            git checkout -b "${target}"
            ;;
        q|Q)
            echo "[INFO] 已退出"
            exit 0
            ;;
        *)
            echo "[WARN] 无效选项，请重新选择"
            switch_branch_if_needed "${target}"
            ;;
    esac
}

show_summary() {
    local final_branch final_origin branch_remote branch_merge
    final_branch="$(get_current_branch)"
    final_origin="$(get_origin_url)"
    branch_remote="$(git config --get "branch.${final_branch}.remote" 2>/dev/null || true)"
    branch_merge="$(git config --get "branch.${final_branch}.merge" 2>/dev/null || true)"

    print_divider
    echo "[OK] 切换完成"
    echo "项目目录: ${PROJECT_DIR}"
    echo "当前分支: ${final_branch}"
    echo "origin 地址: ${final_origin:-<未配置>}"
    echo "branch.${final_branch}.remote = ${branch_remote:-<未配置>}"
    echo "branch.${final_branch}.merge  = ${branch_merge:-<未配置>}"
    echo
    git remote -v | sed 's/^/  /'
    echo
    git branch --list | sed 's/^/  /'
}

main() {
    local selected_branch

    prompt_remote_url
    ensure_origin "${SELECTED_REMOTE_URL}"

    prompt_target_branch
    selected_branch="${TARGET_BRANCH_NAME}"

    switch_branch_if_needed "${selected_branch}"
    set_branch_tracking "${selected_branch}"
    show_summary

    echo
    printf "按 Enter 结束..."
    read -r _
}

main "$@"
