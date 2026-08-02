# CultureLens 当前状态

更新时间：2026-08-02

## 当前阶段

Phase 3 位置感知视觉识别、用户框选与可复现效果评测。

## 2026-08-02 景点候选去重与详情导航

- 建立并本地实施 `design/0032-distinct-attraction-candidates-and-detail-navigation.md`：模型已确认的主景点不再重复进入附近候选；App 同时按主景点名称兼容过滤旧服务响应和旧历史快照。
- 景点候选现携带数据库审核现场介绍，扫描结果页和历史详情优先展示实际介绍，不再让所有候选重复显示固定的“来自当前位置”占位说明。
- 候选卡片改为直接进入独立“候选详情”页面，用户在新页面查看介绍和候选依据后确认保存；主结果页不再原地替换标题。
- 旧生产识别响应缺少候选 `summary` 时，候选详情会使用扫描位置调用现有附近介绍 API，并按 `attractionKey` 读取该景点全部审核现场介绍；固定位置说明不再被同时当作正文和候选依据。生产 API 以西湖坐标验证可返回苏堤 2 条、三潭印月 10 条现场介绍。
- 图谱概念不再由后端复制同一文本到 `summary` 与 `detail`；App 对旧响应做去空白比较，仅在确有独立长文时渲染第二段正文。
- 后端 `internal/recognition` 与 `internal/knowledge` 测试及 vet 通过；iPhoneOS arm64 Debug 编译和全部测试 target 的 build-for-testing 通过。当前工作树中 0031 的 `contentadmin` 类型尚未同步其测试使用的主节点与关系字段，导致与本轮无关的 Go 全量测试仍在该包编译失败；本轮未部署生产。

## 2026-08-02 三潭印月主节点与多跳图谱

- 建立并本地实施 `design/0031-attraction-rooted-multihop-cultural-graph.md`，定位并修复景点候选只保留排序第一条现场介绍元素、再覆盖景点标题造成的图谱中心错配。
- 不修改 PostgreSQL schema：识别 Repository 聚合同一景点已有的全部介绍绑定；存在与景点同 key 的文化元素时将其作为中心，否则兼容回退到第一条绑定，并生成最多 3 跳、32 个概念节点的审核子图。
- 西湖内容包升级为 `hangzhou-west-lake-v2`：34 个文化元素、7 个景点、44 条显式关系、19 条现场介绍。三潭印月保留 10 个景点直接绑定元素，主节点拥有 12 条直接关系，覆盖三座石塔、圆孔与印月光影、小瀛洲与嵌套园林、步移景异、苏轼治湖与苏堤、中秋赏月、西湖十景、雷峰塔/白蛇传、南屏晚钟和一元人民币视觉符号。
- PostgreSQL 18.4 现有 schema 6 上内容包导入和数据库/Repository 集成测试通过；Go `go test ./...`、`go vet ./...` 通过；iPhoneOS arm64 Debug 编译通过。尚未部署生产。

## 已完成

