# =============================================================================
# Libra Boot Low 代码生成器 - PowerShell 启动器
#
# 一、为什么需要这个脚本？
#     generator.py 是纯 CLI（参数式），新手需记忆全部参数才能批量生成。
#     本脚本提供两级交互菜单（选域-选配置-选模式），零记忆成本；
#     无参数=交互，带参数=直通。
#
# 二、工具链与调用流程
#     run.ps1 -> 扫描 config/*/ 域 -> 选域(all 可) -> 选 yml(all 可)
#             -> 选模式(12 种或默认) -> python3 generator.py <config> -> out/ 六段
#
# 三、脚本没有负责的事（刻意排除）
#     不生成/修改 YAML 配置；不校验产物内容；不管理 index.json；不装依赖。
#
# 四、交互设计原则
#     一级 q/9 退出、all/a 全域；二级 b 返回、all/a 全模块；
#     模式子菜单 0=默认+12 模式全列；参数直通不进循环。
#
# 五、换行符与兼容性
#     本文件使用 CRLF 换行符，兼容 PowerShell 5.1 和 7+。
# =============================================================================
# =============================================================================
# Libra Boot Low 代码生成器 — PowerShell 启动器
#
# 【设计思路】
# 本脚本提供两种运行模式：
#   1. 交互式菜单：无参数运行时，显示两级菜单让用户选择业务域和配置文件
#   2. 命令行直通：通过参数直接指定配置文件或批量生成模式
#
# 【CLI 参数支持】
#   .\run.ps1 config/test/t1000.yml              # 单文件生成（使用 YAML 中的模式）
#   .\run.ps1 config/test/t1000.yml single-with-file  # 覆盖生成模式
#   .\run.ps1 --all                              # 生成全部模块（所有业务域）
#   .\run.ps1 --domain test --all                # 生成指定域的全部模块
#   .\run.ps1 --domain test simple.yml             # 生成指定域的指定模块
#   .\run.ps1 --all --mode single-with-file      # 生成全部模块并覆盖模式
#   .\run.ps1 --update-index                     # 仅更新配置索引
#
# 【批量生成逻辑】
#   --all 参数会读取 config/index.json 索引文件，遍历所有模块配置执行生成
#   --domain 参数限定到指定业务域（demo/example）
#   --mode 参数覆盖 YAML 配置文件中的 mode 字段
# =============================================================================

# 锁定工作目录为脚本所在位置（generator/）
Set-Location -Path $PSScriptRoot

# =============================================================================
# 常量定义
# =============================================================================
$TOOL_NAME   = "Libra Boot Low Code Generator"
$CONFIG_DIR  = "config"
$OUTPUT_DIR  = "../../out"
$VALID_MODES = @("single", "single-with-file", "multi-table", "multi-table-with-file", "master-detail", "master-detail-with-file", "master-detail-modules", "master-detail-modules-with-file", "master-details-tabs", "master-details-tabs-with-file", "master-details-tabs-dialog", "master-details-tabs-dialog-with-file")
$INDEX_FILE  = Join-Path $CONFIG_DIR "index.json"

# =============================================================================
# 检查 Python3 环境（优先使用本地 .venv，回退到系统 python3）
# =============================================================================
if (Test-Path ".venv/Scripts/python.exe") {
    $PYTHON = ".venv/Scripts/python.exe"
} elseif (Test-Path ".venv/bin/python3") {
    $PYTHON = ".venv/bin/python3"
} else {
    try {
        $null = python3 --version 2>&1
        $PYTHON = "python3"
    } catch {
        Write-Host ""
        Write-Host "  [ERROR] python3 not found. Please install Python 3 first."
        Write-Host "          https://www.python.org/downloads/"
        Write-Host ""
        Read-Host "  Press Enter to exit"
        exit 1
    }
}

# =============================================================================
# 工具函数
# =============================================================================

<#
.SYNOPSIS
    列出 config/ 下的业务域目录（排序）

.DESCRIPTION
    扫描 config/ 目录下的所有一级子目录，返回业务域名称列表。

