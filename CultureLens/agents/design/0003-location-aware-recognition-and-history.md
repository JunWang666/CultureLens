# Design 0003：融合粗粒度位置的视觉识别与扫描历史

- 状态：已确认，进入实现
- 日期：2026-07-28
- 影响范围：媒体采集、位置权限、视觉模型 BFF、领域模型、SwiftData、导航、扫描结果、关系图谱和历史地图

## 1. 目标

在不把模型密钥放进 App 的前提下，完成可运行的扫描闭环：

> 拍摄或选择图片 -> 本地规范化并移除元数据 -> 用户选择是否提供粗粒度位置 -> 视觉大模型返回结构化候选与文化关系 -> 用户确认结果 -> 本地保存扫描历史 -> 在地图、时间线与关系图谱中继续探索

本设计不承诺开放域生产级准确率。位置只能作为弱上下文，不能覆盖图像证据，也不能让模型把用户所处城市直接当作对象来源。

## 2. 总体架构

```text
Camera / PhotosPicker
  -> ImagePreprocessor
       - 方向归一化
       - 长边缩至 1600 px
       - JPEG 0.82
       - 重新编码，移除 EXIF/GPS
  -> LocationContextProvider（用户显式授权）
       - 单次定位
       - 约 1 km 粒度坐标
       - 可选地点名称
  -> RecognitionCoordinator
       - loading / success / low-confidence / failure / cancel
  -> RecognitionService
       - RemoteRecognitionService（BFF）
       - SampleRecognitionService（Preview、测试和未配置后端）
  -> RecognitionResult
  -> ScanResultView
  -> ScanHistoryStore / SwiftData
  -> HistoryMapView + CultureRelationGraphView
```

共享依赖在 App 根部创建并通过 Environment 注入。扫描的短期状态由 `@Observable ScanCoordinator` 持有；历史记录由 SwiftData 持久化。

## 3. 视觉模型路线

### 3.1 BFF 边界

App 只调用 CultureLens BFF：

```http
POST /v1/recognitions
Content-Type: application/json
```

请求包含：

- 重新编码后的 JPEG Base64。
- MIME 类型和请求 ID。
- 用户可编辑的场景补充。
- 可选粗粒度位置：四舍五入后的经纬度、精度、地点文字。
- App 语言。

BFF 从服务端环境读取 `OPENAI_API_KEY`，调用 OpenAI Responses API。默认模型采用当前官方推荐的 `gpt-5.6-sol`，模型名可由 `OPENAI_VISION_MODEL` 覆盖。图像 detail 明确使用 `high`，避免 GPT-5.6 的 `auto/original` 对手机原图产生不可控的 token 和延迟。

### 3.2 模型任务

模型必须返回严格 JSON，而不是自由文本：

- `primary`：对象名称、类别、置信度、时期、地域、摘要、判断依据。
- `alternatives`：最多两个候选。
- `concepts`：历史、地域、功能、审美、人物、技法、相似对象中的 3-6 个。
- `sources`：仅允许后端验证后的来源；无法验证时返回空数组。
- `uncertainty`：具体说明仍缺少什么证据。
- `model`：服务端实际使用的模型标识。

识别提示约束：

1. 先依据视觉特征，再使用位置。
2. 位置只用于缩小候选范围，不能作为结论。
3. 不确定时降低置信度并给候选，不编造铭文、年代或来源。
4. 文化解释区分可见事实、推断和需查证事实。
5. 不输出精确人物、年代或机构归属，除非图像证据足够。

## 4. 位置隐私

- 只在用户执行扫描时请求 `When In Use`；不在启动时请求。
- UI 提供“使用附近位置帮助判断”开关，默认开启但首次使用必须显示系统授权。
- App 内部可短暂获得原始定位；发送和持久化前坐标四舍五入到小数点后两位。
- 不保存海拔、速度、航向、设备标识或原始 GPS。
- 照片重新编码后才上传，原始 EXIF/GPS 不离开设备。
- 历史地图仅展示粗粒度位置，并标注“约略位置”。

## 5. 领域模型

新增：

```swift
struct PlaceContext: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var accuracyMeters: Double?
    var displayName: String?
}

struct RecognitionInput: Sendable {
    var imageData: Data
    var place: PlaceContext?
    var contextNote: String?
    var localeIdentifier: String
}

struct RecognitionResult: Codable, Hashable {
    var id: UUID
    var object: CultureObject
    var alternatives: [RecognitionCandidate]
    var rationale: String
    var uncertainty: String?
    var modelIdentifier: String
}

struct CultureRelation: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceID: UUID
    var targetID: UUID
    var kind: RelationKind
    var explanation: String
}
```

`CultureObject` 增加可选关系与模型来源字段。现有样例数据继续遵循同一结构。

## 6. SwiftData 持久化

新增 `ScanHistoryRecord`，只保存用户扫描产生的数据：

- 业务记录 ID（Swift 属性名为 `recordID`）、扫描时间。
- 对象 ID、名称、类别、摘要、时期、地域和置信度。
- 粗粒度经纬度与地点名称。
- App 沙盒内规范化图片的相对路径。
- 识别模型标识。
- 关系与来源 JSON 快照。
- 收藏状态。

