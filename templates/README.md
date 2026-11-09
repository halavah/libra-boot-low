# 低代码生成器模板目录

> **文档目的**: 说明各模板的命名规范、附件策略、前端交互模式与生成器处理逻辑

---

## 一、12 种生成模式速查表

### 1.1 模式分类总览

| # | mode | 中文名称 | 前端交互 | 附件支持 | 接口数 |
|---|------|---------|---------|:-------:|:------:|
| **单表系列** |
| 01 | `single` | 单表无附件 | 单页 CRUD | — | 6 |
| 02 | `single-with-file` | 单表有附件 | 单页 CRUD + 上传 | ✓ | 9 |
| **主子表系列（1:1 明细）** |
| 03 | `master-detail` | 主子表无附件 | 视图切换 | — | 12 |
| 04 | `master-detail-with-file` | 主子表有附件 | 视图切换 + 上传 | ✓ | 15 |
| **多明细表系列（1:N 明细，视图切换）** |
| 05 | `master-detail-modules` | 多明细无附件 | 视图切换 | — | 6+6×N |
| 06 | `master-detail-modules-with-file` | 多明细有附件 | 视图切换 + 上传 | ✓ | 9+9×N |
| **多明细表系列（1:N 明细，Tab 切换）** |
| 07 | `master-details-tabs` | Tab明细无附件 | Tab 切换 | — | 6+6×N |
| 08 | `master-details-tabs-with-file` | Tab明细有附件 | Tab 切换 + 上传 | ✓ | 9+9×N |
| **多明细表系列（1:N 明细，Tab + 弹窗）** |
| 09 | `master-details-tabs-dialog` | Tab弹窗无附件 | Tab + 弹窗 | — | 6+6×N |
| 10 | `master-details-tabs-dialog-with-file` | Tab弹窗有附件 | Tab + 弹窗 + 上传 | ✓ | 9+9×N |
| **多平级表系列（N 张独立表）** |
| 11 | `multi-table` | 多平级无附件 | Tab 切换 | — | 6×N |
| 12 | `multi-table-with-file` | 多平级有附件 | Tab 切换 + 上传 | ✓ | 9×N |

### 1.2 模式决策树

```
只有一张业务表？
├─ 无附件  →  01 single
└─ 有附件  →  02 single-with-file

有主表 + 单个明细（明细含外键 → 主表）？
├─ 明细无附件  →  03 master-detail
└─ 明细有附件  →  04 master-detail-with-file

有主表 + 多个明细（明细含外键 → 主表）？
├─ 前端交互模式？
│   ├─ 视图切换（innerType 状态机）    →  05/06 master-detail-modules[-with-file]
│   ├─ Tab 切换（el-tabs）             →  07/08 master-details-tabs[-with-file]
│   └─ Tab + 弹窗（el-dialog）          →  09/10 master-details-tabs-dialog[-with-file]
└─ 附件配置？
    ├─ 主表/明细均无附件  →  选择无 -with-file 后缀的模式
    └─ 主表/明细有附件    →  选择带 -with-file 后缀的模式

多张平级独立表（无外键，Tab 切换）？
├─ 每表无附件  →  11 multi-table
└─ 每表有附件  →  12 multi-table-with-file
```

---

## 二、状态切换功能（status_toggles）

### 2.1 功能说明

所有模式均支持可选的 **状态切换按钮** 功能，通过 `status_toggles` 配置自动生成：

| 产物 | 有 status_toggles | 无 status_toggles |
|------|------------------|-------------------|
| 前端 Service | `toggle()` / `toggleMaster()` API | 不生成 toggle API |
| 后端 Controller | `/toggle` 接口 | 不生成 toggle 接口 |
| 后端 Service | `toggleStatus()` 方法 | 不生成 toggle 方法 |
| 前端 Vue | 列表切换按钮 + `handleToggle` | 不生成切换按钮 |

### 2.2 配置位置