.EXAMPLE
    $domains = Get-Domains
#>
function Get-Domains {
    if (-not (Test-Path $CONFIG_DIR)) {
        return @()
    }
    Get-ChildItem -Path $CONFIG_DIR -Directory | Sort-Object Name | ForEach-Object { $_.Name }
}

<#
.SYNOPSIS
    列出指定业务域下的 .yml 配置文件（排序）

.DESCRIPTION
    扫描指定业务域目录下的所有 .yml 文件，返回文件名列表。

.PARAMETER Domain
    业务域名称（如 demo, demo, demo）

.EXAMPLE
    $ymls = Get-YmlFiles -Domain "demo"
#>
function Get-YmlFiles {
    param([string]$Domain)
    $domainPath = Join-Path $CONFIG_DIR $Domain
    if (-not (Test-Path $domainPath)) {
        return @()
    }
    Get-ChildItem -Path $domainPath -Filter "*.yml" | Sort-Object Name | ForEach-Object { $_.Name }
}

<#
.SYNOPSIS
    从 index.json 读取指定域的模块列表

.DESCRIPTION
    解析 config/index.json 文件，提取指定业务域下的所有模块 code。

.PARAMETER Domain
    业务域名称（如 demo, demo, demo）

.RETURNS
    模块 code 字符串数组

.EXAMPLE
    $modules = Get-ModulesFromIndex -Domain "demo"
#>
function Get-ModulesFromIndex {
    param([string]$Domain)
    if (-not (Test-Path $INDEX_FILE)) {
        return @()
    }
    try {
        $json = Get-Content -Path $INDEX_FILE -Raw | ConvertFrom-Json
        $domainData = $json.domains.$Domain
        if ($domainData -and $domainData.modules) {
            return $domainData.modules | ForEach-Object { $_.code }
        }
    } catch {
        Write-Host "  [WARN] Failed to parse index.json: $_"
    }
    return @()
}

<#
.SYNOPSIS
    从 index.json 读取所有模块的配置文件路径

.DESCRIPTION
    解析 config/index.json 文件，提取所有模块的配置文件相对路径。

.RETURNS
    配置文件路径字符串数组（如 "test/t1000.yml"）

.EXAMPLE
    $allConfigs = GetAll-ModulesFromIndex
#>
function GetAll-ModulesFromIndex {
    if (-not (Test-Path $INDEX_FILE)) {
        return @()
    }
    try {
        $json = Get-Content -Path $INDEX_FILE -Raw | ConvertFrom-Json
        $configs = $json.configs
        if ($configs) {
            return $configs | ForEach-Object { $_.file }
        }
    } catch {
        Write-Host "  [WARN] Failed to parse index.json: $_"
    }
    return @()
}

<#
.SYNOPSIS
    执行代码生成

.DESCRIPTION
    调用 generator.py 执行代码生成，可选择覆盖生成模式和批量时间戳。

.PARAMETER ConfigFile
    配置文件路径（相对于 config/ 目录）

.PARAMETER Mode
    可选的生成模式覆盖，为空则使用 YAML 中的模式

.PARAMETER BatchTimestamp
    可选的批量模式时间戳（用于共享日志文件）

.EXAMPLE
    Invoke-Generate -ConfigFile "config/test/t1000.yml" -Mode "single-with-file" -BatchTimestamp "20260101_120000"
#>
function Invoke-Generate {
    param(
        [string]$ConfigFile,
        [string]$Mode = "",
        [string]$BatchTimestamp = ""
    )
    Write-Host ""
    Write-Host "  ----------------------------------------"
    Write-Host "  Generating: $ConfigFile"
    Write-Host "  Output dir: $OUTPUT_DIR"
    if ($Mode) {
        Write-Host "  Mode override: $Mode"
    }
    if ($BatchTimestamp) {
        Write-Host "  Batch mode: $BatchTimestamp"
    }
    Write-Host "  ----------------------------------------"

    # 构建命令参数
    $cmdArgs = @($ConfigFile, $OUTPUT_DIR)
    if ($Mode) {
        $cmdArgs += "--mode", $Mode
    }
    if ($BatchTimestamp) {
        $cmdArgs += "--batch-timestamp", $BatchTimestamp
    }

    & $PYTHON generator.py @cmdArgs
    $exitCode = $LASTEXITCODE

    Write-Host ""
    if ($exitCode -eq 0) {
        Write-Host "  [OK] Generation complete!"
        return $true
    } else {
        Write-Host "  [ERROR] Generation failed (exit code: $exitCode)"
        return $false
    }
}

