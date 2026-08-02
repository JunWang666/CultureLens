# Design 0016：关联对象与粗粒度位置推荐 API

- 日期：2026-07-30
- 状态：已实施并部署
- 影响范围：Go KnowledgeRepository、PostgreSQL schema/query、HTTP API、OpenAPI 和测试
- 前置设计：
  - `0004-directed-cultural-knowledge-graph.md`
  - `0008-database-first-recognition-candidates.md`
  - `0015-postgresql-reviewed-catalog-repository.md`

## 背景

App 目前只能在识别流程内部使用审核对象目录，尚不能：

1. 从一个稳定文化对象 ID 查询明确审核过的关联对象。
2. 独立请求与用户粗粒度位置相关的审核对象推荐。

本次把两项能力作为只读知识 API 暴露。接口与识别管线共用同一个 PostgreSQL
`KnowledgeRepository` 和 active catalog，不增加第二份事实数据源。

## API

### 关联对象

```http
GET /v1/objects/{objectID}/related?limit=12
```

- `objectID` 必须是 active catalog 中 `reviewed object` 的 UUID。
- `limit` 默认 12，范围 1...20。
- 同时查询以该对象为起点和终点的显式关系。
- 每项返回关联对象、关系方向、稳定关系种类、解释和关系来源。
- 起点存在但没有审核关系时返回 `200` 和空 `relatedObjects`。
- 对象不存在返回 `404 object_not_found`。
- 不按类别、名称、地域或模型输出临时猜测关系。

响应中的 `direction` 以请求对象为视角：

- `outgoing`：请求对象是 `sourceObjectID`。
- `incoming`：请求对象是 `targetObjectID`。

### 位置推荐

```http
GET /v1/objects/recommendations?cityName=上海市&regionCode=CN&limit=12
```

- `cityName` 与 `regionCode` 至少提供一项。
- `cityName` 只接受城市或同等级名称，最长 80 字符且禁止控制字符。
- `regionCode` 是两位 ISO 风格大写地区码。
- `limit` 默认 12，范围 1...20。
- 排序继续使用 0015 已确认的审核地域标签：城市命中优先、地区码命中其次、无地域限制对象再次。
- 无任何地域命中时返回全目录稳定回退，并以 `matchStatus = catalogFallback` 明示；不能伪装成位置命中。
- 有地域命中时返回 `matchStatus = matched`。

本接口不接收经纬度。当前知识表只有城市和地区标签，没有可信对象坐标或覆盖范围；在加入审核坐标、
距离语义和必要的空间索引前，不提供“附近多少公里”能力。

## 公共响应模型

新接口使用与现有 iOS 契约一致的 camelCase 字段。对象包括：

- `id`
- `canonicalName`
- `aliases`
- `category`
- `summary`
- `timePeriod`
- `region`
- `artworkSymbol`
- `geography`
- `sources`

位置推荐响应还包含：

- `catalogVersion`
- `requestedLocation`
- `matchStatus`
- `totalObjects`
- `excludedByLocation`
- `objects`

关联对象响应还包含：

- `catalogVersion`
- `object`
- `relatedObjects`

关系项包括：

- `id`
- `sourceObjectID`
- `targetObjectID`
- `kind`
- `explanation`
- `direction`
- `sources`

## PostgreSQL 数据结构

新增 migration 2：

```text
knowledge_edges
  id UUID PK
  catalog_version TEXT FK
  source_id UUID FK knowledge_nodes
  target_id UUID FK knowledge_nodes
  relation_kind TEXT
  explanation TEXT
  status TEXT
  content_version BIGINT
  created_at TIMESTAMPTZ
  updated_at TIMESTAMPTZ

edge_sources
  edge_id UUID FK knowledge_edges
  source_id UUID FK knowledge_sources
  evidence_note TEXT
  sort_order INTEGER
```

只有 active catalog 中两个端点均为 `reviewed object` 且边本身为 `reviewed` 时才对外返回。
`edge_sources` 保留关系级证据，不能用节点来源替代关系来源。

内嵌审核目录顶层增加可选 `relations` 数组，供 `cmd/db seed-reviewed-catalog` 幂等导入。当前 3 个样例对象
没有足够依据建立对象间关系，因此数组保持为空；不能为演示接口而制造事实。