| 模式 | 配置位置 | 说明 |
|------|---------|------|
| `single` / `single-with-file` | `modules[].status_toggles` | 单表模式直接在模块级配置 |
| `master-detail` 系列 | `master.status_toggles` / `detail.status_toggles` | **不再继承**模块级配置，各自独立配置 |
| `master-detail-modules` 系列 | `master.status_toggles` / `detail_modules[].status_toggles` | **不再继承**模块级配置，各自独立配置 |
| `master-details-tabs` 系列 | `master.status_toggles` / `detail_modules[].status_toggles` | **不再继承**模块级配置，各自独立配置 |
| `master-details-tabs-dialog` 系列 | `master.status_toggles` / `detail_modules[].status_toggles` | **不再继承**模块级配置，各自独立配置 |
| `multi-table` 系列 | `sub_tables[].status_toggles` | 每个子表独立配置 |

> ⚠️ **重要变更**: 从 2026-03-25 起，status_toggles 配置位置进行了调整：
> - **模块级 status_toggles 不再自动继承**: master/detail/sub_tables 需要各自独立配置
> - **单表模式**: 继续在模块级 `modules[].status_toggles` 配置（保持不变）
> - **主从表模式**: master 和 detail 各自配置，不再从模块级继承
> - **多平级表模式**: 每个子表独立配置 `sub_tables[].status_toggles`

### 2.3 配置规范

```yaml
status_toggles:
  - field: "status"        # 必填：状态字段名（需在 fields 中定义）
    label: "状态"          # 可选：中文标签（默认使用 field）
    values:                # 必填：值 → 按钮文本映射
      "0": "禁用"          # ⚠️ YAML 整数键会自动转为字符串
      "1": "启用"
      "2": "审核中"
    colors:                # 可选：值 → 按钮颜色（默认 danger/success）
      "0": "danger"        # el-button type: primary/success/warning/danger/info
      "1": "success"
      "2": "warning"
    icons:                 # 可选：值 → 图标（预留扩展）
      "0": "Close"
      "1": "Check"
```

### 2.4 多状态切换

支持配置多个状态字段的切换按钮：

```yaml
status_toggles:
  - field: "status"
    values: { "0": "禁用", "1": "启用" }
    colors: { "0": "danger", "1": "success" }
  - field: "publishStatus"
    label: "发布状态"
    values: { "0": "未发布", "1": "已发布" }
    colors: { "0": "info", "1": "primary" }
```

---

## 三、批量操作功能（batch_operations）

### 3.1 功能说明

所有模式均支持可选的 **批量操作** 功能，通过 `batch_operations` 配置自动生成：

| 产物 | 有 batch_operations | 无 batch_operations |
|------|-------------------|---------------------|
| 前端 Service | `batchDelete()` / `batchUpdate()` / `batchToggle()` API | 不生成批量操作 API |
| 后端 Controller | `/batch-delete` `/batch-update` `/batch-toggle` 接口 | 不生成批量接口 |
| 后端 Service | `batchDelete()` / `batchUpdate()` / `batchToggle()` 方法 | 不生成批量方法 |
| 后端 Param | `BatchUpdateParam` 入参类 | 不生成 BatchUpdateParam |
| 前端 Vue | 批量按钮 + G-table 多选 + `handleBatch*` 处理函数 | 不生成批量按钮 |

### 3.2 配置位置

| 模式 | 配置位置 | 说明 |
|------|---------|------|
| `single` / `single-with-file` | `modules[].batch_operations` | 单表模式直接在模块级配置 |
| `master-detail` 系列 | `master.batch_operations` / `detail.batch_operations` | 主从表各自独立配置 |
| `master-detail-modules` 系列 | `master.batch_operations` / `detail_modules[].batch_operations` | 主表和每个明细表独立配置 |
| `master-details-tabs` 系列 | `master.batch_operations` / `detail_modules[].batch_operations` | 主表和每个明细表独立配置 |
| `master-details-tabs-dialog` 系列 | `master.batch_operations` / `detail_modules[].batch_operations` | 主表和每个明细表独立配置 |
| `multi-table` 系列 | `sub_tables[].batch_operations` | 每个子表独立配置 |

### 3.3 配置规范

```yaml
batch_operations:
  delete:
    enabled: true              # 是否启用批量逻辑删除（默认 false）
  update:
    enabled: true              # 是否启用批量更新（默认 false）
    confirm_message: "确认批量更新选中的记录？"  # 可选：确认提示（update 层级）
    fields:                    # 批量更新弹窗字段列表
      - name: "title"          # 必填：字段名（camelCase）
        label: "标题"          # 必填：字段中文标签
        type: "input"          # 必填：控件类型（input/textarea/number/date/date-year/select）
        required: false        # 可选：是否必填（默认 false）
      - name: "year"
        label: "年度"
        type: "date-year"
        required: false
      - name: "status"
        label: "状态"
        type: "select"
        required: false
        options:               # select 类型必填：选项列表
          - label: "进行中"
            value: 1
          - label: "已完成"
            value: 2
      - name: "remark"
        label: "备注"
        type: "textarea"
        required: false
```