- 阅读 7 页 CultureLens 效果稿并提炼产品闭环。
- 检查 SwiftUI、SwiftData、测试 target 和工程平台设置。
- 初始化 `agents` 工作区。
- 建立首份架构与数据设计：`design/0001-culturelens-mvp.md`。
- 确认“人文内容层 + iOS 26 Liquid Glass 操作层”的 UI 方向。
- 建立视觉与交互规范：`design/0002-humanist-liquid-glass-ui.md`。
- 替换 SwiftUI/SwiftData 模板页面，建立三 Tab 独立导航 App Shell。
- 建立语义颜色、排版、背景、对象卡片和关系节点等 DesignSystem 基础组件。
- 建立 3 个内置文化对象及其关系、来源样例数据。
- 完成探索首页、扫描占位、对象详情、概念详情、追问占位和文化地图 UI 闭环。
- 扫描页只使用固定样例结果，未接入相机、相册、网络或识别算法。
- 增加样例路由/可信信息单元测试和主 UI 路径测试。
- iOS 26.3 Simulator Debug 编译与 build-for-testing 均通过。
- 建立 `design/0003-location-aware-recognition-and-history.md`。
- 接入 `PhotosPicker` 与系统相机拍摄入口。
- 图片上传前统一旋转、缩至最长边 1600 px、重新编码为 JPEG 并移除 EXIF/GPS。
- 加入用户可选的单次定位；发送与持久化前降为约 1 km 粒度。
- 实现 `ScanCoordinator` 的准备、定位、识别、取消、失败和重试状态流。
- 实现远端 BFF 客户端与明确标记的本地样例降级。
- 增加 OpenAI Responses API 视觉识别 BFF，默认模型 `gpt-5.6-sol`，图像 detail 使用 `high`。
- 实现独立扫描结果页，展示可信度、判断依据、不确定性、位置参与情况、候选和模型标识。
- 扫描结果支持切换主要结果与备选候选，保存时写入用户实际确认的对象。
- 实现可交互文化关系图谱及等价列表模式。
- 使用 SwiftData 与独立图片文件保存扫描历史。
- 实现 MapKit 历史扫描地图、约略位置标记、时间线和历史详情。
- BFF Mock 健康检查、成功响应和非法请求自动契约测试通过。
- BFF 增加 Base64/MIME 校验、55 秒上游超时和统一 request ID；位置名称限制为城市级显示。
- iOS Debug 与 build-for-testing 再次通过，0 错误、0 警告。
- 修复 `ScanHistoryRecord.id` 与 SwiftData 内部持久化标识冲突导致的 `@Query` SIGABRT。
- 历史业务标识改为 `recordID`，开发期损坏的 V1 存储不再加载，新存储曾使用 `CultureLensHistoryV2`。
- 建立 `design/0004-directed-cultural-knowledge-graph.md`。
- 将文化图谱改为真实的有向属性图：对象/概念节点、关系类型、方向、解释和多跳路径。
- 斗拱样例现有 8 个概念节点与 9 条关系，包含 3 项前置知识及“斗拱 → 建筑等级 → 礼制秩序”路径。
- 图谱模式支持拖动画布、箭头、边标签和图例；列表模式展示等价关系三元组及解释。
- iPhone 17 Pro 模拟器已验证探索页、斗拱图谱、礼制秩序节点、关系列表和“我的”空状态。
- CultureLens 单元测试 7 项全部通过，0 失败。
- 确认正式后端采用 Go 单体，现有 `Backend/server.mjs` 仅作为接口原型和迁移参照。
- 建立 `design/0005-go-recognition-and-knowledge-backend.md`，定义 Go 识别管线、评测体系、知识图谱存储、API 契约与分阶段迁移。
- 建立独立 `CultureLensBackend` Go 单体服务，保留 `GET /health` 与 `POST /v1/recognitions` iOS 契约。
- 完成 G1：18 MiB 请求限制、Base64/MIME/图片头与像素校验、粗粒度位置校验、统一 request ID、稳定错误模型及 Mock provider。
- 完成 G2 基础：Google AI Studio Gemini `generateContent` provider、`gemini-3.5-flash-lite`、图片 `inlineData` 输入、版本化 Prompt、55 秒上游预算及 JSON 结构化日志。
- Google AI Studio 使用按顺序的三 key 池；收到 HTTP 429 时自动使用下一 key，非限流错误不会切换。
- iOS 使用全局单例 `CultureLensAPI.shared` 接入 `https://cl.codight.online`；在线服务失败时会显示可重试错误。
- 探索首页移除顶部 `CULTURELENS` 眉题，主标题统一为“探索”，首个内容板块调整为“基于位置推荐”。
- 本轮首页调整已通过 iPhone 17 Pro / iOS 26.3 Simulator Debug 编译，0 错误、0 警告。
- 建立 `design/0012-understood-knowledge-progress.md`，新增按对象/概念稳定 UUID 保存的本地“已了解”进度。
- 每个对象与概念详情底部新增“我已经了解”按钮；对象详情右上角原来源按钮改为同一进度操作，正文来源入口继续保留。
- 已了解状态支持撤销和应用重启恢复；iPhone 17 Pro / iOS 26.3 Simulator 编译 0 错误、0 警告，Swift 单元测试 11/11 通过。
- 建立 `design/0014-live-camera-capture.md`，扫描页改用 AVFoundation 后置摄像头实时预览与 `AVCapturePhotoOutput` 拍照。
- 相机页顶部控件整排移除；底部固定为相册、拍照和手电筒，torch 与同一后置摄像头联动，离开页面后自动关闭。
- 实时相机最终 iOS Simulator Debug 编译 0 错误、0 警告；受影响 UI 测试已改为从底部拍照按钮进入模拟器降级，但重跑时测试工具超时并关闭 Simulator，真机预览、拍照方向和手电筒仍待验证。
- `CultureLensAPI.swift` 与远端识别服务已通过 Swift 编译。
- Go Mock 合约测试覆盖健康检查、成功识别、非法请求和不支持图片；`go test ./...`、`go vet ./...` 与本地 `/health` HTTP 冒烟验证通过。
- 建立 `design/0006-focused-recognition-and-evaluation.md`，确认“整图上下文 + 用户框选特写 + 多候选确认”的识别策略。
- 新增框选页：支持拖动选择框、四角缩放、最小区域限制、识别整张降级和 VoiceOver 说明。
- iOS 将方向归一后的整图与可选裁剪特写发送给 Go 服务；结果页和历史保存用户实际询问的特写。
- Go v1 请求兼容增加 `focus_image_base64` / `focus_mime_type`，分别校验两张图片并清除 Base64 后再进入 Provider。
- Gemini Provider 使用整图 medium + 特写 high（无特写时整图 high），并通过 JSON Schema 限制一个主候选和 1-3 个备选。
- 质量优先默认模型更新为 `gemini-3.6-flash`，Prompt/Schema 更新为 `recognition-v2` / `provider-recognition-v2`；本地 `.env` 已同步非敏感版本配置。
- 新增正式 `cmd/eval`，可对同一授权 JSONL 数据集比较 `whole`、`crop`、`context-focus`，报告 Top-1、Top-3、拒识率和 P50/P95。
- 保存验证发现 V2 的业务字段 `objectID` 与 Core Data 内部标识冲突；已改为 `cultureObjectID` 并启用 `CultureLensHistoryV3`。
- iOS 26.3 Debug 构建 0 错误、0 警告；10 项 Swift 单元测试通过，“样例图 → 框选 → 识别 → 保存”UI 主流程通过。
- Go 双图合约、Provider、评测指标测试通过；`go test ./...` 与 `go vet ./...` 通过。
- 建立 `design/0007-location-prior-candidate-ranking.md`，明确位置只作为视觉候选的低权重地域先验。
- 定位改用系统 reduced accuracy；上传前坐标保持二位小数、误差半径至少 1 km，并增加城市、国家或地区及地区代码，不读取街道、POI 或完整地址。
- Go Provider 不再依赖地点显示名；即使反向地理编码失败，也会把约略坐标和误差半径作为结构化 JSON 先验送入模型。
- Prompt/Schema 更新为 `recognition-v3` / `provider-recognition-v3`：模型先按视觉形成候选，再用位置执行 `none`、`reordered` 或 `narrowed` 重排，并把位置影响与视觉 rationale 分开返回。
- 结果页新增“位置未改变候选 / 调整了候选顺序 / 缩小了候选范围”的可解释说明；旧历史快照缺少该字段时保持兼容。
- `cmd/eval` 增加 `-location-context dataset|off` 与位置影响计数，可在同一数据集上生成严格配对的有位置/无位置报告。
- iOS 26.3 Debug 构建 0 错误、0 警告；Swift 与 UI 测试统计 13 项通过；Go 全量测试与 `go vet ./...` 通过。
- 建立 `design/0008-database-first-recognition-candidates.md`，将识别改为“审核知识库检索在前、LLM 视觉排序在后”。
- 新增只读 `KnowledgeRepository` 和 `reviewed-catalog-v1`：把 App 已有的斗拱、莲花纹、青铜鼎及稳定 UUID、别名、地域标签、摘要和来源迁入后端版本化审核目录。
- 约略位置只进入 Repository；后端按城市和国家或地区代码过滤/排序最多 12 个候选后清除位置，Gemini 不再接收坐标或城市位置 JSON。
- Prompt/Schema 更新为 `recognition-v4` / `provider-recognition-v4`；模型必须返回本次候选中的 `catalog_object_id` 或明确返回空 ID，越界 ID 和 ID/名称不一致会被拒绝。
- 数据库命中时，稳定 ID、规范名、摘要、类别、时期、地域、图标和来源全部由 Repository 覆盖模型输出；库外结果不会写入审核目录。
- 主结果为库外对象时，服务端会在 3 个备选名额中至少补入一个审核知识库候选；已解析备选同时携带数据库摘要、时期、地域、图标和来源。
- iOS 结果页显示“知识库已收录”和“知识库候选”，切换已解析备选后使用数据库事实构建对象。
- 评测报告新增目录版本、每例候选数、解析状态、解析率和平均候选数。
- Go Repository、Provider、Pipeline 和 API 测试及 `go vet ./...` 通过；iOS Debug 构建 0 错误、0 警告，Swift 单元测试 10/10、受影响 UI 主流程 1/1 通过。
- 建立 `design/0009-silk-road-source-ingestion-and-knowledge-bundle.md`，定义 SROM / IIDOS 与维基百科的来源、版权、审核和发布边界。
- 新增 `cmd/knowledge` 与 `internal/knowledgebase`，支持全量同步、结构校验、原子写入和本地查询。
- 生成 `knowledge/bundles/silk-road.v1.json`：包含 2540 条 SROM 藏品事实型元数据、11 个固定修订版中文维基主题和 9 条显式关系，共 2551 个 `imported` 实体。
- SROM 长篇 HTML 描述和图片文件未进入知识库；远端图片只保留来源引用，维基摘要保留 oldid、CC BY-SA 4.0、署名入口和修改标记。
- 知识库文件校验和“丝绸”查询冒烟通过；新增采集分页、异常响应、稳定构建、版权字段、关系端点、原子写入与搜索测试。
- 后端生产 Docker 制品命名为 `ccr.ccs.tencentyun.com/gouzuang/culturelens`；使用多阶段跨平台静态编译、非 root UID/GID `10001`、CA 证书和 `/health` 容器健康检查，构建上下文明确排除 `.env`、评测数据与采集知识包。
- `docker build --platform linux/amd64` 已生成 `latest` 镜像（约 15.7 MB）；Mock 临时容器中 `/health` 返回 `{"status":"ok"}` 且 Docker 状态为 `healthy`，临时容器已清理；镜像已推送腾讯云仓库，远端 digest 为 `sha256:a8666d8f40bcf30b92b32efca0c8c4339f37fc099875503e62e695d9f3b6158f`。
- 建立 `design/0010-pve-internal-service-network.md` 并完成 PVE 内部网络实施：复用 `vmbr1` / `10.0.0.0/24`，CultureLens、DebainAI、cloudflared 与 DebianOwnUse 分别使用 `10.0.0.108`、`10.0.0.107`、`10.0.0.113`、`10.0.0.127`；四节点全互 ping 通过，原 LAN 默认路由未改变。
- cloudflared 服务保持 enabled、active，并可经内部接口直达 `10.0.0.108`。
- 后端已安装到 VM 108（LAN `192.168.3.138`、内部地址 `10.0.0.108`）：Docker 26.1.5 已启用，生产配置以 `root:root` / `600` 保存于 `/opt/culturelens/.env`，`culturelens` 容器使用 `mock=false`、非 root UID/GID `10001` 和 `unless-stopped` 重启策略运行。
- 容器监听主机 IPv4/IPv6 的 `8080`；容器内、LAN `http://192.168.3.138:8080/health` 和内部地址 `http://10.0.0.108:8080/health` 均返回 `{"status":"ok"}`，Docker 健康状态为 `healthy`。
- 公网域名 `cl.codight.online` 已经由 Cloudflare 路由到后端：HTTP `/health` 301 跳转 HTTPS，HTTPS `/health` 返回 200 和 `{"status":"ok"}`；空的 `POST /v1/recognitions` 返回后端约定的 400 `invalid_request` 与 request ID，确认完整 API 路由可用。
- iOS 全局 API Base URL 与对应测试断言已切换为 `https://cl.codight.online`；iPhone 17 Pro / iOS 26.3 的 Debug `build-for-testing` 成功，0 错误、0 警告。模拟器处于关机状态，本轮未启动 Simulator，测试产物已编译但未实际执行。
- 建立 `design/0011-huma-api-documentation.md`，锁定 Huma v2.39.0；使用独立文档 mux 生成 OpenAPI，原 `net/http` 业务 handler、iOS 契约与稳定错误 envelope 保持不变。
- 公网已提供交互式文档 `https://cl.codight.online/docs`、OpenAPI 3.1 JSON/YAML、OpenAPI 3.0 兼容文档和 schema 端点；规范包含 `/health`、`/v1/recognitions`、18 MiB 限制及 200/400/413/415/502/503/504 响应。
- Huma 变更已通过 `go test ./...`、`go vet ./...`、本地 HTTP、Docker 临时容器和公网 Cloudflare 路径验证；生产镜像 ID 为 `sha256:6bfb5111c29f5e5bad8b8d2fd495f0236ede3d3da2a9994d0a1db7bc1c486a9f`，容器状态为 `healthy`。
- 原 Huma 生产容器保留为停止状态的 `culturelens-rollback-huma`；当时使用本地镜像直传完成部署，后续
  PostgreSQL 版镜像已恢复腾讯云仓库推送。
