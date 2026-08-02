# Design 0014：实时相机扫描界面

- 日期：2026-07-30
- 状态：已实施，待真机验证
- 影响范围：扫描页、相机采集、手电筒控制、图片框选入口和 UI 测试降级
- 前置设计：
  - `0002-humanist-liquid-glass-ui.md`
  - `0003-location-aware-recognition-and-history.md`
  - `0006-focused-recognition-and-evaluation.md`

## 1. 问题

当前扫描页使用渐变和虚线框模拟取景画面，只有点击拍照后才弹出系统
`UIImagePickerController`。因此扫描页本身看不到实时摄像头，也无法让页面上的手电筒按钮控制当前取景。
顶部在线状态、位置和帮助操作也与本轮确认的极简相机界面不一致。

## 2. 决策

扫描页改为嵌入 AVFoundation 实时后置相机：

```text
AVCaptureDevice 后置摄像头
  -> AVCaptureSession
  -> AVCaptureVideoPreviewLayer 实时预览
  -> AVCapturePhotoOutput 拍照
  -> JPEG Data
  -> 现有 FocusSelectionView
  -> 现有预处理、位置获取与远端识别
```

相机界面顶部不保留任何操作控件。底部固定只有三个操作：

1. 左侧：从相册选取。
2. 中间：拍照。
3. 右侧：手电筒开关。

识别进度和错误卡片是临时状态反馈，不属于固定按钮组，继续显示在底部按钮上方。

## 3. 相机会话边界

- 相机视图内部持有 `AVCaptureSession`、后置 `AVCaptureDevice` 和 `AVCapturePhotoOutput`。
- 会话配置、启动、停止、拍照和 torch 配置在专用串行队列执行，避免阻塞主线程。
- SwiftUI 通过一次性 `captureRequestID` 请求拍照；相机视图用 ID 去重，避免视图刷新重复拍摄。
- 拍照完成只回传 JPEG `Data`，后续继续复用现有框选和识别数据流。
- 进入相册、离开扫描页或相机不可用时关闭手电筒。
- 手电筒只在设备同时满足 `hasTorch`、`isTorchAvailable` 和支持目标模式时启用；配置前后使用
  `lockForConfiguration()` / `unlockForConfiguration()`。

## 4. 权限与降级

- 继续使用现有 `NSCameraUsageDescription`。
- 未决定权限时由 AVFoundation 请求相机权限。
- 权限拒绝、无后置相机、Simulator、macOS 或 visionOS 不伪造实时画面；保留现有背景作为降级。
- 相机不可用时拍照按钮打开帮助页；UI 测试仍可从帮助页使用样例图片。
- 相册选择保持可用，手电筒按钮显示但禁用。

## 5. UI 与可访问性

- 实时预览铺满扫描页安全区外背景。
- 现有取景框提示继续覆盖在预览上，帮助用户把对象放入画面。
- 相册、拍照、手电筒都保留 VoiceOver 标签和至少 44 pt 触控区域。
- 手电筒开启时使用填充图标和可见 tint，VoiceOver 文案变为“关闭手电筒”。
- 顶部状态、位置和帮助整排移除；位置识别保持默认开启并继续只使用约略位置。

## 6. 验证

- iOS Simulator Debug 编译 0 错误、0 警告。
- Simulator 中相机与手电筒正确降级，相册和样例图片流程仍可用。
- 现有 Swift 单元测试与受影响 UI 流程通过。
- 真机验证实时预览、权限首次请求、拍照方向、相册、手电筒、切换 Tab 后关闭硬件和框选入口。

## 7. 当前边界

- 本轮只使用后置默认摄像头，不提供前后摄像头切换、变焦、曝光补偿或多镜头选择。
- 真机硬件行为无法由 Simulator 证明，编译和模拟器降级验证通过后仍必须真机验收。
