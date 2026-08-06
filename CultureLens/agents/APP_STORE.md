# App Store Connect 上架与 ODR 分包要点

## Bundle ID 与签名

- Bundle ID：`com.junwei.CultureLens`（Development Team `4RN53WGN2C`，自动签名）。
- 需在 App Store Connect 注册新 App（与旧版 `com.junwei.CultureLens` 相互独立）。
- 能力需求：相机、定位（When In Use）。无 App Groups 以外的特殊能力。

## ODR（On-Demand Resources）

- 知识包单一 tag：`knowledge-base`，内容在 `Resources/KnowledgePack/`（sidecar JSON + `pack-manifest.json`）。源内容在 `agents/knowledge-sources/`，用 `scripts/merge_knowledge_packs.py` 合成。
- 图片包 tag `images`：`Resources/images/{west-lake,chinese-history,liangzhu,zhejiang-museum}/`。
- 工程配置：同步 group 排除上述两个整夹，再以两条 folder reference 分别打 `ASSET_TAGS`，避免逐文件膨胀 `project.pbxproj`。
- `ON_DEMAND_RESOURCES_INITIAL_INSTALL_TAGS` 为 `knowledge-base images`。
- 上传：Xcode 归档上传时 asset pack 自动随构建上传到 App Store Connect。
- 验证：归档后确认 `Products/OnDemandResources/` 存在对应 asset pack；主 App bundle 不应再包含这些知识 JSON / 配图。
- 注意：ODR 内容随 App 版本发布，不能独立热更新。

## LLM Key

- Cloudflare AI Gateway key 硬编码于 `Services/LLM/LLMGatewayConfig.swift`。已知可被逆向提取，本期接受；上架前建议在 Cloudflare 侧为该 key 配置用量限额与告警。后续可换远程下发或轻代理。

## R2 图床

- 图片以公开 URL 引用（`https://<bucket>.r2.dev` 或自定义域）。需确认 bucket 公开可读、CORS 不影响（原生 URLSession/AsyncImage 无 CORS 概念）、内容有授权。

## 上架前检查单

- [ ] 真机跑通：扫描识别（resolved / attraction / unresolved 三态）、附近推荐、ODR 下载、离线 fallback。
- [ ] App 图标（当前 AppIcon 为空，沿用旧版状态，上架必须补）。
- [ ] 隐私清单（Privacy Manifest）：相机/定位用途字符串已有；用户照片不上传自家服务器，但会经 AI Gateway 发给 Google——隐私标签需如实声明。
- [ ] 归档导出确认 ODR asset pack 拆分正确。
