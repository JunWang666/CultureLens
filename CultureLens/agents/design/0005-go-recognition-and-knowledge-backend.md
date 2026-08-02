# Design 0005：Go 识别与文化知识后端

- 状态：G1/G2 已完成；G3 PostgreSQL 审核目录基础已由 0015 实施，真实模型与离线评测待验证
- 日期：2026-07-29
- 影响范围：独立仓库 `../CultureLensBackend/`、iOS 识别服务契约、视觉模型调用、评测体系、文化知识图谱、数据存储和部署
- 前置设计：
  - `0003-location-aware-recognition-and-history.md`
  - `0004-directed-cultural-knowledge-graph.md`
- 后续设计：`0006-focused-recognition-and-evaluation.md`

> 0006 已将质量优先默认模型更新为 `gemini-3.6-flash`，并把当前 Prompt/Schema 更新为
> `recognition-v2` / `provider-recognition-v2`。本文件中保留的 Flash-Lite 与 v1 示例用于记录最初
> G2 决策，当前运行配置以 0006 为准。
>
> 0008 已落地只读 KnowledgeRepository、审核候选检索和实体解析，并把当前 Prompt/Schema 更新为
> `recognition-v4` / `provider-recognition-v4`。位置现由 Repository 使用，不再直接发送给模型；
> 当前运行配置以 0008 为准。
>
> 0015 已将生产 API 和 `cmd/eval` 的运行时 Repository 切换到 PostgreSQL，并保留内嵌 JSON 仅作为
> 幂等 seed 源和单元测试 fixture。当前数据库结构、迁移、账号权限和部署以 0015 为准。

## 1. 决策

CultureLens 后端采用 Go 单体服务，不以 Python 或 Node.js 作为正式运行时。

旧 Node 原型仅作为接口迁移参照，但不继续扩展为生产实现。Go 第一阶段
必须保持现有 iOS 使用的接口和 JSON 字段兼容，完成等价替换后再移除 Node 原型。

选择 Go 的原因：

- 后端当前主要承担 HTTP、模型 API 调用、结构化校验、实体归一、数据库查询和结果组装，不在进程内
  运行 PyTorch。
- 单二进制、启动快、容器小，适合低成本部署和频繁发布。
- 并发、超时、取消和流式 I/O 能直接使用标准库。
- Prompt、模型版本和评测集与语言无关，不要求线上服务使用 Python。
- 模型服务：Google AI Studio Gemini API；凭据只从独立后端仓库的 Git-ignored `.env` 或部署环境注入。`GOOGLE_AI_STUDIO_API_KEYS` 按声明顺序组成密钥池，只有上游返回 HTTP 429 / `RESOURCE_EXHAUSTED` 时才尝试下一个 key；不对其他错误切换或重试。

只有未来确定需要自托管 Python 模型时，才增加独立推理 Worker；Go API 仍作为对 iOS 的唯一入口。

## 2. 目标与非目标

### 2.1 当前目标

1. 用 Go 等价替换 Node BFF。
2. 建立可版本化的图片识别管线。
3. 建立离线评测命令，支持比较模型、Prompt 和上下文策略。
4. 保持 API Key、Prompt 和供应商细节不进入 App。
5. 为后续 PostgreSQL 知识图谱预留稳定 repository 边界。
6. 确保模型生成结果不会直接成为已审核知识图谱。

### 2.2 当前非目标

- 不在服务器中训练或微调视觉模型。
- 不自托管 GPU/VLM。
- 不引入微服务、Kafka、Kubernetes、Redis 或任务队列。
- 不在 MVP 阶段引入 Neo4j 等图数据库。
- 不保存用户原始照片。
- 不让模型自动写入正式知识节点或关系。

## 3. 总体架构

```text
iOS App
  -> POST /v1/recognitions
       -> HTTP validation
       -> image validation
       -> RecognitionPipeline
            -> prompt/model configuration
            -> GoogleAIStudioProvider
            -> structured output validation
            -> confidence policy
            -> EntityResolver
       -> optional KnowledgeRepository lookup
       -> stable App response

Admin / local developer
  -> cmd/eval
       -> evaluation dataset
       -> same RecognitionPipeline
       -> metrics + comparison report

PostgreSQL (Phase G3)
  -> culture objects / concepts / relations / sources
  -> aliases and entity resolution
  -> prompt versions / recognition runs / eval results
```

