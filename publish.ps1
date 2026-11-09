# =============================================================================
# Libra Boot Low 发布器 - PowerShell
#
# 一、为什么需要这个脚本？
#     发布 PyPI 包需手动改两处版本号（generator.py --version 与 pyproject.toml）、
#     commit、打 v* 标签、push——步骤多且两处版本号易漏改漂移。本脚本一条命令
#     完成全链，版本单源改动零漂移。
#
# 二、工具链与调用流程
#     publish.ps1 [1|2|3]
#       -> 自动递增版本（patch 或 minor）-> 同步改 generator.py + pyproject.toml
#       -> py_compile 语法闸 -> pytest 快闸 -> git commit -> tag vX.Y.Z
#       -> y/N 确认 -> push（master+tags）-> GitHub Actions 自动构建上架 PyPI
#
# 三、脚本没有负责的事（刻意排除）
#     不本地 build/上传（归 CI 的 pypi.yml，OIDC 免密）；
#     不改 README wheel 版本号；不动文档反哺。
#
# 四、交互设计原则
#     无参数=交互菜单（1 补丁/2 次版本/3 仅构建验证/q 退出）；
#     带参数=直通；push 前一律 y/N 确认门；任一闸失败即中止并还原版本改动。
#
# 五、换行符与兼容性
#     本文件使用 CRLF 换行符，兼容 PowerShell 5.1 和 7+。
# =============================================================================

$ErrorActionPreference = "Continue"
Set-Location -Path $PSScriptRoot