### 3.4 前端 UI 组件

启用批量操作后，自动生成以下前端组件：

1. **G-table 多选列**: `isSelect: true, reserveSelection: true, rowKey: 'id'`
2. **批量按钮区域**:
   - 批量删除按钮（primary）
   - 批量更新按钮（primary）→ 点击打开弹窗表单
3. **处理函数**:
   - `handleSelectionChange(selection)` - 多选变化处理
   - `handleBatchDelete()` - 批量逻辑删除
   - `handleBatchUpdate()` - 打开批量更新弹窗 → 用户填写 → 提交更新

### 3.5 后端 API 接口

| 接口 | 方法 | 路径 | 入参 | 说明 |
|------|------|------|------|------|
| 批量逻辑删除 | POST | `/batch-delete` | `List<Long> ids` | 软删除（设置 is_deleted=1） |
| 批量物理删除 | POST | `/batch-physical-delete` | `List<Long> ids` | 物理删除（DELETE FROM） |
| 批量更新 | POST | `/batch-update` | `BatchUpdateParam` | 弹窗表单，用户可选择性填写多个字段 |

**BatchUpdateParam 结构**:
```java
@ApiModel("批量更新入参")
public class XxxBatchUpdateParam {
    @ApiModelProperty("主键ID列表")
    @NotEmpty(message = "请选择要更新的记录")
    private List<Long> ids;

    @ApiModelProperty("更新数据（字段名→值）")
    @NotNull(message = "更新数据不能为空")
    private Map<String, Object> data;
}
```

### 3.6 使用示例

```yaml
# 单表模式示例
modules:
  - code: "activity"
    name: "活动管理"
    batch_operations:
      delete:
        enabled: true
      update:
        enabled: true
        confirm_message: "确认批量更新选中的活动？"
        fields:
          - name: "title"
            label: "标题"
            type: "input"
            required: false
          - name: "status"
            label: "状态"
            type: "select"
            required: false
            options:
              - label: "进行中"
                value: 1
              - label: "已完成"
                value: 2
          - name: "remark"
            label: "备注"
            type: "textarea"
            required: false

# 主从表模式示例
master:
  code: "project"
  batch_operations:
    delete:
      enabled: true
    update:
      enabled: true
      confirm_message: "确认批量更新选中的主表记录？"
      fields:
        - name: "projectName"
          label: "项目名称"
          type: "input"
          required: false
        - name: "year"
          label: "年度"
          type: "date-year"
          required: false
        - name: "remark"
          label: "备注"
          type: "textarea"
          required: false
detail:
  code: "task"
  batch_operations:
    delete:
      enabled: true
```

---

## 四、附件策略（-with-file 模式专用）

### 4.1 附件配置位置

| 模式 | 主表附件 | 明细表附件 | 配置位置 |
|------|:-------:|:--------:|---------|
| `single-with-file` | ✓ | — | `modules[].file_types` |
| `master-detail-with-file` | 可选 | 可选 | `master.file_types` / `detail.file_types` |
| `master-detail-modules-with-file` | 可选 | 可选 | `master.file_types` / `detail_modules[].file_types` |
| `master-details-tabs-with-file` | 可选 | 可选 | `master.file_types` / `detail_modules[].file_types` |
| `master-details-tabs-dialog-with-file` | 可选 | 可选 | `master.file_types` / `detail_modules[].file_types` |
| `multi-table-with-file` | — | ✓ | `sub_tables[].file_types` |

### 4.2 附件策略组合

对于 `-with-file` 模式，附件有 4 种组合：

| 组合 | 主表附件 | 明细附件 | 典型场景 |
|------|:-------:|:-------:|---------|
| **无附件** | ✗ | ✗ | 纯数据管理，无需文件 |
| **仅主表** | ✓ | ✗ | 项目申报材料（主表） |
| **仅明细** | ✗ | ✓ | 成果附件（明细） |
| **全部** | ✓ | ✓ | 项目+成果都有附件 |

