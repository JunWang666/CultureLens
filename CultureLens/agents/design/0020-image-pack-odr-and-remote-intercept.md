# 0020 图片包 ODR 与远程加载拦截

## 背景

知识详情与探索页的配图仍以 HTTPS URL（`https://culturelens.goudaijun.top/images/...`）保存在知识包 JSON 中，便于编辑与 R2 回源。`RemoteImageCache`（见 `0014`）已统一内存 + 磁盘缓存，但缺网或冷启动时仍会打到图床。仓库内已有与 CDN 路径对齐的 `Resources/images/` 镜像，需要整包按需交付并在加载路径上优先读本地。

## 决策

### ODR 图片包

- 将 `Resources/images/{west-lake,chinese-history,liangzhu,zhejiang-museum}/` 打成单一 ODR asset pack，tag `images`。
- 与知识 JSON 相同：同步 group 的 `membershipExceptions` 排除这些路径，显式 file reference 进入 Resources 并设置 `ASSET_TAGS = (images,)`，避免主 bundle 重复打包。
- `images` 列入 `ON_DEMAND_RESOURCES_INITIAL_INSTALL_TAGS`；Debug/Release 仍可 `EMBED_ASSET_PACKS_IN_PRODUCT_BUNDLE` 以便侧载。
- 运行时由 `ImagePackLoader` 持有 `NSBundleResourceRequest(tags: ["images"])`，启动时在 `AppRootView` 与知识包并行 `ensureAvailable`；设置「资源包管理」可查看状态并单独重新下载。

### 加载拦截

- 不引入 `URLProtocol`。继续走 `RemoteImageCache.data(for:)` 单点：
  1. 内存 `NSCache`
  2. `Library/Caches/CultureLens/RemoteImages`
  3. **本地 ODR**：`ImagePackPathMapping` 解析 host + `/images/{pack}/{file}` → `ImagePackLoader.dataIfAvailable`
  4. 网络 `URLSession`
- ODR 命中后写入磁盘缓存，使 Quick Look 与后续视图重建无需再次触达 pack。
- 清理「网络缓存」只删磁盘/内存缓存，不删除 ODR 图片包。

### URL 与包内布局

- 知识 JSON 继续只存 HTTPS URL，不改内容契约。
- Asset pack 可能扁平到根目录；嵌入 bundle 时可能带 `west-lake/` 或 `images/west-lake/` 前缀。`ImagePackLoader` 按这三类候选查找。当前跨目录 basename 无冲突，扁平布局安全。

## 非目标

- 不按知识包拆四个图片 tag（需要时可再拆，路径映射已带 pack 段）。
- 不热更新图片；更新随 App 版本发版。
- 不缓存非 `culturelens.goudaijun.top/images/` 的任意远程图到 ODR。

## 验证

- 路径解析与「本地 provider 优先于网络」单测。
- 构建产物含 `images` asset pack；主 bundle 不再同步复制 `Resources/images`。
- 真机：断网打开知识详情，已装图片包时仍能出图；设置中可重新下载。
