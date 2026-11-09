# -*- coding: utf-8 -*-
# =============================================================================
# gen_single.py — 单表（无附件）模式生成器
#
# 【职责】
# 处理 single 模式的代码生成，生成标准 6 接口：
# - 分页查询 /list
# - 查询详情 /detail
# - 新增 /add
# - 修改 /update
# - 删除 /remove
# - 导出 /export
#
# 【模板目录】
# templates/single/
#
# 【生成产物】
# - 04-server/ (Java 后端 8 文件)
# - 05-web/ (Vue 前端 3 文件)
# - 02-sql/ (SQL 脚本)
# - 03-http/ (HTTP 测试文件)
# =============================================================================

from pathlib import Path
from datetime import datetime


def generate(config_loader, field_builder, renderer_class, template_dir: Path,
             output_dir: Path, project_info: dict, module: dict) -> int:
    """
    生成单表模式（无附件）的所有代码文件。

    Args:
        config_loader: ConfigLoader 实例
        field_builder: FieldBuilder 实例
        renderer_class: TemplateRenderer 类
        template_dir: 模板根目录 (templates/)
        output_dir: 输出根目录
        project_info: 项目基本信息
        module: YAML 中单个模块的原始配置字典

    Returns:
        int: 成功生成的文件数量
    """
    # 丰富模块配置
    module = config_loader.enrich_module(module)

    # 构建字段列表
    fields = field_builder.build_fields(module.get('fields', []))
    # 自动补充 status_toggles 引用但未在 fields 中声明的字段（DDL/Mapper/VO 需要）
    field_builder.ensure_status_fields(fields, module.get('status_toggles', []))

    # 过滤掉 status_toggles 中的字段（避免重复生成）
    toggle_field_names = {t.get('field') for t in module.get('status_toggles', [])}
    non_toggle_fields = [f for f in fields if f.name not in toggle_field_names]

    # 组装上下文
    generated_date = datetime.now().strftime('%Y-%m-%d')
    context = {
        'module': module,
        'fields': fields,
        'non_toggle_fields': non_toggle_fields,  # 不包含 toggle 字段的字段列表
        'project': project_info,
        'generated_date': generated_date,
        'has_date_field': any(f.type == 'date' for f in fields),
        'has_datetime_field': any(f.type == 'datetime' for f in fields),
    }

    # 确定输出目录
    domain = module.get('domain', '')
    code = module.get('code', '')
    module_output_dir = output_dir / domain / code

    # 确定模板目录
    mode_template_dir = template_dir / 'single'
    if not mode_template_dir.exists():
        raise FileNotFoundError(f"模板目录不存在: {mode_template_dir}")

    print(f"\n{'=' * 60}")
    print(f"📦 生成模块: {module.get('name')} ({code})")
    print(f"📋 模式: single")
    print(f"📂 输出目录: {module_output_dir}")
    print(f"{'=' * 60}")

    # 创建渲染器并渲染所有模板
    renderer = renderer_class(mode_template_dir)
    count = renderer.render_all(context, module_output_dir)

    print(f"\n✅ 生成 {count} 个文件")
    return count
