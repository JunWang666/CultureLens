# 0025 — 文化回顾主图、宽屏与整页分享

- 状态：已实现（2026-08-07）

## 背景

文化回顾详情此前只有文字刊头与统计，没有主图；宽屏（iPad 横屏）仍是单列；分享只支持单张文化卡片，不能把整次参观作为一份「日志」发出去。

## 决策

1. **主图**：按行程对象顺序，取知识包 `element.introduction` 里第一张 HTTPS 图（`imageBlocks.first`）作为回顾主图；详情页与分享卡共用同一解析（`VisitTripHero` / `CultureObjectImage`）。文化卡片图槽（`CultureObjectCard`）同样优先正文配图，无图时回退海报感 `ObjectArtwork`（见 `0024`）。ODR 未就绪时会再等 `KnowledgePackLoader` 后重试解析。
2. **宽屏**：详情页改用 `SplitDetailLayout`——左栏主图 / 标题 / 统计 / 整页分享，右栏卡片网格与识别记录；窄屏保持单列，主图边缘出血。
3. **整页分享**：`ShareVisitTripButton` 调用 `VisitTripShareCopyService`（`dynamic/chat`）写 2–3 句介绍词，失败则用本地模板；`VisitTripShareRenderer` 导出杂志风 PNG + 文本。
4. **详情页展示介绍词**：同一套 LLM 介绍词也显示在回顾详情刊头（替换原先的静态说明）；先落本地模板，生成成功后替换；结果写入 `Library/Caches`，详情与分享按钮共用，纳入统一缓存清理。
5. **可选生图**：设置「图片生成」默认关闭；仅当开启且介绍无主图时，才调火山方舟 Seedream（`VolcengineImageClient`）生成封面。

## 非目标

- 不改行程聚类规则（`VisitTripBuilder`）。
- 不把 Seedream 用作列表缩略图或详情页在线背景。
- 不新增独立「回顾收集」系统。
