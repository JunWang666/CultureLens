# 0007 图谱渲染、性能与交互整备

- 状态：已实现（2026-08-05）。阶段 1–4 全部完成：共享渲染内核 + 重心排序 + 方向分层、语义族配色与图例筛选、`UserKnowledgeGraphEdge` 带类型、缩放与适配、`joinedSeeds` 索引化与重建去抖、搜索 / 筛选 / 列表模式 / 可搜索中心选择 / 截断提示 / 全屏路由修复 / 空态归因、前置未掌握节点标记。

## 背景

图谱是立项书的核心差异点，但当前观感仍是毛坯。按真实西湖包（70 元素 / 182 关系 / 平均度 5.2）
复算布局数学，问题可量化：

| 指标 | 实测 |
| --- | --- |
| 画布尺寸（48 节点 / 3 层） | 1710×1710 到 2197×2197 pt |
| iPhone 视口一次可见比例 | 5.7%，且图谱 Tab **没有缩放** |
| 同屏可见边数 | 98–124 条 |
| 48 节点上限 | 每一个中心都会触发截断，UI 从不提示 |

根因不是缺功能，而是下列具体缺陷叠加。

## 缺陷清单

### 布局

- **环上排序不看连接关系**：`GraphLayout` 与 `UserKnowledgeGraphLayout` 均按
  `$0.name < $1.name` 沿环排布，完全不考虑谁与谁有边。1 环 12 点方向的节点连到 2 环 6 点方向，
  连线直接穿过中心卡片。48 节点 100+ 条边如此绘制即成毛线团。这是毛坯感的首要来源。
- **同心环表达不了抽象方向**：按 hop 分环只能表达「离中心几跳」，无法表达 `0006` 的上行 / 下行 / 横向。

### 绘制

- **边未内缩**：`UserKnowledgeGraphView.edgeCanvas` 直接
  `path.move(to: source); path.addLine(to: target)`，端点即节点中心，线明显压在 146×86 卡片下再穿出。
  对象图谱的 `EdgeGeometry` 已实现 78pt 内缩与箭头，用户图谱未复用。
- **12 种关系被压成 3 色**：`color(for relation:)` 只区分 `prerequisiteFor`（朱红）、
  `governedBy` / `expresses` / `explains`（金），其余 8 种（`产生于` `位于` `用于` `象征` `受到影响`
  `相似于` `组成` `制作采用`）全部同一灰色同一虚线。图例文案「前置知识 / 制度与语境 / 其他关系」
  与 `RelationKind` 的 12 项、`ConceptKind` 的 9 项都对不上。
- **边标签只在连着中心时渲染**：`showsLabel:` 条件导致 2 跳以外的边全部无标签。

### 语义丢失

- `UserKnowledgeGraphEdge` 只有 `id` / `sourceID` / `targetID`，**没有 `kind` 与 `explanation`**。
  `KnowledgeStore.userKnowledgeGraph` 建边时把知识包已有的类型与说明直接丢弃。
  于是图谱 Tab 的边仅按「是否连着中心」分两种灰度，没有类型、没有标签、没有列表模式、没有关系解释。
  类型化工作到了对象图谱，却没到用户真正会打开的那个 Tab。

### 性能

- **重建图谱触发上千次 JSON 解码**：`UserKnowledgeGraphView.joinedSeeds` 对每个已加入节点调
  `object(id:)`，后者遍历**全部**历史记录调 `record.savedObject`；而 `savedObject` 每次访问都执行
  `JSONDecoder().decode`，失败路径再解一次 legacy 格式；`concept(id:)` 又遍历解码一遍。
  `rebuildGraph()` 在加入状态变化、历史变化、会话变化与**每次点选中心**时同步触发。
  30 个已加入节点 × 100 条历史 ≈ 9000 次完整快照解码，全在主线程。
- **对象图谱每帧重算布局**：`GraphLayout(object:)` 在 `graph` / `staticGraphPreview` / `zoomableGraph`
  等计算属性内构造，每次 body 求值都重跑 BFS + 分组 + 排序，包括捏合时
  `MagnifyGesture` 连续更新 `transientMagnification` 的每一帧。

### 交互与状态

- 图谱 Tab 无缩放、无适应屏幕、无缩略图，只有双向 `ScrollView`；`GraphZoom`
  （50%–250%、fit-to-viewport、pinch）已实现但只接在对象图谱全屏模式。
- `isExpansionTruncated` 已计算且有单测，**UI 从不显示**（0002 约定的截断提示在沉浸式改版中丢失）；
  而实测每个中心都会截断，用户看到的是无声被砍到 48 个的任意子集。
