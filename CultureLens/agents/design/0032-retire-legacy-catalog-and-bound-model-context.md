# 0032 退役旧知识目录并限制模型上下文

- 日期：2026-08-02
- 状态：数据库与后端旧 catalog 依赖已清理并部署
- 影响范围：Go 数据库查询、识别 Repository/管线、PostgreSQL 旧表、生产部署
- 前置设计：`0031-attraction-rooted-multihop-cultural-graph.md`

## 问题

生产数据库仍保留 migration 001/002 创建的 8 张旧 `knowledge_*` / source 关联表。它们已经全部为空，公开 API 和当前识别流程使用的是 `cultural_elements`、`cultural_element_relations`、`attractions` 与 `attraction_cultural_introductions`，但后端启动统计、旧 Repository 方法、seed 命令和 sqlc 查询仍引用旧表，导致空表无法安全删除。

0031 首次部署还把每个候选的完整 3 跳图谱装入 Repository 结果。虽然 provider 输入映射目前只取候选正文和现场介绍，但扩充后的候选/现场上下文仍使两次生产 Gemini 请求在 55–60 秒超时，业务返回 504；普通 `/health` 无法反映该故障。

## 决策

1. 删除后端对旧 catalog 的启动查询、`Candidates` / `RelatedObjects` PostgreSQL 实现、seed 命令、旧 SQL 与生成代码；API 只依赖当前文化内容模型。
2. 新增一次真实 schema 清理 migration，删除确认为空且无运行时依赖的 8 张旧表：`edge_sources`、`knowledge_edges`、`node_sources`、`knowledge_sources`、`knowledge_geographies`、`knowledge_aliases`、`knowledge_nodes`、`knowledge_catalogs`。这次 migration 只用于真实表结构退役，不用于内容数据修改。
3. provider 输入保持最多 12 个紧凑候选；每个候选只发送自身简介和有界现场上下文，不发送多跳图谱。完整图谱只在 provider 选出景点/元素之后由后端用于组装公开响应。
4. 对每个候选最多发送 2 条现场上下文，并将富文本转为有长度上限的纯文本，避免内容继续增长时再次拖垮模型调用。
5. `/health` 继续表示进程/数据库就绪；部署验证必须额外执行一次不含用户照片的完整识别冒烟测试。

## 部署与回滚

- 先部署不再引用旧表的新镜像并完成完整识别冒烟，再执行表退役 migration；生产变更前创建可恢复备份。
- 表均为空，回滚数据风险低；若必须回滚旧镜像，则应先恢复迁移前备份，因为旧镜像启动仍查询 `knowledge_catalogs`。
- 失败的 0031 容器停止保留；当前生产已先回滚到部署前镜像恢复识别。

## 最终生产处理

- 用户明确要求本轮只重新处理数据库，不再混入识别候选或图谱逻辑。含识别改动的新镜像未部署，schema v7 migration 未在生产执行。
- 2026-08-02 14:31 生产备份为 `/opt/culturelens/backups/culturelens-pre-legacy-table-drop-20260802T143058.dump`，权限 `root:root/0600`，SHA-256 `930bc08fdfb16eb01a980178d29e19de0780580f75b2540cff9348767c3cff92`，并通过 `pg_restore --list` 校验。
- 生产确认 8 张旧表均为 0 行后，在单个事务中直接删除；生产现只保留 6 张基础表：4 张文化内容表、`recognition_request_logs` 与 `culturelens_schema_version`。
- 当前稳定二进制曾在启动时读取旧 catalog 统计，临时使用 `knowledge_catalogs`、`knowledge_nodes` 两个零行兼容视图；首次视图漏列导致稳定容器启动失败并自动重试 10 次，补齐后恢复。
- 随后重构后端，删除旧启动统计查询、旧 Repository/seed/sqlc 代码，并恢复与当前稳定生产版一致的候选输入排序；真实 PostgreSQL 验证 8 个旧 relation 为 0、基础表为 6。
- 最终 linux/amd64 镜像 `20260802-db-cleanup-only`（ID `sha256:c114e01388dcb668b9ae9613bd1d50d22ccf5bf283a2ff0e05df746c6cadee0c`，registry digest `sha256:184a43b0112e1cae0464de068da691f2eab0ef014a9b9c6dec7d6099cfdf7196`）已部署；两个临时兼容视图已删除。
- 生产 `public` schema 中不存在任何 `knowledge_*` relation，只保留 6 张有效基础表。新容器在完全没有旧表/视图时重启成功，healthy、restartCount=0，本机及公网 `/health` 均为 200。

## 验证

- `rg` 确认生产 Go 代码和 sqlc 查询不再引用 8 张旧表。
- Go 全量测试、vet、schema v7 PostgreSQL 集成测试通过。
- 生产备份通过 `pg_restore --list`；迁移后只保留 4 张文化内容表、识别审计表与 schema 版本表。
- 新容器 healthy、restartCount=0，公网健康 200，完整识别冒烟 200 且耗时低于后端超时。