线上 API 和离线评测必须复用同一个 `RecognitionPipeline`，不能各自复制 Prompt 或解析逻辑。

## 4. 技术栈

### 4.1 核心

- Go：使用项目实施时仍受官方支持的稳定版本。
- HTTP：标准库 `net/http`；没有实际需求前不引入 Web 框架。
- 模型服务：Google AI Studio `generateContent`；使用 `gemini-3.5-flash-lite`，不在应用或日志中保存 API key。
- JSON Schema：使用 Go struct 作为领域源，并生成 Structured Outputs schema。
- PostgreSQL：`github.com/jackc/pgx/v5`。
- SQL 代码生成：`sqlc`。
- 数据迁移：`tern` 或同等级纯 Go 工具；项目初始化时二选一并锁定。
- 日志：标准库 `log/slog`，JSON handler。
- 链路：OpenTelemetry；第一阶段至少保留 request ID、阶段耗时和上游 request ID。
- 测试：标准库 `testing`、`httptest`；数据库集成测试使用独立测试库或容器。
- 构建：多阶段 Dockerfile，最终镜像只包含 Go 二进制、CA 证书和必要 Prompt 文件。

### 4.2 暂不引入

- ORM：知识图谱查询需要明确 SQL，使用 `pgx + sqlc`。
- Redis：只有出现跨实例缓存、限流或队列需求后再引入。
- libvips/OpenCV：App 已完成方向归一、1600 px 限制和 JPEG 重编码；后端第一阶段只验证，不重复做
  重型图像处理。

## 5. 仓库结构

```text
../CultureLensBackend/
  cmd/
    api/
      main.go
    eval/
      main.go
  internal/
    api/
      health_handler.go
      recognition_handler.go
      middleware.go
    config/
      config.go
    recognition/
      pipeline.go
      types.go
      confidence.go
      entity_resolver.go
    providers/
      vision.go
      openai/
        client.go
        mapper.go
    knowledge/
      repository.go
      types.go
      memory_repository.go
      postgres_repository.go
    storage/
      db.go
      generated/
    observability/
      logger.go
      metrics.go
  prompts/
    recognition/
      v1.txt
      v1.schema.json
  evals/
    datasets/
      smoke.jsonl
    expected/
    reports/
      .gitkeep
  sql/
    queries/
    schema/
  migrations/
  testdata/
  .env.example
  compose.yaml
  Dockerfile
  go.mod
  go.sum
  README.md
```

`internal/` 防止后端领域包被仓库其他模块错误依赖。`cmd/api` 和 `cmd/eval` 只做装配，不放业务逻辑。

## 6. 识别管线

### 6.1 阶段

```text
validate request
  -> validate image envelope
  -> choose model/prompt/schema versions
  -> call provider
  -> validate structured output
  -> apply confidence and refusal policy
  -> normalize object identity
  -> optionally attach reviewed knowledge
  -> map to client response
```

每个阶段返回有类型的错误，不直接把供应商错误文本暴露给 iOS。

### 6.2 图片边界

- iOS 上传重新编码后的 JPEG；当前最长边不超过 1600 px。
- Go 服务继续接受当前 JSON Base64 契约，避免第一阶段修改 App。
- 请求体上限延续 18 MiB，并在解码前限制读取长度。
- 校验 MIME、Base64、图片头、像素尺寸和解码结果。
- 不信任客户端提供的 MIME。
- 默认只在内存中处理图片；请求完成即释放。
- 日志不得包含 Base64、图片字节或精确位置。
- 后续若 Base64 成为真实瓶颈，再新增 multipart v2，不静默修改 v1。

### 6.3 位置上下文

- 只接受约略位置；小数点后最多两位。
- 地点名称限制为城市或同等级粗粒度文本。
- Prompt 明确要求位置只能调整候选概率，不能覆盖视觉证据。
- 评测必须分别运行“无位置”和“有位置”两组，量化位置增益及误导率。

### 6.4 结构化输出

供应商输出与 App 输出分离：