# =============================================================================
# CLI 参数解析
# 支持的参数：
#   --all           : 批量生成模式
#   --update-index  : 仅更新配置索引
#   --domain <name> : 指定业务域（demo/example）
#   --mode <mode>   : 覆盖生成模式
#   <config.yml>    : 单文件生成（非选项参数）
# =============================================================================
$CLI_ALL = $false
$CLI_UPDATE_INDEX = $false
$CLI_DOMAIN = ""
$CLI_MODE = ""
$CLI_FILE = ""

for ($i = 0; $i -lt $args.Count; $i++) {
    switch ($args[$i]) {
        "--all" {
            $CLI_ALL = $true
        }
        "--update-index" {
            $CLI_UPDATE_INDEX = $true
        }
        "-u" {
            $CLI_UPDATE_INDEX = $true
        }
        "--domain" {
            if ($i + 1 -lt $args.Count) {
                $CLI_DOMAIN = $args[$i + 1]
                $i++
            } else {
                Write-Host "[ERROR] --domain requires a value"
                exit 1
            }
        }
        "--mode" {
            if ($i + 1 -lt $args.Count) {
                $CLI_MODE = $args[$i + 1]
                $i++
            } else {
                Write-Host "[ERROR] --mode requires a value"
                exit 1
            }
        }
        { $_ -notlike "--*" } {
            # 非选项参数：配置文件路径
            if (-not $CLI_FILE) {
                $CLI_FILE = $_
            }
        }
        default {
            if ($_ -like "--*") {
                Write-Host "[ERROR] Unknown option: $_"
                Write-Host "Usage: .\run.ps1 [--all] [--update-index] [--domain <name>] [--mode <mode>] [config.yml]"
                exit 1
            }
        }
    }
}

# =============================================================================
# 索引更新模式（--update-index）
# =============================================================================
if ($CLI_UPDATE_INDEX) {
    Write-Host ""
    Write-Host "========================================"
    Write-Host "    $TOOL_NAME — 索引更新模式"
    Write-Host "========================================"
    & $PYTHON generator.py --update-index
    exit $LASTEXITCODE
}

