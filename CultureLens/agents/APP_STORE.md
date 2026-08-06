# App Store Connect 上架与 ODR 分包要点

## Bundle ID 与签名

- Bundle ID：`com.junwei.CultureLens`（Development Team `4RN53WGN2C`，自动签名）。
- 需在 App Store Connect 注册新 App（与旧版 `com.junwei.CultureLens` 相互独立）。
- 能力需求：相机、定位（When In Use）。无 App Groups 以外的特殊能力。

## ODR（On-Demand Resources）

- Tag：`knowledge-base`，内容 = 西湖包 `knowledge-pack.json` + `elements-sight.json` + `elements-history.json` + `pack-manifest.json`。
- 良渚 / 浙博 / 中国历史包作为普通 bundle 资源（`KnowledgePackLiangzhu` 等子目录）打进 App，运行时与西湖包合并。
- 工程配置：西湖包以显式 file reference 加入 Resources phase，`ASSET_TAGS = ("knowledge-base")`；通过 `membershipExceptions` 避免与同步 group 重复打包。其余三包用 `explicitFolders` 保留子目录，避免同名 JSON 互相覆盖。
- 当前设置 `ON_DEMAND_RESOURCES_INITIAL_INSTALL_TAGS = "knowledge-base"`：西湖 asset pack **随 App 首装一起下发**；将来可拆独立 tag 做按需下载。
- 上传：Xcode 归档上传时 asset pack 自动随构建上传到 App Store Connect，无需额外操作。
- 验证：归档后确认 `Products/OnDemandResources/` 存在、`OnDemandResources.plist` 含 `knowledge-base` tag（2026-08-02 已验证）；App 包内应可见 `KnowledgePackLiangzhu` 等目录。
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
