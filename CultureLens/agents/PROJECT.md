# CultureLens 项目说明

## 定位

与 CultureLens 相同的产品体验（扫描识别文化现场、附近推荐、知识图谱、历史），但识别管线完全在端侧运行：

- 本地知识库（西湖内容包：70 元素 / 23 看点 / 114 关系 / 65 介绍，2026-08 sidecar + ContentRole，pack UUID 主键为 **v6**）替代 PostgreSQL。
- 本地完成候选挑选（Haversine 1 km 附近查询、1 km 内全量景点、超 10 个省略介绍、BFS 图谱、景点绑定）与 prompt 拼接（v5 模板 + 候选 JSON），逻辑移植自 Go 后端并按 `design/0015` 收紧半径。
- LLM 调用直连 Cloudflare AI Gateway 的 OpenAI 兼容端点：识别用 `dynamic/culturelens`（多模态），讲解与追问用 `dynamic/chat`（追问可附现场照片，同样走 `image_url`）；key 硬编码于 `Services/LLM/LLMGatewayConfig.swift`（本期接受的安全取舍）。
- 文化问答会话经 JSON 文件（`ChatHistoryStore` → `CultureLens/ChatHistory/conversations.json`）本地持久化，图片落盘于 Application Support `CultureLens/Chats/`。
- 响应在端侧校验映射（key 校验、UUIDv5、富文本压平用于识别摘要、SF Symbol），产出与旧版相同的 `RecognitionResult`；详情页优先用 `RichTextBlocksView` 渲染知识库原文。

## 外部依赖（仅两个）

1. **Cloudflare AI Gateway**：`https://gateway.ai.cloudflare.com/v1/<account>/apps/compat/chat/completions`，多模态 image_url 与 `response_format: json_schema` 已实测可用（实际模型 gemini-3.6-flash）。
2. **Cloudflare R2 图床**：介绍富文本中的 `image` block 直接引用 R2 URL，本地库只存 URL 不存图片。后端 `contentadmin` 校验已放宽接受 image block。

## 身份模型：pack UUID 与 LLM 短 ID

- **运行时身份**是知识包实体的 pack UUID（`Element.id` / `Attraction.id`）。`CultureObject.culturalElementID`、图谱节点、主题进度、引用 URL 的 `elementKey=` 参数在进 App 后一律是 UUID 字符串。
- **编辑 / 迁移**仍可用可选 slug（`key`）；`DeterministicID.culturalElement(_:)` / `attraction(_:)` 对 slug 铸 UUIDv5，与后端 Go `uuid.NewSHA1(NameSpaceURL, …)` 兼容。
- **LLM 契约**用每请求短 ID：`LLMIDSession` 把元素与景点各自从 `"1"` 起独立编号写入 prompt；模型回写短 ID 后，经 `resolveElement` / `resolveAttraction` / `remapElementShortIDs` 还原为 pack UUID，再进 `RecognitionResponseMapper` 与引用解析。短 ID 绝不持久化。
- 知识包中 attraction 与其绑定元素**有意可共用 slug**；识别映射按「景点优先、展品回落节点」解析（`RecognitionResponseMapper.responseObject`），图谱成员身份永远是绑定元素的 UUID。

## 多语言

- UI 文案：`Localizable.xcstrings`（zh-Hans / en），语言偏好在「我的」页。纯 `String` 文案经 `String(localized:)` / `LocalizedStringKey` 接入目录；构建后用 `xcstringstool sync`（配合 DerivedData 里的 `.stringsdata`）同步新 key。
- LLM（识别 `dynamic/culturelens`、讲解/问答 `dynamic/chat`）：按目标语言直接生成；见 `PromptLanguagePolicy`。
- 知识包：`source_language` + `locales` overlay；译文暂缺时详情页用 `dynamic/chat` 即时翻译（`KnowledgeTranslationService`，`thinking: { type: "disabled" }`），翻译期间显示骨架屏（`SkeletonViews`），译好后直接展示，不再先显示原文再替换。设计见 `agents/design/0005`。

## 知识包与 ODR 分包

- 四个数据目录分别打成独立 ODR asset pack，由 App Store 托管：
  - `Resources/KnowledgePack/`（西湖）→ `knowledge-base`。
  - `Resources/KnowledgePackChineseHistory/`（中国历史）→ `knowledge-chinese-history`。
  - `Resources/KnowledgePackLiangzhu/`（良渚）→ `knowledge-liangzhu`。
  - `Resources/KnowledgePackZhejiangMuseum/`（浙博）→ `knowledge-zhejiang-museum`。
- 四个 tag 当前均列入 **initial-install**（`ON_DEMAND_RESOURCES_INITIAL_INSTALL_TAGS`），默认随 App 首装交付，但仍可被系统清理并在「设置 → 资源包管理」中逐包重新下载。
- 运行时：`KnowledgePackLoader` 持有每个 tag 的 `NSBundleResourceRequest`，按西湖 / 中国历史 / 良渚 / 浙博顺序加载并由 `KnowledgeStore.mergePacks` 合并；ID 冲突时先到先得。
- 知识包当前以仓库内 sidecar JSON 为源；需要更新时编辑对应目录并同步 `pack-manifest.json`。

