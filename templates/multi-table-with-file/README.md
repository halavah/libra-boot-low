# multi-table-with-file 模板

## 模式说明

- **适用**: 多个平级独立业务表，Tab 切换展示，每个子表各带 1:N 附件从表
- **接口数**: 9×N 个（每子表 6 个标准接口 + 3 个附件接口）+ 可选 toggle 接口
- **关联生成器**: `module/gen_multi_table_with_file.py`

## 可选功能：状态切换（status_toggles）

**每个 sub_table 均支持独立配置**，不再从模块级继承。

详见 `templates/multi-table/README.md`。

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
│   ├── api.md                    （9×N 接口）
│   ├── database.md               （N 主表 + N 附件表）
│   └── ui.md                     （Tab 切换 + 上传组件）
├── 02-sql/
│   ├── group_enum.md             （含各子表 fileType 枚举，合并）
│   ├── group_exec.sql            （2N 个建表语句，子表 + 附件表）
│   └── group_mock.sql            （子表测试数据）
├── 02-sql-scripts/
├── 03-http/
│   └── group.http                （9×N 段，所有子表合并）
├── 03-http-scripts/
│   └── test_{module}.txt         （上传测试文件）
├── 04-page-scripts/
│   └── index.test.js             （2 Suite / 7 Test）
├── 04-server/                    ⚠️ 扁平化，N 个子表文件同层
│   ├── controller/
│   │   ├── {Domain}{Sub1}Controller.java    （含附件3接口）
│   │   └── ...
│   ├── entity/
│   │   ├── param/
│   │   │   ├── {Domain}{Sub1}Param.java
│   │   │   ├── {Domain}{Sub1}FileParam.java
│   │   │   └── ...
│   │   ├── po/
│   │   │   ├── Biz{Domain}{Sub1}.java
│   │   │   ├── Biz{Domain}{Sub1}File.java
│   │   │   └── ...
│   │   └── vo/
│   │       ├── {Domain}{Sub1}VO.java        （含 fileList）
│   │       ├── {Domain}{Sub1}FileVO.java
│   │       └── ...
│   ├── mapper/
│   │   ├── {Domain}{Sub1}Mapper.java
│   │   ├── {Domain}{Sub1}FileMapper.java
│   │   ├── ...
│   │   └── xml/
│   │       ├── {Domain}{Sub1}Mapper.xml
│   │       └── ...
│   └── service/
│       ├── I{Domain}{Sub1}Service.java
│       ├── ...
│       └── impl/
│           ├── {Domain}{Sub1}ServiceImpl.java （含MinIO+级联删除）
│           └── ...
├── 05-web/
│   ├── service/{module}.js       （N×9 API 合并）
│   └── views/
│       ├── index.vue
│       ├── {module}-{sub1}.vue
│       ├── {module}-{sub1}-add-or-edit.vue   （含 el-upload）
│       ├── {module}-{sub1}-detail.vue
│       └── ...（其他子表）
└── AGENT.md
```

## 模板文件清单

每个子表使用相同模板，通过上下文变量循环渲染（含附件相关文件）：

| 模板文件 | 输出文件 | 说明 |
|---------|---------|------|
| `04-server/controller/DomainModuleController.java.j2` | `{Domain}{Sub}Controller.java` | 控制器（含附件3接口） |
| `04-server/entity/po/BizDomainModule.java.j2` | `Biz{Domain}{Sub}.java` | 子表实体 |
| `04-server/entity/po/BizDomainModuleFile.java.j2` | `Biz{Domain}{Sub}File.java` | 附件表实体 |
| `04-server/entity/vo/DomainModuleVO.java.j2` | `{Domain}{Sub}VO.java` | 子表VO（含fileList） |
| `04-server/entity/vo/DomainModuleFileVO.java.j2` | `{Domain}{Sub}FileVO.java` | 附件VO |
| `04-server/entity/param/DomainModuleParam.java.j2` | `{Domain}{Sub}Param.java` | 子表入参 |
| `04-server/entity/param/DomainModuleFileParam.java.j2` | `{Domain}{Sub}FileParam.java` | 附件入参 |
| `04-server/mapper/DomainModuleMapper.java.j2` | `{Domain}{Sub}Mapper.java` | 子表Mapper |
| `04-server/mapper/DomainModuleFileMapper.java.j2` | `{Domain}{Sub}FileMapper.java` | 附件Mapper |
| `04-server/mapper/xml/DomainModuleMapper.xml.j2` | `{Domain}{Sub}Mapper.xml` | MyBatis XML |
| `04-server/service/IDomainModuleService.java.j2` | `I{Domain}{Sub}Service.java` | 服务接口 |
| `04-server/service/impl/DomainModuleServiceImpl.java.j2` | `{Domain}{Sub}ServiceImpl.java` | 服务实现 |

## 目录结构规范

⚠️ **扁平化结构**：N 个子表的主表文件和附件文件统一在同一层

```
✅ 正确
04-server/entity/po/
├── BizDemoDemo1.java
├── BizDemoDemo1File.java
├── BizDemoDemo2.java
├── BizDemoDemo2File.java
└── BizDemoDemo3.java

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
| `module.file_types` | 当前子表的附件类型列表 |
| `has_file` | 固定为 `true` |
| `group_code` | 模块组代码 |
| `sub_tables` | 所有子表配置列表（index.vue 使用） |
| `fields` | 当前子表字段列表 |

## 变更记录
### 2026-03-30


### 2026-03-26


### 2026-03-25


### 2026-03-10

1. **[FIX] 网关前缀**: `service.js.j2` 添加 `const SVC = '/layer/v1/sys-service'`，修复 401 路由匹配失败。

