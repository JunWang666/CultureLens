# CultureLens 项目说明

## 定位

与 CultureLens 相同的产品体验（扫描识别文化现场、附近推荐、知识图谱、历史），但识别管线完全在端侧运行：

- 本地知识库（西湖内容包：34 元素 / 7 景点 / 44 关系 / 19 介绍）替代 PostgreSQL。
- 本地完成候选挑选（Haversine 附近查询、优先级排序 top 12、BFS 图谱、景点绑定）与 prompt 拼接（v5 模板 + 候选 JSON），逻辑 1:1 移植自 Go 后端 `internal/knowledge`、`internal/recognition`、`internal/providers/googleai`。
- LLM 调用直连 Cloudflare AI Gateway 的 OpenAI 兼容端点（`dynamic/culturelens`，中转 Gemini），key 硬编码于 `Services/LLM/LLMGatewayConfig.swift`（本期接受的安全取舍）。
- 响应在端侧校验映射（key 校验、UUIDv5、富文本压平、SF Symbol），产出与旧版相同的 `RecognitionResult`，UI 层零改动。

## 外部依赖（仅两个）

1. **Cloudflare AI Gateway**：`https://gateway.ai.cloudflare.com/v1/<account>/apps/compat/chat/completions`，多模态 image_url 与 `response_format: json_schema` 已实测可用（实际模型 gemini-3.6-flash）。
2. **Cloudflare R2 图床**：介绍富文本中的 `image` block 直接引用 R2 URL，本地库只存 URL 不存图片。后端 `contentadmin` 校验已放宽接受 image block。

## 知识包与 ODR 分包

- 数据文件：`CultureLens/Resources/KnowledgePack/`（knowledge-pack.json + pack-manifest.json），打 ODR tag `knowledge-base`，App Store 托管。
- 当前为 **initial-install**（`ON_DEMAND_RESOURCES_INITIAL_INSTALL_TAGS`），随 App 首装下发；将来移除该设置即切换为按需下载，实现按地域拆包分发。
- 内置回退：`Resources/KnowledgePackFallback/`（同内容副本，不打 tag），保证首启与离线可用。
- 运行时：`Services/Knowledge/KnowledgePackLoader.swift` 用 `NSBundleResourceRequest` 优先取 ODR 包，失败回退内置副本。
- 知识包当前以仓库内 JSON 为源；需要更新时直接编辑 `Resources/KnowledgePack/`（及 fallback 副本）并同步 `pack-manifest.json`。
- 后续可按地域/主题拆多包（每包一个 ODR tag），结构已预留。

## 已移除的后端

Go BFF（`CultureLensBackend/`）已从仓库删除。识别与知识检索均在端侧完成；`RemoteRecognitionService`、`CultureLensAPI` 等远程调用路径亦已删除。
