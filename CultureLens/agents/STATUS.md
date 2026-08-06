# CultureLens STATUS

## 当前阶段

端侧化改造已完成并通过单元测试；讲解 / 追问与用户知识三级状态已接入；P1 三个玩法（文化回顾、主题探索、文化卡片）与视觉备选已落地；多语言基础设施已接入；待真机验证与 App Store 上架准备。

## 已完成

- 2026-08-06 多语言扩展日语 / 俄语：`AppLanguage` 与设置语言偏好增加 `ja` / `ru`；`Localizable.xcstrings` 补齐静态 UI 译文；`PromptLanguagePolicy` / 引用解析 / TTS 语音 / 枚举展示名支持目标语言；知识包正文仍不打包日俄译文，详情与缺 overlay 文案继续走 `KnowledgeTranslationService` 即时翻译。见 `design/0005-i18n-and-knowledge-locale-fallback.md`。
- 2026-08-06 识别绑定收紧：删除空 `cultural_element_key` 的名称 / summary `fromText` 模糊回填与 catalog 名猜测；空 key 保持未绑定，有 key 仍经 `LLMIDSession` 短 ID→UUID。根因修复：浙博包补齐与景点同 key 的 `jade-cong-wang` / `jade-cong-ritual` 看点元素（v8），避免仅装浙博时 `nearbyIntroductions` 因缺元素丢弃之江展陈介绍。见 `design/0021-recognition-no-fuzzy-element-binding.md`。
- 2026-08-06 知识配图整包 ODR：`Resources/images/`（约 180 张，路径对齐 R2）打成 tag `images`，列入 initial-install；`RemoteImageCache` 在内存/磁盘之后、网络之前拦截 `culturelens.goudaijun.top/images/...` 并读本地包；启动预加载与「资源包管理」可单独下载。见 `design/0020-image-pack-odr-and-remote-intercept.md`。
- 2026-08-06 扫描识别新增 MapKit 地理上下文：围绕当前/照片坐标用 `MKLocalPointsOfInterestRequest` 搜索 1 km，二次按直线距离过滤、去重后只向模型发送最近 3 条 POI，并同时发送坐标精度/反向地理名称；MapKit 无网、失败或无结果时不阻断识别，POI 不会写入历史或成为知识库候选。通用 iOS App 与 unit-test target 编译通过，Simulator 运行受既有依赖宏插件阻断。见 `design/0019-recognition-mapkit-geographic-context.md`。
- 2026-08-06 AI 文化讲解从 Caches 缓存升级为 Application Support 正式持久记录：同一对象 / 扫描结果按地点与语言稳定读取，不因知识进度、模型或 prompt 变化自动消失，也不受“清理缓存”影响；讲解组件右上角新增重新生成按钮，生成期间保留旧内容，成功后覆盖保存，失败则保留原讲解。见 `design/0018-durable-explanation-storage-and-regeneration.md`。
- 2026-08-06 时间线足迹从足迹地图模式挪到回顾 Tab：`ReviewHomeView` 分栏同时展示时间线足迹与文化回顾（各预览 10 条，超出后进「更多」全列表；iPad 左右分栏、iPhone 上下堆叠）；足迹页仅保留地图足迹与兴趣点。
- 2026-08-06 AI 文化讲解改为更有现场感的个性化同伴语气：从资料中确实存在的线索或观看角度切入，以自然的引导与节奏展开；优先衔接用户已理解 / 掌握节点，并借已有兴趣重心选择补充角度，不暴露画像或猜测用户偏好。事实来源与引用约束不放宽；其存储生命周期随后由 `design/0018` 升级为正式持久记录。设计见 `design/0017-lively-personalized-explanation-voice.md`。
- 2026-08-06 识别候选改为 1 km 内全量景点：取消最多 8 个景点截断，对应看点根全部进入文化内容候选；附近景点超过 10 个时 prompt 只保留 id/name、省略 introduction 与 nearby_contexts。探索页附近推荐半径不变。新增相关单测 2 项通过；顺手修复探索页 `NearbyEditorialRow` 缺 `number` 参数导致的编译错误。设计见 `design/0015-recognition-1km-all-attractions.md`。
- 2026-08-06 网络产物缓存初版：在线知识图片改为内存 + Caches 磁盘缓存并复用于 Quick Look，即时译文纳入统一清理；AI 讲解最初按可清理缓存实现，随后由 `design/0018` 改为 Application Support 正式持久记录。相关缓存单测、通用 iOS 真机 Debug build 与 `build-for-testing` 均通过。见 `design/0014-network-image-and-llm-result-caching.md`。
- 2026-08-06 足迹支持直接从 Apple Fitness / 健康导入运动路线：只读申请 `HKWorkout` 与 `HKWorkoutRoute`，仅展示实际含 GPS 路线的最近记录，支持多选、按 Workout UUID 幂等导入、独立路线分段和 App 内持久化；删除只影响本地副本。工程已启用 HealthKit capability / entitlement 与读取用途说明，旧 GPX JSON 保持兼容；存储 smoke test、iOS SDK 类型检查、通用 iOS 真机 Debug 构建及 `build-for-testing` 均通过，真实 Fitness 授权和历史数据读取待真机验证。设计见 `design/0013-fitness-workout-route-import.md`。
- 2026-08-06 知识详情在线图片支持点击后用系统 Quick Look（`QLPreviewController`）全屏放大查看：成功加载的 HTTPS 图可点，下载到临时文件后预览，关闭清理；复用既有加载 / 失败 / 重试链路。见 `design/0008-knowledge-detail-remote-images.md`。
- 2026-08-06 Debug / Release 暂时均启用 `EMBED_ASSET_PACKS_IN_PRODUCT_BUNDLE`，使四个 ODR 知识包在 Xcode 侧载与无资源服务器的安装方式中随 App 一起交付；ODR tag、initial-install 与资源包管理器保留。
- 2026-08-06 足迹支持从“文件”批量导入 GPX 运动轨迹：兼容 track / route 与多分段，保留名称、源时间、海拔和完整轨迹点，以独立 JSON 文件持久化到 Application Support，不修改 SwiftData schema；地图足迹叠加彩色轨迹折线，超长分段渲染采样但完整数据保留，并提供显示/隐藏、聚焦和确认删除。新增解析、限制、采样、持久化与删除测试 6 项通过，iOS 18.6 Simulator Debug 编译通过。设计见 `design/0012-imported-workout-tracks.md`。
- 2026-08-06 足迹页的地图足迹 / 兴趣点改为复用同一张 `Map` 与同一套相机状态；切换前固定当前实际相机并关闭模式切换动画，只替换标注层，避免底图重新创建或按新标注自动取景造成跳跃。兴趣点载入 / 空状态改为地图上方提示，搜索、定位和 3D 俯视统一操作共享相机；兴趣点聚合跨度设有上限，避免足迹或 GPX 的远距离视图把城市内大量兴趣点错误堆叠；兴趣点导航优先绑定 attraction 同 slug 的看点根元素，避免三潭印月等景点误跳到首条文化历史介绍。设计见 `design/0011-shared-footprint-poi-map-camera.md`。
- 2026-08-06 探索页新增「点亮图鉴」仪式：复用主题进度点亮文化系，从扫描历史派生已点亮城市，并按首个节点 / 首个文化系 / 首座城市 / 现场扫描数 / 节点数 / 跨城探索解锁六枚徽章；新徽章提供单次庆祝覆盖层、成功触感与 Reduce Motion 适配。城市和徽章均从现有数据派生，不改 SwiftData schema；新增规则单测 3 项通过，iOS Simulator Debug build 通过。设计见 `design/0010-exploration-illumination-and-badges.md`。
- 2026-08-06 设置新增「资源包管理」：展示四个知识包的可用状态、版本与内容数量，并支持缺失时逐包下载 / 重试；西湖 / 中国历史 / 良渚 / 浙博均改为独立 ODR tag，四个 tag 全部设为 initial-install，默认随 App 首装交付。通用 iOS Simulator App build 已通过并确认产出四个独立 asset pack，主 App bundle 不再重复包含知识 JSON。设计见 `design/0009-settings-knowledge-pack-manager.md`。
- 2026-08-06 知识包 UUID 主键迁移完成：entities 以 `id: UUID` 为运行时身份，`key` 为可选 slug；relations / themes / introductions 跨引用改 UUID；识别 / 引用 / 主题进度 / 图谱 API 对齐；LLM 经 `LLMIDSession` 使用 per-request 短 ID 并在入 App 前还原。包版本：西湖 v6 / 历史 v5 / 良渚 v5 / 浙博 v6。单元测试与 `LLMIDSessionTests` 已更新。
- 2026-08-06 图谱捏合缩放锚点修复：全屏图谱（对象关系图谱 + 用户知识图谱）的缩放从 SwiftUI `scaleEffect`（固定绕画布中心缩放，双指位置无效）改为 `ZoomableScrollView`（`UIViewRepresentable` 包装 `UIScrollView.viewForZooming`），捏合以双指中心为锚点，附系统惯性 / 橡皮筋；工具栏 ± / 复位按钮经绑定驱动 `setZoomScale`，内容小于视口时居中，宿主 `UIHostingController` 挂入 VC 链保证节点 popover / 长按菜单可用，节点导航在全屏态改走 `onNavigate` 闭包（宿主内 `NavigationLink` 拿不到栈）。
- 2026-08-06 知识详情在线图片展示完善：继续复用 `RichTextDocument.image` block，不改知识包内容；详情页补齐 HTTPS 图片加载 / 失败 / 重试 / 图注 / VoiceOver 状态，并在 overlay 或即时翻译只返回文本时保留源文档图片。见 `design/0008-knowledge-detail-remote-images.md`。
- 2026-08-06 知识包按 ContentRole 拆 sidecar：看点（`elements-sight`）与文化历史（`elements-history`）分文件，另拆 `introductions` / `themes` / `locales-<lang>`；主 JSON 只留 version / relations；加载时合并并按 `contentRole` 筛选识别 catalog（只收看点）与开放问答兜底（优先文化历史）。版本升至西湖 v5 / 良渚 v4 / 浙博 v5 / 历史 v4（随后 UUID 迁移再升至西湖 v6 / 良渚 v5 / 浙博 v6 / 历史 v5）。
- 2026-08-06 识别候选收紧：`recognitionKnowledge` / prompt / v5 只允许 LLM 选择看点；景点根优先用同 key 看点，现场介绍里的文化历史只进 nearby_contexts / 绑图，不再作为 `cultural_element_key`。
- 2026-08-06 补齐正式 App 图标：将文化镜头图标处理为无透明通道的 1024×1024 iOS 主图，并生成 macOS 全套尺寸资源。
- 2026-08-06 足迹地图完善：右上角三段式模式选择器改为单个原生工具栏菜单，菜单内直接内联地图足迹 / 时间线足迹 / 兴趣点、标准 / 混合 / 卫星底图、足迹照片标记与 3D 俯视选项，消除重复玻璃和二级弹层；接入左下角 Liquid Glass 地点搜索，当前位置按钮移入系统 toolbar（定位后显示约 2 km 范围）；足迹与兴趣点按当前缩放范围合并为 stack 聚合点，点击后在搜索框上方选择具体项目再进入详情，并解除聚合标记与组内首条记录 ID 的隐式绑定；照片标记通过 ImageIO 下采样为 128px 本地预览；修复兴趣点系统标题与自定义标题重复；无带位置足迹时地图仍可搜索和定位。
- 2026-08-05 足迹升级为三模式地图（地图足迹 / 时间线足迹 / 兴趣点，`KnowledgeStore.attractionPoints()` 聚合知识包景点坐标，已到访景点朱砂标记可跳详情）；用户图谱支持多高亮中心（多源 BFS，空选择默认全部已加入节点，`RadialGraphLayout` 多中心内圈簇布局），扫描已记录节点加显眼朱砂徽章；中英词条同步。
- 2026-08-05 浙博 / 良渚包按「有实体即景点」改数据：玉琮王等可拍文物升为 `attractions` 并带展陈坐标；馆区景点保留但不独占附近候选。
- 2026-08-05 多知识包：良渚 / 浙博 / 中国历史打进 App，`KnowledgeStore.mergePacks` + `KnowledgePackLoader` 与西湖 ODR 合并（空 key 模糊名绑定已于 2026-08-06 移除，见 `design/0021`）。
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
3. 真机验证：Fitness / 健康授权与含 GPS 路线的运动记录导入、扫描识别三态、分层讲解、多轮追问（含历史恢复与图片上传）、附近推荐、ODR 下载路径（TestFlight 最佳）、离线 fallback、文化回顾 / 主题探索 / 卡片分享、语言切换与知识译文。
4. 归档 + 导出 ipa，确认 OnDemandResources 拆分；按 `APP_STORE.md` 检查单准备上架。
5. R2 bucket 开通公开读并补内容图片 URL；admin 侧维护含 image block 的介绍。
6. 补隐私清单（照片经 AI Gateway 发 Google 需如实声明；问答上传图片同属此声明）。