图片文件由 `ScanMediaStore` 写入 `Application Support/Scans`。SwiftData 不保存图片大字段。删除记录时由 store 负责同步删除文件；首轮实现先提供单条删除和全量删除入口。

### 6.1 SwiftData 标识约束与兼容迁移

`@Model` 底层使用 Core Data，并为模型提供框架内部的 `id` / `objectID` 标识，因此业务字段不得使用
这两个名称。历史记录使用
`recordID: UUID` 作为路由、地图选择和结果幂等保存所需的稳定业务标识；SwiftUI 列表身份继续使用
SwiftData 模型自身的持久化标识。文化对象外键使用 `cultureObjectID`，不得命名为 `objectID`。

开发期 V1 存储曾使用业务属性名 `id`。该名称已与 SwiftData 内部标识发生运行时冲突，旧记录无法
安全物化，因而不能通过常规轻量迁移读取并复制。修复版使用底层字段名同为 `recordID` 的全新
`CultureLensHistoryV2` 配置。后续验证发现 V2 的业务字段 `objectID` 又与 Core Data
`NSManagedObject.objectID` 冲突，新增记录在保存时会触发 `_NSCoreDataTaggedObjectID` 到 `NSUUID`
的强制转换崩溃。V3 将该字段改为 `cultureObjectID`，并使用全新的 `CultureLensHistoryV3` 配置。
V1/V2 存储文件保留在沙盒中，不主动删除，但不再加载。当前仍处于开发期，旧测试历史不会进入 V3
时间线。所有跨页面查找必须显式比较 `recordID`，不能依赖 SwiftData 内部标识。

## 7. 页面与导航

### 7.1 扫描页

- iOS 使用 AVFoundation 实时预览与拍照；相册使用 `PhotosPicker`。
- 相机不可用或权限拒绝时，使用 `ContentUnavailableView` 并保留相册入口。
- 识别过程中显示阶段、取消和重试。
- 未配置 BFF 时显示明确的“演示识别”标记，并使用 Sample 服务，不伪装成真实模型结果。

### 7.2 扫描结果页

- 独立 `ScanResultView`，显示本次照片、可信度、依据、不确定性、备选候选、位置参与情况和模型标识。
- 用户点击“确认并保存”后才写入扫描历史。
- 确认后可进入完整 `ObjectDetailView`。

### 7.3 文化关系图谱

- `CultureRelationGraphView` 以中心对象和 3-6 个关系节点组成可交互图谱。
- 节点位置由语义槽位确定，不使用力导向随机布局，保证稳定和无障碍。
- 必须提供等价列表模式。
- 选择节点进入 `ConceptDetailView`。

### 7.4 历史扫描地图

- “我的”页拆成“地图 / 时间线”两种主视图。
- 地图使用 MapKit Marker 显示有位置的扫描；无位置记录仍出现在时间线。
- 地图选择记录后显示底部摘要并可进入历史详情。
- 空状态直接引导扫描。

## 8. 错误与降级

- 无权限：相机与位置分别降级，不互相阻塞。
- 无网络或服务不可用：保留当前图片与输入，支持重试；明确允许切换演示识别。
- 低置信度：结果页要求用户从候选中确认，不能自动保存。
- 解析失败：记录 request ID 和非敏感错误类型，不记录图片 Base64 或精确位置。
- 取消：取消当前 Task，不写历史。
- 后端未配置：只使用 Sample 服务并在 UI 常驻“演示模式”标签。

## 9. 配置

App 使用：

- `CultureLensAPI.shared.baseURL`：全局唯一 BFF 根 URL，当前固定为 `https://cl.codight.online`。App 启动即使用远端识别；服务不可用时展示现有可重试的网络失败状态，不静默改用演示识别。

BFF 读取：

- `OPENAI_API_KEY`：必需。
- `OPENAI_VISION_MODEL`：可选，默认 `gpt-5.6-sol`。
- `PORT`：可选。

任何密钥不得写入源码、Info.plist、UserDefaults 或 SwiftData。

## 10. 验证

- 单元测试：图像尺寸/格式、位置降精度、BFF 编解码、样例/远端服务同构、历史 mapper。
- 服务测试：无密钥启动失败、无效请求、OpenAI 非 2xx、拒绝、非法 JSON。
- UI 测试：相册样例 -> 识别进度 -> 结果 -> 确认保存 -> 时间线与地图回看。
- 模拟器：用相册路径验证；相机必须在真机验证。
- 隐私检查：上传数据中不存在 EXIF/GPS，日志无图片与精确坐标。

## 11. 当前实现边界

本轮在仓库中实现 App 客户端、BFF 源码、样例降级与自动测试。没有可用的 BFF 地址或服务端 API Key 时，可以证明接口、状态机、持久化和 UI 流程，但不能声称已完成真实在线识别验证。真实准确率仍需要标注样本集和部署后的端到端评估。