- `ProviderRecognition`：模型直接返回的严格结构。
- `RecognitionDecision`：通过置信度和实体归一后的内部结果。
- `RecognitionResponseV1`：兼容当前 iOS 的传输结构。

禁止把模型响应直接 `json.Marshal` 后转发给客户端。

## 7. Prompt、模型与 Schema 版本

每次识别必须记录三个独立版本：

```text
model_version
prompt_version
schema_version
```

规则：

- Prompt 作为仓库文件保存，不写成长字符串散落在 handler。
- 每个 Prompt 文件不可原地修改语义；有行为变化就新增版本。
- 模型通过环境变量选择，但响应必须记录供应商实际返回的模型标识。
- Structured Outputs schema 同样版本化。
- API 返回 `modelIdentifier`；后续可追加 `promptVersion` 和 `schemaVersion`，保持向后兼容。
- 线上默认版本变更前必须先跑评测集。

## 8. 实体归一

视觉模型回答的是名称，不是可靠的知识库 ID。`EntityResolver` 负责把结果映射到稳定对象：

```text
model canonical name
  -> exact canonical-name match
  -> alias match
  -> optional normalized-text match
  -> unresolved
```

MVP 规则：

- 已解析：返回知识库中稳定的 object UUID。
- 未解析：生成仅属于本次识别结果的 UUID，并标记 `resolutionStatus = unresolved`。
- 不允许仅凭模糊名称相似度把对象强制并入现有实体。
- iOS v1 可忽略新增状态字段；后续 UI 再明确显示“尚未归入知识库”。

## 9. 知识图谱边界

识别模型只负责对象候选、视觉依据和不确定性。文化知识服务负责经过审核的节点、边和来源。

```text
RecognitionPipeline
  -> stable object ID
  -> KnowledgeRepository.Subgraph(objectID, depth, limits)
  -> reviewed CultureObject + CultureConcept + CultureRelation
```

模型临时生成的文化概念可作为“待核验建议”，但：

- 不写入正式节点表。
- 不作为已审核关系返回。
- 不展示为有来源的事实。
- 必须经过人工或受控内容流程后才能进入图谱。

首版 Go BFF 可继续返回空 `relations`；内置斗拱图谱仍由 App 用于 UI 验证。

## 10. PostgreSQL 数据模型

Phase G3 引入以下核心表：

### 10.1 知识数据

```text
knowledge_nodes
  id UUID PK
  node_type TEXT
  canonical_name TEXT
  summary TEXT
  detail TEXT
  status TEXT
  content_version BIGINT
  created_at TIMESTAMPTZ
  updated_at TIMESTAMPTZ

knowledge_aliases
  id UUID PK
  node_id UUID FK
  normalized_alias TEXT
  locale TEXT
  UNIQUE(normalized_alias, locale)

knowledge_edges
  id UUID PK
  source_id UUID FK
  target_id UUID FK
  relation_kind TEXT
  explanation TEXT
  status TEXT
  content_version BIGINT
  created_at TIMESTAMPTZ
  updated_at TIMESTAMPTZ

knowledge_sources
  id UUID PK
  title TEXT
  publisher TEXT
  url TEXT
  accessed_at TIMESTAMPTZ

edge_sources
  edge_id UUID FK
  source_id UUID FK
  evidence_note TEXT
  PRIMARY KEY(edge_id, source_id)
```

`knowledge_edges` 的 source 和 target 都引用统一节点表，支持对象到概念、概念到概念的多跳关系。

### 10.2 识别与评测

```text
recognition_runs
  id UUID PK
  request_id TEXT
  model_version TEXT
  prompt_version TEXT
  schema_version TEXT
  result_object_id UUID NULL
  resolution_status TEXT
  confidence DOUBLE PRECISION
  used_place_context BOOLEAN
  latency_ms INTEGER
  input_tokens INTEGER NULL
  output_tokens INTEGER NULL
  outcome TEXT
  created_at TIMESTAMPTZ

eval_cases
  id UUID PK
  dataset_version TEXT
  expected_object_id UUID NULL
  image_ref TEXT
  coarse_place JSONB NULL
  tags TEXT[]

eval_results
  id UUID PK
  eval_case_id UUID FK
  model_version TEXT
  prompt_version TEXT
  schema_version TEXT
  predicted_object_id UUID NULL
  confidence DOUBLE PRECISION
  latency_ms INTEGER
  outcome TEXT
  raw_result JSONB
  created_at TIMESTAMPTZ
```

