#!/bin/bash
# =============================================================================
# Libra Boot Low 代码生成器 — Bash 启动器
#
# 一、为什么需要这个脚本？
#     generator.py 是纯 CLI（参数式），新手需记忆 --all/--domain/--module/--mode
#     全部参数才能批量生成。本脚本提供两级交互菜单（选域→选配置→选模式），
#     让"跑一次生成"零记忆成本；无参数=交互，带参数=直通，兼顾两种使用习惯。
#
# 二、工具链与调用流程
#     用户运行 run.sh
#       → 扫描 config/*/ 业务域 → 选域（或 all）
#       → 扫描域内 *.yml → 选配置（或 all）
#       → 选生成模式（12 种，或默认用 YAML 内声明）
#       → 调用 python3 generator.py <config> [output] [--mode ...]
#       → 产物落 out/{domain}/{code}/ 六段 + 报告落 output/
#
# 三、脚本没有负责的事（刻意排除）
#     - 不生成/修改任何 YAML 配置（配置是输入，须手写或复制 config/test/ 样例）
#     - 不校验产物内容（质量归 CI 与 pytest）
#     - 不管理 index.json（归 generator.py -u）
#     - 不做 Python 环境安装（缺依赖时仅提示）
#
# 四、交互设计原则
#     - 一级选域：q/9 退出；all/a 全域批量
#     - 二级选配置：b 返回一级；all/a 全模块批量
#     - 模式子菜单：0=默认（用 YAML 声明）+12 模式全列；批量流共享批次时间戳
#     - 无参数=交互菜单；带参数=直通直行，执行完即退
#
# 五、换行符与兼容性
#     本文件使用 LF 换行符，兼容 bash 和 zsh（无 [[ ]]、无 here-string、无 $''）。
# =============================================================================
TOOL_NAME="Libra Boot Low Code Generator"
CONFIG_DIR="config"
OUTPUT_DIR="../../out"
VALID_MODES=("single" "single-with-file" "multi-table" "multi-table-with-file" "master-detail" "master-detail-with-file" "master-detail-modules" "master-detail-modules-with-file" "master-details-tabs" "master-details-tabs-with-file" "master-details-tabs-dialog" "master-details-tabs-dialog-with-file")
INDEX_FILE="$CONFIG_DIR/index.json"

# =============================================================================
# 检查 Python3 环境（优先使用本地 .venv，回退到系统 python3）
# =============================================================================
if [ -f ".venv/bin/python3" ]; then
    PYTHON=".venv/bin/python3"
elif command -v python3 &>/dev/null; then
    PYTHON="python3"
else
    echo ""
    echo "[ERROR] python3 not found. Please install Python 3 first."
    echo "        macOS: brew install python3"
    echo "        Linux: sudo apt install python3"
    exit 1
fi

# =============================================================================
# 工具函数
# =============================================================================

# 列出 config/ 下的业务域目录（排序）
list_domains() {
    if [ ! -d "$CONFIG_DIR" ]; then
        echo ""
        return
    fi
    find "$CONFIG_DIR" -mindepth 1 -maxdepth 1 -type d | sort | xargs -I{} basename {}
}

# 列出指定业务域下的 .yml 配置文件（排序）
list_ymls() {
    local domain="$1"
    find "$CONFIG_DIR/$domain" -maxdepth 1 -name "*.yml" | sort | xargs -I{} basename {}
}

# 从 index.json 读取指定域的模块列表（返回 JSON 数组字符串）
get_modules_from_index() {
    local domain="$1"
    if [ -f "$INDEX_FILE" ]; then
        $PYTHON -c "
import json
with open('$INDEX_FILE', 'r', encoding='utf-8') as f:
    data = json.load(f)
domain_data = data.get('domains', {}).get('$domain', {})
modules = domain_data.get('modules', [])
for m in modules:
    print(m['code'])
"
    fi
}

# 从 index.json 读取所有域的模块列表
get_all_modules_from_index() {
    if [ -f "$INDEX_FILE" ]; then
        $PYTHON -c "
import json
with open('$INDEX_FILE', 'r', encoding='utf-8') as f:
    data = json.load(f)
for config in data.get('configs', []):
    print(config['file'])
"
    fi
}

# 检查是否为有效的生成模式
is_valid_mode() {
    local mode="$1"
    for m in "${VALID_MODES[@]}"; do
        if [ "$mode" = "$m" ]; then
            return 0
        fi
    done
    return 1
}

