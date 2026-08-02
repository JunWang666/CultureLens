# CultureLens STATUS

## 当前阶段

端侧化改造已完成并通过单元测试；待真机验证与 App Store 上架准备。

## 已完成

- 2026-08-02 工程从 CultureLens 复制重命名（bundle ID `com.junwei.CultureLens`，SwiftData 配置 `CultureLensHistoryV1`），模拟器构建通过。
- 2026-08-02 端侧识别管线移植完成：`Services/Knowledge`（KnowledgeStore / Haversine / 候选挑选 / BFS 图谱）、`Services/LLM`（PromptAssembler / LLMGatewayClient，CF AI Gateway `dynamic/culturelens`）、`Services/Recognition`（ResponseMapper / OnDeviceRecognitionService / UUIDv5）。`RemoteRecognitionService`、`CultureLensAPI` 已删除；`CultureContentService` 改本地查询。
- 2026-08-02 知识包落地：`Resources/KnowledgePack/`（西湖包 34 元素 / 7 景点 / 44 关系 / 19 介绍 + manifest），后端新增 `cmd/exportknowledge` 导出工具；ODR tag `knowledge-base` 接线完成（initial-install 随首装下发，为将来按需拆包预留），`KnowledgePackLoader` ODR 优先、内置 fallback 兜底。
- 2026-08-02 富文本支持 image block（R2 URL），后端 `contentadmin` 校验同步放宽；`RichTextBlocksView` 渲染。
- 2026-08-02 CF AI Gateway 实测：text / json_schema / 多模态 image_url 均可用（实际模型 gemini-3.6-flash）；模拟器 E2E 测试（`OnDeviceRecognitionE2ETests`，env `CULTURELENS_E2E_IMAGE` 门控）。
- 单元测试与 UI 测试全绿（含 Haversine、候选优先级、UUIDv5 与 Go 一致性、bundle 解码、image block 等）；模拟器 E2E 经真实网关识别三潭印月测试图，返回 `attraction`（model=gemini-3.6-flash）。
- 2026-08-02 Release 归档（免签名）验证通过：`Products/OnDemandResources/` 中生成 `knowledge-base` asset pack，App 主包内含 fallback 副本与 prompt 资源。正式上传需先在 Xcode 登录 Apple ID（当前机器无账户，自动签名无法生成 provisioning profile）。

## 下一步

1. 真机验证：扫描识别三态、附近推荐、ODR 下载路径（TestFlight 最佳）、离线 fallback。
2. 归档 + 导出 ipa，确认 OnDemandResources 拆分；按 `APP_STORE.md` 检查单准备上架。
3. R2 bucket 开通公开读并补内容图片 URL；admin 侧维护含 image block 的介绍。
4. 补 App 图标与隐私清单（照片经 AI Gateway 发 Google 需如实声明）。

## 已知取舍与阻塞

- LLM key 硬编码，需在 Cloudflare 配限额告警（用户已确认接受）。
- ODR 不能独立于 App 版本热更；多地域拆分待内容增长后执行。
- 丝绸之路包（5.1MB）未导入，本期仅西湖包。
- `AskCultureView` 仍是占位。
