# Design 0015：PostgreSQL 审核目录与运行时 Repository

- 日期：2026-07-30
- 状态：已实施并验证
- 影响范围：Go 配置与启动、知识库 schema、目录导入、评测命令、Docker 制品和生产部署
- 前置设计：
  - `0005-go-recognition-and-knowledge-backend.md`
  - `0008-database-first-recognition-candidates.md`
  - `0013-postgresql-container-foundation.md`

## 背景

生产 Go API 当前通过 `NewEmbeddedRepository` 读取编译进二进制的
`internal/knowledge/data/objects.v1.json`。PostgreSQL 18.4 已运行，但数据库尚无业务表，API 也没有
注入 `DATABASE_URL`。

本次把 `reviewed-catalog-v1` 的 3 个审核对象、别名、地域和来源导入 PostgreSQL，并把 API 与评测命令的
运行时 Repository 切换到 PostgreSQL。

## 数据源边界

- `objects.v1.json` 继续作为首批审核目录的版本化导入源，只供数据库导入命令和单元测试使用。
- 生产 API 和 `cmd/eval` 不再调用 `NewEmbeddedRepository`。
- 生产运行必须提供 `DATABASE_URL`；缺失、连接失败、无 active catalog 或目录为空时启动失败。
- 不实现“PG 失败后回退内嵌 JSON”，避免同一版本在不同请求中使用不同事实源。
- 模型生成结果仍不能写回审核表；本次运行账号只有只读权限。

## 依赖与工具

- PostgreSQL driver/pool：`github.com/jackc/pgx/v5`，锁定明确版本。
- SQL 生成：sqlc，配置 `sql_package: pgx/v5`，生成代码提交仓库。
- 迁移：Tern v2 library，迁移文件嵌入数据库命令二进制。
- 新增 `cmd/db`：
  - `migrate`：只执行 schema migration。
  - `seed-reviewed-catalog`：幂等导入内嵌审核目录。
  - `up`：依次执行 migrate 和 seed，作为部署入口。

Docker 最终镜像同时包含 `culturelens-api` 与 `culturelens-db`；默认入口仍是 API，迁移通过覆盖 entrypoint
执行。

## Schema

### `knowledge_catalogs`

记录目录发布版本：

```text
version TEXT PK
source_sha256 TEXT
is_active BOOLEAN
object_count INTEGER
imported_at TIMESTAMPTZ
```

部分唯一索引保证同一时刻最多一个 active catalog。

### `knowledge_nodes`

复用 0005 的统一节点方向，本次只写入 `node_type = object`：

```text
id UUID PK
catalog_version TEXT FK
node_type TEXT
canonical_name TEXT
normalized_name TEXT
category TEXT
summary TEXT
detail TEXT
time_period TEXT
region TEXT
artwork_symbol TEXT
status TEXT
content_version BIGINT
created_at TIMESTAMPTZ
updated_at TIMESTAMPTZ
```

识别候选只读取 active catalog 中 `node_type = object AND status = reviewed` 的节点。

### 别名、地域与来源

```text
knowledge_aliases
  id UUID PK
  node_id UUID FK
  alias_text TEXT
  normalized_alias TEXT
  locale TEXT
  sort_order INTEGER

knowledge_geographies
  node_id UUID FK
  geography_kind TEXT  # region_code | city
  value TEXT
  normalized_value TEXT
  sort_order INTEGER

knowledge_sources
  id UUID PK
  title TEXT
  publisher TEXT
  url TEXT

node_sources
  node_id UUID FK
  source_id UUID FK
  evidence_note TEXT
  sort_order INTEGER
```

别名 ID 由节点 UUID 与 normalized alias 确定性生成，重复导入不会产生新行。外键明确定义级联删除边界。
`sort_order` 保留审核目录中的人工顺序，避免数据库聚合改变 API 输出顺序。

## 导入语义

导入在单个事务中完成：

1. 解析并执行现有目录校验，非法 UUID、类别、重复名称、地域或来源使导入失败。
2. 对原始 JSON 计算 SHA-256，写入 catalog metadata。
3. 先停用旧 catalog，再激活本次版本。
4. 对节点和来源 upsert；别名、地域、node-source 关联按对象替换。
5. 删除同一 catalog 中已不在源文件的对象、旧 inactive catalog 遗留节点和无引用来源；旧版本只保留
   catalog metadata，不保留可能与 active catalog 冲突的别名。
6. 校验数据库对象数量等于源目录对象数量后提交。

重复执行 `up` 必须保持 3 个对象及相同关联数，不重复数据。

## Repository 查询

sqlc 查询直接在 PostgreSQL 计算地域分数并限制候选：

- 城市命中 300。
- 国家或地区代码命中 200。
- 无地域限制节点 100。
- 有命中时排除明确属于其他地区的节点。
- 完全无命中时回退 active catalog 全目录。
- 最多返回 12 项，同分按规范名排序。

别名、地域和来源通过 PostgreSQL 聚合结果组装回现有 `knowledge.Object`，保持 Pipeline 和 iOS JSON 契约
不变。`catalogVersion`、候选数、`ExcludedByLocation` 和 `OrderChanged` 行为与内存实现一致。

连接池上限 4、最小连接 1；启动使用 5 秒超时完成 `Ping` 和 active catalog 统计。日志只记录
`repository=postgresql`、目录版本和对象数，不记录连接 URL 或密码。

## 账号与权限

