# Design 0006：用户框选、多候选与识别效果评测

- 状态：已确认，进入实现
- 日期：2026-07-29
- 影响范围：扫描交互、图片预处理、iOS 识别请求、Go 识别管线、Gemini Provider、Prompt/Schema 版本与离线评测
- 前置设计：
  - `0003-location-aware-recognition-and-history.md`
  - `0005-go-recognition-and-knowledge-backend.md`

## 1. 问题

当前 App 在拍照或选择相册图片后立即识别。文化现场图片经常同时包含屋檐、梁柱、纹样、说明牌和
人物，模型无法知道用户真正想问哪一处。只发送整图会让背景中的显著对象抢占判断；只发送裁剪图又会
丢失建筑空间、陈列场景和对象尺度等上下文。

当前服务虽然返回主结果和备选项，但没有用评测数据证明模型、图片输入策略或 Prompt 的选择。只凭单张
样例或主观观感不能声称“识别效果最好”。

## 2. 决策

采用“整图上下文 + 用户框选特写 + 多候选确认”的识别方式：

1. 拍照或选择图片后，先进入框选页，不立即发起网络识别。
2. 用户可拖动并缩放矩形框，明确指出要识别的对象；也可选择“识别整张”。
3. App 对方向归一后的图片执行裁剪。框选时同时发送：
   - 整图：只用于场景和空间上下文。
   - 框选特写：作为主要视觉证据。
4. Gemini 请求中明确标记两张图片的职责，要求不得用整图中的其他显著对象覆盖框选目标。
5. 服务始终返回一个主候选和最多三个备选候选；候选必须按可能性排序并分别给出可见证据。
6. 结果页由用户确认主候选或任一备选后再保存。
7. 默认模型从吞吐优先的 `gemini-3.5-flash-lite` 改为多模态质量优先的
   `gemini-3.6-flash`；正式切换结论仍必须由同一授权评测集验证。

不采用“只把矩形坐标写进文字 Prompt”的方案。直接发送裁剪图能让框内小纹样、构件接缝和铭文获得
足够的视觉分辨率，同时避免服务端引入新的图像裁剪依赖。

## 3. iOS 数据流

```text
Camera / PhotosPicker
  -> ImagePreprocessor.normalizedJPEG
  -> FocusSelectionView
       -> 识别整张
       -> 或 NormalizedRegion(x, y, width, height)
  -> ImagePreprocessor.croppedJPEG
  -> RecognitionInput
       imageData: 整图
       focusImageData: 可选框选特写
  -> RemoteRecognitionService
  -> ScanResultView 多候选确认
```

`NormalizedRegion` 使用方向归一后图片的左上角坐标系，所有值位于 `0...1`。它只属于本次短期编辑状态，
不写入 SwiftData。框选识别后，`ScanSession.imageData` 使用裁剪后的特写，结果页和扫描历史保存用户
真正询问的对象；整图只在请求期间保留，不新增历史持久化字段。

框选页状态由页面本地 `@State` 持有。网络、定位和取消仍由 `ScanCoordinator` 管理，不把手势状态放进
Coordinator。

## 4. 框选交互

- 初始框覆盖图片中央约 70% 区域，避免用户从极小框开始调整。
- 拖动框内部移动；拖动四角调整大小。
- 最小框边长为可见图片短边的 18%，防止误触产生无法辨认的微小裁剪。
- 框始终限制在图片可见区域内。
- 底部提供“识别框选区域”和“识别整张”两个清晰操作。
- VoiceOver 提供整图识别，并为框选区域提供位置和尺寸说明；精细拖拽不是完成任务的唯一方式。
- 框选图片处理失败时停留在本页并允许重试或改用整图。

## 5. API v1 兼容扩展

`POST /v1/recognitions` 增加可选字段，不破坏旧客户端：

```json
{
  "image_base64": "<完整图片>",
  "mime_type": "image/jpeg",
  "focus_image_base64": "<框选特写，可选>",
  "focus_mime_type": "image/jpeg"
}
```

约束：