- 建立并实施 `design/0013-postgresql-container-foundation.md`：VM Docker 已配置用户指定的 `xuanyuan.run` Docker Hub mirror，重启后原 API 自动恢复并保持健康。
- VM 已运行 PostgreSQL 18.4 官方 Alpine 镜像，容器 `culturelens-postgres` 为 `healthy`；镜像 digest 为 `sha256:9a8afca54e7861fd90fab5fdf4c42477a6b1cb7d293595148e674e0a3181de15`。
- 数据库 `culturelens` 使用 UTF-8，应用所有者 `culturelens_app` 无超级用户、建库和建角色权限；管理员与应用密码及环境文件只保存在 `/opt/culturelens`，均为 `root:root` / `0600`。
- PG 数据通过 `culturelens-postgres-data:/var/lib/postgresql` 持久化，写入探针经容器重启后仍可读取并已清理；API 与 PG 通过 `culturelens-db` 内部网络互通。
- VM IPv4/IPv6 的 5432 已发布；Docker 内部网络、服务器 LAN 地址认证和开发 Mac 到 `192.168.3.138:5432` 的 TCP 连接均验证通过。
- 建立并实施 `design/0015-postgresql-reviewed-catalog-repository.md`，使用 pgx v5.10.0、Tern v2.4.1 和 sqlc v1.31.1 完成 schema migration、幂等目录导入与类型安全查询。
- `reviewed-catalog-v1` 已写入生产 PostgreSQL；catalog/node/alias/geography/source/node-source 数量为 `1/3/6/5/4/4`，重复导入不重复数据，未变化节点的 `content_version` 保持 1。
- `culturelens_admin` 为数据库和业务表所有者；`culturelens_app` 只有知识表 SELECT 权限。生产 API 已注入只读 `DATABASE_URL`，不再使用内嵌 JSON 作为运行时数据源，也不在 PG 故障时静默回退。
- 新生产镜像 ID 为 `sha256:709a31e858858e2885b1dbe49bc688d4b9357818077855eaac5bc81cee169826`，同时包含 API 与 DB migration 二进制；生产启动日志和 PG 会话均确认 `repository=postgresql`、active catalog 为 `reviewed-catalog-v1`、对象数为 3。
- PostgreSQL 版 `latest` 已推送至腾讯云仓库，registry digest 为 `sha256:4602f5196e962052382fd1f228d2d8b06443f6388997663478f458ccec976625`。
- PG 切换前 custom-format 备份以 `root:root` / `0600` 保存于 `/opt/culturelens/backups/culturelens-pre-pg-repository-20260730T1845.dump`；旧 API 保留为 `culturelens-rollback-pg`。
- PostgreSQL Repository 已通过全量 Go 测试、vet、真实 PG 迁移/幂等导入/地域查询测试、本地 Mock HTTP、生产 Docker 双容器测试和公网回归；新 API 与 PG 均为 `healthy`。
- 建立 `design/0016-related-objects-and-location-recommendations-api.md`，新增
  `GET /v1/objects/{objectID}/related` 与
  `GET /v1/objects/recommendations?cityName=&regionCode=` 两个只读知识接口。
