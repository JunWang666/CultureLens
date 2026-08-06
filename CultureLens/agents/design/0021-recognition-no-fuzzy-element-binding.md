# 0021 — 识别绑定：禁止空 key 模糊回填

## 背景

模型有时返回空的 `cultural_element_key`，却在 `canonical_name` / `summary` / `rationale` 里写出候选相关字样。旧管线用名称子串与正文 `fromText` 猜测绑定（例如「玉琮」→「玉琮王」，或摘要里的「河姆渡」绑到河姆渡节点），在候选缺失时会产生错误绑定。

## 决策

1. **空 key = 未绑定**。`RecognitionResponseMapper` 不再按名称或 summary/rationale 文本回填 `cultural_element_key`（主结论与 alternatives 相同）。
2. **有 key 时仍走短 ID 还原**。`OnDeviceRecognitionService` 经 `LLMIDSession` 把 prompt 短数字 id 还原为 pack UUID；未知 id 清空后保持未绑定，不再触发目录名猜测。
3. **校验仍允许空 key**；有 key 时仍要求与候选 id 匹配，且名称与候选兼容（含子串兼容，仅用于已声明 key 的校验）。

## 非目标

- 不放宽 prompt 候选集合；模型只能引用本轮候选里的短 id。
- 不改变景点 `attraction_key` 的短 ID 还原规则。
