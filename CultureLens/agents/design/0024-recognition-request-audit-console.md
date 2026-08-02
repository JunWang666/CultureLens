# Design 0024：识别请求全量审计与最近 100 条管理台

- 日期：2026-08-01
- 状态：已实施、部署并完成生产端到端验证
- 影响范围：PostgreSQL schema、识别 HTTP 入口、运行时/编辑角色权限、管理 API、内嵌管理前端、生产部署
- 前置设计：
  - `0005-go-recognition-and-knowledge-backend.md`
  - `0019-west-lake-content-admin.md`
  - `0022-cultural-content-recognition-pipeline.md`

## 1. 目标与范围

后端持久化每一次 `POST /v1/recognitions` 调用，成功、校验失败、数据库失败、Provider 失败和客户端取消都尽量形成一条审计记录。
管理端提供最近 100 条列表和单条详情，用于定位真机请求内容、图片输入、位置上下文、模型响应、错误与耗时。

“全量”在本设计中表示：

- 所有识别调用都记录，不只记录成功请求；
- 有效 JSON 请求保存整图和可选框选图原始字节、MIME、位置、场景备注和 locale；
- 保存完整成功响应或公开错误 envelope、HTTP 状态和端到端耗时；
- 无法解析的 JSON 仍记录状态、耗时和原始字节数，但不保存任意未解析正文；
- 不记录 Google API Key、数据库凭据、代理地址、Cookie、Authorization 或全部 HTTP headers。

当前管理 UI 只查询最近 100 条，数据库历史不自动删除。自动保留期限和容量阈值需要后续结合实际流量确定。

## 2. 数据结构

新增 `recognition_request_logs`（migration 5 创建，migration 6 在存在历史默认 ACL 时强制恢复最小权限）：

```text
id BIGINT identity primary key
request_id TEXT
received_at / completed_at / duration_ms
http_status / error_code
request_body_bytes
request_payload JSONB               # Base64 图片字段已剥离
context_image BYTEA / context_mime_type / context_image_bytes
focus_image BYTEA / focus_mime_type / focus_image_bytes
response_payload JSONB              # 成功响应或公开错误 envelope
model_identifier / prompt_version / schema_version
resolution_status / cultural_element_key / canonical_name
```

按 `(received_at DESC, id DESC)` 建索引。图片不进入列表查询；只在管理详情显式加载单张图片，避免最近 100 条响应携带大量 Base64。

## 3. 权限与隐私边界

- `culturelens_app` 只有审计表的 `INSERT` 和 identity sequence 使用权限，不获得历史读取权限。
- `culturelens_editor` 只有审计表 `SELECT` 权限，通过现有 server-only 管理连接读取。
- 管理页面和 `/v1/admin/recognition-requests*` 延续现有 Cloudflare Zero Trust 边界，不进入公开 OpenAPI。
- 图片响应使用 `Cache-Control: no-store`、`X-Content-Type-Options: nosniff` 和准确 MIME。
- 运行日志只写 request ID、状态和审计落库失败，不输出图片、请求 JSON 或响应正文。
- 审计写入失败不能改变原识别响应；服务记录结构化错误，避免观测系统反过来使识别不可用。

## 4. 写入流程

```text
POST /v1/recognitions
  -> 分配 X-Request-ID + 记录开始时间
  -> 限制并读取请求体
  -> JSON 解码
       失败：记录 400 + body bytes，不保存任意正文
       成功：剥离 Base64 后保存请求 JSON；可解码图片保存 BYTEA
  -> Recognition Pipeline
  -> 形成成功响应或公开错误 envelope
  -> 使用脱离客户端取消、带短超时的数据库 context 同步写审计
       写入失败：只写结构化服务日志
  -> 返回原响应
```

审计写入位于 HTTP 边界而不是 Provider 或 Repository 内，因此能覆盖进入识别路由后的全部业务结局，并保存实际对客户端返回的状态。

## 5. 管理 API 与页面

- `GET /admin/recognitions`：内嵌只读页面。
- `GET /v1/admin/recognition-requests?limit=100`：按时间倒序返回最多 100 条，不包含图片字节。
- `GET /v1/admin/recognition-requests/{id}/images/context`：返回整图。
- `GET /v1/admin/recognition-requests/{id}/images/focus`：返回框选图；不存在时返回 404。

页面显示成功/失败、时间、耗时、主结果、模型与版本、是否包含位置/框选图、请求与响应 JSON，并按需加载图片。页面只读，不提供删除或重放，避免误操作和重复上传。

## 6. 验证与部署

- migration：表、索引、角色最小权限、down migration。
- Repository：插入成功/失败记录；最近 100 条倒序且不取图片；单图读取和不存在语义。
- API：成功与失败识别均尝试审计；审计失败不改变响应；管理列表、图片、404、无管理连接。
- UI：HTML/CSP/no-store 合约，空状态、刷新、详情和图片懒加载。
- 执行 `go test ./...`、`go vet ./...`、PostgreSQL 18.4 集成测试、Docker 本地冒烟。
- 生产迁移前备份数据库；迁移后部署新镜像，验证一条成功和一条失败识别均出现在最近请求页。

## 7. 生产实施记录

- migration 前备份：`/opt/culturelens/backups/culturelens-pre-audit-console-20260801T2023.dump`，
  `root:root/0600`，43,735 bytes，SHA-256
  `113165e0ce08ec44da0b815320e02428b353765fcdc85355df06c4b8a9fa8f39`，`pg_restore --list` 验证通过。
- migration 5 创建表后发现生产 `culturelens_admin` 历史 default ACL 自动赋予 app 新表 SELECT；容器切换前停止，
  新增并执行 migration 6，最终权限验证为 app `INSERT=true / SELECT=false / sequence USAGE=true /
  sequence SELECT=false`，editor `SELECT=true / INSERT=false`。
- 生产 schema 当前为 6；最终镜像
  `culturelens:20260801-audit-console` ID 为
  `sha256:20aec1727557590856e8f80727ea70e81aae33b874a0b4553831999ec0116068`。正式容器保持原代理、端口、
  `unless-stopped` 与 `bridge + culturelens-db` 双网络，启动零重试且健康；旧 v5 容器保留为
  `culturelens-rollback-pre-audit-console-20260801`，状态 stopped、restart policy `no`。
- 公网 `/admin/recognitions`、最近 100 条 API 和图片接口均返回 200。真实 `gemini-3.6-flash` 测试请求返回 200，
  非法 JSON 返回 400；两者分别写入审计 ID 1/2，列表倒序正确。成功记录保存 68-byte PNG，图片接口返回
  `image/png`、`Content-Length: 68`、`Cache-Control: no-store` 与 `nosniff`；非法 JSON 记录没有请求正文或图片。
- 最终审计表 2 行、总 relation size 81,920 bytes；服务日志没有审计写入失败。上传用临时镜像归档已删除。