### 4.3 file_types 配置规范

```yaml
file_types:
  - code: "plan"      # ⚠️ 必须英文小写，禁止中文/数字
    label: "计划文件"  # 中文显示名
  - code: "result"
    label: "成果文件"
  - code: "photo"
    label: "现场照片"
```

---

## 五、前端交互模式详解

### 5.1 视图切换模式（master-detail-modules）

```
┌─────────────────────────────────────┐
│  [新增] [导出]        [刷新] [列设置] │
├─────────────────────────────────────┤
│  主表列表（isType=1）                 │
│  ┌───┬───────┬───────┬───────────┐   │
│  │选择│名称   │状态   │  操作     │   │
│  ├───┼───────┼───────┼───────────┤   │
│  │   │项目A  │进行中 │详情 编辑 删除│  │
│  └───┴───────┴───────┴───────────┘   │
├─────────────────────────────────────┤
│  点击「新增/编辑」→ isType=2         │
│  ┌─────────────────────────────────┐ │
│  │ [返回] 新增/编辑主表              │ │
│  │ ─────────────────────────────── │ │
│  │ 字段1: [________]               │ │
│  │ 字段2: [________]               │ │
│  │ ─────────────────────────────── │ │
│  │ [明细表1] [明细表2]  ← 视图切换   │ │
│  │ ─────────────────────────────── │ │
│  │ [新增] 明细表1列表               │ │
│  │ ┌───┬────┬────┐                │ │
│  │ │名称│日期│操作│                │ │
│  │ └───┴────┴────┘                │ │
│  │            [确认] [取消]        │ │
│  └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

### 5.2 Tab 切换模式（master-details-tabs）

```
┌─────────────────────────────────────┐
│  [新增] [导出]        [刷新] [列设置] │
├─────────────────────────────────────┤
│  主表列表（isType=1）                 │
│  ┌───┬───────┬───────┬───────────┐   │
│  │   │项目A  │进行中 │详情 编辑 删除│  │
│  └───┴───────┴───────┴───────────┘   │
├─────────────────────────────────────┤
│  点击「详情」→ isType=3              │
│  ┌─────────────────────────────────┐ │
│  │ [返回] 主表详情                  │ │
│  │ ─────────────────────────────── │ │
│  │ 名称: 项目A                      │ │
│  │ 状态: 进行中                     │ │
│  │ ─────────────────────────────── │ │
│  │ [明细表1] [明细表2]  ← Tab 切换   │ │
│  │ ─────────────────────────────── │ │
│  │ [新增] [导出] 明细表1            │ │
│  │ ┌───┬────┬────┐                │ │
│  │ │名称│日期│操作│                │ │
│  │ └───┴────┴────┘                │ │
│  └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

### 5.3 Tab + 弹窗模式（master-details-tabs-dialog）

```
┌─────────────────────────────────────┐
│  [新增] [导出]        [刷新] [列设置] │
├─────────────────────────────────────┤
│  主表列表（isType=1）                 │
│  ┌───┬───────┬───────┬───────────┐   │
│  │   │项目A  │进行中 │详情 编辑 删除│  │
│  └───┴───────┴───────┴───────────┘   │
├─────────────────────────────────────┤
│  点击「编辑」→ isType=2              │
│  ┌─────────────────────────────────┐ │
│  │ [返回] 编辑主表                  │ │
│  │ ─────────────────────────────── │ │
│  │ 字段1: [________]               │ │
│  │ ─────────────────────────────── │ │
│  │ [明细表1] [明细表2]  ← Tab 切换   │ │
│  │ ─────────────────────────────── │ │
│  │ [新增] [导出] 明细表1            │ │
│  │ ┌───┬────┬────────────┐        │ │
│  │ │名称│日期│    操作    │        │ │
│  │ │xx │xx  │详情 编辑 删除│        │ │
│  │ └───┴────┴────────────┘        │ │
│  │            [确认] [取消]        │ │
│  └─────────────────────────────────┘ │
│                                      │
│  点击明细「新增/编辑」→ el-dialog     │
│  ┌─────────────────────────┐        │
│  │ 新增明细表1       [×]    │        │
│  │ ─────────────────────── │        │
│  │ 名称: [________]        │        │
│  │ 日期: [________]        │        │
│  │ ─────────────────────── │        │
│  │ [附件上传区域]           │        │
│  │ ─────────────────────── │        │
│  │        [取消] [确认]    │        │
│  └─────────────────────────┘        │
└─────────────────────────────────────┘
```

