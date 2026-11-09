#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
================================================================================
可选配置上下文一致性分析工具
================================================================================

【背景问题】
---------
低代码生成器支持多种可选配置：
- has_batch_operations: 批量操作（批量删除/批量更新）
- has_status_toggles: 状态切换开关
- has_master_file: 主表附件
- has_detail_file: 明细表附件
- has_file: 通用附件标识

这些配置在 Jinja2 模板中存在 5 种不同的访问方式：
1. `has_batch_operations`         - 顶层变量（单表模式）
2. `module.has_batch_operations`  - module dict 属性（主从表模式）
3. `master_module.has_batch_operations` - 主表直接引用
4. `dm.has_batch_operations`      - 明细表遍历中的引用
5. `st.module.has_batch_operations` - 子表遍历中的引用

【问题根源】
---------
不同的生成器（gen_single.py, gen_master_detail_file.py 等）构建上下文的方式不同：
- 单表模式: context = { "module": enriched_module, "has_batch_operations": True }
- 主从模式: web_context = { "module": { "has_batch_operations": master.get(...) } }

如果生成器没有正确注入某个变量，模板渲染时会报 Jinja2 UndefinedError。

【分析思路】
---------
Phase 1 - 扫描模板:
  遍历 templates/**/*.j2，用正则提取 {% if xxx %} 和 {{ xxx }} 中的变量路径
  结果: template_access[var][access_path] = [使用文件列表]

Phase 2 - 扫描生成器:
  遍历 module/gen_*.py，用正则提取上下文注入点
  结果: generator_injections[var][gen_file] = [注入点列表]

Phase 3 - 对比分析:
  对于每个变量，检查：模板使用的路径 ∈ 生成器提供的路径
  不匹配则记录为潜在冲突

Phase 4 - 输出报告:
  生成 Markdown 报告到 output/ 目录，包含：
  - 模板访问统计表
  - 生成器注入统计表
  - 潜在冲突清单
  - 修复建议

【设计原则】
---------
1. 只读不写：不自动修改任何代码，只输出分析报告
2. 正则宽松：宁可多匹配也不要漏报，人工复核成本低
3. 路径归一：将 module.xxx 和 xxx 视为等价（同一上下文）

【使用方式】
---------
cd .claude/scripts/low-code-generator
python3 module/analyze_optional_context.py

