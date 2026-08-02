# Design 0009：丝绸之路来源采集与可追溯知识库

- 状态：已确认，进入实现
- 日期：2026-07-30
- 影响范围：`CultureLensBackend` 数据采集命令、知识库数据结构、来源与版权信息、审核发布边界、查询与测试
- 前置设计：
  - `0004-directed-cultural-knowledge-graph.md`
  - `0005-go-recognition-and-knowledge-backend.md`
  - `0008-database-first-recognition-candidates.md`

## 1. 问题

当前后端只有 3 个手工审核对象。它足以验证识别实体解析，但不足以覆盖丝绸之路沿线的器物、材料、
时期、地域、收藏机构、路线和人物，也没有可重复执行的数据采集流程。

本轮指定两个来源：

- 中国丝绸博物馆 IIDOS 所链接的丝绸之路数字博物馆 SROM 数字藏品。
- 中文维基百科中的丝绸之路主题条目。

这两个来源的权利边界不同：

- SROM 当前公开接口提供藏品元数据和图片 URL，但站点页脚标注 All Rights Reserved，公开接口没有为
  每条记录给出可再分发许可。
- 维基百科文字允许依照 CC BY-SA 4.0 再利用，但必须保留条目 URL、修订版本、署名入口、许可和修改
  说明。

因此不能把抓取结果直接当成“已审核、可发布、可用于识别”的正式目录，也不能批量下载或重新分发
SROM 图片。

## 2. 决策

新增独立的可追溯知识库构建链路：

```text
SROM 公开藏品 API
  -> 只读取元数据
  -> 丢弃长篇 HTML 描述
  -> 生成事实型摘要与来源指纹
  -> imported 藏品实体

Wikipedia 固定修订种子
  -> 保留条目、oldid、访问时间和 CC BY-SA 4.0
  -> 保存经过改写的短摘要
  -> imported 主题实体与显式关系

两路数据
  -> 校验
  -> 稳定排序
  -> knowledge/bundles/silk-road.v1.json
  -> 本地查询、人工审核和后续 PostgreSQL 导入
```

首版知识库是“研究与审核语料库”，不是 `reviewed-catalog-v1` 的替代品。识别运行时继续只读取已审核
目录；只有人工确认名称、摘要、地域、来源和使用权后，实体才可通过后续 publish 流程进入运行时目录。

## 3. 数据范围

### 3.1 SROM

采集公开 `collection/list_web` 返回的全部可见藏品元数据：

- 藏品 ID、中英文名称。
- 材质、年代、地区、收藏机构、题材。
- 尺寸。
- 藏品详情页 URL。
- 一张远端图片引用 URL；只作来源定位，不下载、不打包。
- 原始记录 SHA-256 指纹，用于后续检测来源变化。

不写入知识库：

- `describe` / `enDescribe` 长篇 HTML 正文。
- 图片二进制、图片副本和图片缩略图。
- 登录态、收藏状态或用户信息。
- SROM 未公开的后台字段。

藏品摘要只从结构化元数据生成，例如：

> 南宋时期的瓷质藏品，现藏海南省博物馆。

它不复制来源正文，也不推断来源未提供的作者、出土地、用途或文化关系。

### 3.2 Wikipedia

首批固定 11 个与丝路藏品检索直接相关的主题：

- 丝绸之路、海上丝绸之路、草原丝绸之路、南方丝绸之路。
- 河西走廊、长安、敦煌市。
- 张骞。
- 丝绸、瓷器、中国青铜器。

如果同一主题同时承担材料、地点或人物角色，以主题种子中明确声明的 `kind` 为准。条目标题、规范
URL、`oldid`、访问时间和许可全部进入来源引用。摘要经过压缩改写，并标记 `modified = true`。

## 4. 知识库结构

知识库文件使用统一实体和有向边：

```text
KnowledgeBundle
  version
  generated_at
  records[]
  relations[]
  statistics

KnowledgeRecord
  id UUID
  source_key
  kind
  canonical_name
  aliases[]
  summary
  attributes[]
  citations[]
  media_references[]
  review_status
  content_fingerprint

KnowledgeRelation
  id UUID
  source_id UUID
  target_id UUID
  kind
  explanation
  citation_ids[]
  review_status
```

`kind` 首版允许：

- `artifact`
- `route`
- `place`
- `person`
- `material`
- `concept`

