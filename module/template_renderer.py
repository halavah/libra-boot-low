# -*- coding: utf-8 -*-
# =============================================================================
# template_renderer.py — Jinja2 模板渲染引擎
#
# 【职责】
# 将业务模块上下文（module/fields/project 字典）注入到 Jinja2 模板文件中，
# 生成最终的代码文件，并将其写入指定的输出目录。
#
# 【核心设计决策】
# 1. StrictUndefined 模式
#    Jinja2 默认对未定义变量输出空字符串，很难发现模板 Bug。
#    本引擎强制使用 StrictUndefined，访问未定义变量直接抛出异常，
#    强迫开发者在模板中明确所有变量引用。
#
# 2. 文件名占位符替换（compute_output_path）
#    模板文件名使用 {{Domain}}/{{Module}} 占位符（如
#    "BizDomainModule.java.j2"），渲染时通过字符串替换转换为实际类名
#    （如 "BizDemoBasic.java"），使同一套模板可复用于所有模块。
#
# 3. 自定义 Jinja2 过滤器
#    注册了 camel/pascal/snake_to_camel/snake_to_pascal/date/year 过滤器，
#    模板内可直接用 {{ name | pascal }} 做字符串转换，无需在上下文中
#    预先计算所有派生字段。
#
# 4. trim_blocks + lstrip_blocks
#    开启这两个选项后，Jinja2 会自动去除控制块（{% %}）所在行的换行符
#    和行首空白，避免生成代码中出现多余的空行。
#
# 【依赖】
#   外部: jinja2（pip install jinja2）
# =============================================================================

import os
import shutil
from datetime import datetime
from pathlib import Path

try:
    from jinja2 import Environment, FileSystemLoader, StrictUndefined
except ImportError:
    print("Error: Jinja2 is required. Install with: pip install jinja2")
    exit(1)


# DRY-RUN 全局旗标：True 时只打印将写入的文件路径，不落盘（由 Generator 按需开启）
DRY_RUN = False


