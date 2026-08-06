# 0018 AI 讲解持久存储与显式重新生成

## 背景

`design/0014` 将 AI 文化讲解放入 `Library/Caches`，并把用户知识状态、模型与 prompt schema 纳入缓存键。这适合可再生成的缓存，但不符合“讲解是用户已经获得的内容”这一产品语义：

- iOS 可以自行清理 Caches。
- 设置页清理缓存会删除讲解。
- 首次讲解后的知识进度变化可能改变缓存键，导致同一对象再次请求。
- prompt 或模型版本变化会让已经生成的讲解自动失效。

## 决策

### 存储位置与生命周期

- 以 `CultureExplanationStore` actor 持久化完整 `PersonalizedExplanation`。
- 文件位于 `Application Support/CultureLens/Explanations/explanations-v1.json`。
- 不设置条数淘汰，不参与系统/设置页的网络缓存清理。
- 只有收到 LLM finished 事件的完整讲解才写入；断流 partial 内容仍只保留在当前页面。

### 稳定身份

存储键只包含：

- `RecognitionResult.id`
- 展示对象 id 与可选知识包元素 id
- 地点上下文
- 目标语言

用户知识状态、模型版本和 prompt 版本不进入键。它们是生成当时的上下文，不应让已经保存的内容自动消失。用户希望采用最新上下文时，使用显式“重新生成”。中英文讲解分别保存。

### 重新生成交互

- `PersonalizedExplanationView` 的标题行右上角显示 `arrow.clockwise` 按钮，VoiceOver 名称为“重新生成”。
- 重新生成期间继续显示旧讲解，右上角按钮替换为小型进度指示，不回退骨架屏。
- 新讲解完整返回并成功解析后，原键覆盖保存并原位替换 UI。
- 网络失败时恢复旧讲解并提示“已保留原讲解”。
- 本地写入失败时仍展示本次生成结果，但明确提示未能保存。

### 清理缓存

设置页“清理缓存”只删除在线图片和即时译文缓存。AI 讲解、扫描历史、问答记录、文化图谱、轨迹与知识资源包均不受影响。

## 迁移边界

旧 `Library/Caches/CultureLens/LLM/explanations-v2.json` 的键包含无法从条目反推的个性化请求上下文，无法安全映射为新的稳定内容身份，因此不迁移。它仍属于可由系统回收的旧缓存，不作为正式记录。

## 验证

- Store 跨实例读取测试，确认落盘后可在新 actor 实例恢复。
- 稳定键测试，确认同一对象输入得到相同键、不同语言得到不同键。
- 图片缓存落盘/清理测试继续保留。
- Simulator 定向运行 `NetworkCacheTests`，并完成通用 iOS build / `build-for-testing`。