是否保存真实识别图片仍为待确认隐私决策。默认 `recognition_runs` 不保存图片或图片引用；评测图片只来自
明确授权的独立数据集。

## 11. HTTP API

### 11.1 第一阶段必须兼容

```http
GET /health
POST /v1/recognitions
```

`POST /v1/recognitions` 保持当前字段：

```json
{
  "request_id": "uuid",
  "image_base64": "...",
  "mime_type": "image/jpeg",
  "location": {
    "latitude": 31.23,
    "longitude": 121.47,
    "accuracy_meters": 1000,
    "display_name": "上海"
  },
  "context_note": "古建筑屋檐",
  "locale": "zh_CN"
}
```

响应继续兼容当前 `RecognitionResult`。允许增加客户端会忽略的可选字段：

```json
{
  "requestID": "uuid",
  "promptVersion": "recognition-v1",
  "schemaVersion": "provider-recognition-v1",
  "resolutionStatus": "resolved"
}
```

### 11.2 知识服务阶段

```http
GET /v1/objects/{objectID}
GET /v1/objects/{objectID}/graph?depth=2&limit=40
GET /v1/concepts/{conceptID}
GET /v1/objects/{objectID}/prerequisites
```

图谱接口必须限制深度、节点数量、边数量和允许的关系类型，避免一次请求展开整个知识库。

## 12. 错误模型

客户端只接收稳定错误码：

```json
{
  "request_id": "uuid",
  "error": {
    "code": "recognition_upstream_timeout",
    "message": "识别服务暂时不可用，请稍后重试。",
    "retryable": true
  }
}
```

至少覆盖：

- `invalid_request`
- `image_too_large`
- `unsupported_image`
- `recognition_upstream_timeout`
- `recognition_upstream_rejected`
- `recognition_invalid_output`
- `recognition_unavailable`
- `rate_limited`
- `internal_error`

HTTP 状态和错误码必须在合约测试中固定。

## 13. 超时、重试与取消

- 总请求预算：60 秒，与当前 iOS 超时保持一致。
- 上游模型预算：不超过 55 秒。
- iOS 断开或取消后，通过 request context 取消上游请求。
- 图片请求只会在 Google AI Studio 返回 HTTP 429 时按顺序切换到下一个配置 key；其他连接失败、5xx 或拒绝不更换 key。
- 图片请求不做无上限自动重试。
- 所有重试必须受总预算约束，并记录尝试次数。

## 14. 评测体系

`cmd/eval` 是正式产品能力，不是临时脚本。

支持：

```bash
go run ./cmd/eval \
  -dataset evals/datasets/culture-v1.jsonl \
  -model <model-version> \
  -prompt recognition-v2 \
  -schema provider-recognition-v1
```

首轮指标：

- Top-1 对象准确率。
- Top-3 候选召回率。
- 未知对象拒识率。
- 已知对象误拒率。
- 位置加入前后的准确率变化。
- 位置误导率。
- 结构化输出成功率。
- P50/P95 延迟。
- 单请求 token 与成本。

每份报告记录 Git commit、模型、Prompt、Schema 和数据集版本，保证结果可复现。

## 15. 可观测性与隐私

每个请求至少记录：

- 应用 request ID。
- 上游 request ID。
- model/prompt/schema 版本。
- 各阶段耗时。
- HTTP 与领域 outcome。
- token 使用量。
- 是否使用位置。
- 是否成功解析为稳定对象。

禁止记录：

- 图片 Base64 或原始字节。
- 精确位置。
- API Key。
- 未清洗的供应商完整请求。

OpenTelemetry 第一阶段可以只导出标准输出；部署环境确定后再接具体后端。

## 16. 配置

环境变量：

```text
PORT
GOOGLE_AI_STUDIO_BASE_URL
GOOGLE_AI_STUDIO_API_KEYS
CULTURELENS_VISION_MODEL
CULTURELENS_PROMPT_VERSION
CULTURELENS_SCHEMA_VERSION
DATABASE_URL
LOG_LEVEL
MOCK_RECOGNITION
```