`review_status` 首版只有：

- `imported`：由采集器生成，尚未进入产品审核目录。
- `reviewed`：结构预留；采集器不得自动产生。

属性采用稳定的 `key/value` 数组，而不是任意嵌套 JSON。首批 key：

- `material`
- `period`
- `region`
- `holding_institution`
- `theme`
- `dimensions`
- `external_id`
- `wikipedia_revision`

来源引用至少包含：

- 稳定 UUID。
- 来源类型、标题、发布者和 URL。
- 访问时间。
- 许可或权利说明。
- 是否对原文作了修改。

## 5. 稳定标识与去重

- SROM 藏品实体 UUID 由 `srom:collection:<collectionId>` 使用 UUID v5 生成。
- Wikipedia 主题 UUID 由 `wikipedia:zh:<normalized-title>` 使用 UUID v5 生成。
- 关系 UUID 由 `sourceID + kind + targetID` 使用 UUID v5 生成。
- 同一来源 key 必须唯一。
- 不按模糊名称自动合并不同来源实体。
- 跨来源 `same_as` 只能由种子中的显式映射或人工审核产生。

这保证重复运行不会因为时间或返回顺序产生新 ID。

## 6. 关系边界

首版只为固定 Wikipedia 主题建立显式、有来源的关系：

- 路线属于广义丝绸之路。
- 长安、敦煌、河西走廊位于或连接陆上丝路。
- 张骞与汉代西域交通开拓相关。
- 丝绸、瓷器、中国青铜器与丝路物质交流相关。

不从 SROM 的自然语言描述中自动抽取关系，不让 LLM 猜测边，也不因名称相近建立 `same_as`。

## 7. 命令与文件

后端新增：

```text
cmd/knowledge/
  main.go
internal/knowledgebase/
  types.go
  sync.go
  store.go
  search.go
knowledge/
  README.md
  seeds/wikipedia.zh.v1.json
  bundles/silk-road.v1.json
```

命令：

```bash
go run ./cmd/knowledge sync
go run ./cmd/knowledge validate -file knowledge/bundles/silk-road.v1.json
go run ./cmd/knowledge query -file knowledge/bundles/silk-road.v1.json -q 丝绸
```

`sync` 使用单次或少量分页请求，设置明确 User-Agent、超时和响应大小上限。输出采用原子替换，失败时
不得破坏现有 bundle。

## 8. 版权与发布边界

- SROM：只保存事实型元数据、来源链接、远端媒体引用和内容指纹；不保存长篇描述，不下载图片。
- Wikipedia：摘要及其改写继续按 CC BY-SA 4.0 处理；每条记录保留可访问页面历史的 URL、固定
  修订号、许可 URL和 `modified = true`。
- `knowledge/README.md` 必须说明两类来源的不同再利用条件。
- 应用 UI 后续展示 Wikipedia 改写文字时必须显示来源链接和许可。
- SROM 图片只有在取得逐项授权或来源明确开放许可后，才可进入 App 资源、训练集或可再分发缓存。

## 9. 查询与审核

本轮提供只读本地查询：

- 名称和别名精确/包含匹配优先。
- 摘要和属性值其次。
- 结果返回实体 ID、类型、摘要、审核状态和首个来源 URL。

查询能力用于检查采集结果和辅助人工审核，不直接替换识别候选检索。后续 PostgreSQL 导入和审核发布
流程另写设计。

## 10. 验证

- SROM 采集器对分页、HTTP 错误、非法 JSON、总数不一致和重复 ID 有测试。
- 所有实体和关系 UUID 可解析且唯一。
- 所有关系端点和 citation ID 可解析。
- 所有 SROM 记录都是 `imported`，没有长篇描述字段。
- 所有 Wikipedia 记录包含 `oldid`、CC BY-SA 4.0、来源 URL 和修改标记。
- 相同固定输入重复构建得到相同实体、关系和排序。
- `go test ./...`、`go vet ./...` 通过。

## 11. 当前边界

- Wikipedia 首版是人工选定的固定主题，不做开放式爬链。
- SROM 远端字段可能变更；内容指纹只提示变化，不自动覆盖人工审核结果。
- 本轮不导入 PostgreSQL，不提供 CMS，不自动发布到 `reviewed-catalog-v1`。
- 知识库数量增长不等于识别准确率提升；正式候选检索仍需图像/文本召回和授权评测。
