# Design 0017：文化元素与景点特定介绍

- 日期：2026-08-01
- 状态：已实施并部署
- 影响范围：PostgreSQL schema、sqlc 查询、DB 运维命令与集成测试
- 前置设计：
  - `0015-postgresql-reviewed-catalog-repository.md`
  - `0016-related-objects-and-location-recommendations-api.md`

## 背景

原模型以 `knowledge_nodes` 同时表达文化对象、概念、地域标签和简介，不能清晰区分：

1. 跨景点复用的通用文化元素，例如斗拱、榫卯或莲花纹。
2. 某个文化元素在特定景点和精确位置中的现场介绍。

用户已清空原生产知识数据，新内容不再以官方目录或来源表为中心，而以“文化元素 + 景点语境”为核心。

## 目标

- 文化元素保存稳定 key、名称、富文本介绍和多对多关联。
- 景点特定介绍保存自身稳定 key、展示名称、富文本介绍、所属文化元素、所属景点和
  WGS84 经纬度。
- 所有关联由外键维护，不在 JSON 数组中存放孤立 key。
- 新 schema 未导入内容时保持为空，不自动回灌已删除的低质量样例。

## 数据表

### `cultural_elements`

```text
key TEXT PK
name TEXT
introduction JSONB
created_at TIMESTAMPTZ
updated_at TIMESTAMPTZ
```

`key` 是不随展示名称改变的 ASCII 稳定标识，长度 1...128，只允许小写字母、数字、`.`、`_`、`-`。

### `cultural_element_relations`

```text
element_key TEXT FK cultural_elements
related_element_key TEXT FK cultural_elements
created_at TIMESTAMPTZ
```

关联是无向的，数据库使用 `LEAST/GREATEST` 唯一索引防止 A→B 和 B→A 重复，并禁止元素自关联。

### `attractions`

```text
key TEXT PK
name TEXT
created_at TIMESTAMPTZ
updated_at TIMESTAMPTZ
```

虽然用户只明确了两类内容实体，“关联的景点”仍需要独立受外键约束的目标；否则景点名会在每条介绍中重复且
无法稳定关联。

### `attraction_cultural_introductions`

```text
key TEXT PK
name TEXT
introduction JSONB
cultural_element_key TEXT FK cultural_elements
attraction_key TEXT FK attractions
latitude DOUBLE PRECISION
longitude DOUBLE PRECISION
created_at TIMESTAMPTZ
updated_at TIMESTAMPTZ
```

- 经纬度必填，使用 WGS84 十进制度；纬度限定 `[-90, 90]`，经度限定 `[-180, 180]`。
- 同一文化元素允许在同一景点出现多次，每个现场位置使用不同的介绍 key。
- 按景点、文化元素和经纬度建立索引，为后续景点列表和附近查询做准备。首版不引入 PostGIS。

## 富文本合约

`introduction` 使用可版本化的 JSON block document，不存任意 HTML：

```json
{
  "schemaVersion": 1,
  "blocks": [
    {"type": "paragraph", "text": "正文"},
    {"type": "heading", "level": 2, "text": "标题"}
  ]
}
```

数据库验证根节点为 object、`schemaVersion = 1`、`blocks` 为非空 array。具体 block 白名单由后续写入层和客户端
渲染器验证，客户端不执行内容中的脚本。

## 兼容和迁移

- migration 3 新增上述 4 表，不把旧表中的低质量资料迁移过来。
- 旧 `knowledge_*` 表暂时保留，仅为已有识别管线和 API 合约的过渡兼容；新内容只写入新表。
- `culturelens-db up` 改为只执行 migration。原 `seed-reviewed-catalog` 保留为显式兼容命令，但不再由 `up`
  自动调用，避免旧 3 个样例回灌生产。
- 后续切换识别候选和公开 API 后，再以独立 migration 删除旧表，不在本次破坏性删表。

## 权限

- `culturelens_admin` 拥有新表并负责写入。
- 如 `culturelens_app` 角色已存在，migration 只授予新表 `SELECT`。
- 运行时 API 不拥有 INSERT、UPDATE 或 DELETE。

## 验证

- migration 1→3 从空库可一次完成，migration 3 可在生产 schema v2 上前向执行。
- 无效 key、空富文本、非法经纬度、孤立外键、自关联和反向重复关联必须被 PostgreSQL 拒绝。
- sqlc 生成代码无 diff，`go test ./...` 与 `go vet ./...` 通过。
- 使用真实 PostgreSQL 18 容器验证新增、查询、关联双向读取和约束。

## 本次不包含

- 生产内容导入或自动生成文案。
- 对外写入 API 或内容管理后台。
- 公开知识 API 的路径和响应合约切换。
- PostGIS、路线规划或室内定位。

## 实施结果

- 新增 migration 3 和 4 张新表；旧知识表未删除、旧数据未迁移。
- 新增 sqlc 类型安全查询：文化元素和景点的 upsert/get/list、无向关联新增/删除/双向读取、景点特定介绍
  upsert/get/list。
- `culturelens-db up` 已不再执行 `seed-reviewed-catalog`；在空旧目录的测试库执行后只输出
  `schema_version=3`，`knowledge_catalogs` 仍为 0。
- PostgreSQL 18.4 容器集成测试通过：新表写入和关联双向读取正常，非法 key、空富文本、越界坐标、
  自关联和反向重复关联均被拒绝。
- `go test ./... -count=1` 在真实 PostgreSQL 环境下通过，`go vet ./...` 通过；临时数据库容器已清理。
- 2026-08-01 已在生产备份后执行 migration 3，schema version 为 3；4 张新表均由
  `culturelens_admin` 持有，`culturelens_app` 只有 `SELECT`，表内计数均为 0。未写入西湖或其他景点资料。
