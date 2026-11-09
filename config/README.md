# 低代码生成器配置索引

> 更新于 2026-03-19

---

## 配置总览

- **总配置数**: 38 个
- **业务域**: 4 个（demo, demo, demo, test）
- **索引文件**: `index.json`（自动生成）

---

## 测试域配置（test/）- 24 个模块

测试配置采用 **四位数字命名规范**（保证文件自然排序正确）：

**命名规则**：
- **第一位**：模式类型（1=单表, 2=主子表, 3=多明细, 4=Tab明细, 5=Tab弹窗, 6=多平级）
- **后三位**：000=无附件, 001=全无边界, 002=仅主表, 003=仅明细, 004=全部

### 1-单表系列

| 编号 | 配置文件 | 模式 | 附件 | 说明 |
|:----:|---------|------|:----:|------|
| t1000 | `t1000.yml` | single | — | 单表无附件 |
| t1001 | `t1001.yml` | single-with-file | ✓ | 单表有附件 |

### 2-主子表系列

| 编号 | 配置文件 | 模式 | 附件配置 | 说明 |
|:----:|---------|------|:--------:|------|
| t2000 | `t2000.yml` | master-detail | — | 主子表无附件 |
| t2001 | `t2001.yml` | master-detail-with-file | 主× 明× | 主子表全无附件（边界） |
| t2002 | `t2002.yml` | master-detail-with-file | 主✓ 明× | 主子表主表附件 |
| t2003 | `t2003.yml` | master-detail-with-file | 主× 明✓ | 主子表明细附件 |
| t2004 | `t2004.yml` | master-detail-with-file | 主✓ 明✓ | 主子表全部附件 |

### 3-多明细系列

| 编号 | 配置文件 | 模式 | 附件配置 | 说明 |
|:----:|---------|------|:--------:|------|
| t3000 | `t3000.yml` | master-detail-modules | — | 多明细无附件 |
| t3001 | `t3001.yml` | master-detail-modules-with-file | 主× 明× | 多明细全无附件（边界） |
| t3002 | `t3002.yml` | master-detail-modules-with-file | 主✓ 明× | 多明细主表附件 |
| t3003 | `t3003.yml` | master-detail-modules-with-file | 主× 明✓ | 多明细明细附件 |
| t3004 | `t3004.yml` | master-detail-modules-with-file | 主✓ 明✓ | 多明细全部附件 |

### 4-Tab明细系列

| 编号 | 配置文件 | 模式 | 附件配置 | 说明 |
|:----:|---------|------|:--------:|------|
| t4000 | `t4000.yml` | master-details-tabs | — | Tab明细无附件 |
| t4001 | `t4001.yml` | master-details-tabs-with-file | 主× 明× | Tab明细全无附件（边界） |
| t4002 | `t4002.yml` | master-details-tabs-with-file | 主✓ 明× | Tab明细主表附件 |
| t4003 | `t4003.yml` | master-details-tabs-with-file | 主× 明✓ | Tab明细明细附件 |
| t4004 | `t4004.yml` | master-details-tabs-with-file | 主✓ 明✓ | Tab明细全部附件 |

### 5-Tab弹窗系列

| 编号 | 配置文件 | 模式 | 附件配置 | 说明 |
|:----:|---------|------|:--------:|------|
| t5000 | `t5000.yml` | master-details-tabs-dialog | — | Tab弹窗无附件 |
| t5001 | `t5001.yml` | master-details-tabs-dialog-with-file | 主× 明× | Tab弹窗全无附件（边界） |
| t5002 | `t5002.yml` | master-details-tabs-dialog-with-file | 主✓ 明× | Tab弹窗主表附件 |
| t5003 | `t5003.yml` | master-details-tabs-dialog-with-file | 主× 明✓ | Tab弹窗明细附件 |
| t5004 | `t5004.yml` | master-details-tabs-dialog-with-file | 主✓ 明✓ | Tab弹窗全部附件 |

### 6-多平级系列

| 编号 | 配置文件 | 模式 | 附件 | 说明 |
|:----:|---------|------|:----:|------|
| t6000 | `t6000.yml` | multi-table | — | 多平级无附件 |
| t6001 | `t6001.yml` | multi-table-with-file | ✓ | 多平级有附件 |

**附件标识规则**（后三位）：
- `000` = 无附件模式（基础模式，不支持附件）
- `001` = 全无附件（边界场景，验证 `with-file` 模式不配置附件时行为）
- `002` = 仅主表有附件
- `003` = 仅明细有附件
- `004` = 主表 + 明细都有附件

---

## 业务域配置说明

业务域目录按需自建（如 `config/demo/`），每个业务域一个子目录，目录内每个模块一个 YAML 文件。仓库仅内置 `test/` 测试域（24 个配置，覆盖 12 种生成模式全部分支）；使用者可参照 `config/test/t1000.yml` 内的逐字段注释创建自己的业务域配置。

---

## 配置文件结构

```
config/
├── index.json          # 配置索引（自动生成）
├── README.md           # 本文件
├── test/               # 测试域（24 个配置）
│   ├── t1000.yml       # 单表无附件
│   ├── t1001.yml       # 单表有附件
│   ├── t2000.yml       # 主子表无附件
│   ├── t2001.yml       # 主子表全无附件（边界）
│   ├── t2002.yml       # 主子表主表附件
│   ├── t2003.yml       # 主子表明细附件
│   ├── t2004.yml       # 主子表全部附件
│   ├── t3000.yml       # 多明细无附件
│   ├── t3001.yml       # 多明细全无附件（边界）
│   ├── t3002.yml       # 多明细主表附件
│   ├── t3003.yml       # 多明细明细附件
│   ├── t3004.yml       # 多明细全部附件
│   ├── t4000.yml       # Tab明细无附件
│   ├── t4001.yml       # Tab明细全无附件（边界）
│   ├── t4002.yml       # Tab明细主表附件
│   ├── t4003.yml       # Tab明细明细附件
│   ├── t4004.yml       # Tab明细全部附件
│   ├── t5000.yml       # Tab弹窗无附件
│   ├── t5001.yml       # Tab弹窗全无附件（边界）
│   ├── t5002.yml       # Tab弹窗主表附件
│   ├── t5003.yml       # Tab弹窗明细附件
│   ├── t5004.yml       # Tab弹窗全部附件
│   ├── t6000.yml       # 多平级无附件
│   └── t6001.yml       # 多平级有附件
└── demo/               # 示例业务域（按需自建）
    └── sample.yml
```

---

## 如何使用配置

### 交互式菜单

```bash
cd .claude/scripts/low-code-generator
./run.sh
```

### 命令行模式

```bash
# 生成单个测试模块
./run.sh config/test/t1000.yml

# 批量生成全部测试模块
./run.sh config/test/*.yml
```

---

## 注意事项


1. **测试模块用途**
   - `test/` 目录下的 24 个配置用于验证 12 种生成模式
   - 覆盖各种附件组合场景（无附件/主表附件/明细附件/全部附件）

2. **测试完整性**
   - L3: SQL 重置 + HTTP 接口测试
   - L4: Playwright E2E 页面测试
   - Full: L3 + L4 全量验证

---

更新时间: 2026-03-19
