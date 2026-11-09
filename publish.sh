#!/bin/bash
# =============================================================================
# Libra Boot Low 发布器 — Bash
#
# 一、为什么需要这个脚本？
#     发布 PyPI 包需手动改两处版本号（generator.py --version 与 pyproject.toml）、
#     commit、打 v* 标签、push——步骤多且两处版本号易漏改漂移。本脚本一条命令
#     完成全链，版本单源改动零漂移。
#
# 二、工具链与调用流程
#     publish.sh [1|2|3]
#       → 自动递增版本（patch 或 minor）→ 同步改 generator.py + pyproject.toml
#       → py_compile 语法闸 → pytest 快闸 → git commit → tag vX.Y.Z
#       → y/N 确认 → push（master+tags）→ GitHub Actions 自动构建上架 PyPI
#
# 三、脚本没有负责的事（刻意排除）
#     - 不本地 build/上传（构建与发布归 CI 的 pypi.yml，OIDC 免密）
#     - 不改 README 安装通道里的 wheel 版本号（README 已指向 PyPI 页面动态态）
#     - 不动 CHANGELOG/文档（文档反哺另行进行）
#
# 四、交互设计原则
#     - 无参数=交互菜单（1 补丁/2 次版本/3 仅构建验证/q 退出）
#     - 带参数=直通（1/2/3），但 push 前一律 y/N 确认门（闸门不豁免）
#     - 任一闸失败即中止，不带病推进；已做的版本改动自动还原
#
# 五、换行符与兼容性
#     本文件使用 LF 换行符，兼容 bash 和 zsh（无 [[ ]]、无 here-string、无 $''）。
# =============================================================================
if [ ! -x "$0" ]; then chmod +x "$0" 2>/dev/null; fi
cd "$(dirname "$0")" || exit 1

# 颜色
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[0;34m'; NC='\033[0m'

PY=python3
log_ok()   { printf "${G}[OK]${NC} %s\n" "$1"; }
log_err()  { printf "${R}[ERROR]${NC} %s\n" "$1"; }
log_info() { printf "${B}[INFO]${NC} %s\n" "$1"; }

# ── 工作区干净检查 ──
dirty=$(git status --porcelain | wc -l | tr -d ' ')
if [ "$dirty" != "0" ]; then
    log_err "工作区有 $dirty 个未提交变更——先提交或还原再发布"
    git status --short | head -5
    exit 1
fi

# ── 读当前版本（以 pyproject.toml 为事实源）──
CUR=$(grep -m1 '^version' pyproject.toml | cut -d'"' -f2)
[ -n "$CUR" ] || { log_err "pyproject.toml 读版本失败"; exit 1; }
MAJOR=${CUR%%.*}; REST=${CUR#*.}; MINOR=${REST%%.*}; PATCH=${REST#*.}

# ── 发布环境就绪：pytest 缺失时自建专用 venv（PEP 668 拦全局装）──
ensure_publish_env() {
    if python3 -m pytest --version > /dev/null 2>&1; then
        PY="python3"; return 0
    fi
    log_info "系统 python3 缺 pytest——创建发布专用环境 .venv-publish ..."
    python3 -m venv .venv-publish || { log_err "venv 创建失败"; return 1; }
    .venv-publish/bin/pip install -q pytest pyyaml jinja2 || { log_err "依赖安装失败"; return 1; }
    PY=".venv-publish/bin/python3"
    log_ok "发布环境就绪（.venv-publish，已入 .gitignore）"
}

# ── 版本递增 ──
# $1 = patch | minor
bump_version() {
    local kind="$1" new
    case "$kind" in
        patch) new="$MAJOR.$MINOR.$((PATCH + 1))" ;;
        minor) new="$MAJOR.$((MINOR + 1)).0" ;;
        *) log_err "未知版本档: $kind"; return 1 ;;
    esac
    # 两处同步改
    sed -i '' "s/version='%(prog)s ${CUR}'/version='%(prog)s ${new}'/" generator.py || return 1
    sed -i '' "s/^version = \"${CUR}\"/version = \"${new}\"/" pyproject.toml || return 1
    # 验证两处都已改到
    grep -q "version='%(prog)s ${new}'" generator.py || { log_err "generator.py 版本改写失败"; return 1; }
    grep -q "\"${new}\"" pyproject.toml || { log_err "pyproject.toml 版本改写失败"; return 1; }
    printf '%s' "$new"
}