- `culturelens_admin`：数据库和 `public` schema 所有者，执行 migration/seed。
- `culturelens_app`：只保留 CONNECT、schema USAGE 和知识表 SELECT；不拥有数据库或业务表。
- `/opt/culturelens/database-admin.env`：只供一次性迁移容器，`root:root` / `0600`。
- `/opt/culturelens/database.env`：API 只读连接，`root:root` / `0600`。

生产 API 同时读取原 `/opt/culturelens/.env` 和 `database.env`，不会把数据库秘密复制进镜像。

## 部署顺序

1. 对切换前数据库执行 `pg_dump`，保存 root-only 备份。
2. 构建并验证包含 API/DB 两个二进制的新镜像。
3. 使用管理员连接运行 `culturelens-db up`。
4. 校验目录、节点、别名、地域、来源数量及只读账号权限。
5. 停止并保留旧 API 容器，创建新容器但暂不启动。
6. 新容器同时附加 bridge 和 `culturelens-db`，注入两个 env 文件后启动。
7. 验证启动日志显示 PostgreSQL active catalog、容器健康、公网 `/health` 和 API 错误契约。

## 测试

- 单元测试继续验证目录源文件与内存参考算法。
- 真实 PostgreSQL 集成测试覆盖 migration、幂等 seed、CN/JP/未知地区、limit、来源组装和空库失败。
- 本地 Mock API 使用 PostgreSQL 完成 HTTP 冒烟。
- `go test ./...`、`go vet ./...`、sqlc 重新生成无 diff、Docker build 与容器测试通过。
- 生产查询确认 active catalog 为 `reviewed-catalog-v1`、对象数为 3，API 启动日志确认使用 PostgreSQL。

## 回滚

- 停止新 API，恢复保留的旧容器；旧镜像仍读取内嵌目录，因此数据库迁移不影响回滚。
- PostgreSQL 表和备份保留，不执行 down migration、不删除数据卷。
- 修复后可以重复执行幂等 `culturelens-db up` 再切换。

## 实施结果

- 锁定 `github.com/jackc/pgx/v5 v5.10.0`、`github.com/jackc/tern/v2 v2.4.1` 和
  sqlc v1.31.1；sqlc 生成代码已进入 `internal/database/dbgen`。
- Tern schema version 1 已在生产执行；`culturelens-db up` 可重复运行，节点 `content_version` 在数据
  未改变时保持不变。
- `reviewed-catalog-v1` 已导入生产 PG：catalog/node/alias/geography/source/node-source 数量分别为
  `1/3/6/5/4/4`，source SHA-256 为
  `70cbd2ec3257d1c88d4795b5d0245d198a6a8b5abfb10d4f831ab6f235105fc3`。
- `culturelens_admin` 已成为数据库、schema 和业务表所有者；`culturelens_app` 对知识表只有 SELECT，
  INSERT/UPDATE/DELETE 均为 false。
- 切换前备份保存于
  `/opt/culturelens/backups/culturelens-pre-pg-repository-20260730T1845.dump`，为
  `root:root` / `0600`。
- 新镜像 ID 为 `sha256:709a31e858858e2885b1dbe49bc688d4b9357818077855eaac5bc81cee169826`，
  包含 `culturelens-api` 和 `culturelens-db`，仍以 UID/GID `10001` 运行。
- 镜像已推送至 `ccr.ccs.tencentyun.com/gouzuang/culturelens:latest`，registry digest 为
  `sha256:4602f5196e962052382fd1f228d2d8b06443f6388997663478f458ccec976625`。
- 生产 API 启动日志显示
  `repository=postgresql catalog_version=reviewed-catalog-v1 catalog_objects=3`；PG
  `pg_stat_activity` 确认 `culturelens_app` / `culturelens-api` 连接池会话存在。
- 新 API 和 PG 容器均为 `healthy`；公网 `/health` 返回 200、OpenAPI 3.1 正常、空识别请求继续返回
  既有 400 `invalid_request` envelope。
- 旧 API 容器保留为停止状态的 `culturelens-rollback-pg`。

## 2026-08-01 生产知识数据清理

用户判定现有资料质量不足后，生产环境执行一次可恢复的数据清理。这是运维数据变更，不修改数据库
schema 或 Repository 合约。

- 清理前数量：catalog/node/alias/geography/source/node-source/edge/edge-source 为
  `1/3/6/5/4/4/0/0`。
- 在单个事务中 `TRUNCATE` 八张知识表；清理后八表均为 0，Tern schema version 仍为 2。
- 数据库实例、schema、角色、权限和持久化数据卷全部保留。
- 清理前 custom-format 备份保存于
  `/opt/culturelens/backups/culturelens-pre-knowledge-clear-20260801T140123.dump`，属主/权限为
  `root:root` / `0600`，大小 29183 bytes，SHA-256 为
  `9ff3fcaea239276d2c6176260733d7c6ec14ad1859330cfff6ab4d0f211a9be8`，已通过
  `pg_restore --list` 验证。
- 现有 API 进程保持运行，因此 `/health` 和 `/debug` 仍可访问；实际知识查询已分别返回
  `knowledge_unavailable` 或 `object_not_found`。
- Repository 启动约束仍要求非空 active catalog，所以在导入新的已审核目录前不应重启 API。
- 代码库内嵌 seed 仍包含原 3 个样例；在完成质量复核和替换前不得运行 `culturelens-db up`，
  否则会将已清理资料重新导入生产。
