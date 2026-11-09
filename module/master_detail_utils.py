# -*- coding: utf-8 -*-
"""
master_detail_utils.py

主子表模板共享工具：
1) 解析主表显示字段（field / column / label）
2) 构建模板上下文元数据（含 SQL 表达式）
3) 将元数据注入到多个模块上下文
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping, MutableMapping
from typing import Any, Dict, Optional, Sequence, Tuple

# 支持在 master 配置中显式指定显示字段的 key（按优先级）
DISPLAY_FIELD_CONFIG_KEYS: Tuple[str, ...] = (
    "display_field",
    "displayField",
    "display_name_field",
    "displayNameField",
    "name_field",
    "nameField",
    "master_display_field",
    "masterDisplayField",
    "master_name_field",
)

DEFAULT_DISPLAY_FIELD = "id"
DEFAULT_DISPLAY_COLUMN = "id"
DEFAULT_DISPLAY_LABEL = "主表名称"
DEFAULT_TABLE_ALIAS = "m"


def _read_prop(source: Any, key: str, default: Any = None) -> Any:
    """兼容 dict / object 读取。"""
    if source is None:
        return default
    if isinstance(source, Mapping):
        return source.get(key, default)
    return getattr(source, key, default)


def _norm(value: Any) -> str:
    """标准化字符串。"""
    return "" if value is None else str(value).strip()


def _truthy(value: Any) -> bool:
    """宽松布尔判断。"""
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    if isinstance(value, (int, float)):
        return value != 0
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "y", "on"}
    return bool(value)


def _field_name(field: Any) -> str:
    return _norm(_read_prop(field, "name") or _read_prop(field, "field_name"))


def _field_column(field: Any) -> str:
    # 优先 column_name，其次 column，最后回退到字段名
    return _norm(
        _read_prop(field, "column_name")
        or _read_prop(field, "column")
        or _field_name(field)
    )


def _field_type(field: Any) -> str:
    return _norm(_read_prop(field, "type") or _read_prop(field, "field_type")).lower()


def _field_label(field: Any) -> str:
    return _norm(_read_prop(field, "label") or _read_prop(field, "title"))


def _iter_business_fields(master_fields: Optional[Sequence[Any]]) -> Iterable[Any]:
    """过滤 generated 字段，仅保留业务字段。"""
    for field in master_fields or []:
        generated = _read_prop(field, "generated", False) or _read_prop(
            field, "is_generated", False
        )
        if _truthy(generated):
            continue
        yield field


def _resolve_preferred_name(master_config: Optional[Mapping[str, Any]]) -> str:
    """按优先级读取显式配置的显示字段名。"""
    config = master_config or {}
    for key in DISPLAY_FIELD_CONFIG_KEYS:
        value = _norm(_read_prop(config, key, ""))
        if value:
            return value
    return ""


def _find_field_by_name_or_column(
    fields: Sequence[Any], name_or_column: str
) -> Optional[Any]:
    """先按字段名匹配，再按列名匹配（不区分大小写）。"""
    target = _norm(name_or_column).lower()
    if not target:
        return None

    for field in fields:
        if _field_name(field).lower() == target:
            return field

    for field in fields:
        col = _field_column(field)
        if col and col.lower() == target:
            return field

    return None


def _build_sql_expr(column_name: str, table_alias: str = DEFAULT_TABLE_ALIAS) -> str:
    """
    构建 SQL 显示表达式：
    - 普通列名：m.xxx
    - 已是完整表达式（含 . 或 ( ）：原样返回
    - 无列名：CAST(m.id AS CHAR)
    """
    alias = _norm(table_alias).rstrip(".") or DEFAULT_TABLE_ALIAS
    col = _norm(column_name)

    if col:
        if "." in col or "(" in col:
            return col
        return f"{alias}.{col}"

    return f"CAST({alias}.id AS CHAR)"


def resolve_master_display_field(
    master_fields: Optional[Sequence[Any]],
    master_config: Optional[Mapping[str, Any]] = None,
) -> Tuple[str, str, str]:
    """
    解析主表显示字段，返回 (field_name, column_name, label)。

    优先级：
    1) 显式配置（display_field / displayField / ...）
    2) 字段名为 name
    3) 第一个 input/textarea 字段
    4) 第一个 show_in_list=True 字段
    5) 第一个业务字段
    """
    fields = list(_iter_business_fields(master_fields))
    if not fields:
        return "", "", ""

    target = _find_field_by_name_or_column(
        fields, _resolve_preferred_name(master_config)
    )

    if target is None:
        target = _find_field_by_name_or_column(fields, "name")

    if target is None:
        for field in fields:
            if _field_type(field) in {"input", "textarea"}:
                target = field
                break

    if target is None:
        for field in fields:
            if _truthy(_read_prop(field, "show_in_list", False)):
                target = field
                break

    if target is None:
        target = fields[0]

    field_name = _field_name(target) or DEFAULT_DISPLAY_FIELD
    column_name = _field_column(target) or field_name or DEFAULT_DISPLAY_COLUMN
    label = _field_label(target) or DEFAULT_DISPLAY_LABEL
    return field_name, column_name, label


def build_master_display_meta(
    master_fields: Optional[Sequence[Any]],
    master_config: Optional[Mapping[str, Any]] = None,
    table_alias: str = DEFAULT_TABLE_ALIAS,
) -> Dict[str, str]:
    """
    构建主表显示字段元信息（模板上下文可直接使用）。

    返回两套 key：
    - master_display_*（推荐）
    - master_name_*（兼容旧模板）
    同时保留 display_* 与 *_expr 历史别名。
    """
    field_name, column_name, label = resolve_master_display_field(
        master_fields, master_config
    )

    display_field = field_name or DEFAULT_DISPLAY_FIELD
    display_column = column_name or DEFAULT_DISPLAY_COLUMN
    display_label = label or DEFAULT_DISPLAY_LABEL
    sql_expr = _build_sql_expr(display_column, table_alias=table_alias)

    return {
        # 推荐 key
        "master_display_field": display_field,
        "master_display_column": display_column,
        "master_display_label": display_label,
        "master_display_sql_expr": sql_expr,
        # 兼容 key
        "master_name_field": display_field,
        "master_name_column": display_column,
        "master_name_label": display_label,
        "master_name_sql_expr": sql_expr,
        # 历史别名
        "display_field": display_field,
        "display_column": display_column,
        "display_label": display_label,
        "master_display_expr": sql_expr,
        "master_name_expr": sql_expr,
    }


def inject_master_display_meta(
    meta: Optional[Mapping[str, Any]],
    *modules: MutableMapping[str, Any],
) -> Dict[str, Any]:
    """将元信息注入到一个或多个模块上下文（原地更新）。"""
    payload: Dict[str, Any] = dict(meta or {})
    for module in modules:
        if isinstance(module, MutableMapping):
            module.update(payload)
    return payload


def resolve_and_inject_master_display_meta(
    master_fields: Optional[Sequence[Any]],
    master_config: Optional[Mapping[str, Any]] = None,
    *target_modules: MutableMapping[str, Any],
    table_alias: str = DEFAULT_TABLE_ALIAS,
    modules: Optional[Iterable[MutableMapping[str, Any]]] = None,
) -> Dict[str, str]:
    """
    一步完成：解析 + 注入。

    支持两种调用方式：
    - resolve_and_inject_master_display_meta(..., module_a, module_b)
    - resolve_and_inject_master_display_meta(..., modules=[module_a, module_b])
    """
    meta = build_master_display_meta(
        master_fields=master_fields,
        master_config=master_config,
        table_alias=table_alias,
    )

    all_targets = list(target_modules)
    if modules:
        all_targets.extend(list(modules))

    inject_master_display_meta(meta, *all_targets)
    return meta


__all__ = (
    "DISPLAY_FIELD_CONFIG_KEYS",
    "DEFAULT_DISPLAY_FIELD",
    "DEFAULT_DISPLAY_COLUMN",
    "DEFAULT_DISPLAY_LABEL",
    "DEFAULT_TABLE_ALIAS",
    "resolve_master_display_field",
    "build_master_display_meta",
    "inject_master_display_meta",
    "resolve_and_inject_master_display_meta",
)