- 新增 PostgreSQL migration 2：`knowledge_edges` / `edge_sources` 保存有向审核关系及关系级来源；
  运行时只返回 active catalog 中端点与边均为 reviewed 的关系，不按名称、类别或模型输出猜边。
- 位置推荐复用现有 Repository 城市/地区标签排序；无地域命中时以
  `matchStatus = catalogFallback` 明示全目录回退，不虚构经纬度距离或附近 POI 语义。
- 当前 3 个审核样例没有有依据的对象间关系，seed 的 `relations` 保持为空；接口对已有对象返回 200
  和空数组。Memory/API 合约测试已覆盖带来源关系的双向查询。
- 新知识接口、OpenAPI 3.1/3.0 schema、参数错误、404 和稳定错误 envelope 已加入自动测试；
  `go test ./...` 与 `go vet ./...` 通过；隔离 PostgreSQL 18.4 容器中的 migration 2、seed、空关系、推荐和
  调试页冒烟均通过，临时容器与网络已清理。
- 新增后端内嵌单页调试台 `GET /debug`：可填写 object UUID 查询关联对象，也可填写城市/地区码获取推荐；
  页面显示实际请求 URL、HTTP 状态、耗时、`X-Request-ID` 和格式化 JSON。
- 调试台只调用同源只读接口，不保存输入、不包含凭据、无需独立前端构建；页面响应包含 no-store、CSP 和
  nosniff 安全头。GET 页面及 POST 405 合约测试通过，`go test ./... -count=1` 与 `go vet ./...` 通过。
- 2026-08-01 已部署知识接口与调试台：生产 PostgreSQL 升级至 schema v2，`knowledge_edges` /
  `edge_sources` 当前均为 0，`culturelens_app` 对新表只有 SELECT。
- 生产迁移前备份保存于
  `/opt/culturelens/backups/culturelens-pre-related-debug-20260801T1346.dump`，为 `root:root` / `0600`，
  SHA-256 为 `418d98d025279b9be245f71107f9c1397a2d3653a041e9f7a2bb9b0cb8255abf`，且可由
  `pg_restore --list` 读取。
- 新生产镜像 ID 为 `sha256:7b6b06c34581b4b6bc7248fe88c35f4823ce863bedebf8228946e65d69183bf8`；
  腾讯云仓库 `latest` digest 为
  `sha256:f5264bdb00028156b9cd47a480cf45564b0d31e778e8ea20a2d4a92690b07848`。
- 新 `culturelens` 容器保持原端口、env、`unless-stopped` 与 `bridge + culturelens-db` 双网络并为
  `healthy`；旧容器保留为 `culturelens-rollback-pre-related-debug-20260801`。
- 公网 `https://cl.codight.online/debug`、两个知识接口、OpenAPI 和 `/health` 均验证通过；空识别请求继续
  返回既有 400 `invalid_request` envelope。
- 2026-08-01 按用户要求清空生产库全部知识资料：`knowledge_catalogs`、`knowledge_nodes`、
  `knowledge_aliases`、`knowledge_geographies`、`knowledge_sources`、`node_sources`、
  `knowledge_edges`、`edge_sources` 已在单个事务中全部清空，清理后逐表计数均为 0；
  数据库、schema v2、角色与数据卷保留。
- 清理前 custom-format 备份为
  `/opt/culturelens/backups/culturelens-pre-knowledge-clear-20260801T140123.dump`，为 `root:root` / `0600`，
  大小 29183 bytes，SHA-256 为
  `9ff3fcaea239276d2c6176260733d7c6ec14ad1859330cfff6ab4d0f211a9be8`，并已通过
  `pg_restore --list` 可读性验证。
- 清理后 API 与 PostgreSQL 容器仍为 `healthy`，公网 `/health` 与 `/debug` 返回 200；
  位置推荐返回 503 `knowledge_unavailable`，旧 object UUID 的关联查询返回 404
  `object_not_found`，确认原资料已不可读。
- 建立并实施 `design/0017-cultural-elements-and-attraction-introductions.md`：migration 3 新增
  `cultural_elements`、`cultural_element_relations`、`attractions`、
  `attraction_cultural_introductions` 4 表，分离通用文化元素与带 WGS84 精确坐标的景点现场介绍。
- 富文本使用 `schemaVersion = 1` 的 JSON block document；元素关联为无向多对多，数据库防止自关联和反向重复；
  所有元素/景点关联由外键维护。
