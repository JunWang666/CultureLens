# Design 0008：数据库优先的识别候选与实体解析

- 状态：已实施；PostgreSQL 运行时适配由 0015 完成
- 日期：2026-07-29
- 影响范围：Go KnowledgeRepository、审核对象目录、识别管线、Gemini Prompt/Schema、iOS 结果来源标记与评测
- 前置设计：
  - `0005-go-recognition-and-knowledge-backend.md`
  - `0007-location-prior-candidate-ranking.md`

> 0015 已把本文件的内存适配器替换为生产 PostgreSQL Repository。第 3 节保留为迁移前历史；
> 当前 API 不再从内嵌 JSON 读取运行时目录。

## 1. 问题

0007 把约略位置直接交给模型，并要求模型自行生成和重排候选。这仍然把候选空间、地域知识和实体解析都
交给了 LLM：

- 模型可能生成数据库中不存在的名称，却被界面误认为已收录对象。
- 位置可能诱导模型联想到附近景点或藏品，而不是使用 CultureLens 自己审核过的数据。
- 模型返回的名称、摘要、时期、地域和来源没有经过数据库覆盖。
- Go 后端虽在 0005 中预留了 `KnowledgeRepository`，但代码中尚未实现；当前实际可用的审核数据只有
  App 内置的斗拱、莲花纹和青铜鼎三个样例对象。

## 2. 决策

改为“数据库候选检索在前，LLM 视觉排序在后”：

```text
约略位置
  -> KnowledgeRepository.Candidates
       -> 审核目录地域过滤与排序
       -> 最多 12 个稳定对象候选
  -> Gemini
       -> 结合图片选择候选 ID
       -> 或明确返回库外对象
  -> 服务端校验候选 ID
  -> 数据库内容覆盖模型生成的实体事实
  -> 返回主结果和数据库备选
```

位置不再直接发送给 Gemini。LLM 只收到经过服务端检索的审核候选及其稳定 ID、别名、类别、摘要、时期和
地域。模型仍可判断“图片不属于候选集合”，但必须返回空 `catalog_object_id`，不能伪造库内命中。

## 3. 当前知识数据源

正式 PostgreSQL 尚未实现，本阶段先提供与其接口一致的只读 `KnowledgeRepository`：

- 数据文件：`internal/knowledge/data/objects.v1.json`
- 启动时解析并校验，随后作为不可变内存索引使用。
- 编译进 Go 二进制，容器运行时不依赖可修改的外部文件。
- 首批数据来自 App 已有的 3 个审核样例，沿用稳定 UUID：
  - 斗拱：`BFCDA92E-6F97-4FC4-A965-FE7F795B6B1E`
  - 莲花纹：`3A31D620-7E93-4C48-B405-29D1E07F5D47`
  - 青铜鼎：`C1514E46-4F2A-40F5-82E1-35B23A21F1F5`

这不是把 JSON 冒充最终数据库。它是当前可运行的审核目录适配器；后续 PostgreSQL Repository 必须实现
同一接口，识别管线和 Provider 不应因此改写。

## 4. 对象与地域索引

审核对象至少包含：

```json
{
  "id": "BFCDA92E-6F97-4FC4-A965-FE7F795B6B1E",
  "canonical_name": "斗拱",
  "aliases": ["斗栱", "枓栱"],
  "category": "建筑构件",
  "summary": "……",
  "time_period": "唐宋至明清",
  "region": "中国传统木构建筑",
  "artwork_symbol": "building.columns.fill",
  "geography": {
    "region_codes": ["CN"],
    "city_names": []
  },
  "sources": []
}
```

地域检索只使用数据库字段，不让模型自己解释坐标：

1. 城市精确标签命中优先。
2. 国家或地区代码命中其次。
3. 没有地域限制的全局对象可保留。
4. 存在地域命中时，排除明确属于其他地区的对象。
5. 没有任何地域命中时回退到全目录，避免位置数据造成空候选。
6. 结果最多 12 项；同分按规范名稳定排序。

当前位置只提供城市和国家或地区级查询。坐标半径检索、行政区多边形和附近 POI 不在本阶段实现。

## 5. Provider 输入与输出

使用 `recognition-v4` Prompt 和 `provider-recognition-v4` Schema。

Provider 输入新增服务端生成的审核候选 JSON：

