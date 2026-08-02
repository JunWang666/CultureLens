# Design 0021：识别边界前固化图片载荷

- 日期：2026-08-01
- 状态：第二轮修正已实施，待真机端到端回归
- 影响范围：相机照片回调、图片规范化/裁剪、识别输入、远端请求和测试
- 前置设计：
  - `0003-location-aware-recognition-and-history.md`
  - `0006-focused-recognition-and-evaluation.md`
  - `0014-live-camera-capture.md`
  - `0020-database-backed-home-recommendations-and-camera-capture-safety.md`

## 1. 问题

真机通过相机拍照、框选并开始远端识别后，在
`input.imageData.base64EncodedString()` 读取 `Data._Representation` 时触发
`EXC_BAD_ACCESS`。堆栈顶部为 `swift_retain` 和 `outlined copy of Data._Representation`，说明请求尚未发出，
崩溃发生在复制图片数据表示时，不是网络或后端返回导致。

当前图片链路包含两个不明确的所有权边界：

1. `ImagePreprocessor` 使用 `NSMutableData` 接收 ImageIO 编码结果，再以 `output as Data` 桥接返回。
2. 相机的 `fileDataRepresentation()` 直接穿过 AVFoundation delegate、串行 DispatchQueue、MainActor、
   SwiftUI sheet 状态、`Task.detached` 和 `@Sendable` 识别闭包。

Swift `Data` 是值类型且声明为 `Sendable`，但从 Objective-C 可变对象桥接得到的底层表示不应被当作已经拥有独立、
不可变字节的证明。页面 dismiss 与并发任务交错时，继续共享该表示会扩大生命周期和引用计数风险。

第一次修正为各环节增加 owned copy 后，相册选图仍在同一行、同一
`Data._Representation` 复制堆栈触发 `EXC_BAD_ACCESS`。相册链路不经过
`AVCapturePhoto`，因此可以排除相机回调和某一种图片来源；剩余共同路径是
`RecognitionInput(Data)` 依次穿过 `ScanCoordinator` 的任务、类型擦除的
`@Sendable` 操作闭包和远端服务异步函数，最后才读取 `Data`。

## 2. 决策

定义统一的 `Data.ownedCopy()`：通过 `withUnsafeBytes` 创建新的 Swift `Data` 字节存储。图片跨越以下边界时必须
获得 owned copy：

```text
AVCapturePhoto.fileDataRepresentation
  -> ownedCopy
  -> FocusSelectionView

ImageIO NSMutableData 编码完成
  -> Data(bytes:count:) owned copy
  -> SwiftUI @State / ScanCoordinator

RecognitionInput init
  -> whole/focus Base64 String
  -> recognition service
```

- `RecognitionInput` 与 `NormalizedImageRegion` 显式声明为 `nonisolated`，避免项目默认 MainActor 隔离隐式参与
  后台值传递。
- `RecognitionInput` 不再保存 `Data`，而是在构造时同步生成不可变 Base64 字符串。原始图片字节不进入识别服务的
  异步边界，也不会在远端请求组装阶段再次访问 `Data._Representation`。
- `RecognitionService` 去掉 `@Sendable` 操作闭包类型擦除，改为显式的 sample/remote 后端分支。这样可以消除堆栈中
  多层 closure/partial-apply 转发，并让远端服务调用关系可直接追踪。
- 不改变 HTTP 契约、JPEG 质量、最大尺寸、框选算法或后端行为。
- 不依赖在远端请求处捕获异常；`EXC_BAD_ACCESS` 不是 Swift `throw`，必须在数据所有权源头消除。

## 3. 资源边界

- owned copy 会短暂增加图片内存占用，但图片在此前已被限制到最长边 1600 px、JPEG 质量 0.82。
- Base64 会比 JPEG 原始数据增大约三分之一，但当前协议本来就需要 Base64；本次只是把编码时间提前到服务边界之前，
  不增加最终请求体大小。
- `RecognitionInput` 只持有不可变字符串；请求体完成编码后由 `URLRequest` 持有 JSON Data。
- 不长期缓存额外副本，扫描结束或失败后沿现有任务/视图生命周期释放。

## 4. 验证

- 单元测试已覆盖 owned copy 与原可变 Foundation 存储解耦。
- 新增规范化整图和裁剪特写各 16 次并发 Base64 编码压力测试，验证 32 个结果均稳定非空。
- iPhoneOS arm64 Debug 与 App、单元测试、UI 测试 target 的 `build-for-testing` 均通过；本轮没有启动
  Simulator，测试已编译但未实际执行。
- 第二轮新增识别输入预编码测试，验证整图和框选图在进入服务前已可解码回原始字节。
- 最终仍需在真机分别重复“拍照/相册选图 → 框选 → 开始识别”，确认远端服务中已不存在读取图片 `Data` 的代码。
