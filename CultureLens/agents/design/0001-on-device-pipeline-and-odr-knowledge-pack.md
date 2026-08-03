# 0001 端侧识别管线与 ODR 知识分包

- 状态：已实现（2026-08-02）
- 取代：CultureLens `design/0005`（Go BFF 承担识别管线）在 CultureLens 中的对应部分

## 背景

CultureLens 的识别链路为 App → Go BFF →（PostgreSQL 候选 + prompt 拼接）→ Gemini。数据库内容仅 36KB，拼接逻辑为纯函数，全部可以在端侧完成；服务端只保留 LLM 出口与图片托管。CultureLens 因此把管线搬到端侧，后端依赖降为两个外部服务。

## 架构

```
拍照/选图 → ImagePreprocessor（沿用旧版）
  → KnowledgeStore（本地知识包：Haversine 附近查询、候选优先级 top12、BFS 图谱、景点绑定）
  → PromptAssembler（v5.txt + 候选 JSON，对齐 googleai/client.go 的文本）
  → LLMGatewayClient（Cloudflare AI Gateway，OpenAI 兼容 chat/completions，
     model=dynamic/culturelens，response_format=json_schema=v5.schema.json）
  → RecognitionResponseMapper（key 校验、UUIDv5、富文本压平、category→SF Symbol）
  → RecognitionResult（与旧版同一领域模型，UI 零改动）
```

移植来源（Go）：`internal/knowledge/postgres.go`、`internal/recognition/pipeline.go`、`internal/providers/googleai/client.go`、`internal/database/queries/content.sql`。逐函数对应关系见各 Swift 文件头注释。

## 知识包与分包分发

- 包格式 = 原后端 `contentadmin.Bundle` JSON 同构；现以仓库内 `Resources/KnowledgePack/` 为源，附带 `pack-manifest.json`（packVersion / generatedAt / recordCounts / sha256）。
- 分发 = 整库一个 ODR asset pack，tag `knowledge-base`，App Store Connect 托管；**当前为 initial-install 随首装下发**（`ON_DEMAND_RESOURCES_INITIAL_INSTALL_TAGS`），将来移除该 build setting 即切换为按需下载。运行时 `KnowledgePackLoader` 用 `NSBundleResourceRequest` 访问。
- 回退 = App 内置同内容副本（`Resources/KnowledgePackFallback/`），ODR 不可用或未完成下载时使用，保证离线与首启可用。
- 多包扩展 = 后续按地域拆分（如 `knowledge-hangzhou`、`knowledge-silkroad` 各自成 tag），loader 按请求地拉取；manifest 字段已预留。

## LLM 出口

- 端点：`https://gateway.ai.cloudflare.com/v1/b6fa8079d0ef1344774cb287040dc153/apps/compat/chat/completions`，Bearer key 硬编码（见 `LLMGatewayConfig.swift`）。
- 已实测：多模态 `image_url`（data URI）、`response_format: json_schema`、实际路由到 gemini-3.6-flash。
- 已知取舍：key 可被逆向，需在 Cloudflare 侧配限额告警；后续可换远程下发。

## 图床

- 富文本 block 新增 `{"type":"image","url","caption"}`，URL 指向 Cloudflare R2 公开对象；本地不存图片。后端 `contentadmin` 校验已同步放宽。

## 备选方案（未采用）

- 保留 Go BFF 做精简 LLM 代理：更安全但违背「只做端侧 + 图库」的目标，且要长期运维。
- 知识包用 SQLite：当前 36KB 全量入内存足够，JSON 解码即可；数据量增长到 MB 级后再评估。
- Apple Foundation Models 端侧模型：视觉能力与中文文化知识不足。
