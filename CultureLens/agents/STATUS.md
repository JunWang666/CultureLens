# CultureLens STATUS

## 当前阶段

端侧化改造已完成并通过单元测试；讲解 / 追问与用户知识三级状态已接入；P1 三个玩法（文化回顾、主题探索、文化卡片）与视觉备选已落地；多语言基础设施已接入；待真机验证与 App Store 上架准备。

## 已完成

- 2026-08-06 知识包 `ContentRole`：有实体「看点」与无实体「文化历史」分文件（`elements-sight.json` / `elements-history.json`）并在元素上显式标注；识别 catalog / 无景点 fill 只收看点，问答兜底优先文化历史。
- 2026-08-05 足迹升级为三模式地图（地图足迹 / 时间线足迹 / 兴趣点，`KnowledgeStore.attractionPoints()` 聚合知识包景点坐标，已到访景点朱砂标记可跳详情）；用户图谱支持多高亮中心（多源 BFS，空选择默认全部已加入节点，`RadialGraphLayout` 多中心内圈簇布局），扫描已记录节点加显眼朱砂徽章；中英词条同步。
- 2026-08-05 浙博 / 良渚包按「有实体即景点」改数据：玉琮王等可拍文物升为 `attractions` 并带展陈坐标；馆区景点保留但不独占附近候选。
- 2026-08-05 多知识包：良渚 / 浙博 / 中国历史打进 App，`KnowledgeStore.mergePacks` + `KnowledgePackLoader` 与西湖 ODR 合并；识别名允许子串绑定（如「玉琮」→「玉琮王」）。
- 2026-08-04 统一文化问答系统提示词结构，强化正文行内引用与文末来源列表的一一对应、编码和原文摘录规则；面向用户的回答改用“现有资料”等自然表述，不再暴露内部资料系统称谓。
- 2026-08-04 修复文化问答作曲器：恢复系统原生多行 `TextField` 以避免中文输入法候选态丢失焦点；去掉底部整条材质背景和闲置副标题，输入区改为 Liquid Glass 容器（旧系统回退材质），附件缩略图收进同一容器并在有图时向上扩展，关闭键紧贴图片，添加菜单锚定在 `+` 按钮。
- 2026-08-03 文化问答增强：SwiftData 持久化历史会话（首页 / 对象追问分作用域）、工具栏新对话与历史列表、相册图片上传（归一化 JPEG + 多模态 `image_url`）；历史轮用文字标注避免重复传图。见 `agents/design/0005-chat-history-and-image-upload.md`。
- 2026-08-03 P1 玩法：文化回顾（按时间+地点聚合成「行程」汇总页）、主题探索（知识包 `themes` + 进度）、文化卡片分享（复用 `CultureObjectCard`，与回顾合并）；识别结果保留模型视觉 alternatives，不再只展示附近景点候选。
- 2026-08-03 多语言基础设施：`Localizable.xcstrings`（zh-Hans / en）固化 UI 文案；「我的」页语言偏好；识别 / 讲解 / 问答经 `PromptLanguagePolicy` 直接输出目标语言；知识包增加 `source_language` + `locales` overlay（内容暂空），详情页缺译文时用 `dynamic/chat` 即时翻译并缓存。见 `design/0005-i18n-and-knowledge-locale-fallback.md`。
- 2026-08-03 文化问答页输入框调整为 ChatGPT 风格紧凑单胶囊布局：空输入保持 48pt 单行高度，输入换行后才按内容增长；左侧快捷入口、中部多行输入、麦克风入口，以及随输入状态切换的蓝色语音波形 / 发送按钮；保留中文输入法候选确认与发送键语义。
- 2026-08-03 聊天 UI 换成 Messages 风格气泡 + Microsoft `SwiftStreamingMarkdown` 流式 Markdown 渲染；问答改为 SSE `stream: true`（`dynamic/chat`）。未采用 ExyteChat：其强制依赖 Giphy SDK，体积与审核成本过高。
- 2026-08-03 讲解生成（`CultureExplanationService` + `explain` prompt / `dynamic/chat`）与多轮追问（`AskCultureView` + `CultureChatService`）；PromptAssembler / v5 增加用户知识状态与「跳过已知、锚定已知、补缺」；对象 / 概念 / 扫描结果详情用 `RichTextBlocksView`；用户状态升级为接触 / 理解 / 掌握（SwiftData 存时间戳与来源）。
- 2026-08-03 真实用户文化图谱落地：所有已加入节点始终可见，并从可选中心按无向 BFS 向外展开 3 层；采用确定性同心最短路布局、48 节点扩展上限和单 `Canvas` 批量绘边控制开销。原「收藏」/「我已了解」统一为持久化「加入文化图谱」，旧 UserDefaults 状态迁移进 SwiftData。
- 2026-08-03 修复照片框选在 iPhone 与 13 英寸 iPad 上的坐标漂移：手势统一到预览命名坐标系，并扣除 aspect-fit 黑边偏移；最小框改为 16pt 屏幕尺寸，发送标注与屏幕框保持一致，补充跨设备坐标映射单测。
- 2026-08-04 问答历史改出 SwiftData，改为 `ChatHistoryStore` JSON 文件持久化（修复 `ChatConversationRecord` fetch/save `SIGABRT`）；主库升为 `CultureLensHistoryV3`（仅扫描历史 + 知识进度）。
- 2026-08-02 工程从 CultureLens 复制重命名（bundle ID `com.junwei.CultureLens`，SwiftData 配置 `CultureLensHistoryV1`），模拟器构建通过。
- 2026-08-02 端侧识别管线移植完成：`Services/Knowledge`（KnowledgeStore / Haversine / 候选挑选 / BFS 图谱）、`Services/LLM`（PromptAssembler / LLMGatewayClient，CF AI Gateway `dynamic/culturelens`）、`Services/Recognition`（ResponseMapper / OnDeviceRecognitionService / UUIDv5）。`RemoteRecognitionService`、`CultureLensAPI` 已删除；`CultureContentService` 改本地查询。
- 2026-08-02 知识包落地：`Resources/KnowledgePack/`（西湖包 + manifest），ODR tag `knowledge-base` 接线完成，`KnowledgePackLoader` ODR 优先、内置 fallback 兜底。
- 2026-08-02 富文本支持 image block（R2 URL）；`RichTextBlocksView` 渲染。
- 2026-08-02 CF AI Gateway 实测可用；模拟器 E2E 测试门控。
- 单元测试覆盖 Haversine、候选优先级、UUIDv5、bundle 解码、image block、行程聚合与主题进度等。
- 2026-08-02 Release 归档（免签名）验证通过。正式上传需先在 Xcode 登录 Apple ID。

