# -*- coding: utf-8 -*-
# =============================================================================
# config_loader.py — YAML 配置加载与校验
#
# 【职责】
# 负责读取生成器的 YAML 配置文件，校验其合法性，并为每个模块配置补充
# 由代码推导出的计算字段（如 PascalCase 名称、表名、API 路径等），
# 使下游的模板渲染器无需自行做字符串转换。
#
# 【核心设计决策】
# - 校验与加载分离：load() 只做读取，validate() 只做校验，两者解耦，
#   便于在 --validate 模式下只校验而不执行生成流程。
# - enrich_module() 采用"就地修改"策略，直接在原字典上追加计算字段，
#   避免创建额外的数据结构，使模板上下文中的 module 字典保持扁平。
# - 域中文名映射（DOMAIN_CHINESE_MAP）集中管理，新增业务域只需在此
#   字典中追加一行，无需改动模板。
#
# 【依赖】
#   外部: pyyaml（pip install pyyaml）
# =============================================================================

import os
from pathlib import Path

try:
    import yaml
except ImportError:
    print("Error: PyYAML is required. Install with: pip install pyyaml")
    exit(1)


class ConfigLoader:
    """
    YAML 配置加载与校验器。

    负责从磁盘读取 YAML 配置文件，校验各模块配置的合法性，
    并为模块配置补充模板渲染所需的计算字段。

    Attributes:
        REQUIRED_MODULE_FIELDS (list): 每个模块必须包含的字段名列表。
        VALID_MODES (list): 合法的生成模式列表。
        DOMAIN_CHINESE_MAP (dict): 业务域代码到中文名的映射表。
        config_path (Path): 配置文件的绝对路径。
        config (dict | None): 已加载的配置字典；未调用 load() 前为 None。
    """

    REQUIRED_MODULE_FIELDS = ['name', 'code', 'domain', 'mode']
    VALID_MODES = ['single', 'single-with-file', 'multi-table', 'multi-table-with-file', 'master-detail', 'master-detail-with-file', 'master-detail-modules', 'master-detail-modules-with-file', 'master-details-tabs', 'master-details-tabs-with-file', 'master-details-tabs-dialog', 'master-details-tabs-dialog-with-file']
    MASTER_DETAIL_MODES = ['master-detail', 'master-detail-with-file', 'master-detail-modules', 'master-detail-modules-with-file', 'master-details-tabs', 'master-details-tabs-with-file', 'master-details-tabs-dialog', 'master-details-tabs-dialog-with-file']

    # 业务域代码 → 中文名映射，用于模板中的注释和说明文字
    DOMAIN_CHINESE_MAP = {
        'demo': '示例业务域',
        'test': '测试验证域',
    }

    def __init__(self, config_path: str):
        """
        初始化配置加载器。

        Args:
            config_path (str): YAML 配置文件路径（绝对或相对路径均可）。
        """
        self.config_path = Path(config_path)
        self.config = None

    def load(self) -> dict:
        """
        从磁盘读取 YAML 配置文件并缓存到 self.config。

        使用 yaml.safe_load() 避免执行任意 Python 对象反序列化，保证安全性。
        加载结果会缓存在实例上，多次调用只读取一次文件。

        Returns:
            dict: 完整的 YAML 配置字典。

        Raises:
            FileNotFoundError: 配置文件路径不存在时抛出。
        """
        if not self.config_path.exists():
            raise FileNotFoundError(f"配置文件不存在: {self.config_path}")

        with open(self.config_path, 'r', encoding='utf-8') as f:
            self.config = yaml.safe_load(f)

        # 可配置包前缀：project.group 缺省时注入中性默认值（模板 {{ project.group }} 引用）
        project = self.config.get('project')
        if isinstance(project, dict) and not project.get('group'):
            project['group'] = 'com.libra'

        return self.config

    def validate(self) -> tuple[bool, list[str]]:
        """
        校验已加载的配置文件，收集所有错误后一次性返回。

        采用"收集所有错误"而非"遇第一个错误就抛出"的策略，
        使用户能够一次性看到所有问题，无需反复修改后重新运行。

        校验规则：
        - 配置根节点必须包含 'modules' 键
        - 每个模块必须包含 REQUIRED_MODULE_FIELDS 中的全部字段
        - mode 必须是 VALID_MODES 中的合法值
        - multi-table 模式必须定义 sub_tables
        - single-with-file 模式建议定义 file_types（仅警告，不阻断）

        Returns:
            tuple[bool, list[str]]: (是否全部合法, 错误/警告信息列表)。
                                     列表为空则表示无错误。
                                     警告信息会包含在列表中但不影响布尔值。
        """
        errors = []
        warnings = []

        if 'modules' not in self.config:
            errors.append("配置文件缺少 'modules' 节")
            return False, errors

        for i, module in enumerate(self.config.get('modules', [])):
            # 逐一检查必需字段是否存在
            for field in self.REQUIRED_MODULE_FIELDS:
                if field not in module:
                    errors.append(f"模块 {i+1} 缺少必需字段 '{field}'")

            # 检查 mode 是否是合法枚举值
            mode = module.get('mode')
            if mode not in self.VALID_MODES:
                errors.append(f"模块 '{module.get('name', i+1)}' 的 mode 值无效: {mode}")

            # multi-table / multi-table-with-file 模式需要 sub_tables 定义子表结构
            if mode in ('multi-table', 'multi-table-with-file') and 'sub_tables' not in module:
                errors.append(f"模块 '{module.get('name', i+1)}' 是 {mode} 模式但未定义 sub_tables")

            # multi-table-with-file 模式建议每个 sub_table 定义 file_types
            if mode == 'multi-table-with-file' and 'sub_tables' in module:
                for j, st in enumerate(module.get('sub_tables', [])):
                    if 'file_types' not in st:
                        warnings.append(f"警告: 模块 '{module.get('name', i+1)}' 的第 {j+1} 个 sub_table ('{st.get('code', j+1)}') 是 multi-table-with-file 模式但未定义 file_types")

            # single-with-file 模式建议有 file_types，缺失时输出警告但不阻断
            if mode == 'single-with-file' and 'file_types' not in module:
                warnings.append(f"警告: 模块 '{module.get('name', i+1)}' 是 single-with-file 模式但未定义 file_types")

            # master-detail / master-detail-with-file 模式需要 master 和 detail 节
            if mode in ['master-detail', 'master-detail-with-file']:
                if 'master' not in module:
                    errors.append(f"模块 '{module.get('name', i+1)}' 是 {mode} 模式但未定义 master 节")
                else:
                    master = module.get('master', {})
                    if 'code' not in master:
                        errors.append(f"模块 '{module.get('name', i+1)}' 的 master 节缺少 code 字段")
                    if 'fields' not in master:
                        errors.append(f"模块 '{module.get('name', i+1)}' 的 master 节缺少 fields 字段")

                if 'detail' not in module:
                    errors.append(f"模块 '{module.get('name', i+1)}' 是 {mode} 模式但未定义 detail 节")
                else:
                    detail = module.get('detail', {})
                    if 'code' not in detail:
                        errors.append(f"模块 '{module.get('name', i+1)}' 的 detail 节缺少 code 字段")
                    if 'fields' not in detail:
                        errors.append(f"模块 '{module.get('name', i+1)}' 的 detail 节缺少 fields 字段")
                    if 'master_fk' not in detail:
                        errors.append(f"模块 '{module.get('name', i+1)}' 的 detail 节缺少 master_fk 字段")
                    # master-detail-with-file 模式建议有 file_types
                    if mode == 'master-detail-with-file' and 'file_types' not in detail:
                        warnings.append(f"警告: 模块 '{module.get('name', i+1)}' 是 master-detail-with-file 模式但 detail 未定义 file_types")

            # master-detail-modules / master-detail-modules-with-file 模式需要 master 和 detail_modules 节
            if mode in ['master-detail-modules', 'master-detail-modules-with-file']:
                if 'master' not in module:
                    errors.append(f"模块 '{module.get('name', i+1)}' 是 {mode} 模式但未定义 master 节")
                else:
                    master = module.get('master', {})
                    if 'code' not in master:
                        errors.append(f"模块 '{module.get('name', i+1)}' 的 master 节缺少 code 字段")
                    if 'fields' not in master:
                        errors.append(f"模块 '{module.get('name', i+1)}' 的 master 节缺少 fields 字段")

                detail_modules = module.get('detail_modules', []) or []
                if not detail_modules:
                    errors.append(f"模块 '{module.get('name', i+1)}' 是 {mode} 模式但未定义 detail_modules 或列表为空")
                else:
                    for j, dm in enumerate(detail_modules):
                        dm_label = dm.get('code', f'第{j+1}个')
                        if 'code' not in dm:
                            errors.append(f"模块 '{module.get('name', i+1)}' 的 detail_modules[{j}] 缺少 code 字段")
                        if 'fields' not in dm:
                            errors.append(f"模块 '{module.get('name', i+1)}' 的 detail_modules[{j}] ({dm_label}) 缺少 fields 字段")
                        if 'master_fk' not in dm:
                            errors.append(f"模块 '{module.get('name', i+1)}' 的 detail_modules[{j}] ({dm_label}) 缺少 master_fk 字段")

        return len(errors) == 0, errors + warnings

    def get_modules(self) -> list[dict]:
        """
        获取配置中所有模块的列表。

        Returns:
            list[dict]: 模块配置字典列表；配置中无 modules 节时返回空列表。
        """
        return self.config.get('modules', [])

    def get_project_info(self) -> dict:
        """
        获取项目基本信息。

        Returns:
            dict: 包含 name/code/version 等字段的项目信息字典。
        """
        return self.config.get('project', {})

    def get_field_types(self) -> dict:
        """
        获取配置文件中自定义的字段类型映射表。

        注意：当前生成器优先使用 FieldBuilder.TYPE_MAPPING 中的硬编码映射，
        此方法仅供未来扩展（支持配置文件覆盖默认映射）时使用。

        Returns:
            dict: 字段类型映射字典；配置中未定义时返回空字典。
        """
        return self.config.get('field_types', {})

    def get_output_config(self) -> dict:
        """
        获取输出相关的配置项。

        Returns:
            dict: 输出配置字典；配置中未定义时返回空字典。
        """
        return self.config.get('output', {})

    def enrich_module(self, module: dict) -> dict:
        """
        为模块配置补充由代码推导出的计算字段。

        模板中需要 PascalCase 的类名、snake_case 的表名、标准 API 路径等，
        统一在此处预先计算好并注入到模块字典，避免模板内出现复杂逻辑。

        补充的字段列表：
        - domain_chinese : 业务域中文名（如 '示例业务域'）
        - domain_pascal  : 业务域 PascalCase（如 'Demo'）
        - code_pascal    : 模块代码 PascalCase（如 'Basic'）
        - code_camel     : 模块代码 camelCase（如 'basic'，当前与 code 相同）
        - table_name     : 数据库表名（如 'biz_demo_basic'）
        - api_path       : 后端 API 路径前缀（如 '/demo/basic'）

        Args:
            module (dict): 模块的原始配置字典（就地修改）。

        Returns:
            dict: 补充了计算字段后的模块配置字典（与入参同一对象）。
        """
        # 业务域相关字段
        domain = module.get('domain', '')
        module['domain_chinese'] = self.DOMAIN_CHINESE_MAP.get(domain, domain)
        module['domain_pascal'] = self._to_pascal_case(domain)

        # 模块代码相关字段
        code = module.get('code', '')
        module['code_pascal'] = self._to_pascal_case(code)
        module['code_camel'] = self._to_camel_case(code)

        # 数据库表名：遵循 biz_{domain}_{code} 命名规范
        module['table_name'] = f"biz_{domain}_{code}"

        # 后端 API 路径前缀
        module['api_path'] = f"/{domain}/{code}"

        # Java 包路径（用于模板 package 声明）
        module['package_path'] = f"{domain}.{code}"

        # 状态切换配置（可选）
        # 支持在 YAML 中配置多个状态字段，自动生成切换按钮和接口
        status_toggles = module.get('status_toggles', [])
        enriched_toggles = []
        for toggle in status_toggles:
            field = toggle.get('field', '')
            if not field:
                continue
            # 将 values 和 colors 的整数键转换为字符串键
            values = toggle.get('values', {})
            colors = toggle.get('colors', {'0': 'danger', '1': 'success'})
            enriched_toggles.append({
                'field': field,
                'field_pascal': self._to_pascal_case(field),
                'label': toggle.get('label', field),
                'values': {str(k): v for k, v in values.items()},
                'colors': {str(k): v for k, v in colors.items()},
                'icons': toggle.get('icons', {}),
            })
        module['status_toggles'] = enriched_toggles
        # 便捷标志：是否有状态切换配置
        module['has_status_toggles'] = len(enriched_toggles) > 0

        # 批量操作配置（可选）
        # 支持批量删除、批量物理删除、批量更新
        batch_ops = module.get('batch_operations', {})
        # 提取实体字段名列表，用于过滤 batch_operations.update 中不存在的字段
        _entity_field_names = [f.get('name', '') for f in module.get('fields', []) if isinstance(f, dict) and f.get('name')]
        module['batch_operations'] = {
            'delete': self._enrich_batch_delete(batch_ops.get('delete', {})),
            'physical_delete': self._enrich_batch_physical_delete(batch_ops.get('physical_delete', {})),
            'update': self._enrich_batch_update(batch_ops.get('update', {}), _entity_field_names)
        }
        # 便捷标志：是否有任何批量操作
        module['has_batch_operations'] = (
            batch_ops.get('delete', {}).get('enabled', False) or
            batch_ops.get('physical_delete', {}).get('enabled', False) or
            batch_ops.get('update', {}).get('enabled', False)
        )

        # 单条操作配置（可选）
        # 支持独立控制逻辑删除、物理删除按钮的显示
        module['single_operations'] = self._enrich_single_operations(module.get('single_operations'))

        return module

    def enrich_master_detail_submodule(self, group_module: dict, sub_config: dict, sub_type: str) -> dict:
        """
        为主子表模式的 master 或 detail 子模块补充计算字段。

        Args:
            group_module (dict): 父模块配置（包含 domain, code, name, mode 等）
            sub_config (dict): 子模块配置（master 或 detail 节的内容）
            sub_type (str): 子模块类型，'master' 或 'detail'

        Returns:
            dict: 补充了计算字段后的子模块配置字典。
        """
        # 从父模块继承 domain 和 group_code
        domain = group_module.get('domain', '')
        group_code = group_module.get('code', '')  # 如 'sample2'

        # 子模块自己的 code
        sub_code = sub_config.get('code', '')
        sub_name = sub_config.get('name', '')

        # 构建子模块字典
        sub_module = {
            **sub_config,
            'domain': domain,
            'group_code': group_code,  # 父模块的 code（如 sample2）
            'group_name': group_module.get('name', ''),  # 父模块名称
            'domain_chinese': self.DOMAIN_CHINESE_MAP.get(domain, domain),
            'domain_pascal': self._to_pascal_case(domain),
            'code': sub_code,
            'code_pascal': self._to_pascal_case(sub_code),
            'code_camel': self._to_camel_case(sub_code),
            # 表名格式: biz_{domain}_{group}_{code}，如 biz_demo_sample2_talent
            'table_name': f"biz_{domain}_{group_code}_{sub_code}",
            # 包路径: {domain}.{group_code}.{sub_code}，如 demo.sample2.talent
            'package_path': f"{domain}.{group_code}.{sub_code}",
            # API 路径: /{domain}/{group_code}/{sub_code}，如 /demo/sample2/talent
            'api_path': f"/{domain}/{group_code}/{sub_code}",
        }

        # 对于 detail 模块，添加 master_fk 相关字段
        if sub_type == 'detail':
            master_fk = sub_config.get('master_fk', '')
            sub_module['master_fk'] = master_fk
            sub_module['master_fk_pascal'] = self._to_pascal_case(master_fk)
            # snake_case 列名，用于 SQL 模板（如 'talentId' → 'talent_id'）
            sub_module['master_fk_column'] = self._to_snake_case(master_fk)
            # master 信息（用于模板中引用）
            master_config = group_module.get('master', {})
            sub_module['master_code'] = master_config.get('code', '')
            sub_module['master_name'] = master_config.get('name', '')
            sub_module['master_code_pascal'] = self._to_pascal_case(master_config.get('code', ''))

        # 确保 file_types 存在（默认空列表，避免模板访问报错）
        if 'file_types' not in sub_module:
            sub_module['file_types'] = []

        # 处理 status_toggles 配置
        # 【重要】不再从模块级继承 status_toggles，每个子模块需要独立配置
        # master 和 detail 均支持独立配置 status_toggles
        status_toggles = sub_config.get('status_toggles', [])
        enriched_toggles = []
        for toggle in status_toggles:
            field = toggle.get('field', '')
            if not field:
                continue
            # 将 values 和 colors 的整数键转换为字符串键
            values = toggle.get('values', {})
            colors = toggle.get('colors', {'0': 'danger', '1': 'success'})
            enriched_toggles.append({
                'field': field,
                'field_pascal': self._to_pascal_case(field),
                'label': toggle.get('label', field),
                'values': {str(k): v for k, v in values.items()},
                'colors': {str(k): v for k, v in colors.items()},
                'icons': toggle.get('icons', {}),
            })
        sub_module['status_toggles'] = enriched_toggles
        sub_module['has_status_toggles'] = len(enriched_toggles) > 0

        # 处理批量操作配置（master 和 detail 均支持独立配置）
        # 【重要】不再从模块级继承 batch_operations，每个子模块需要独立配置
        # 与 status_toggles 处理方式保持一致
        sub_batch_ops = sub_config.get('batch_operations', {})
        # 提取子模块实体字段名列表，用于过滤 batch_operations.update 中不存在的字段
        _sub_entity_field_names = [f.get('name', '') for f in sub_config.get('fields', []) if isinstance(f, dict) and f.get('name')]

        sub_module['batch_operations'] = {
            'delete': self._enrich_batch_delete(sub_batch_ops.get('delete', {})),
            'physical_delete': self._enrich_batch_physical_delete(sub_batch_ops.get('physical_delete', {})),
            'update': self._enrich_batch_update(sub_batch_ops.get('update', {}), _sub_entity_field_names)
        }
        # 便捷标志：是否有任何批量操作
        sub_module['has_batch_operations'] = (
            sub_module['batch_operations']['delete']['enabled'] or
            sub_module['batch_operations']['physical_delete']['enabled'] or
            sub_module['batch_operations']['update']['enabled']
        )

        # 单条操作配置（master/detail 均支持独立配置）
        sub_module['single_operations'] = self._enrich_single_operations(sub_config.get('single_operations'))

        return sub_module

    def enrich_sub_table(self, group_module: dict, sub_config: dict) -> dict:
        """
        为 multi-table 模式的子表补充计算字段。

        子表与 master-detail 子模块的逻辑相同（共享 domain/group_code），
        但不含 master_fk 等主子表关联字段。

        Args:
            group_module (dict): 父模块配置（包含 domain, code, name 等）。
            sub_config (dict): 子表配置（sub_tables 列表中的单项）。

        Returns:
            dict: 补充了计算字段后的子表配置字典。
        """
        domain = group_module.get('domain', '')
        group_code = group_module.get('code', '')

        sub_code = sub_config.get('code', '')

        result = {
            **sub_config,
            'domain': domain,
            'group_code': group_code,
            'group_name': group_module.get('name', ''),
            'domain_chinese': self.DOMAIN_CHINESE_MAP.get(domain, domain),
            'domain_pascal': self._to_pascal_case(domain),
            'code': sub_code,
            'code_pascal': self._to_pascal_case(sub_code),
            'code_camel': self._to_camel_case(sub_code),
            'table_name': f"biz_{domain}_{group_code}_{sub_code}",
            'package_path': f"{domain}.{group_code}.{sub_code}",
            'api_path': f"/{domain}/{group_code}/{sub_code}",
        }

        # 处理 status_toggles 配置（multi-table 模式的子表支持独立配置）
        status_toggles = sub_config.get('status_toggles', [])
        enriched_toggles = []
        for toggle in status_toggles:
            field = toggle.get('field', '')
            if not field:
                continue
            # 将 values 和 colors 的整数键转换为字符串键
            values = toggle.get('values', {})
            colors = toggle.get('colors', {'0': 'danger', '1': 'success'})
            enriched_toggles.append({
                'field': field,
                'field_pascal': self._to_pascal_case(field),
                'label': toggle.get('label', field),
                'values': {str(k): v for k, v in values.items()},
                'colors': {str(k): v for k, v in colors.items()},
                'icons': toggle.get('icons', {}),
            })
        result['status_toggles'] = enriched_toggles
        result['has_status_toggles'] = len(enriched_toggles) > 0

        # 处理批量操作配置（multi-table 模式的子表支持独立配置）
        # 【重要】不再从模块级继承 batch_operations，每个子表需要独立配置
        # 与 status_toggles 处理方式保持一致
        sub_batch_ops = sub_config.get('batch_operations', {})
        # 提取子表实体字段名列表，用于过滤 batch_operations.update 中不存在的字段
        _sub_entity_field_names = [f.get('name', '') for f in sub_config.get('fields', []) if isinstance(f, dict) and f.get('name')]

        result['batch_operations'] = {
            'delete': self._enrich_batch_delete(sub_batch_ops.get('delete', {})),
            'physical_delete': self._enrich_batch_physical_delete(sub_batch_ops.get('physical_delete', {})),
            'update': self._enrich_batch_update(sub_batch_ops.get('update', {}), _sub_entity_field_names)
        }
        # 便捷标志：是否有任何批量操作
        result['has_batch_operations'] = (
            result['batch_operations']['delete']['enabled'] or
            result['batch_operations']['physical_delete']['enabled'] or
            result['batch_operations']['update']['enabled']
        )

        # 单条操作配置（multi-table 子表支持独立配置）
        result['single_operations'] = self._enrich_single_operations(sub_config.get('single_operations'))

        # 处理附件配置（multi-table-with-file 模式的子表支持独立配置）
        file_types = sub_config.get('file_types', [])
        result['file_types'] = file_types
        result['has_file'] = len(file_types) > 0

        return result

    @staticmethod
    def _to_pascal_case(name: str) -> str:
        """
        将字符串转换为 PascalCase（支持驼峰、下划线、连字符）。

        示例：
        - 'demo' → 'Demo'
        - 'date_range' → 'DateRange'
        - 'sample2Talent' → 'Sample2Talent'（驼峰输入保留驼峰）
        - 'masterFk' → 'MasterFk'

        Args:
            name (str): 原始字符串（camelCase / snake_case / kebab-case）。

        Returns:
            str: PascalCase 字符串。
        """
        import re
        # 先统一转为下划线分隔（处理驼峰和连字符）
        # 'sample2Talent' → 'sample2_Talent' → 'sample2_talent'
        s1 = re.sub(r'(.)([A-Z][a-z]+)', r'\1_\2', name)
        s2 = re.sub(r'([a-z0-9])([A-Z])', r'\1_\2', s1)
        parts = s2.replace('-', '_').split('_')
        return ''.join(word.capitalize() for word in parts if word)

    @staticmethod
    def _to_camel_case(name: str) -> str:
        """
        将下划线或连字符分隔的字符串转换为 camelCase。

        先转 PascalCase 再将首字母小写。
        示例：'honor_name' → 'honorName'，'BASIC' → 'Basic'（全大写单词不拆分）

        Args:
            name (str): 原始字符串。

        Returns:
            str: camelCase 字符串；空字符串时返回空字符串。
        """
        pascal = ConfigLoader._to_pascal_case(name)
        return pascal[0].lower() + pascal[1:] if pascal else ''

    @staticmethod
    def _to_snake_case(name: str) -> str:
        """
        将 camelCase 字符串转换为 snake_case 数据库列名。

        示例：'talentId' → 'talent_id'，'masterFk' → 'master_fk'

        Args:
            name (str): camelCase 字符串。

        Returns:
            str: snake_case 字符串。
        """
        import re
        return re.sub(r'(?<!^)(?=[A-Z])', '_', name).lower()

    def _enrich_batch_delete(self, config: dict) -> dict:
        """
        处理批量逻辑删除配置。

        逻辑删除：UPDATE is_deleted = 1

        Args:
            config (dict): delete 节的配置字典。

        Returns:
            dict: 补充了默认值后的配置字典。
        """
        return {
            'enabled': config.get('enabled', False),
            'confirm_message': config.get('confirm_message', '确认删除选中的记录？')
        }

    def _enrich_batch_physical_delete(self, config: dict) -> dict:
        """
        处理批量物理删除（彻底删除）配置。

        物理删除：DELETE FROM（不可恢复）

        Args:
            config (dict): physical_delete 节的配置字典。

        Returns:
            dict: 补充了默认值后的配置字典。
        """
        return {
            'enabled': config.get('enabled', False),
            'confirm_message': config.get('confirm_message', '确认彻底删除选中的记录？此操作不可恢复！')
        }

    # 字段 type → Java 类型映射（用于批量更新的类型转换）
    TYPE_TO_JAVA = {
        'input': 'String',
        'textarea': 'String',
        'number': 'Integer',
        'decimal': 'java.math.BigDecimal',
        'date': 'java.time.LocalDate',
        'datetime': 'java.time.LocalDateTime',
        'date-year': 'Integer',
        'select': 'Integer',
    }

    def _enrich_batch_update(self, config: dict, entity_field_names: list = None) -> dict:
        """
        处理批量更新配置。

        支持新旧两种字段格式：
        - 旧格式：fields[].field / default_value / confirm_message（per-field）
        - 新格式：fields[].name / type / required / options（per-field）+ confirm_message（全局）

        Args:
            config (dict): update 节的配置字典。
            entity_field_names (list): 实体字段名列表，用于过滤不存在的字段（可选）。

        Returns:
            dict: 补充了默认值和字段白名单后的配置字典。
        """
        if not config.get('enabled', False):
            return {'enabled': False, 'fields': []}

        fields = config.get('fields', [])
        enriched_fields = []
        for f in fields:
            # 兼容旧格式 field 和新格式 name
            field_name = (f.get('name', '') or f.get('field', '')) if isinstance(f, dict) else f
            if not field_name:
                continue
            enriched_field = {
                'name': field_name,
                'name_pascal': self._to_pascal_case(field_name),
                'field': field_name,          # 保留旧 key 兼容
                'field_pascal': self._to_pascal_case(field_name),
                'label': f.get('label', field_name) if isinstance(f, dict) else field_name,
                'type': f.get('type', 'input') if isinstance(f, dict) else 'input',
                'java_type': f.get('java_type', '') if isinstance(f, dict) else '',
                'required': f.get('required', False) if isinstance(f, dict) else False,
            }
            # 如果 java_type 未显式指定，从 type 推导
            if not enriched_field['java_type']:
                enriched_field['java_type'] = self.TYPE_TO_JAVA.get(enriched_field['type'], 'String')
            # select 类型的选项列表
            if isinstance(f, dict) and 'options' in f:
                enriched_field['options'] = f['options']
            enriched_fields.append(enriched_field)

        # 过滤：只保留实体中实际存在的字段，防止模板生成不存在的 getter/setter 调用
        if entity_field_names:
            enriched_fields = [f for f in enriched_fields if f['name'] in entity_field_names]

        return {
            'enabled': True,
            'fields': enriched_fields,
            'confirm_message': config.get('confirm_message', '确认批量更新选中的记录?')
        }

    def _enrich_single_operations(self, config: dict) -> dict:
        """
        处理单条操作配置。

        向后兼容：YAML 无 single_operations 节时，默认 delete=true, physical_delete=false。

        Args:
            config (dict): single_operations 节的配置字典，可能为 None。

        Returns:
            dict: 包含 delete / physical_delete 各自 enabled + confirm_message 的字典。
        """
        if not config:
            # 向后兼容：保持当前行为（逻辑删除开启，物理删除关闭）
            return {
                'delete': {'enabled': True, 'confirm_message': '确认删除该记录？'},
                'physical_delete': {'enabled': False, 'confirm_message': '确认彻底删除该记录？此操作不可恢复！'},
            }
        return {
            'delete': {
                'enabled': config.get('delete', {}).get('enabled', True),
                'confirm_message': config.get('delete', {}).get('confirm_message', '确认删除该记录？'),
            },
            'physical_delete': {
                'enabled': config.get('physical_delete', {}).get('enabled', False),
                'confirm_message': config.get('physical_delete', {}).get('confirm_message', '确认彻底删除该记录？此操作不可恢复！'),
            },
        }
