# CultureLens agents 工作区

CultureLens 是 CultureLens 的端侧化版本：知识库与 LLM prompt 拼接逻辑从 Go 后端搬到 iOS 端侧，App 只依赖两个外部资源——Cloudflare AI Gateway（LLM）与 Cloudflare R2（图片 URL）。

## 目录约定

- `PROJECT.md`：产品定位、端侧架构与约束。
- `STATUS.md`：当前阶段、已完成事项、下一步和阻塞项。
- `design/`：架构与数据流设计文档。
- `APP_STORE.md`：App Store Connect 上架与 ODR 分包分发要点。

## 工作规则

沿用 CultureLens/agents 的规则：改架构先写 design 文档，实现后更新 STATUS.md，未确认内容标记"待定"。
