# 0029 保存候选并统一扫描结果/历史详情展示

## 背景

扫描结果已经返回文化知识图谱和景点候选，但历史快照只按单个 `RecognitionResult` 保存，且历史详情只展示对象图谱，不展示候选列表。用户无法确认候选是否被保存，也无法在历史记录中复看扫描时的完整文化上下文。

## 目标

- 扫描结果页明确分为“文化知识图谱”和“附近景点候选”两块。
- 候选只作为景点候选展示，不再出现“知识库候选”标签。
- 保存时保留原始主结果、全部候选、文化图谱和最终选择的对象/候选 ID。
- 历史详情页恢复并展示与扫描结果页一致的图谱和候选内容。
- 兼容旧的只含 `RecognitionResult` 的历史快照。

## 数据设计

新增 Codable 快照包装：

```text
ScanHistorySnapshot
├── result              原始识别结果，包含 alternatives 和文化图谱
├── selectedObject      用户最终确认后写入地图的对象
└── selectedCandidateID 用户选择的候选 ID，可为空表示主结果
```

`ScanHistoryRecord.resultSnapshotData` 继续使用 `Data`，避免新增 SwiftData 字段和迁移风险；数据格式升级时使用新的 `CultureLensHistoryV4` 容器名。读取时先解码包装快照，失败则回退解码旧 `RecognitionResult`。

## UI 设计

- `CultureRelationGraphView` 上方保留“文化知识图谱”标题，作为文化知识区域。
- 景点候选区域使用“附近景点候选”标题；空列表不显示候选区域，说明文化知识与景点候选不是同一类数据。
- 历史详情复用只读候选卡片，并把图谱绑定到保存的文化结果，而不是绑定到可能没有文化关系的景点候选对象。

## 验证

- Swift 编译检查和 `git diff --check`。
- 无可用 Simulator runtime 时，不启动模拟器；记录环境限制。
