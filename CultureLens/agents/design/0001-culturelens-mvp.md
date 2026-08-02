# Design 0001：CultureLens MVP

- 状态：已采纳，Phase 1 UI 骨架已实现
- 日期：2026-07-27
- 依据：`/Users/goudaijun/Downloads/CultureLens.pdf`
- 影响范围：应用导航、领域模型、持久化结构、识别与文化知识服务边界

## 1. 目标

用一个可替换数据源的 iPhone SwiftUI 应用，验证以下闭环：

> 用户看到陌生文化对象 -> 拍摄 -> 获得可信的对象解释 -> 沿文化关系继续探索 -> 将理解结果沉淀到个人文化地图

MVP 的成功标准不是“识别所有对象”，而是证明识别、解释、关联和积累这四步能形成清晰、有价值的体验。

## 2. 信息架构

应用采用三个顶层入口，每个入口维护独立导航历史：

1. `探索`：推荐主题、最近识别、拍摄入口。
2. `扫描`：相机/相册、识别过程、识别结果。
3. `我的`：个人文化地图、收藏、历史和设置。

核心页面：

- `ExploreHomeView`
- `CaptureView`
- `RecognitionProgressView`
- `ObjectDetailView`
- `ConceptDetailView`
- `AskCultureView`
- `CultureMapView`
- `CollectionView`
- `SettingsView`

扫描是主操作，可作为中间 Tab，也可由首页主按钮直接切入。识别结果进入独立 `NavigationStack`，关系节点继续推入详情，避免多层 sheet。

## 3. 首版用户流程

### 3.1 主流程

1. 用户点击扫描。
2. 拍摄或选择照片。
3. 应用展示识别进度和可取消状态。
4. 服务返回一个主要候选项和可选备选项。
5. 用户确认对象，进入对象详情。
6. 页面先显示一句话结论，再按“历史、地域、功能、审美、相似对象”组织关系。
7. 用户点亮关系节点、收藏对象或继续提问。
8. 探索记录写入 SwiftData，并更新个人文化地图。

### 3.2 降级流程

- 低置信度：展示 2-3 个候选对象，请用户确认。
- 无法识别：允许补充地点、类别或重新拍摄。
- 网络失败：保留本地照片引用与待处理任务，支持重试。
- 知识不足：明确标记“资料不足”，不生成确定性结论。
- 来源不可用：不展示无引用的历史事实。

## 4. 视觉与交互方向

从效果稿提取以下视觉语言：

- 背景：温暖米白，不使用纯白大面积铺底。
- 主色：深海军蓝；强调色：克制的朱橙；辅助色：淡金。
- 图形：细线描、文化纹样、关系连线和轻量水墨层次。
- 卡片：低对比边框、较大留白、少量圆角，不做通用科技产品式高饱和渐变。
- 信息层级：对象名称和一句话解释优先，文化关系图其次，长文下沉。

实现时优先使用 SwiftUI 原生材质、形状和 SF Symbols。主题插画作为独立资源，不把重要文字烘焙进图片。动态字体、VoiceOver、降低动态效果和高对比模式必须可用。

详细的 iOS 26 Liquid Glass 使用边界、页面构成、设计 Token 和验收规则见 `0002-humanist-liquid-glass-ui.md`。若两份文档对 UI 的描述冲突，以 0002 为准。

## 5. 应用结构

建议采用按功能分组、单 target 起步的结构：

```text
CultureLens/
  App/
    CultureLensApp.swift
    AppRootView.swift
    AppRoute.swift
    AppTab.swift
  Domain/
    Models/
    Repositories/
  Features/
    Explore/
    Capture/
    ObjectDetail/
    CultureMap/
    Profile/
  Services/
    Recognition/
    CultureKnowledge/
    Media/
  Persistence/
    Models/
    Mappers/
  DesignSystem/
    Theme/
    Components/
  Resources/
    SampleData/
```

边界原则：

- SwiftUI View 只负责渲染和局部交互。
- 共享服务通过 `@Environment` 注入。
- 功能内状态由 `@Observable` 模型在页面根部持有，并显式传给子视图。
- 领域模型使用值类型，不直接依赖 SwiftData。
- SwiftData 模型只负责本地持久化，通过 mapper 与领域模型转换。
- 首版不拆 Swift Package，待模块稳定或需要复用时再拆。

