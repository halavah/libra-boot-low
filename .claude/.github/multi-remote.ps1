# ============================================================
# 工具名称: 多平台 Git 同步工具 (multi-remote.ps1)
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
#         - 各步骤独立捕获 $LASTEXITCODE，任一失败即标记为失败
#     Pull（下载）：只拉取远端与当前同名的分支（git pull remote current_branch）
#     Sync（同步）：fetch 远端后 merge 当前同名分支到本地
#     Status（查看状态）：显示当前分支与远端的差异

# 六、自动提交策略（push 前自动执行）
#     每次 push 前，脚本会自动检查工作区是否有未提交的更改：
#         1. git add .                     暂存所有更改（含新增/修改/删除）
#         2. git diff --staged --quiet     检查暂存区是否为空
#         3. 若有更改 → git commit -m "yyyyMMdd_HHmmss"（时间戳作为提交信息）
#         4. 若无更改 → 跳过提交，直接推送
#     设计要点：
#     - $script:CommitDone 全局标记：选"全部远端"时遍历3个remote，自动提交只在
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
#     7.3 PowerShell 全局状态管理
#         原因：函数内修改外部变量需要使用 $script: 作用域前缀。
#         方案：$script:CommitDone 在函数 Auto-Commit-IfNeeded 中读写，
#         确保 Do-Push 遍历多个 remote 时提交只发生一次。
#
#     7.4 $LASTEXITCODE 捕获
#         原因：PowerShell 中外部命令（git）的退出码存在 $LASTEXITCODE，
#         必须在下一条命令前读取，否则会被覆盖。
#         方案：每条 git 命令后立即读取 $LASTEXITCODE 保存到局部变量。
#
#     7.5 全部远端遍历输出
#         原因：选"全部远端"时三个remote的输出混在一起，难以区分。
#         方案：每个 remote 前后添加 ═══ 分隔线（Cyan色）+ 远端名称标题。
#
#     7.6 .git/config 保护机制（完整还原）
#         脚本启动时拍快照，记录每个已有 remote 的名称 + URL。
#         Ensure-Remote 不仅检查名称是否存在，还会检查 URL 是否匹配：
#         - 名称不存在 → git remote add（新增）
#         - 名称存在但 URL 不同 → git remote set-url（修正）
#         退出时 (try/finally) 完整还原：
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
#         全局设置 $env:GIT_SSH_COMMAND 添加 ConnectTimeout=5，
#         确保所有 git 命令最多 5 秒连接超时，避免网络不通时卡死。
#
#     7.8 自动创建仓库（默认关闭）
#         当远端仓库不存在时（非网络问题），可根据全局开关决定行为：
#         $AUTO_CREATE_REPO = $false（默认）→ 跳过，保持原有行为
#         $AUTO_CREATE_REPO = $true         → 调用平台 API 创建私有仓库
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
#           $env:SOURCE_REMOTE="old-origin"; .\multi-remote.ps1 --remote gitlab push

# 八、换行符与兼容性
#     本文件使用 CRLF 换行符，兼容 PowerShell 5.1 和 7+。

# ============================================================
# 用户配置区（修改以下变量即可适配其他仓库）
# ============================================================
# REPO_NAME 自动推导：从脚本所在目录的上级目录名获取（即项目根目录名）
# 如需手动指定，取消下行注释并修改值，注释掉自动推导行
# $REPO_NAME = "custom-repo-name"

# 自动推导：获取项目根目录名（脚本在 .github/ 子目录）
$SCRIPT_DIR_CONFIG = $PSScriptRoot
$PROJECT_DIR_CONFIG = (Resolve-Path (Join-Path $SCRIPT_DIR_CONFIG "..")).Path
$REPO_NAME = if ($env:REPO_NAME) { $env:REPO_NAME } else { (Split-Path $PROJECT_DIR_CONFIG -Leaf) }

