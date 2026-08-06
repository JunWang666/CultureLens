# 0014 网络图片与 LLM 结果缓存

> AI 文化讲解部分已由 `design/0018` 的正式持久存储取代；在线图片与即时译文缓存决策继续有效。

## 背景

知识详情与探索页的远程图片此前使用 `AsyncImage`。SwiftUI 因横竖屏、语言或资源状态重建页面后，视图本地状态丢失，图片可能重新请求。扫描结果页的个性化文化讲解也只保存在 `ScanExplanationSectionView.@State` 中，离开页面再回来会重新调用 `dynamic/chat`。

即时知识翻译已有内存 + `UserDefaults` 缓存，但设置页没有统一清理入口。

## 决策

### 在线图片

- 新增 `RemoteImageCache` actor，使用 URL 的 SHA-256 作为不泄露原始地址的文件名。
- 查找顺序为内存 `NSCache` → `Library/Caches/CultureLens/RemoteImages` → 网络；同 URL 的并发请求共享进行中的 Task。
- `CachedAsyncImage` 保留 `AsyncImagePhase` 风格的 SwiftUI 接口，统一替换知识详情、附近看点缩略图和封面故事图片。
- Quick Look 预览先从 `RemoteImageCache` 取数据，再生成带扩展名的临时文件，避免点击已显示图片时第二次下载。

### AI 文化讲解

- 新增 `CultureExplanationCache` actor，将完整 `PersonalizedExplanation` 持久化到 `Library/Caches/CultureLens/LLM/explanations-v2.json`，最多保留 80 条，按最旧写入时间淘汰。
- 缓存键包含完整识别结果、地点上下文、排序后的用户知识状态、目标语言、模型名与显式 schema 版本。知识状态、语言或输入变化会自然生成新键。
- 页面加载优先读取缓存；只有 miss 才流式请求 LLM。成功收到 finished 事件后才写缓存，断流的 partial 内容不持久化。
- 已完成讲解下方提供「刷新讲解」。刷新绕过读取但保留旧缓存，只有新讲解成功后才原键替换；刷新失败时下次进页面仍能回退旧结果。

### 统一清理

- 设置页新增「网络缓存」区块与二次确认。
- 清理范围：远程图片、AI 文化讲解、即时知识译文。
- 明确不清理：扫描历史、问答记录及聊天图片、文化图谱进度、导入轨迹、知识资源包。

## 不缓存的请求

- 文化问答每一轮依赖完整会话上下文，缓存“下一条回答”会改变对话语义；回答已经随聊天记录持久化，因此不另建响应缓存。
- 扫描识别结果已经由 `ScanSessionStore` 和扫描历史持有，页面布局切换不会重新识别；用户主动重新扫描仍应得到新的模型判断，因此本次不增加跨扫描识别缓存。

## 失效与演进

- 图片缓存遵循显式清理；服务端若需要立即更新图片，应使用版本化 URL。
- 讲解 prompt/schema 的语义发生不兼容变化时，提升 `CultureExplanationCache` 的 key schema 与落盘文件版本。
- 缓存目录位于系统 Caches 域，iOS 可在空间紧张时清理；所有读取 miss 都能回源恢复。

## 验证

- 远程图片落盘复用/清理、讲解缓存落盘复用/清理，以及缓存键对知识状态与语言变化的 3 项 Simulator 单元测试全部通过。
- 通用 iOS 真机 Debug build 与 `build-for-testing` 通过。
- 仍需在真机上验证切换横竖布局、返回重进页面、刷新讲解和设置清理的实际交互。
