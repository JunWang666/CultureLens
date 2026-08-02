# Design 0013：PostgreSQL 容器基础设施

- 日期：2026-07-30
- 状态：已实施并验证
- 影响范围：VM `192.168.3.138`、Docker 网络与持久卷、后续 Go `KnowledgeRepository`
- 前置设计：
  - `0005-go-recognition-and-knowledge-backend.md`
  - `0008-database-first-recognition-candidates.md`
  - `0010-pve-internal-service-network.md`

> 后续设计 0015 已完成 schema migration、审核目录导入、只读账号授权和 Go API 切换。

## 背景

CultureLens 后端当前使用编译进 Go 二进制的 `reviewed-catalog-v1` JSON 和不可变内存索引。
G3 计划需要 PostgreSQL，但当前生产 VM 尚无数据库服务。

本次先建立可持久化、可供后端和开发机连接的 PostgreSQL 基础设施。暂不创建业务表、不迁移审核目录，
也不改变当前 API 的读写路径。

## 版本

使用 Docker Official Image：

```text
postgres:18.4-alpine
```

选择明确的 `18.4` patch tag，不使用浮动 `latest`。PostgreSQL 18 的容器数据根目录挂载到
`/var/lib/postgresql`，实际 `PGDATA` 使用 `/var/lib/postgresql/18/docker`，避免错误挂载导致重建
容器后数据落入匿名卷。

首次拉取后记录镜像 digest；同一部署重建应使用相同 tag 与已记录 digest，升级 patch 或 major 前先备份和
验证恢复。

生产 VM 直连 Docker Hub 曾出现 `context deadline exceeded`。按部署环境配置以下 Docker Hub registry
mirror：

```text
https://2i4cjmb0k3zjbpwjri.xuanyuan.run
```

该地址写入 `/etc/docker/daemon.json` 的 `registry-mirrors`。修改前保留既有 daemon 配置；本次确认原文件
不存在，因此创建最小 JSON 配置。重启 Docker 后必须验证现有 `culturelens` 容器自动恢复且健康。

## 容器与网络

```text
container: culturelens-postgres
networks:  bridge（主机端口发布）+ culturelens-db（Docker internal bridge）
volume:    culturelens-postgres-data -> /var/lib/postgresql
port:      VM 0.0.0.0:5432 / [::]:5432 -> container 5432
restart:   unless-stopped
```

现有 `culturelens` API 容器在数据库健康后增加 `culturelens-db` 网络附件，同时保留原 bridge 网络用于
访问 Gemini 和对外提供 API。PostgreSQL 同时接入 bridge 网络以生成主机端口映射；仅连接 Docker
`--internal` 网络时端口映射不会产生实际主机监听。发布端口用于开发机调试，可通过
`192.168.3.138:5432` 或 PVE 内部地址 `10.0.0.108:5432` 访问。

Docker 端口发布只让 VM 已有网络可达；它不包含路由器端口转发或 Cloudflare TCP Tunnel，因此不承诺从
互联网直接连接。若以后需要互联网访问，必须另行设计 TLS、来源 IP 限制或零信任隧道，不能裸露数据库。

数据库主机名固定为 `culturelens-postgres`。未来后端连接形式：

```text
postgres://culturelens_app:<secret>@culturelens-postgres:5432/culturelens?sslmode=disable
```

`sslmode=disable` 只适用于同主机的 Docker network。局域网调试连接当前也未启用 TLS，仅用于受信网络；
若以后跨不受信网络访问，必须改为 TLS。

## 身份与秘密

初始化两个角色：

- `culturelens_admin`：数据库所有者和迁移管理角色，不供 API 日常查询使用。
- `culturelens_app`：无超级用户、无建库、无建角色权限，供未来 Go API 使用。

秘密只保存在 VM：

```text
/opt/culturelens/postgres-admin-password
/opt/culturelens/postgres-app-password
/opt/culturelens/postgres.env
/opt/culturelens/database.env
```

所有文件均为 `root:root`、权限 `0600`。密码使用服务器本地 CSPRNG 生成，不进入 Git、命令输出、日志、
设计文档或聊天。PostgreSQL 官方镜像通过 `POSTGRES_PASSWORD_FILE` 读取管理员密码。

`database.env` 预留未来后端使用的 `DATABASE_URL`，本次不注入当前 API 容器，避免代码尚未实现 PG
Repository 时造成误导。

## 资源与健康检查

- 容器内存上限：1 GiB。
- CPU 上限：1 核。
- `/dev/shm`：256 MiB。
- 健康检查：`pg_isready -U culturelens_admin -d culturelens`。
- 容器保持 `unless-stopped`，宿主机 Docker 重启后自动恢复。

服务器实施前状态为约 7.8 GiB 总内存、43 GiB 可用磁盘，足够当前空库和后续首批审核数据。

## 本次验证

1. 容器状态达到 `healthy`，实际版本为 PostgreSQL 18.4。
2. `docker info` 显示指定 registry mirror，服务器可经该配置拉取官方镜像。
3. `culturelens` 数据库存在，UTF-8 编码正常。
4. `culturelens_app` 为非超级用户且不能建库、建角色。
5. 从 `culturelens-db` 网络内可以用应用账号执行 `SELECT 1`。
6. VM IPv4/IPv6 的 5432 正常监听，LAN `192.168.3.138:5432` 可建立认证连接。
7. 创建探针表、写入一行、重启容器后仍可读取，再删除探针表。
8. 原 API 容器继续 `healthy`，公网 `/health` 继续返回 200。

## 后续边界

本次不包含：

- `pgx`、`sqlc`、迁移工具接入。
- 业务 schema 和知识图谱表设计。
- `reviewed-catalog-v1` 或 2551 条 imported 数据迁移。
- 自动备份、异机恢复和监控告警。

在写入正式数据前，必须补充业务 schema/migration 设计和至少一套定期备份与恢复演练。

## 回滚

当前 API 未读取 PostgreSQL，因此数据库启动失败不会影响线上识别。回滚时只停止数据库容器并断开 API
容器的 `culturelens-db` 网络；持久卷和 VM 密钥文件保留，除非用户明确要求销毁数据。

## 实施结果

- VM 的 `/etc/docker/daemon.json` 已配置
  `https://2i4cjmb0k3zjbpwjri.xuanyuan.run`，daemon 校验和重启通过。
- 经 registry mirror 拉取 `postgres:18.4-alpine`，仓库 digest 为
  `sha256:9a8afca54e7861fd90fab5fdf4c42477a6b1cb7d293595148e674e0a3181de15`。
- `culturelens-postgres` 运行状态为 `healthy`，实际 PostgreSQL 版本为 18.4。
- `culturelens` 数据库为 UTF-8，所有者 `culturelens_app` 为非超级用户、不可建库和建角色。
- PG 与 API 同时加入 `culturelens-db`；PG 另接 bridge，VM 的 IPv4/IPv6 5432 均监听。
- 从 Docker internal network 和 `192.168.3.138:5432` 均已使用应用账号认证成功；开发 Mac 到
  `192.168.3.138:5432` 的 TCP 连接成功。
- 持久卷为 `culturelens-postgres-data:/var/lib/postgresql`。临时探针写入后重启容器仍可读取，随后已删除。
- 四个服务器秘密/环境文件均为 `root:root`、权限 `0600`，密码未写入日志或项目文件。
- 原 CultureLens API 容器保持 `healthy`，公网 `https://cl.codight.online/health` 返回 200。
