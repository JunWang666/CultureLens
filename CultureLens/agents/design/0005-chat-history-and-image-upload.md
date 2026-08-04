# 0005 文化问答：历史会话与图片上传

- 状态：已实现（2026-08-03）

## 背景

文化问答与对象追问已支持多轮流式回答，但会话仅存在内存中，离开页面即丢失；作曲器左侧「+」也只是快捷填入建议，无法附现场照片。识别管线已具备多模态 `image_url`，问答侧尚未复用。

## 产品语义

- 每次进入问答默认新对话；工具栏提供「新对话」与「历史对话」。
- 历史按作用域隔离：首页自由问答与某对象追问各自列表；可删除单条会话。
- 完成一轮问答后自动持久化；标题取自首条用户问题（或「图片提问」）。
- 「+」打开附件菜单，可从相册选图；仅图片也可发送。气泡与作曲器上方展示缩略图。
- 发给模型时：当前轮携带 JPEG（归一化后）；历史轮若曾附图片，以文字标注「（附图片）」避免反复上传大图。

## 数据与接口

1. `ChatConversationRecord` JSON 列表：会话元数据 + `[PersistedChatMessage]`（文件：Application Support `CultureLens/ChatHistory/conversations.json`）。不走 SwiftData，避免与扫描历史 store 混用导致的 `SIGABRT`。
2. `ChatMediaStore`：Application Support `CultureLens/Chats/*.jpg`。
3. `ChatHistoryStore`：按 `objectID?` 查询 / upsert / 删除（删会话时顺带清图片）。
4. `ChatTurn` 增加可选 `ImageAttachment`；`asAPIMessage()` 产出 OpenAI 多模态 `content` 数组。
5. `CultureChatService.streamAsk` 增加 `imageJPEG`；prompt `ask.txt` 补充图片关联约束。

## 验证

- 单元测试：多模态 `ChatTurn` 编码、会话标题生成、消息快照往返。
- 真机：相册选图 → 流式回答 → 退出再进历史恢复；对象追问与首页问答历史互不串扰。