- `culturelens-db up` 已改为只执行 migration，不再自动回灌旧 3 个样例；显式
  `seed-reviewed-catalog` 命令暂作兼容保留。
- sqlc 已生成新表的 upsert/get/list 和关联双向读取查询。PostgreSQL 18.4 容器验证 migration 3、
  正常查询和数据约束；连接真实 PG 的 `go test ./... -count=1` 与 `go vet ./...` 均通过。
- migration 3 已部署到生产；新表未写入任何内容。
- 建立并实施 `design/0018-go-cultural-content-query-api.md`：Go 新增独立 `ContentRepository`，关联查询切到
  `cultural_elements` / `cultural_element_relations`，位置推荐切到
  `attraction_cultural_introductions` 并使用 WGS84 Haversine 米制距离。
- 新公开路径为 `GET /v1/cultural-elements/{elementKey}/related` 和
  `GET /v1/attraction-introductions/recommendations?latitude=&longitude=&radiusMeters=`；旧 object UUID 与城市标签
  路径已从业务路由、OpenAPI 和调试台移除。
- 旧 active catalog 为空时 API 现在允许启动：识别候选仍返回 503，但健康检查、文档、调试台和新内容查询可用。
  全量 Go test/vet 与隔离 PostgreSQL 18.4 集成测试通过，临时容器已删除。
- 2026-08-01 已部署 migration 3 和新 Go API。迁移前生产备份为
  `/opt/culturelens/backups/culturelens-pre-cultural-content-20260801T152503.dump`，权限 `root:root/0600`，
  大小 27683 bytes，SHA-256 为 `17f46641feb87a8923733b6b31f4eaec48b0b838c7ff1c1e9ec9c68f176070ec`，
  并通过 `pg_restore --list` 校验。
- 生产 schema 为 v3，4 张新表计数均为 0，`culturelens_app` 只有 SELECT。生产镜像 ID 为
  `sha256:ed61bb759f5087f307cb09af91f6776913d45cc32c8f557cd44fd4c5d2f47ad4`，腾讯云仓库 digest 为
  `sha256:2eff818f83125c297ca21486486a51164b24095e0e9038e73977b214c6b80a00`。
- 新容器保持 8080、`unless-stopped` 和 `bridge + culturelens-db` 双网络并为 healthy；旧 API 保留为
  `culturelens-rollback-pre-cultural-content-20260801`。公网/LAN/内部健康检查、新接口空数据、旧接口 404、
  调试台、文档、OpenAPI 和空目录识别 503 均验证符合设计。
- 建立并部署 `design/0019-west-lake-content-admin.md`：新增独立 `culturelens_editor` 最小权限角色、
  `CULTURELENS_ADMIN_DATABASE_URL` 编辑池、Bearer 管理令牌、`/v1/admin/*` upsert/import API 和 `/admin` 单页。
- editor 只对 4 张新内容表具有 SELECT/INSERT/UPDATE；DELETE、旧知识表读取、schema/database CREATE 均为 false。
  随机密码与令牌只保存在生产 `/opt/culturelens` 的 root-only 文件中，公开 OpenAPI 不包含管理路径。
- 西湖 v1 内容包已写入生产：7 个文化元素、7 个景点、5 条显式关系、10 条景点特定介绍，覆盖雷峰塔、保俶塔、
  净慈寺、岳王庙、文澜阁、苏堤和三潭印月；每条介绍的坐标来源保留在仓库导入包中。
- 本轮生产备份为 `/opt/culturelens/backups/culturelens-pre-west-lake-admin-20260801T161400.dump`，大小 39668 bytes，
  SHA-256 为 `fc9d9a9f2605686823fe49b38cedca60615045f954ee9c9719d16db0db7a0b64`，且通过恢复清单验证。
- 生产 schema 为 v4，镜像 ID 为 `sha256:877dec0e37935a8248e483199591bfe05fad70b887f3124f54b2746c70c999f4`，
  registry digest 为 `sha256:86ff4f11824cb5aa0d6e80b78ceb5a1c33a4c12d56c03905015eed5027f07fc4`；
  回滚容器为 `culturelens-rollback-pre-west-lake-admin-20260801`。
- 公网管理页、401 鉴权、内部正确令牌、雷峰塔 50 米推荐 2 条和“西湖十景”4 个关联元素均验证通过。
- 2026-08-01 按办公网 Cloudflare Zero Trust 边界移除应用层管理令牌：Go 配置、管理 API 和单页均不再读取、
  保存或发送 `CULTURELENS_ADMIN_TOKEN` / Bearer header，管理能力只由 server-only
  `CULTURELENS_ADMIN_DATABASE_URL` 启用；公开 OpenAPI 仍不包含管理路径。
- 无令牌生产镜像 `20260801-zero-trust-admin` 的 image ID 为
  `sha256:283311b842e73b41d61d6cd163f440e2c3e31e868c5fbafba96a51541ec1f0af`，registry digest 为
  `sha256:4a2d9537674bedd1b7513a8bca88656205f2fdc3bad517051ffc44d456122f89`；容器 healthy，源站及办公网
  Zero Trust 放行路径下 `/admin` 与 `/v1/admin/content` 均为 200，`/health` 为 200。
- 生产 `/opt/culturelens/admin-token`、`admin.env` 和含旧令牌的临时回滚容器已删除；
  `database-editor.env` 与 `culturelens_editor` 最小权限数据库连接保留。
- iOS App、单元测试与 UI 测试 target 的最低系统版本已统一降至 iOS 18.0；反向地理编码在 iOS 18–25
  使用 `CLGeocoder`、iOS 26 使用 `MKReverseGeocodingRequest`，扫描操作区在旧系统使用 material 与标准按钮样式，
  iOS 26 保留 Liquid Glass。iOS 18 deployment target 的 Simulator Debug 编译通过。
- 建立并实施 `design/0020-database-backed-home-recommendations-and-camera-capture-safety.md`：探索首页的
  “基于位置推荐”已从 `SampleCultureData.objects.prefix(2)` 切换到生产
  `GET /v1/attraction-introductions/recommendations`，使用降精度当前位置显示最多 2 条数据库景点介绍；请求失败、
  位置不可用或空结果均不再用本地样例补位。
- 首页旧“屋檐之下”样例主题与“UI 演示”文案已移除；生产公开接口在西湖坐标 50 km 查询返回 10 条数据库内容，
  limit=2 时实际返回文澜阁与三潭印月介绍。
