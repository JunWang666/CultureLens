# 0005 P1 玩法：文化回顾、主题探索、文化卡片与视觉备选

- 状态：已实现（2026-08-03）

## 背景

立项书承诺「点亮文化节点、收集文化卡片、完成主题探索和生成文化回顾」。P0 已落库讲解与历史/图谱；P1 在此之上补齐三个玩法，并修掉识别管线丢掉模型 alternatives 的浪费。

## 文化回顾

- `VisitTripBuilder` 将扫描历史按时间间隙（默认 3 小时）与地点（同名或 Haversine ≤ 2km）聚成「行程」。
- 汇总页展示点亮节点数、走过景点、新增关系，并列出本次对象的可分享文化卡片。
- 入口：探索 Tab「文化回顾」、我的 Tab 工具栏。

## 主题探索

- 知识包新增可选 `themes[]`：`key` / `name` / `summary` / `elementKeys` / `minContacted`。
- 进度按用户图谱中已接触的 elementKey 计算；达到 `minContacted` 即完成。
- 西湖包内置 4 个主题（月影三潭、十景观看、塔影对景、长堤治理）。旧包缺字段时解码为空数组。

## 文化卡片

- 复用并增强 `CultureObjectCard`（品牌角标）；`ShareCultureCardButton` 用 `ImageRenderer` 导出 PNG + 文本回退。
- 对象详情分享与文化回顾卡片共用同一分享管线，不另建收集系统。

## 视觉备选

- `RecognitionResponseMapper.mapResponse` 先写入模型 alternatives（`visual` / 库内命中为 `resolved`），再追加附近景点（`attraction`）。
- `RecognitionResult.displayVisualAlternatives` / `displayAttractionCandidates` 分流；扫描结果页低置信时标题为「也可能是」。
