# App Store Connect 上架与 ODR 分包要点

## Bundle ID 与签名

- Bundle ID：`com.junwei.CultureLens`（Development Team `4RN53WGN2C`，自动签名）。
- 需在 App Store Connect 注册新 App（与旧版 `com.junwei.CultureLens` 相互独立）。
- 能力需求：相机、定位（When In Use）。无 App Groups 以外的特殊能力。

## ODR（On-Demand Resources）

- Tag：`knowledge-base`，内容 = `knowledge-pack.json` + `pack-manifest.json`（约 36KB）。
- 工程配置：`project.pbxproj` 中这两个文件以显式 file reference 加入 Resources phase，`ASSET_TAGS = ("knowledge-base")`；同时通过 `PBXFileSystemSynchronizedBuildFileExceptionSet` 把它们从同步 group 的 target 成员中排除，避免重复打包。
- 当前设置 `ON_DEMAND_RESOURCES_INITIAL_INSTALL_TAGS = "knowledge-base"`：asset pack **随 App 首装一起下发**（用户决定，暂不省下载体积），运行时无需等待下载。
- 将来要省体积/按需分发时，从该 build setting 移除 tag 即可切换为按需下载，工程与代码无需改动。
- 上传：Xcode 归档上传时 asset pack 自动随构建上传到 App Store Connect，无需额外操作。
- 验证：归档后确认 `Products/OnDemandResources/` 存在、`OnDemandResources.plist` 含 `knowledge-base` tag（2026-08-02 已验证）。
- 注意：ODR 内容随 App 版本发布，不能独立热更新；`pack-manifest.json` 的 `packVersion`/`sha256` 为将来多包或自托管下发预留。

## LLM Key

- Cloudflare AI Gateway key 硬编码于 `Services/LLM/LLMGatewayConfig.swift`。已知可被逆向提取，本期接受；上架前建议在 Cloudflare 侧为该 key 配置用量限额与告警。后续可换远程下发或轻代理。

## R2 图床

- 图片以公开 URL 引用（`https://<bucket>.r2.dev` 或自定义域）。需确认 bucket 公开可读、CORS 不影响（原生 URLSession/AsyncImage 无 CORS 概念）、内容有授权。

## 上架前检查单

- [ ] 真机跑通：扫描识别（resolved / attraction / unresolved 三态）、附近推荐、ODR 下载、离线 fallback。
- [ ] App 图标（当前 AppIcon 为空，沿用旧版状态，上架必须补）。
- [ ] 隐私清单（Privacy Manifest）：相机/定位用途字符串已有；用户照片不上传自家服务器，但会经 AI Gateway 发给 Google——隐私标签需如实声明。
- [ ] 归档导出确认 ODR asset pack 拆分正确。
