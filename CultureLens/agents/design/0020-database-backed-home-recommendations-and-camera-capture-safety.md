# Design 0020：数据库首页推荐与相机拍照安全

- 日期：2026-08-01
- 状态：已实施，待真机拍照回归
- 影响范围：首页数据流、公开内容 API 客户端、位置权限说明、AVFoundation 拍照配置和测试
- 前置设计：
  - `0014-live-camera-capture.md`
  - `0017-cultural-elements-and-attraction-introductions.md`
  - `0018-go-cultural-content-query-api.md`
  - `0019-west-lake-content-admin.md`

## 1. 问题

探索首页的“基于位置推荐”仍直接读取 `SampleCultureData.objects.prefix(2)`。这些对象属于早期 UI 样例，
与已经切换到 `cultural_elements`、`attractions` 和 `attraction_cultural_introductions` 的生产数据库无关，
因此即使数据库已清空或替换，首页仍会显示并不存在于数据库中的两张对象卡。

真机拍照还会在 `AVCapturePhotoOutput.capturePhoto` 抛出 Objective-C exception。当前每次都把
`AVCapturePhotoSettings.photoQualityPrioritization` 强制设为 `.quality`，但没有保证它不超过当前
`AVCapturePhotoOutput.maxPhotoQualityPrioritization`。Simulator 不提供真实相机，无法暴露这个硬件约束。

## 2. 决策

### 2.1 首页只显示生产内容

“基于位置推荐”改为以下数据流：

```text
LocationContextProvider（降精度位置）
  -> GET /v1/attraction-introductions/recommendations
  -> NearbyRecommendationsResponse
  -> 景点特定介绍卡片
```

- 首页不再从 `SampleCultureData` 读取推荐，也不在请求失败或空结果时回退到样例对象。
- 返回卡片直接使用后端的介绍 key、名称、文化元素、景点、富文本摘要和距离，不强行转换成旧
  `CultureObject`，避免伪造类别、时期、图谱或来源。
- 位置不可用、服务失败或附近无内容时显示明确状态；重试只重新请求真实位置和真实 API。
- UI 测试模式不发起位置与网络请求，避免系统权限弹窗干扰既有扫描主流程。
- 首页继续只展示最多两条，但两条必须来自本次数据库 API 响应。

### 2.2 拍照质量遵守输出能力

- 每次创建 `AVCapturePhotoSettings` 后，将其 `photoQualityPrioritization` 设为当前
  `photoOutput.maxPhotoQualityPrioritization`，不再无条件请求 `.quality`。
- 会话配置、运行状态和单次 completion 防重逻辑保持不变。
- 这样仍使用该输出在当前设备/格式上允许的最高优先级，同时避免“设置值超过输出最大值”的 exception。

## 3. 数据模型

App 新增只对应公开内容 API 的只读模型：

```text
RichTextDocument { schemaVersion, blocks[] }
AttractionIntroductionRecommendation
  key, name, introduction
  culturalElement { key, name }
  attraction { key, name }
  location { latitude, longitude }
  distanceMeters
NearbyRecommendationsResponse
  requestedLocation, totalMatches, introductions[]
```

这些类型不替代识别结果的 `CultureObject`；后续若增加文化元素详情路由，应基于 element key 单独设计。

## 4. 隐私与权限

- 首页复用现有 reduced-accuracy 定位并在发送前保留二位小数降精度，不保存首页位置。
- `NSLocationWhenInUseUsageDescription` 同步说明“附近内容推荐”和“识别候选”两个用途。
- 请求半径为后端允许的 50 km，附近没有数据库内容时返回空状态，不用固定地点数据冒充当前位置推荐。

## 5. 验证

- 单元测试已增加生产响应字段和富文本解码覆盖；App、单元测试和 UI 测试 target 的 iPhoneOS
  `build-for-testing` 编译通过。
- iOS Simulator Debug 构建 0 警告通过；随后 iPhoneOS arm64 Debug 构建通过。
- 首页源码不再引用 `SampleCultureData`，也移除了旧“屋檐之下”样例主题和“UI 演示”文案。
- 生产公开接口以西湖坐标查询返回 10 条真实数据库介绍，限制 2 条时返回文澜阁与三潭印月内容。
- 仍需在真机重新验证连续拍照、框选入口和离开页面后相机会话停止；编译和 Simulator 不能替代该项。
