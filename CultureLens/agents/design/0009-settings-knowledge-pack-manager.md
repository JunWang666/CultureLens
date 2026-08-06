# 0009 设置中的知识资源包管理器

## 背景

App 当前会在 `KnowledgePackLoader` 中自动加载并合并四个知识包，但用户无法确认哪些包可用、版本和内容规模，也无法在 ODR 资源缺失时主动重试下载。

四个包统一改为独立 On-Demand Resources tag，并全部加入 initial-install：

- 西湖：`knowledge-base`（保留现有 tag）。
- 中国历史：`knowledge-chinese-history`。
- 良渚：`knowledge-liangzhu`。
- 浙江省博物馆：`knowledge-zhejiang-museum`。

因此首次安装仍默认随 App 一起交付，但每个包拥有独立的可用状态与下载重试能力，后续可以只调整某个 tag 的分发策略。

## 目标

- 在「设置」中增加「资源包管理」入口。
- 管理页按固定合并优先级展示四个包的名称、来源、版本、内容数量与可用状态。
- 任一 ODR 包未在本机时允许用户单独发起下载或失败后重试。

## 非目标

- 不改变知识包 JSON、UUID、合并优先级或识别契约。
- 不增加 App 内手动删除 ODR 的按钮。`endAccessingResources()` 只会释放访问声明，不能保证系统立即删除磁盘内容，不能把它包装成「删除」。

## 设计

### 状态模型

新增只读的 `KnowledgePackResource` 快照：

- `directory`：沿用 `KnowledgePackDirectory`，作为稳定目录身份。
- `delivery`：四个包均为 `onDemand`。
- `availability`：`available`、`notDownloaded`、`unavailable`。
- 可用时从实际解码后的 `KnowledgePack` 统计 version、elements、attractions、relations、introductions、themes。

状态快照不持久化，避免版本升级后产生陈旧缓存；每次进入页面或手动刷新时重新检查 bundle / ODR。

### ODR 生命周期

`KnowledgePackLoader` 继续是 ODR request 的唯一所有者：

1. `resourceStatuses()` 只做条件访问检查，不会因为打开管理页就自动下载。
2. `downloadOnDemandPack(_:)` 才对指定 tag 调用 `beginAccessingResources()`。
3. 下载完成后重建 loader 的合并缓存，使后续识别、讲解、地图和图谱能使用新包。
4. loader 按目录分别持有 request 与访问状态，避免对同一个 request 重复 begin。
5. App 启动时预加载 initial-install 的四个 tag，并把合并结果安装到线程安全的 `KnowledgeStore.shared` 快照；同步读取知识库的现有页面在根视图刷新后继续工作。
6. 识别、讲解和问答服务允许同步初始化时暂时没有知识包，并在实际异步请求前从 loader 获取；避免所有包迁出 main bundle 后服务被永久初始化为 unavailable。

### UI

- `SettingsView` 增加与现有语言卡片同层级的导航卡片。
- `KnowledgePackManagerView` 使用现有 `CulturePageBackground`、surface card 与 `cultureNavigationTitle`。
- 加载中显示进度；失败显示行内错误与重试；下拉/工具栏刷新重新检查状态。
- ODR 未下载时显示「下载」，下载中显示 spinner；可用包显示「默认安装」。

## 兼容与验证

- iOS 18 deployment target 可继续使用现有 `NSBundleResourceRequest` async overlay。
- 单元测试覆盖资源快照的来源、可用状态与计数映射。
- 在 macOS + Xcode 环境执行 iOS Simulator build 和 CultureLensTests；ODR 的真实下载/清理行为仍需 TestFlight 或真机验证。
