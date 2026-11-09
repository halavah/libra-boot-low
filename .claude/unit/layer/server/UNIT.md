# unit/layer/server — 服务端单元测试规范

## 目录结构

```
server/
├── 00-inbox/          待处理输入区（外部提供的需求/数据/临时文件）
├── 01-design/         设计文档（api.md / database.md / model.md / ui.md）
├── 02-sql/            SQL 数据文件（server_mock_*.sql / server_exec.sql / server_enum.md）
├── 02-sql-scripts/    SQL 执行脚本（run_mock.* / run_redis.*）
├── 03-http/           HTTP 测试文件（*.http，REST Client 格式）
├── 03-http-scripts/   HTTP 测试脚本（test_mock.* / gen_mock.*）
├── 04-web-ht-scripts/ H5 页面测试（Playwright + .env）
├── 04-web-pc-scripts/ PC 页面测试（Playwright + .env）
├── 05-exec/           SQL 执行区（exec/临时 / struc/表结构 / test/测试数据）
├── 05-jmeter/         压力测试（references/参考文档 / script/K6脚本）
├── 05-page/           页面手册/操作文档/截图
└── UNIT.md            本文件
```

## 运行模式

| 模式 | 含义 | 命令 |
|------|------|------|
| 0 | 表结构+数据 | `./run_mock 0 --yes` |
| 1 | 仅表结构 | `./run_mock 1 --yes` |
| 2 | 仅数据 | `./run_mock 2 --yes` |

## 注意事项

- `02-sql-scripts/run_mock.*` 为主入口，双平台（sh/ps1）
- `server_mock_00_sys_user.sql` 是固定用户文件，禁止修改
- `05-exec/exec/` 中的 SQL 执行后移入 `bak/`
- HTTP/页面测试默认不执行，明确要求时才触发
