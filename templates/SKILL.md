---
name: update-readme
description: 规范和约束修改低代码模板代码后，更新各模板 README 变更记录的动作。
---

# 🔧 角色设定与任务规则：低代码模板变更日志维护器

你在帮生成器或用户修改低代码模板代码（位于 `.claude/scripts/low-code-generator/templates` 目录下的 12 种模板）后，**必须且强制**执行以下 README 变更记录（Changelog）的更新补充工作，绝不能遗漏。

## 📍 目标范围
你要修改的 README 文件固定为以下 12 个：
1. `templates/single/README.md`
2. `templates/single-with-file/README.md`
3. `templates/master-detail/README.md`
4. `templates/master-detail-with-file/README.md`
5. `templates/master-detail-modules/README.md`
6. `templates/master-detail-modules-with-file/README.md`
7. `templates/master-details-tabs/README.md`
8. `templates/master-details-tabs-with-file/README.md`
9. `templates/master-details-tabs-dialog/README.md`
10. `templates/master-details-tabs-dialog-with-file/README.md`
11. `templates/multi-table/README.md`
12. `templates/multi-table-with-file/README.md`

*(注意：如果本次变动仅影响部分模板，则只更新受影响模板的 README)*

## 📝 记录格式要求
每次变更完成后，请定位到 README 文件末尾的 `## 变更记录` 区域，并在当天的日期节点下，**追加最新的流水号和变更说明**。格式必须严格遵照如下标准：

1. **流水号递增**：读取当前列表最后的序号 `N`，新加的一行必须是 `N+1.`。
2. **操作类型标签**：必须包含加粗的类型标签：
   - `**[FIX]**`：用于漏洞、BUG、报错修复
   - `**[ENHANCE]**`：用于新增功能、交互优化、能力增强
   - `**[REFACTOR]**`：用于代码重构、性能优化
3. **变更概要**：用最精简的词句总结（如 `全字段搜索（前端）`）。
4. **变更详情**：具体指明修改了哪个模板组件（如 `index.vue.j2`）、做了什么改动（如 `引入 fileExport 工具函数`）、解决了什么业务问题。


**标准示例：**

## ⚙️ 你的执行动作
当你完成任何针对涉及 templates 的代码修改并验证后：
1. 确定你准备更新的 README 文件列表。
2. 在 `archive/` 目录同步创建/完善技术归档。
3. 生成包含归档链接的单行日志文本。
4. 使用集成工具统一更新 README 文件。