```json
[
  {
    "id": "BFCDA92E-6F97-4FC4-A965-FE7F795B6B1E",
    "canonical_name": "斗拱",
    "aliases": ["斗栱", "枓栱"],
    "category": "建筑构件",
    "summary": "……",
    "time_period": "唐宋至明清",
    "region": "中国传统木构建筑"
  }
]
```

Provider 主结果与每个备选新增必填字符串 `catalog_object_id`：

- 匹配审核候选时，必须返回候选中的原始 ID。
- 判断为库外对象时，返回空字符串。
- 服务端可用规范名或精确别名补全遗漏的 ID，但不使用模糊字符串相似度。
- 非空 ID 不在本次候选集合中，或 ID 与名称不一致时，Provider 输出无效。

位置影响不再由模型自述。Repository 根据过滤前后候选数量和顺序生成
`none / reordered / narrowed`，服务端写入现有 `locationInfluence` 响应。

## 6. 服务端实体解析

主结果命中数据库时：

- `CultureObject.id` 使用数据库稳定 UUID。
- `canonicalName`、`summary`、`category`、`timePeriod`、`region`、`artworkSymbol` 和 `sources`
  全部来自数据库。
- 只有本次图片相关的 `confidence`、`rationale` 和 `uncertainty` 来自模型。
- `resolutionStatus = resolved`。

主结果未命中时：

- 保留模型的临时名称与视觉说明。
- 使用本次请求范围的临时 UUID。
- 不附加数据库来源。
- `resolutionStatus = unresolved`。

备选先保留模型返回的合法项，再用本次数据库候选补足到最多 3 项。已解析备选同时返回数据库摘要、时期、
地域、图标与来源，用户切换候选后仍看到数据库事实。服务端补充项必须明确说明“来自已审核知识库，需
对照图片确认”，不能伪装成模型已经观察到的视觉证据。

响应兼容新增：

```json
{
  "catalogVersion": "reviewed-catalog-v1",
  "catalogCandidateCount": 3,
  "resolutionStatus": "resolved",
  "alternatives": [
    {
      "resolutionStatus": "resolved"
    }
  ]
}
```

iOS 对已解析主结果显示“知识库已收录”，对已解析备选显示“知识库候选”。字段都是可选的，旧快照无需
迁移。

## 7. 安全与可信边界

- 客户端不能提交候选集合；候选只由服务端 Repository 生成。
- LLM 不能返回本次未提供的数据库 ID。
- LLM 不能覆盖数据库中的摘要、时期、地域或来源。
- 模型生成的新对象不会写回审核目录。
- 审核目录启动校验 UUID、类别、唯一规范名、唯一别名、地域代码和来源字段；非法数据使服务启动失败。
- 日志只记录目录版本、候选数、解析状态，不记录位置明细或完整模型请求。

## 8. 评测

评测报告继续使用生产管线，因此自动经过同一个 Repository。新增或检查：

- Top-1 / Top-3 的数据库对象 ID 命中，而不只比较名称。
- `resolved` 与 `unresolved` 比例。
- 数据库候选召回率：正确对象是否在检索出的候选集合中。
- 库外对象误归入率。
- 有位置和无位置时的数据库候选数量变化。

当前 JSONL 数据集尚未包含稳定 `expected_object_id`，本次先记录目录版本、候选数和解析状态；加入正式
授权数据集时再扩展 ID 指标。

## 9. 验证

- Repository 测试：目录校验、别名唯一、CN/JP 地域过滤、无命中回退、限制数量与稳定顺序。
- Pipeline 测试：非法候选 ID 拒绝、精确别名解析、数据库字段覆盖模型字段、数据库备选补足。
- Provider 测试：请求包含审核候选，不再包含原始位置 JSON，v4 输出带候选 ID。
- API 合约测试：稳定对象 UUID、来源、解析状态、目录版本和候选数量。
- iOS 解码与 UI 测试：新字段缺失兼容、主结果及备选来源标记。
- `go test ./...`、`go vet ./...`、iOS Debug build 与单元测试。

## 10. 后续

- PostgreSQL G3 实现同一 Repository，并把审核目录迁入表结构。
- 只有具备带地域标签且经过审核的对象后，位置才能真正缩小到场馆或城市级候选；不能由模型补造标签。
- App 内置样例最终改由后端知识 API 同步，消除两份数据源；当前稳定 UUID 保证迁移期间能够互认。
