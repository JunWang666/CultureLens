# 0005 多语言（i18n）与知识库译文回退

- 状态：已实现（基础设施，2026-08-03）

## 背景

CultureLens 原为简体中文单语：UI 字符串硬编码、知识包仅为中文、识别 / 讲解 / 追问 system prompt 强制「所有文字使用简体中文」。需要：

1. 固定界面文案打进软件包（String Catalog）
2. 知识包预留多语言 overlay，当前译文内容暂缺
3. 缺译文时用 `dynamic/chat` 即时翻译知识库展示文本
4. 原有 LLM 路径（识别 / 讲解 / 问答）直接按目标语言生成，而不是先出中文再翻

## 方案

### UI 固化文案

- `Localizable.xcstrings`（`sourceLanguage = zh-Hans`，含 `en`）
- SwiftUI `Text("…")` / `String(localized:)` 随 `\.locale` 切换
- 「我的」页增加语言偏好：`跟随系统` / `简体中文` / `English`（`AppLanguageStore`）

### LLM 直接输出目标语言

- `PromptLanguagePolicy` 按当前语言改写 bundled prompt 的输出规则与 Markdown 标题
- `PromptAssembler.withLanguage(_:)` 在识别、讲解、追问调用时注入
- `RecognitionInput.localeIdentifier` 接入 `AppLanguageStore`
- category 等 schema 枚举仍用中文机器值；自由文本字段用目标语言
- 引用区解析接受 `引用来源` / `Sources` / `Citations` 等别名

### 知识库多语言（内容暂缺）

知识包 JSON 增加：

```json
{
  "source_language": "zh-Hans",
  "locales": {
    "en": {
      "elements": { "<key>": { "name": "...", "introduction": { ... } } },
      "attractions": { "<key>": { "name": "..." } },
      "introductions": { "<key>": { "name": "...", "introduction": { ... } } }
    }
  }
}
```

关系边仍按 key，与语言无关。当前 `locales` 为空对象。

解析顺序：`locales[lang]` overlay → 否则源语言字段 → UI 展示时由 `KnowledgeTranslationService`（`dynamic/chat`）翻译并缓存。

### 详情页

`LocalizedKnowledgeBlocksView` 在对象 / 概念详情中按上述顺序加载介绍；翻译中显示轻量状态。

## 非目标

- 不把 enum `rawValue` 改成英文（避免破坏已存 SwiftData / 历史快照）
- 不在流式 Markdown 中途做二次全文翻译
- 本期不提供完整英文知识包内容

## 验证

- 单元测试：语言解析、English prompt 注入、英文 Sources 引用解析、locales 编解码、缺 overlay 回退
- 真机：切换 English 后 Tab 文案、识别 rationale、讲解标题、问答与详情翻译回退