class TemplateRenderer:
    """
    Jinja2 模板渲染器。

    封装 Jinja2 Environment 的创建与配置，提供模板渲染、
    文件写入和批量渲染的统一接口。

    每个实例绑定一个模板目录（对应一种生成模式，如 templates/single/），
    生成不同模式的代码时应创建不同的实例。

    Attributes:
        template_dir (Path): 模板根目录路径。
        env (Environment): 已配置自定义过滤器的 Jinja2 环境对象。
    """

    def __init__(self, template_dir: str):
        """
        初始化渲染器，创建并配置 Jinja2 Environment。

        配置要点：
        - FileSystemLoader：从文件系统加载模板，支持相对路径引用
        - StrictUndefined：访问未定义变量时立即抛出异常（见模块注释）
        - trim_blocks=True：去除控制块后的换行符
        - lstrip_blocks=True：去除控制块所在行的行首空白
        - keep_trailing_newline=True：保留文件末尾换行（符合 POSIX 规范）

        Args:
            template_dir (str): 模板根目录路径（绝对或相对路径）。
        """
        self.template_dir = Path(template_dir)
        self.env = Environment(
            loader=FileSystemLoader(str(self.template_dir)),
            undefined=StrictUndefined,  # 严格模式，未定义变量报错
            trim_blocks=True,
            lstrip_blocks=True,
            keep_trailing_newline=True,
        )

        # 注册自定义过滤器
        self._register_filters()

    def _register_filters(self):
        """
        向 Jinja2 Environment 注册项目专用的自定义过滤器。

        注册的过滤器列表：
        - camel        : 将字符串首字母小写（如 'HonorName' → 'honorName'）
        - pascal       : 将字符串首字母大写（如 'honorName' → 'HonorName'）
        - snake_to_camel  : 下划线转 camelCase（如 'honor_name' → 'honorName'）
        - snake_to_pascal : 下划线转 PascalCase（如 'honor_name' → 'HonorName'）
        - date         : 返回当前日期字符串（忽略输入值）
        - year         : 返回当前年份字符串（忽略输入值）
        """

        # 首字母小写
        self.env.filters["camel"] = lambda s: s[0].lower() + s[1:] if s else ""

        # 首字母大写
        self.env.filters["pascal"] = lambda s: s[0].upper() + s[1:] if s else ""

        # 下划线转驼峰
        def snake_to_camel(s):
            parts = s.split("_")
            return parts[0] + "".join(word.capitalize() for word in parts[1:])

        self.env.filters["snake_to_camel"] = snake_to_camel

        # 下划线转帕斯卡
        def snake_to_pascal(s):
            return "".join(word.capitalize() for word in s.split("_"))

        self.env.filters["snake_to_pascal"] = snake_to_pascal

        # 日期格式化
        self.env.filters["date"] = lambda _: datetime.now().strftime("%Y-%m-%d")

        # 年份
        self.env.filters["year"] = lambda _: datetime.now().strftime("%Y")

        # 字符串分割
        self.env.filters["split"] = lambda s, sep=".": s.split(sep) if s else []

        # 字符串替换（支持链式调用）
        self.env.filters["replace"] = lambda s, old, new="": (
            s.replace(old, new) if s else s
        )

    def render(self, template_path: str, context: dict) -> str:
        """
        渲染单个模板文件，返回渲染后的字符串。

        内部调用 Jinja2 的 env.get_template() + template.render()，
        模板中所有 {{ var }} 和 {% block %} 会被替换为上下文中的实际值。

        Args:
            template_path (str): 相对于 template_dir 的模板文件路径。
            context (dict): 模板上下文字典（通常包含 module/fields/project 等）。

        Returns:
            str: 渲染后的代码字符串。

        Raises:
            jinja2.UndefinedError: 模板中引用了上下文中不存在的变量时抛出（StrictUndefined）。
        """
        template = self.env.get_template(template_path)
        return template.render(**context)

    def render_to_file(
        self, template_path: str, output_path: str, context: dict
    ) -> str:
        """
        渲染模板并将结果写入文件。

        自动创建输出文件所在的父目录（mkdir -p 语义），
        如果父目录已存在则静默跳过。文件以 UTF-8 编码写入，
        覆盖已有文件。

        Args:
            template_path (str): 模板文件的相对路径（相对于 template_dir）。
            output_path (str): 输出文件的绝对路径。
            context (dict): 模板上下文字典。

        Returns:
            str: 输出文件的绝对路径字符串。
        """
        content = self.render(template_path, context)

        if DRY_RUN:
            print(f"  👁 [DRY-RUN] {output_path}")
            return output_path

        # 确保目录存在
        Path(output_path).parent.mkdir(parents=True, exist_ok=True)

        # 写入文件
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(content)

        return output_path

    def get_template_files(self, subdir: str = "") -> list[str]:
        """
        递归扫描模板目录，返回所有 Jinja2 模板文件的相对路径列表。

        只收集扩展名为 .j2 / .jinja2 / .jinja 的文件，忽略其他文件。
        路径相对于 self.template_dir，格式与 env.get_template() 接受的
        格式一致，可直接传入 render() 方法。

        Args:
            subdir (str): 在 template_dir 内进一步限定的子目录名。
                          为空字符串时扫描整个 template_dir。

        Returns:
            list[str]: 模板文件相对路径列表（如 '04-server/entity/po/BizDomainModule.java.j2'）。
        """
        search_dir = self.template_dir / subdir if subdir else self.template_dir
        files = []

        for root, _, filenames in os.walk(search_dir):
            for filename in filenames:
                if filename.endswith((".j2", ".jinja2", ".jinja")):
                    full_path = Path(root) / filename
                    rel_path = full_path.relative_to(self.template_dir)
                    # =====================================================================
                    # [Windows 兼容性修复] 路径分隔符统一化
                    # =====================================================================
                    # 问题描述：
                    #   在 Windows 上，os.walk() + str(rel_path) 返回的路径使用 \ 分隔符，
                    #   例如："04-server\controller\MasterController.java.j2"
                    #   导致后续 gen_*.py 中的 `if "/" not in tpl` 过滤条件失效，
                    #   以及 compute_output_path() 中的正则表达式 (^|/) 无法匹配路径开头。
                    #
                    # 修复方案：
                    #   使用 Path.as_posix() 强制返回 / 分隔符的路径字符串，
                    #   确保所有平台返回统一格式："04-server/controller/MasterController.java.j2"
                    #
                    # 影响范围：
                    #   - gen_master_detail.py 等生成器中的根目录模板过滤
                    #   - compute_output_path() 中的 Master/Detail 前缀正则匹配
                    # =====================================================================
                    files.append(rel_path.as_posix())

        return files

    def get_static_files(self, subdir: str = "") -> list[str]:
        """
        递归扫描模板目录，返回所有非 Jinja2 模板文件的相对路径列表。

        收集扩展名不为 .j2 / .jinja2 / .jinja 的常规文件（如 .md, .py, .sh）。
        路径相对于 self.template_dir。

        注意：返回的路径始终使用 / 作为分隔符（跨平台兼容）。

        Args:
            subdir (str): 在 template_dir 内进一步限定的子目录名。
                          为空字符串时扫描整个 template_dir。

        Returns:
            list[str]: 静态文件相对路径列表（如 '03-http-scripts/test_mock.py'）。
        """
        search_dir = self.template_dir / subdir if subdir else self.template_dir
        files = []

        for root, _, filenames in os.walk(search_dir):
            for filename in filenames:
                if not filename.endswith((".j2", ".jinja2", ".jinja")):
                    full_path = Path(root) / filename
                    rel_path = full_path.relative_to(self.template_dir)
                    if rel_path.name == "README.md":
                        continue
                    # [Windows 兼容性修复] 同 get_template_files()，详见上方注释
                    files.append(rel_path.as_posix())

        return files

    def compute_output_path(
        self, template_rel_path: str, output_dir: str, context: dict
    ) -> str:
        """
        根据模板相对路径和上下文，计算最终的输出文件绝对路径。

        处理逻辑：
        1. 去除模板文件名的 .j2/.jinja2/.jinja 扩展名
        2. 将路径中的 {{Domain}} 替换为业务域 PascalCase（如 'Demo'）
        3. 将路径中的 {{domain}} 替换为原始业务域代码（如 'demo'）
        4. 将路径中的 {{Module}} 替换为模块 PascalCase（如 'Basic'）
        5. 将路径中的 {{module}} 替换为原始模块代码（如 'basic'）
        6. 拼接到 output_dir 下得到完整绝对路径

        示例：
            模板路径 "04-server/entity/po/BizDomainModule.java.j2"
            + domain='demo', code='basic'
            → 输出路径 "{output_dir}/04-server/entity/po/BizDemoBasic.java"

        Args:
            template_rel_path (str): 模板文件相对路径（相对于 template_dir）。
            output_dir (str): 输出根目录路径。
            context (dict): 模板上下文字典（需包含 module 子字典）。

        Returns:
            str: 输出文件的绝对路径字符串。
        """
        # 移除 .j2 / .jinja2 后缀
        path = template_rel_path
        for ext in [".j2", ".jinja2", ".jinja"]:
            if path.endswith(ext):
                path = path[: -len(ext)]
                break

        # 替换路径中的占位符
        module = context.get("module", {})
        domain = module.get("domain", "")
        code = module.get("code", "")
        code_pascal = module.get("code_pascal", "")
        domain_pascal = self._to_pascal(domain)

        # 1. 先替换 DomainModule 复合词（Java 模板命名风格，无花括号）
        #    必须最先替换，避免后续单词替换导致部分匹配
        path = path.replace("DomainModule", f"{domain_pascal}{code_pascal}")

        # 2. 再替换双花括号占位符（SQL/HTTP 模板命名风格）
        # 2.1 支持嵌套点号语法（如 {{module.master.code}}, {{module.detail.code}}）
        #     用于 master-detail 模式的文件命名
        master = module.get("master", {})
        detail = module.get("detail", {})
        master_code = master.get("code", "") if isinstance(master, dict) else ""
        detail_code = detail.get("code", "") if isinstance(detail, dict) else ""

        path = path.replace("{{module.master.code}}", master_code)
        path = path.replace("{{module.detail.code}}", detail_code)

        # 2.2 支持点号语法（如 {{module.code}}, {{module.domain}}）
        path = path.replace("{{module.code}}", code)
        path = path.replace("{{Module.Code}}", code_pascal)
        path = path.replace("{{module.domain}}", domain)
        path = path.replace("{{Module.Domain}}", domain_pascal)
        path = path.replace("{{module.name}}", module.get("name", ""))
        path = path.replace("{{Module.Name}}", self._to_pascal(module.get("name", "")))
        path = path.replace("{{module.table_name}}", module.get("table_name", ""))
        path = path.replace("{{module.api_path}}", module.get("api_path", ""))

        # 2.3 简单占位符（向后兼容）
        path = path.replace("{{Domain}}", domain_pascal)
        path = path.replace("{{domain}}", domain)
        path = path.replace("{{Module}}", code_pascal)
        path = path.replace("{{module}}", code)

        # 3. 移除 Master/Detail/IMaster/IDetail 前缀（主子表模式下文件名前缀与类名不一致的问题）
        #    模板文件名: MasterDomainModuleController.java.j2 → DemoTalentController.java
        #    模板文件名: IMasterDomainModuleService.java.j2 → IDemoTalentService.java
        #    类名: DemoTalentController / IDemoTalentService (无 Master/Detail 前缀)
        import re

        # =====================================================================
        # [Windows 兼容性修复] 正则表达式路径分隔符匹配
        # =====================================================================
        # 问题描述：
        #   原正则表达式 (^|/) 只匹配 Unix 风格的 / 分隔符，
        #   在 Windows 上，如果路径使用 \ 分隔符（如 "04-server\MasterController.java"），
        #   正则无法匹配路径开头的 Master 前缀，导致：
        #   - 文件名中的 Master/Detail 前缀无法被移除
        #   - 输出文件名错误（如 MasterDemoController.java 而非 DemoController.java）
        #   - 多个文件可能被写入同一路径，导致覆盖丢失
        #
        # 修复方案：
        #   使用 (^|[\\/]) 同时匹配：
        #   - ^  : 字符串开头
        #   - [\\/] : 字符类，匹配 \ 或 / 任一分隔符
        #
        # 注意：
        #   由于 get_template_files() 已使用 as_posix() 统一返回 / 分隔符，
        #   此处 [\\/] 主要是防御性编程，确保即使有遗漏也能正确处理。
        # =====================================================================

        # 先处理 IMaster/IDetail：保留 I 前缀，移除 Master/Detail
        path = re.sub(r"(^|[\\/])I(Master|Detail)(?=[A-Z])", r"\1I", path)
        # 再处理 Master/Detail（无 I 前缀的）：完全移除
        path = re.sub(r"(^|[\\/])(Master|Detail)(?=[A-Z])", r"\1", path)

        return str(Path(output_dir) / path)

    @staticmethod
    def _to_pascal(name: str) -> str:
        """
        将下划线分隔的字符串转换为 PascalCase，用于文件名占位符替换。

        示例：'demo' → 'Demo'，'demo' → 'Demo'

        Args:
            name (str): 下划线分隔（或无分隔符）的字符串。

        Returns:
            str: PascalCase 字符串。
        """
        return "".join(word.capitalize() for word in name.split("_"))

    def render_all(self, context: dict, output_dir: str, exclude: list = None) -> int:
        """
        批量渲染模板目录下的所有 .j2 文件并写入输出目录。

        这是生成器主流程调用的核心方法。执行步骤：
        1. 确保输出目录存在（mkdir -p）
        2. 通过 get_template_files() 获取全部模板文件列表
        3. 对每个模板调用 compute_output_path() 计算实际输出路径
        4. 调用 render_to_file() 渲染并写入文件
        5. 返回已生成的文件数量

        Args:
            context (dict): 模板上下文字典（module/fields/project 等）。
            output_dir (str): 输出根目录路径。
            exclude (list): 需要跳过的模板文件名列表（仅匹配文件名，不含路径）。

        Returns:
            int: 成功生成的文件数量。
        """
        output_dir = Path(output_dir)
        if not DRY_RUN:
            output_dir.mkdir(parents=True, exist_ok=True)

        # 获取所有模板文件
        template_files = self.get_template_files()
        static_files = self.get_static_files()
        # 双模运行件（_runtime/ 目录）：config 未开 include_runtime 时默认不渲染（贴入式产物零污染）
        rt_on = context.get('include_runtime') or (context.get('module') or {}).get('include_runtime')
        if not rt_on:
            template_files = [t for t in template_files if '_runtime' not in str(Path(t).parent)]
            static_files = [s_ for s_ in static_files if '_runtime' not in str(Path(s_).parent)]
        if exclude:
            template_files = [t for t in template_files if Path(t).name not in exclude]
            static_files = [s for s in static_files if Path(s).name not in exclude]
        count = 0

        for template_path in template_files:
            # 计算输出路径
            output_path = self.compute_output_path(template_path, output_dir, context)

            print(f"  📄 {Path(output_path).name}")

            # 渲染并写入
            self.render_to_file(template_path, output_path, context)
            count += 1

        for static_path in static_files:
            # 计算输出路径（不会移除后缀，但会执行可能需要的变量替换）
            output_path = self.compute_output_path(static_path, output_dir, context)

            print(f"  📄 {Path(output_path).name} (Static)")

            if DRY_RUN:
                print(f"  👁 [DRY-RUN] {output_path} (Static)")
                count += 1
                continue

            # 确保目录存在
            Path(output_path).parent.mkdir(parents=True, exist_ok=True)

            # 直接通过 shutil 复制静态文件
            source_path = self.template_dir / static_path
            shutil.copy2(source_path, output_path)
            count += 1

        return count

    def render_all_with_prefix(
        self, context: dict, output_dir: str, prefix: str, exclude: list = None
    ) -> int:
        """
        批量渲染模板目录下以指定前缀开头的 .j2 文件并写入输出目录。

        用于 master-detail 模式，只渲染 Master* 或 Detail* 前缀的模板。

        Args:
            context (dict): 模板上下文字典（module/fields/project 等）。
            output_dir (str): 输出根目录路径。
            prefix (str): 文件名前缀过滤条件（如 'Master' 或 'Detail'）。
            exclude (list): 可选排除列表。支持传入模板相对路径或文件名。

        Returns:
            int: 成功生成的文件数量。
        """
        output_dir = Path(output_dir)
        if not DRY_RUN:
            output_dir.mkdir(parents=True, exist_ok=True)

        # 获取所有模板文件和静态文件
        template_files = self.get_template_files()
        static_files = self.get_static_files()

        # 可选排除：支持按完整相对路径或文件名排除
        if exclude:
            exclude_set = set(exclude)
            template_files = [
                t
                for t in template_files
                if t not in exclude_set and Path(t).name not in exclude_set
            ]
            static_files = [
                s
                for s in static_files
                if s not in exclude_set and Path(s).name not in exclude_set
            ]

        count = 0

        for template_path in template_files:
            # 只处理文件名以 prefix 开头的模板
            filename = Path(template_path).name
            if not filename.startswith(prefix):
                continue

            # 计算输出路径
            output_path = self.compute_output_path(template_path, output_dir, context)

            print(f"  📄 {Path(output_path).name}")

            # 渲染并写入
            self.render_to_file(template_path, output_path, context)
            count += 1

        for static_path in static_files:
            # 只处理文件名前缀
            filename = Path(static_path).name
            if not filename.startswith(prefix):
                continue

            # 计算输出路径
            output_path = self.compute_output_path(static_path, output_dir, context)

            print(f"  📄 {Path(output_path).name} (Static)")

            if DRY_RUN:
                print(f"  👁 [DRY-RUN] {output_path} (Static)")
                count += 1
                continue

            # 确保目录存在
            Path(output_path).parent.mkdir(parents=True, exist_ok=True)

            # 直接复制静态文件
            source_path = self.template_dir / static_path
            shutil.copy2(source_path, output_path)
            count += 1

        return count
