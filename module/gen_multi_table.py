# -*- coding: utf-8 -*-
# =============================================================================
# gen_multi_table.py — 多平级子表（无附件）模式生成器
#
# 【职责】
# 处理 multi-table 模式的代码生成，生成：
# - 每个 sub_table 独立拥有一套 Java 后端（Controller/Service/Mapper/Entity）
# - 彼此之间无 FK 关联，是平级的独立业务表
# - 每个子表标准 6 接口
#
# 【模板目录】
# templates/multi-table/
#
# 【生成产物】
# - 04-server/ (所有子表 Java 后端文件，按子表 code 区分)
# - 05-web/service/{group_code}.js (合并所有子表 API)
# - 05-web/views/index.vue (Tab 切换入口)
# - 05-web/views/{group_code}-{sub_code}.vue (各子表列表组件)
# - 02-sql/group_exec.sql + group_mock.sql + group_enum.md
# - 03-http/group.http (所有子表 HTTP 请求)
# =============================================================================

from pathlib import Path
from datetime import datetime


def generate(config_loader, field_builder, renderer_class, template_dir: Path,
             output_dir: Path, project_info: dict, group_module: dict) -> int:
    """
    生成多平级子表模式（无附件）的所有代码文件。

    Args:
        config_loader: ConfigLoader 实例
        field_builder: FieldBuilder 实例
        renderer_class: TemplateRenderer 类
        template_dir: 模板根目录 (templates/)
        output_dir: 输出根目录
        project_info: 项目基本信息
        group_module: YAML 中模块的完整配置（包含 sub_tables 列表）

    Returns:
        int: 成功生成的文件数量
    """
    domain = group_module.get('domain', '')
    group_code = group_module.get('code', '')
    group_name = group_module.get('name', '')

    # ============ 1. 丰富 group_module ============
    group_module = config_loader.enrich_module(group_module)

    # ============ 2. 构建所有 sub_table 信息 ============
    sub_tables_raw = group_module.get('sub_tables', [])
    enriched_sub_tables = []

    for sub_config in sub_tables_raw:
        sub_module = config_loader.enrich_sub_table(group_module, sub_config)
        # 修正 package_path：所有 Java 文件放在 group 级扁平目录下，包路径统一用 {domain}.{group_code}
        sub_module['package_path'] = f"{domain}.{group_code}"
        sub_fields = field_builder.build_fields(sub_config.get('fields', []))
        # 自动补充 status_toggles 引用但未在 fields 中声明的字段（DDL/Mapper/VO 需要）
        field_builder.ensure_status_fields(sub_fields, sub_module.get('status_toggles', []))
        enriched_sub_tables.append({
            'module': sub_module,
            'fields': sub_fields,
            'has_date_field': any(f.type == 'date' for f in sub_fields),
            'has_datetime_field': any(f.type == 'datetime' for f in sub_fields),
        })

    # ============ 3. 确定输出目录 ============
    module_output_dir = output_dir / domain / group_code
    generated_date = datetime.now().strftime('%Y-%m-%d')

    print(f"\n{'=' * 60}")
    print(f"📦 生成多子表模块: {group_name} ({group_code})")
    print(f"📋 模式: multi-table")
    for st in enriched_sub_tables:
        print(f"   ├─ 子表: {st['module'].get('name')} ({st['module'].get('code')})")
    print(f"📂 输出目录: {module_output_dir}")
    print(f"{'=' * 60}")

    total_count = 0

    # ============ 4. 为每个 sub_table 渲染 Java 模板 ============
    sub_java_template_dir = template_dir / 'multi-table' / '04-server'
    if sub_java_template_dir.exists():
        for st in enriched_sub_tables:
            sub_module = st['module']
            sub_code = sub_module.get('code')
            sub_context = {
                'module': sub_module,
                'fields': st['fields'],
                'project': project_info,
                'generated_date': generated_date,
                'has_date_field': st['has_date_field'],
                'has_datetime_field': st['has_datetime_field'],
                'group_code': group_code,
                'group_name': group_name,
            }
            print(f"\n--- 渲染子表 ({sub_code}) Java 模板 ---")
            sub_renderer = renderer_class(sub_java_template_dir)
            java_output = module_output_dir / '04-server'
            count = sub_renderer.render_all(sub_context, java_output, exclude=['package-info.java.j2'])
            total_count += count
    else:
        print(f"⚠️ sub Java 模板目录不存在: {sub_java_template_dir}")

    # ============ 5. 组装 group_context ============
    group_context = {
        'module': group_module,
        'sub_tables': enriched_sub_tables,
        'group_code': group_code,
        'group_name': group_name,
        'project': project_info,
        'generated_date': generated_date,
    }

    # ============ 5.1 渲染 package-info.java（group 级别上下文）============
    pkg_info_file = sub_java_template_dir / 'package-info.java.j2'
    if pkg_info_file.exists():
        print(f"\n--- 渲染 package-info ---")
        pkg_renderer = renderer_class(sub_java_template_dir)
        java_output = module_output_dir / '04-server'
        output_path = pkg_renderer.compute_output_path('package-info.java.j2', java_output, group_context)
        print(f"  📄 {Path(output_path).name}")
        pkg_renderer.render_to_file('package-info.java.j2', output_path, group_context)
        total_count += 1

    # ============ 5.5 渲染 01-design 模板 ============
    design_template_dir = template_dir / 'multi-table' / '01-design'
    if design_template_dir.exists():
        print(f"\n--- 渲染设计文档模板 ---")
        design_renderer = renderer_class(design_template_dir)
        design_output = module_output_dir / '01-design'
        count = design_renderer.render_all(group_context, design_output)
        total_count += count
    else:
        print(f"⚠️ 设计文档模板目录不存在: {design_template_dir}")

    # ============ 6. 渲染 SQL 模板 ============
    sql_template_dir = template_dir / 'multi-table' / '02-sql'
    if sql_template_dir.exists():
        print(f"\n--- 渲染 SQL 模板 ---")
        sql_renderer = renderer_class(sql_template_dir)
        sql_output = module_output_dir / '02-sql'
        count = sql_renderer.render_all(group_context, sql_output)
        total_count += count

    # ============ 7. 渲染 HTTP 模板 ============
    http_template_dir = template_dir / 'multi-table' / '03-http'
    if http_template_dir.exists():
        print(f"\n--- 渲染 HTTP 模板 ---")
        http_renderer = renderer_class(http_template_dir)
        http_output = module_output_dir / '03-http'
        count = http_renderer.render_all(group_context, http_output)
        total_count += count

    # ============ 8. 渲染前端 Service + index.vue ============
    web_template_dir = template_dir / 'multi-table' / '05-web'
    if web_template_dir.exists():
        print(f"\n--- 渲染前端公共模板 (service + index.vue) ---")
        web_renderer = renderer_class(web_template_dir)
        for tpl in web_renderer.get_template_files():
            # 跳过 sub-*.vue 模板
            if Path(tpl).name.startswith('sub-'):
                continue
            # service/module.js.j2 特殊处理：输出文件名应为 {group_code}.js
            if Path(tpl).name == 'module.js.j2':
                output_path = str(module_output_dir / '05-web' / 'service' / f'{group_code}.js')
            else:
                output_path = web_renderer.compute_output_path(tpl, module_output_dir / '05-web', group_context)
            print(f"  📄 {Path(output_path).name}")
            web_renderer.render_to_file(tpl, output_path, group_context)
            total_count += 1

        # ============ 9. 为每个 sub_table 渲染 Vue 子组件 ============
        sub_vue_templates = {
            'sub-list.vue.j2': '{group_code}-{sub_code}.vue',
            'sub-add-or-edit.vue.j2': '{group_code}-{sub_code}-add-or-edit.vue',
            'sub-detail.vue.j2': '{group_code}-{sub_code}-detail.vue',
        }
        views_output_dir = module_output_dir / '05-web' / 'views'
        if not DRY_RUN:
            views_output_dir.mkdir(parents=True, exist_ok=True)

        print(f"\n--- 渲染子表 Vue 组件 ---")
        for st in enriched_sub_tables:
            sub_module = st['module']
            sub_code = sub_module.get('code')
            sub_context = {
                'module': sub_module,
                'fields': st['fields'],
                'project': project_info,
                'generated_date': generated_date,
                'has_date_field': st['has_date_field'],
                'has_datetime_field': st['has_datetime_field'],
                'group_code': group_code,
                'group_name': group_name,
                'sub_tables': enriched_sub_tables,
            }
            for tpl_name, output_pattern in sub_vue_templates.items():
                tpl_path = f"views/{tpl_name}"
                tpl_full = web_template_dir / tpl_path
                if not tpl_full.exists():
                    continue
                output_name = output_pattern.format(
                    group_code=group_code,
                    sub_code=sub_code
                )
                output_path = str(views_output_dir / output_name)
                print(f"  📄 {output_name}")
                web_renderer.render_to_file(tpl_path, output_path, sub_context)
                total_count += 1
    else:
        print(f"⚠️ 前端模板目录不存在: {web_template_dir}")

    # ============ 10. 渲染 SQL 脚本模板 ============
    sql_scripts_template_dir = template_dir / 'multi-table' / '02-sql-scripts'
    if sql_scripts_template_dir.exists():
        print(f"\n--- 渲染 SQL 脚本模板 ---")
        sql_scripts_renderer = renderer_class(sql_scripts_template_dir)
        sql_scripts_output = module_output_dir / '02-sql-scripts'
        count = sql_scripts_renderer.render_all(group_context, sql_scripts_output)
        total_count += count

    # ============ 11. 渲染 HTTP 脚本模板 ============
    http_scripts_template_dir = template_dir / 'multi-table' / '03-http-scripts'
    if http_scripts_template_dir.exists():
        print(f"\n--- 渲染 HTTP 脚本模板 ---")
        http_scripts_renderer = renderer_class(http_scripts_template_dir)
        http_scripts_output = module_output_dir / '03-http-scripts'
        count = http_scripts_renderer.render_all(group_context, http_scripts_output)
        total_count += count

    # ============ 12. 渲染页面测试脚本模板 ============
    page_scripts_template_dir = template_dir / 'multi-table' / '04-page-scripts'
    if page_scripts_template_dir.exists():
        print(f"\n--- 渲染页面测试脚本模板 ---")
        page_scripts_renderer = renderer_class(page_scripts_template_dir)
        page_scripts_output = module_output_dir / '04-page-scripts'
        count = page_scripts_renderer.render_all(group_context, page_scripts_output)
        total_count += count

    # ============ 13. 渲染根目录模板（AGENT.md 等） ============
    root_template_dir = template_dir / 'multi-table'
    root_renderer = renderer_class(root_template_dir)
    root_templates = [tpl for tpl in root_renderer.get_template_files() if '/' not in tpl]
    if root_templates:
        print(f"\n--- 渲染根目录模板 ---")
        for tpl in root_templates:
            output_path = root_renderer.compute_output_path(tpl, module_output_dir, group_context)
            print(f"  📄 {Path(output_path).name}")
            root_renderer.render_to_file(tpl, output_path, group_context)
            total_count += 1

    # ============ 14. 渲染 00-inbox 模板 ============
    inbox_template_dir = template_dir / 'multi-table' / '00-inbox'
    if inbox_template_dir.exists():
        print(f"\n--- 渲染 00-inbox 模板 ---")
        inbox_renderer = renderer_class(inbox_template_dir)
        inbox_output = module_output_dir / '00-inbox'
        count = inbox_renderer.render_all(group_context, inbox_output)
        total_count += count

    print(f"\n✅ 生成 {total_count} 个文件")
    return total_count
