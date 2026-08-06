# 知识包编写指南

本指南规定 CultureLens 知识包（`Resources/KnowledgePack*/` sidecar 目录）的内容设计原则与数据编写规范。目标是让图谱成为**有明确流向和掌握顺序的学习路径**，而不是概念共现网。

## 一、内容设计三原则

### 1. 实体即景点

任何实体的东西——塔、桥、堤、寺、墓、玉器、瓷器、书画、长城、运河——都是**景点（attraction）**，因为只有景点可以被扫描出来。景点是用户进入知识图谱的唯一入口。

由此得到节点分层：

- **景点层**：实体节点。必须在 `attractions[]` 里有同名同 key 的记录，必须配 `introductions[]`（带坐标的现场讲解）。
- **知识层**：抽象概念节点——朝代、制度、审美、技法、人物、传说。它们不可扫描，只能通过边从景点抵达。

一个节点不能既是实体又是抽象概念。像"雷峰塔与雷峰夕照"这种把实体（塔）和观看方式（夕照）揉在一起的节点要拆开：`leifeng-pagoda`（景点）+ `leifeng-evening-glow`（审美知识），用边连接。

### 2. 边只表达两种流向

边的唯一职责是回答外国用户的两个问题：

- **前置知识**："看懂它，我需要先知道什么？"（往基础走）
- **扩展知识**："看完之后，还能延伸到什么？"（往深处、广处走）

每条边必须有明确方向（见第三节的方向语义表）。不允许为了"让图连通"加成对的双向互链——对称边会让任何遍历算法失去方向感。

### 3. 外国人视角

假设用户**完全不了解中国文化**：不知道什么是朝代、没听过中秋节、分不清塔和庙、不知道"团圆"意味着什么。由此：

- 任何文化负载词（团圆、忠烈、科举、风水、礼制、四字景名……）要么有自己的节点，要么在 introduction 里就地用一句话解释，不能默认读者懂。
- 侧重**文化和历史**：讲"为什么是这样、背后的人和时代"，而不是建筑参数和导游词。
- 每个包必须带 `locales.en` 覆盖层（见第五节），英文名和英文正文是必填，不是锦上添花。

## 二、图谱的组织结构：三层地基

一个健康的包（或包群）应该能排出这样的掌握顺序：

```
地基层    朝代脉络、中华文明、儒释道、重大制度（科举、汉字……）
          —— 由 chinese-history 包提供，是全库共享地基
区域层    本地文化总览、历史分期、地理格局（西湖文化景观、良渚文化总览）
景点层    具体可扫描实体（三潭印月、玉琮王、剩山图）
```

前置边（`理解前先懂`）的整体指向必须是 **景点层 → 区域层 → 地基层**，形成无环的学习阶梯。跨包的前置链是这个产品的核心价值：用户在西湖扫了"南宋临安"，应该能一路走到"宋朝 → 中国历代王朝脉络"。

## 三、数据模型与字段规范

JSON 结构见 `Services/Knowledge/KnowledgePackModels.swift`。运行时 `KnowledgeStore.loadPack` 把目录内 sidecar 合并成完整 `KnowledgePack`，多包再按 key 合并（先到先得），两端元素不存在的边会被丢弃。

### 文件拆分（sidecar）

不要把全部内容塞进一个大 JSON。每个包目录按类型分文件；`pack-manifest.json` 是唯一 manifest，主 JSON 里不要再嵌一份。

| 文件 | 内容 |
|---|---|
| `knowledge-pack.json` | 只留 `version` / `source_language` / `relations` |
| `elements-sight.json` | 看点元素（`contentRole: 看点`）+ `attractions` 列表 |
| `elements-history.json` | 文化历史元素（`contentRole: 文化历史`） |
| `introductions.json` | 现场介绍 |
| `themes.json` | 探索主题 |
| `locales-<lang>.json` | 每种语言一个覆盖层（如 `locales-en.json`） |
| `pack-manifest.json` | 版本、记录数、`sha256`、文件列表 |