- 图谱 Tab 无搜索、无筛选、无选中高亮邻居、无列表模式（同时丢失 VoiceOver 可用通道）。
- `centerMenu` 是 48 项平铺字母序 `Menu`。
- `staticGraphPreview` 在 270pt 高框内按 100% 绘制再裁切，等于钥匙孔；`GraphZoom.fittedScale` 就在旁边未被使用。
- `fullscreenDestination(for:)` 只处理 `.concept`，`.knowledgeElement` 与 `.object` 一律「当前入口不可用」。
- 空态「关系资料不足」对任何未匹配到知识库的扫描都显示，读起来像内容缺失，实际是未绑定。

## 设计

### 统一两套渲染内核

抽出共享的 `RadialGraphLayout` 与图谱画布组件，让 `CultureRelationGraphView` 与
`UserKnowledgeGraphView` 共用同一套半径计算、边几何（内缩 + 箭头）、缩放与图例。
当前两套各写一遍，是图谱 Tab 长期落后于对象图谱的结构性原因。

### 布局：重心排序 + 方向分层

保留 0002 确立的「确定性、无迭代模拟、O(V+E)」约束（不退回力导向），仅把排序依据从名称改为重心排序：
第 k 环节点按其在第 k−1 环已定位邻居的平均角度排列，再做一到两轮中位数扫描。
仍然确定性、线性，但能消掉绝大部分穿心长边。

接入 `0006` 的方向表后，进一步把纯 hop 同心环改为方向分层：上行边向上、下行边向下、横向边水平。
两项合并为一次布局改造，不做两遍。

### 关系语义族

不做 12 种颜色（读不出来），归并为 4–5 个语义族，每族一个颜色 + 线型 + 图标：

| 族 | 含 RelationKind |
| --- | --- |
| 前置与构成 | `理解前先懂` `组成` |
| 时空来源 | `产生于` `位于` |
| 功能与工艺 | `用于` `制作采用` |
| 意涵与审美 | `象征` `体现` `受规制于` `受到影响` |
| 类比 | `相似于` `解释` |

图例与族一一对应，并支持点图例筛选。边标签显示条件从「连着中心」放宽到「当前选中节点的邻边」。

### 语义补全

`UserKnowledgeGraphEdge` 增加 `kind` 与 `explanation`，`KnowledgeStore.userKnowledgeGraph` 透传；
图谱 Tab 补列表模式，既作为大图下的兜底浏览方式，也作为 VoiceOver 可用路径。

### 缩放与视口

图谱 Tab 复用 `GraphZoom`：进入时 fit-to-viewport，捏合 50%–250%，工具栏 ±25% 与「回到适合大小」，
并把中心节点滚到视口中央。`staticGraphPreview` 改用 `GraphZoom.fittedScale` 缩到能看全。

同时重新标定 48 的展开上限——2000pt 画布配手机屏是失衡的，建议默认降到 24 左右并提供「展开更多」，
且把 `isExpansionTruncated` 真正显示出来。

### 性能

- `joinedSeeds` 改为一次性建立 `[UUID: CultureObject]` 索引，或给 `savedObject` 加惰性缓存，
  避免在循环内反复解码；`rebuildGraph` 的快照与布局计算移出主线程或加去抖。
- 对象图谱把 `GraphLayout` 提到 `@State`，仅在 `object.id` 变化时重算，捏合期间不重跑 BFS。

### 查找与导航

按名称搜索、按 `ConceptKind` 与掌握程度筛选；选中节点时高亮邻居并淡化其余；
`centerMenu` 从 48 项平铺 `Menu` 换为可搜索选择列表；
修 `fullscreenDestination` 使 `.knowledgeElement` 与 `.object` 均可打开。

### 空态归因

拆成三种不同文案：未匹配到知识库对象、知识包未载入、该节点确实没有关系边。

## 分阶段任务

**阶段 1（能看）**：统一渲染内核；重心排序；边内缩与箭头；`UserKnowledgeGraphEdge` 带类型；
语义族配色与图例；图谱 Tab 接入缩放与适配；预览用 fittedScale。

**阶段 2（不卡）**：`joinedSeeds` 索引化 / `savedObject` 缓存；`GraphLayout` 提到 `@State`；
重建去抖。

**阶段 3（能用）**：搜索与筛选；选中高亮；列表模式；可搜索中心选择器；截断提示；
全屏路由修复；空态归因。

**阶段 4（表达抽象轴）**：方向分层布局 + 前置节点显式标记（未掌握用警示色，点击直达讲解「先理解」小节）。
依赖 `0006` 阶段 1。

## 验证

- 布局改造可量化单测，不依赖 UI 截图：同一中心下可见边交叉数降至改造前三分之一以内；
  相同输入两次布局结果完全一致（确定性）。
- 性能改造用已加入节点数 × 历史条数的合成数据断言解码次数上界。
- 视觉与手势部分需 Mac + Xcode 模拟器与真机验证；当前 Cloud VM 无法编译 iOS。
