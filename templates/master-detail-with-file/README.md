# master-detail-with-file 模板

## 模式说明

- **适用**: 主从关系业务，1:N 主子表，明细需要附件上传
- **接口数**: 15 个（主表 6 + 明细 6 + 明细附件 3）+ 可选 toggle 接口
- **关联生成器**: `module/gen_master_detail_file.py`

## 可选功能：状态切换（status_toggles）

**master 和 detail 均支持独立配置**，不再从模块级继承。

详见 `templates/master-detail/README.md`。

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
│       ├── {module}-{master}.vue
│       ├── {module}-{master}-add-or-edit.vue
│       └── ...
├── 01-design/
│   ├── api.md                    （15 接口）
│   ├── database.md               （主表 + 明细表 + 附件从表）
│   └── ui.md
├── 02-sql/
│   ├── group_enum.md             （合并主表、明细和附件的枚举，含 fileType）
│   ├── group_exec.sql            （主表 + 明细 + 附件从表建表语句）
│   └── group_mock.sql            （主表 + 明细测试数据）
├── 02-sql-scripts/
├── 03-http/
│   ├── master.http               （主表 6 段）
│   └── detail.http               （明细 9 段，含附件 3 段）
├── 03-http-scripts/
│   └── test_{module}.txt         （上传测试文件）
├── 04-page-scripts/
│   └── index.test.js             （2 Suite / 9 Test）
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

主表文件用 `Master` 前缀，明细文件（含附件）用 `Detail` 前缀，渲染时自动去掉前缀：

| 模板文件 | 输出文件 | 上下文 |
|---------|---------|--------|
| `controller/MasterDomainModuleController.java.j2` | `{Domain}{Master}Controller.java` | master_context |
| `controller/DetailDomainModuleController.java.j2` | `{Domain}{Detail}Controller.java` | detail_context |
| `entity/po/MasterBizDomainModule.java.j2` | `Biz{Domain}{Master}.java` | master_context |
| `entity/po/DetailBizDomainModule.java.j2` | `Biz{Domain}{Detail}.java` | detail_context |
| `entity/po/DetailBizDomainModuleFile.java.j2` | `Biz{Domain}{Detail}File.java` | detail_context |
| `entity/vo/MasterDomainModuleVO.java.j2` | `{Domain}{Master}VO.java` | master_context |
| `entity/vo/DetailDomainModuleVO.java.j2` | `{Domain}{Detail}VO.java` | detail_context |
| `entity/vo/DetailDomainModuleFileVO.java.j2` | `{Domain}{Detail}FileVO.java` | detail_context |
| `entity/param/MasterDomainModuleParam.java.j2` | `{Domain}{Master}Param.java` | master_context |
| `entity/param/DetailDomainModuleParam.java.j2` | `{Domain}{Detail}Param.java` | detail_context |
| `entity/param/DetailDomainModuleFileParam.java.j2` | `{Domain}{Detail}FileParam.java` | detail_context |
| `mapper/MasterDomainModuleMapper.java.j2` | `{Domain}{Master}Mapper.java` | master_context |
| `mapper/DetailDomainModuleMapper.java.j2` | `{Domain}{Detail}Mapper.java` | detail_context |
| `mapper/DetailDomainModuleFileMapper.java.j2` | `{Domain}{Detail}FileMapper.java` | detail_context |
| `service/IMasterDomainModuleService.java.j2` | `I{Domain}{Master}Service.java` | master_context |
| `service/IDetailDomainModuleService.java.j2` | `I{Domain}{Detail}Service.java` | detail_context |
| `service/impl/MasterDomainModuleServiceImpl.java.j2` | `{Domain}{Master}ServiceImpl.java` | master_context |
| `service/impl/DetailDomainModuleServiceImpl.java.j2` | `{Domain}{Detail}ServiceImpl.java` | detail_context |

## 命名规则

`Detail*File*` 文件名同样经过 `compute_output_path` 处理：

- `DetailBizDomainModuleFile.java.j2` → `BizDemoResultFile.java`（移除 Detail，保留 File）
- `DetailDomainModuleFileVO.java.j2` → `DemoResultFileVO.java`

## 上下文变量

| 变量 | 说明 |
|------|------|
| `module` | 当前渲染子模块 |
| `master_module` | 主表模块信息 |
| `detail_module` | 明细表模块信息 |
| `module.file_types` | 附件类型列表（detail 轮次可用） |
| `has_file` | 固定为 `true` |
| `module.master_fk` | 明细表外键字段名 |

## 变更记录
### 2026-03-30


### 2026-03-26


### 2026-03-25


### 2026-03-18

1. **[DOCS] 扁平化结构说明重构**: 统一 README 生成产物章节格式，新增 05-web 单一 Service 文件规范，明确禁止子模块目录和分散 API 文件。

### 2026-03-17


### 2026-03-10

1. **[FIX] 网关前缀**: `service.js.j2` 添加 `const SVC = '/layer/v1/sys-service'`，修复 401 路由匹配失败。
