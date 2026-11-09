# -*- coding: utf-8 -*-
# =============================================================================
# gen_master_details_tabs_dialog_file.py — 主表（无新增）+ N 个明细表（Tab 内嵌（弹窗模式），含附件）模式生成器
#
# 【职责】
# 处理 master-details-tabs-dialog-with-file 模式的代码生成：
# - 主表（Master）: 标准 6 接口（无新增按钮，列表仅详情/编辑/删除）
# - N 个明细表（Detail 1..N）:
#   - 有附件 (has_file=True, file_types 非空): 9 接口（含上传/附件列表/删除附件）
#   - 无附件 (has_file=False, file_types 为空): 标准 6 接口
#
# 【与 master-details-tabs-dialog 的区别】
# - 每个 DM 可选附件从表（通过 file_types 控制）
# - manage.vue 含 {% if has_detail_file %} 文件上传区块
#
# 【模板目录】
# templates/master-details-tabs-dialog/         (主表和无附件 DM 的前端模板)
# templates/master-details-tabs-dialog-with-file/ (有附件 DM 的前端/SQL/HTTP 模板)
# templates/master-detail-modules/       (Java 后端模板复用)
# templates/master-detail-modules-with-file/ (有附件 DM 的 Java 后端模板)
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
    生成主表（无新增）+ N 个明细表（Tab 内嵌（弹窗模式），含附件）模式的所有代码文件。
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
    master_file_types = master_config.get("file_types", []) or []
    has_master_file = len(master_file_types) > 0
    master_module["has_file"] = has_master_file
    master_module["file_types"] = master_file_types

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
        file_types = dm_config.get("file_types", []) or []
        dm["file_types"] = file_types
        dm["has_file"] = len(file_types) > 0
        detail_modules.append(dm)

    if not detail_modules:
        print("⚠️  detail_modules 为空，请检查 YAML 配置")
        return 0

    # ============ 3. 解析主表显示字段 ============
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
        "has_master_file": has_master_file,
        "has_any_file": has_master_file or any(dm["has_file"] for dm in detail_modules),
        "has_detail_file": any(dm["has_file"] for dm in detail_modules),
    }

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
        "has_master_file": has_master_file,
        "has_file": has_master_file,
        "file_types": master_file_types,
    }

    # ============ 5. 确定输出目录 ============
    module_output_dir = output_dir / domain / group_code

    print(f"\n{'=' * 60}")
    print(f"📦 生成模块组: {group_name} ({group_code})")
    print("📋 模式: master-details-tabs-dialog-with-file")
    print(f"   ├─ 主表: {master_module.get('name')} ({master_module.get('code')})")
    for i, dm in enumerate(detail_modules):
        prefix = "└─" if i == len(detail_modules) - 1 else "├─"
        file_info = f"含附件 ({len(dm['file_types'])} types)" if dm["has_file"] else "无附件"
        print(f"   {prefix} 明细{i+1}: {dm.get('name')} ({dm.get('code')}) [{file_info}]")
    print(f"   └─ 主表展示字段: {master_display_field} ({master_display_column})")
    print(f"📂 输出目录: {module_output_dir}")
    print(f"{'=' * 60}")

    total_count = 0

    # ============ 6. 渲染 Java 模板 ============
    java_nofile_dir = template_dir / "master-detail-modules" / "04-server"
    java_withfile_dir = template_dir / "master-detail-modules-with-file" / "04-server"
    java_output_root = module_output_dir / "04-server"

    if java_nofile_dir.exists():
        master_code = master_module.get("code")

        print(f"\n--- 渲染主表 ({master_code}) Java 模板 ---")
        # 主表有附件时使用 with-file 模板
        if has_master_file and java_withfile_dir.exists():
            master_renderer = renderer_class(java_withfile_dir)
        else:
            master_renderer = renderer_class(java_nofile_dir)
        total_count += master_renderer.render_all_with_prefix(
            master_java_context, java_output_root, "Master"
        )
        total_count += master_renderer.render_all_with_prefix(
            master_java_context, java_output_root, "IMaster"
        )

        for dm in detail_modules:
            dm_code = dm.get("code")
            has_file = dm["has_file"]
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
                "has_file": has_file,
                "has_detail_file": has_file,
                "file_types": dm.get("file_types", []),
            }
            print(f"\n--- 渲染明细表 ({dm_code}) Java 模板 ---")
            if has_file and java_withfile_dir.exists():
                dm_renderer = renderer_class(java_withfile_dir)
            else:
                dm_renderer = renderer_class(java_nofile_dir)
            total_count += dm_renderer.render_all_with_prefix(
                dm_java_context, java_output_root, "Detail"
            )
            total_count += dm_renderer.render_all_with_prefix(
                dm_java_context, java_output_root, "IDetail"
            )
    else:
        print(f"⚠️  Java模板目录不存在: {java_nofile_dir}")

    # ============ 7. 渲染 package-info.java ============
    pkg_tpl_dir = java_nofile_dir
    pkg_info_file = pkg_tpl_dir / "package-info.java.j2"
    if pkg_info_file.exists():
        print("\n--- 渲染 package-info ---")
        pkg_renderer = renderer_class(pkg_tpl_dir)
        output_path = pkg_renderer.compute_output_path(
            "package-info.java.j2", java_output_root, web_context
        )
        print(f"  📄 {Path(output_path).name}")
        pkg_renderer.render_to_file("package-info.java.j2", output_path, web_context)
        total_count += 1

    # ============ 8. 渲染前端模板 ============
    web_template_dir = template_dir / "master-details-tabs-dialog-with-file" / "05-web"
    web_output = module_output_dir / "05-web"

    if web_template_dir.exists():
        print("\n--- 渲染前端模板 ---")
        web_renderer = renderer_class(web_template_dir)
        master_code = master_module.get("code")

        # 主表视图（从 no-file 模板目录取，主表无附件）
        nofile_web_template_dir = template_dir / "master-details-tabs-dialog" / "05-web"
        nofile_web_renderer = renderer_class(nofile_web_template_dir)

        # add-or-edit.vue: 主表有附件时用 with-file 渲染器（含上传区块），否则用 no-file 渲染器
        add_or_edit_renderer = web_renderer if has_master_file else nofile_web_renderer
        add_or_edit_tag = "[with-file]" if has_master_file else "[no-file]"
        add_or_edit_out = str(web_output / "views" / f"{group_code}-{master_code}-add-or-edit.vue")
        print(f"  📄 {group_code}-{master_code}-add-or-edit.vue {add_or_edit_tag}")
        add_or_edit_renderer.render_to_file("views/master-add-or-edit.vue.j2", add_or_edit_out, web_context)
        total_count += 1

        # master-detail.vue: with-file 渲染器已内置 {% if has_master_file %} 逻辑，始终用之
        detail_out = str(web_output / "views" / f"{group_code}-{master_code}-detail.vue")
        print(f"  📄 {group_code}-{master_code}-detail.vue")
        web_renderer.render_to_file("views/master-detail.vue.j2", detail_out, web_context)
        total_count += 1

        # 合并 Service（主表 + 所有明细表）
        merged_svc_out = str(web_output / "service" / f"{group_code}.js")
        print(f"  📄 {group_code}.js (merged)")
        web_renderer.render_to_file("service/module-service.js.j2", merged_svc_out, web_context)
        total_count += 1

        # index.vue（from with-file dir）
        index_out = str(web_output / "views" / "index.vue")
        print(f"  📄 index.vue")
        web_renderer.render_to_file("views/index.vue.j2", index_out, web_context)
        total_count += 1

        # 每个 DM 生成 manage.vue
        for dm in detail_modules:
            dm_code = dm.get("code")
            has_file = dm["has_file"]
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
                "has_detail_file": has_file,
                "file_types": dm.get("file_types", []),
            }
            # manage.vue：有附件用 with-file 模板，无附件用 no-file 模板
            if has_file:
                dm_renderer = web_renderer
                tpl_tag = "with-file"
            else:
                dm_renderer = nofile_web_renderer
                tpl_tag = "no-file"
            out_name = f"{group_code}-{dm_code}-manage.vue"
            out_file = str(web_output / "views" / out_name)
            print(f"  📄 {out_name} [{tpl_tag}]")
            dm_renderer.render_to_file("views/{{module}}-manage.vue.j2", out_file, dm_context)
            total_count += 1
    else:
        print(f"⚠️  前端模板目录不存在: {web_template_dir}")

    # ============ 9. 渲染 SQL 模板 ============
    sql_template_dir = template_dir / "master-details-tabs-dialog-with-file" / "02-sql"
    if not sql_template_dir.exists():
        sql_template_dir = template_dir / "master-detail-modules-with-file" / "02-sql"
    if sql_template_dir.exists():
        print("\n--- 渲染 SQL 模板 ---")
        sql_renderer = renderer_class(sql_template_dir)
        sql_output = module_output_dir / "02-sql"
        total_count += sql_renderer.render_all(web_context, sql_output)

    # ============ 10. 渲染 HTTP 模板 ============
    http_template_dir = template_dir / "master-details-tabs-dialog-with-file" / "03-http"
    if not http_template_dir.exists():
        http_template_dir = template_dir / "master-detail-modules-with-file" / "03-http"
    if http_template_dir.exists():
        print("\n--- 渲染 HTTP 模板 ---")
        http_renderer = renderer_class(http_template_dir)
        http_output = module_output_dir / "03-http"
        total_count += http_renderer.render_all(web_context, http_output)

    # ============ 11. 渲染设计文档模板 ============
    design_template_dir = template_dir / "master-details-tabs-dialog-with-file" / "01-design"
    if not design_template_dir.exists():
        design_template_dir = template_dir / "master-detail-modules-with-file" / "01-design"
    if design_template_dir.exists():
        print("\n--- 渲染设计文档模板 ---")
        design_renderer = renderer_class(design_template_dir)
        design_output = module_output_dir / "01-design"
        total_count += design_renderer.render_all(web_context, design_output)

    # ============ 12. 渲染 SQL 脚本模板 ============
    sql_scripts_template_dir = template_dir / "master-details-tabs-dialog-with-file" / "02-sql-scripts"
    if not sql_scripts_template_dir.exists():
        sql_scripts_template_dir = template_dir / "master-detail-modules-with-file" / "02-sql-scripts"
    if sql_scripts_template_dir.exists():
        print("\n--- 渲染 SQL 脚本模板 ---")
        sql_scripts_renderer = renderer_class(sql_scripts_template_dir)
        sql_scripts_output = module_output_dir / "02-sql-scripts"
        total_count += sql_scripts_renderer.render_all(web_context, sql_scripts_output)

    # ============ 13. 渲染 HTTP 脚本模板 ============
    http_scripts_template_dir = template_dir / "master-details-tabs-dialog-with-file" / "03-http-scripts"
    if not http_scripts_template_dir.exists():
        http_scripts_template_dir = template_dir / "master-detail-modules-with-file" / "03-http-scripts"
    if http_scripts_template_dir.exists():
        print("\n--- 渲染 HTTP 脚本模板 ---")
        http_scripts_renderer = renderer_class(http_scripts_template_dir)
        http_scripts_output = module_output_dir / "03-http-scripts"
        total_count += http_scripts_renderer.render_all(web_context, http_scripts_output)

    # ============ 14. 渲染页面测试脚本模板 ============
    page_scripts_template_dir = template_dir / "master-details-tabs-dialog-with-file" / "04-page-scripts"
    if not page_scripts_template_dir.exists():
        page_scripts_template_dir = template_dir / "master-detail-modules-with-file" / "04-page-scripts"
    if not page_scripts_template_dir.exists():
        page_scripts_template_dir = template_dir / "master-detail-modules" / "04-page-scripts"
    if page_scripts_template_dir.exists():
        print("\n--- 渲染页面测试脚本模板 ---")
        page_scripts_renderer = renderer_class(page_scripts_template_dir)
        page_scripts_output = module_output_dir / "04-page-scripts"
        total_count += page_scripts_renderer.render_all(web_context, page_scripts_output)

    # ============ 15. 渲染根目录模板（AGENT.md 等） ============
    root_template_dir = template_dir / "master-details-tabs-dialog-with-file"
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
    inbox_template_dir = template_dir / "master-details-tabs-dialog-with-file" / "00-inbox"
    if not inbox_template_dir.exists():
        inbox_template_dir = template_dir / "master-detail-modules-with-file" / "00-inbox"
    if inbox_template_dir.exists():
        print("\n--- 渲染 00-inbox 模板 ---")
        inbox_renderer = renderer_class(inbox_template_dir)
        inbox_output = module_output_dir / "00-inbox"
        total_count += inbox_renderer.render_all(web_context, inbox_output)

    # ============ 17. 渲染 05-out 占位模板 ============
    out_template_dir = template_dir / "master-details-tabs-dialog-with-file" / "05-out"
    if not out_template_dir.exists():
        out_template_dir = template_dir / "master-detail-modules" / "05-out"
    if out_template_dir.exists():
        print("\n--- 渲染 05-out 模板 ---")
        out_renderer = renderer_class(out_template_dir)
        out_output = module_output_dir / "05-out"
        total_count += out_renderer.render_all(web_context, out_output)

    print(f"\n✅ 生成 {total_count} 个文件")
    return total_count
