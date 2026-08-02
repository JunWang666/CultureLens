# CultureLens agents 工作区

这个目录记录项目目标、当前状态、设计决策和后续计划。开始新的开发工作前，先阅读本文件、`PROJECT.md` 和 `STATUS.md`。

## 目录约定

- `PROJECT.md`：长期稳定的产品目标、工程现状和约束。
- `STATUS.md`：当前阶段、已完成事项、下一步和阻塞项。
- `design/`：涉及架构、数据结构、跨模块流程的设计文档。

## 工作规则

1. 开始工作前先确认 `STATUS.md` 是否仍与代码一致。
2. 修改架构、持久化模型、服务协议或跨模块数据流前，必须先新增或更新 `design/` 文档。
3. 实现完成后同步更新 `STATUS.md`，记录验证方式和遗留问题。
4. 文档描述的是已确认决策；尚未确认的内容必须标记为“待定”或“假设”。
5. 效果稿用于定义产品方向，不等同于已经存在的技术能力。

## 当前入口

- 产品与工程概览：[`PROJECT.md`](PROJECT.md)
- 当前工作状态：[`STATUS.md`](STATUS.md)
- MVP 设计：[`design/0001-culturelens-mvp.md`](design/0001-culturelens-mvp.md)
- 人文 Liquid Glass UI：[`design/0002-humanist-liquid-glass-ui.md`](design/0002-humanist-liquid-glass-ui.md)
- 位置感知识别与扫描历史：[`design/0003-location-aware-recognition-and-history.md`](design/0003-location-aware-recognition-and-history.md)
- 有向文化知识图谱：[`design/0004-directed-cultural-knowledge-graph.md`](design/0004-directed-cultural-knowledge-graph.md)
- Go 识别与文化知识后端：[`design/0005-go-recognition-and-knowledge-backend.md`](design/0005-go-recognition-and-knowledge-backend.md)
- 用户框选、多候选与识别评测：[`design/0006-focused-recognition-and-evaluation.md`](design/0006-focused-recognition-and-evaluation.md)
- 约略位置先验与候选重排：[`design/0007-location-prior-candidate-ranking.md`](design/0007-location-prior-candidate-ranking.md)
- 数据库优先的识别候选与实体解析：[`design/0008-database-first-recognition-candidates.md`](design/0008-database-first-recognition-candidates.md)
- 丝绸之路来源采集与可追溯知识库：[`design/0009-silk-road-source-ingestion-and-knowledge-bundle.md`](design/0009-silk-road-source-ingestion-and-knowledge-bundle.md)
- PVE 内部服务网络：[`design/0010-pve-internal-service-network.md`](design/0010-pve-internal-service-network.md)
- Huma API 文档与 OpenAPI：[`design/0011-huma-api-documentation.md`](design/0011-huma-api-documentation.md)
- 已了解知识节点进度：[`design/0012-understood-knowledge-progress.md`](design/0012-understood-knowledge-progress.md)
- PostgreSQL 容器基础设施：[`design/0013-postgresql-container-foundation.md`](design/0013-postgresql-container-foundation.md)
- 实时相机扫描界面：[`design/0014-live-camera-capture.md`](design/0014-live-camera-capture.md)
- PostgreSQL 审核目录与运行时 Repository：[`design/0015-postgresql-reviewed-catalog-repository.md`](design/0015-postgresql-reviewed-catalog-repository.md)
- 关联对象与粗粒度位置推荐 API：[`design/0016-related-objects-and-location-recommendations-api.md`](design/0016-related-objects-and-location-recommendations-api.md)
- 文化元素与景点特定介绍模型：[`design/0017-cultural-elements-and-attraction-introductions.md`](design/0017-cultural-elements-and-attraction-introductions.md)
- Go 文化元素与精确位置查询：[`design/0018-go-cultural-content-query-api.md`](design/0018-go-cultural-content-query-api.md)
- 西湖首批内容与数据库管理台：[`design/0019-west-lake-content-admin.md`](design/0019-west-lake-content-admin.md)
- 数据库首页推荐与相机拍照安全：[`design/0020-database-backed-home-recommendations-and-camera-capture-safety.md`](design/0020-database-backed-home-recommendations-and-camera-capture-safety.md)
- 识别边界前固化图片载荷：[`design/0021-owned-image-data-across-concurrency.md`](design/0021-owned-image-data-across-concurrency.md)
- 新文化内容识别管线：[`design/0022-cultural-content-recognition-pipeline.md`](design/0022-cultural-content-recognition-pipeline.md)
- 相册扫描使用照片记录位置：[`design/0023-photo-recorded-location-for-library-scans.md`](design/0023-photo-recorded-location-for-library-scans.md)
- 识别请求全量审计与最近 100 条管理台：[`design/0024-recognition-request-audit-console.md`](design/0024-recognition-request-audit-console.md)
- 单图显眼框目标标注：[`design/0025-single-image-focus-annotation.md`](design/0025-single-image-focus-annotation.md)
- 从三潭映月扩展西湖文化节点：[`design/0026-west-lake-three-pools-cultural-expansion.md`](design/0026-west-lake-three-pools-cultural-expansion.md)
- 识别结果返回文化知识图谱：[`design/0027-recognition-knowledge-graph-response.md`](design/0027-recognition-knowledge-graph-response.md)
- 景点候选与文化知识分层：[`design/0028-separate-attraction-candidates-from-cultural-knowledge.md`](design/0028-separate-attraction-candidates-from-cultural-knowledge.md)
- 景点候选去重、真实介绍与独立详情导航：[`design/0032-distinct-attraction-candidates-and-detail-navigation.md`](design/0032-distinct-attraction-candidates-and-detail-navigation.md)
