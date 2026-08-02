# Design 0011：Huma API 文档与 OpenAPI

- 日期：2026-07-30
- 状态：已实施并验证
- 影响范围：`../CultureLensBackend/internal/api`、Go module 依赖、Docker 镜像与公网 API
- 前置设计：
  - `0005-go-recognition-and-knowledge-backend.md`
  - `0008-database-first-recognition-candidates.md`
  - `0010-pve-internal-service-network.md`

## 背景

CultureLens 后端当前只有 `GET /health` 和 `POST /v1/recognitions`，接口契约分散在
Go struct、测试、README 和设计文档中，没有浏览器可访问的 API 文档页，也没有机器可读的
OpenAPI 文档。

现有 iOS 客户端已经依赖当前 JSON 字段、HTTP 状态、错误 envelope 和 `X-Request-ID`。
增加文档能力不能把 Huma 默认的 Problem Details 错误格式带入现有运行接口。

## 决策

引入 Huma v2，使用 Huma 的 Go struct schema 反射生成 OpenAPI 3.1，并启用内置交互式文档。

公开入口：

```text
GET /docs
GET /openapi.json
GET /openapi.yaml
GET /openapi-3.0.json
GET /openapi-3.0.yaml
GET /schemas/{schema}.json
```

OpenAPI 的生产 Server 固定为 `https://cl.codight.online`。

## 运行时边界

真实业务路由继续由现有 `net/http` handler 处理：

```text
GET /health
POST /v1/recognitions
```

Huma 在独立的文档 mux 中注册同名 typed operation，用领域 struct 生成 OpenAPI 与 schema。
顶层 handler 仅把 `/docs`、`/openapi.*`、`/openapi-3.0.*` 和 `/schemas/*` 交给 Huma；
业务路径继续交给现有 mux。

选择这个边界的原因：

- 保持 iOS 已使用的请求/响应字段完全不变。
- 保持现有稳定错误 envelope、HTTP 状态和中文消息不变。
- 保持 18 MiB 请求限制、图片校验、request ID 和日志路径不变。
- 避免 Huma 默认验证错误的 RFC 9457 Problem Details 替换现有客户端错误模型。
- 文档的 Try It 仍访问同一域名下的真实业务路径，不使用示例 handler。

后续若要让 Huma直接承载业务路由，必须先设计错误模型迁移和客户端兼容策略，不在本次范围。

## 文档模型

Huma typed operation 直接复用：

- `recognition.Request`
- `recognition.Response`
- `recognition.Location`
- `recognition.Candidate`
- `recognition.CultureObject`
- `recognition.Source`

文档层额外定义：

- 健康检查响应 `{ "status": "ok" }`。
- 稳定错误 envelope：`request_id`、`error.code`、`error.message`、`error.retryable`。
- `X-Request-ID` 请求头与响应头。

`POST /v1/recognitions` 明确记录：

- `application/json` 请求。
- 最大请求体 18 MiB。
- 整图、可选框选特写、粗粒度位置和 locale 字段。
- 200、400、413、415、502、503、504 响应。
- 不在示例中放置真实图片、API key 或用户位置。

## 依赖与制品

- 锁定 Huma v2 的明确版本，不使用未固定的 `latest`。
- 使用标准库适配器 `adapters/humago`，不新增 Chi 或其他路由器。
- Huma 文档页和 OpenAPI 由 Go 进程直接提供，不增加独立文档容器或静态站点。
- Docker 镜像继续只复制 Go 二进制和 Prompt/Schema；Huma 文档资源由依赖编译进二进制。

## 验证

1. 现有 API 合约测试全部保持通过。
2. `/docs` 返回 200 和 HTML。
3. `/openapi.json` 与 `/openapi.yaml` 返回 200。
4. OpenAPI 包含 `/health` 和 `/v1/recognitions`，并且 method、Server、请求 schema 和错误状态正确。
5. malformed JSON、非法图片、正常 Mock 识别仍返回原有 envelope。
6. `go test ./...` 与 `go vet ./...` 通过。
7. 重建并部署 Docker 镜像后，公网 `https://cl.codight.online/docs` 和
   `https://cl.codight.online/openapi.json` 可访问，原 `/health` 继续正常。

## 回滚

- 恢复原 `net/http` 路由装配。
- 移除 Huma module 依赖和文档测试。
- 重新构建并部署上一个镜像 digest。

业务 API 和 iOS 契约不需要回滚或迁移。

## 实施结果

- 锁定 `github.com/danielgtaylor/huma/v2 v2.39.0`。
- 增加独立 Huma 文档 mux，原 `net/http` 业务 handler 与稳定错误 envelope 保持不变。
- `/docs`、OpenAPI 3.1/3.0 JSON/YAML 和 schema 路径已由同一 Go 进程提供。
- `go test ./...`、`go vet ./...`、本地 HTTP 冒烟和 Docker 临时容器验证通过。
- 镜像 `sha256:6bfb5111c29f5e5bad8b8d2fd495f0236ede3d3da2a9994d0a1db7bc1c486a9f`
  已部署至 `192.168.3.138`，生产容器健康。
- 公网 `https://cl.codight.online/docs`、`/openapi.json` 和原 `/health` 均验证通过。
- 旧生产容器保留为停止状态的 `culturelens-rollback-huma`，可用于快速回滚。
- 当时腾讯云仓库推送因本机 macOS 钥匙串凭据助手阻塞，服务器使用本地镜像直传部署；后续 0015
  PostgreSQL 版 `latest` 已成功推送并取代该镜像。