加载时合并 sidecar 成完整包。按 `contentRole` 筛选：识别 catalog / 无景点填充 → 只收「看点」；景点绑定的介绍仍可引用「文化历史」；开放问答兜底可优先文化历史。

### 顶层字段（合并后的逻辑模型）

| 字段 | 说明 |
|---|---|
| `version` | 包版本，如 `hangzhou-west-lake-v5`。改内容必须升版本号，并同步 `pack-manifest.json`。 |
| `source_language` | BCP-47，默认 `zh-Hans`。 |
| `elements[]` | 图谱节点（看点 + 文化历史）。每条带 `contentRole`。 |
| `attractions[]` | 可扫描景点清单，每个 key 必须有对应 element（可跨包）。 |
| `relations[]` | 图谱边（写在主 `knowledge-pack.json`）。 |
| `introductions[]` | 现场讲解记录（绑定景点 + 元素 + 坐标）。 |
| `themes[]` | 主题探索线路，只引用 elementKeys。 |
| `locales` | 翻译覆盖层（由 `locales-*.json` 组装）；`en` 必填。 |

### ContentRole（看点 / 文化历史）

枚举见 `Domain/CultureModels.swift` 的 `ContentRole`：

| 取值 | 含义 | 分类规则 |
|---|---|---|
| `看点` | 有实体、可扫描（景点 / 文物 / 遗址） | 本包 `attractions` 里有同 key |
| `文化历史` | 无实体、抽象知识（朝代、审美、人物、制度等） | 否则 |

`conceptKind` 仍描述文化角色（基础知识 / 历史 / 人物…），与 `contentRole` 正交：玉琮王是「看点」+「基础知识」，宋朝是「文化历史」+「历史」。

### 身份：UUID 主键 + 可选 slug

- 每个 entity（element / attraction / introduction / theme）以 **`id: UUID`** 为运行时主键；可选 `key` 是人类可读 kebab slug，用于编辑与迁移。
- 跨引用一律用 UUID：`relations[].elementId` / `relatedElementId`，`themes[].elementIds`，`introductions[].culturalElementId` / `attractionId`。
- 遗留 JSON 仍可写 `elementKey` / `culturalElementKey` / `elementKeys`；解码时经 `DeterministicID` 铸成与 slug 对应的 UUIDv5。
- **attraction 与其绑定元素可共用 slug**，但 UUID 命名空间不同（`culturalElement` vs `attraction`）。
- slug / `key` 一旦发布尽量不要改（已有进度行会按 UUIDv5(slug) 对齐）；新内容以 pack 内显式 `id` 为准。
- 当前包版本：西湖 `hangzhou-west-lake-v6`、中国历史 `chinese-history-v5`、良渚 `liangzhu-v5`、浙博 `zhejiang-museum-v6`。

### key / slug 规范

- 小写 kebab-case 英文，描述实体本身而非视角：`leifeng-pagoda` ✓，`leifeng-pagoda-and-evening-glow` ✗（那是两个节点）。
- **同一实体全库共用一个 slug**。玉琮王在良渚包和浙博包必须是同一个 `jade-cong-wang`，靠合并去重；不允许出现 `jade-cong-wang` / `liangzhu-cong-wang` 两份。新增节点前先在全部包里搜一遍同名实体。
- **attraction 与其绑定元素共用 slug 是设计特性**（景点就是图谱里的实体节点）。代码侧靠命名空间 UUID 消歧（元素 `culturalElement` / 景点 `attraction` / 地图点 `attractionPoint`，见 `agents/PROJECT.md`「身份模型」），不要因为"key 撞名"给景点另造 key。

### elements（看点 / 文化历史 sidecar）

```json
{
  "id": "…-uuidv5-from-slug…",
  "key": "three-pools-mirroring-moon",
  "name": "三潭印月",
  "contentRole": "看点",
  "conceptKind": "基础知识",
  "introduction": { "schemaVersion": 1, "blocks": [ … ] },
  "sources": [ { "title": "…", "publisher": "…", "url": "…" } ]
}
```

