# Design 0019：西湖首批内容与数据库管理台

- 日期：2026-08-01
- 状态：已实施并部署（应用层管理令牌已移除）
- 影响范围：生产 PostgreSQL 权限、Go 配置与 Repository、管理 API、内嵌单页 UI、首批西湖内容和部署
- 前置设计：
  - `0017-cultural-elements-and-attraction-introductions.md`
  - `0018-go-cultural-content-query-api.md`

## 目标

1. 向生产新表写入一组可直接验证附近推荐的西湖文化内容。
2. 提供一个简单管理页，后续可手工新增或修改文化元素、景点、介绍和 WGS84 坐标。
3. 保持公开只读接口与数据库只读账号不变，写能力使用独立数据库凭据；管理入口由 Cloudflare Zero Trust
   统一鉴权，不再叠加应用层令牌。

## 首批内容边界

- 文案为本项目原创短介绍，不复制景区官方介绍。
- 只陈述可稳妥表达的文化观察，不声称这是完整、权威或现场考古说明。
- 坐标来自 Wikidata、Wikimedia Commons 或基于 OpenStreetMap 的 Mapcarta，用作首版推荐锚点；它们不是现场测绘点，
  管理页允许后续人工校准。
- 导入包保留每个坐标的来源 URL；当前数据库按既定 schema 只保存坐标，不新增来源列。

首批景点锚点：

