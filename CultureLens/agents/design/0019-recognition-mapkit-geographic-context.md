# 0019 扫描识别的 MapKit 地理上下文

- 状态：已实现，待真机网络验证（2026-08-06）

## 背景

原识别链路把当前设备 GPS 或照片 EXIF 坐标传给本地 `KnowledgeStore`，以便选取 1 km 内的知识包看点；LLM 本身没有收到坐标、城市或 Apple 地图中的真实周边地点。因此，知识包尚未覆盖的新地点、馆区或地标无法作为场景辅助信息。

## 决策

1. 新增请求级 `NearbyMapPlaceContext`，包含 MapKit POI 的名称、坐标、直线距离与可用地址。它只存在于 `RecognitionInput` 和本次 prompt，不写入扫描历史或 SwiftData。
2. `NearbyMapPlaceProvider` 通过 `MKLocalPointsOfInterestRequest(center:radius:)` 以拍照位置为圆心请求 1,000 m。由于 MapKit 的返回仍可能处于边界框内，App 会重新计算直线距离、去重、按距离排序，再取最近 3 条。
3. `ScanCoordinator` 在拿到当前 GPS、已预解析的 GPS 或照片 EXIF 后查询一次 MapKit；没有坐标时不查询。MapKit 不可用、离线或无结果时返回空数组，照常进入识别，不提示为识别失败。
4. `PromptAssembler` 在有位置时附加 `拍摄地理上下文 JSON`：拍照坐标精度/反向地理名称和最多 3 条 `nearby_map_places`。提示词明确要求模型仅将它用于场景理解和视觉近似候选的区分，不能代替可见证据；地图名称作为不可信数据处理。

## 边界

- 不改变 v5 输出 schema、LLM 短 ID 映射、识别候选选择或结果映射。
- 不把 MapKit POI 视为知识包景点，也不允许它们写入 `attraction_key` / `cultural_element_key`；这些字段依旧只能引用端侧知识包候选。
- 不持久化 Apple 地图的外部 POI，扫描记录继续只保存用户拍摄/照片已有的 `PlaceContext`。
- 本地知识包的 1 km 候选策略（`design/0015`）与 MapKit 1 km 查询相互独立：前者确定可返回的知识实体，后者只提供场景辅助。

## 验证

- 单测：MapKit 条目以直线距离过滤、排序并截到 3 条；prompt 包含坐标与 `nearby_map_places` 的稳定 snake_case JSON，且带“不可替代可见证据”的约束。
- 构建：2026-08-06 通用 iOS 设备 `CultureLens` App build 与 `CultureLensTests` target build 已通过。Simulator `build-for-testing` 受既有第三方 `EquatableMacros` 宏插件加载失败影响，未能执行；该失败发生在依赖包编译阶段而非本功能源码。
- 真机：在有网络、位置授权和不同行政区的场景下确认 Apple Maps 返回的地点会进入识别请求；断网/无 POI 时确认识别仍可完成。
