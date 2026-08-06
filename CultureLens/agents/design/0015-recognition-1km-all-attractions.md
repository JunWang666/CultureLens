# 0015 — 识别候选：1 km 内全量景点，超 10 个省略介绍

## 背景

附近景点很多时（例如西湖景区密集看点），旧逻辑把传给视觉模型的景点候选硬截到 8 个、文化看点默认 12 个，远处但仍在视野内的对象无法被模型选中。

## 决策

1. **识别半径改为 1 km**（`KnowledgeStore.recognitionRadiusMeters`）。探索页附近推荐仍可用更大半径（`defaultRadiusMeters`）。
2. **1 km 内每一个去重后的景点都进入 prompt**（取消 `maximumAttractionCandidates = 8`）；对应看点根也全部进入文化内容候选，不再被 `limit` 截断。目录补齐（附近景点 &lt; 3 时）仍受 `defaultCandidateLimit` 约束。
3. **附近景点数 &gt; 10** 时，prompt 里的文化内容候选只保留 `id` / `name`：清空 `introduction`，并去掉 `nearby_contexts`（`KnowledgeCandidateContext.omittingIntroductions()`）。本地 `RecognitionKnowledgeSet` 仍保留完整介绍，供结果映射与详情使用。

## 非目标

- 不改 v5 JSON 契约字段名。
- 不改探索页 / `nearbyIntroductions` 的默认查询半径。
- 不把历史节点重新开放为 `cultural_element_key` 候选。