---

## 六、Service 文件命名规范

### 8.1 核心原则

1. **`{{module}}` 占位符**: 在 `compute_output_path` 中会被替换为 `module.code`
2. **`{{module.code}}` 占位符**: 在 `compute_output_path` 中会被替换为 `module["code"]` 的值
3. **`{{group_code}}` 占位符**: **仅在模板内容中生效**，不在 `compute_output_path` 文件名替换中生效
4. **`module.js.j2`**: 特殊文件名，部分生成器会**硬编码检测**并特殊处理输出路径

### 8.2 生成器处理方式分类

#### 方式一：显式指定输出路径（推荐）

生成器代码显式指定模板路径和输出路径，模板文件名可以是任意值：

```python
# 示例：gen_master_detail_modules.py
master_svc_tpl = "service/{{module.master.code}}.js.j2"
master_svc_out = str(web_output / "service" / f"{master_code}.js")
web_renderer.render_to_file(master_svc_tpl, master_svc_out, web_context)
```

**适用模板**：
- `master-detail-modules` 系列
- `master-details-tabs` 系列
- `master-details-tabs-dialog` 系列

#### 方式二：硬编码检测特殊文件名

生成器检测 `module.js.j2` 文件名并特殊处理输出路径：

```python
# 示例：gen_multi_table.py
if Path(tpl).name == 'module.js.j2':
    output_path = str(module_output_dir / '05-web' / 'service' / f'{group_code}.js')
```

**适用模板**：
- `multi-table`
- `multi-table-with-file`

#### 方式三：render_all + compute_output_path

使用 `render_all` 方法批量渲染，依赖 `compute_output_path` 处理文件名占位符：

```python
# 示例：gen_master_detail.py
web_renderer = renderer_class(web_template_dir)
count = web_renderer.render_all(web_context, web_output)
```

**适用模板**：
- `master-detail`
- `master-detail-with-file`
- `single`
- `single-with-file`

### 8.3 各模板 Service 文件对照表

| 模板 | 模板文件名 | 输出文件名 | 处理方式 |
|------|-----------|-----------|---------|
| `single` | `{{module}}.js.j2` | `{code}.js` | render_all |
| `single-with-file` | `{{module}}.js.j2` | `{code}.js` | render_all |
| `master-detail` | `{{module.code}}.js.j2` | `{group_code}.js` | render_all |
| `master-detail-with-file` | `{{module.code}}.js.j2` | `{group_code}.js` | render_all |
| `master-detail-modules` | `{{group_code}}.js.j2` | `{group_code}.js` (merged) | 显式指定 |
| `master-detail-modules-with-file` | `{{group_code}}.js.j2` | `{group_code}.js` (merged) | 显式指定 |
| `master-details-tabs` | `{{group_code}}.js.j2` | `{group_code}.js` (merged) | 显式指定 |
| `master-details-tabs-with-file` | `{{group_code}}.js.j2` | `{group_code}.js` (merged) | 显式指定 |
| `master-details-tabs-dialog` | `{{group_code}}.js.j2` | `{group_code}.js` (merged) | 显式指定 |
| `master-details-tabs-dialog-with-file` | `module-service.js.j2` | `{group_code}.js` (merged) | 显式指定 |
| `multi-table` | `module.js.j2` | `{group_code}.js` (merged) | 硬编码检测 |
| `multi-table-with-file` | `module.js.j2` | `{group_code}.js` (merged) | 硬编码检测 |

---

## 七、Vue 模板 API 调用规范

### 8.1 合并 Service 文件的 API 方法命名

所有复合模板（主从/多表）生成的 `{group_code}.js` Service 文件，API 方法命名遵循以下规范：

