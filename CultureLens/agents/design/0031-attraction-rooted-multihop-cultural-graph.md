# 0031 景点主文化节点与多跳文化图谱

- 日期：2026-08-02
- 状态：已确认、已实施、已部署
- 影响范围：西湖内容包、Go 识别 Repository/响应、三潭印月知识图谱
- 前置设计：`0017-cultural-elements-and-attraction-introductions.md`、`0026-west-lake-three-pools-cultural-expansion.md`、`0027-recognition-knowledge-graph-response.md`、`0030-attraction-primary-and-scan-result-cleanup.md`

## 问题

现有表已经通过 `attraction_cultural_introductions.attraction_key → cultural_element_key` 保存景点与多个文化元素的绑定。问题发生在读取层：识别模型返回 `attraction_key` 后，后端按景点去重时只保留排序最靠前介绍的 `cultural_element_key`。三潭印月因此会把“西湖月景与倒影营造”当作图谱中心，只返回它到“西湖十景的观看方式”的一条边，再把标题覆盖为“三潭印月”。标题和真实图谱根节点发生错配，其余已经绑定的元素也在去重时丢失。

此外，识别响应只查询一跳，无法返回“三潭印月 → 三潭石塔 → 苏轼治湖 → 苏堤春晓”这样的连续路径。

## 决策

1. 不修改 PostgreSQL schema。继续使用现有 `attractions`、`attraction_cultural_introductions`、`cultural_elements` 和 `cultural_element_relations`。
2. Repository 聚合同一景点全部现场介绍绑定的文化元素，不再在按景点去重时丢弃后续绑定。
3. 如果文化元素中存在与 `attraction_key` 同 key 的节点，就把它作为景点图谱中心；否则兼容回退到排序第一条现场介绍的元素。三潭印月使用已有 `three-pools-mirroring-moon` 同 key 元素作为中心。
4. 景点全部直接绑定元素都加入中心图谱；显式文化关系再从中心执行有界广度遍历，默认最多 3 跳、32 个概念节点。
5. 现有关系表没有关系类型和关系说明，本轮继续保守映射为通用“解释”，不为 UI 标签扩表。
6. 补充现场对象、三潭石塔与苏轼治湖、园林空间、月景、十景、雷峰塔/白蛇传、南屏晚钟等节点和显式关系。

## 数据边界

- “印月”光影保留多种历史解释，文案明确为不同说法，不包装成唯一物理结论。
- 北宋石塔传统与今天的小瀛洲园林格局分开叙述。
- 历史建筑、民间传说和当代重建分别表述。
- 本轮沿用现有富文本和来源线索机制，不新增未经审核的自动推断。

## 兼容与回滚

- 无 migration，生产 schema 保持 v6。
- App JSON 契约不改字段名，旧客户端仍接收 `concepts` / `relations`。
- 内容包继续幂等 upsert，不执行删除；回滚后端镜像即可恢复旧读取逻辑。

## 验证

- 内容包结构校验覆盖节点、景点介绍绑定和关系端点。
- PostgreSQL 集成测试覆盖景点主节点读取及 3 跳图谱。
- Pipeline/Repository 测试确认同 key 中心节点不再受介绍排序影响、全部景点绑定保留并返回多跳边。
- `go test ./...`、`go vet ./...`、内容包 validate 和 iOS 编译检查通过后再考虑部署。

## 部署结果

- 2026-08-02 使用原有 schema v6 的临时 PostgreSQL 18.4 验证内容包导入成功：34 个文化元素、7 个景点、44 条关系、19 条景点介绍；三潭印月保留 10 个直接绑定。未新增或执行 migration。
- 生产变更前备份为 `/opt/culturelens/backups/culturelens-pre-three-pools-bindings-20260802T134927.dump`，权限 `root:root/0600`，SHA-256 为 `99667ce7c958e5d586d4c9f5dd13d388378ae90faa87824ea96484cac98789cc`，且通过 `pg_restore --list` 校验。
- 内容包以 `culturelens_editor` 最小权限账号幂等导入生产；生产 schema 保持 v6，最终计数为 34/7/44/19，三潭印月直接绑定为 10。
- linux/amd64 生产镜像为 `20260802-three-pools-bindings-amd64`，镜像 ID `sha256:f0dcac888ca52669d3369ffa9b556e6b50a786ebfb5fafec48e50da8dcea081f`，registry digest `sha256:da7118b377d9ed50bda37cc956853d92a70ecc956c77e101e3fd836cb622b7d5`。
- 新容器保持 8080、`unless-stopped` 与 `bridge + culturelens-db` 双网络，healthy 且 restartCount=0；旧容器保留为 `culturelens-rollback-pre-three-pools-bindings-20260802`，restart policy 为 `no`。
- 公网 `/health` 返回 200；公开文化元素接口返回三潭印月中心节点及 12 个直接关联元素。
