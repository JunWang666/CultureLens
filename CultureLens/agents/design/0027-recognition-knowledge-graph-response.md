# Design 0027：识别结果返回文化知识图谱

- 日期：2026-08-01
- 状态：已确认，待部署
- 影响范围：Go 识别响应、PostgreSQL 文化关联读取、iOS 扫描结果图谱
- 前置设计：
  - `0004-directed-cultural-knowledge-graph.md`
  - `0022-cultural-content-recognition-pipeline.md`
  - `0026-west-lake-three-pools-cultural-expansion.md`

## 1. 问题

生产 PostgreSQL 已经有文化元素关联，但识别管线在 `knowledgeCultureObject` 中始终返回空的 `concepts` 与 `relations`。扫描结果因此进入 SwiftUI 的“关系资料不足”分支，数据库内容无法进入图谱。

## 2. 方案

- 识别候选读取完成后，对最终候选范围内的文化元素查询显式关联元素。
- 将关联元素映射为 iOS 现有 `CultureConcept` JSON 结构，使用稳定的 `culturalElementID` 生成 UUID。
- 将每条显式关联映射为 iOS 现有 `CultureRelation` JSON 结构，来源为识别对象，目标为关联概念；当前数据库关系表没有保存关系类型和解释，因此使用 `解释` 作为保守的通用关系类型，并在解释文本中明确它来自数据库显式关联。
- 识别结果仍保持原有 JSON 契约，不新增数据库表或 iOS 持久化字段。
- 无关联、未解析结果和旧响应继续返回空数组，客户端保留“关系资料不足”降级。

## 3. 数据边界

本轮只把数据库已经审核通过的显式关联返回给客户端，不根据概念名称或朝代自动推断关系方向。当前关系表是无向关联，所以 API 返回的图谱边表示“当前对象与该概念存在显式文化关联”，不声称数据库已保存更细的因果方向。

后续如果需要“理解前先懂”“体现”“受规制于”等有向类型，必须新增关系类型、方向和关系级来源的正式数据设计，不能在客户端猜测。

## 4. 验证

- Go 单元测试验证识别对象包含非空 concepts/relations，且 relation 两端 UUID 能解析到对象或 concept。
- JSON 编解码测试验证 Swift `CultureObject` 能读取生产响应中的图谱字段。
- 部署后使用三潭映月/北宋疏浚候选执行真实识别响应检查，确认不再出现“关系资料不足”。