| 操作类型 | 主表方法名 | 明细表方法名 |
|---------|-----------|-------------|
| 分页查询 | `getMasterList(params)` | `get{DetailCodePascal}List(params)` |
| 详情查询 | `getMasterDetail(id)` | `get{DetailCodePascal}Detail(id)` |
| 新增 | `addMaster(data)` | `add{DetailCodePascal}(data)` |
| 修改 | `updateMaster(data)` | `update{DetailCodePascal}(data)` |
| 删除 | `removeMaster(ids)` | `remove{DetailCodePascal}(ids)` |
| 导出 | `exportMaster(params)` | `export{DetailCodePascal}(params)` |
| 上传附件 | `uploadMaster(formData)` | `upload{DetailCodePascal}File(formData)` |
| 附件列表 | `getMasterFileList(id)` | `get{DetailCodePascal}FileList(id)` |
| 删除附件 | `removeMasterFile(ids)` | `remove{DetailCodePascal}File(ids)` |

### 8.2 Vue 组件 import 规范

```javascript
// ✅ 正确：统一使用 {{ group_code }}.js
import api from "@/service/{{ module.domain }}/{{ group_code }}.js"

// ❌ 错误：使用单独的 master/detail service
import masterApi from "@/service/{{ module.domain }}/{{ master_module.code }}.js"
import detailApi from "@/service/{{ module.domain }}/{{ detail_module.code }}.js"
```

### 8.3 API 调用示例

```javascript
// 主表操作
api.getMasterList(params)
api.getMasterDetail(id)
api.addMaster(data)
api.updateMaster(data)
api.removeMaster([id])

// 明细表操作（以 sample2result 为例）
api.getSample2resultList(params)
api.getSample2resultDetail(id)
api.addSample2result(data)
api.updateSample2result(data)
api.removeSample2result([id])
```

---

## 八、测试模块命名规范

### 8.1 编码规则

```
T{模式编号}{附件标识}
├── 模式编号: 01-12（对应上表）
└── 附件标识:
    - 0 = 无附件
    - 1 = 仅主表附件
    - 2 = 仅明细附件
    - 3 = 主表+明细都有
```

### 8.2 测试模块命名示例

> ⚠️ **命名规范**：编码不使用连字符，保证 Java 包名合法

| 编码 | 中文名称 | mode | 附件配置 |
|------|---------|------|---------|
| **单表系列** |
| t01 | 单表无附件 | single | — |
| t02 | 单表有附件 | single-with-file | ✓ |
| **主子表系列** |
| t03 | 主子表无附件 | master-detail | — |
| t040 | 主子表全无附件 | master-detail-with-file | 主× 明细× |
| t041 | 主子表主表附件 | master-detail-with-file | 主✓ 明细× |
| t042 | 主子表明细附件 | master-detail-with-file | 主× 明细✓ |
| t043 | 主子表全部附件 | master-detail-with-file | 主✓ 明细✓ |
| **多明细表系列** |
| t05 | 多明细无附件 | master-detail-modules | — |
| t060 | 多明细全无附件 | master-detail-modules-with-file | 主× 明细× |
| t061 | 多明细主表附件 | master-detail-modules-with-file | 主✓ 明细× |
| t062 | 多明细明细附件 | master-detail-modules-with-file | 主× 明细✓ |
| t063 | 多明细全部附件 | master-detail-modules-with-file | 主✓ 明细✓ |
| **Tab明细系列** |
| t07 | Tab明细无附件 | master-details-tabs | — |
| t080 | Tab明细全无附件 | master-details-tabs-with-file | 主× 明细× |
| t081 | Tab明细主表附件 | master-details-tabs-with-file | 主✓ 明细× |
| t082 | Tab明细明细附件 | master-details-tabs-with-file | 主× 明细✓ |
| t083 | Tab明细全部附件 | master-details-tabs-with-file | 主✓ 明细✓ |
| **Tab弹窗系列** |
| t09 | Tab弹窗无附件 | master-details-tabs-dialog | — |
| t100 | Tab弹窗全无附件 | master-details-tabs-dialog-with-file | 主× 明细× |
| t101 | Tab弹窗主表附件 | master-details-tabs-dialog-with-file | 主✓ 明细× |
| t102 | Tab弹窗明细附件 | master-details-tabs-dialog-with-file | 主× 明细✓ |
| t103 | Tab弹窗全部附件 | master-details-tabs-dialog-with-file | 主✓ 明细✓ |
| **多平级表系列** |
| t11 | 多平级无附件 | multi-table | — |
| t12 | 多平级有附件 | multi-table-with-file | ✓ |

### 8.3 配置文件命名

