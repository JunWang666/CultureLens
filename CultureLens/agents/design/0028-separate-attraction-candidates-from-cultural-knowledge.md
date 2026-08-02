# Design 0028：景点候选与文化知识分层

- 日期：2026-08-01
- 状态：已确认，待部署
- 影响范围：识别候选语义、Go 识别响应、LLM 上下文、Swift 扫描结果页
- 前置设计：
  - `0022-cultural-content-recognition-pipeline.md`
  - `0027-recognition-knowledge-graph-response.md`

## 1. 目标

识别结果中，“候选”只表示当前位置附近、可被用户确认的景点；文化元素只作为 LLM 的知识依据和主结果的图谱节点，不再混入候选卡片。

## 2. 数据分层

```text
PostgreSQL cultural_elements
        └─ LLM 文化知识上下文 ──▶ 主结果与文化知识图谱

PostgreSQL attraction_cultural_introductions
        └─ 去重后的附近景点候选 ──▶ 扫描结果候选区
```

- 有位置且命中现场介绍时，按 `attraction_key` 去重生成景点候选，保留其关联文化元素 key 作为后续解释入口。
- 无位置或附近没有景点现场介绍时，景点候选为空；LLM 仍接收文化元素知识上下文进行开放集合识别。
- 识别 Provider 仍可返回文化元素 key 供主结果解析；Provider 的文化元素 alternatives 不直接展示为 UI 候选。

## 3. 契约调整

- `RecognitionSet` 增加内部 `AttractionCandidates`，由附近介绍派生，不修改数据库表。
- 响应 `alternatives` 只序列化景点候选；景点候选增加 `attractionKey` 和 `resolutionStatus=attraction`。
- Swift 结果页对景点候选显示“附近景点候选”，不显示“知识库候选”；文化知识通过主结果图谱呈现。
- `locationInfluence` 文案改为说明发现了多少条景点现场介绍，不再说“调整文化元素候选顺序”。

## 4. 边界

- 景点候选是位置候选，不是视觉模型已经确认的结论，必须明确标注并允许用户继续确认。
- 没有附近景点时不伪造“其他可能”卡片，也不把文化元素名称降级成景点名称。
- 本轮不新增景点识别模型和新的数据库表；若未来要让 LLM 直接输出景点 key，需要另行升级 Provider Schema。

## 5. 验证

- 有西湖位置时，响应 alternatives 中每项都有 `attractionKey`，且名称来自 `attractions`。
- 无位置或无附近介绍时，响应 alternatives 为空，文化知识候选仍进入 Provider 输入。
- Swift UI 不再把文化元素名称渲染为候选卡片；主结果图谱仍能读取 concepts/relations。