# 执行生成：调用 generator.py，可选传入模式覆盖和批量时间戳
run_generate() {
    local config_file="$1"
    local mode="$2"          # 可选，为空则使用 YAML 中的模式
    local batch_ts="$3"      # 可选，批量模式时间戳（共享日志文件）

    # 打印头部信息（同时写入日志文件）
    _log ""
    _log "----------------------------------------"
    _log "Generating: $config_file"
    _log "Output dir: $OUTPUT_DIR"
    if [ -n "$mode" ]; then
        _log "Mode override: $mode"
    fi
    if [ -n "$batch_ts" ]; then
        _log "Batch mode: $batch_ts"
    fi
    _log "----------------------------------------"

    # 构建命令参数
    local cmd_args=("$config_file" "$OUTPUT_DIR")
    if [ -n "$mode" ]; then
        cmd_args+=("--mode" "$mode")
    fi
    if [ -n "$batch_ts" ]; then
        cmd_args+=("--batch-timestamp" "$batch_ts")
    fi

    # 执行生成器（批量模式下使用 tee 捕获输出）
    local exit_code
    if [ -n "$batch_ts" ] && [ -n "$BATCH_LOG_FILE" ]; then
        $PYTHON generator.py "${cmd_args[@]}" 2>&1 | tee -a "$BATCH_LOG_FILE"
        exit_code=${PIPESTATUS[0]}
    else
        $PYTHON generator.py "${cmd_args[@]}"
        exit_code=$?
    fi

    _log ""
    if [ $exit_code -eq 0 ]; then
        _log "  [OK] Generation complete!"
    else
        _log "  [ERROR] Generation failed (exit code: $exit_code)"
    fi
    return $exit_code
}

# 日志辅助函数：同时输出到控制台和日志文件（批量模式）
_log() {
    local msg="$1"
    echo "$msg"
    if [ -n "$BATCH_LOG_FILE" ]; then
        echo "$msg" >> "$BATCH_LOG_FILE"
    fi
}

# =============================================================================
# CLI 参数解析（支持 --all / --domain / --mode / --update-index）
# =============================================================================
CLI_ALL=false
CLI_UPDATE_INDEX=false
CLI_DOMAIN=""
CLI_MODE=""
CLI_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --all)
            CLI_ALL=true
            shift
            ;;
        --update-index|-u)
            CLI_UPDATE_INDEX=true
            shift
            ;;
        --domain)
            CLI_DOMAIN="$2"
            shift 2
            ;;
        --mode)
            CLI_MODE="$2"
            shift 2
            ;;
        -*)
            echo "[ERROR] Unknown option: $1"
            echo "Usage: $0 [--all] [--domain <name>] [--mode <mode>] [--update-index] [config.yml]"
            exit 1
            ;;
        *)
            # 非选项参数：第一个为配置文件路径，第二个为模式覆盖（兼容位置参数写法）
            if [ -z "$CLI_FILE" ]; then
                CLI_FILE="$1"
            elif [ -z "$CLI_MODE" ] && is_valid_mode "$1"; then
                CLI_MODE="$1"
            else
                echo "[ERROR] Unknown argument: $1"
                echo "Usage: $0 [--all] [--domain <name>] [--mode <mode>] [--update-index] [config.yml [mode]]"
                exit 1
            fi
            shift
            ;;
    esac
done

# =============================================================================
# 索引更新模式（--update-index）
# =============================================================================
if [ "$CLI_UPDATE_INDEX" = true ]; then
    echo ""
    echo "========================================"
    echo "    $TOOL_NAME — 索引更新模式"
    echo "========================================"
    $PYTHON generator.py --update-index
    exit $?
fi