| key | 名称 | 纬度 | 经度 | 坐标来源 |
|---|---|---:|---:|---|
| `leifeng-pagoda` | 雷峰塔 | 30.233889 | 120.145000 | [Wikipedia](https://fr.wikipedia.org/wiki/Pagode_de_Leifeng) |
| `baochu-pagoda` | 保俶塔 | 30.263333 | 120.143611 | [Wikidata Q977249](https://www.wikidata.org/wiki/Q977249) |
| `jingci-temple` | 净慈寺 | 30.231130 | 120.144340 | [OpenStreetMap/Mapcarta](https://mapcarta.com/N4427428610) |
| `yue-fei-temple` | 岳王庙 | 30.257778 | 120.126111 | [Wikidata Q579874](https://www.wikidata.org/wiki/Q579874) |
| `wenlan-pavilion` | 文澜阁 | 30.253303 | 120.137856 | [Wikimedia Commons](https://commons.wikimedia.org/wiki/Category:Wenlan_Pavilion) |
| `su-causeway` | 苏堤 | 30.245833 | 120.133472 | [Wikimedia Commons](https://commons.wikimedia.org/wiki/Category:Su_Causeway) |
| `three-pools-mirroring-moon` | 三潭印月 | 30.240833 | 120.140278 | [Wikidata Q10866444](https://www.wikidata.org/wiki/Q10866444) |

## 权限与入口认证

- `culturelens_app` 继续只有公开查询所需的 `SELECT`。
- 新增 `culturelens_editor` 登录角色，只对 4 张新内容表拥有 `SELECT/INSERT/UPDATE`；不授予旧知识表、schema、
  role、database 或删除权限。
- API 使用独立 `CULTURELENS_ADMIN_DATABASE_URL` 建立上限 2 个连接的编辑池，不能复用只读连接串。
- `/admin` 与 `/v1/admin/*` 不再实现应用层令牌；公网入口的身份认证、会话、MFA 和访问策略由
  Cloudflare Zero Trust 负责，源站避免维护第二套登录状态。
- Zero Trust 是部署前置条件：隧道源站不得绕过访问策略直接暴露到公网；源站内网地址仍视为受信运维入口。
- `culturelens_editor` 密码仅是服务端到 PostgreSQL 的最小权限连接凭据，不发送到浏览器，也不等同于管理令牌。
- 页面和 API 均使用 `Cache-Control: no-store`；管理 API 不进入公开 OpenAPI。

## 管理 API

```http
GET /v1/admin/content
PUT /v1/admin/cultural-elements/{key}
PUT /v1/admin/attractions/{key}
PUT /v1/admin/attraction-introductions/{key}
PUT /v1/admin/cultural-element-relations/{elementKey}/{relatedElementKey}
PUT /v1/admin/content/import
```

- 单项 `PUT` 是幂等 upsert；path key 必须与 JSON key 一致。
- 富文本输入使用与数据库一致的 JSON block document；UI 的普通正文输入会生成单个 paragraph block。
- relation `PUT` 只新增显式无向关系，重复调用返回成功，不提供删除入口。
- bulk import 在单个事务中按“元素 → 景点 → 关系 → 景点介绍”执行；只 upsert 包内数据，不删除库中其他内容。
- key、名称、富文本、外键和坐标在 API 层验证，数据库约束继续作为最后防线。

## 管理页

`GET /admin` 返回编译进 Go 二进制的单页 UI：

- 页面打开后自动读取内容，可手工刷新；不再显示、存储或发送管理令牌。
- 展示文化元素、景点、介绍数量与列表。
- 文化元素表单：key、名称、正文。
- 景点表单：key、名称。
- 景点介绍表单：key、名称、正文、文化元素、景点、latitude、longitude；已有记录可一键载入修改。
- 关联表单：两个文化元素 key。
- 保存后自动刷新列表，显示实际 HTTP 状态、request ID 和错误信息。

首版不提供删除，避免误删关联数据；如需清理，后续另行设计带确认和审计的操作。

## 启动与失败边界

- 仅通过 `CULTURELENS_ADMIN_DATABASE_URL` 启用管理能力；缺失时公开 API 可正常启动，但
  `/v1/admin/*` 返回 503。
- 编辑数据库不可达时拒绝启动已启用管理功能的进程；不会回退到只读连接执行写入。
- 日志记录管理操作类型、资源 key 和 request ID，不记录数据库 URL、数据库密码或富文本正文。

## 验证与部署

- Repository：事务导入、幂等 upsert、关系重复、坐标与外键错误。
- API：400、503、无应用令牌成功 upsert 和非 null 列表。
- UI：CSP/no-store、只同源请求、无令牌存储和坐标编辑流程。
- 真实 PostgreSQL 18.4：migration 4、editor 精确授权、首批导入和 Haversine 推荐结果。
- 生产部署前再次备份数据库；先创建 editor 角色和 root-only 环境文件，再 migration、替换 API、导入内容。
- 部署后验证 `/admin`、管理鉴权、新内容计数、7 个景点坐标、附近推荐排序、公开健康和旧路径 404。
- 回滚 API 时保留 schema v4 和已导入内容；旧 API 不读取新表，不会破坏数据。

## 实施与部署结果

- 新增 migration 4、独立 `contentadmin.PostgresRepository`、受保护管理 API、`/admin` 单页 UI、镜像内
  `culturelens-content import` 事务导入命令和 `content/hangzhou-west-lake.v1.json` 审计包。
- `go test -count=1 ./...` 与 `go vet ./...` 通过。隔离 PostgreSQL 18.4 中验证 schema v4、重复导入、
  坐标更新、Haversine 查询；editor 权限矩阵为新表 SELECT/INSERT/UPDATE=true，DELETE、旧知识表 SELECT、
  schema CREATE、database CREATE=false，临时容器已删除。
- 生产变更前备份为 `/opt/culturelens/backups/culturelens-pre-west-lake-admin-20260801T161400.dump`，权限
  `root:root/0600`，大小 39668 bytes，SHA-256 为
  `fc9d9a9f2605686823fe49b38cedca60615045f954ee9c9719d16db0db7a0b64`，并通过 `pg_restore --list` 校验。
- 生产已创建 `culturelens_editor`，无 superuser/createdb/createrole/replication；随机密码、管理令牌和两个 env
  文件均在 `/opt/culturelens` 以 `root:root/0600` 保存，令牌未写入代码、镜像、日志或工作记录。
- 生产 schema 已升级为 v4，权限矩阵与隔离测试一致。隔离测试中重复导入保持幂等；生产执行一次导入后计数为
  7 个元素、7 个景点、5 条关系和 10 条景点介绍。
- 生产镜像 ID 为 `sha256:877dec0e37935a8248e483199591bfe05fad70b887f3124f54b2746c70c999f4`，唯一标签
  `20260801-west-lake-admin` 与 `latest` 的 registry digest 均为
  `sha256:86ff4f11824cb5aa0d6e80b78ceb5a1c33a4c12d56c03905015eed5027f07fc4`。
- 新容器保持 8080、`unless-stopped` 和 `bridge + culturelens-db` 双网络并为 healthy；旧版本保留为停止的
  `culturelens-rollback-pre-west-lake-admin-20260801`。
- 公网 `/admin` 与 `/health` 为 200；无令牌管理 API 返回带 `WWW-Authenticate` 的 401，生产主机内部用正确
  令牌读取成功。公开 OpenAPI 不包含 admin 路径。
- 雷峰塔坐标 50 米范围公开查询返回 2 条按距离排序的介绍；`west-lake-ten-scenes` 返回 4 个显式关联元素，
  证明生产写入已进入公开查询链路。

## 2026-08-01 无应用令牌调整

- 用户确认公网管理入口已接入 Cloudflare Zero Trust，因此撤销本设计最初的 Bearer token 双重认证方案。
- Go 服务、管理单页、环境变量和部署文件删除 `CULTURELENS_ADMIN_TOKEN`；管理页不再使用
  `sessionStorage`，管理 API 不再读取 `Authorization`。
- 生产已发布镜像 `20260801-zero-trust-admin`，镜像 ID 为
  `sha256:283311b842e73b41d61d6cd163f440e2c3e31e868c5fbafba96a51541ec1f0af`，registry digest 为
  `sha256:4a2d9537674bedd1b7513a8bca88656205f2fdc3bad517051ffc44d456122f89`。
- `/opt/culturelens/admin-token`、`/opt/culturelens/admin.env` 和暂存的含旧令牌容器均已删除；保留
  `culturelens_editor` 最小权限数据库账号和 root-only `database-editor.env`。
- 新容器为 healthy，运行环境中不存在 `CULTURELENS_ADMIN_TOKEN`；源站与经 Cloudflare 的 `/admin`、
  `/v1/admin/content` 均无需应用令牌返回 200，页面不包含 token、`sessionStorage` 或 `Authorization` 逻辑。
- 此调整以 Cloudflare Zero Trust 持续覆盖 `/admin` 和 `/v1/admin/*` 为安全边界；若未来开放源站公网直连，
  必须先新增独立认证设计，不能沿用当前无令牌接口。
