# master-detail 模板

## 模式说明

- **适用**: 主从关系业务，1:N 主子表，明细无附件
- **接口数**: 12 个（主表 6 + 明细表 6）+ 可选 toggle 接口
- **关联生成器**: `module/gen_master_detail.py`

## 可选功能：状态切换（status_toggles）

**master 和 detail 均支持独立配置**，不再从模块级继承：

```yaml
modules:
  - name: "主子表"
    code: "sample2"
    mode: "master-detail"
    # 模块级 status_toggles 不再自动继承到 master/detail
    master:
      code: "talent"
      status_toggles:                  # 主表独立配置
        - field: "status"
          values: { "0": "草稿", "1": "进行中", "2": "已完成" }
          colors: { "0": "info", "1": "warning", "2": "success" }
    detail:
      code: "result"
      status_toggles:                  # 明细表独立配置（可选）
        - field: "itemStatus"
          values: { "0": "未开始", "1": "已完成" }
          colors: { "0": "info", "1": "success" }
```

| 配置位置 | 生成产物 |
|---------|---------|
| `master.status_toggles` | 主表 toggle API + 按钮代码 |
| `detail.status_toggles` | 明细表 toggle API + 按钮代码 |

> ⚠️ **注意**: 模块级 `status_toggles` 不再自动继承，需要在 master/detail 各自配置。

## ⚠️ 网关前缀（Gateway Prefix）

前端 service 文件的 API 路径**必须**携带网关路由前缀 `/layer/v1/sys-service`，否则请求经过 Vite proxy → Gateway 后无法匹配路由，返回 **401 Access Denied**。

```javascript
// ✅ 正确
const SVC = '/layer/v1/sys-service'
const BASE_URL = `${SVC}/{{ module.domain }}/{{ group_code }}/{{ master_module.code }}`

// ❌ 错误（缺少网关前缀，Gateway 无法路由）
const BASE_URL = '/{{ module.domain }}/{{ group_code }}/{{ master_module.code }}'
```

请求链路：`浏览器 /api/layer/v1/sys-service/...` → `Vite proxy 去掉 /api` → `Gateway 匹配 /layer/v1/sys-service/** 路由` → `StripPrefix=3 转发后端`

## 生成产物

```
out/{domain}/{module}/
├── 01-design/
│   ├── api.md                    （12 接口）
│   ├── database.md               （主表 + 明细表）
│   └── ui.md
├── 02-sql/
│   ├── group_enum.md             （合并主表和明细的枚举）
│   ├── group_exec.sql            （主表 + 明细建表语句）
│   └── group_mock.sql            （主表 + 明细测试数据）
├── 02-sql-scripts/
├── 03-http/
│   ├── master.http               （主表 6 段）
│   └── detail.http               （明细 6 段）
├── 03-http-scripts/
├── 04-page-scripts/
│   └── index.test.js             （2 Suite / 9 Test）
├── 04-server/                    ⚠️ 扁平化，主表和明细同层
│   ├── controller/
│   │   ├── {Domain}{Master}Controller.java
│   │   └── {Domain}{Detail}Controller.java
│   ├── entity/
│   │   ├── param/
│   │   │   ├── {Domain}{Master}Param.java
│   │   │   └── {Domain}{Detail}Param.java
│   │   ├── po/
│   │   │   ├── Biz{Domain}{Master}.java
│   │   │   └── Biz{Domain}{Detail}.java
│   │   └── vo/
│   │       ├── {Domain}{Master}VO.java
│   │       └── {Domain}{Detail}VO.java
│   ├── mapper/
│   │   ├── {Domain}{Master}Mapper.java
│   │   ├── {Domain}{Detail}Mapper.java
│   │   └── xml/
│   │       ├── {Domain}{Master}Mapper.xml
│   │       └── {Domain}{Detail}Mapper.xml
│   └── service/
│       ├── I{Domain}{Master}Service.java
│       ├── I{Domain}{Detail}Service.java
│       └── impl/
│           ├── {Domain}{Master}ServiceImpl.java
│           └── {Domain}{Detail}ServiceImpl.java
├── 05-web/
│   ├── service/{module}.js       （合并 API，使用 {group_code} 命名）
│   └── views/
│       ├── index.vue
│       ├── {module}-{master}.vue              （主表列表）
│       ├── {module}-{master}-add-or-edit.vue  （主表表单）
│       ├── {module}-{master}-detail.vue       （主表详情）
│       ├── {module}-add-or-edit.vue           （明细表单，无子代码前缀）
│       └── {module}-detail.vue                （明细详情，无子代码前缀）
└── AGENT.md
```

## 目录结构规范