规则：

- 生产模式缺少至少一个 Google AI Studio API key 时启动失败。
- Mock 模式不需要 Key。
- Prompt/Schema 版本不存在时启动失败。
- 配置只在启动时解析一次，生成不可变 config。
- API Key 不进入日志、数据库或错误响应。

## 17. 部署

MVP 使用单实例 Go API：

```text
HTTPS ingress
  -> CultureLens Go API container
  -> Google AI Studio -> gemini-3.5-flash-lite
  -> PostgreSQL (Phase G3)
```

Docker 使用多阶段构建：

1. builder 阶段下载依赖、运行测试、编译。
2. runtime 阶段复制静态二进制、CA 证书和 Prompt/Schema。
3. 非 root 用户运行。
4. `/health` 仅表示进程可服务；后续增加 `/ready` 检查必要依赖。

当前容器制品约定：

- 镜像仓库名为 `ccr.ccs.tencentyun.com/gouzuang/culturelens`，未指定发布版本时本地构建使用
  `latest` 标签；正式发布仍应增加不可变版本标签。
- 默认生成 `linux/amd64` 生产制品，Dockerfile 同时保留 BuildKit `TARGETOS` /
  `TARGETARCH` 跨平台编译能力。
- `.env`、评测数据和采集知识包不得进入 Docker build context；Google AI Studio Key 只能在
  容器启动时由部署环境注入。
- runtime 使用固定的非 root UID/GID `10001`，默认监听 `8080`，容器健康检查调用
  `GET /health`。
- 当前识别目录已经编译进二进制；Prompt/Schema 作为只读文件复制进 runtime 镜像。

暂不选择具体云平台，避免技术方案与单一供应商绑定。

## 18. 从 Node 原型迁移

### Phase G1：Go 合约等价实现

1. 建立 Go module 和目录骨架。
2. 移植 `/health`、请求限制、Base64/MIME 校验和错误处理。
3. 实现 Mock provider。
4. 把现有 `server.test.mjs` 合约用 Go `httptest` 重写。
5. 对同一输入比较 Node 与 Go JSON 响应。
6. iOS 指向 Go 服务完成 Mock 端到端验证。

验收：iOS 无需修改即可通过现有流程，Go 合约测试全部通过。

### Phase G2：真实模型与评测

1. 接入 Google AI Studio Gemini `generateContent` provider。
2. 将 Prompt 和 Schema 移到版本文件。
3. 建立 provider/pipeline 边界。
4. 加入 request ID、超时、取消、有限重试和结构化日志。
5. 建立最小标注集与 `cmd/eval`。
6. 完成真实模型端到端测试。

验收：有可复现评测报告，模型或 Prompt 变更可量化比较。

### Phase G3：知识图谱服务

1. 引入 PostgreSQL、pgx、sqlc 和迁移工具。
2. 导入已审核的斗拱节点、关系和来源。
3. 实现 EntityResolver。
4. 实现受限深度的 graph/prerequisites API。
5. iOS 从本地图谱切到远端子图，并保留缓存降级。

验收：斗拱图谱关系全部来自后端稳定 ID，边可追溯到来源。

### Phase G4：生产加固

1. 身份认证、限流和滥用防护。
2. 指标、trace 和告警。
3. 数据保留与删除策略。
4. 灰度发布和 Prompt/模型回滚。
5. 容量与故障演练。

## 19. 验证要求

- `go test ./...` 通过。
- `go vet ./...` 通过。
- Mock 合约测试覆盖健康检查、成功、非法请求、超限、超时和取消。
- iOS 使用 Go Mock 服务完成识别结果解码。
- 不配置真实 Key 时不产生外部模型请求。
- 真实模型版本切换不修改 handler 或 iOS。
- 所有知识边能解析 source/target，并至少关联一个审核来源后才可进入正式服务。

## 20. 待确认

- Go 数据迁移工具最终选择 `tern` 还是其他方案。
- 首批评测图片的授权、存储位置和保留周期。
- 知识内容审核角色和发布流程。
- MVP 部署平台与域名。
- iOS 访问后端的身份认证方式。