$USERNAME = "halavah"              # 用户名（Gitee/GitHub）
$GITLAB_NAMESPACE = "demo"         # GitLab 命名空间（组名或用户名）

$REMOTE_GITEE = "git@gitee.com:${USERNAME}/${REPO_NAME}.git"
$REMOTE_GITHUB = "git@github.com:${USERNAME}/${REPO_NAME}.git"
$REMOTE_GITLAB = "http://192.168.3.200/${GITLAB_NAMESPACE}/${REPO_NAME}.git"

# API Token（自动创建仓库功能，需配合 $AUTO_CREATE_REPO = $true 开启）
# 获取方式：
#   GitHub: Settings → Developer settings → Personal access tokens → repo 权限
#   Gitee:  设置 → 私人令牌 → projects 权限
#   GitLab: 设置 → Access Tokens → api 权限
$GITHUB_TOKEN = ""
$GITEE_TOKEN = ""
$GITLAB_TOKEN = ""

# 全局开关：仓库不存在时是否自动创建私有仓库（默认关闭）
$AUTO_CREATE_REPO = $false

# 全量分支迁移的来源远程：默认读取 origin/*；旧仓库迁移时可临时设为 old-origin
$SOURCE_REMOTE = if ($env:SOURCE_REMOTE) { $env:SOURCE_REMOTE } else { "origin" }
$TARGET_BRANCH = if ($env:TARGET_BRANCH) { $env:TARGET_BRANCH } else { "master" }
# ============================================================

$ErrorActionPreference = "Stop"

# 全局 SSH 超时：所有 git 命令最多 5 秒连接超时，避免网络不通时卡死
$env:GIT_SSH_COMMAND = "ssh -o ConnectTimeout=5 -o BatchMode=yes"

# 设置控制台编码
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 锁定工作目录到脚本所在目录
$SCRIPT_DIR = $PSScriptRoot
# 回到项目根目录（脚本在 .github/ 子目录，上级就是项目根）
$PROJECT_DIR = (Resolve-Path (Join-Path $SCRIPT_DIR "..")).Path
Set-Location -Path $PROJECT_DIR

# 检查是否在 git 仓库中，不是则自动初始化
$gitDir = git rev-parse --git-dir 2>$null
if ($LASTEXITCODE -ne 0 -or -not $gitDir) {
    Write-Host "[WARN] 当前目录不是 Git 仓库，正在自动初始化..." -ForegroundColor Yellow
    git init
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] git init 失败" -ForegroundColor Red
        exit 1
    }
    Write-Host "[INFO] git init 完成" -ForegroundColor Cyan

    # 确保默认分支为 master
    git checkout -b master 2>$null

    # 检查是否有 .gitignore
    if (-not (Test-Path ".gitignore")) {
        Write-Host "[INFO] 创建默认 .gitignore" -ForegroundColor Cyan
        @"
node_modules/
dist/
.DS_Store
*.log
.env
.env.local
.env.*.local
.idea/
.vscode/
"@ | Set-Content -Path ".gitignore" -Encoding UTF8
    }

    # 暂存所有文件
    git add .
    git diff --staged --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[WARN] 没有文件可提交" -ForegroundColor Yellow
    } else {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        Write-Host "[INFO] 创建初始提交: ${timestamp}" -ForegroundColor Cyan
        git commit -m "$timestamp"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] 初始提交失败（可能缺少 user.name/user.email）" -ForegroundColor Red
            Write-Host "  请运行: git config user.name 'Your Name' && git config user.email 'you@example.com'" -ForegroundColor Yellow
            exit 1
        }
        Write-Host "[OK] Git 仓库初始化并完成首次提交" -ForegroundColor Green
    }
}

# 拍快照：记录脚本启动前已有的 remote 名称 + URL（退出时完整还原）
$script:ExistingRemotes = @(git remote)
$script:ExistingRemoteUrls = @{}
foreach ($r in $script:ExistingRemotes) {
    $script:ExistingRemoteUrls[$r] = git remote get-url $r
}

