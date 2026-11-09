#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# =============================================================================
# Libra Boot Low 代码生成器 — 统一入口（索引 + 生成 + 报告）
#
# 【设计思路】
# 本工具整合三大功能：
#   1. 索引更新 → 自动扫描 config/ 目录，更新 config/index.json
#   2. 代码生成 → 根据 YAML 配置 + Jinja2 模板生成后端/前端代码
#   3. 报告输出 → 生成运行报告到 output/gen_{timestamp}.log
#
# 【支持的生成模式（10 种）】
#   - single                            : 单表（无附件），标准 6 接口
#   - single-with-file                  : 单表 + 附件从表（1:N），9 接口
#   - master-detail                     : 主表 + 明细从表（1:N，无附件），主6 + 明细6 接口
#   - master-detail-with-file           : 主表 + 明细从表 + 明细附件从表，主6 + 明细9 接口
#   - master-detail-modules             : 主表 + N 个明细从表（无附件），主6 + 明细6×N 接口
#   - master-detail-modules-with-file   : 主表 + N 个明细从表，各自可选附件，主6 + 明细6/9×N 接口
#   - master-details-tabs               : 主表（无新增）+ N 明细（Tab 内嵌，无附件），主6 + 明细6×N
#   - master-details-tabs-with-file     : 主表（无新增）+ N 明细（Tab 内嵌，各自可选附件）
#   - multi-table                       : 多平级子表（无 FK，各自独立 CRUD），6×N 接口
#   - multi-table-with-file             : 多平级子表，每张表含附件从表，9×N 接口
#
# 【用法】
#   python generator.py <config.yml> [output_dir]
#   python generator.py --update-index                    # 仅更新索引
#   python generator.py config/test/t1000.yml             # 生成指定模块
#
# 【报告输出】
#   output/gen_{timestamp}.txt  (生成报告)
#   output/log_{timestamp}.txt  (控制台日志)
# =============================================================================
import os
import sys
import yaml
import json
import argparse
from pathlib import Path
from datetime import datetime

# =============================================================================
# 路径常量定义
# =============================================================================
SCRIPT_DIR = Path(__file__).parent.resolve()
CONFIG_DIR = SCRIPT_DIR / 'config'
TEMPLATE_DIR = SCRIPT_DIR / 'templates'
OUTPUT_DIR = SCRIPT_DIR / 'output'

# 添加 lib 到路径
sys.path.insert(0, str(SCRIPT_DIR))

from module.config_loader import ConfigLoader
from module.field_builder import FieldBuilder
from module.template_renderer import TemplateRenderer
from module import template_renderer as _tr

# 导入各模式生成器
from module.gen_single import generate as gen_single
from module.gen_single_with_file import generate as gen_single_with_file
from module.gen_master_detail import generate as gen_master_detail
from module.gen_master_detail_file import generate as gen_master_detail_file
from module.gen_master_detail_modules import generate as gen_master_detail_modules
from module.gen_master_detail_modules_file import generate as gen_master_detail_modules_file
from module.gen_master_details_tabs import generate as gen_master_details_tabs
from module.gen_master_details_tabs_file import generate as gen_master_details_tabs_file
from module.gen_master_details_tabs_dialog import generate as gen_master_details_tabs_dialog
from module.gen_master_details_tabs_dialog_file import generate as gen_master_details_tabs_dialog_file
from module.gen_multi_table import generate as gen_multi_table
from module.gen_multi_table_with_file import generate as gen_multi_table_with_file


