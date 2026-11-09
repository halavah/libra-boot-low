#!/bin/bash
# unit-ops.sh — 单元测试运维工具（端口检查/依赖检查/模式菜单）
# 用法: ./unit-ops.sh [模式]
# 模式: 0=表结构+数据 1=仅表结构 2=仅数据
if [ ! -x "$0" ]; then chmod +x "$0" && exec "$0" "$@"; fi
cd "$(dirname "$0")"
echo "[unit-ops] 单元测试运维工具"
echo "用法: ./unit-ops.sh [0|1|2]"
echo "  0 = 表结构+数据"
echo "  1 = 仅表结构"
echo "  2 = 仅数据"
echo "详细用法请参考 UNIT.md"