# 退出时还原：删除脚本添加的 remote / 还原被修改的 URL
function Restore-Remotes {
    foreach ($remote in $REMOTE_NAMES) {
        $wasExisting = $script:ExistingRemotes -contains $remote
        if (-not $wasExisting) {
            # 脚本新添加的 remote → 删除
            $currentRemotes = @(git remote 2>$null)
            if ($currentRemotes -contains $remote) {
                Write-Host "[INFO] 清理 remote: ${remote}" -ForegroundColor Cyan
                git remote remove $remote 2>$null
            }
        } else {
            # 脚本修改了 URL 的 remote → 还原原始 URL
            $savedUrl = $script:ExistingRemoteUrls[$remote]
            if ($savedUrl) {
                $currentUrl = git remote get-url $remote 2>$null
                if ($currentUrl -and ($currentUrl -ne $savedUrl)) {
                    Write-Host "[INFO] 还原 remote URL: ${remote} -> ${savedUrl}" -ForegroundColor Cyan
                    git remote set-url $remote $savedUrl 2>$null
                }
            }
        }
    }
}

# 获取当前分支名
function Get-CurrentBranch {
    return git rev-parse --abbrev-ref HEAD
}

# 全局标记：防止全部远端模式下重复提交
$script:CommitDone = $false

# 自动提交（如有未暂存更改）
function Auto-Commit-IfNeeded {
    if ($script:CommitDone) { return }
    git add .
    git diff --staged --quiet
    if ($LASTEXITCODE -eq 0) { return }
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    Write-Host "[INFO] 发现未提交更改，自动提交: ${timestamp}" -ForegroundColor Cyan
    git commit -m "$timestamp"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARN] 自动提交失败，跳过（可能缺少 user.name/user.email）" -ForegroundColor Yellow
        return
    }
    $script:CommitDone = $true
}

# 检查并添加 remote
function Ensure-Remote {
    param([string]$Name, [string]$Url)
    $remotes = git remote
    if (-not ($remotes -contains $Name)) {
        Write-Host "[INFO] 添加 remote: ${Name} -> ${Url}"
        git remote add $Name $Url
    } else {
        $currentUrl = git remote get-url $Name
        if ($currentUrl -ne $Url) {
            Write-Host "[INFO] 更新 remote URL: ${Name} ${currentUrl} -> ${Url}"
            git remote set-url $Name $Url
        }
    }
}

# 定义远端信息
$REMOTE_NAMES = @("gitee", "github", "gitlab")
$REMOTE_URLS = @{
    "gitee" = $REMOTE_GITEE
    "github" = $REMOTE_GITHUB
    "gitlab" = $REMOTE_GITLAB
}
$REMOTE_LABELS = @{
    "gitee" = "Gitee"
    "github" = "GitHub"
    "gitlab" = "GitLab"
}

# 预检查所有 remote
foreach ($remote in $REMOTE_NAMES) {
    Ensure-Remote -Name $remote -Url $REMOTE_URLS[$remote]
}

# 显示操作结果
function Show-Result {
    param([string]$Op, [string]$Remote, [int]$Code)
    if ($Code -eq 0) {
        Write-Host "[OK] ${Op} 操作成功: $($REMOTE_LABELS[$Remote]) (${Remote})" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] ${Op} 操作失败: $($REMOTE_LABELS[$Remote]) (${Remote}), 退出码: ${Code}" -ForegroundColor Red
    }
}