# =============================================================================
# 批量生成模式（--all 或 --domain + --all）
# =============================================================================
if ($CLI_ALL) {
    if (-not (Test-Path $INDEX_FILE)) {
        Write-Host "[ERROR] 索引文件不存在: $INDEX_FILE"
        Write-Host "请先运行 .\run.ps1 --update-index 生成索引"
        exit 1
    }

    # 生成批量模式共享时间戳（所有模块使用同一日志文件）
    $BATCH_TIMESTAMP = Get-Date -Format "yyyyMMdd_HHmmss"
    $BATCH_LOG_FILE = "output/log_$BATCH_TIMESTAMP.txt"

    $TOTAL = 0
    $SUCCESS = 0
    $FAILED = 0

    Write-Host ""
    Write-Host "========================================"
    Write-Host "    $TOOL_NAME — 批量生成模式"
    Write-Host "========================================"
    Write-Host "批量时间戳: $BATCH_TIMESTAMP"
    Write-Host "日志文件: $BATCH_LOG_FILE"
    Write-Host ""

    if ($CLI_DOMAIN) {
        Write-Host "目标域: $CLI_DOMAIN"
        # 生成指定域的所有模块
        $modules = Get-ModulesFromIndex -Domain $CLI_DOMAIN
        foreach ($moduleCode in $modules) {
            if ($moduleCode) {
                $configFile = "$CONFIG_DIR/$CLI_DOMAIN/${moduleCode}.yml"
                if (Test-Path $configFile) {
                    $TOTAL++
                    $result = Invoke-Generate -ConfigFile $configFile -Mode $CLI_MODE -BatchTimestamp $BATCH_TIMESTAMP
                    if ($result) { $SUCCESS++ } else { $FAILED++ }
                }
            }
        }
    } else {
        Write-Host "目标: 全部模块"
        # 生成所有模块
        $allConfigs = GetAll-ModulesFromIndex
        foreach ($configPath in $allConfigs) {
            if ($configPath) {
                $TOTAL++
                $result = Invoke-Generate -ConfigFile "$CONFIG_DIR/$configPath" -Mode $CLI_MODE -BatchTimestamp $BATCH_TIMESTAMP
                if ($result) { $SUCCESS++ } else { $FAILED++ }
            }
        }
    }

    # 写入批量汇总到日志文件
    Add-Content -Path $BATCH_LOG_FILE -Value ""
    Add-Content -Path $BATCH_LOG_FILE -Value "========================================"
    Add-Content -Path $BATCH_LOG_FILE -Value "批量生成完成"
    Add-Content -Path $BATCH_LOG_FILE -Value "  总计: $TOTAL"
    Add-Content -Path $BATCH_LOG_FILE -Value "  成功: $SUCCESS"
    Add-Content -Path $BATCH_LOG_FILE -Value "  失败: $FAILED"
    Add-Content -Path $BATCH_LOG_FILE -Value "  完成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Add-Content -Path $BATCH_LOG_FILE -Value "========================================"

    Write-Host ""
    Write-Host "========================================"
    Write-Host "批量生成完成"
    Write-Host "  总计: $TOTAL"
    Write-Host "  成功: $SUCCESS"
    Write-Host "  失败: $FAILED"
    Write-Host "  日志文件: $BATCH_LOG_FILE"
    Write-Host "========================================"
    exit 0
}

# =============================================================================
# 指定域的单文件模式（--domain xxx file.yml）
# =============================================================================
if ($CLI_DOMAIN -and $CLI_FILE) {
    # 如果 CLI_FILE 不包含路径，则拼接域路径
    if ($CLI_FILE -notmatch "[/\\]") {
        $CLI_FILE = "$CONFIG_DIR/$CLI_DOMAIN/$CLI_FILE"
    }
    Invoke-Generate -ConfigFile $CLI_FILE -Mode $CLI_MODE
    exit $LASTEXITCODE
}

# =============================================================================
# 传统 CLI 透传模式 — 有外部参数时直接调用 generator.py，跳过菜单
#
# 支持格式:
#   .\run.ps1 config/test/t1000.yml                   # 使用 YAML 中的模式
#   .\run.ps1 config/test/t1000.yml single-with-file  # 覆盖生成模式
# =============================================================================
if ($CLI_FILE) {
    # 检测模式覆盖
    $overrideMode = $CLI_MODE

    if ($overrideMode) {
        & $PYTHON generator.py $CLI_FILE $OUTPUT_DIR --mode $overrideMode
    } else {
        & $PYTHON generator.py $CLI_FILE $OUTPUT_DIR
    }
    exit $LASTEXITCODE
}