- `contentRole` 必填，取值 `看点` / `文化历史`。
- `conceptKind` 必填，取值见 `Domain/CultureModels.swift` 的 `ConceptKind`（9 种）。**实体节点按其文化角色归类**：塔/堤/桥是"基础知识"，遗址格局是"地域"，水利工程是"功能"——不要用"审美"装长城、用"技法"装玉琮王。"相似对象"是边（`相似于`）的语义，一般不作节点身份。
- `introduction` 用 RichTextDocument（paragraph / image blocks）。写法要求：
  - 第一段永远是"你眼前看到的是什么"——用户正站在它面前。
  - 中间讲历史与人：谁造的、哪个朝代、为什么、后来发生了什么。
  - 结尾给一条延伸线索（对应图里的扩展边）。
  - 文化负载词就地一句话解释，或链接到对应节点。
- `sources` 至少一条可信外部来源（Wikipedia / UNESCO / 政府网）。

### attractions[] 与 introductions[]

- **每个景点 key 必须同时存在于 `elements[]`**——扫描识别命中 attraction 后要能落进图谱节点。西湖包 19/23 景点无对应节点的现状属于缺陷，新包不允许。
- `introductions[]` 的 `attractionId` / `culturalElementId`（或遗留 `attractionKey` / `culturalElementKey`）对景点节点指向同一实体；`latitude/longitude` 必填，`coordinateSourceUrl` 注明坐标出处。
- 现场介绍可把 `culturalElementId` 指到文化历史节点（例如展厅景点绑定「施昕更发现」），识别 catalog 仍只收看点。

### relations[]

```json
{
  "elementId": "…",
  "relatedElementId": "…",
  "kind": "理解前先懂",
  "explanation": "先认识塔身圆孔，才能理解月光、塔灯与水面如何共同「印月」。"
}
```

- 也可用遗留 `elementKey` / `relatedElementKey`（解码铸 UUIDv5）。
- `kind` 与 `explanation` **必填**，缺 kind 的边渲染层没有方向可画，等于废边。
- `explanation` 的方向必须与边的方向一致：读作「起点 （kind） 终点」，解释里先出现的概念应是边的起点一侧。

**12 种 kind 的方向语义**（起点 = A，终点 = B）：

| kind | 读法 | 方向规则 | 典型场景 |
|---|---|---|---|
| 理解前先懂 | A 是 B 的前置 | A 更基础 | 圆孔 → 印月原理；宋朝 → 南宋临安 |
| 解释 | B 解释 A 的由来 | B 是原因/语境，A 是现象 | 北宋三潭 → 苏轼治湖；雷峰塔 → 《白蛇传》 |
| 产生于 | A 产生于 B | A 晚于/源于 B | 苏堤春晓 → 苏轼治湖 |
| 受到影响 | A 受到 B 影响 | B 更早/更上游 | 龙泉窑 → 越窑 |
| 组成 | B 是 A 的组成部分 | A 大 B 小（整体 → 部分） | 三潭印月 → 三座石塔；十景体系 → 苏堤春晓 |
| 位于 | A 位于 B | A 是实体/子区域 | 灵隐寺 → 西湖佛教文化圈 |
| 用于 | A 用于 B | A 是工具/手段 | 堤岸水利 → 十景游赏 |
| 制作采用 | A 制作采用 B | A 是成品，B 是工艺/材料 | 玉琮 → 阴线雕琢 |
| 体现 | A 体现 B | A 是实例，B 是抽象观念 | 玉琮王 → 琮的礼制 |
| 象征 | A 象征 B | A 是符号，B 是意义 | 三潭灯月 → 团圆意象 |
| 受规制于 | A 受规制于 B | B 是制度/体系 | 十景 → 四字景名规则 |
| 相似于 | A 与 B 相似 | 横向，可只写单向 | 平湖秋月 ↔ 三潭印月（选一条即可） |