# ── 发布主流程 ──
# $1 = patch | minor
do_release() {
    local kind="$1" new tag
    ensure_publish_env || return 1
    log_info "当前版本: $CUR（${kind} 递增）"
    new=$(bump_version "$kind") || { log_err "版本改写失败（已还原检查：git checkout .）"; git checkout -- generator.py pyproject.toml 2>/dev/null; return 1; }
    tag="v${new}"
    log_ok "新版本: $new"

    log_info "闸1：py_compile ..."
    "$PY" -m py_compile generator.py module/*.py || { log_err "语法闸失败"; git checkout -- generator.py pyproject.toml; return 1; }
    log_info "闸2：pytest 12 用例 ..."
    "$PY" -m pytest tests/ -q > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log_err "测试闸失败（退出码非零）"; git checkout -- generator.py pyproject.toml; return 1
    fi
    log_ok "双闸通过"

    git add generator.py pyproject.toml
    git commit -m "chore: v${new}——发布（publish.sh 自动版）" --quiet || { log_err "commit 失败"; git checkout -- generator.py pyproject.toml; return 1; }
    git tag -a "$tag" -m "${tag}：发布（Trusted Publishing 自动上架 PyPI）"
    log_ok "commit + tag ${tag} 完成"

    printf "确认推送到 origin（将触发 CI 自动上架 PyPI ${new}）？[y/N]: "
    local answer; read -r answer
    case "$answer" in
        y|yes|Y|YES)
            git push origin master 2>&1 | tail -1
            git push origin "$tag" 2>&1 | tail -1
            log_ok "已推送——Actions 构建中，约 1 分钟后 PyPI 上架 ${new}"
            log_info "验证：curl -s https://pypi.org/pypi/libra-boot-low/json | grep -o '\"${new}\"'"
            ;;
        *)
            log_info "已取消推送——本地 commit/tag 保留，可手工 push 或 git tag -d ${tag} 回退"
            ;;
    esac
}

# ── 仅构建验证（不发布）──
do_build_check() {
    log_info "本地构建验证（不发布）..."
    ensure_publish_env || return 1
    "$PY" -m pip install -q build 2>/dev/null || true
    rm -rf dist
    "$PY" -m build --outdir dist 2>&1 | tail -1 || { log_err "构建失败"; return 1; }
    log_ok "构建产物："
    ls -la dist/ | awk 'NR>1 {print "  " $5 "  " $9}'
    log_info "敏感词解包扫描..."
    python3 - <<'SCAN'
import zipfile, tarfile, glob, re
pat = re.compile(r'zkzx|myslayers|zhgh|lqzx|sxlq|工会|职工|甄选|101\.42\.36|eJcQkAkQGP5wKmxr|troyesivens|antigravity', re.I)
bad = 0
for f in glob.glob('dist/*'):
    z = zipfile.ZipFile(f) if f.endswith('.whl') else tarfile.open(f)
    names = z.namelist() if hasattr(z, 'namelist') else [m.name for m in z.getmembers()]
    for n in names:
        data = z.read(n) if hasattr(z, 'read') else z.extractfile(n).read()
        m = pat.findall(data.decode('utf-8', 'ignore'))
        if m: bad += len(m); print(f'  命中: {f} -> {n}')
print(f'敏感词命中: {bad}（0=净）')
SCAN
    rm -rf dist
    log_ok "构建验证完成（产物已清）"
}

# ── 交互菜单 ──
menu() {
    while true; do
        clear 2>/dev/null || true
        echo "========================================"
        echo "    Libra Boot Low 发布器（当前 v${CUR}）"
        echo "========================================"
        echo ""
        echo "  1) 补丁发布（patch +1，bug 修复）"
        echo "  2) 次版本发布（minor +1，新功能）"
        echo "  3) 仅构建验证（不发布）"
        echo "  q) 退出"
        echo ""
        read -p "  请选择 [1/2/3/q]: " choice
        case "$choice" in
            1) do_release patch; printf "\n按回车返回... "; read -r _ ;;
            2) do_release minor; printf "\n按回车返回... "; read -r _ ;;
            3) do_build_check; printf "\n按回车返回... "; read -r _ ;;
            q|Q|9) echo "Bye!"; exit 0 ;;
            *) echo "[ERROR] 无效输入"; sleep 1 ;;
        esac
    done
}

# ── 参数直通 ──
if [ $# -gt 0 ]; then
    case "$1" in
        1) do_release patch ;;
        2) do_release minor ;;
        3) do_build_check ;;
        -h|--help) sed -n '2,40p' "$0" ;;
        *) log_err "未知参数: $1（可用 1/2/3/-h）"; exit 1 ;;
    esac
    exit $?
fi

menu
