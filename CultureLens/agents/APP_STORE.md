# App Store Connect 上架与 ODR 分包要点

## Bundle ID 与签名

- Bundle ID：`com.junwei.CultureLens`（Development Team `4RN53WGN2C`，自动签名）。
- 需在 App Store Connect 注册新 App（与旧版 `com.junwei.CultureLens` 相互独立）。
- 能力需求：相机、定位（When In Use）。无 App Groups 以外的特殊能力。

## ODR（On-Demand Resources）

- 四个独立 tag：西湖 `knowledge-base`、中国历史 `knowledge-chinese-history`、良渚 `knowledge-liangzhu`、浙博 `knowledge-zhejiang-museum`。每包内容均为 `knowledge-pack.json` + `elements-sight.json` + `elements-history.json` + `introductions.json` + `themes.json` + `locales-en.json` + `pack-manifest.json`。
- 工程配置：四个目录的文件均以显式 file reference 加入 Resources phase，并分别配置 `ASSET_TAGS`；同步 group 的 `membershipExceptions` 排除这些路径，避免主 bundle 重复打包和同名 JSON 冲突。
- `ON_DEMAND_RESOURCES_INITIAL_INSTALL_TAGS` 当前包含全部四个 tag：四个 asset pack **随 App 首装一起下发**，同时保留逐包状态检查和重新下载能力。
- 上传：Xcode 归档上传时 asset pack 自动随构建上传到 App Store Connect，无需额外操作。
- 验证：归档后确认 `Products/OnDemandResources/` 存在四个 asset pack，`OnDemandResources.plist` 含四个 tag；主 App bundle 不应再包含这些知识 JSON。2026-08-06 已用通用 iOS Simulator build 验证四包拆分与 initial-install manifest。
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