# =============================================================================
# 交互式菜单模式（无参数时进入）
# =============================================================================
while ($true) {
    Clear-Host

    Write-Host "========================================"
    Write-Host "    $TOOL_NAME"
    Write-Host "========================================"
    Write-Host ""

    # 扫描业务域列表
    $domains = @(Get-Domains)

    if ($domains.Count -eq 0) {
        Write-Host "  [WARN] No domain directories found under config/"
        Write-Host ""
        Write-Host "  Create directories like: config/demo/, config/biz/"
        Write-Host ""
        Read-Host "  Press Enter to exit"
        exit 0
    }

    Write-Host "  Please select domain:"
    Write-Host ""
    for ($i = 0; $i -lt $domains.Count; $i++) {
        Write-Host "    $($i + 1). $($domains[$i])"
    }
    Write-Host ""
    Write-Host "  Or enter 'all' to generate all domains"
    Write-Host ""
    $domainInput = Read-Host "  Enter domain number (1-$($domains.Count)), 'all' for all [Enter 'q' to quit]"

    # 退出
    if ($domainInput -eq "q" -or $domainInput -eq "9") {
        Write-Host ""
        Write-Host "  Bye!"
        Write-Host ""
        exit 0
    }

    # 全域批量生成
    if ($domainInput -eq "all" -or $domainInput -eq "a") {
        Write-Host ""
        Write-Host "  Selected: ALL DOMAINS"
        Write-Host ""

        # ── 选择生成模式 ──
        Write-Host "  ----------------------------------------"
        Write-Host "  Select generation mode:"
        Write-Host ""
        Write-Host "    0.  [default] Use mode from YAML config"
        Write-Host "    1.  single                              - 单表（无附件）"
        Write-Host "    2.  single-with-file                    - 单表 + 附件"
        Write-Host "    3.  multi-table                         - 多平级子表（无附件）"
        Write-Host "    4.  multi-table-with-file               - 多平级子表 + 附件"
        Write-Host "    5.  master-detail                       - 主子表（无附件）"
        Write-Host "    6.  master-detail-with-file             - 主子表 + 附件"
        Write-Host "    7.  master-detail-modules               - 主子表（子表独立模块）"
        Write-Host "    8.  master-detail-modules-with-file     - 主子表模块化 + 附件"
        Write-Host "    9.  master-details-tabs                 - 主多明细（页签）"
        Write-Host "    10. master-details-tabs-with-file       - 页签 + 附件"
        Write-Host "    11. master-details-tabs-dialog          - 页签 + 弹窗编辑"
        Write-Host "    12. master-details-tabs-dialog-with-file - 页签弹窗 + 附件"
        Write-Host ""
        $modeInput = Read-Host "  Enter mode number [0-12, default 0]"

        $selectedMode = switch ($modeInput) {
            "1" { "single" }
            "2" { "single-with-file" }
            "3" { "multi-table" }
            "4" { "multi-table-with-file" }
            "5" { "master-detail" }
            "6" { "master-detail-with-file" }
            "7" { "master-detail-modules" }
            "8" { "master-detail-modules-with-file" }
            "9" { "master-details-tabs" }
            "10" { "master-details-tabs-with-file" }
            "11" { "master-details-tabs-dialog" }
            "12" { "master-details-tabs-dialog-with-file" }
            default { "" }
        }

        # 遍历所有域的所有模块
        $TOTAL = 0
        $SUCCESS = 0
        $FAILED = 0
        foreach ($domain in $domains) {
            $domainYmls = @(Get-YmlFiles -Domain $domain)
            foreach ($yml in $domainYmls) {
                $TOTAL++
                $result = Invoke-Generate -ConfigFile "$CONFIG_DIR/$domain/$yml" -Mode $selectedMode
                if ($result) { $SUCCESS++ } else { $FAILED++ }
            }
        }

        Write-Host ""
        Write-Host "  ===================================="
        Write-Host "  批量生成完成（全部域）"
        Write-Host "    总计: $TOTAL"
        Write-Host "    成功: $SUCCESS"
        Write-Host "    失败: $FAILED"
        Write-Host "  ===================================="
        Write-Host ""
        Read-Host "  Press Enter to continue"
        continue
    }

    # 校验输入（数字）
    $domainNum = 0
    if (-not [int]::TryParse($domainInput, [ref]$domainNum) -or
        $domainNum -lt 1 -or $domainNum -gt $domains.Count) {
        Write-Host ""
        Write-Host "  [ERROR] Invalid input, please retry."
        Start-Sleep -Seconds 1
        continue
    }

    $selectedDomain = $domains[$domainNum - 1]

    # -------------------------------------------------------------------------
    # 第二级菜单 — 选择具体的 .yml 文件
    # -------------------------------------------------------------------------
    while ($true) {
        Clear-Host

        Write-Host "========================================"
        Write-Host "    $TOOL_NAME"
        Write-Host "========================================"
        Write-Host ""
        Write-Host "  Selected: $selectedDomain"
        Write-Host ""

        # 扫描该业务域下的 .yml 文件
        $ymls = @(Get-YmlFiles -Domain $selectedDomain)

        if ($ymls.Count -eq 0) {
            Write-Host "  [WARN] No .yml files found under config/$selectedDomain/"
            Write-Host ""
            Read-Host "  Press Enter to go back"
            break
        }

        Write-Host "  Please select module config:"
        Write-Host ""
        for ($i = 0; $i -lt $ymls.Count; $i++) {
            Write-Host "    $($i + 1). $($ymls[$i])"
        }
        Write-Host ""
        $fileInput = Read-Host "  Enter file number (1-$($ymls.Count)), 'all' for all modules [Enter 'b' to go back]"

        # 返回上级
        if ($fileInput -eq "b") {
            break
        }

        # 校验输入
        $isAll = $false
        $fileNum = 0
        if ($fileInput -eq "all" -or $fileInput -eq "a") {
            $isAll = $true
        } elseif (-not [int]::TryParse($fileInput, [ref]$fileNum) -or
                  $fileNum -lt 1 -or $fileNum -gt $ymls.Count) {
            Write-Host ""
            Write-Host "  [ERROR] Invalid input, please retry."
            Start-Sleep -Seconds 1
            continue
        }

        # ── 选择生成模式（对单文件和 'all' 均生效）──
        Write-Host ""
        Write-Host "  ----------------------------------------"
        Write-Host "  Select generation mode:"
        Write-Host ""
        Write-Host "    0.  [default] Use mode from YAML config"
        Write-Host "    1.  single                              - 单表（无附件）"
        Write-Host "    2.  single-with-file                    - 单表 + 附件"
        Write-Host "    3.  multi-table                         - 多平级子表（无附件）"
        Write-Host "    4.  multi-table-with-file               - 多平级子表 + 附件"
        Write-Host "    5.  master-detail                       - 主子表（无附件）"
        Write-Host "    6.  master-detail-with-file             - 主子表 + 附件"
        Write-Host "    7.  master-detail-modules               - 主子表（子表独立模块）"
        Write-Host "    8.  master-detail-modules-with-file     - 主子表模块化 + 附件"
        Write-Host "    9.  master-details-tabs                 - 主多明细（页签）"
        Write-Host "    10. master-details-tabs-with-file       - 页签 + 附件"
        Write-Host "    11. master-details-tabs-dialog          - 页签 + 弹窗编辑"
        Write-Host "    12. master-details-tabs-dialog-with-file - 页签弹窗 + 附件"
        Write-Host ""
        $modeInput = Read-Host "  Enter mode number [0-12, default 0]"

        $selectedMode = switch ($modeInput) {
            "1" { "single" }
            "2" { "single-with-file" }
            "3" { "multi-table" }
            "4" { "multi-table-with-file" }
            "5" { "master-detail" }
            "6" { "master-detail-with-file" }
            "7" { "master-detail-modules" }
            "8" { "master-detail-modules-with-file" }
            "9" { "master-details-tabs" }
            "10" { "master-details-tabs-with-file" }
            "11" { "master-details-tabs-dialog" }
            "12" { "master-details-tabs-dialog-with-file" }
            default { "" }
        }

        # 全量生成
        if ($isAll) {
            foreach ($yml in $ymls) {
                Invoke-Generate -ConfigFile "$CONFIG_DIR/$selectedDomain/$yml" -Mode $selectedMode
            }
            Write-Host ""
            Read-Host "  Press Enter to continue"
            continue
        }

        # 单文件生成
        $selectedYml = $ymls[$fileNum - 1]
        Invoke-Generate -ConfigFile "$CONFIG_DIR/$selectedDomain/$selectedYml" -Mode $selectedMode
        Write-Host ""
        Read-Host "  Press Enter to continue"

    }  # end inner while (second level)

}  # end outer while (first level)