# =============================================================================
# 模式映射表 — 将 mode 字符串映射到对应的生成函数
# =============================================================================
MODE_GENERATORS = {
    'single': gen_single,
    'single-with-file': gen_single_with_file,
    'master-detail': gen_master_detail,
    'master-detail-with-file': gen_master_detail_file,
    'master-detail-modules': gen_master_detail_modules,
    'master-detail-modules-with-file': gen_master_detail_modules_file,
    'master-details-tabs': gen_master_details_tabs,
    'master-details-tabs-with-file': gen_master_details_tabs_file,
    'master-details-tabs-dialog': gen_master_details_tabs_dialog,
    'master-details-tabs-dialog-with-file': gen_master_details_tabs_dialog_file,
    'multi-table': gen_multi_table,
    'multi-table-with-file': gen_multi_table_with_file,
}

# 模式分组（用于确定参数名称）
SINGLE_MODES = ['single', 'single-with-file']
MASTER_DETAIL_MODES = ['master-detail', 'master-detail-with-file', 'master-detail-modules', 'master-detail-modules-with-file', 'master-details-tabs', 'master-details-tabs-with-file', 'master-details-tabs-dialog', 'master-details-tabs-dialog-with-file']
MULTI_TABLE_MODES = ['multi-table', 'multi-table-with-file']


class ConfigIndexer:
    """
    配置索引器。

    扫描 config/ 目录下所有 YAML 配置文件，生成 index.json 索引。

    Attributes:
        config_dir (Path): 配置目录路径

    Example:
        >>> indexer = ConfigIndexer()
        >>> indexer.generate_index()
    """

    def __init__(self, config_dir=None):
        """
        初始化索引器。

        Args:
            config_dir: 配置目录路径（默认为 script/config/）
        """
        if config_dir is None:
            self.config_dir = CONFIG_DIR
        else:
            self.config_dir = Path(config_dir)

    def scan_configs(self):
        """
        扫描所有 YAML 配置文件。

        Returns:
            list: 配置信息列表
        """
        configs = []

        # 遍历所有域目录
        for domain_dir in sorted(self.config_dir.iterdir()):
            if not domain_dir.is_dir() or domain_dir.name.startswith('.'):
                continue

            domain = domain_dir.name

            # 遍历该域下的所有 YAML 文件
            for yml_file in sorted(domain_dir.glob('*.yml')):
                config_info = self._parse_config(yml_file, domain)
                if config_info:
                    configs.append(config_info)

        return configs

    def _parse_config(self, yml_file, domain):
        """
        解析单个配置文件。

        Args:
            yml_file: YAML 文件路径
            domain: 业务域代码

        Returns:
            dict: 配置信息字典
        """
        try:
            with open(yml_file, 'r', encoding='utf-8') as f:
                data = yaml.safe_load(f)

            # 提取模块信息
            modules = data.get('modules', [])
            if not modules:
                return None

            module = modules[0]  # 取第一个模块
            mode = module.get('mode', 'single')
            code = module.get('code', '')
            name = module.get('name', '')
            description = module.get('description', '')
            fields = module.get('fields', [])

            # 构建配置信息
            config_info = {
                'file': str(yml_file.relative_to(self.config_dir)),
                'mode': mode,
                'domain': domain,
                'code': code,
                'name': name,
                'description': description,
                'field_count': len(fields),
                'last_modified': datetime.fromtimestamp(yml_file.stat().st_mtime).isoformat()
            }

            # 根据 mode 添加额外信息
            if mode in ['master-detail', 'master-detail-with-file']:
                config_info['has_master'] = 'master' in module
                config_info['has_detail'] = 'detail' in module
                if config_info['has_master']:
                    config_info['master_code'] = module.get('master', {}).get('code', '')
                if config_info['has_detail']:
                    config_info['detail_code'] = module.get('detail', {}).get('code', '')

            elif mode in ['master-detail-modules', 'master-detail-modules-with-file']:
                config_info['has_master'] = 'master' in module
                detail_modules = module.get('detail_modules', []) or []
                config_info['detail_module_count'] = len(detail_modules)
                config_info['detail_module_codes'] = [dm.get('code', '') for dm in detail_modules]
                if config_info['has_master']:
                    config_info['master_code'] = module.get('master', {}).get('code', '')

            elif mode in ['multi-table', 'multi-table-with-file']:
                sub_tables = module.get('sub_tables', [])
                config_info['sub_table_count'] = len(sub_tables)
                config_info['sub_table_codes'] = [st.get('code', '') for st in sub_tables]

            return config_info

        except Exception as e:
            print(f"⚠️  解析失败 {yml_file}: {e}")
            return None

    def generate_index(self, output_file=None):
        """
        生成索引文件。

        Args:
            output_file: 输出文件路径（默认为 config/index.json）

        Returns:
            dict: 索引数据
        """
        if output_file is None:
            output_file = self.config_dir / 'index.json'

        # 扫描所有配置
        print(f"正在扫描 {self.config_dir}...")
        configs = self.scan_configs()

        # 构建索引数据
        index_data = {
            'last_updated': datetime.now().isoformat(),
            'total_configs': len(configs),
            'domains': {},
            'configs': configs
        }

        # 按域分组统计
        for config in configs:
            domain = config['domain']
            if domain not in index_data['domains']:
                index_data['domains'][domain] = {
                    'domain': domain,
                    'count': 0,
                    'modules': []
                }
            index_data['domains'][domain]['count'] += 1
            index_data['domains'][domain]['modules'].append({
                'code': config['code'],
                'name': config['name'],
                'mode': config['mode']
            })

        # 写入 JSON 文件
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(index_data, f, ensure_ascii=False, indent=2)

        print(f"\n✅ 发现 {len(configs)} 个配置文件:")
        for config in configs:
            print(f"   - {config['file']}")
            print(f"     └─ 模式: {config['mode']} | {config['domain']}/{config['code']} - {config['name']}")

        print(f"\n✅ 索引已生成: {output_file}")

        return index_data