# 输出来源分支名：本地分支 + 来源远程跟踪分支，去掉 SOURCE_REMOTE/HEAD
function Get-SourceBranchNames {
    $names = @()
    $names += @(git for-each-ref --format="%(refname:short)" refs/heads)

    git remote get-url $SOURCE_REMOTE > $null 2> $null
    if ($LASTEXITCODE -eq 0) {
        $remoteRefs = @(git for-each-ref --format="%(refname)" "refs/remotes/${SOURCE_REMOTE}")
        foreach ($ref in $remoteRefs) {
            if (-not $ref) { continue }
            if ($ref -eq "refs/remotes/${SOURCE_REMOTE}/HEAD") { continue }
            $names += $ref.Substring("refs/remotes/${SOURCE_REMOTE}/".Length)
        }
    }

    return @($names | Where-Object { $_ } | Sort-Object -Unique)
}

# 推送来源远程跟踪分支，覆盖 git push --all 无法处理的远程-only 分支
function Push-RemoteTrackingBranches {
    param([string]$Remote)

    git remote get-url $SOURCE_REMOTE > $null 2> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[INFO] 来源远程 ${SOURCE_REMOTE} 不存在，跳过远程跟踪分支 refspec 推送" -ForegroundColor Cyan
        return 0
    }

    Write-Host "[INFO] 正在刷新来源远程 ${SOURCE_REMOTE} 的分支引用..." -ForegroundColor Cyan
    git fetch $SOURCE_REMOTE --prune
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] fetch ${SOURCE_REMOTE} 失败，无法推送远程跟踪分支" -ForegroundColor Red
        return $LASTEXITCODE
    }

    $refspecCode = 0
    $pushedCount = 0
    $remoteRefs = @(git for-each-ref --format="%(refname)" "refs/remotes/${SOURCE_REMOTE}")
    foreach ($ref in $remoteRefs) {
        if (-not $ref) { continue }
        if ($ref -eq "refs/remotes/${SOURCE_REMOTE}/HEAD") { continue }
        $branch = $ref.Substring("refs/remotes/${SOURCE_REMOTE}/".Length)
        Write-Host "[INFO] refspec 推送来源分支 ${SOURCE_REMOTE}/${branch} -> ${Remote}/${branch}" -ForegroundColor Cyan
        git push $Remote "refs/remotes/${SOURCE_REMOTE}/${branch}:refs/heads/${branch}"
        if ($LASTEXITCODE -ne 0) {
            $refspecCode = $LASTEXITCODE
        }
        $pushedCount += 1
    }

    Write-Host "[INFO] 来源远程跟踪分支 refspec 推送完成: ${pushedCount} 个" -ForegroundColor Cyan
    return $refspecCode
}

# 推送后验证目标远程的分支/tag 数量
function Test-RemoteRefs {
    param([string]$Remote)

    $sourceBranchCount = @(Get-SourceBranchNames).Count
    $sourceTagCount = @(git tag -l | Where-Object { $_ }).Count
    $targetRefs = @(git ls-remote --heads --tags $Remote)
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] git ls-remote --heads --tags ${Remote} 验证失败" -ForegroundColor Red
        return $LASTEXITCODE
    }

    $targetBranchCount = @($targetRefs | Where-Object { $_ -match "\srefs/heads/" }).Count
    $targetTagCount = @($targetRefs | Where-Object { $_ -match "\srefs/tags/" -and $_ -notmatch "\^\{\}$" }).Count

    Write-Host "[INFO] 验证远程引用: 来源分支=${sourceBranchCount}, 目标分支=${targetBranchCount}; 来源tags=${sourceTagCount}, 目标tags=${targetTagCount}" -ForegroundColor Cyan
    if ($sourceBranchCount -eq $targetBranchCount -and $sourceTagCount -eq $targetTagCount) {
        Write-Host "[OK] 目标远程分支/tag 数量一致" -ForegroundColor Green
        return 0
    }

    Write-Host "[ERROR] 目标远程分支/tag 数量不一致，请检查 git ls-remote --heads --tags ${Remote}" -ForegroundColor Red
    return 1
}

