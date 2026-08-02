# Design 0012：已了解知识节点进度

- 日期：2026-07-30
- 状态：已实施并验证
- 影响范围：知识节点详情、对象详情工具栏、应用依赖注入、本地进度存储与测试
- 前置设计：
  - `0002-humanist-liquid-glass-ui.md`
  - `0004-directed-cultural-knowledge-graph.md`

## 1. 问题

文化关系图谱允许用户打开对象和概念节点，但目前阅读完成后没有明确动作，也不会记录用户已经理解的
节点。对象详情右上角的资料来源按钮与正文底部的来源入口重复，占用了更适合表达探索进度的位置。

## 2. 决策

新增本地 `KnowledgeProgressStore`，以节点稳定 UUID 保存“已了解”状态：

- `CultureObject.id` 与 `CultureConcept.id` 使用同一套节点标识。
- 对象与概念详情底部都提供“我已经了解”主按钮。
- 对象详情右上角原资料来源按钮改为同一功能的图标按钮。
- 已了解时按钮显示勾选状态和“已了解”；再次点击可撤销，防止误触后无法修正。
- 对象详情正文中的来源按钮继续保留，资料来源仍可访问。

本轮只记录布尔状态，不计算等级、积分、完成时间或服务端同步。

## 3. 状态与存储

`KnowledgeProgressStore` 是由 `AppRootView` 持有并通过 SwiftUI environment 注入的
`@Observable` 共享状态。它公开：

```text
isUnderstood(nodeID)
toggleUnderstanding(nodeID)
```

持久化使用 `UserDefaults` 中版本化键 `culturelens.understood-node-ids.v1`，值为排序后的 UUID
字符串数组。选择该方案是因为当前进度只有一个小型集合，不需要查询、关系或独立 SwiftData 生命周期；
现有 `ScanHistoryRecord` schema 与 `CultureLensHistoryV3` 不变。

无效 UUID 在读取时忽略。每次切换后立即写入，应用重启后恢复。

## 4. 组件与交互

新增可复用的 `KnowledgeUnderstandingButton`：

- 正文模式使用全宽系统 prominent 按钮，未了解时文案为“我已经了解”。
- 工具栏模式使用 `checkmark.circle` / `checkmark.circle.fill`。
- 两种模式读取和修改同一个 `KnowledgeProgressStore`，状态即时同步。
- VoiceOver 分别说明“标记为已了解”和“取消已了解”。
- 最小触控区域由系统按钮与工具栏布局保证。

按钮不替代来源可信度展示，也不自动推断用户真正掌握了内容；它只记录用户主动确认。

## 5. 验证

- 新节点初始为未了解，点击后变为已了解，再次点击可撤销。
- 使用相同 `UserDefaults` 重新创建 Store 后能恢复状态。
- 对象与概念详情底部都存在“我已经了解”按钮。
- 对象详情右上角不再显示来源按钮，改为了解状态按钮。
- 对象详情正文来源入口仍可打开来源列表。
- iOS Simulator Debug 编译和相关单元测试通过。

## 6. 后续

- 文化地图可读取同一 Store，展示已点亮节点数量和主题进度。
- 如果未来需要账号同步、完成时间或多设备合并，再设计服务端协议和迁移；本轮不预留未经验证的同步字段。
