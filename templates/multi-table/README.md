# multi-table 模板

## 模式说明

- **适用**: 多个平级独立业务表，Tab 切换展示，各表无外键关联，无附件
- **接口数**: 6×N 个（每子表 6 个标准接口）+ 可选 toggle 接口
- **关联生成器**: `module/gen_multi_table.py`

## 可选功能：状态切换（status_toggles）

**每个 sub_table 均支持独立配置**，不再从模块级继承。

### 配置位置

| 表 | 配置位置 |
|---|---------|
| 子表 | `sub_tables[].status_toggles` |

### 配置示例

```yaml
modules:
  - name: "多平级表"
    code: "jsnjs"
    mode: "multi-table"
    sub_tables:
      - code: "jsjc"
        name: "技能竞赛"
        status_toggles:                  # 子表1独立配置
          - field: "status"
            values: { "0": "未开始", "1": "进行中", "2": "已结束" }
            colors: { "0": "info", "1": "warning", "2": "success" }
        fields: [...]
      - code: "gpln"
        name: "岗位练兵"
        # 子表2无状态切换（可选）
        fields: [...]
```

### 生成产物

| 有 status_toggles | 无 status_toggles |
|------------------|-------------------|
| 子表 `toggle()` API | 不生成 toggle API |
| 子表 `/toggle` 接口 | 不生成 toggle 接口 |

## ⚠️ 网关前缀（Gateway Prefix）

前端 service 文件的 API 路径**必须**携带网关路由前缀 `/layer/v1/sys-service`，否则请求经过 Vite proxy → Gateway 后无法匹配路由，返回 **401 Access Denied**。

```javascript
// ✅ 正确（本模板已使用此格式）
const SVC = '/layer/v1/sys-service'
// URL: `${SVC}{{ st.module.api_path }}/list`

// ❌ 错误（缺少网关前缀，Gateway 无法路由）
// URL: `/{{ module.domain }}/{{ module.code }}/list`
```

请求链路：`浏览器 /api/layer/v1/sys-service/...` → `Vite proxy 去掉 /api` → `Gateway 匹配 /layer/v1/sys-service/** 路由` → `StripPrefix=3 转发后端`

## 生成产物

```
out/{domain}/{module}/
├── 01-design/
│   ├── api.md                    （6×N 接口）
│   ├── database.md               （N 个独立表）
│   └── ui.md                     （Tab 切换）
├── 02-sql/
│   ├── group_enum.md             （合并所有子表枚举）
│   ├── group_exec.sql            （N 个建表语句）
│   └── group_mock.sql            （N×25 测试数据）
├── 02-sql-scripts/
├── 03-http/
│   └── group.http                （6×N 段，所有子表合并）
├── 03-http-scripts/
├── 04-page-scripts/
│   └── index.test.js             （N Suite / 7N Test）
├── 04-server/                    ⚠️ 扁平化，N 个子表文件同层
│   ├── controller/
│   │   ├── {Domain}{Sub1}Controller.java
│   │   ├── {Domain}{Sub2}Controller.java
│   │   └── ...
│   ├── entity/
│   │   ├── param/
│   │   │   ├── {Domain}{Sub1}Param.java
│   │   │   └── ...
│   │   ├── po/
│   │   │   ├── Biz{Domain}{Sub1}.java
│   │   │   └── ...
│   │   └── vo/
│   │       ├── {Domain}{Sub1}VO.java
│   │       └── ...
│   ├── mapper/
│   │   ├── {Domain}{Sub1}Mapper.java
│   │   ├── ...
│   │   └── xml/
│   │       ├── {Domain}{Sub1}Mapper.xml
│   │       └── ...
│   └── service/
│       ├── I{Domain}{Sub1}Service.java
│       ├── ...
│       └── impl/
│           ├── {Domain}{Sub1}ServiceImpl.java
│           └── ...
├── 05-web/
│   ├── service/{module}.js       （N 个子表 API）
│   └── views/
│       ├── index.vue             （el-tabs 切换）
│       ├── {module}-{sub1}.vue
│       ├── {module}-{sub1}-add-or-edit.vue
│       ├── {module}-{sub1}-detail.vue
│       └── ...（其他子表）
└── AGENT.md
```

## 模板文件清单

每个子表使用相同模板，通过上下文变量（`module` = 各子表信息）循环渲染：

| 模板文件 | 输出文件 | 说明 |
|---------|---------|------|
| `04-server/controller/DomainModuleController.java.j2` | `{Domain}{Sub}Controller.java` | 子表控制器 |
| `04-server/entity/po/BizDomainModule.java.j2` | `Biz{Domain}{Sub}.java` | 子表实体 |
| `04-server/entity/vo/DomainModuleVO.java.j2` | `{Domain}{Sub}VO.java` | 子表VO |
| `04-server/entity/param/DomainModuleParam.java.j2` | `{Domain}{Sub}Param.java` | 子表入参 |
| `04-server/mapper/DomainModuleMapper.java.j2` | `{Domain}{Sub}Mapper.java` | 子表Mapper |
| `04-server/mapper/xml/DomainModuleMapper.xml.j2` | `{Domain}{Sub}Mapper.xml` | MyBatis XML |
| `04-server/service/IDomainModuleService.java.j2` | `I{Domain}{Sub}Service.java` | 服务接口 |
| `04-server/service/impl/DomainModuleServiceImpl.java.j2` | `{Domain}{Sub}ServiceImpl.java` | 服务实现 |
| `05-web/views/sub-list.vue.j2` | `{module}-{sub}.vue` | 子表列表 |
| `05-web/views/sub-add-or-edit.vue.j2` | `{module}-{sub}-add-or-edit.vue` | 子表表单 |
| `05-web/views/sub-detail.vue.j2` | `{module}-{sub}-detail.vue` | 子表详情 |
| `05-web/views/index.vue.j2` | `index.vue` | Tab 入口（含所有子表） |
| `05-web/service/module.js.j2` | `{module}.js` | 所有子表 API 合并 |

## 命名规则

- 生成器对每个 `sub_table` 独立调用 `render_all`，每次传入该子表的上下文
- `DomainModule` 占位符替换为各子表的 `{DomainPascal}{SubPascal}`

## 目录结构规范

⚠️ **扁平化结构**：N 个子表文件统一放在 `04-server/{controller|entity|mapper|service}/` 同一层

```
✅ 正确
04-server/
├── controller/
│   ├── DemoDemo1Controller.java
│   ├── DemoDemo2Controller.java
│   └── DemoDemo3Controller.java

❌ 禁止（子模块目录）
04-server/
├── demo1/    ← 禁止！
├── demo2/     ← 禁止！
└── demo3/  ← 禁止！
```

## 上下文变量

| 变量 | 说明 |
|------|------|
| `module` | 当前子表模块信息（循环每次切换） |
| `group_code` | 模块组代码 |
| `group_name` | 模块组名称 |
| `sub_tables` | 所有子表配置列表（index.vue 使用） |
| `fields` | 当前子表字段列表 |

## 变更记录
### 2026-03-30


### 2026-03-26


### 2026-03-25


### 2026-03-10

1. **[FIX] 网关前缀**: `service.js.j2` 添加 `const SVC = '/layer/v1/sys-service'`，修复 401 路由匹配失败。