### ⚠️ 04-server 扁平化结构

**主表和明细表所有文件统一放在 `04-server/{controller|entity|mapper|service}/` 下**

```
✅ 正确
04-server/
├── controller/
│   ├── DemoTalentController.java
│   └── DemoResultController.java
├── entity/po/
│   ├── BizDemoTalent.java
│   └── BizDemoResult.java
└── ...

❌ 禁止（子模块目录）
04-server/
├── talent/    ← 禁止！
└── result/    ← 禁止！
```

### ⚠️ 05-web 单一 Service 文件

**所有 API 合并到单个 `{group_code}.js` 文件**

```
✅ 正确
05-web/service/
└── sample2.js     ← 单一文件，包含主表 + 明细 API

❌ 禁止（分散文件）
05-web/service/
├── talent.js   ← 禁止！
└── result.js   ← 禁止！
```

## 模板文件清单

模板文件通过 `Master`/`Detail` 前缀区分主表和明细，渲染时自动去掉前缀：

| 模板文件 | 输出文件 | 上下文 |
|---------|---------|--------|
| `controller/MasterDomainModuleController.java.j2` | `{Domain}{Master}Controller.java` | master_context |
| `controller/DetailDomainModuleController.java.j2` | `{Domain}{Detail}Controller.java` | detail_context |
| `entity/po/MasterBizDomainModule.java.j2` | `Biz{Domain}{Master}.java` | master_context |
| `entity/po/DetailBizDomainModule.java.j2` | `Biz{Domain}{Detail}.java` | detail_context |
| `entity/vo/MasterDomainModuleVO.java.j2` | `{Domain}{Master}VO.java` | master_context |
| `entity/vo/DetailDomainModuleVO.java.j2` | `{Domain}{Detail}VO.java` | detail_context |
| `entity/param/MasterDomainModuleParam.java.j2` | `{Domain}{Master}Param.java` | master_context |
| `entity/param/DetailDomainModuleParam.java.j2` | `{Domain}{Detail}Param.java` | detail_context |
| `mapper/MasterDomainModuleMapper.java.j2` | `{Domain}{Master}Mapper.java` | master_context |
| `mapper/DetailDomainModuleMapper.java.j2` | `{Domain}{Detail}Mapper.java` | detail_context |
| `mapper/xml/MasterDomainModuleMapper.xml.j2` | `{Domain}{Master}Mapper.xml` | master_context |
| `mapper/xml/DetailDomainModuleMapper.xml.j2` | `{Domain}{Detail}Mapper.xml` | detail_context |
| `service/IMasterDomainModuleService.java.j2` | `I{Domain}{Master}Service.java` | master_context |
| `service/IDetailDomainModuleService.java.j2` | `I{Domain}{Detail}Service.java` | detail_context |
| `service/impl/MasterDomainModuleServiceImpl.java.j2` | `{Domain}{Master}ServiceImpl.java` | master_context |
| `service/impl/DetailDomainModuleServiceImpl.java.j2` | `{Domain}{Detail}ServiceImpl.java` | detail_context |
| `05-web/service/{{module.code}}.js.j2` | `{group_code}.js` | web_context（合并） |

## 命名规则

生成器通过 `render_all_with_prefix` 按文件名前缀分两轮渲染：

1. 前缀 `Master` / `IMaster` → 使用 `master_context`（`module` = master_module）
2. 前缀 `Detail` / `IDetail` → 使用 `detail_context`（`module` = detail_module）

`compute_output_path` 会自动移除路径中的 `Master`/`Detail`/`IMaster`/`IDetail` 前缀，最终文件名形如 `DemoTalentController.java`。

## 上下文变量

| 变量 | 说明 |
|------|------|
| `module` | 当前渲染的子模块（master 轮次为主表，detail 轮次为明细） |
| `master_module` | 主表模块信息（两轮均可访问） |
| `detail_module` | 明细表模块信息（两轮均可访问） |
| `master_fields` | 主表字段列表 |
| `detail_fields` | 明细表字段列表 |
| `group_code` | 模块组代码（如 `sample2`） |
| `group_name` | 模块组名称 |
| `module.master_fk` | 明细表外键字段名（如 `talentId`） |

## 变更记录
### 2026-03-30


### 2026-03-26


### 2026-03-25


### 2026-03-18

2. **[DOCS] README 扁平化重构**: 更新目录结构说明，明确 04-server 扁平化和 05-web 单一 Service 规范。

### 2026-03-10

1. **[FIX] 网关前缀**: `service.js.j2` 添加 `const SVC = '/layer/v1/sys-service'`，修复 401 路由匹配失败。