```
config/test/test-{mode}[-{file-strategy}].yml

示例：
- test-single.yml                    # T01
- test-single-with-file.yml          # T02
- test-master-detail-modules.yml     # T05
- test-master-detail-modules-with-file-master-only.yml   # T06-1
- test-master-detail-modules-with-file-detail-only.yml   # T06-2
- test-master-detail-modules-with-file-both-file.yml     # T06-3
```

---

## 九、重要提示

### ⚠️ 合并 Service 文件原则（2026-03-18 统一）

**所有复合模板（主从/多表）现在统一输出单个合并的 `{group_code}.js` 文件**，包含：
- 主表（Master）的所有 CRUD API
- 所有明细表（Detail Modules）的 CRUD API
- 附件相关 API（如适用）

### ⚠️ 不要随意修改 Service 模板文件名

1. **`module.js.j2`**: 生成器代码会**硬编码检测**这个文件名
2. **`module-service.js.j2`**: 生成器代码会**显式引用**这个文件名
3. **`{{group_code}}.js.j2`**: 生成器代码会**显式引用**这个文件名

### ⚠️ `{{group_code}}` 占位符的限制

- **模板内容中**：`{{ group_code }}` 可以正常使用（Jinja2 渲染）
- **文件名中**：`{{group_code}}.js.j2` **不会被 `compute_output_path` 替换**（需显式指定输出路径）

### 如果需要添加新的 Service 模板

1. 检查对应生成器 (`gen_*.py`) 中的处理逻辑
2. 确认使用哪种处理方式（显式指定 / 硬编码检测 / render_all）
3. 根据处理方式选择正确的文件名：
   - 显式指定：文件名任意（生成器代码中指定），推荐使用 `{{group_code}}.js.j2`
   - 硬编码检测：必须使用 `module.js.j2`
   - render_all：使用 `{{module}}.js.j2` 或 `{{module.code}}.js.j2`

---

## 十、变更记录

| 日期 | 变更内容 |
|------|---------|
| 2026-03-18 | 创建文档，说明 Service 文件命名规范与生成器处理逻辑 |
| 2026-03-18 | 修复 `master-detail` 和 `master-detail-with-file` 的 service 文件名（`module.js.j2` → `{{module.code}}.js.j2`） |
| 2026-03-18 | 修复 `master-details-tabs` 系列的 service 文件名（`{{group_code}}.js.j2` → `{{module.master.code}}.js.j2`） |
| 2026-03-18 | **统一合并 Service 输出**: 所有复合模板统一输出单个 `{group_code}.js` |
| 2026-03-18 | **统一 Vue 模板 API 调用**: 修复 API 方法命名不一致问题 |
| 2026-03-18 | **新增测试模块命名规范**: 定义 t01-t12 编码规则与配置文件命名规范 |
| 2026-03-18 | **统一小写命名**: 配置文件名、模块 code、sub_tables code 统一使用小写（t01/t02/.../t12） |
| 2026-03-25 | **[FEATURE] 状态切换功能**: 新增可选的 `status_toggles` 配置，支持在列表页生成状态切换按钮，自动生成前端 `toggle()` API 和后端 `/toggle` 接口。功能完全可选，不配置则不生成相关代码。支持主表和明细表独立配置。见本文档"状态切换功能"章节。 |
| 2026-03-25 | **[REFACTOR] status_toggles 配置位置重构**: 移除模块级 status_toggles 自动继承逻辑，master/detail/sub_tables 需要各自独立配置。见 **[归档 31](archive/31.status_toggles配置位置重构.md)**。 |
| 2026-03-26 | **[ENHANCE] 批量操作功能增强**: 所有模板新增彻底删除/批量删除/批量彻底删除/批量更新功能，删除改为逻辑删除（is_deleted=1），级联删除子表及附件，见 **[归档 32](archive/32.批量操作功能增强与物理删除分离.md)**。 |
| 2026-03-31 | **[ENHANCE] 批量更新多字段弹窗模式改造**: `batch_operations.update` 从单字段一键更新改为多字段弹窗表单模式，配置格式从 `field/default_value/confirm_message` 改为 `name/type/required/options` + 顶层 `confirm_message`，前端从多按钮改为单按钮弹窗，后端入参从 `{ids, field, value}` 改为 `{ids, data: Map}`，见 **[归档 36](archive/36.批量更新多字段弹窗模式改造.md)**。 |