# =============================================================================
# 批量生成模式（--all 或 --domain + --all）
# =============================================================================
if [ "$CLI_ALL" = true ]; then
    if [ ! -f "$INDEX_FILE" ]; then
        echo "[ERROR] 索引文件不存在: $INDEX_FILE"
        echo "请先运行 ./run.sh --update-index 生成索引"
        exit 1
    fi

    # 生成批量模式共享时间戳（所有模块使用同一日志文件）
    BATCH_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BATCH_LOG_FILE="output/log_${BATCH_TIMESTAMP}.txt"

    TOTAL=0
    SUCCESS=0
    FAILED=0

    echo ""
    echo "========================================"
    echo "    $TOOL_NAME — 批量生成模式"
    echo "========================================"
    echo "批量时间戳: $BATCH_TIMESTAMP"
    echo "日志文件: $BATCH_LOG_FILE"
    echo ""

    if [ -n "$CLI_DOMAIN" ]; then
        echo "目标域: $CLI_DOMAIN"
        # 生成指定域的所有模块
        while IFS= read -r module_code; do
            if [ -n "$module_code" ]; then
                config_file="$CONFIG_DIR/$CLI_DOMAIN/${module_code}.yml"
                if [ -f "$config_file" ]; then
                    ((TOTAL++))
                    if run_generate "$config_file" "$CLI_MODE" "$BATCH_TIMESTAMP"; then
                        ((SUCCESS++))
                    else
                        ((FAILED++))
                    fi
                fi
            fi
        done < <(get_modules_from_index "$CLI_DOMAIN")
    else
        echo "目标: 全部模块"
        # 生成所有模块
        while IFS= read -r config_file; do
            if [ -n "$config_file" ]; then
                ((TOTAL++))
                if run_generate "$CONFIG_DIR/$config_file" "$CLI_MODE" "$BATCH_TIMESTAMP"; then
                    ((SUCCESS++))
                else
                    ((FAILED++))
                fi
            fi
        done < <(get_all_modules_from_index)
    fi

    # 写入批量汇总到日志文件
    echo "" >> "$BATCH_LOG_FILE"
    echo "========================================" >> "$BATCH_LOG_FILE"
    echo "批量生成完成" >> "$BATCH_LOG_FILE"
    echo "  总计: $TOTAL" >> "$BATCH_LOG_FILE"
    echo "  成功: $SUCCESS" >> "$BATCH_LOG_FILE"
    echo "  失败: $FAILED" >> "$BATCH_LOG_FILE"
    echo "  完成时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$BATCH_LOG_FILE"
    echo "========================================" >> "$BATCH_LOG_FILE"

    echo ""
    echo "========================================"
    echo "批量生成完成"
    echo "  总计: $TOTAL"
    echo "  成功: $SUCCESS"
    echo "  失败: $FAILED"
    echo "  日志文件: $BATCH_LOG_FILE"
    echo "========================================"
    exit 0
fi

# =============================================================================
# 指定域的单文件模式（--domain xxx file.yml）
# =============================================================================
if [ -n "$CLI_DOMAIN" ] && [ -n "$CLI_FILE" ]; then
    # 如果 CLI_FILE 不包含路径，则拼接域路径
    if ! printf '%s' "$CLI_FILE" | grep -q '/'; then
        CLI_FILE="$CONFIG_DIR/$CLI_DOMAIN/$CLI_FILE"
    fi
    run_generate "$CLI_FILE" "$CLI_MODE"
    exit $?
fi

# =============================================================================
# 传统 CLI 透传模式 — 有外部参数时直接调用 generator.py，跳过菜单
#
# 支持格式:
#   ./run.sh config/test/t1000.yml                   # 使用 YAML 中的模式
#   ./run.sh config/test/t1000.yml single-with-file  # 覆盖生成模式
# =============================================================================
if [ -n "$CLI_FILE" ]; then
    # 检测第二个参数是否为合法模式名（兼容旧版调用方式）
    OVERRIDE_MODE=""
    if [ -n "$CLI_MODE" ]; then
        OVERRIDE_MODE="$CLI_MODE"
    fi

    if [ -n "$OVERRIDE_MODE" ]; then
        $PYTHON generator.py "$CLI_FILE" "$OUTPUT_DIR" --mode "$OVERRIDE_MODE"
    else
        $PYTHON generator.py "$CLI_FILE" "$OUTPUT_DIR"
    fi
    exit $?
fi