## 已知取舍与阻塞

- LLM key 硬编码，需在 Cloudflare 配限额告警（用户已确认接受）。
- ODR 不能独立于 App 版本热更；四包已按地域 / 主题拆成独立 tag，但当前均为 initial-install。
- 丝绸之路包未导入。浙博 / 良渚 / 中国历史与西湖包均为 ODR，并在运行时合并
  （`KnowledgeStore.mergePacks` / `KnowledgePackLoader`）。键冲突仅 `shi-xingeng-discovery`
  （良渚优先）。跨包桥接边已随 UUID 主键落地；详见 `KNOWLEDGE_PACK_GUIDE.md` / `PROJECT.md` 身份模型。
- 关系类型化只覆盖一半：西湖包 94/182 条带 `kind`，另三包 0/310；`conceptKind` 西湖包 70/70，
  另三包 0/106。缺 `kind` 的边无法参与抽象阶梯。
- `理解前先懂` 边全包仅 3 条且都是对象内部细节，不足以支撑「自动补未掌握前置」。
- 上行关系图存在 1 个环（西湖文化景观 → 南宋临安与西湖十景 → 西湖十景的观看方式 → 1985 西湖新十景 →
  西湖文化景观），`产生于` 有约 2/4 条反向边，会导致阶梯层级算错，须先审计。
- 讲解 / 追问依赖 `dynamic/chat` 网关可用性；演示识别结果使用本地占位。
- 本 Cloud VM 无法编译 iOS；P1 改动需在 Mac + Xcode 上跑模拟器验证。