## Repository

现有 `Repository` 增加：

```go
RelatedObjects(ctx, objectID, limit) (RelatedObjectSet, error)
```

`Candidates` 继续作为位置排序的唯一实现，HTTP 推荐接口只做参数校验与公共响应映射，避免识别候选和推荐
产生两套地域规则。内存 Repository 与 PostgreSQL Repository 必须保持相同关系方向、限制和稳定排序语义。

## 错误与安全

- 所有响应继续携带 `X-Request-ID`。
- `400 invalid_request`：UUID、位置或 limit 非法。
- `404 object_not_found`：active/reviewed 对象不存在。
- `503 knowledge_unavailable`：Repository 查询失败。
- 日志只记录 request ID、目录版本、结果数、match status，不记录数据库连接信息。
- 接口只读；模型输出、识别结果和客户端输入都不能写入关系表。

## 验证

- Memory Repository：双向关系方向、稳定排序、limit、缺失对象。
- PostgreSQL 集成测试：migration 2、空关系、插入审核关系后双向查询、关系来源组装。
- API 合约：推荐命中、目录回退、参数错误、对象不存在、空关联和带关系响应。
- OpenAPI 3.1/3.0：两个新路径、参数、200/400/404/503。
- `go test ./...` 和 `go vet ./...`。

## 部署注意

生产部署需先执行 `culturelens-db migrate`。migration 会在 `culturelens_app` 已存在时自动授予新增表的
`SELECT`，切换新 API 镜像前仍需验证 schema version 和表权限。

## 单页调试台

后端提供 `GET /debug`，返回一份编译进 Go 二进制的静态 HTML，不引入 Node 构建链或额外静态文件部署：

- “关联对象”区域填写稳定 object UUID 和 limit，请求当前服务的
  `/v1/objects/{objectID}/related`。
- “位置推荐”区域填写 cityName、regionCode 和 limit，请求当前服务的
  `/v1/objects/recommendations`。
- 页面展示实际请求 URL、HTTP 状态、`X-Request-ID`、耗时和格式化 JSON。
- 默认 object UUID 使用审核目录中的斗拱 ID，位置使用 `CN`，方便打开页面后直接发起请求。
- 请求只发往同源相对路径，不允许页面填写其他主机，避免把调试台变成任意请求代理。
- 页面不保存输入、不包含数据库或模型凭据，也不提供写接口。
- `/debug` 是开发和运维辅助入口，不写入 OpenAPI 业务契约。

## 部署结果

- 2026-08-01 使用隔离 PostgreSQL 18.4 容器验证新镜像：migration/seed 返回 schema v2、3 个审核对象，
  `/health`、`/debug`、关联对象和位置推荐接口均为 200；临时容器与网络已清理。
- 生产迁移前备份保存为
  `/opt/culturelens/backups/culturelens-pre-related-debug-20260801T1346.dump`，权限为
  `root:root` / `0600`，SHA-256 为
  `418d98d025279b9be245f71107f9c1397a2d3653a041e9f7a2bb9b0cb8255abf`，`pg_restore --list`
  可正常读取。
- 生产 PostgreSQL 已升级至 schema v2；`knowledge_edges` / `edge_sources` 均为空，符合当前 seed；
  `culturelens_app` 对两表只有 `SELECT`。
- 生产镜像 ID 为
  `sha256:7b6b06c34581b4b6bc7248fe88c35f4823ce863bedebf8228946e65d69183bf8`，唯一标签为
  `20260801-related-debug`；腾讯云仓库 `latest` digest 为
  `sha256:f5264bdb00028156b9cd47a480cf45564b0d31e778e8ea20a2d4a92690b07848`。
- 新 `culturelens` 容器保持 `unless-stopped`、8080 端口和 `bridge + culturelens-db` 双网络，状态为
  `healthy`；旧容器保留为停止状态的 `culturelens-rollback-pre-related-debug-20260801`。
- 公网 `https://cl.codight.online/health`、`/debug`、两个知识接口和 OpenAPI 均验证通过；空识别请求仍返回
  既有 400 `invalid_request` envelope。