# 执行 push 操作（只推送指定分支到同名远端分支）
function Do-Push {
    param([string]$Remote)
    Auto-Commit-IfNeeded
    git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] 本地分支不存在: $TARGET_BRANCH" -ForegroundColor Red
        Show-Result -Op "push" -Remote $Remote -Code 1
        return
    }
    Write-Host "[INFO] 正在推送到 $($REMOTE_LABELS[$Remote]) (${Remote}) [仅分支: ${TARGET_BRANCH} -> ${TARGET_BRANCH}]..."
    git push $Remote "refs/heads/$TARGET_BRANCH`:refs/heads/$TARGET_BRANCH"
    $pushCode = $LASTEXITCODE
    $verifyRefs = ""
    $verifyCode = 0
    if ($pushCode -eq 0) {
        $verifyRefs = git ls-remote --heads $Remote "refs/heads/$TARGET_BRANCH" 2>$null
        if (-not $verifyRefs) { $verifyCode = 1 }
    } else {
        $verifyCode = 1
    }
    if ($pushCode -eq 0 -and $verifyCode -eq 0) {
        Show-Result -Op "push" -Remote $Remote -Code 0
    } else {
        Show-Result -Op "push" -Remote $Remote -Code 1
    }
}

# 执行 pull 操作（只拉取当前同名分支）
function Do-Pull {
    param([string]$Remote)
    $branch = Get-CurrentBranch
    Write-Host "[INFO] 正在从 $($REMOTE_LABELS[$Remote]) (${Remote}) 拉取 [当前同名分支: ${branch}]..."
    git pull $Remote $branch
    Show-Result -Op "pull" -Remote $Remote -Code $LASTEXITCODE
}

# 执行 sync 操作 (fetch + merge)
function Do-Sync {
    param([string]$Remote)
    $branch = Get-CurrentBranch
    Write-Host "[INFO] 正在同步 $($REMOTE_LABELS[$Remote]) (${Remote}) [分支: ${branch}]..."
    git fetch $Remote
    if ($LASTEXITCODE -eq 0) {
        git merge "${Remote}/${branch}" --no-edit
    }
    Show-Result -Op "sync" -Remote $Remote -Code $LASTEXITCODE
}

# 执行 status 操作
function Do-Status {
    param([string]$Remote)
    $branch = Get-CurrentBranch
    Write-Host "[INFO] 查看 $($REMOTE_LABELS[$Remote]) (${Remote}) 状态 [分支: ${branch}]..."
    git fetch $Remote
    Write-Host ""
    Write-Host "--- 本地分支状态 ---"
    git status -sb
    Write-Host ""
    Write-Host "--- 与 $($REMOTE_LABELS[$Remote]) 的差异 ---"
    git --no-pager log --oneline --left-right "HEAD...${Remote}/${branch}" -- 2>$null
    Show-Result -Op "status" -Remote $Remote -Code 0
}

