# Design 0022：新文化内容识别管线

- 日期：2026-08-01
- 状态：已实施、部署并完成生产端到端验证
- 影响范围：Go ContentRepository、识别管线、Gemini Prompt/Schema、识别响应、iOS 领域模型、测试与生产部署
- 前置设计：
  - `0008-database-first-recognition-candidates.md`
  - `0017-cultural-elements-and-attraction-introductions.md`
  - `0018-go-cultural-content-query-api.md`

## 1. 问题

首页和内容查询已经迁移到 `cultural_elements`、`attractions` 与
`attraction_cultural_introductions`，但图片识别仍调用旧
`knowledge_catalogs/knowledge_nodes` 的 `Repository.Candidates`。旧目录按产品要求清空后，
Repository 把零行结果当作错误，API 又把未分类错误映射成 503，因此图片通过校验后在调用 Gemini 前固定失败。

这同时包含两个错误边界：

1. 新内容表已是正式事实源，识别仍依赖明确标记为过渡兼容的旧目录。
2. “数据库正常但没有候选”与“数据库查询失败”被合并成同一种服务不可用。

## 2. 决策

识别改为使用独立的 `RecognitionKnowledgeRepository`，候选和位置上下文都来自新内容模型：

```text
整图 + 框选图 + 约略位置
  -> RecognitionKnowledgeRepository
       -> cultural_elements：最多 12 个文化元素候选
       -> attraction_cultural_introductions：约略位置 50 km 内的现场上下文
       -> 有现场上下文的文化元素优先，其余元素继续保留
  -> Gemini
       -> 返回 cultural_element_key 或空字符串
  -> 服务端校验 key
       -> 命中：数据库名称和介绍覆盖模型事实
       -> 未命中/空候选：保留模型视觉结果，resolutionStatus=unresolved
```

- Provider v5 使用 `cultural_element_key`，不再使用旧 `catalog_object_id`。
- 候选包含稳定 key、名称和富文本介绍；现场上下文包含景点名、介绍名和介绍正文，不把经纬度发送给 Gemini。
- 约略位置只影响候选顺序和现场上下文，不删除未在附近出现的文化元素。
- 数据库返回零个文化元素是合法状态：继续调用 Provider，允许开放集合识别。
- 只有 PostgreSQL 查询实际失败才中止识别并返回 503。
- 旧 `Repository.Candidates` 暂时只为旧测试/兼容代码保留，不再处于生产识别调用链。

## 3. 响应兼容

- iOS 现有 `CultureObject.id: UUID` 保持不变。已解析文化元素使用
  UUID v5 风格的确定性 UUID：`URL namespace + "culturelens:cultural-element:" + key`。
- `CultureObject` 和备选候选新增可选 `culturalElementKey`；旧历史快照和旧响应可继续解码。
- 已解析结果的名称与摘要来自 `cultural_elements`；当前新表没有类别、时期、地域和来源字段，因此类别沿用经校验的
  视觉类别，时期/地域不冒充数据库事实，来源保持空数组。
- 为兼容现有客户端，响应暂时保留 `catalogVersion` / `catalogCandidateCount` 字段，值分别表示
  `cultural-elements-v1` 与本次文化元素候选数；后续可在 API v2 中改名。

## 4. 空数据与错误语义

| 状态 | 行为 |
| --- | --- |
| 文化元素存在 | 携带候选调用模型并校验 key |
| 文化元素为空 | 不返回 503；不携带候选调用模型，结果为未收录 |
| 附近介绍为空 | 保留全部文化元素候选，不提供地点现场上下文 |
| PostgreSQL 查询失败 | 返回 503 `recognition_unavailable` |
| Gemini 超时/限流/不可用 | 保持现有 504/503 上游错误语义 |

## 5. 验证与部署

- Repository：文化元素读取、位置上下文、附近元素优先、空元素成功返回、数据库错误。
- Pipeline：新 key 解析、越界 key 拒绝、空候选仍调用 Provider、数据库事实覆盖、位置影响说明。
- Provider：v5 Prompt/Schema、新候选 JSON、附近上下文不含经纬度。
- API：有效图片在空候选下不再因 Repository 返回 503；数据库错误仍返回 503。
- 执行 `go test ./...`、`go vet ./...`、iOS arm64 Debug 与测试 target 编译。
- 生产已部署镜像 `culturelens:20260801-recognition-v5`；旧容器以
  `culturelens-rollback-pre-recognition-v5-20260801` 停止保留，环境配置备份为
  `/opt/culturelens/.env.pre-recognition-v5-20260801T1923`。
- 生产数据库隔离预检读取到 7 个文化元素和 10 条景点介绍，Mock 识别返回
  `recognition-v5` / `provider-recognition-v5`、7 个新候选及 HTTP 200。
- 正式容器和公网 `/health` 均返回 HTTP 200。生产机直连 Google AI Studio 不可达，现通过用户指定的
  `http://10.0.0.114:7890` 注入 `HTTP_PROXY` / `HTTPS_PROXY`，并使用 `NO_PROXY` 保持 PostgreSQL 与本机流量直连；
  代理前配置备份为 `/opt/culturelens/.env.pre-google-proxy-20260801T1935`。
- 带代理的正式容器启动零重试且健康；服务器本机与公网 `https://cl.codight.online/v1/recognitions` 的真实
  `gemini-3.6-flash` 请求均返回 HTTP 200，响应为 `recognition-v5` / `provider-recognition-v5`、
  `cultural-elements-v1` 和 7 个新表候选。旧目录 503 与 provider 出口 504 均已消除。
