# CultureLens STATUS

## 当前阶段

端侧化改造已完成并通过单元测试；讲解 / 追问与用户知识三级状态已接入；P1 三个玩法（文化回顾、主题探索、文化卡片）与视觉备选已落地；待真机验证与 App Store 上架准备。

## 已完成

- 2026-08-03 P1 玩法：文化回顾（按时间+地点聚合成「行程」汇总页）、主题探索（知识包 `themes` + 进度）、文化卡片分享（复用 `CultureObjectCard`，与回顾合并）；识别结果保留模型视觉 alternatives，不再只展示附近景点候选。
- 2026-08-03 文化问答页输入框调整为 ChatGPT 风格紧凑单胶囊布局：空输入保持 48pt 单行高度，输入换行后才按内容增长；左侧快捷入口、中部多行输入、麦克风入口，以及随输入状态切换的蓝色语音波形 / 发送按钮；保留中文输入法候选确认与发送键语义。
- 2026-08-03 聊天 UI 换成 Messages 风格气泡 + Microsoft `SwiftStreamingMarkdown` 流式 Markdown 渲染；问答改为 SSE `stream: true`（`dynamic/chat`）。未采用 ExyteChat：其强制依赖 Giphy SDK，体积与审核成本过高。
- 2026-08-03 讲解生成（`CultureExplanationService` + `explain` prompt / `dynamic/chat`）与多轮追问（`AskCultureView` + `CultureChatService`）；PromptAssembler / v5 增加用户知识状态与「跳过已知、锚定已知、补缺」；对象 / 概念 / 扫描结果详情用 `RichTextBlocksView`；用户状态升级为接触 / 理解 / 掌握（SwiftData 存时间戳与来源）。
- 2026-08-03 真实用户文化图谱落地：所有已加入节点始终可见，并从可选中心按无向 BFS 向外展开 3 层；采用确定性同心最短路布局、48 节点扩展上限和单 `Canvas` 批量绘边控制开销。原「收藏」/「我已了解」统一为持久化「加入文化图谱」，旧 UserDefaults 状态迁移进 SwiftData。
- 2026-08-03 修复照片框选在 iPhone 与 13 英寸 iPad 上的坐标漂移：手势统一到预览命名坐标系，并扣除 aspect-fit 黑边偏移；最小框改为 16pt 屏幕尺寸，发送标注与屏幕框保持一致，补充跨设备坐标映射单测。
- 2026-08-02 工程从 CultureLens 复制重命名（bundle ID `com.junwei.CultureLens`，SwiftData 配置 `CultureLensHistoryV1`），模拟器构建通过。
- 2026-08-02 端侧识别管线移植完成：`Services/Knowledge`（KnowledgeStore / Haversine / 候选挑选 / BFS 图谱）、`Services/LLM`（PromptAssembler / LLMGatewayClient，CF AI Gateway `dynamic/culturelens`）、`Services/Recognition`（ResponseMapper / OnDeviceRecognitionService / UUIDv5）。`RemoteRecognitionService`、`CultureLensAPI` 已删除；`CultureContentService` 改本地查询。
- 2026-08-02 知识包落地：`Resources/KnowledgePack/`（西湖包 + manifest），ODR tag `knowledge-base` 接线完成，`KnowledgePackLoader` ODR 优先、内置 fallback 兜底。
- 2026-08-02 富文本支持 image block（R2 URL）；`RichTextBlocksView` 渲染。
- 2026-08-02 CF AI Gateway 实测可用；模拟器 E2E 测试门控。
- 单元测试覆盖 Haversine、候选优先级、UUIDv5、bundle 解码、image block、行程聚合与主题进度等。
- 2026-08-02 Release 归档（免签名）验证通过。正式上传需先在 Xcode 登录 Apple ID。

## 下一步

1. 真机验证：扫描识别三态、讲解/追问、附近推荐、ODR、文化回顾 / 主题探索 / 卡片分享。
2. 归档 + 导出 ipa；按 `APP_STORE.md` 准备上架。
3. R2 bucket 公开读并补内容图片 URL。
4. 补 App 图标与隐私清单。

## 已知取舍与阻塞

- LLM key 硬编码，需在 Cloudflare 配限额告警（用户已确认接受）。
- ODR 不能独立于 App 版本热更；多地域拆分待内容增长后执行。
- 丝绸之路包未导入，本期仅西湖包。
- 讲解 / 追问依赖 `dynamic/chat` 网关可用性；演示识别结果使用本地占位。
- 本 Cloud VM 无法编译 iOS；P1 改动需在 Mac + Xcode 上跑模拟器验证。