## 6. 导航与状态

使用 `TabView`，每个 Tab 内一个独立 `NavigationStack`。路由只保存轻量、稳定的标识符：

```swift
enum AppRoute: Hashable {
    case object(id: CultureObject.ID)
    case concept(id: CultureConcept.ID)
    case session(id: ExplorationSession.ID)
    case ask(objectID: CultureObject.ID)
}
```

不把 View、照片二进制或完整领域对象放入路由路径。拍摄来源选择等短时模态使用枚举驱动的 `.sheet(item:)`。

异步状态统一建模，避免散落多个布尔值：

```swift
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(UserFacingError)
}
```

## 7. 领域数据设计

### 7.1 核心实体

```swift
struct CultureObject: Identifiable, Codable, Hashable {
    let id: UUID
    var canonicalName: String
    var summary: String
    var category: ObjectCategory
    var timePeriod: String?
    var region: String?
    var heroImage: URL?
    var sources: [KnowledgeSource]
}

struct CultureConcept: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var kind: ConceptKind
    var summary: String
}

struct CultureRelation: Identifiable, Codable, Hashable {
    let id: UUID
    let sourceID: UUID
    let targetID: UUID
    var kind: RelationKind
    var explanation: String
    var sourceIDs: [UUID]
}

struct RecognitionCandidate: Identifiable, Codable, Hashable {
    let id: UUID
    let objectID: UUID
    var confidence: Double
    var rationale: String?
}

struct ExplorationSession: Identifiable, Codable, Hashable {
    let id: UUID
    var createdAt: Date
    var place: PlaceContext?
    var recognizedObjectIDs: [UUID]
    var exploredConceptIDs: [UUID]
}
```

辅助类型：

- `ObjectCategory`：建筑构件、器物、纹样、展品、空间、其他。
- `ConceptKind`：历史、地域、功能、审美、人物、技法、相似对象。
- `RelationKind`：产生于、位于、用于、象征、受到影响、相似于、组成。
- `KnowledgeSource`：标题、发布者、URL、发布日期、访问日期、授权说明。
- `PlaceContext`：用户授权后保存粗粒度地点和场景标签，不默认保存精确坐标。

### 7.2 用户状态

```swift
struct LearningState: Codable, Hashable {
    let conceptID: UUID
    var level: UnderstandingLevel
    var isBookmarked: Bool
    var lastExploredAt: Date
    var revisitCount: Int
}
```

`UnderstandingLevel` 首版使用离散等级 `seen / explored / understood`，不要在缺少行为依据时伪造精细知识分数。

### 7.3 SwiftData 持久化

MVP 仅持久化用户产生的数据：

- `SavedObjectRecord`
- `LearningStateRecord`
- `ExplorationSessionRecord`
- `PendingRecognitionRecord`

文化对象、概念和关系由 repository 提供并可缓存，但不在首版把完整知识库建成 SwiftData 图数据库。这样可以避免远端内容版本升级与用户数据迁移耦合。

照片不直接作为 SwiftData 大字段保存。仅保存应用沙盒内文件 URL、缩略图 URL 和处理状态；用户删除会话时一并清理对应文件。

## 8. 服务协议

```swift
protocol ObjectRecognitionService: Sendable {
    func recognize(_ input: RecognitionInput) async throws -> RecognitionResult
}

protocol CultureKnowledgeRepository: Sendable {
    func object(id: UUID) async throws -> CultureObject
    func concepts(for objectID: UUID) async throws -> [CultureConcept]
    func relations(for objectID: UUID) async throws -> [CultureRelation]
}

protocol ExplanationService: Sendable {
    func explain(
        objectID: UUID,
        question: String?,
        learningContext: [LearningState]
    ) async throws -> CultureExplanation
}
```

首版提供两套实现：

- `SampleRecognitionService` + `BundledCultureRepository`：离线样例演示和稳定 UI 测试。
- `RemoteRecognitionService` + `RemoteCultureRepository`：后续真实服务，占位但不阻塞 UI。

生成式讲解必须基于检索到的 `KnowledgeSource` 和结构化关系，返回引用列表。UI 不把模型自由生成内容伪装成已验证事实。

## 9. 识别与知识处理流程

