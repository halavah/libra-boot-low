# -*- coding: utf-8 -*-
# =============================================================================
# field_builder.py — 字段类型转换器
#
# 【职责】
# 将 YAML 配置中的字段描述（type: input/select/date-year/...）转换为
# 包含 Java 类型、SQL 类型、MyBatis JdbcType、Vue 组件等完整类型信息
# 的 FieldDefinition 数据对象，供 Jinja2 模板直接使用。
#
# 【核心设计思路】
# - TYPE_MAPPING 是本文件的核心：以 YAML type 为 key，记录该类型在
#   Java / SQL / Vue 三个技术栈中的对应形态。新增类型只需在此表加一行，
#   其余逻辑会自动适配。
# - FieldDefinition 是一个 dataclass，字段全部扁平化，模板可直接用
#   {{ field.java_type }}、{{ field.column_name }} 等方式引用，无需
#   在模板内做任何类型判断或字符串转换。
# - build() 方法完成从原始 dict → FieldDefinition 的转换，所有计算
#   （snake_case、PascalCase、Vue 默认值、options_json 等）都在此处
#   集中处理，模板保持纯展示逻辑。
# - get_vue_form_item() 等辅助方法供 FieldBuilder 作为工具类使用（如
#   在需要动态生成 Vue 片段但不走模板的场景），当前生成器主流程不调用，
#   仅供扩展备用。
#
# 【依赖】
#   标准库: dataclasses, typing, re, json
# =============================================================================

from dataclasses import dataclass
from typing import Optional


@dataclass
class FieldDefinition:
    """
    单个业务字段的完整定义，包含原始配置属性和所有计算字段。

    该对象在 Jinja2 模板上下文中以 fields 列表的形式传入，
    模板可直接通过 {{ field.java_type }}、{{ field.column_name }} 等方式
    引用任意属性，无需在模板内做字符串转换。

    原始属性（来自 YAML 配置）：
        name (str): 字段名（camelCase，对应 Java 字段名）。
        label (str): 中文标签，用于表单、列表列头、SQL 注释。
        type (str): 字段类型（input/select/date-year/...）。
        required (bool): 是否必填，影响表单校验和 SQL NOT NULL。
        filterable (bool): 是否可搜索，影响 Param 类和搜索表单。
        show_in_list (bool): 是否显示在列表，影响 columns 配置。
        indexed (bool): 是否建立数据库索引（自动与 filterable 同步）。
        generated (bool): 是否为自动生成字段（如审计字段），模板跳过表单渲染。
        options (list | None): 下拉选项列表，仅 select 类型有效。
        default (str | None): 字段默认值。
        placeholder (str | None): 表单占位文本。
        maxlength (int | None): 输入框最大长度。

    计算属性（由 FieldBuilder.build() 填充）：
        java_type (str): 对应的 Java 类型（如 'String'、'Integer'）。
        sql_type (str): 对应的 SQL 列类型（如 'VARCHAR'、'INT'）。
        sql_length (str): SQL 类型长度参数（如 '200'、'10,2'），无则为空。
        vue_component (str): 对应的 Vue 组件（如 'el-input'）。
        mybatis_jdbc_type (str): MyBatis JdbcType（如 'VARCHAR'、'INTEGER'）。
        column_name (str): 数据库列名（snake_case，如 'honor_name'）。
        name_pascal (str): PascalCase 字段名（如 'HonorName'），用于 getter/setter。
        name_camel (str): camelCase 字段名（与 name 相同，备用）。
        default_value (str): Vue 响应式对象中的默认值字符串（如 'null'）。
        vue_filter_type (str): 搜索表单组件类型（如 'input'、'select'、'year'）。
        vue_display (str): 详情页展示用的 Vue 表达式（如 '{{ info.honorName }}'）。
        options_json (str): 序列化为 JSON 字符串的选项列表，供 Vue 模板使用。
    """
    name: str
    label: str
    type: str
    required: bool = False
    filterable: bool = False
    show_in_list: bool = False
    indexed: bool = False  # 是否建立索引
    generated: bool = False  # 是否为自动生成字段（审计字段）
    options: Optional[list[dict]] = None
    default: Optional[str] = None
    placeholder: Optional[str] = None
    maxlength: Optional[int] = None

    # 计算字段
    java_type: str = ''
    sql_type: str = ''
    sql_length: str = ''
    vue_component: str = ''
    mybatis_jdbc_type: str = ''
    column_name: str = ''  # snake_case 列名
    name_pascal: str = ''  # PascalCase 字段名
    name_camel: str = ''  # camelCase 字段名
    default_value: str = 'null'  # Vue 默认值
    vue_filter_type: str = 'input'  # 搜索表单类型
    vue_display: str = ''  # Vue 详情页显示模板
    options_json: str = '[]'  # 选项 JSON