## 下一步

1. 抽象阶梯与前置知识感知讲解，见 `design/0006-abstraction-axis-and-prerequisite-aware-explanation.md`：
   关系方向表与有向遍历 API（可先在 Cloud 环境纯单测验证）→ `产生于` 取向审计与多包合并 →
   讲解 prompt 三节改造 → 阶梯 UI。
2. 图谱渲染、性能与交互整备，见 `design/0007-graph-rendering-performance-and-interaction.md`：
   重心排序与边内缩、图谱 Tab 缺失的缩放、用户图谱丢失的关系类型、`joinedSeeds` 解码风暴。
   方向分层布局与 `0006` 阶段 1 合并实施。
3. 真机验证：扫描识别三态、分层讲解、多轮追问（含历史恢复与图片上传）、附近推荐、ODR 下载路径（TestFlight 最佳）、离线 fallback、文化回顾 / 主题探索 / 卡片分享、语言切换与知识译文。
4. 归档 + 导出 ipa，确认 OnDemandResources 拆分；按 `APP_STORE.md` 检查单准备上架。
5. R2 bucket 开通公开读并补内容图片 URL；admin 侧维护含 image block 的介绍。
6. 补 App 图标与隐私清单（照片经 AI Gateway 发 Google 需如实声明；问答上传图片同属此声明）。

## 已知取舍与阻塞

- LLM key 硬编码，需在 Cloudflare 配限额告警（用户已确认接受）。
- ODR 不能独立于 App 版本热更；多地域拆分待内容增长后执行。
- 丝绸之路包未导入。浙博 / 良渚 / 中国历史三个包已随 App 打包，并与西湖包在运行时合并
  （`KnowledgeStore.mergePacks` / `KnowledgePackLoader`）。键冲突仅 `shi-xingeng-discovery`
  （良渚优先）。跨包桥接边与 UUID 命名空间仍见 `design/0006` 待做。
- 关系类型化只覆盖一半：西湖包 94/182 条带 `kind`，另三包 0/310；`conceptKind` 西湖包 70/70，
  另三包 0/106。缺 `kind` 的边无法参与抽象阶梯。
- `理解前先懂` 边全包仅 3 条且都是对象内部细节，不足以支撑「自动补未掌握前置」。
- 上行关系图存在 1 个环（西湖文化景观 → 南宋临安与西湖十景 → 西湖十景的观看方式 → 1985 西湖新十景 →
  西湖文化景观），`产生于` 有约 2/4 条反向边，会导致阶梯层级算错，须先审计。
- 讲解 / 追问依赖 `dynamic/chat` 网关可用性；演示识别结果使用本地占位。
- 本 Cloud VM 无法编译 iOS；P1 改动需在 Mac + Xcode 上跑模拟器验证。