function Write-Ok   { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Err2 { param($m) Write-Host "  [ERROR] $m" -ForegroundColor Red }
function Write-Info { param($m) Write-Host "  [INFO] $m" -ForegroundColor Blue }

# 工作区干净检查
$dirty = @(git status --porcelain)
if ($dirty.Count -gt 0) {
    Write-Err2 "工作区有 $($dirty.Count) 个未提交变更——先提交或还原再发布"
    $dirty | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" }
    exit 1
}

# 读当前版本（pyproject.toml 为事实源）
$pyproject = Get-Content pyproject.toml -Raw
if ($pyproject -match 'version = "([\d.]+)"') { $CUR = $Matches[1] } else { Write-Err2 "读版本失败"; exit 1 }
$parts = $CUR.Split('.')
$MAJOR = [int]$parts[0]; $MINOR = [int]$parts[1]; $PATCH = [int]$parts[2]

function Bump-Version {
    param([string]$Kind)
    if ($Kind -eq "patch") { $new = "$MAJOR.$MINOR.$($PATCH + 1)" }
    elseif ($Kind -eq "minor") { $new = "$MAJOR.$($MINOR + 1).0" }
    else { Write-Err2 "未知版本档: $Kind"; return $null }
    $g2 = (Get-Content generator.py -Raw) -replace "version='%\(prog\)s $CUR'", "version='%\(prog\)s $new'"
    $p2 = (Get-Content pyproject.toml -Raw) -replace "version = `"$CUR`"", "version = `"$new`""
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $PSScriptRoot "generator.py"), $g2, $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $PSScriptRoot "pyproject.toml"), $p2, $utf8NoBom)
    $g = (Get-Content generator.py -Raw) -match [regex]::Escape("version='%(prog)s $new'")
    $p = (Get-Content pyproject.toml -Raw) -match [regex]::Escape("version = `"$new`"")
    if ($g -and $p) { return $new }
    Write-Err2 "版本改写验证失败"; return $null
}

function Invoke-QuickGates {
    python3 -m py_compile generator.py module/*.py
    if ($LASTEXITCODE -ne 0) { return $false }
    python3 -m pytest tests/ -q | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Err2 "pytest 未全过（退出码非零）"; return $false }
    return $true
}

function Invoke-Release {
    param([string]$Kind)
    if (-not (Ensure-PublishEnv)) { return }
    Write-Info "当前版本: $CUR（$Kind 递增）"
    $new = Bump-Version -Kind $Kind
    if ($null -eq $new) { return }
    $tag = "v$new"
    Write-Ok "新版本: $new"

    Write-Info "闸1：py_compile ..."
    python3 -m py_compile generator.py module/*.py
    if ($LASTEXITCODE -ne 0) { Write-Err2 "语法闸失败"; git checkout -- generator.py pyproject.toml; return }
    Write-Info "闸2：pytest 12 用例 ..."
    python3 -m pytest tests/ -q | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Err2 "测试闸失败（退出码非零）"; git checkout -- generator.py pyproject.toml; return }
    Write-Ok "双闸通过"

    git add generator.py pyproject.toml
    git commit -m "chore: v$new——发布（publish.ps1 自动版）"
    if ($LASTEXITCODE -ne 0) { Write-Err2 "commit 失败"; return }
    git tag -a $tag -m "${tag}：发布（Trusted Publishing 自动上架 PyPI）"
    Write-Ok "commit + tag $tag 完成"

    $answer = Read-Host "  确认推送到 origin（将触发 CI 自动上架 PyPI $new）？[y/N]"
    if ($answer -match '^(y|yes|Y|YES)$') {
        git push origin master 2>&1 | Select-Object -Last 1
        git push origin $tag 2>&1 | Select-Object -Last 1
        Write-Ok "已推送——Actions 构建中，约 1 分钟后 PyPI 上架 $new"
    } else {
        Write-Info "已取消推送——本地 commit/tag 保留"
    }
}

function Invoke-BuildCheck {
    Write-Info "本地构建验证（不发布）..."
    pip install -q build 2>$null
    if (Test-Path dist) { Remove-Item -Recurse -Force dist }
    python -m build --outdir dist
    if ($LASTEXITCODE -ne 0) { Write-Err2 "构建失败"; return }
    Write-Ok "构建产物："
    Get-ChildItem dist | ForEach-Object { Write-Host ("  " + $_.Length + "  " + $_.Name) }
    Write-Info "敏感词解包扫描..."
    $pat = 'zkzx|myslayers|zhgh|lqzx|sxlq|工会|职工|甄选|101\.42\.36|eJcQkAkQGP5wKmxr|troyesivens|antigravity'
    $bad = 0
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Get-ChildItem dist -Filter *.whl | ForEach-Object {
        $z = [System.IO.Compression.ZipFile]::OpenRead($_.FullName)
        foreach ($e in $z.Entries) {
            if ($e.Name -match '\.(py|md|txt|json|toml)$') {
                $reader = New-Object System.IO.StreamReader($e.Open())
                $content = $reader.ReadToEnd(); $reader.Close()
                $ms = [regex]::Matches($content, $pat, 'IgnoreCase')
                if ($ms.Count -gt 0) { $bad += $ms.Count; Write-Host ("  命中: " + $_.Name + " -> " + $e.FullName) }
            }
        }
        $z.Dispose()
    }
    Write-Host ("  敏感词命中: $bad（0=净）")
    Remove-Item -Recurse -Force dist -ErrorAction SilentlyContinue
    Write-Ok "构建验证完成（产物已清）"
}

# 交互菜单
while ($true) {
    Clear-Host
    Write-Host "========================================"
    Write-Host "    Libra Boot Low 发布器（当前 v$CUR）"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "  1) 补丁发布（patch +1，bug 修复）"
    Write-Host "  2) 次版本发布（minor +1，新功能）"
    Write-Host "  3) 仅构建验证（不发布）"
    Write-Host "  q) 退出"
    Write-Host ""
    $choice = Read-Host "  请选择 [1/2/3/q]"
    switch ($choice) {
        "1" { Invoke-Release -Kind "patch"; $null = Read-Host "按回车返回" }
        "2" { Invoke-Release -Kind "minor"; $null = Read-Host "按回车返回" }
        "3" { Invoke-BuildCheck; $null = Read-Host "按回车返回" }
        "q" { Write-Host "Bye!"; exit 0 }
        "Q" { Write-Host "Bye!"; exit 0 }
        "9" { Write-Host "Bye!"; exit 0 }
        default { Write-Host "[ERROR] 无效输入"; Start-Sleep -Seconds 1 }
    }
}