# =============================================================================
# 交互式菜单模式（无参数时进入）
# =============================================================================
while true; do
    clear

    echo "========================================"
    echo "    $TOOL_NAME"
    echo "========================================"
    echo ""

    # 扫描业务域列表
    DOMAINS=()
    while IFS= read -r line; do
        [ -n "$line" ] && DOMAINS+=("$line")
    done < <(list_domains)

    if [ ${#DOMAINS[@]} -eq 0 ]; then
        echo "  [WARN] No domain directories found under config/"
        echo ""
        echo "  Create directories like: config/demo/, config/biz/"
        echo ""
        read -p "Press Enter to exit..." _
        exit 0
    fi

    echo "  Please select domain:"
    echo ""
    for i in "${!DOMAINS[@]}"; do
        echo "    $((i + 1)). ${DOMAINS[$i]}"
    done
    echo ""
    echo "  Or enter 'all' to generate all domains"
    echo ""
    read -p "  Enter domain number (1-${#DOMAINS[@]}), 'all' for all [Enter 'q' to quit]: " DOMAIN_INPUT

    # 退出
    if [ "$DOMAIN_INPUT" = "q" ] || [ "$DOMAIN_INPUT" = "9" ]; then
        echo ""
        echo "  Bye!"
        echo ""
        exit 0
    fi

    # 全域批量生成
    if [ "$DOMAIN_INPUT" = "all" ] || [ "$DOMAIN_INPUT" = "a" ]; then
        echo ""
        echo "  Selected: ALL DOMAINS"
        echo ""

        # ── 选择生成模式 ──
        echo "  ----------------------------------------"
        echo "  Select generation mode:"
        echo ""
        echo "    0.  [default] Use mode from YAML config"
        echo "    1.  single                              — 单表（无附件）"
        echo "    2.  single-with-file                    — 单表 + 附件"
        echo "    3.  multi-table                         — 多平级子表（无附件）"
        echo "    4.  multi-table-with-file               — 多平级子表 + 附件"
        echo "    5.  master-detail                       — 主子表（无附件）"
        echo "    6.  master-detail-with-file             — 主子表 + 附件"
        echo "    7.  master-detail-modules               — 主子表（子表独立模块）"
        echo "    8.  master-detail-modules-with-file     — 主子表模块化 + 附件"
        echo "    9.  master-details-tabs                 — 主多明细（页签）"
        echo "    10. master-details-tabs-with-file       — 页签 + 附件"
        echo "    11. master-details-tabs-dialog          — 页签 + 弹窗编辑"
        echo "    12. master-details-tabs-dialog-with-file — 页签弹窗 + 附件"
        echo ""
        read -p "  Enter mode number [0-12, default 0]: " MODE_INPUT

        case "$MODE_INPUT" in
            1) SELECTED_MODE="single" ;;
            2) SELECTED_MODE="single-with-file" ;;
            3) SELECTED_MODE="multi-table" ;;
            4) SELECTED_MODE="multi-table-with-file" ;;
            5) SELECTED_MODE="master-detail" ;;
            6) SELECTED_MODE="master-detail-with-file" ;;
            7) SELECTED_MODE="master-detail-modules" ;;
            8) SELECTED_MODE="master-detail-modules-with-file" ;;
            9) SELECTED_MODE="master-details-tabs" ;;
            10) SELECTED_MODE="master-details-tabs-with-file" ;;
            11) SELECTED_MODE="master-details-tabs-dialog" ;;
            12) SELECTED_MODE="master-details-tabs-dialog-with-file" ;;
            *) SELECTED_MODE="" ;;
        esac

        # 生成批量模式共享时间戳
        BATCH_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        BATCH_LOG_FILE="output/log_${BATCH_TIMESTAMP}.txt"

        echo ""
        echo "  批量时间戳: $BATCH_TIMESTAMP"
        echo "  日志文件: $BATCH_LOG_FILE"
        echo ""

        # 遍历所有域的所有模块
        TOTAL=0
        SUCCESS=0
        FAILED=0
        for domain in "${DOMAINS[@]}"; do
            YMLS=()  # 清空数组
            while IFS= read -r yml; do
                [ -n "$yml" ] && YMLS+=("$yml")
            done < <(list_ymls "$domain")
            for yml in "${YMLS[@]}"; do
                ((TOTAL++))
                if run_generate "$CONFIG_DIR/$domain/$yml" "$SELECTED_MODE" "$BATCH_TIMESTAMP"; then
                    ((SUCCESS++))
                else
                    ((FAILED++))
                fi
            done
        done

        # 写入批量汇总到日志文件
        echo "" >> "$BATCH_LOG_FILE"
        echo "========================================" >> "$BATCH_LOG_FILE"
        echo "批量生成完成（全部域）" >> "$BATCH_LOG_FILE"
        echo "  总计: $TOTAL" >> "$BATCH_LOG_FILE"
        echo "  成功: $SUCCESS" >> "$BATCH_LOG_FILE"
        echo "  失败: $FAILED" >> "$BATCH_LOG_FILE"
        echo "  完成时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$BATCH_LOG_FILE"
        echo "========================================" >> "$BATCH_LOG_FILE"

        echo ""
        echo "  ===================================="
        echo "  批量生成完成（全部域）"
        echo "    总计: $TOTAL"
        echo "    成功: $SUCCESS"
        echo "    失败: $FAILED"
        echo "    日志文件: $BATCH_LOG_FILE"
        echo "  ===================================="
        echo ""
        read -p "  Press Enter to continue..." _
        continue
    fi

    # 校验输入（数字）
    case "$DOMAIN_INPUT" in
        ''|*[!0-9]*) echo ""; echo "  [ERROR] Invalid input, please retry."; sleep 1; continue ;;
    esac
    if [ "$DOMAIN_INPUT" -lt 1 ] || \
       [ "$DOMAIN_INPUT" -gt ${#DOMAINS[@]} ]; then
        echo ""
        echo "  [ERROR] Invalid input, please retry."
        sleep 1
        continue
    fi

    SELECTED_DOMAIN="${DOMAINS[$((DOMAIN_INPUT - 1))]}"

    # -------------------------------------------------------------------------
    # 第二级菜单 — 选择具体的 .yml 文件
    # -------------------------------------------------------------------------
    while true; do
        clear

        echo "========================================"
        echo "    $TOOL_NAME"
        echo "========================================"
        echo ""
        echo "  Selected: $SELECTED_DOMAIN"
        echo ""

        # 扫描该业务域下的 .yml 文件
        YMLS=()
        while IFS= read -r line; do
            [ -n "$line" ] && YMLS+=("$line")
        done < <(list_ymls "$SELECTED_DOMAIN")

        if [ ${#YMLS[@]} -eq 0 ]; then
            echo "  [WARN] No .yml files found under config/$SELECTED_DOMAIN/"
            echo ""
            read -p "  Press Enter to go back..." _
            break
        fi

        echo "  Please select module config:"
        echo ""
        for i in "${!YMLS[@]}"; do
            echo "    $((i + 1)). ${YMLS[$i]}"
        done
        echo ""
        read -p "  Enter file number (1-${#YMLS[@]}), 'all' for all modules [Enter 'b' to go back]: " FILE_INPUT

        # 返回上级
        if [ "$FILE_INPUT" = "b" ]; then
            break
        fi

        # 校验输入
        IS_ALL=false
        if [ "$FILE_INPUT" = "all" ] || [ "$FILE_INPUT" = "a" ]; then
            IS_ALL=true
        elif case "$FILE_INPUT" in ''|*[!0-9]*) true;; *) false;; esac; then
            echo ""
            echo "  [ERROR] Invalid input, please retry."
            sleep 1
            continue
        fi

        # ── 选择生成模式（对单文件和 'all' 均生效）──
        echo ""
        echo "  ----------------------------------------"
        echo "  Select generation mode:"
        echo ""
        echo "    0.  [default] Use mode from YAML config"
        echo "    1.  single                              — 单表（无附件）"
        echo "    2.  single-with-file                    — 单表 + 附件"
        echo "    3.  multi-table                         — 多平级子表（无附件）"
        echo "    4.  multi-table-with-file               — 多平级子表 + 附件"
        echo "    5.  master-detail                       — 主子表（无附件）"
        echo "    6.  master-detail-with-file             — 主子表 + 附件"
        echo "    7.  master-detail-modules               — 主子表（子表独立模块）"
        echo "    8.  master-detail-modules-with-file     — 主子表模块化 + 附件"
        echo "    9.  master-details-tabs                 — 主多明细（页签）"
        echo "    10. master-details-tabs-with-file       — 页签 + 附件"
        echo "    11. master-details-tabs-dialog          — 页签 + 弹窗编辑"
        echo "    12. master-details-tabs-dialog-with-file — 页签弹窗 + 附件"
        echo ""
        read -p "  Enter mode number [0-12, default 0]: " MODE_INPUT

        case "$MODE_INPUT" in
            1) SELECTED_MODE="single" ;;
            2) SELECTED_MODE="single-with-file" ;;
            3) SELECTED_MODE="multi-table" ;;
            4) SELECTED_MODE="multi-table-with-file" ;;
            5) SELECTED_MODE="master-detail" ;;
            6) SELECTED_MODE="master-detail-with-file" ;;
            7) SELECTED_MODE="master-detail-modules" ;;
            8) SELECTED_MODE="master-detail-modules-with-file" ;;
            9) SELECTED_MODE="master-details-tabs" ;;
            10) SELECTED_MODE="master-details-tabs-with-file" ;;
            11) SELECTED_MODE="master-details-tabs-dialog" ;;
            12) SELECTED_MODE="master-details-tabs-dialog-with-file" ;;
            *) SELECTED_MODE="" ;;
        esac

        # 全量生成
        if [ "$IS_ALL" = true ]; then
            for yml in "${YMLS[@]}"; do
                run_generate "$CONFIG_DIR/$SELECTED_DOMAIN/$yml" "$SELECTED_MODE"
            done
            echo ""
            read -p "  Press Enter to continue..." _
            continue
        fi

        # 单文件生成
        SELECTED_YML="${YMLS[$((FILE_INPUT - 1))]}"
        run_generate "$CONFIG_DIR/$SELECTED_DOMAIN/$SELECTED_YML" "$SELECTED_MODE"
        echo ""
        read -p "  Press Enter to continue..." _

    done  # end inner while (second level)

done  # end outer while (first level)