class FieldBuilder:
    """
    字段类型转换器，将 YAML 字段配置转换为 FieldDefinition 对象。

    TYPE_MAPPING 是本类的核心数据，定义了各 YAML type 到 Java/SQL/Vue/
    MyBatis 类型的完整映射关系。新增字段类型只需在此表追加一行。
    """

    # 字段类型映射表：YAML type → Java/SQL/Vue/MyBatis 类型
    # 遵循项目规范：Integer 传输枚举、LocalDate/LocalDateTime 处理日期时间
    TYPE_MAPPING = {
        'input': {
            'java': 'String',
            'sql': 'VARCHAR',
            'sql_length': '200',
            'vue': 'el-input',
            'jdbc': 'VARCHAR',
        },
        'textarea': {
            'java': 'String',
            'sql': 'TEXT',
            'sql_length': '',
            'vue': 'el-input[type="textarea"]',
            'jdbc': 'LONGVARCHAR',
        },
        'number': {
            'java': 'Integer',
            'sql': 'INT',
            'sql_length': '',
            'vue': 'el-input-number',
            'jdbc': 'INTEGER',
        },
        'decimal': {
            'java': 'BigDecimal',
            'sql': 'DECIMAL',
            'sql_length': '10,2',
            'vue': 'el-input-number[:precision="2"]',
            'jdbc': 'DECIMAL',
        },
        'date': {
            'java': 'LocalDate',
            'sql': 'DATE',
            'sql_length': '',
            'vue': 'el-date-picker[type="date"]',
            'jdbc': 'DATE',
        },
        'datetime': {
            'java': 'LocalDateTime',
            'sql': 'DATETIME',
            'sql_length': '',
            'vue': 'el-date-picker[type="datetime"]',
            'jdbc': 'TIMESTAMP',
        },
        'date-year': {
            'java': 'Integer',
            'sql': 'INT',
            'sql_length': '',
            'vue': 'el-date-picker[type="year"]',
            'jdbc': 'INTEGER',
        },
        'date-month': {
            'java': 'String',
            'sql': 'VARCHAR',
            'sql_length': '7',
            'vue': 'el-date-picker[type="month"]',
            'jdbc': 'VARCHAR',
        },
        'select': {
            'java': 'Integer',
            'sql': 'INT',
            'sql_length': '',
            'vue': 'el-select',
            'jdbc': 'INTEGER',
        },
        'upload': {
            'java': 'String',
            'sql': 'VARCHAR',
            'sql_length': '500',
            'vue': 'el-upload',
            'jdbc': 'VARCHAR',
        },
    }

    def __init__(self):
        """初始化字段构建器（无状态，所有数据来自 TYPE_MAPPING）。"""
        pass

    def build(self, field_config: dict) -> FieldDefinition:
        """
        将单个 YAML 字段配置字典转换为 FieldDefinition 对象。

        转换逻辑：
        1. 根据 type 在 TYPE_MAPPING 中查找 Java/SQL/Vue/MyBatis 映射
        2. 将 camelCase 的 name 转换为 snake_case 的 column_name
        3. 根据字段类型确定搜索表单组件类型（vue_filter_type）
        4. 确定 Vue 响应式对象中的默认值字符串（default_value）
        5. 将 options 列表序列化为 JSON 字符串（options_json）
        6. 生成详情页展示表达式（vue_display）

        Args:
            field_config (dict): YAML 中单个字段的原始配置字典。

        Returns:
            FieldDefinition: 填充了所有计算属性的字段定义对象。
        """
        field_type = field_config.get('type', 'input')
        type_info = self.TYPE_MAPPING.get(field_type, self.TYPE_MAPPING['input'])

        # 计算 snake_case 列名
        name = field_config.get('name', '')
        column_name = self._to_snake_case(name)

        # Vue 搜索表单类型映射
        vue_filter_type_map = {
            'input': 'input',
            'textarea': 'input',
            'number': 'number',
            'decimal': 'number',
            'date': 'daterange',
            'datetime': 'daterange',
            'date-year': 'year',
            'date-month': 'monthrange',
            'select': 'select',
            'upload': 'input',
        }

        # 默认值
        default_value = 'null'
        if field_config.get('default') is not None:
            default_value = f"'{field_config['default']}'"
        elif field_type == 'number' or field_type == 'date-year' or field_type == 'date-month':
            default_value = 'null'
        elif field_type == 'select':
            default_value = 'null'

        # 选项 JSON
        options_json = '[]'
        if field_config.get('options'):
            import json
            options_json = json.dumps(field_config['options'], ensure_ascii=False)

        # Vue 详情页显示模板
        vue_display = f'{{{{ info.{name} }}}}'
        if field_type == 'select' and field_config.get('options'):
            # 下拉框需要显示文本
            vue_display = f'{{{{ info.{name} }}}}'  # 简化处理，实际项目中需要转换

        field = FieldDefinition(
            name=name,
            label=field_config.get('label', ''),
            type=field_type,
            required=field_config.get('required', False),
            filterable=field_config.get('filterable', False),
            show_in_list=field_config.get('show_in_list', False),
            indexed=field_config.get('filterable', False),  # 可筛选字段建立索引
            generated=field_config.get('generated', False),  # 自动生成字段
            options=field_config.get('options'),
            default=field_config.get('default'),
            placeholder=field_config.get('placeholder'),
            maxlength=field_config.get('maxlength'),
        )

        # 填充类型信息
        field.java_type = type_info['java']
        field.sql_type = type_info['sql']
        field.sql_length = type_info['sql_length']
        field.vue_component = type_info['vue']
        field.mybatis_jdbc_type = type_info['jdbc']
        field.column_name = column_name
        field.name_pascal = self._to_pascal_case(name)
        field.name_camel = self._to_camel_case(name)
        field.default_value = default_value
        field.vue_filter_type = vue_filter_type_map.get(field_type, 'input')
        field.vue_display = vue_display
        field.options_json = options_json

        return field

    def _to_snake_case(self, name: str) -> str:
        """
        将 camelCase 字符串转换为 snake_case 数据库列名。

        使用正则在每个大写字母前插入下划线，再全部转小写。
        示例：'honorName' → 'honor_name'，'activityType' → 'activity_type'

        Args:
            name (str): camelCase 字段名。

        Returns:
            str: snake_case 列名。
        """
        import re
        return re.sub(r'(?<!^)(?=[A-Z])', '_', name).lower()

    def _to_pascal_case(self, name: str) -> str:
        """
        将字符串转换为 PascalCase（支持驼峰、下划线、连字符）。

        示例：
        - 'honor_name' → 'HonorName'
        - 'sample2Talent' → 'Sample2Talent'（驼峰输入保留驼峰）
        - 'masterFk' → 'MasterFk'

        Args:
            name (str): 原始字符串（camelCase / snake_case / kebab-case）。

        Returns:
            str: PascalCase 字符串。
        """
        import re
        # 先统一转为下划线分隔（处理驼峰和连字符）
        s1 = re.sub(r'(.)([A-Z][a-z]+)', r'\1_\2', name)
        s2 = re.sub(r'([a-z0-9])([A-Z])', r'\1_\2', s1)
        parts = s2.replace('-', '_').split('_')
        return ''.join(word[0].upper() + word[1:] if word else '' for word in parts)

    def _to_camel_case(self, name: str) -> str:
        """
        将下划线分隔的字符串转换为 camelCase。

        Args:
            name (str): 下划线分隔的字符串。

        Returns:
            str: camelCase 字符串；空字符串时返回空字符串。
        """
        pascal = self._to_pascal_case(name)
        return pascal[0].lower() + pascal[1:] if pascal else ''

    def build_all(self, fields_config: list[dict]) -> list[FieldDefinition]:
        """
        批量将 YAML 字段配置列表转换为 FieldDefinition 对象列表。

        Args:
            fields_config (list[dict]): YAML 字段配置字典列表。

        Returns:
            list[FieldDefinition]: 字段定义对象列表，顺序与输入一致。
        """
        return [self.build(f) for f in fields_config]

    def build_fields(self, fields_config: list[dict]) -> list[FieldDefinition]:
        """
        build_all() 的语义别名，供外部调用方使用更具表意性的方法名。

        Args:
            fields_config (list[dict]): YAML 字段配置字典列表。

        Returns:
            list[FieldDefinition]: 字段定义对象列表。
        """
        return self.build_all(fields_config)

    def ensure_status_fields(
        self,
        fields: list[FieldDefinition],
        status_toggles: list[dict],
    ) -> list[FieldDefinition]:
        """
        确保 status_toggles 引用的字段存在于字段列表中。

        当 YAML 配置了 status_toggles 但未在 fields 中声明对应字段时，
        自动补充为 select 类型的 Integer 字段，使 DDL / Mapper / VO / Param
        模板能正确渲染这些列。

        PO 模板已有 toggle_fields 排除逻辑，不会重复渲染。

        Args:
            fields: 已构建的字段定义列表（就地修改并返回）。
            status_toggles: enrich 后的 toggle 配置列表，每项含 field/label/values。

        Returns:
            list[FieldDefinition]: 补充了状态字段后的字段列表（与入参同一对象）。
        """
        existing_names = {f.name for f in fields}
        for toggle in status_toggles:
            fname = toggle.get('field', '')
            if not fname or fname in existing_names:
                continue
            # 构造一个 select 类型字段，与 status_toggles 语义一致
            # 将 toggle.values 转为 options 列表（如 [{label: '草稿', value: 0}, ...]）
            toggle_values = toggle.get('values', {})
            options = [
                {'label': v, 'value': int(k) if str(k).isdigit() else k}
                for k, v in toggle_values.items()
            ] if toggle_values else None
            fake_config = {
                'name': fname,
                'label': toggle.get('label', fname),
                'type': 'select',
                'required': False,
                'filterable': False,
                'show_in_list': True,
                'options': options,
            }
            fields.append(self.build(fake_config))
            existing_names.add(fname)
        return fields

    def get_sql_column(self, field: FieldDefinition) -> str:
        """
        根据 FieldDefinition 生成单个 SQL 列定义字符串。

        生成格式：`column_name` TYPE[(length)] [NOT NULL] [DEFAULT value] COMMENT 'label'

        注意：此方法为辅助工具，当前主流程通过 Jinja2 模板直接渲染 SQL，
        不调用此方法；仅在需要动态生成 SQL 片段的扩展场景中使用。

        Args:
            field (FieldDefinition): 字段定义对象。

        Returns:
            str: SQL 列定义字符串（不含尾部逗号）。
        """
        sql = f"`{field.name}` {field.sql_type}"

        if field.sql_length:
            sql += f"({field.sql_length})"

        if field.required:
            sql += " NOT NULL"

        if field.default is not None:
            sql += f" DEFAULT '{field.default}'"

        sql += f" COMMENT '{field.label}'"

        return sql

    def get_java_field(self, field: FieldDefinition) -> str:
        """
        根据 FieldDefinition 生成 Java 字段声明字符串（含 Javadoc 注释和注解）。

        对 date/datetime 类型字段自动添加 @JsonFormat 和 @DateTimeFormat 注解，
        确保前后端日期格式一致（遵循项目后端规范 02-backend.md）。

        注意：同 get_sql_column()，此方法为辅助工具，主流程通过模板渲染。

        Args:
            field (FieldDefinition): 字段定义对象。

        Returns:
            str: Java 字段声明字符串（含缩进）。
        """
        lines = []
        lines.append("    /**")
        lines.append(f"     * {field.label}")
        lines.append("     */")

        # 注解（根据类型）
        if field.type == 'date':
            lines.append('    @JsonFormat(pattern = "yyyy-MM-dd")')
            lines.append('    @DateTimeFormat(pattern = "yyyy-MM-dd")')
        elif field.type == 'datetime':
            lines.append('    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")')
            lines.append('    @DateTimeFormat(pattern = "yyyy-MM-dd HH:mm:ss")')

        # 字段声明
        lines.append(f"    private {field.java_type} {field.name};")

        return '\n'.join(lines)

    def get_vue_form_item(self, field: FieldDefinition) -> str:
        """
        根据字段类型分发到对应的 Vue 表单项生成方法。

        作为分发器（dispatcher），根据 field.type 调用具体的 _vue_xxx() 方法，
        未知类型默认回退到 _vue_input()。

        注意：同 get_sql_column()，此方法为辅助工具，主流程通过模板渲染。

        Args:
            field (FieldDefinition): 字段定义对象。

        Returns:
            str: Vue 表单项 HTML 片段字符串。
        """
        if field.type == 'input':
            return self._vue_input(field)
        elif field.type == 'textarea':
            return self._vue_textarea(field)
        elif field.type == 'number':
            return self._vue_number(field)
        elif field.type == 'decimal':
            return self._vue_decimal(field)
        elif field.type == 'date':
            return self._vue_date(field)
        elif field.type == 'datetime':
            return self._vue_datetime(field)
        elif field.type == 'date-year':
            return self._vue_year(field)
        elif field.type == 'date-month':
            return self._vue_month(field)
        elif field.type == 'select':
            return self._vue_select(field)
        elif field.type == 'upload':
            return self._vue_upload(field)
        else:
            return self._vue_input(field)

    def _vue_input(self, field: FieldDefinition) -> str:
        """生成 el-input 文本输入框表单项，placeholder 优先使用配置值。"""
        ph = field.placeholder or f'请输入{field.label}'
        return f'''      <el-form-item label="{field.label}" prop="{field.name}">
        <el-input v-model="form.{field.name}" placeholder="{ph}" clearable />
      </el-form-item>'''

    def _vue_textarea(self, field: FieldDefinition) -> str:
        """生成 el-input[textarea] 多行文本框表单项，默认行数为 3。"""
        ph = field.placeholder or f'请输入{field.label}'
        return f'''      <el-form-item label="{field.label}" prop="{field.name}">
        <el-input v-model="form.{field.name}" type="textarea" :rows="3" placeholder="{ph}" />
      </el-form-item>'''

    def _vue_number(self, field: FieldDefinition) -> str:
        """生成 el-input-number 整数输入框表单项，最小值为 0，宽度 100%。"""
        return f'''      <el-form-item label="{field.label}" prop="{field.name}">
        <el-input-number v-model="form.{field.name}" :min="0" style="width: 100%" />
      </el-form-item>'''

    def _vue_decimal(self, field: FieldDefinition) -> str:
        """生成 el-input-number 小数输入框表单项，精度 2 位，最小值 0，宽度 100%。"""
        return f'''      <el-form-item label="{field.label}" prop="{field.name}">
        <el-input-number v-model="form.{field.name}" :precision="2" :min="0" style="width: 100%" />
      </el-form-item>'''

    def _vue_date(self, field: FieldDefinition) -> str:
        """生成 el-date-picker 日期选择器表单项，值格式为 YYYY-MM-DD，宽度 100%。"""
        return f'''      <el-form-item label="{field.label}" prop="{field.name}">
        <el-date-picker v-model="form.{field.name}" type="date" value-format="YYYY-MM-DD" style="width: 100%" />
      </el-form-item>'''

    def _vue_datetime(self, field: FieldDefinition) -> str:
        """生成 el-date-picker 日期时间选择器表单项，值格式为 YYYY-MM-DD HH:mm:ss，宽度 100%。"""
        return f'''      <el-form-item label="{field.label}" prop="{field.name}">
        <el-date-picker v-model="form.{field.name}" type="datetime" value-format="YYYY-MM-DD HH:mm:ss" style="width: 100%" />
      </el-form-item>'''

    def _vue_year(self, field: FieldDefinition) -> str:
        """生成 el-date-picker 年份选择器表单项，值格式为 YYYY（对应 Java Integer 类型）。"""
        return f'''      <el-form-item label="{field.label}" prop="{field.name}">
        <el-date-picker v-model="form.{field.name}" type="year" value-format="YYYY" style="width: 100%" />
      </el-form-item>'''

    def _vue_month(self, field: FieldDefinition) -> str:
        """生成 el-date-picker 月份选择器表单项，值格式为 YYYY-MM（对应 Java String / VARCHAR(7)）。"""
        return f'''      <el-form-item label="{field.label}" prop="{field.name}">
        <el-date-picker v-model="form.{field.name}" type="month" value-format="YYYY-MM" style="width: 100%" />
      </el-form-item>'''

    def _vue_select(self, field: FieldDefinition) -> str:
        """生成 el-select 下拉框表单项，根据 field.options 动态渲染选项，宽度 100%。"""
        options_str = ''
        if field.options:
            for opt in field.options:
                options_str += f'\n          <el-option label="{opt["label"]}" :value="{opt["value"]}" />'
        return f'''      <el-form-item label="{field.label}" prop="{field.name}">
        <el-select v-model="form.{field.name}" placeholder="请选择{field.label}" clearable style="width: 100%">{options_str}
        </el-select>
      </el-form-item>'''

    def _vue_upload(self, field: FieldDefinition) -> str:
        """
        生成 el-upload 文件上传表单项。

        上传成功后将响应中的 url 字段赋值给对应表单字段，
        遵循项目上传规范（07-upload.md）：后端返回完整 MinIO URL。
        """
        return f'''      <el-form-item label="{field.label}" prop="{field.name}">
        <el-upload :action="uploadUrl" :on-success="(res) => form.{field.name} = res.url">
          <el-button type="primary">点击上传</el-button>
        </el-upload>
      </el-form-item>'''
