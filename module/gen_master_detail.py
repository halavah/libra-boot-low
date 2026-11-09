# -*- coding: utf-8 -*-
# =============================================================================
# gen_master_detail.py — 主子表（无附件）模式生成器
#
# 【职责】
# 处理 master-detail 模式的代码生成，生成：
# - 主表（Master）: 标准 6 接口
# - 明细表（Detail）: 标准 6 接口
#
# 【模板目录】
# templates/master-detail/
#
# 【生成产物】
# - 04-server/（扁平化结构）
#   controller/ mapper/ service/ entity/{po,vo,param}/
#   主表和明细表文件通过 Master*/Detail* 前缀区分，输出后自动去前缀
# - 05-web/ (前端 Vue 组件 + Service)
# - 02-sql/ (SQL 脚本，主表 + 明细表)
# - 03-http/ (HTTP 测试文件，主表 6 段 + 明细 6 段)
# =============================================================================

from datetime import datetime
from pathlib import Path

from module.master_detail_utils import resolve_and_inject_master_display_meta


def generate(
    config_loader,
    field_builder,
    renderer_class,
    template_dir: Path,
    output_dir: Path,
    project_info: dict,
    group_module: dict,
) -> int:
    """
    生成主子表模式（无附件）的所有代码文件。

    Args:
        config_loader: ConfigLoader 实例
        field_builder: FieldBuilder 实例
        renderer_class: TemplateRenderer 类
        template_dir: 模板根目录 (templates/)
        output_dir: 输出根目录
        project_info: 项目基本信息
        group_module: YAML 中模块的完整配置（包含 master/detail 子配置）

    Returns:
        int: 成功生成的文件数量
    """
    domain = group_module.get("domain", "")
    group_code = group_module.get("code", "")
    group_name = group_module.get("name", "")

    # ============ 1. 丰富子模块配置 ============
    master_config = group_module.get("master", {}) or {}
    detail_config = group_module.get("detail", {}) or {}

    master_module = config_loader.enrich_master_detail_submodule(
        group_module, master_config, "master"
    )
    detail_module = config_loader.enrich_master_detail_submodule(
        group_module, detail_config, "detail"
    )

    # 修正 package_path：所有 Java 文件放在 group 级扁平目录下，包路径统一用 {domain}.{group_code}
    master_module["package_path"] = f"{domain}.{group_code}"
    detail_module["package_path"] = f"{domain}.{group_code}"

    # ============ 2. 构建字段列表 ============
    master_fields = field_builder.build_fields(master_config.get("fields", []))
    detail_fields = field_builder.build_fields(detail_config.get("fields", []))
    # 自动补充 status_toggles 引用但未在 fields 中声明的字段（DDL/Mapper/VO 需要）
    field_builder.ensure_status_fields(master_fields, master_module.get("status_toggles", []))
    field_builder.ensure_status_fields(detail_fields, detail_module.get("status_toggles", []))

    # 解析主表显示字段并注入主/明细上下文（避免硬编码 m.name）
    master_display_meta = resolve_and_inject_master_display_meta(
        master_fields=master_fields,
        master_config=master_config,
        table_alias="m",
        modules=(master_module, detail_module),
    )
    master_display_field = master_display_meta.get("master_display_field", "id")
    master_display_column = master_display_meta.get("master_display_column", "id")
    master_display_label = master_display_meta.get("master_display_label", "主表名称")
    master_display_sql_expr = master_display_meta.get(
        "master_display_sql_expr", "CAST(m.id AS CHAR)"
    )

    # ============ 3. 组装上下文 ============
    generated_date = datetime.now().strftime("%Y-%m-%d")

    master_context = {
        "module": master_module,
        "fields": master_fields,
        "project": project_info,
        "generated_date": generated_date,
        "has_date_field": any(f.type == "date" for f in master_fields),
        "has_datetime_field": any(f.type == "datetime" for f in master_fields),
        "group_code": group_code,
        "group_name": group_name,
        "detail_module": detail_module,
    }

    detail_context = {
        "module": detail_module,
        "fields": detail_fields,
        "project": project_info,
        "generated_date": generated_date,
        "has_date_field": any(f.type == "date" for f in detail_fields),
        "has_datetime_field": any(f.type == "datetime" for f in detail_fields),
        "group_code": group_code,
        "group_name": group_name,
        "master_module": master_module,
        "master_fields": master_fields,
    }

    # ============ 4. 确定输出目录 ============
    module_output_dir = output_dir / domain / group_code

    print(f"\n{'=' * 60}")
    print(f"📦 生成模块组: {group_name} ({group_code})")
    print("📋 模式: master-detail")
    print(f"   ├─ 主表: {master_module.get('name')} ({master_module.get('code')})")
    print(f"   ├─ 明细: {detail_module.get('name')} ({detail_module.get('code')})")
    print(f"   └─ 主表展示字段: {master_display_field} ({master_display_column})")
    print(f"📂 输出目录: {module_output_dir}")
    print(f"{'=' * 60}")

    total_count = 0

    # ============ 5. 渲染 Java 模板 ============
    java_template_dir = template_dir / "master-detail" / "04-server"
    java_output_root = module_output_dir / "04-server"

    if java_template_dir.exists():
        master_code = master_module.get("code")
        detail_code = detail_module.get("code")

        # Master 文件：Master* 前缀（Controller/Mapper/MapperXml/ServiceImpl/entity po|vo|param）
        print(f"\n--- 渲染主表 ({master_code}) Java 模板 ---")
        master_renderer = renderer_class(java_template_dir)
        count = master_renderer.render_all_with_prefix(
            master_context, java_output_root, "Master"
        )
        total_count += count

        # IMaster* 前缀（Service 接口）
        count = master_renderer.render_all_with_prefix(
            master_context, java_output_root, "IMaster"
        )
        total_count += count

        # Detail 文件：Detail* 前缀（Controller/Mapper/MapperXml/ServiceImpl/entity po|vo|param）
        print(f"\n--- 渲染明细表 ({detail_code}) Java 模板 ---")
        detail_renderer = renderer_class(java_template_dir)
        count = detail_renderer.render_all_with_prefix(
            detail_context, java_output_root, "Detail"
        )
        total_count += count

        # IDetail* 前缀（Service 接口）
        count = detail_renderer.render_all_with_prefix(
            detail_context, java_output_root, "IDetail"
        )
        total_count += count
    else:
        print(f"⚠️ Java模板目录不存在: {java_template_dir}")

    # 组装共享上下文（web_context 使用 group 级 module，供后续步骤使用）
    # 注意：module 顶级属性应来自 group_module（模块组），不能用 master_module（主表）
    web_context = {
        **master_context,
        "module": {
            # 模块级属性（来自 group_module）
            "code": group_code,
            "name": group_name,
            "domain": domain,
            "code_pascal": config_loader._to_pascal_case(group_code),
            "code_camel": group_code,
            "domain_chinese": master_module.get("domain_chinese", ""),
            "domain_pascal": master_module.get("domain_pascal", ""),
            "table_name": f"biz_{domain}_{group_code}",
            "api_path": f"/{domain}/{group_code}",
            "package_path": f"{domain}.{group_code}",
            # 主表展示字段上下文（供模板选择 masterName / option label）
            "master_display_field": master_display_field,
            "master_display_column": master_display_column,
            "master_display_label": master_display_label,
            "master_display_sql_expr": master_display_sql_expr,
            # 批量操作 & 状态切换（从主表透传）
            "has_batch_operations": master_module.get("has_batch_operations", False),
            "has_status_toggles": master_module.get("has_status_toggles", False),
            # 子模块属性
            "master": master_module,
            "detail": detail_module,
        },
        "master_module": master_module,
        "master_fields": master_fields,
        "detail_module": detail_module,
        "detail_fields": detail_fields,
        "detail_context": detail_context,
        "master_display_field": master_display_field,
        "master_display_column": master_display_column,
        "master_display_label": master_display_label,
        "master_display_sql_expr": master_display_sql_expr,
    }

    # ============ 5.5 渲染 package-info.java（group 级上下文）============
    pkg_info_file = java_template_dir / "package-info.java.j2"
    if pkg_info_file.exists():
        print("\n--- 渲染 package-info ---")
        pkg_renderer = renderer_class(java_template_dir)
        output_path = pkg_renderer.compute_output_path(
            "package-info.java.j2", java_output_root, web_context
        )
        print(f"  📄 {Path(output_path).name}")
        pkg_renderer.render_to_file("package-info.java.j2", output_path, web_context)
        total_count += 1

    # ============ 6. 渲染前端模板 ============
    web_template_dir = template_dir / "master-detail" / "05-web"
    if web_template_dir.exists():
        print("\n--- 渲染前端模板 ---")
        web_renderer = renderer_class(web_template_dir)
        web_output = module_output_dir / "05-web"
        count = web_renderer.render_all(web_context, web_output)
        total_count += count
    else:
        print(f"⚠️ 前端模板目录不存在: {web_template_dir}")

    # ============ 7. 渲染 SQL 模板 ============
    sql_template_dir = template_dir / "master-detail" / "02-sql"
    if sql_template_dir.exists():
        print("\n--- 渲染 SQL 模板 ---")
        sql_renderer = renderer_class(sql_template_dir)
        sql_output = module_output_dir / "02-sql"
        count = sql_renderer.render_all(web_context, sql_output)
        total_count += count

    # ============ 8. 渲染 HTTP 模板 ============
    http_template_dir = template_dir / "master-detail" / "03-http"
    if http_template_dir.exists():
        print("\n--- 渲染 HTTP 模板 ---")
        http_renderer = renderer_class(http_template_dir)
        http_output = module_output_dir / "03-http"
        count = http_renderer.render_all(web_context, http_output)
        total_count += count

    # ============ 9. 渲染设计文档模板 ============
    design_template_dir = template_dir / "master-detail" / "01-design"
    if design_template_dir.exists():
        print("\n--- 渲染设计文档模板 ---")
        design_renderer = renderer_class(design_template_dir)
        design_output = module_output_dir / "01-design"
        count = design_renderer.render_all(web_context, design_output)
        total_count += count

    # ============ 10. 渲染 SQL 脚本模板 ============
    sql_scripts_template_dir = template_dir / "master-detail" / "02-sql-scripts"
    if sql_scripts_template_dir.exists():
        print("\n--- 渲染 SQL 脚本模板 ---")
        sql_scripts_renderer = renderer_class(sql_scripts_template_dir)
        sql_scripts_output = module_output_dir / "02-sql-scripts"
        count = sql_scripts_renderer.render_all(web_context, sql_scripts_output)
        total_count += count

    # ============ 11. 渲染 HTTP 脚本模板 ============
    http_scripts_template_dir = template_dir / "master-detail" / "03-http-scripts"
    if http_scripts_template_dir.exists():
        print("\n--- 渲染 HTTP 脚本模板 ---")
        http_scripts_renderer = renderer_class(http_scripts_template_dir)
        http_scripts_output = module_output_dir / "03-http-scripts"
        count = http_scripts_renderer.render_all(web_context, http_scripts_output)
        total_count += count

    # ============ 12. 渲染页面测试脚本模板 ============
    page_scripts_template_dir = template_dir / "master-detail" / "04-page-scripts"
    if page_scripts_template_dir.exists():
        print("\n--- 渲染页面测试脚本模板 ---")
        page_scripts_renderer = renderer_class(page_scripts_template_dir)
        page_scripts_output = module_output_dir / "04-page-scripts"
        count = page_scripts_renderer.render_all(web_context, page_scripts_output)
        total_count += count

    # ============ 13. 渲染根目录模板（AGENT.md 等） ============
    root_template_dir = template_dir / "master-detail"
    root_renderer = renderer_class(root_template_dir)
    root_templates = [
        tpl for tpl in root_renderer.get_template_files() if "/" not in tpl
    ]
    if root_templates:
        print("\n--- 渲染根目录模板 ---")
        for tpl in root_templates:
            output_path = root_renderer.compute_output_path(
                tpl, module_output_dir, web_context
            )
            print(f"  📄 {Path(output_path).name}")
            root_renderer.render_to_file(tpl, output_path, web_context)
            total_count += 1

    # ============ 14. 渲染 00-inbox 模板 ============
    inbox_template_dir = template_dir / "master-detail" / "00-inbox"
    if inbox_template_dir.exists():
        print("\n--- 渲染 00-inbox 模板 ---")
        inbox_renderer = renderer_class(inbox_template_dir)
        inbox_output = module_output_dir / "00-inbox"
        count = inbox_renderer.render_all(web_context, inbox_output)
        total_count += count

    print(f"\n✅ 生成 {total_count} 个文件")
    return total_count