```text
照片/相册
  -> 方向与尺寸规范化
  -> 场景元数据（需授权）
  -> 对象识别候选
  -> 用户确认或自动采用高置信候选
  -> 获取对象与文化关系
  -> 结合 LearningState 生成分层解释
  -> 写入 ExplorationSession
  -> 更新个人文化地图
```

推荐阈值先作为可配置策略，不写死在 View：

- 高置信：直接进入结果并允许更换候选。
- 中置信：先显示候选选择。
- 低置信：请求补充信息或重新拍摄。

具体数值必须用真实样本评估后确定。

## 10. 隐私、安全与可信度

- 相机和相册权限文案说明用途，不在启动时抢先请求。
- 上传前压缩并移除非必要 EXIF；位置单独授权。
- 日志不得记录照片内容、精确位置或完整用户问题。
- 每条关键文化事实展示来源入口。
- AI 输出区分“已识别”“可能是”“相关资料表明”等确定性等级。
- API 密钥不放入 App；真实服务通过受控后端访问。

## 11. 分阶段实施

### Phase 1：可交互样例闭环

- 替换模板 `Item`。
- 建立 App Shell、路由、主题和领域模型。
- 使用 3-5 个本地样例对象与关系数据。
- 完成探索、模拟扫描、对象详情、概念详情、收藏和文化地图。
- 建立单元测试、关键 UI 流程和无障碍标识。

验收：无网络也能完整演示一次“拍摄 -> 理解 -> 关联 -> 积累”。

### Phase 2：系统媒体能力

- 接入相机与 `PhotosPicker`。
- 图片规范化、权限、错误与重试。
- 本地文件生命周期和待识别任务。

验收：真实设备可稳定拍摄/选图，取消、拒绝权限、后台切换均不丢状态。

### Phase 3：真实识别与知识服务

- 选定云端多模态或端侧模型路线。
- 建立后端代理、结构化响应和来源校验。
- 加入候选确认、低置信度降级和可观测性。

验收：在约定样本集上达到明确的准确率、响应时间和引用完整率目标。

### Phase 4：个性化与扩展

- 基于 `LearningState` 调整解释层级。
- 主题探索、文化回顾、路线推荐。
- 评估 AR 标注、多语言和机构端。

## 12. 测试策略

- 领域测试：关系过滤、学习状态升级、会话合并、来源完整性。
- 服务契约测试：样例服务与远端服务输出遵循同一模型。
- 持久化测试：新增、恢复、删除会话及图片清理。
- View 状态测试：idle/loading/loaded/failed/low-confidence。
- UI 测试：从探索页进入扫描，确认对象，点亮节点，在文化地图中回看。
- 真机测试：相机权限、内存压力、后台恢复和弱网。

## 13. 关键决策

1. iPhone 优先，其他平台暂不作为 Phase 1 验收目标。
2. 样例数据与真实服务共用领域模型和协议。
3. 领域模型与 SwiftData 持久化模型分离。
4. 知识关系使用显式实体，而不是把所有内容塞进一段生成文本。
5. 用户学习状态只记录可解释行为，不推断未经验证的能力分数。
6. 第一版使用单 target 功能分组，不提前拆包。

## 14. 待确认问题

1. Phase 1 首批样例对象选择哪些具体建筑、构件或纹样？
2. 竞赛演示是否要求现场真实识别，还是稳定样例闭环即可？
3. 是否已有可合法使用的文化资料库与图片资源？
4. 产品名称最终写作 `CultureLens` 还是视觉稿中的 `Culture Lens`？
5. 是否需要账号、云同步或团队共享文化地图？

## 15. Phase 1 UI 骨架实现记录

2026-07-27 已按本设计完成首轮 UI 骨架：

- 使用三个原生 Tab 和各自独立的 `NavigationStack`。
- 建立 `CultureObject`、`CultureConcept`、`KnowledgeSource` 等值类型领域模型。
- 使用三个内置样例对象打通探索、扫描占位、对象详情、概念详情、追问占位和文化地图。
- 删除 SwiftData 模板 `Item`；本轮不建立持久化模型，收藏与探索进度仍为界面状态。
- 扫描入口只导航到固定样例结果，不访问相机、相册、网络或识别算法。

真实媒体、识别服务、知识服务和 SwiftData 用户记录仍分别留在后续阶段。
