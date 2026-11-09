# single 模板

## 模式说明

- **适用**: 简单单表业务，无附件，无主子表关系
- **接口数**: 6 个（list / detail / add / update / remove / export）
- **关联生成器**: `module/gen_single.py`

## ⚠️ 网关前缀（Gateway Prefix）

前端 service 文件的 API 路径**必须**携带网关路由前缀 `/layer/v1/sys-service`，否则请求经过 Vite proxy → Gateway 后无法匹配路由，返回 **401 Access Denied**。

```javascript
// ✅ 正确
const SVC = '/layer/v1/sys-service'
const BASE_URL = `${SVC}/{{ module.domain }}/{{ module.code }}`

// ❌ 错误（缺少网关前缀，Gateway 无法路由）
const BASE_URL = '/{{ module.domain }}/{{ module.code }}'
```

请求链路：`浏览器 /api/layer/v1/sys-service/...` → `Vite proxy 去掉 /api` → `Gateway 匹配 /layer/v1/sys-service/** 路由` → `StripPrefix=3 转发后端`

## 生成产物

```
out/{domain}/{module}/
├── 01-design/
│   ├── api.md
│   ├── database.md
│   └── ui.md
├── 02-sql/
│   ├── {module}_enum.md
│   ├── {module}_exec.sql
│   └── {module}_mock.sql
├── 02-sql-scripts/
│   ├── run_mock.sh / .ps1 / .py
│   └── run_mock.md
├── 03-http/
│   └── {module}.http
├── 03-http-scripts/
│   ├── test_mock.sh / .ps1 / .py
│   ├── gen_mock.sh / .ps1
│   └── test_{module}.txt
├── 04-page-scripts/
│   ├── playwright.config.js
│   ├── auth.setup.js
│   ├── index.test.js
│   └── run_page_test.*
├── 04-server/
│   ├── controller/
│   │   └── DomainModuleController.java
│   ├── entity/
│   │   ├── param/  DomainModuleParam.java
│   │   ├── po/     BizDomainModule.java
│   │   └── vo/     DomainModuleVO.java
│   ├── mapper/
│   │   ├── DomainModuleMapper.java
│   │   └── xml/DomainModuleMapper.xml
│   └── service/
│       ├── IDomainModuleService.java
│       └── impl/DomainModuleServiceImpl.java
├── 05-web/
│   ├── service/{module}.js
│   └── views/
│       ├── index.vue
│       ├── {module}-add-or-edit.vue
│       └── {module}-detail.vue
└── AGENT.md
```

## 模板文件清单

| 模板文件 | 输出文件 | 说明 |
|---------|---------|------|
| `04-server/controller/DomainModuleController.java.j2` | `{Domain}{Module}Controller.java` | 控制器（6接口） |
| `04-server/entity/po/BizDomainModule.java.j2` | `Biz{Domain}{Module}.java` | 实体类 |
| `04-server/entity/vo/DomainModuleVO.java.j2` | `{Domain}{Module}VO.java` | 输出对象 |
| `04-server/entity/param/DomainModuleParam.java.j2` | `{Domain}{Module}Param.java` | 入参对象 |
| `04-server/mapper/DomainModuleMapper.java.j2` | `{Domain}{Module}Mapper.java` | Mapper 接口 |
| `04-server/mapper/xml/DomainModuleMapper.xml.j2` | `{Domain}{Module}Mapper.xml` | MyBatis XML |
| `04-server/service/IDomainModuleService.java.j2` | `I{Domain}{Module}Service.java` | 服务接口 |
| `04-server/service/impl/DomainModuleServiceImpl.java.j2` | `{Domain}{Module}ServiceImpl.java` | 服务实现 |
| `05-web/service/module.js.j2` | `{module}.js` | API 服务 |
| `05-web/views/index.vue.j2` | `index.vue` | 列表页 |
| `05-web/views/add-or-edit.vue.j2` | `{module}-add-or-edit.vue` | 表单页 |
| `05-web/views/detail.vue.j2` | `{module}-detail.vue` | 详情页 |

## 命名规则

| 类型 | 模板占位符 | 示例（demo/basic） |
|------|-----------|------------------|
| Controller | `DomainModuleController` | `DemoBasicController` |
| PO | `BizDomainModule` | `BizDemoBasic` |
| VO | `DomainModuleVO` | `DemoBasicVO` |
| Param | `DomainModuleParam` | `DemoBasicParam` |
| Mapper | `DomainModuleMapper` | `DemoBasicMapper` |
| Service | `IDomainModuleService` | `IDemoBasicService` |
| ServiceImpl | `DomainModuleServiceImpl` | `DemoBasicServiceImpl` |

## 目录结构规范

⚠️ **扁平化结构**：所有文件直接放在 `controller/`、`entity/`、`mapper/`、`service/` 下

❌ **禁止**：在 `04-server/` 下创建子模块目录（如 `04-server/basic/`）

## 上下文变量

| 变量 | 说明 | 示例 |
|------|------|------|
| `module.code` | 模块代码 | `basic` |
| `module.name` | 模块名称 | `荣誉申报` |
| `module.domain` | 业务域 | `demo` |
| `module.code_pascal` | Pascal 命名 | `Basic` |
| `module.domain_pascal` | 域 Pascal 命名 | `Demo` |
| `module.table_name` | 表名 | `biz_demo_basic` |
| `module.api_path` | API 路径 | `/demo/basic` |
| `module.package_path` | 包路径 | `demo.basic` |
| `module.status_toggles` | 状态切换配置（可选） | `[{field, values, colors}]` |
| `module.has_status_toggles` | 是否有状态切换 | `true/false` |
| `fields` | 字段列表 | `[{name, label, type, ...}]` |
| `project` | 项目信息 | `{name, code, version}` |
| `has_date_field` | 是否含 date 字段 | `true/false` |
| `has_datetime_field` | 是否含 datetime 字段 | `true/false` |

## 可选功能：状态切换（status_toggles）

在 YAML 配置中添加 `status_toggles` 节，自动生成状态切换按钮和相关接口。

### 配置示例

```yaml
modules:
  - name: "荣誉申报"
    code: "basic"
    mode: "single"
    status_toggles:                    # 可选，不配置则不生成
      - field: "status"                # 状态字段名
        label: "状态"                  # 中文标签
        values:
          "0": "禁用"                  # 值 → 按钮文本
          "1": "启用"
        colors:
          "0": "danger"                # 值 → 按钮颜色
          "1": "success"
    fields:
      - name: "status"
        label: "状态"
        type: "select"
        options:
          - label: "禁用"
            value: 0
          - label: "启用"
            value: 1
```

### 生成产物

| 有 status_toggles | 无 status_toggles |
|------------------|-------------------|
| 前端 `toggle(data)` API | 不生成 toggle API |
| 后端 `/toggle` 接口 | 不生成 toggle 接口 |
| 后端 `toggleStatus()` 方法 | 不生成 toggle 方法 |
| 列表切换按钮 + `handleToggle` | 不生成切换按钮 |

## 变更记录
### 2026-03-30


### 2026-03-26


### 2026-03-25


### 2026-03-10

1. **[FIX] 网关前缀**: `service.js.j2` 添加 `const SVC = '/layer/v1/sys-service'`，修复 401 路由匹配失败。