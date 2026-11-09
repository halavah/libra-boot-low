<div align="center">

# 🚀 Libra Boot Low

**基于 YAML 配置 + Jinja2 模板的低代码生成器，一键生成 Spring Boot + Vue3 完整业务骨架**

[![PyPI](https://img.shields.io/pypi/v/libra-boot-low)](https://pypi.org/project/libra-boot-low/)
[![PyPI downloads](https://img.shields.io/pypi/dm/libra-boot-low)](https://pypi.org/project/libra-boot-low/)
[![Python](https://img.shields.io/badge/Python-3.9+-blue.svg)](https://www.python.org/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Spring Boot](https://img.shields.io/badge/generates-Spring%20Boot-6DB33F.svg)](https://spring.io/projects/spring-boot)
[![Vue3](https://img.shields.io/badge/generates-Vue3-42b883.svg)](https://vuejs.org/)

[English](README_EN.md) | **简体中文**

</div>

> **本文遵循开源说明规范**：结构与徽章按统一体例，徽章仅指向公开可访问资源，版本信息指向发布渠道动态页。


---

## 📖 目录

- [快速上手](#-快速上手)
- [安装](#-安装)
- [生成链路](#-生成链路)
- [十二种生成模式](#-十二种生成模式)
- [生成产物](#-生成产物)
- [配置示例](#-配置示例)
- [测试](#-测试)
- [CLI 参数](#-cli-参数)
- [技术栈](#-技术栈)
- [项目结构](#-项目结构)
- [贡献指南](#-贡献指南)
- [License](#-license)
- [联系我们](#-联系我们)
- [Star History](#-star-history)

---

## 🚀 快速上手

```bash
# 方式一：直接从源码运行
pip install -r requirements.txt

# 使用示例配置生成
python3 generator.py config/test/t1000.yml

# 或使用交互式菜单
bash run.sh

# 批量生成全部模块
bash run.sh --all
```

## 📦 安装

| 通道 | 命令 | 状态 |
|---|---|---|
| 源码直跑 | `pip install -r requirements.txt` 后 `python3 generator.py` | ✅ 现可用 |
| GitHub Release wheel | `pip install https://github.com/halavah/libra-boot-low/releases/latest/download/libra_boot_low-1.2.0-py3-none-any.whl` | ✅ 现可用 |
| git 直装 | `pip install git+https://github.com/halavah/libra-boot-low.git` | 🔒 内网（需克隆权限） |
| PyPI | `pip install libra-boot-low` | ✅ 已上架（Trusted Publishing 自动发布，推 v* 标签即出新版；最新版见 [PyPI 页面](https://pypi.org/project/libra-boot-low/)） |

## 🔄 生成链路

```
YAML 配置  ──►  generator.py  ──►  module/gen_*.py  ──►  templates/{mode}/  ──►  out/{domain}/{code}/
  (yml/)         (主入口)          (模式生成器)         (Jinja2 模板)           (完整产物)
```

## 🧩 十二种生成模式

| 模式 | 说明 | 适用场景 |
|------|------|---------|
| `single` | 单表 CRUD | 简单业务表 |
| `single-with-file` | 单表 + 附件上传 | 带文件的业务表 |
| `multi-table` | 多表关联 | 主表带字典/配置表 |
| `multi-table-with-file` | 多表 + 附件 | 带文件的多表 |
| `master-detail` | 主从表（一对多） | 订单-订单明细 |
| `master-detail-with-file` | 主从表 + 附件 | 带文件的主从 |
| `master-detail-modules` | 主从表（模块化） | 子表独立成模块 |
| `master-detail-modules-with-file` | 主从模块化 + 附件 | 带文件的主从模块化 |
| `master-details-tabs` | 主多明细（页签） | 一主多子页签切换 |
| `master-details-tabs-with-file` | 主多明细页签 + 附件 | 带文件的多明细 |
| `master-details-tabs-dialog` | 主多明细（页签弹窗） | 弹窗编辑的复杂主从 |
| `master-details-tabs-dialog-with-file` | 页签弹窗 + 附件 | 带文件的页签弹窗 |

每种模式均有对应的 `templates/{mode}/` 模板目录和 `config/test/` 示例配置。

## 📦 生成产物

每个模块按六段编号生成完整产物链：

```
out/{domain}/{code}/
├── 00-inbox/ 01-design/      # 生成物清单 + 设计说明
├── 02-sql/ 02-sql-scripts/   # 建表 DDL + SQL 执行脚本
├── 03-http/ 03-http-scripts/ # HTTP 接口测试用例 + 运行脚本
├── 04-server/                # Spring Boot 后端
│   ├── controller/ service/ mapper/  # 控制器/业务/MyBatis 数据层
│   └── entity/{param,po,vo}/         # 实体三件套
└── 05-web/                   # Vue3 前端
    ├── views/                # 页面组件
    └── service/              # API 调用
```

## ⚙️ 配置示例

```yaml
# config/test/t1000.yml（节选——完整注释见该文件）
project:
  name: "Libra Boot Low"
  code: "demo"          # 项目编码（英文小写）
  version: "1.0.0"
  group: "com.libra"   # 生成代码包前缀（可配置，默认 com.libra）

modules:
  - name: "单表无附件"   # 模块中文名
    code: "t1000"       # 模块编码（英文小写）
    domain: "test"      # 业务域编码
    mode: "single"      # 生成模式（12 种之一）
    fields:             # 字段清单（type 决定 Java/SQL/Vue 三端类型）
      - { name: "title", label: "标题", type: "input", required: true }
      - { name: "status", label: "状态", type: "select" }
      - { name: "createTime", label: "创建时间", type: "date-year" }
```

## 🧪 测试

```bash
pip install pytest
python -m pytest tests/ -q   # 12 用例：配置加载/类型转换/DRY_RUN 零落盘/渲染器/单表产物结构
```

## ⌨️ CLI 参数

**generator.py 参数：**

| 参数 | 说明 |
|------|------|
| `config`（位置参数） | YAML 配置文件路径 |
| `output`（位置参数） | 输出目录（默认 `../../out`） |
| `--module <code>` / `-m` | 仅生成指定 code 的模块 |
| `--mode <mode>` | 覆盖 YAML 中的 mode |
| `--validate` / `-v` | 仅校验配置，不生成 |
| `--list` / `-l` | 列出配置内的模块 |
| `--list-modes` | 列出全部 12 种支持的模式 |
| `--dry-run` | 预览将生成的文件列表，零落盘 |
| `--update-index` / `-u` | 仅重建 config/index.json 索引 |
| `--batch-timestamp <ts>` | 批量模式共享日志时间戳 |
| `--version` | 显示版本号 |

**run.sh / run.ps1 启动器额外提供：** 交互式菜单（无参数运行）、`--all`（批量生成全部模块）、`--domain <name>`（按域过滤）——由启动器循环调用 generator.py 实现。

## 🛠️ 技术栈

| 组件 | 说明 |
|------|------|
| Python 3.9+ | 运行环境 |
| PyYAML | 配置解析 |
| Jinja2 | 模板渲染 |

## 📁 项目结构

```
libra-boot-low/
├── generator.py            # 主入口
├── run.sh                  # Shell 交互式菜单
├── run.ps1                 # PowerShell 交互式菜单
├── module/                 # 核心生成模块
│   ├── config_loader.py    # YAML 配置加载
│   ├── field_builder.py    # 字段构建器
│   ├── template_renderer.py # Jinja2 渲染器
│   └── gen_*.py            # 各模式生成器
├── templates/              # Jinja2 模板（12 种模式）
│   ├── single/
│   ├── single-with-file/
│   ├── multi-table/
│   ├── master-detail/
│   └── ...
├── config/                 # YAML 配置文件
│   ├── README.md           # 配置说明
│   └── test/               # 示例配置
```

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request！

```bash
# 1. Fork 本仓库
# 2. 创建特性分支
git checkout -b feature/your-feature
# 3. 提交变更（跑 pytest 确保不破坏）
python -m pytest tests/ -q
# 4. 推送并发 PR
git push origin feature/your-feature
```

**贡献要求**：
- 新增功能须附带测试用例（`tests/` 目录）
- 模板变更须跑全量 dry-run 回归（24 配置零落盘）
- 提交信息用中文描述变更内容

## 📄 License

MIT License — 详见 [LICENSE](LICENSE) 文件。

### 协议解读

MIT 是最宽松的开源协议之一：

- ✅ **允许**：商业使用、修改、分发、私有使用、专利使用
- ⚠️ **唯一要求**：保留版权声明和许可声明
- ❌ **不提供**：作者担保、责任担保

**为什么选择 MIT？**

低代码生成器是工具类项目，选 MIT 是为了：
- **零门槛使用**：企业可放心引入，无开源传染性
- **广泛兼容**：生成的代码不受本项目协议约束
- **社区友好**：鼓励 Fork 和二次开发

## 📮 联系我们

**项目维护者**：Halavah
**GitHub**：[@halavah](https://github.com/halavah)

**相关链接**：
- 项目主页：[GitHub](https://github.com/halavah/libra-boot-low)
- 问题反馈：[Issues](https://github.com/halavah/libra-boot-low/issues)
- 发布记录：[PyPI](https://pypi.org/project/libra-boot-low/)

## ⭐ Star History

如果这个项目对你有帮助，请给我们一个 ⭐ Star！你的支持是我们最大的动力！

[![Star History Chart](https://api.star-history.com/svg?repos=halavah/libra-boot-low&type=Date)](https://star-history.com/#halavah/libra-boot-low&Date)

---

**用 ❤️ 构建 | Made with ❤️**

如果这个项目帮助到了你，请考虑给我们一个 ⭐ Star

[⬆ 回到顶部](#-libra-boot-low)