class ReportWriter:
    """
    报告写入器。

    将生成结果拆分为两个文件：
    - gen_{timestamp}.txt: 生成报告（结构化的生成结果）
    - log_{timestamp}.txt: 控制台输出（运行时日志）

    Attributes:
        report_dir (Path): 报告输出目录
        report_file (Path): 生成报告文件路径 (gen_*.txt)
        log_file (Path): 控制台日志文件路径 (log_*.txt)
        start_time (datetime): 开始时间
        records (list): 生成记录列表
        log_lines (list): 控制台日志行列表

    Example:
        >>> report = ReportWriter()
        >>> with report.capture():
        ...     print("正在处理模块 simple...")
        >>> report.add_record('simple', True, '生成成功')
        >>> report.write()
    """

    class _Tee:
        """同时输出到控制台和日志列表的 Tee 类。"""
        def __init__(self, log_lines, original_stdout):
            self.log_lines = log_lines
            self.original_stdout = original_stdout

        def write(self, message):
            # 输出到控制台
            self.original_stdout.write(message)
            # 同时捕获到日志列表（去除空行）
            stripped = message.rstrip('\n\r')
            if stripped:
                timestamp = datetime.now().strftime('%H:%M:%S')
                self.log_lines.append(f"[{timestamp}] {stripped}")

        def flush(self):
            self.original_stdout.flush()

    def __init__(self, output_dir=None, batch_timestamp=None, dry_run=False):
        """
        初始化报告写入器。

        Args:
            output_dir: 输出目录（默认为 script/output/）
            batch_timestamp: 批量模式时间戳（用于多个模块共享同一日志文件）
            dry_run: 预览模式——不创建目录、不写任何文件
        """
        self.dry_run = dry_run
        if output_dir is None:
            self.report_dir = OUTPUT_DIR
        else:
            self.report_dir = Path(output_dir)

        if not dry_run:
            self.report_dir.mkdir(parents=True, exist_ok=True)

        # 批量模式使用共享时间戳，否则生成新的
        if batch_timestamp:
            self.timestamp = batch_timestamp
        else:
            self.timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')

        # 拆分为两个文件：生成报告 + 控制台日志
        self.report_file = self.report_dir / f'gen_{self.timestamp}.txt'
        self.log_file = self.report_dir / f'log_{self.timestamp}.txt'
        self.start_time = datetime.now()
        self.records = []
        self.log_lines = []  # 控制台日志行

        # stdout 捕获状态
        self._original_stdout = None
        self._tee = None

        # 标记是否为批量模式（追加而非覆盖）
        self.is_batch_mode = batch_timestamp is not None

    def capture_start(self):
        """开始捕获 stdout。"""
        import sys
        self._original_stdout = sys.stdout
        self._tee = self._Tee(self.log_lines, self._original_stdout)
        sys.stdout = self._tee

    def capture_end(self):
        """停止捕获 stdout。"""
        import sys
        if self._original_stdout:
            sys.stdout = self._original_stdout
            self._original_stdout = None
            self._tee = None

    def capture(self):
        """返回一个 context manager 用于捕获 stdout。"""
        return self._CaptureContext(self)

    class _CaptureContext:
        """stdout 捕获的 context manager。"""
        def __init__(self, report_writer):
            self.report_writer = report_writer

        def __enter__(self):
            self.report_writer.capture_start()
            return self

        def __exit__(self, exc_type, exc_val, exc_tb):
            self.report_writer.capture_end()
            return False

    def add_record(self, module_code: str, success: bool, message: str, config_file: str = ''):
        """
        添加生成记录。

        Args:
            module_code: 模块代码
            success: 是否成功
            message: 消息内容
            config_file: 配置文件路径
        """
        self.records.append({
            'module': module_code,
            'success': success,
            'message': message,
            'config': config_file,
            'time': datetime.now().isoformat()
        })

    def log(self, message: str):
        """
        添加控制台日志行。

        Args:
            message: 日志消息
        """
        timestamp = datetime.now().strftime('%H:%M:%S')
        self.log_lines.append(f"[{timestamp}] {message}")

    def write(self, project_info: dict = None, summary: dict = None, is_final: bool = True):
        """
        写入报告文件和日志文件。

        Args:
            project_info: 项目信息
            summary: 汇总信息 {'total': N, 'success': N, 'failed': N}
            is_final: 是否为最后一次写入（批量模式下控制是否写入汇总）
        """
        end_time = datetime.now()
        duration = (end_time - self.start_time).total_seconds()

        # 批量模式：追加记录，非批量模式：完整报告
        if self.is_batch_mode:
            self._write_batch_record(project_info, summary)
        else:
            self._write_full_report(end_time, duration, project_info, summary)

        # 写入控制台日志文件
        self._write_log_file(end_time, duration)

    def _write_log_file(self, end_time, duration):
        """
        写入控制台日志文件 (log_{timestamp}.txt)。
        批量模式下使用追加模式，非批量模式使用覆盖模式。

        Args:
            end_time: 结束时间
            duration: 运行时长
        """
        if self.is_batch_mode:
            # 批量模式：追加日志
            self._write_batch_log(end_time, duration)
        else:
            # 非批量模式：完整日志（覆盖）
            self._write_full_log(end_time, duration)

    def _write_batch_log(self, end_time, duration):
        """
        批量模式：追加日志到文件。

        Args:
            end_time: 结束时间
            duration: 运行时长
        """
        # 如果文件不存在，先写入头部（使用追加模式）
        if not self.log_file.exists():
            header = []
            header.append("=" * 60)
            header.append("Libra Boot Low 代码生成器 - 批量生成日志")
            header.append("=" * 60)
            header.append("")
            header.append(f"批量开始时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
            header.append(f"日志文件: {self.log_file}")
            header.append("")
            header.append("-" * 40)
            header.append("运行日志")
            header.append("-" * 40)
            with open(self.log_file, 'a', encoding='utf-8') as f:
                f.write('\n'.join(header) + '\n')

        # 追加当前模块日志（使用追加模式）
        with open(self.log_file, 'a', encoding='utf-8') as f:
            if self.log_lines:
                for line in self.log_lines:
                    f.write(f"{line}\n")
            f.write("")  # 空行分隔

        print(f"📋 控制台日志: {self.log_file}")

    def _write_full_log(self, end_time, duration):
        """
        非批量模式：写入完整日志（覆盖）。

        Args:
            end_time: 结束时间
            duration: 运行时长
        """
        lines = []
        lines.append("=" * 60)
        lines.append("Libra Boot Low 代码生成器 - 控制台日志")
        lines.append("=" * 60)
        lines.append("")
        lines.append(f"开始时间: {self.start_time.strftime('%Y-%m-%d %H:%M:%S')}")
        lines.append(f"结束时间: {end_time.strftime('%Y-%m-%d %H:%M:%S')}")
        lines.append(f"运行时长: {duration:.2f} 秒")
        lines.append(f"日志文件: {self.log_file}")
        lines.append("")
        lines.append("-" * 40)
        lines.append("运行日志")
        lines.append("-" * 40)

        if self.log_lines:
            for line in self.log_lines:
                lines.append(line)
        else:
            lines.append("(无运行日志)")

        lines.append("")
        lines.append("=" * 60)
        lines.append("日志结束")
        lines.append("=" * 60)

        with open(self.log_file, 'w', encoding='utf-8') as f:
            f.write('\n'.join(lines))

        print(f"📋 控制台日志: {self.log_file}")

    def _write_batch_record(self, project_info: dict = None, summary: dict = None):
        """
        批量模式：追加单条记录到日志文件。

        Args:
            project_info: 项目信息
            summary: 汇总信息（仅最后一个模块时使用）
        """
        # 如果文件不存在，先写入头部
        if not self.report_file.exists():
            header = []
            header.append("=" * 60)
            header.append("Libra Boot Low 代码生成器 - 批量生成报告")
            header.append("=" * 60)
            header.append("")
            header.append(f"批量开始时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
            header.append(f"报告文件: {self.report_file}")
            header.append("")
            header.append("-" * 40)
            header.append("生成记录")
            header.append("-" * 40)
            with open(self.report_file, 'w', encoding='utf-8') as f:
                f.write('\n'.join(header) + '\n')

        # 追加当前模块记录
        with open(self.report_file, 'a', encoding='utf-8') as f:
            for record in self.records:
                status = "✅ 成功" if record['success'] else "❌ 失败"
                f.write(f"  [{status}] {record['module']}\n")
                if record['config']:
                    f.write(f"           配置: {record['config']}\n")
                f.write(f"           消息: {record['message']}\n")
                f.write(f"           时间: {record['time']}\n\n")

        print(f"  📄 记录已追加: {self.report_file}")

    def _write_full_report(self, end_time, duration, project_info: dict = None, summary: dict = None):
        """
        非批量模式：写入完整报告。

        Args:
            end_time: 结束时间
            duration: 运行时长
            project_info: 项目信息
            summary: 汇总信息
        """
        lines = []
        lines.append("=" * 60)
        lines.append("Libra Boot Low 代码生成器 - 运行报告")
        lines.append("=" * 60)
        lines.append("")
        lines.append(f"开始时间: {self.start_time.strftime('%Y-%m-%d %H:%M:%S')}")
        lines.append(f"结束时间: {end_time.strftime('%Y-%m-%d %H:%M:%S')}")
        lines.append(f"运行时长: {duration:.2f} 秒")
        lines.append(f"报告文件: {self.report_file}")
        lines.append("")

        if project_info:
            lines.append("-" * 40)
            lines.append("项目信息")
            lines.append("-" * 40)
            lines.append(f"  名称: {project_info.get('name', 'Unknown')}")
            lines.append(f"  代码: {project_info.get('code', 'Unknown')}")
            lines.append(f"  版本: {project_info.get('version', 'Unknown')}")
            lines.append("")

        if summary:
            lines.append("-" * 40)
            lines.append("生成汇总")
            lines.append("-" * 40)
            lines.append(f"  总计: {summary.get('total', 0)}")
            lines.append(f"  成功: {summary.get('success', 0)}")
            lines.append(f"  失败: {summary.get('failed', 0)}")
            lines.append("")

        if self.records:
            lines.append("-" * 40)
            lines.append("生成记录")
            lines.append("-" * 40)
            for record in self.records:
                status = "✅ 成功" if record['success'] else "❌ 失败"
                lines.append(f"  [{status}] {record['module']}")
                if record['config']:
                    lines.append(f"           配置: {record['config']}")
                lines.append(f"           消息: {record['message']}")
                lines.append("")

        lines.append("=" * 60)
        lines.append("报告结束")
        lines.append("=" * 60)

        with open(self.report_file, 'w', encoding='utf-8') as f:
            f.write('\n'.join(lines))

        print(f"\n📄 生成报告: {self.report_file}")


class Generator:
    """
    代码生成器入口路由器。

    负责协调 ConfigLoader、FieldBuilder 和各模式生成模块，
    根据 mode 参数路由到对应的 module/gen_*.py 模块执行生成逻辑。

    Attributes:
        config_path (str): 配置文件路径
        output_dir (Path): 输出目录路径
        script_dir (Path): 脚本所在目录
        template_dir (Path): 模板目录路径
        config_loader (ConfigLoader): 配置加载器实例
        field_builder (FieldBuilder): 字段构建器实例
        config (dict): 加载后的配置数据
        project_info (dict): 项目信息字典
        report (ReportWriter): 报告写入器实例

    Example:
        >>> generator = Generator('config/test/t1000.yml', '../../out')
        >>> generator.validate()
        True
        >>> generator.generate()
    """

    def __init__(self, config_path: str, output_dir: str, batch_timestamp: str = None, dry_run: bool = False):
        """
        初始化代码生成器。

        Args:
            config_path (str): YAML 配置文件的路径
            output_dir (str): 生成代码的输出目录路径
            batch_timestamp (str, optional): 批量模式时间戳（用于共享日志文件）
        """
        self.dry_run = dry_run
        self.config_path = config_path
        self.output_dir = Path(output_dir)
        self.batch_timestamp = batch_timestamp
        # 使用模块级常量
        self.script_dir = SCRIPT_DIR
        self.template_dir = TEMPLATE_DIR

        self.config_loader = ConfigLoader(config_path)
        self.field_builder = FieldBuilder()

        self.config = self.config_loader.load()
        self.project_info = self.config_loader.get_project_info()

        # 初始化报告写入器（批量模式下共享时间戳）
        self.report = ReportWriter(batch_timestamp=batch_timestamp, dry_run=dry_run)

    def validate(self) -> bool:
        """
        验证配置文件的合法性。

        调用 ConfigLoader 的 validate 方法检查配置文件的结构和内容，
        包括必需字段、字段类型、枚举值等。

        Returns:
            bool: 验证通过返回 True，否则返回 False
        """
        valid, errors = self.config_loader.validate()
        if not valid:
            print("❌ 配置验证失败:")
            for error in errors:
                print(f"   - {error}")
            return False
        print("✅ 配置验证通过")
        return True

    def list_modules(self):
        """
        列出配置文件中定义的所有模块。

        以表格形式输出模块索引、名称、代码和生成模式。
        """
        print(f"\n📋 配置文件: {self.config_path}")
        print(f"📦 项目: {self.project_info.get('name', 'Unknown')}\n")
        print("模块列表:")
        for i, module in enumerate(self.config_loader.get_modules(), 1):
            mode = module.get('mode', 'single')
            print(f"  {i}. {module.get('name')} ({module.get('code')}) [{mode}]")

    def generate(self, module_code: str = None, mode_override: str = None):
        """
        生成代码的主入口方法。

        遍历配置文件中的所有模块，根据 module_code 过滤（可选），
        调用对应的生成器函数生成代码，最后写入清单文件和报告。

        Args:
            module_code (str, optional): 仅生成指定 code 的模块。
            mode_override (str, optional): 覆盖 YAML 配置中的生成模式。
        """
        modules = self.config_loader.get_modules()
        generated = []
        failed = []

        # DRY-RUN：通知渲染器只预览不落盘
        _tr.DRY_RUN = self.dry_run

        # 开始捕获 stdout（所有 print 输出）
        self.report.capture_start()

        try:
            for module in modules:
                if module_code and module.get('code') != module_code:
                    continue

                if mode_override:
                    module = dict(module)
                    module['mode'] = mode_override

                try:
                    self._generate_module(module)
                    generated.append(module.get('code'))
                    self.report.add_record(
                        module.get('code'),
                        True,
                        f"生成成功 - {module.get('name')}",
                        self.config_path
                    )
                except Exception as e:
                    failed.append(module.get('code'))
                    self.report.add_record(
                        module.get('code'),
                        False,
                        f"生成失败: {str(e)}",
                        self.config_path
                    )
                    print(f"❌ 模块 '{module.get('name')}' 生成失败: {e}")
                    import traceback
                    traceback.print_exc()

            if self.dry_run:
                print("\n👁 [DRY-RUN] 预览模式：未写入任何文件（含清单）")
            else:
                self._write_manifest(generated)

        finally:
            # 停止捕获 stdout（无论成功或失败都要执行）
            self.report.capture_end()

        # 写入报告（此时 stdout 已恢复正常；DRY-RUN 只回放不落盘）
        if not self.dry_run:
            self.report.write(
                project_info=self.project_info,
                summary={
                    'total': len(generated) + len(failed),
                    'success': len(generated),
                    'failed': len(failed)
                }
            )

        print(f"\n{'=' * 60}")
        print(f"✅ 生成完成!")
        print(f"📦 共生成 {len(generated)} 个模块: {', '.join(generated)}")
        if failed:
            print(f"❌ 失败 {len(failed)} 个模块: {', '.join(failed)}")
        print(f"📂 输出目录: {self.output_dir.absolute()}")
        print(f"📄 清单文件: {self.output_dir / '.manifest.json'}")
        print(f"{'=' * 60}")

    def _generate_module(self, module: dict):
        """
        根据 mode 路由到对应的生成器模块。

        Args:
            module (dict): 模块配置字典

        Raises:
            ValueError: 当 mode 不在支持的模式列表中时抛出
        """
        mode = module.get('mode', 'single')

        # 检查 mode 是否支持
        if mode not in MODE_GENERATORS:
            raise ValueError(f"不支持的生成模式: {mode}")

        # 获取对应的生成函数
        generator_func = MODE_GENERATORS[mode]

        # 根据模式类型使用不同的参数名
        if mode in SINGLE_MODES:
            generator_func(
                config_loader=self.config_loader,
                field_builder=self.field_builder,
                renderer_class=TemplateRenderer,
                template_dir=self.template_dir,
                output_dir=self.output_dir,
                project_info=self.project_info,
                module=module,
            )
        else:
            generator_func(
                config_loader=self.config_loader,
                field_builder=self.field_builder,
                renderer_class=TemplateRenderer,
                template_dir=self.template_dir,
                output_dir=self.output_dir,
                project_info=self.project_info,
                group_module=module,
            )

    def _write_manifest(self, generated: list):
        """
        写入清单文件。

        Args:
            generated (list): 已成功生成的模块 code 列表
        """
        manifest = {
            'generated_at': datetime.now().isoformat(),
            'config_file': str(self.config_path),
            'project': self.project_info,
            'modules': generated,
            'total': len(generated),
        }

        manifest_path = self.output_dir / '.manifest.json'
        self.output_dir.mkdir(parents=True, exist_ok=True)

        with open(manifest_path, 'w', encoding='utf-8') as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)


def main():
    """
    CLI 入口函数。

    命令行参数:
        config: 配置文件路径（必需）
        output: 输出目录（可选，默认 ../../out）
        --update-index: 仅更新配置索引
        --module, -m: 仅生成指定模块
        --mode: 覆盖 YAML 中的生成模式
        --validate, -v: 仅验证配置文件
        --list, -l: 列出配置中的所有模块
        --batch-timestamp: 批量模式时间戳（用于多个模块共享同一日志文件）
    """
    parser = argparse.ArgumentParser(
        description='Libra Boot Low 项目级代码生成器（索引 + 生成 + 报告）',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  %(prog)s --update-index                                  # 更新配置索引
  %(prog)s config/test/t1000.yml                           # 生成指定模块
  %(prog)s config/test/t1000.yml --mode single-with-file   # 覆盖生成模式
  %(prog)s my-config.yml --validate                        # 仅验证配置
  %(prog)s my-config.yml --list                            # 列出模块
  %(prog)s config/test/t1000.yml --batch-timestamp 20260101_120000  # 批量模式
        """
    )

    parser.add_argument('config', nargs='?', help='配置文件路径 (YAML)')
    parser.add_argument('output', nargs='?', default='../../out', help='输出目录')
    parser.add_argument('--update-index', '-u', action='store_true', help='更新配置索引')
    parser.add_argument('--module', '-m', help='仅生成指定模块')
    parser.add_argument('--mode', help='覆盖 YAML 中的生成模式')
    parser.add_argument('--validate', '-v', action='store_true', help='仅验证配置文件')
    parser.add_argument('--list', '-l', action='store_true', help='列出配置中的所有模块')
    parser.add_argument('--batch-timestamp', help='批量模式时间戳（共享日志文件）')
    parser.add_argument('--version', action='version', version='%(prog)s 1.3.1', help='显示版本号并退出')
    parser.add_argument('--list-modes', action='store_true', help='列出全部支持的生成模式')
    parser.add_argument('--dry-run', action='store_true', help='仅预览将生成的文件列表，不写入磁盘')

    args = parser.parse_args()
    if args.list_modes:
        print("支持的生成模式：")
        print("  single                          单表 CRUD")
        print("  single-with-file                单表 + 附件上传")
        print("  multi-table                     多表关联")
        print("  multi-table-with-file           多表 + 附件")
        print("  master-detail                   主从表（一对多）")
        print("  master-detail-with-file         主从表 + 附件")
        print("  master-detail-modules           主从表（模块化）")
        print("  master-detail-modules-with-file 主从表模块化 + 附件")
        print("  master-details-tabs             主多明细（页签）")
        print("  master-details-tabs-with-file   主多明细页签 + 附件")
        print("  master-details-tabs-dialog      主多明细（页签弹窗）")
        print("  master-details-tabs-dialog-with-file  主多明细页签弹窗 + 附件")
        return


    # 仅更新索引
    if args.update_index:
        indexer = ConfigIndexer()
        indexer.generate_index()
        sys.exit(0)

    # 必须提供配置文件
    if not args.config:
        parser.print_help()
        sys.exit(1)

    if not os.path.exists(args.config):
        print(f"❌ 配置文件不存在: {args.config}")
        sys.exit(1)

    generator = Generator(args.config, args.output, batch_timestamp=args.batch_timestamp, dry_run=args.dry_run)

    if args.validate:
        success = generator.validate()
        sys.exit(0 if success else 1)

    if args.list:
        generator.list_modules()
        sys.exit(0)

    if not generator.validate():
        sys.exit(1)

    generator.generate(args.module, args.mode)



if __name__ == '__main__':
    main()
