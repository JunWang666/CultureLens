# CultureLens 丝绸之路知识库

这里保存“采集语料库”，不是自动发布到识别服务的审核目录。

## 构建

```bash
go run ./cmd/knowledge sync
go run ./cmd/knowledge validate \
  -file knowledge/bundles/silk-road.v1.json
go run ./cmd/knowledge query \
  -file knowledge/bundles/silk-road.v1.json \
  -q 丝绸
```

`sync` 从 IIDOS 当前链接的丝绸之路数字博物馆 SROM 公开藏品接口读取
结构化元数据，并与 `seeds/wikipedia.zh.v1.json` 中固定到具体修订版本的中文
维基百科主题合并。输出文件使用稳定 UUID、稳定排序、来源 URL 和内容指纹。

## 数据权利边界

### SROM / IIDOS

- 只保存名称、材质、年代、地区、收藏机构、题材、尺寸等事实型元数据。
- 不保存接口中的长篇 HTML 描述。
- 不下载、不打包、不重新分发远端图片。
- 图片 URL 仅用于定位来源；逐项使用前仍需确认并取得授权。
- 站点未在公开接口中提供可再分发许可，因此知识库不会为其记录虚构 license。

### 中文维基百科

- 种子摘要依据指定 `oldid` 的条目内容压缩改写。
- 记录保留条目固定修订 URL、修订号、访问时间、贡献者署名入口和
  [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)。
- `modified` 始终为 `true`；再发布这些摘要或衍生内容时仍需保留署名和相同方式共享要求。
- 维基共享资源中的图片有各自许可，本知识库没有采集这些图片。

## 审核边界

同步生成的所有记录都是 `imported`。它们可用于本地检索、来源核查和人工审核，但
不会进入 `internal/knowledge/data/objects.v1.json`。人工确认名称、内容、来源和使用权
后，才能通过后续发布流程成为 `reviewed` 识别候选。

详细决策见 iOS 仓库
`agents/design/0009-silk-road-source-ingestion-and-knowledge-bundle.md`。
