# -*- coding: utf-8 -*-
# =============================================================================
# lib/__init__.py — 代码生成器工具库包声明
#
# 【职责】
# 将 lib/ 目录声明为 Python 包，并对外统一导出三个核心子模块，
# 使 generate.py 可以通过 `from lib.xxx import Xxx` 的方式引用。
#
# 【三个核心子模块的职责划分】
# - ConfigLoader      : 负责"读数据" — 加载/校验 YAML，补充计算字段
# - FieldBuilder      : 负责"转类型" — YAML 字段类型 → Java/SQL/Vue 映射
# - TemplateRenderer  : 负责"渲染代码" — Jinja2 模板 + 上下文 → 代码文件
# =============================================================================

from .config_loader import ConfigLoader
from .field_builder import FieldBuilder
from .template_renderer import TemplateRenderer

__all__ = ['ConfigLoader', 'FieldBuilder', 'TemplateRenderer']
