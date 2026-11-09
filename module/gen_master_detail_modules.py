# -*- coding: utf-8 -*-
# =============================================================================
# gen_master_detail_modules.py — 主表 + N 个明细表（无附件）模式生成器
#
# 【职责】
# 处理 master-detail-modules 模式的代码生成，生成：
# - 主表（Master）: 标准 6 接口
# - N 个明细表（Detail 1..N）: 各 6 接口
#
# 【YAML 配置结构】
# mode: master-detail-modules
# master: { code, name, fields, ... }
# detail_modules:
#   - { code, name, master_fk, fields, ... }
#   - { code, name, master_fk, fields, ... }
#
# 【模板目录】
# templates/master-detail-modules/
#
# 【生成产物】
# - 04-server/（扁平化结构，所有子模块文件在同一包下）
# - 05-web/ (index.vue + 主表页 + 每个 DM 的页 + 每个 DM 的 service)
# - 02-sql/ (建表 + mock，覆盖所有 DM)
# - 03-http/ (主表 HTTP + 所有 DM HTTP)
# - 01-design/ (API/DB/UI 设计文档，覆盖所有 DM)
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
    生成主表 + N 个明细表（无附件）模式的所有代码文件。

    Args:
        config_loader: ConfigLoader 实例
        field_builder: FieldBuilder 实例
        renderer_class: TemplateRenderer 类
        template_dir: 模板根目录 (templates/)
        output_dir: 输出根目录
        project_info: 项目基本信息
        group_module: YAML 中模块的完整配置（包含 master/detail_modules 子配置）

    Returns:
        int: 成功生成的文件数量
    """
    domain = group_module.get("domain", "")
    group_code = group_module.get("code", "")
    group_name = group_module.get("name", "")

    # ============ 1. 丰富主表配置 ============
    master_config = group_module.get("master", {}) or {}
    master_module = config_loader.enrich_master_detail_submodule(
        group_module, master_config, "master"
    )
    master_module["package_path"] = f"{domain}.{group_code}"
    master_fields = field_builder.build_fields(master_config.get("fields", []))
    # 自动补充 status_toggles 引用但未在 fields 中声明的字段（DDL/Mapper/VO 需要）
    field_builder.ensure_status_fields(master_fields, master_module.get("status_toggles", []))

    # ============ 2. 丰富各明细表配置 ============
    detail_modules_config = group_module.get("detail_modules", []) or []
    detail_modules = []
    for dm_config in detail_modules_config:
        dm = config_loader.enrich_master_detail_submodule(
            group_module, dm_config, "detail"
        )
        dm["package_path"] = f"{domain}.{group_code}"
        dm["fields"] = field_builder.build_fields(dm_config.get("fields", []))
        # 自动补充 status_toggles 引用但未在 fields 中声明的字段（DDL/Mapper/VO 需要）
        field_builder.ensure_status_fields(dm["fields"], dm.get("status_toggles", []))
        dm["has_file"] = False  # 无附件版本
        detail_modules.append(dm)

    if not detail_modules:
        print("⚠️  detail_modules 为空，请检查 YAML 配置")
        return 0

    # ============ 3. 解析主表显示字段 ============
    # 注：resolve_and_inject_master_display_meta 期望 modules 是 (master, detail)
    # 这里只注入 master，detail_modules 循环各自不用显示字段注入
    master_display_meta = resolve_and_inject_master_display_meta(
        master_fields=master_fields,
        master_config=master_config,
        table_alias="m",
        modules=(master_module,),
    )
    master_display_field = master_display_meta.get("master_display_field", "id")
    master_display_column = master_display_meta.get("master_display_column", "id")
    master_display_label = master_display_meta.get("master_display_label", "主表名称")
    master_display_sql_expr = master_display_meta.get(
        "master_display_sql_expr", "CAST(m.id AS CHAR)"
    )

    # ============ 4. 组装上下文 ============
    generated_date = datetime.now().strftime("%Y-%m-%d")

    # 组级模块（用于前端 module 变量）
    web_module = {
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
        "master_display_field": master_display_field,
        "master_display_column": master_display_column,
        "master_display_label": master_display_label,
        "master_display_sql_expr": master_display_sql_expr,
        # 批量操作 & 状态切换（从主表透传）
        "has_batch_operations": master_module.get("has_batch_operations", False),
        "has_status_toggles": master_module.get("has_status_toggles", False),
        "master": master_module,
        "detail_modules": detail_modules,
    }

    # 完整 web 上下文（供单次渲染使用：index.vue / SQL / HTTP / 设计文档）
    web_context = {
        "module": web_module,
        "master_module": master_module,
        "master_fields": master_fields,
        "detail_modules": detail_modules,
        "fields": master_fields,
        "group_code": group_code,
        "group_name": group_name,
        "project": project_info,
        "generated_date": generated_date,
        "has_date_field": any(f.type == "date" for f in master_fields),
        "has_datetime_field": any(f.type == "datetime" for f in master_fields),
        "master_display_field": master_display_field,
        "master_display_column": master_display_column,
        "master_display_label": master_display_label,
        "master_display_sql_expr": master_display_sql_expr,
    }

    # 主表 Java 上下文（render_all_with_prefix 使用 module = master_module）
    master_java_context = {
        "module": master_module,
        "fields": master_fields,
        "project": project_info,
        "generated_date": generated_date,
        "has_date_field": any(f.type == "date" for f in master_fields),
        "has_datetime_field": any(f.type == "datetime" for f in master_fields),
        "group_code": group_code,
        "group_name": group_name,
        "detail_modules": detail_modules,
    }

    # ============ 5. 确定输出目录 ============
    module_output_dir = output_dir / domain / group_code

    print(f"\n{'=' * 60}")
    print(f"📦 生成模块组: {group_name} ({group_code})")
    print("📋 模式: master-detail-modules")
    print(f"   ├─ 主表: {master_module.get('name')} ({master_module.get('code')})")
    for i, dm in enumerate(detail_modules):
        prefix = "└─" if i == len(detail_modules) - 1 else "├─"
        print(f"   {prefix} 明细{i+1}: {dm.get('name')} ({dm.get('code')})")
    print(f"   └─ 主表展示字段: {master_display_field} ({master_display_column})")
    print(f"📂 输出目录: {module_output_dir}")
    print(f"{'=' * 60}")

    total_count = 0

    # ============ 6. 渲染 Java 模板 ============
    java_template_dir = template_dir / "master-detail-modules" / "04-server"
    java_output_root = module_output_dir / "04-server"

    if java_template_dir.exists():
        master_code = master_module.get("code")

        # Master 文件：Master* 前缀
        print(f"\n--- 渲染主表 ({master_code}) Java 模板 ---")
        master_renderer = renderer_class(java_template_dir)
        total_count += master_renderer.render_all_with_prefix(
            master_java_context, java_output_root, "Master"
        )
        total_count += master_renderer.render_all_with_prefix(
            master_java_context, java_output_root, "IMaster"
        )

        # Detail 文件：每个 DM 循环一次
        for dm in detail_modules:
            dm_code = dm.get("code")
            dm_java_context = {
                "module": dm,
                "fields": dm["fields"],
                "project": project_info,
                "generated_date": generated_date,
                "has_date_field": any(f.type == "date" for f in dm["fields"]),
                "has_datetime_field": any(f.type == "datetime" for f in dm["fields"]),
                "group_code": group_code,
                "group_name": group_name,
                "master_module": master_module,
                "master_fields": master_fields,
            }
            print(f"\n--- 渲染明细表 ({dm_code}) Java 模板 ---")
            dm_renderer = renderer_class(java_template_dir)
            total_count += dm_renderer.render_all_with_prefix(
                dm_java_context, java_output_root, "Detail"
            )
            total_count += dm_renderer.render_all_with_prefix(
                dm_java_context, java_output_root, "IDetail"
            )
    else:
        print(f"⚠️  Java模板目录不存在: {java_template_dir}")

    # ============ 7. 渲染 package-info.java ============
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

    # ============ 8. 渲染前端模板（逐文件显式渲染） ============
    web_template_dir = template_dir / "master-detail-modules" / "05-web"
    web_output = module_output_dir / "05-web"

    if web_template_dir.exists():
        print("\n--- 渲染前端模板 ---")
        web_renderer = renderer_class(web_template_dir)
        master_code = master_module.get("code")

        # 主表 add/edit 和 detail（使用 master-add-or-edit.vue.j2 / master-detail.vue.j2）
        master_views = [
            ("views/master-add-or-edit.vue.j2", f"{group_code}-{master_code}-add-or-edit.vue"),
            ("views/master-detail.vue.j2", f"{group_code}-{master_code}-detail.vue"),
        ]
        for tpl_path, out_name in master_views:
            out_file = str(web_output / "views" / out_name)
            print(f"  📄 {out_name}")
            web_renderer.render_to_file(tpl_path, out_file, web_context)
            total_count += 1

        # 合并 Service（主表 + 所有明细表，单一文件）
        merged_svc_tpl = "service/{{group_code}}.js.j2"
        merged_svc_out = str(web_output / "service" / f"{group_code}.js")
        print(f"  📄 {group_code}.js (merged)")
        web_renderer.render_to_file(merged_svc_tpl, merged_svc_out, web_context)
        total_count += 1

        # index.vue（含完整 detail_modules 列表）
        index_out = str(web_output / "views" / "index.vue")
        print(f"  📄 index.vue")
        web_renderer.render_to_file("views/index.vue.j2", index_out, web_context)
        total_count += 1

        # 每个 DM 的 add/edit、detail 和 service
        for dm in detail_modules:
            dm_code = dm.get("code")
            dm_context = {
                "module": web_module,
                "detail_module": dm,
                "detail_fields": dm["fields"],
                "master_module": master_module,
                "master_fields": master_fields,
                "group_code": group_code,
                "group_name": group_name,
                "project": project_info,
                "generated_date": generated_date,
                "has_date_field": any(f.type == "date" for f in dm["fields"]),
                "has_datetime_field": any(f.type == "datetime" for f in dm["fields"]),
                "master_display_field": master_display_field,
                "master_display_column": master_display_column,
                "master_display_label": master_display_label,
                "master_display_sql_expr": master_display_sql_expr,
                "has_detail_file": False,
            }
            dm_views = [
                ("views/{{module}}-add-or-edit.vue.j2", f"{group_code}-{dm_code}-add-or-edit.vue"),
                ("views/{{module}}-detail.vue.j2", f"{group_code}-{dm_code}-detail.vue"),
            ]
            for tpl_path, out_name in dm_views:
                out_file = str(web_output / "views" / out_name)
                print(f"  📄 {out_name}")
                web_renderer.render_to_file(tpl_path, out_file, dm_context)
                total_count += 1
    else:
        print(f"⚠️  前端模板目录不存在: {web_template_dir}")

    # ============ 9. 渲染 SQL 模板 ============
    sql_template_dir = template_dir / "master-detail-modules" / "02-sql"
    if sql_template_dir.exists():
        print("\n--- 渲染 SQL 模板 ---")
        sql_renderer = renderer_class(sql_template_dir)
        sql_output = module_output_dir / "02-sql"
        total_count += sql_renderer.render_all(web_context, sql_output)

    # ============ 10. 渲染 HTTP 模板 ============
    http_template_dir = template_dir / "master-detail-modules" / "03-http"
    if http_template_dir.exists():
        print("\n--- 渲染 HTTP 模板 ---")
        http_renderer = renderer_class(http_template_dir)
        http_output = module_output_dir / "03-http"
        total_count += http_renderer.render_all(web_context, http_output)

    # ============ 11. 渲染设计文档模板 ============
    design_template_dir = template_dir / "master-detail-modules" / "01-design"
    if design_template_dir.exists():
        print("\n--- 渲染设计文档模板 ---")
        design_renderer = renderer_class(design_template_dir)
        design_output = module_output_dir / "01-design"
        total_count += design_renderer.render_all(web_context, design_output)

    # ============ 12. 渲染 SQL 脚本模板 ============
    sql_scripts_template_dir = template_dir / "master-detail-modules" / "02-sql-scripts"
    if sql_scripts_template_dir.exists():
        print("\n--- 渲染 SQL 脚本模板 ---")
        sql_scripts_renderer = renderer_class(sql_scripts_template_dir)
        sql_scripts_output = module_output_dir / "02-sql-scripts"
        total_count += sql_scripts_renderer.render_all(web_context, sql_scripts_output)

    # ============ 13. 渲染 HTTP 脚本模板 ============
    http_scripts_template_dir = template_dir / "master-detail-modules" / "03-http-scripts"
    if http_scripts_template_dir.exists():
        print("\n--- 渲染 HTTP 脚本模板 ---")
        http_scripts_renderer = renderer_class(http_scripts_template_dir)
        http_scripts_output = module_output_dir / "03-http-scripts"
        total_count += http_scripts_renderer.render_all(web_context, http_scripts_output)

    # ============ 14. 渲染页面测试脚本模板 ============
    page_scripts_template_dir = template_dir / "master-detail-modules" / "04-page-scripts"
    if page_scripts_template_dir.exists():
        print("\n--- 渲染页面测试脚本模板 ---")
        page_scripts_renderer = renderer_class(page_scripts_template_dir)
        page_scripts_output = module_output_dir / "04-page-scripts"
        total_count += page_scripts_renderer.render_all(web_context, page_scripts_output)

    # ============ 15. 渲染根目录模板（AGENT.md 等） ============
    root_template_dir = template_dir / "master-detail-modules"
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

    # ============ 16. 渲染 00-inbox 模板 ============
    inbox_template_dir = template_dir / "master-detail-modules" / "00-inbox"
    if inbox_template_dir.exists():
        print("\n--- 渲染 00-inbox 模板 ---")
        inbox_renderer = renderer_class(inbox_template_dir)
        inbox_output = module_output_dir / "00-inbox"
        total_count += inbox_renderer.render_all(web_context, inbox_output)

    # ============ 17. 渲染 05-out 占位模板 ============
    out_template_dir = template_dir / "master-detail-modules" / "05-out"
    if out_template_dir.exists():
        print("\n--- 渲染 05-out 模板 ---")
        out_renderer = renderer_class(out_template_dir)
        out_output = module_output_dir / "05-out"
        total_count += out_renderer.render_all(web_context, out_output)

    print(f"\n✅ 生成 {total_count} 个文件")
    return total_count