方向审计要点：`受到影响` 的箭头指向**更早/更上游的一方**；`理解前先懂` 全库统一为「A 是 B 的前置」（旧浙博包 `liangzhu-cong-wang → cong-ritual-jade` 曾是反例，v4 重构已清除）。

- 不成对互链。如果 A→B（体现）成立而 B→A（解释）也说得通，**只留信息量大的一条**；双向关系用一条 `相似于` 表达。
- 前置边不得成环：沿 `理解前先懂` 从任意节点往上走，必须能在"地基层"终止。

### themes[]

- 每条主题线是一条策展路径（如"月与倒影""玉与礼制"），`elementKeys` 按推荐游览/学习顺序排列，`minContacted` 设为 keys 数量的 60%–80%。
- 主题线里至少一半节点应是看点（可扫描），纯知识主题用户无法开始。

### locales-en.json（必填）

```json
{
  "elements": {
    "jade-cong-wang": {
      "name": "King Jade Cong",
      "introduction": { "schemaVersion": 1, "blocks": [ … ] }
    }
  },
  "attractions": { "…": { "name": "…" } },
  "introductions": { "…": { "name": "…", "introduction": { … } } }
}
```

- `elements` 必须覆盖**每一个** element 的 `name`；`introduction` 英译对区域包（良渚/浙博/历史）为必填，西湖包目前只提供名称，正文由运行时 LLM 翻译兜底（`KnowledgeTranslationService`，设计见 PROJECT.md「多语言」）。
- 英文不是逐字翻译，是给英语读者重写的版本——拼音首次出现要配释义（Cong, a jade tube with a circular inner bore and square outer body）。

## 四、历史与文化内容的编写要点

1. **朝代是锚点**。任何超过一百年前的内容，introduction 里要点明朝代并确保图中有通往该朝代节点的边；朝代节点统一由 chinese-history 包维护，其他包只做引用（共用 key）。
2. **人物要挂在时代上**。人物节点的第一条前置边指向其朝代或历史事件（岳飞 → 靖康之变），避免人物悬浮。
3. **讲因果，不讲罗列**。"苏轼为什么修堤"比"堤长 2.8 公里"重要；数据细节进 introduction 正文，不进节点结构。
4. **区分史实与传说**。传说（白蛇传、济公）是独立的人物/文化节点，用 `象征` 边连到实体景点，explanation 里点明"文学再创作 vs 历史遗址"。
5. **宗教与哲学用生活化入口**。佛教、道教、儒家先落到具体可见物（塔、钟声、碑刻），再上行到思想节点；不要从定义讲起。
6. ** comparisons 用横向边**。与国外读者熟悉的事物类比（如大运河 vs 巴拿马运河）写进 introduction 正文，图里用 `相似于` 连接国内同类对象即可。

## 五、提交前检查清单

- [ ] 每个 attraction 的 key 都存在于 elements（景点可落图；可跨包）
- [ ] 每个 element 有正确的 `contentRole`（attractions 同 key → 看点，否则 → 文化历史）
- [ ] 内容按 sidecar 分文件，主 JSON 不含 elements/attractions/introductions/themes/locales
- [ ] 每条 relation 都有 kind 和 explanation，且方向与上表一致
- [ ] 无成对互链；`理解前先懂` 无环、最终落到地基层
- [ ] 无跨包重复实体（全库搜 key 与中文名）
- [ ] 每个 element 有 `locales-en.json` 名称覆盖（区域包还需 introduction 英译）
- [ ] 版本号已升级、`pack-manifest.json` 已同步
- [ ] `AbstractionAxisTests` / `InternationalizationTests` 通过

快速自检（在仓库根目录；按**合并宇宙**校验——跨包边与跨包景点引用是设计特性）：