- 修复真机 `AVCapturePhotoOutput.capturePhoto` exception：单次拍照设置不再无条件指定 `.quality`，而是使用当前
  输出的 `maxPhotoQualityPrioritization`，满足 AVFoundation “请求值不得超过输出上限”的硬件约束。
- 建立并实施 `design/0029-persist-candidates-and-history-graph-ui.md`：扫描结果页仅将 `resolutionStatus=attraction`
  的结果放入“附近景点候选”，文化知识图谱独立绑定原始文化对象；不再显示“知识库候选”。
- 新增 `ScanHistorySnapshot`，保存原始 `RecognitionResult`（含全部候选与图谱）、最终确认对象和选中候选 ID；
  历史详情页恢复文化图谱并展示已保存的景点候选，旧 `RecognitionResult` 快照保持回退兼容。
- 历史容器版本更新为 `CultureLensHistoryV4`。Swift 编译阶段已执行；本机 CoreSimulatorService 没有可用
  simulator runtime，`actool` 因环境缺少 runtime 失败，未启动 Simulator。
- 建立并实施 `design/0030-attraction-primary-and-scan-result-cleanup.md`：识别协议新增 `attraction_key`，只有
  LLM 明确确认画面目标就是附近景点时，服务端才把景点提升为主结果并保留其关联文化图谱；附近景点仍作为独立候选返回。
- 扫描结果页移除“位置调整了候选顺序”及位置影响段落，将判断依据卡片放到景点候选之后；对象详情移除“先看结构，再看装饰”说明卡片。
- Go `go test ./...` 与 `go vet ./...` 已通过（使用 `/tmp` GOCACHE）；生产镜像已构建并推送，digest 为
  `sha256:f65e42fef4db949bb8863009b848ce7ac76c4107af7fb3434d118b531aedd620`；用户确认后已部署到生产，
  运行 image ID 为 `sha256:69ab47e28f731cad9ad767a78fabc24a20a3ed0420c9276dae4bf923d94e0fd6`，容器健康。
  旧版本保留为 `culturelens-rollback-pre-attraction-primary-20260801`，公网 `/health` 返回 HTTP 200。
- iOS 真机 UI 尚待再次安装验证。
- 本轮 iOS Simulator Debug 构建 0 警告；iPhoneOS arm64 Debug 构建和 App/单元测试/UI 测试 target 的
  `build-for-testing` 均通过。相机崩溃修复仍需在真机重新拍照回归。
- 真机继续完成拍照和框选后，在 `RemoteRecognitionService.recognize` 读取
  `input.imageData.base64EncodedString()` 时出现 `EXC_BAD_ACCESS`；堆栈为 `swift_retain` 与
  `outlined copy of Data._Representation`，确认请求尚未发出，和后端响应无关。
- 建立并实施 `design/0021-owned-image-data-across-concurrency.md`：ImageIO 不再把 `NSMutableData` 直接桥接返回，
  相机 `fileDataRepresentation()` 在跨越 delegate 队列前建立独立 owned byte copy；`RecognitionInput` 与框选区域模型
  显式 `nonisolated`。
- 新增 Foundation 可变存储解耦测试，以及规范化整图/裁剪特写各 16 次、共 32 次并发 Base64 压力测试。
  第一次修正后，相册选图也在远端服务同一 `Data._Representation` 行闪退，排除了 AVFoundation 和单一图片来源。
- 第二轮把整图和框选图在 `RecognitionInput` 构造时预编码为不可变 Base64 字符串，远端服务不再持有或读取图片
  `Data`；同时以显式 sample/remote 后端分支替换 `@Sendable` 识别闭包类型擦除，消除截图堆栈里的多层闭包转发。
- 新增识别输入预编码还原测试；iPhoneOS arm64 Debug 和 App/单元测试/UI 测试 target 的
  `build-for-testing` 均通过。测试已编译但未实际执行，仍需真机重跑相册与拍照两条识别路径。
- 建立并本地实施 `design/0022-cultural-content-recognition-pipeline.md`：生产识别不再注入旧
  `knowledge.Repository`，候选改读 `cultural_elements`，约略位置匹配的
  `attraction_cultural_introductions` 作为不含坐标的现场上下文；Provider 契约升级为
  `recognition-v5` / `provider-recognition-v5` 和稳定 `cultural_element_key`。
- 文化元素为空现在是合法开放集合识别：仍调用 Provider 并返回 `unresolved`；只有 PostgreSQL 查询实际失败才返回
  503。iOS `CultureObject` / 备选增加可选 `culturalElementKey`，已解析元素使用由 key 确定生成的 UUID，旧响应和历史兼容。
- Go 全量测试、vet、真实 PostgreSQL 18.4 串行集成测试和 iPhoneOS arm64 `build-for-testing` 通过。linux/amd64
  镜像 `culturelens:20260801-recognition-v5`（ID `sha256:8c03206bca4e3af19c5840e3a3de47130f0d0d438aae967019d37bec6fe0480f`）
  已构建；装入 7 个文化元素与 10 条介绍的隔离容器冒烟中，有效图片识别由 503 变为 200，返回 7 个新候选。
- 获得用户明确部署授权后，生产已切换到 `culturelens:20260801-recognition-v5`（ID
  `sha256:8c03206bca4e3af19c5840e3a3de47130f0d0d438aae967019d37bec6fe0480f`）；正式容器健康，公网
  `https://cl.codight.online/health` 返回 200。旧 `20260801-zero-trust-admin` 容器以
  `culturelens-rollback-pre-recognition-v5-20260801` 停止保留，restart policy 为 `no`；生产 `.env` 备份为
  `/opt/culturelens/.env.pre-recognition-v5-20260801T1923`。
- 生产数据库网络隔离预检读取 7 个文化元素和 10 条景点介绍，v5 Mock 识别返回 HTTP 200 和 7 个新候选。生产机
  直连 Google AI Studio 不可达，已按用户提供的 `http://10.0.0.114:7890` 配置 `HTTP_PROXY` / `HTTPS_PROXY`，并用
  `NO_PROXY` 保持 PostgreSQL 与本机流量直连；配置备份为
  `/opt/culturelens/.env.pre-google-proxy-20260801T1935`，无代理 v5 容器以
  `culturelens-rollback-pre-google-proxy-20260801` 停止保留。
