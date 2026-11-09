# single-with-file 模板

## 模式说明

- **适用**: 单表业务 + 1:N 附件从表（独立 `_file` 表）
- **接口数**: 9 个（标准 6 + 附件 3：upload / file/list / file/remove）+ 可选 toggle 接口
- **关联生成器**: `module/gen_single_with_file.py`

## 可选功能：状态切换（status_toggles）

与 `single` 模板完全一致，详见 `templates/single/README.md`。

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
│   ├── {module}_exec.sql        （主表 + _file 附件表）
│   └── {module}_mock.sql
├── 02-sql-scripts/
├── 03-http/
│   └── {module}.http            （9 段）
├── 03-http-scripts/
│   └── test_{module}.txt        （上传测试文件）
├── 04-page-scripts/
│   └── index.test.js            （2 Suite / 7 Test）
├── 04-server/
│   ├── controller/
│   │   └── DomainModuleController.java      （含附件3接口）
│   ├── entity/
│   │   ├── param/
│   │   │   ├── DomainModuleParam.java
│   │   │   └── DomainModuleFileParam.java
│   │   ├── po/
│   │   │   ├── BizDomainModule.java
│   │   │   └── BizDomainModuleFile.java
│   │   └── vo/
│   │       ├── DomainModuleVO.java          （含 fileList）
│   │       └── DomainModuleFileVO.java
│   ├── mapper/
│   │   ├── DomainModuleMapper.java
│   │   ├── DomainModuleFileMapper.java
│   │   └── xml/DomainModuleMapper.xml
│   └── service/
│       ├── IDomainModuleService.java
│       └── impl/DomainModuleServiceImpl.java （含 MinIO 上传+级联删除）
├── 05-web/
│   ├── service/{module}.js
│   └── views/
│       ├── index.vue
│       ├── {module}-add-or-edit.vue         （含 el-upload）
│       └── {module}-detail.vue              （含附件列表展示）
└── AGENT.md
```

## 模板文件清单

| 模板文件 | 输出文件 | 说明 |
|---------|---------|------|
| `04-server/controller/DomainModuleController.java.j2` | `{Domain}{Module}Controller.java` | 控制器（含附件3接口） |
| `04-server/entity/po/BizDomainModule.java.j2` | `Biz{Domain}{Module}.java` | 主表实体 |
| `04-server/entity/po/BizDomainModuleFile.java.j2` | `Biz{Domain}{Module}File.java` | 附件表实体 |
| `04-server/entity/vo/DomainModuleVO.java.j2` | `{Domain}{Module}VO.java` | 主表VO（含fileList） |
| `04-server/entity/vo/DomainModuleFileVO.java.j2` | `{Domain}{Module}FileVO.java` | 附件VO |
| `04-server/entity/param/DomainModuleParam.java.j2` | `{Domain}{Module}Param.java` | 主表入参 |
| `04-server/entity/param/DomainModuleFileParam.java.j2` | `{Domain}{Module}FileParam.java` | 附件入参 |
| `04-server/mapper/DomainModuleMapper.java.j2` | `{Domain}{Module}Mapper.java` | 主表Mapper |
| `04-server/mapper/DomainModuleFileMapper.java.j2` | `{Domain}{Module}FileMapper.java` | 附件Mapper |
| `04-server/mapper/xml/DomainModuleMapper.xml.j2` | `{Domain}{Module}Mapper.xml` | MyBatis XML |
| `04-server/service/IDomainModuleService.java.j2` | `I{Domain}{Module}Service.java` | 服务接口 |
| `04-server/service/impl/DomainModuleServiceImpl.java.j2` | `{Domain}{Module}ServiceImpl.java` | 服务实现 |

## 命名规则

`DomainModule` 占位符在渲染时替换为 `{DomainPascal}{ModulePascal}`，例如：

| 模板文件名 | 输出文件名（demo/basic） |
|-----------|----------------------|
| `BizDomainModule.java.j2` | `BizDemoBasic.java` |
| `BizDomainModuleFile.java.j2` | `BizDemoBasicFile.java` |
| `DomainModuleFileVO.java.j2` | `DemoBasicFileVO.java` |

## 目录结构规范

⚠️ **扁平化结构**：所有文件直接放在 `controller/`、`entity/`、`mapper/`、`service/` 下

❌ **禁止**：在 `04-server/` 下创建子模块目录（如 `04-server/basic/`）

## 上下文变量

| 变量 | 说明 |
|------|------|
| `module.*` | 同 single 模式 |
| `module.file_types` | 附件类型列表 `[{code, label}]` |
| `has_file` | 固定为 `true` |
| `fields` | 字段列表 |

## 变更记录
### 2026-03-30


### 2026-03-26


### 2026-03-25


### 2026-03-10

1. **[FIX] 网关前缀**: `service.js.j2` 添加 `const SVC = '/layer/v1/sys-service'`，修复 401 路由匹配失败。