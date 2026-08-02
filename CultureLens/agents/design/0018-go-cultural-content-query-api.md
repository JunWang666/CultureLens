# Design 0018：Go 文化元素与精确位置查询

- 日期：2026-08-01
- 状态：已实施并部署
- 影响范围：Go Repository、PostgreSQL/sqlc 查询、HTTP API、OpenAPI、单页调试台和测试
- 前置设计：
  - `0016-related-objects-and-location-recommendations-api.md`
  - `0017-cultural-elements-and-attraction-introductions.md`

## 背景

migration 3 已把通用文化元素和景点特定介绍分离，但 Go 后端仍在查询旧
`knowledge_nodes/knowledge_edges/knowledge_geographies`，并只支持城市/地区标签排序。旧生产目录已清空，
所以服务重启还会因“没有非空 active catalog”失败。

## 新查询合约

### 文化元素关联

```http
GET /v1/cultural-elements/{elementKey}/related?limit=12
```

- `elementKey` 使用 migration 3 定义的稳定文本 key，不再要求 UUID。
- 先查询起点元素；不存在返回 `404 cultural_element_not_found`。
- 同时匹配 `element_key` 和 `related_element_key`，对外作为无向关联。
- 结果按名称、key 稳定排序；无关联时返回 200 和非 null 空数组。
- 返回文化元素的 `key`、`name`、`introduction`，不再编造旧模型才有的方向、关系解释或来源。

### 附近景点特定介绍

```http
GET /v1/attraction-introductions/recommendations
    ?latitude=30.248963
    &longitude=120.148691
    &radiusMeters=5000
    &limit=12
```

- `latitude` / `longitude` 必填并验证为有限数和 WGS84 合法范围。
- `radiusMeters` 默认 5000，范围 1...50000；`limit` 默认 12，范围 1...20。
- PostgreSQL 使用 Haversine 大圆距离，地球平均半径取 6371008.8 米；不将经纬度差直接当作平面距离。
- 只返回半径内结果，按 `distanceMeters`、名称、key 稳定排序，没有匹配时返回 200 和空数组，
  不做全库回退。
- 每项包含景点特定介绍、关联文化元素、关联景点、原始坐标和计算距离。

## 响应模型

```text
CulturalElement
  key
  name
  introduction

AttractionIntroductionRecommendation
  key
  name
  introduction
  culturalElement { key, name }
  attraction { key, name }
  location { latitude, longitude }
  distanceMeters
```

富文本 `introduction` 原样输出为 JSON object，不在 Go 查询层转换为 HTML。

## 路径切换

- 删除旧 `GET /v1/objects/{objectID}/related` 和 `GET /v1/objects/recommendations` 业务路由及 OpenAPI 文档。
- 不将旧路径做成响应字段完全不同的隐式别名，避免旧客户端将新数据误解为旧 object 模型。
- `/debug` 改为输入元素 key 和精确经纬度，只请求新路径。

## Repository 与启动

- 保留原 `Repository.Candidates` 供识别管线过渡使用，新增独立 `ContentRepository`，避免把识别候选的旧字段
  伪造到新文化元素模型。
- PostgreSQL Repository 实现两个接口，共用同一连接池和 sqlc queries。
- 启动时必须能读取 migration 3 的新表；新表可以为空。
- 旧 active catalog 缺失不再阻止 API 启动；此时识别管线返回现有 503，但 `/health`、`/debug` 和新内容查询
  仍可用。
- 新查询只需 `culturelens_app` SELECT，不增加运行时写权限。

## 错误与日志

- `400 invalid_request`：key、经纬度、radius 或 limit 非法。
- `404 cultural_element_not_found`：文化元素不存在。
- `503 knowledge_unavailable`：PostgreSQL 查询失败。
- 日志记录 request ID、element key、结果数、请求半径，不记录数据库 URL。

## 验证

- Repository/API 测试覆盖富文本 JSON、非 null 空数组、limit、距离米数、新路径
  200/400/404/503 以及旧路径 404。
- OpenAPI 3.1/3.0 与调试页已切到新查询合约。
- `go test -count=1 ./...` 与 `go vet ./...` 通过。
- 隔离 PostgreSQL 18.4 容器中串行运行数据库集成测试通过：覆盖无向关联双向读取、元素 404、Haversine
  距离排序、半径过滤、limit 下的 `totalMatches`，以及空旧 catalog 可启动而识别候选不可用。
- 临时 PostgreSQL 容器已停止并自动删除。

## 部署结果

- 2026-08-01 生产迁移前备份保存于
  `/opt/culturelens/backups/culturelens-pre-cultural-content-20260801T152503.dump`，权限为
  `root:root` / `0600`，大小 27683 bytes，SHA-256 为
  `17f46641feb87a8923733b6b31f4eaec48b0b838c7ff1c1e9ec9c68f176070ec`，并通过 `pg_restore --list` 校验。
- 生产 PostgreSQL 已升级到 schema v3；4 张新表计数均为 0，`culturelens_app` 对新表只有 `SELECT`。
- 生产镜像 ID 为 `sha256:ed61bb759f5087f307cb09af91f6776913d45cc32c8f557cd44fd4c5d2f47ad4`，
  唯一标签为 `20260801-cultural-content`；腾讯云仓库唯一标签和 `latest` digest 均为
  `sha256:2eff818f83125c297ca21486486a51164b24095e0e9038e73977b214c6b80a00`。
- 生产服务器镜像仓库登录已失效，唯一标签拉取返回 `unauthorized`；部署改用本地已验证镜像经 SSH 直接加载，
  未修改或导出生产仓库凭据。
- 新 `culturelens` 容器保持 8080、`unless-stopped` 和 `bridge + culturelens-db` 双网络并为 `healthy`；旧版本
  保留为停止的 `culturelens-rollback-pre-cultural-content-20260801`，重启策略为 `no`。
- 公网、LAN 和 PVE 内部地址健康检查均返回 200。公网附近介绍接口对空表返回 200 和空数组，缺失文化元素
  返回 404；两个旧 object 路径返回 404。`/debug`、`/docs`、OpenAPI 均为 200 且只展示新路径。
- 使用临时 2x2 JPEG 验证识别请求：空旧 catalog 时返回设计约定的 503 `recognition_unavailable`；临时图片已删除。