- 带代理的正式容器启动零重试且健康；生产机本地和公网真实 `gemini-3.6-flash` 识别均返回 HTTP 200，响应确认
  `recognition-v5` / `provider-recognition-v5`、`cultural-elements-v1` 和 7 个新表候选。旧目录 503 与 provider
  出口 504 均已消除。
- 建立并本地实施 `design/0023-photo-recorded-location-for-library-scans.md`：相册扫描先读取
  `PHAsset.location`，不可用时回退到原始图片 EXIF/GPS；没有照片位置时继续纯图片识别，不再请求当前设备位置。
- 扫描位置不再四舍五入到两位小数或强制扩大到 1 km；相机定位改为 `kCLLocationAccuracyBest`，识别请求和历史
  保存原始可用坐标精度。Go 识别 API 已本地放宽为完整 WGS84 十进制度，同时继续拒绝非有限和超范围坐标。
- 图片规范化仍移除 EXIF/GPS；iOS Simulator Debug 编译通过，Swift 单元测试 17/17、Go 全量测试与 vet 通过。
  本轮 Go API 契约变更尚未部署，真机仍需分别选择有/无位置照片并回归拍照位置。
- 建立并本地实施 `design/0024-recognition-request-audit-console.md`：migration 5 新增
  `recognition_request_logs`，记录每次识别的成功/失败、整图/框选图、去 Base64 的请求 JSON、完整公开响应/错误、
  HTTP 状态、模型版本与耗时；非法 JSON 只保存字节数与结果，不保存任意未解析正文。
- migration 6 显式撤销生产历史 default ACL 可能继承的宽权限，再只授予 app 审计 INSERT/sequence USAGE 和 editor
  审计 SELECT；模拟生产 ACL 的 PostgreSQL 18.4 测试通过。
- `culturelens_app` 对审计表只有 INSERT 和 identity sequence 使用权、没有 SELECT；`culturelens_editor` 只有 SELECT、
  没有 INSERT。`GET /v1/admin/recognition-requests?limit=100` 不返回图片字节，单图通过 no-store 管理接口按需读取。
- 新增内嵌 `/admin/recognitions` 前端，支持最近 100 条刷新、成功/失败过滤、Request ID/对象/错误/模型搜索、展开请求与
  响应 JSON，并在展开时懒加载整图和框选图；入口已加入现有内容管理页。
- Go 全量测试和 vet 通过；真实 PostgreSQL 18.4 migration 5、成功/失败/NULL 审计、倒序分页、图片读取与角色权限通过。
  最终 linux/amd64 镜像 `culturelens:20260801-audit-console`（ID
  `sha256:20aec1727557590856e8f80727ea70e81aae33b874a0b4553831999ec0116068`）构建通过；Docker Mock 冒烟确认
  成功请求 200、非法 JSON 400 均落库，最近列表不内嵌图片，图片和管理页 no-store/CSP 正确。临时容器与网络已清理。
- 获得部署授权后已完成生产数据库备份、migration 5/6 和最终镜像部署。备份为
  `/opt/culturelens/backups/culturelens-pre-audit-console-20260801T2023.dump`，`root:root/0600`，43,735 bytes，
  SHA-256 `113165e0ce08ec44da0b815320e02428b353765fcdc85355df06c4b8a9fa8f39`，恢复清单可读；生产 schema 6、
  最终权限为 app `INSERT=true/SELECT=false/sequence USAGE=true/sequence SELECT=false`、editor
  `SELECT=true/INSERT=false`。
- 正式容器已切换到 `culturelens:20260801-audit-console`，保持代理、8080、`unless-stopped` 与
  `bridge + culturelens-db` 双网络，启动零重试且 healthy；旧 v5 容器以
  `culturelens-rollback-pre-audit-console-20260801` 停止保留、restart policy 为 `no`。
- 公网 `/admin/recognitions`、最近 100 条 API 和审计图片均返回 200。真实 Gemini 测试请求 200 与非法 JSON 400
  分别成为审计 ID 1/2；列表倒序、完整响应/错误、68-byte PNG、正确 MIME、no-store/nosniff 均验证通过，非法 JSON
  不保存正文或图片。审计表当前 2 行、总 relation size 81,920 bytes，服务日志无审计写入失败；上传归档已清理。
- 建立并实施 `design/0025-single-image-focus-annotation.md`：iOS 框选识别不再裁剪并发送第二张特写，改为在
  方向归一后的完整 JPEG 上绘制白色外描边与朱红色内描边，只上传一张带框完整图；固定 `context_note`
  明确要求模型只识别框内目标，结果页和历史也保存同一张带框完整图。后端双图字段继续兼容旧客户端和评测。
- 修复框选四角只有单点可拖动：角点手势改为先绑定独立 44 × 44 pt 命中区、最后再定位，避免 `.position`
  之后绑定手势造成多个角点命中区域在父容器重叠。带框输出已目视确认尺寸、方向和框位置正确。
- iPhoneOS arm64 Debug 的 App、单元测试和 UI 测试 target `build-for-testing` 通过；iPhone 17 Pro / iOS 26.3.1
  Simulator 的 Swift 单元测试 17/17 通过，“样例图 → 确认标注框 → 识别 → 保存”UI 主流程 1/1 通过。
  四角真实触控仍需真机回归。
- 建立并实施 `design/0026-west-lake-three-pools-cultural-expansion.md`：以三潭映月为中心补充西湖文化景观、北宋疏浚、
  苏轼、白居易、南宋临安、宋代山水审美、园林借景、小瀛洲园林格局和赏月文化等 10 个文化元素（含三潭映月中心节点），
  新增 15 条显式关联与 9 条三潭映月现场介绍；内容包来源线索和事实边界已写入设计文档。
- 生产数据库已通过 `/app/culturelens-content import` 幂等导入本轮包：最终为 17 个文化元素、7 个景点、20 条关系、19 条景点介绍。
  重复导入后数量保持 `17|20|19`；三潭映月对应 10 条现场介绍、5 条直接文化关联，生产 `/health` 返回 `{"status":"ok"}`。
