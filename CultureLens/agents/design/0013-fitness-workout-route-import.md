# 0013 从 Apple Fitness / 健康导入运动路线

- 状态：已实现（2026-08-06）

## 背景

足迹已经支持导入 GPX 并保存为 App 内独立轨迹，但 Apple Watch、体能训练 App 或第三方运动 App 写入 Fitness / 健康的记录仍需先手工导出文件。用户希望直接选择这些运动记录，并在文化足迹地图上叠加路线。

## 产品范围

- 足迹页导入入口提供“从 Fitness 导入”和“从文件导入 GPX”两个来源。
- 通过 HealthKit 只读请求 `HKWorkout` 与 `HKWorkoutRoute`；不写入、修改或删除健康数据。
- 选择器只列出最近运动记录中实际带 GPS 路线且当前授权范围可读的项目，展示运动类型、时间、时长和来源 App。
- 支持多选导入；已导入的 HealthKit workout 以其 UUID 标记并禁用重复选择。
- 导入完成后复制坐标、海拔和时间到现有 `ImportedTrackStore`，自动显示并框选最后一条轨迹。

## 数据与服务

`ImportedTrack` 增加可选来源字段：

- `sourceKind`：`gpxFile` 或 `appleFitness`；旧 JSON 缺少该字段时按 GPX 兼容读取。
- `sourceIdentifier`：Fitness 使用 `HKWorkout.uuid`，用于幂等导入；GPX 暂不做内容去重。

新增 `FitnessWorkoutRouteService`：

1. 先检查设备是否支持健康数据，再在用户打开导入页时请求只读权限。
2. 查询最近的 workouts，并通过 workout 关联谓词查询 `HKWorkoutRoute`；没有路线的室内运动不展示。
3. 导入时使用 `HKWorkoutRouteQueryDescriptor` 分批读取 `CLLocation`，每个 route sample 保留为独立分段，避免跨暂停或多段路线直连。
4. HealthKit 对读取权限采用隐私保护：App 无法区分“拒绝读取”和“确实没有数据”，因此空状态合并说明两种可能。

## 持久化与隐私

- HealthKit 只作为导入源；导入后的归一化 JSON 位于 Application Support，之后绘图不依赖 HealthKit。
- 删除 App 内轨迹只删除本地副本，不影响 Fitness / 健康原记录。
- 工程启用 HealthKit entitlement，并提供 `NSHealthShareUsageDescription`；不申请写权限、后台读取或临床记录权限。
- 轨迹仍沿用单条最多 200,000 点及地图单段最多 10,000 渲染采样的边界。

## 验证

- 单元测试覆盖 Fitness 来源持久化、旧 GPX JSON 向后兼容、Workout UUID 幂等导入和非法空路线。
- `ImportedTrackStore` 独立 smoke test 与 Fitness 相关源码的 iOS SDK 类型检查通过。
- 通用 iOS 真机目标 Debug 构建与 `build-for-testing` 通过，确认 App、单元测试和 UI 测试目标均可编译。
- 当前第三方 `SwiftStreamingMarkdown` 宏在 Simulator 工具链下报 `DYLD_ROOT_PATH`，因此未把模拟器测试运行结果作为本功能完成条件。
- Fitness 历史和授权必须在含真实健康数据的 iPhone 上最终验证；模拟器无法证明真实记录读取结果。