# 调用平台 API 创建私有仓库
function New-Repo {
    param([string]$Remote)
    $token = ""
    $apiUrl = ""
    $body = ""
    $headers = @{}
    switch ($Remote) {
        "github" {
            $token = $GITHUB_TOKEN
            $apiUrl = "https://api.github.com/user/repos"
            if (-not $token) {
                Write-Host "[SKIP] $($REMOTE_LABELS[$Remote]) (${Remote}) 未配置 GITHUB_TOKEN，无法创建仓库" -ForegroundColor Yellow
                return $false
            }
            Write-Host "[INFO] 尝试创建 GitHub 私有仓库: $REPO_NAME" -ForegroundColor Cyan
            $headers = @{ "Authorization" = "token $token"; "Accept" = "application/vnd.github.v3+json" }
            $body = @{ "name" = $REPO_NAME; "private" = $true } | ConvertTo-Json
        }
        "gitee" {
            $token = $GITEE_TOKEN
            $apiUrl = "https://gitee.com/api/v5/user/repos"
            if (-not $token) {
                Write-Host "[SKIP] $($REMOTE_LABELS[$Remote]) (${Remote}) 未配置 GITEE_TOKEN，无法创建仓库" -ForegroundColor Yellow
                return $false
            }
            Write-Host "[INFO] 尝试创建 Gitee 私有仓库: $REPO_NAME" -ForegroundColor Cyan
            $body = "access_token=$token&name=$REPO_NAME&private=true"
            $headers = @{}
        }
        "gitlab" {
            $token = $GITLAB_TOKEN
            $apiUrl = "http://192.168.3.200/api/v4/projects"
            if (-not $token) {
                Write-Host "[SKIP] $($REMOTE_LABELS[$Remote]) (${Remote}) 未配置 GITLAB_TOKEN，无法创建仓库" -ForegroundColor Yellow
                return $false
            }
            Write-Host "[INFO] 尝试创建 GitLab 私有仓库: $REPO_NAME" -ForegroundColor Cyan
            $headers = @{ "PRIVATE-TOKEN" = $token }
            $body = "name=$REPO_NAME&visibility=private"
        }
        default {
            Write-Host "[SKIP] 未知远端: $Remote" -ForegroundColor Yellow
            return $false
        }
    }
    try {
        if ($Remote -eq "github") {
            $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $body -ContentType "application/json" -ErrorAction Stop
        } elseif ($Remote -eq "gitee") {
            $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
        } else {
            $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
        }
        Write-Host "[OK] 仓库创建成功: $($REMOTE_LABELS[$Remote]) (${Remote})" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[SKIP] $($REMOTE_LABELS[$Remote]) (${Remote}) 仓库创建失败: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

# 快速检测远端连通性（区分网络不通 / 仓库不存在）
function Test-RemoteReachable {
    param([string]$Remote)
    git ls-remote $Remote > $null 2> $null
    if ($LASTEXITCODE -eq 0) {
        return $true
    }

    # ls-remote 失败，区分原因
    $errOutput = git ls-remote $Remote 2>&1 | Out-String

    # 网络不通（超时/连接拒绝/无路由）
    if ($errOutput -match "timed out|connection refused|no route|network is unreachable|could not resolve") {
        Write-Host "[SKIP] $($REMOTE_LABELS[$Remote]) (${Remote}) 网络不可达，跳过" -ForegroundColor Yellow
        return $false
    }

    # 仓库不存在
    if ($AUTO_CREATE_REPO) {
        return (New-Repo -Remote $Remote)
    }

    Write-Host "[SKIP] $($REMOTE_LABELS[$Remote]) (${Remote}) 仓库不存在或不可达，跳过" -ForegroundColor Yellow
    return $false
}

# 对单个远端执行操作
function Execute-Operation {
    param([string]$Remote, [string]$Op)
    if (-not (Test-RemoteReachable -Remote $Remote)) {
        return
    }
    switch ($Op) {
        "push"   { Do-Push -Remote $Remote }
        "pull"   { Do-Pull -Remote $Remote }
        "sync"   { Do-Sync -Remote $Remote }
        "status" { Do-Status -Remote $Remote }
    }
}

# 命令行直通模式（try/finally 确保退出时清理 remote）
try {
if ($args.Count -gt 0) {
    switch ($args[0]) {
        { $_ -in "--all", "-a" } {
            $op = if ($args.Count -gt 1) { $args[1] } else { "push" }
            foreach ($remote in $REMOTE_NAMES) {
                Execute-Operation -Remote $remote -Op $op
                Write-Host ""
            }
            exit 0
        }
        { $_ -in "--remote", "-r" } {
            $remote = $args[1]
            $op = if ($args.Count -gt 2) { $args[2] } else { "push" }
            if (-not $remote) {
                Write-Host "[ERROR] 请指定远端名称: gitee/github/gitlab" -ForegroundColor Red
                exit 1
            }
            Execute-Operation -Remote $remote -Op $op
            exit 0
        }
        { $_ -in "--help", "-h" } {
            Write-Host "用法: $PSCommandPath [选项]"
            Write-Host ""
            Write-Host "选项:"
            Write-Host "  --all, -a [op]     对所有远端执行操作 (默认: push)"
            Write-Host "  --remote, -r <n> [op] 对指定远端执行操作 (默认: push)"
            Write-Host "  --help, -h         显示帮助"
            Write-Host ""
            Write-Host "操作: push, pull, sync, status"
            exit 0
        }
    }
}

# 主循环（第一级：选择远端）
while ($true) {
    Clear-Host
    Write-Host "========================================"
    Write-Host "    多平台 Git 同步工具"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "请选择目标远端:"
    Write-Host "  1. Gitee    ($REMOTE_GITEE)"
    Write-Host "  2. GitHub   ($REMOTE_GITHUB)"
    Write-Host "  3. GitLab   ($REMOTE_GITLAB)"
    Write-Host "  4. 全部远端 (依次操作所有平台)"
    Write-Host ""
    Write-Host "========================================"
    Write-Host ""

    $remoteChoice = Read-Host "Enter number (1-4) [Enter 'q' to quit]"

    switch ($remoteChoice) {
        { $_ -in "q", "Q", "9" } {
            Write-Host "Bye!"
            exit 0
        }
        "1" { $selectedRemote = "gitee" }
        "2" { $selectedRemote = "github" }
        "3" { $selectedRemote = "gitlab" }
        "4" { $selectedRemote = "all" }
        default {
            Write-Host "[ERROR] 无效输入，请重试" -ForegroundColor Red
            Start-Sleep -Seconds 1
            continue
        }
    }

    # 第二级循环（选择操作）
    while ($true) {
        Clear-Host
        Write-Host "========================================"
        Write-Host "    多平台 Git 同步工具"
        Write-Host "========================================"
        Write-Host ""
        if ($selectedRemote -eq "all") {
            Write-Host "已选择: 全部远端"
        } else {
            Write-Host "已选择: $($REMOTE_LABELS[$selectedRemote]) ($selectedRemote)"
        }
        Write-Host ""
        Write-Host "请选择操作:"
        Write-Host "  1. 上传 (push)    -> 推送当前分支到远端"
        Write-Host "  2. 下载 (pull)    -> 从远端拉取当前分支"
        Write-Host "  3. 同步 (sync)    -> fetch + merge，合并远端更新"
        Write-Host "  4. 查看状态       -> 显示当前分支与远端的差异"
        Write-Host ""
        Write-Host "========================================"
        Write-Host ""

        $opChoice = Read-Host "Enter number (1-4) [Enter 'b' to go back]"

        switch ($opChoice) {
            { $_ -in "b", "B" } {
                break
            }
            "1" { $selectedOp = "push" }
            "2" { $selectedOp = "pull" }
            "3" { $selectedOp = "sync" }
            "4" { $selectedOp = "status" }
            default {
                Write-Host "[ERROR] 无效输入，请重试" -ForegroundColor Red
                Start-Sleep -Seconds 1
                continue
            }
        }

        Clear-Host
        Write-Host "========================================"
        Write-Host "    执行操作"
        Write-Host "========================================"
        Write-Host ""

        $currentBranch = Get-CurrentBranch
        Write-Host "[INFO] 当前分支: ${currentBranch}"
        Write-Host ""

        if ($selectedRemote -eq "all") {
            foreach ($remote in $REMOTE_NAMES) {
                Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
                Write-Host "  远端: $($REMOTE_LABELS[$remote]) ($remote)" -ForegroundColor White
                Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
                Execute-Operation -Remote $remote -Op $selectedOp
                Write-Host ""
            }
        } else {
            Execute-Operation -Remote $selectedRemote -Op $selectedOp
        }

        Write-Host ""
        Write-Host "[OK] 操作完毕！" -ForegroundColor Green
        Write-Host ""
        Read-Host "按 Enter 继续"
    }
}
} finally {
    Restore-Remotes
}