## 抽象轴与图谱渲染（0006 / 0007）

- 关系抽象方向：`RelationKind.abstractionDirection`（上行 / 下行 / 横向 / 前置），`产生于` 因数据中存在反向边暂不纳入默认上行集合。
- 有向遍历：`KnowledgeStore.upward/downward/lateral/ancestors/siblings/missingPrerequisites`，含环检测与层级去重，全部为纯函数（`AbstractionAxisTests` 以真实西湖包断言「三潭印月 → 宋代山水审美」可达）。
- 讲解契约：`explainUserText` payload 新增 `abstraction_path` / `missing_prerequisites` / `preference_profile` / `user_knowledge_total_count`，邻居按轴分配名额；`explain.txt` 输出扩为三节（「先理解」仅当前置缺失时出现），旧两节格式讲解仍可正常解析展示。
- 关联脉络：讲解契约再增 `relation_dimensions`（`KnowledgeStore.edges(key:kinds:)` 按 kind 取边、方向不解释，每维上限 2 条），覆盖五个固定维度——历史时期（产生于）、地域文化（位于）、使用功能（用于）、审美观念（体现/象征/受到影响）、相似对象（相似于）；维度邻居的 introduction 并入 `knowledge_fragments` 供引用。输出在「文化背景」后新增「关联脉络」节，仅写有数据的维度；注意输出骨架由 `PromptLanguagePolicy.explainMarkdownSkeleton` 在运行时重写（英文为「Connections」），`explain.txt` 文末模板仅作同步文档。
- 抽象阶梯：`DesignSystem/AbstractionLadderView`（纵向祖先链 + 同级 chips），曾接入扫描结果页（对象/概念详情复用该页）；因展示价值有限当前已在 `ScanResultView` 隐藏，组件保留，恢复时还原该处调用即可。
- 图谱渲染：`RadialGraphLayout` 共享内核（重心排序 + 方向分层偏置，确定性 O(V+E)），对象图谱与用户图谱共用，内核支持多中心（中心簇均布内圈小圆，各自向外发散）；边按 5 个语义族着色/线型/图标，图例可点选筛选；用户图谱接入捏合缩放、搜索筛选、列表模式、可搜索多选中心（默认全部已加入节点为中心）、截断提示、前置未掌握标记与扫描已记录朱砂徽章。
- 足迹双模式：`CultureMapView` 切换「地图足迹 / 兴趣点」；兴趣点来自 `KnowledgeStore.attractionPoints()`（按 knowledge pack 现场介绍聚合坐标），已到访（命中扫描记录的 `culturalElementID`）用朱砂 checkmark 标记，可跳转知识节点详情。时间线足迹改在回顾 Tab（`ReviewHomeView`：时间线足迹 / 文化回顾）。
- 内容重构（2026-08 完成）：四包边已按统一方向语义重写（kind / conceptKind / 前置边覆盖、`产生于` 取向审计、跨包重复实体合并、跨包前置边接入历史包地基），规范见 `agents/KNOWLEDGE_PACK_GUIDE.md`。**UUID 主键迁移已完成**（pack `id` + 跨引用 UUID；LLM 用 per-request 短 ID）；西湖包 en 正文翻译待补。

## 已移除的后端

Go BFF（`CultureLensBackend/`）已从仓库删除。识别与知识检索均在端侧完成；`RemoteRecognitionService`、`CultureLensAPI` 等远程调用路径亦已删除。

## 杂志化视觉语言（2026-08）

- 版面组件：`DesignSystem/MagazineHeader.swift`（`MagazineSectionHeader` 栏目头 / `MagazinePageHeader` 页头；英文 eyebrow 是版面装饰，`Text(verbatim:)` 不进本地化目录）；远程照片统一暖调用 `View.magazinePhoto()`。
- 标题宋体：`Font.magazineDisplay(...)`。内置子集化思源宋体 `Resources/Fonts/CultureLensSerif-SemiBold.ttf`（GB2312 字符集子集 ≈3MB；OFL 的 Reserved Font Name 约束要求改名，许可见同目录 `OFL.txt`），`CultureThemeFonts` 运行时注册并探测，回退链：内置宋体 → Songti SC → 系统衬线。
- 页面背景：`CulturePageBackground` 用运行时生成的纸纹颗粒平铺，不再用光斑。
- 版面原则：分栏细线（hairline rule）与大留白代替圆角卡片盒；刊头不放品牌字标。探索页（刊头 + NEARBY / COLLECTION / COVER STORY / UP NEXT 栏目）是参考实现。
- ODR 注意：asset pack 内文件为扁平布局，`KnowledgePackLoader.loadPack` 需从包根目录读取（子目录候选仅为 bundle 内旧布局保留）。