- 本地 Go 测试尝试受当前沙箱网络限制，依赖无法从 `goproxy.cn` 下载；JSON 校验、生产 bundle 校验、真实 PostgreSQL 导入和重复导入验证均通过。
- 建立并实施 `design/0027-recognition-knowledge-graph-response.md`：修复识别管线将已解析文化元素的
  `concepts` / `relations` 硬编码为空数组的问题；生产候选读取显式文化关联，返回 Swift 图谱可解析的稳定 UUID 节点和边。
- 建立并实施 `design/0028-separate-attraction-candidates-from-cultural-knowledge.md`：识别响应的 `alternatives` 改为只返回
  由附近景点现场介绍按 `attraction_key` 去重得到的景点候选，文化元素只进入 LLM 上下文和主结果图谱；无附近景点时不再用文化元素填充候选，仍开放调用 LLM。
- 新增 `attractionKey` / `resolutionStatus=attraction` 响应字段和 Swift 候选展示语义；结果页将“其他可能”改为“附近景点候选”，
  不再显示文化元素名称作为候选。生产镜像 `culturelens:20260801-knowledge-graph` 已部署并 healthy，旧容器保留为
  `culturelens-rollback-pre-knowledge-graph-20260801`。
- Docker 内 `go test ./...` 与 linux/amd64 构建通过；生产 `/health` 返回 `{"status":"ok"}`。
- iOS 源码已同步候选分层字段；本轮仅执行 build 未启动模拟器。当前机器 CoreSimulatorService 没有可用 iOS Simulator runtime，
  `xcodebuild` 在 Asset Catalog 的 simulator runtime 检查阶段失败，尚未完成 iOS 二进制回归。
- 建立并部署 `design/0031-attraction-rooted-multihop-cultural-graph.md`：确认原表已有景点到文化元素的完整绑定，撤销不必要的 schema 7 方案，生产继续保持 schema v6；Repository 改为按景点聚合全部绑定、优先使用与 `attraction_key` 同 key 的中心元素，并返回最多 3 跳/32 节点的有界图谱。
- 西湖内容包扩充至 34 个文化元素、7 个景点、44 条关系、19 条景点介绍；生产三潭印月保留 10 个直接绑定，公开关联接口返回中心节点及 12 个直接关联元素。数据通过 `culturelens_editor` 幂等 upsert 写入，没有运行 migration。
- 2026-08-02 生产备份 `/opt/culturelens/backups/culturelens-pre-three-pools-bindings-20260802T134927.dump` 已通过恢复清单校验，SHA-256 `99667ce7c958e5d586d4c9f5dd13d388378ae90faa87824ea96484cac98789cc`；linux/amd64 镜像 `20260802-three-pools-bindings-amd64` 已部署，容器 healthy、restartCount=0，旧容器以 `culturelens-rollback-pre-three-pools-bindings-20260802` 停止保留。
- 该三潭图谱镜像随后因生产识别请求在 Gemini 阶段超时被回滚，不再作为当前生产版本；当前运行镜像 ID 为 `sha256:69ab47e28f731cad9ad767a78fabc24a20a3ed0420c9276dae4bf923d94e0fd6`。
- 2026-08-02 按用户要求将数据库清理与识别逻辑彻底拆分：确认 8 张旧知识表均为空后直接 SQL 删除；后端同时删除旧 catalog 启动查询、Repository/seed/sqlc 代码，并恢复稳定版候选输入行为。
- 删除前备份 `/opt/culturelens/backups/culturelens-pre-legacy-table-drop-20260802T143058.dump` 已通过恢复清单校验，SHA-256 `930bc08fdfb16eb01a980178d29e19de0780580f75b2540cff9348767c3cff92`。临时兼容视图首次漏列造成 10 次自动重启，补齐后恢复；最终清理镜像部署后两个兼容视图也已删除。
- 当前生产 `public` schema 中 `knowledge_*` relation 为 0，只剩 6 张有效基础表。镜像 `20260802-db-cleanup-only` ID 为 `sha256:c114e01388dcb668b9ae9613bd1d50d22ccf5bf283a2ff0e05df746c6cadee0c`，registry digest 为 `sha256:184a43b0112e1cae0464de068da691f2eab0ef014a9b9c6dec7d6099cfdf7196`；容器在无旧对象状态下重启成功，healthy、restartCount=0，本机和公网 `/health` 均为 200。

## 下一步

1. 准备至少 30 张覆盖建筑构件、器物、纹样、展品、空间、未知对象和复杂背景的授权标注图片。
2. 对同一数据集比较 `whole`、`annotated-whole`、`crop`、`context-focus`、Flash-Lite / Flash，以及 `-location-context dataset|off`，生成首份可复现报告后再确认最终默认策略。
3. 在用户明确授权测试图片上传后，完成 Google AI Studio Gemini 3.6 Flash 的真实带框单图端到端验证。
4. 在真机验证相机权限、拍照、框选、位置授权、取消和后台恢复。
5. 使用 `https://cl.codight.online` 完成“框选 → 识别 → 候选确认 → 保存 → 历史回看”端到端验证。
6. 在现场或可信地图中逐点复核首批 7 个 WGS84 坐标，并通过管理页修正入口级位置。
7. 扩充更多西湖文化元素与景点介绍，并逐条内容审核。
8. v5 生产观察稳定后，以独立 migration 删除旧 `knowledge_*` 过渡表和旧 seed 命令。
9. 根据实际图片流量确定审计照片保留天数、容量告警和清理任务；当前数据库历史不自动删除。
10. 在管理端增加 draft/publish 状态，使公开运行时只读取已发布数据。
11. 为已部署的 Go BFF 增加身份认证、限流、来源验证和更完整的观测性。
12. 校准深浅色、辅助功能字号、VoiceOver、降低透明度与增强对比度。

## 待确认

- 首版是否只支持 iPhone，还是必须同时适配 iPad、macOS、visionOS。
- 文化资料的授权来源、引用格式与内容审核责任。
- 用户照片是否上传、是否持久保存以及保留期限。
- 是否需要登录和多设备同步。

## 当前阻塞

- 首批坐标来自开放结构化数据与地图节点，不是现场测绘入口点；推荐已可用，但上线面向游客前仍应人工逐点复核。
- 尚无可用于比较识别准确率的授权标注集，当前只能确定工程策略，不能声称已测得最终最优模型。
- 开发期 V1/V2 历史存储分别因 SwiftData/Core Data 的 `id` / `objectID` 冲突不再加载；文件保留但不迁入 V3。