输出: output/optional_context_analysis_YYYYMMDD_HHMMSS.md
================================================================================
"""

import os
import re
from pathlib import Path
from collections import defaultdict
from datetime import datetime


class OptionalContextAnalyzer:
    """可选配置上下文一致性分析器"""

    # 目标变量
    TARGET_VARS = [
        'has_batch_operations',
        'has_status_toggles',
        'has_master_file',
        'has_detail_file',
        'has_file',
    ]

    def __init__(self, base_dir: str = None):
        self.base_dir = Path(base_dir) if base_dir else Path(__file__).parent.parent
        self.templates_dir = self.base_dir / 'templates'
        self.module_dir = self.base_dir / 'module'
        self.output_dir = self.base_dir / 'output'
        self.output_dir.mkdir(parents=True, exist_ok=True)

        # 分析结果
        self.template_access = defaultdict(lambda: defaultdict(list))
        self.generator_injections = defaultdict(lambda: defaultdict(list))

    def run(self):
        """执行完整分析"""
        print("=" * 60)
        print("📊 可选配置上下文一致性分析")
        print("=" * 60)

        # Phase 1: 扫描模板
        print("\n## Phase 1: 扫描模板访问路径\n")
        self._scan_templates()

        # Phase 2: 读取生成器
        print("\n## Phase 2: 读取生成器注入点\n")
        self._scan_generators()

        # Phase 3: 对比分析
        print("\n## Phase 3: 对比分析\n")
        self._analyze_conflicts()

        # Phase 4: 输出报告
        print("\n## Phase 4: 输出报告\n")
        self._generate_report()

    def _scan_templates(self):
        """扫描所有模板，提取访问路径"""
        j2_files = list(self.templates_dir.rglob('**/*.j2'))

        for j2_file in j2_files:
            rel_path = j2_file.relative_to(self.templates_dir)
            content = j2_file.read_text(encoding='utf-8')

            for var in self.TARGET_VARS:
                # 匹配 {% if xxx %} 或 {% if module.xxx %} 等
                patterns = [
                    # {% if has_batch_operations %}
                    (r'{%-?\s*if\s+' + var + r'\s*%}'),
                    # {% if module.has_batch_operations %}
                    (r'{%-?\s*if\s+' + var + r'\s*%}'),
                    # {% if dm.has_batch_operations %}
                    (r'{%-?\s*if\s+([a-zA-Z_]+\.)?' + var + r'\s*%}'),
                    # {{ module.has_batch_operations }}
                    (r'{{-?\s*' + var + r'\s*}}'),
                    (r'{{-?\s*([a-zA-Z_]+\.)?' + var + r'\s*}}'),
                ]

                for pattern in patterns:
                    matches = re.findall(pattern, content)
                    for match in matches:
                        # 提取完整的访问路径
                        access_path = self._extract_access_path(match, var)
                        if access_path:
                            self.template_access[var][access_path].append(str(rel_path))

        # 打印统计
        for var in self.TARGET_VARS:
            if self.template_access[var]:
                print(f"\n### {var} 访问统计:")
                for path, files in sorted(self.template_access[var].items(), key=lambda x: len(x[1]), reverse=True):
                    print(f"  {path}: {len(files)} 次")

    def _extract_access_path(self, match: str, var: str) -> str:
        """从匹配中提取完整的访问路径"""
        # 提取 {% if xxx %} 或 {{ xxx }} 中的变量路径
        if_match = re.search(r'if\s+(.+?)\s*%}', match)
        if if_match:
            return if_match.group(1).strip()
        else_match = re.search(r'{{\s*(.+?)\s*}}', match)
        if else_match:
            return else_match.group(1).strip()
        return None

    def _scan_generators(self):
        """读取所有生成器，提取上下文注入点"""
        gen_files = list(self.module_dir.glob('gen_*.py'))

        for gen_file in gen_files:
            content = gen_file.read_text(encoding='utf-8')
            rel_path = gen_file.name

            for var in self.TARGET_VARS:
                # 查找上下文注入点
                # 模式1: "has_batch_operations": xxx (顶层)
                pattern1 = rf'"{var}"\s*:\s*[^,\n\}}]+'
                matches = re.findall(pattern1, content)
                for match in matches:
                    self.generator_injections[var][rel_path].append(f'顶层注入: {match.strip()}')

                # 模式2: "module": { "has_batch_operations": xxx }
                pattern2 = rf'"{var}"\s*:\s*[^,\n\}}]+'
                matches = re.findall(pattern2, content)
                for match in matches:
                    self.generator_injections[var][rel_path].append(f'module 注入: {match.strip()}')

                # 模式3: module[var] = xxx 或 module.get(var)
                pattern3 = rf'module\[.?\s*["\']?{var}["\']?\s*\.?\]?\s*=\s*[^,\n\}}]+'
                matches = re.findall(pattern3, content)
                for match in matches:
                    self.generator_injections[var][rel_path].append(f'module 赋值: {match.strip()}')

        # 打印统计
        for var in self.TARGET_VARS:
            if self.generator_injections[var]:
                print(f"\n### {var} 注入统计:")
                for gen, injections in sorted(self.generator_injections[var].items()):
                    unique_injections = list(set(injections))
                    print(f"  {gen}:")
                    for inj in unique_injections:
                        print(f"    - {inj}")

    def _analyze_conflicts(self):
        """对比分析，找出冲突"""
        self.conflicts = []

        for var in self.TARGET_VARS:
            template_paths = set(self.template_access[var].keys())
            generator_provides = set()

            # 收集生成器提供的路径
            for gen_file, injections in self.generator_injections[var].items():
                for inj in injections:
                    if '顶层注入' in inj:
                        generator_provides.add(var)
                    elif 'module 注入' in inj or 'module 赋值' in inj:
                        generator_provides.add(f'module.{var}')

            # 找出模板使用但生成器未提供的路径
            for path in template_paths:
                if path not in generator_provides and path != var:
                    # 检查是否是子路径（如 dm.xxx, st.module.xxx）
                    is_sub_path = '.' in path or '[' in path
                    if not is_sub_path:
                        files = self.template_access[var][path][:5]  # 只显示前5个
                        self.conflicts.append({
                            'var': var,
                            'path': path,
                            'files': files,
                            'reason': f'模板使用 {path}，但生成器未提供'
                        })

        # 打印冲突
        if self.conflicts:
            print("\n### ⚠️ 潜在冲突:")
            for conflict in self.conflicts:
                print(f"\n  {conflict['var']} - {conflict['path']}:")
                print(f"    原因: {conflict['reason']}")
                print(f"    使用文件: {', '.join(conflict['files'])}")
        else:
            print("\n### ✅ 未发现明显冲突")

    def _generate_report(self):
        """生成分析报告"""
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        report_file = self.output_dir / f'optional_context_analysis_{timestamp}.md'

        with open(report_file, 'w', encoding='utf-8') as f:
            f.write("# 可选配置上下文一致性分析报告\n\n")
            f.write(f"> **生成时间**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
            f.write("---\n\n")

            # 1. 模板访问统计
            f.write("## 1. 模板访问统计\n\n")
            for var in self.TARGET_VARS:
                if self.template_access[var]:
                    f.write(f"### {var}\n\n")
                    f.write("| 访问路径 | 使用次数 | 使用文件 |\n")
                    f.write("|----------|---------|----------|\n")
                    for path, files in sorted(self.template_access[var].items(), key=lambda x: len(x[1]), reverse=True):
                        unique_files = list(set(files))
                        f.write(f"| `{path}` | {len(files)} | {len(unique_files)} 个模板 |\n")
                    f.write("\n")

            # 2. 生成器注入统计
            f.write("## 2. 生成器注入统计\n\n")
            for var in self.TARGET_VARS:
                if self.generator_injections[var]:
                    f.write(f"### {var}\n\n")
                    for gen, injections in sorted(self.generator_injections[var].items()):
                        unique_injections = list(set(injections))
                        f.write(f"#### {gen}\n\n")
                        for inj in unique_injections:
                            f.write(f"- {inj}\n")
                        f.write("\n")

            # 3. 冲突分析
            f.write("## 3. 冲突分析\n\n")
            if self.conflicts:
                f.write("### ⚠️ 潜在冲突\n\n")
                for conflict in self.conflicts:
                    f.write(f"#### {conflict['var']} - `{conflict['path']}`\n\n")
                    f.write(f"- **原因**: {conflict['reason']}\n")
                    f.write(f"- **使用文件**: {', '.join(conflict['files'])}\n\n")
            else:
                f.write("### ✅ 未发现明显冲突\n\n")

            # 4. 修复建议
            f.write("## 4. 修复建议\n\n")
            f.write("### 统一访问路径规范\n\n")
            f.write("| 模式 | 推荐访问路径 | 上下文注入点 |\n")
            f.write("|------|---------------|------------|\n")
            f.write("| 单表 | `has_batch_operations` (顶层) | gen_single.py |\n")
            f.write("| 主从表 | `module.has_batch_operations` | gen_master_detail*.py |\n")
            f.write("| 多表 | `st.module.has_batch_operations` | gen_multi_table*.py |\n")
            f.write("| 明细遍历 | `dm.has_batch_operations` | gen_master_detail*.py |\n\n")

        print(f"\n✅ 报告已生成: {report_file}")


def main():
    """主函数"""
    analyzer = OptionalContextAnalyzer()
    analyzer.run()


if __name__ == '__main__':
    main()
