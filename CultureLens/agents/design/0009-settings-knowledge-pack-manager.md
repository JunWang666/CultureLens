# 0009 设置中的知识资源包管理器

## 背景

App 通过 ODR 交付知识与配图资源，用户需要确认版本、内容规模，并在系统清理按需资源后重新下载。

当前发行形态：

- 文化知识库：单一 tag `knowledge-base`（`Resources/KnowledgePack/`，由 `agents/knowledge-sources/` 四源合并）。
- 配图：tag `images`。

二者均为 initial-install；Debug / Release 可启用 `EMBED_ASSET_PACKS_IN_PRODUCT_BUNDLE` 以便侧载。

## 目标

- 在「设置」中提供「资源包管理」入口。
- 展示知识包与图片包的版本、内容数量与可用状态。
- ODR 缺失时允许重新下载。

## 非目标

- 不在 App 内提供“删除 ODR”按钮（`endAccessingResources()` 不能保证立即清盘）。

## 设计

### 状态模型

- `KnowledgePackResource`：目录身份、`onDemand` 交付、可用性、version 与计数。
- `ImagePackResource`：图片包独立快照。

### ODR 生命周期

`KnowledgePackLoader` / `ImagePackLoader` 各自持有 `NSBundleResourceRequest`：

1. 管理页 `resourceStatuses()` 只做条件访问，不自动下载。
2. 用户触发时才 `beginAccessingResources()`。
3. 成功后刷新运行时快照。

### UI

- `KnowledgePackManagerView`：杂志化列表，展示知识库与图片包。