- 请求总大小继续受 18 MiB HTTP 上限保护。
- 两张图片分别校验 Base64、MIME、图片头和像素数。
- 只接受 JPEG 或 PNG；当前 iOS 始终发送重新编码、无 EXIF/GPS 的 JPEG。
- Provider 接收已校验的 `MediaInput{ContextImage, FocusImage}`，不读取请求中的 Base64。
- 日志只记录是否使用框选，不记录图片、Base64 或框选内容。

## 6. Gemini 输入策略

识别请求使用同一个 `generateContent` 调用：

```text
任务说明
-> 整图（存在框选时为 medium；否则为 high）
-> “下面是用户框选的目标特写”
-> 框选特写（high）
```

使用版本化 `recognition-v2` Prompt，并加入以下规则：

- 有特写时只识别特写中的中心目标，整图仅用于场景、尺度和相邻结构。
- 候选名称必须互斥且具体；同义名称合并为一个候选。
- 输出 1 个主结果和 1 至 3 个备选；证据不足可少于 3 个，不凑数。
- 置信度不是统计概率，不允许所有候选都给出虚假高分。
- 无法可靠识别时主结果为“其他”，并说明下一张照片需要补充的视角或细节。

`generationConfig` 使用 JSON Schema 约束类别枚举、置信度范围、必填字段和备选数量。服务仍需执行语义
校验，Schema 通过不等于识别事实正确。

## 7. 模型与分辨率策略

依据当前 Google 官方能力说明，`gemini-3.6-flash` 比 `gemini-3.5-flash-lite` 更适合复杂多模态和空间
推理，作为质量优先默认值。Flash-Lite 保留为低成本对照组。

图片分辨率策略：

- 仅整图：`MEDIA_RESOLUTION_HIGH`。
- 整图 + 特写：整图 `MEDIA_RESOLUTION_MEDIUM`，特写 `MEDIA_RESOLUTION_HIGH`。
- 不默认使用 `ULTRA_HIGH`；只有评测证明对小纹样或铭文有稳定增益时才切换。

模型、Prompt、Schema 和图片策略都必须作为独立评测维度记录，不能一次同时更改后只报告总结果。

## 8. 离线评测

实现 `cmd/eval`，读取只引用已授权本地图片的 JSONL 数据集。每条样本至少包含：

```json
{
  "id": "case-001",
  "image_path": "images/case-001.jpg",
  "focus": {"x": 0.18, "y": 0.22, "width": 0.44, "height": 0.51},
  "expected_names": ["斗拱"],
  "known": true,
  "tags": ["建筑构件", "复杂背景"]
}
```

同一批样本至少比较：

1. 整图 high。
2. 仅裁剪图 high。
3. 整图 medium + 裁剪图 high。
4. 第 3 种策略分别使用 Flash-Lite 与 Flash。
5. 有位置与无位置。

主要指标：

- Top-1 名称命中率。
- Top-3 候选召回率。
- 未知对象拒识率。
- 结构化输出成功率。
- 框选相对整图的提升和退化样本数。
- P50/P95 延迟。

首个可用报告至少需要 30 张已授权图片，并覆盖建筑构件、器物、纹样、展品、空间、未知对象和复杂背景。
样本不足时只报告冒烟结果，不声称模型优劣。

## 9. 验证

- 单元测试：归一化框坐标、边界限制、裁剪像素尺寸、裁剪后无 GPS/EXIF。
- iOS 合约测试：有/无 `focus_image_base64` 均可编解码。
- Go 合约测试：双图成功、非法特写、超限和旧单图请求兼容。
- Provider 测试：双图顺序、媒体分辨率和 JSON Schema 都进入请求。
- UI 验证：相册 -> 框选 -> 识别 -> 多候选切换 -> 确认保存。
- 后端：`go test ./...` 与 `go vet ./...`。
- App：iOS Debug build 和单元测试；相机继续要求真机验证。

## 10. 当前边界

- 本设计先实现框选、双图输入、多候选和可复现评测工具骨架。
- 没有授权数据集和真实模型报告前，只能说明方案依据与工程能力，不能宣称已找到最终最优模型。
- 不使用模型自动生成的候选写入正式知识图谱。
- 端到端保存验证暴露出 V2 的 `ScanHistoryRecord.objectID` 与 Core Data 内部 `objectID` 冲突；
  按 0003 的兼容规则改为 `cultureObjectID` 并启用 V3 存储，不迁入开发期 V2 测试记录。
