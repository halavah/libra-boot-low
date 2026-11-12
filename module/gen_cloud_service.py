# -*- coding: utf-8 -*-
# =============================================================================
# gen_cloud_service.py — 微服务独立服务（cloud-service）模式生成器
#
# 【职责】
# 处理 cloud-service 模式：生成微服务三件套（api/model/service）
# - api: Feign 契约 + 远程 DTO（独立成件·消费方只引本包）
# - model: PO 实体（LbBaseEntity 继承·cloud_ 前缀表）
# - service: 接口+实现（LbBaseService 五件套）+ Controller（Feign 契约端点+REST CRUD）
# - _runtime: 独立启动类 + application-cloud.yml（Nacos/Seata/MQ/Tracing 全套）
# - 02-sql: cloud_ 表建表
# - 03-http: HTTP 调试集
#
# 【模板目录】
# templates/cloud-service/
#
# 【产物与 libra-boot-plus cloud 服务同构】
# user/product/order 三服务结构比对即验证。
# =============================================================================

from pathlib import Path
from datetime import datetime


def generate(config_loader, field_builder, renderer_class, template_dir: Path,
             output_dir: Path, project_info: dict, module: dict = None,
             group_module: dict = None) -> int:
    """
    生成 cloud-service 模式（微服务独立服务）的所有代码文件。

    Args:
        module / group_module: 同一模块配置（generator.py 非 SINGLE 分支以 group_module 传参）。
    Returns:
        int: 成功生成的文件数量
    """
    module = module if module is not None else group_module
    module = config_loader.enrich_module(module)
    fields = field_builder.build_fields(module.get('fields', []))

    generated_date = datetime.now().strftime('%Y-%m-%d')
    context = {
        'include_runtime': True,  # cloud-service 模式：独立服务运行件（启动类+cloud yml）是核心产物——默认渲染（区别于贴入式的 single 模式）
        'module': module,
        'fields': fields,
        'non_toggle_fields': fields,
        'project': project_info,
        'generated_date': generated_date,
    }

    domain = module.get('domain', '')
    code = module.get('code', '')
    module_output_dir = output_dir / domain / code

    mode_template_dir = template_dir / 'cloud-service'
    if not mode_template_dir.exists():
        raise FileNotFoundError(f"模板目录不存在: {mode_template_dir}")

    print(f"\n{'=' * 60}")
    print(f"📦 生成模块: {module.get('name')} ({code})")
    print(f"📋 模式: cloud-service（微服务独立服务·三件套）")
    print(f"📂 输出目录: {module_output_dir}")
    print(f"{'=' * 60}")

    renderer = renderer_class(mode_template_dir)
    count = renderer.render_all(context, module_output_dir)

    print(f"\n✅ 生成 {count} 个文件")
    return count