```bash
python3 - <<'EOF'
import json, glob, sys, os
ok = True
dirs = [d for d in glob.glob('CultureLens/CultureLens/Resources/KnowledgePack*')
        if os.path.isdir(d)]

def load_pack(d):
    main = json.load(open(f'{d}/knowledge-pack.json'))
    sight = json.load(open(f'{d}/elements-sight.json'))
    hist = json.load(open(f'{d}/elements-history.json'))
    intros = json.load(open(f'{d}/introductions.json'))
    themes = json.load(open(f'{d}/themes.json'))
    en_path = f'{d}/locales-en.json'
    en = json.load(open(en_path)) if os.path.exists(en_path) else {}
    elements = sight.get('elements', []) + hist.get('elements', [])
    return {
        'version': main['version'],
        'elements': elements,
        'attractions': sight.get('attractions', []),
        'relations': main.get('relations', []),
        'introductions': intros.get('introductions', []),
        'themes': themes.get('themes', []),
        'locales': {'en': en},
    }

packs = [load_pack(d) for d in dirs]
elems = {}
for d in packs:
    for e in d['elements']:
        if e['key'] in elems:
            ok = False; print(f"跨包重复元素 {e['key']}")
        elems[e['key']] = d['version']
        role = e.get('contentRole')
        in_attr = e['key'] in {a['key'] for a in d['attractions']}
        expect = '看点' if in_attr else '文化历史'
        if role != expect:
            ok = False; print(f"{d['version']}: {e['key']} contentRole={role} 期望 {expect}")
attrs = {a['key'] for d in packs for a in d['attractions']}
seen_pairs = set()
for d in packs:
    for a in d['attractions']:
        if a['key'] not in elems:
            ok = False; print(f"{d['version']}: 景点无对应节点 {a['key']}")
    for r in d['relations']:
        if not r.get('kind') or not r.get('explanation'):
            ok = False; print(f"{d['version']}: 缺 kind/explanation 的边 {r['elementKey']} -> {r['relatedElementKey']}")
        for k in (r['elementKey'], r['relatedElementKey']):
            if k not in elems:
                ok = False; print(f"{d['version']}: 边引用了不存在的元素 {k}")
        pair = tuple(sorted((r['elementKey'], r['relatedElementKey'])))
        if pair in seen_pairs:
            ok = False; print(f"{d['version']}: 成对互链 {pair}")
        seen_pairs.add(pair)
    for i in d['introductions']:
        if i['culturalElementKey'] not in elems or i['attractionKey'] not in attrs:
            ok = False; print(f"{d['version']}: 讲解记录引用悬空 {i['key']}")
    en = (d.get('locales') or {}).get('en', {}).get('elements', {})
    no_en = [e['key'] for e in d['elements'] if e['key'] not in en]
    if no_en:
        print(f"{d['version']}: {len(no_en)} 个元素缺英文名称覆盖")
sys.exit(0 if ok else 1)
EOF
```

## 六、v5 sidecar 基线（2026-08）

四个源包已按本指南拆成 sidecar，并给每条 element 打上 `contentRole`（西湖 v5 / 良渚 v4 / 浙博 v5 / 历史 v4）。节点与边计数与上一轮实体化重构一致：

- 节点：西湖 70（看点 23 / 文化历史 47）/ 良渚 25（9 / 16）/ 浙博 35（16 / 19）/ 历史 45（2 / 43）。
- 边全部有 kind + explanation、单向、无对称对；跨包边统一指向历史包地基（朝代、文化概念）。
- 玉琮王 canonical key 为良渚包 `jade-cong-wang`；河姆渡为浙博包 `hemudu-culture`；施昕更为良渚包 `shi-xingeng-discovery`。新内容引用这些 key，不要再建同义节点。
- 浙博包对跨主题展品（如 `jade-cong-wang`）须自带同 key / 同 UUID 的看点元素与之江展陈介绍；合并时良渚正文优先，单装浙博时识别候选仍完整。西湖包 `locales.en` 目前只有名称级覆盖；补正文英译是已知的后续工作。

**发行形态（2026-08 更新）**：App 只打一个 ODR 知识包 `Resources/KnowledgePack/`（tag `knowledge-base`，version `culturelens-v1`）。分源编辑目录在 `agents/knowledge-sources/`；改完后运行 `python3 scripts/merge_knowledge_packs.py` 再构建。
