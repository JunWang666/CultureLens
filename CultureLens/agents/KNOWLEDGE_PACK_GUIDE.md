# 知识包编写指南

本指南规定 CultureLens 知识包（`Resources/KnowledgePack*/`）的内容设计原则与数据编写规范。目标是让图谱成为**有明确流向和掌握顺序的学习路径**，而不是概念共现网。

## 文件布局（sidecar-first）

每个包目录拆成多个 JSON，运行时由 `KnowledgeStore.discoverPacks` 合并：

| 文件 | 内容 |
|---|---|
| `knowledge-pack.json` | `version` / `source_language` / `relations` |
| `elements-sight.json` | 看点元素（`contentRole: 看点`）+ `attractions` 看点列表 |
| `elements-history.json` | 文化历史元素（`contentRole: 文化历史`） |
| `introductions.json` | 现场讲解（坐标） |
| `themes.json` | 探索主题 |
| `locales-<tag>.json` | 每种语言一份 overlay（如 `locales-en.json`） |
| `pack-manifest.json` | 计数与 sha256（唯一 manifest） |

`ContentRole` 与节点分层一一对应：本包 `attractions[]` 里有同 key 的 element → **看点**；其余 element → **文化历史**。识别 catalog / 无景点 fill 只收看点；景点绑定的介绍仍可引用文化历史节点。

## 一、内容设计三原则

### 1. 实体即景点

任何实体的东西——塔、桥、堤、寺、墓、玉器、瓷器、书画、长城、运河——都是**景点（attraction）**，因为只有景点可以被扫描出来。景点是用户进入知识图谱的唯一入口。

由此得到节点分层：

- **景点层（看点）**：实体节点。必须在 `attractions[]` 里有同名同 key 的记录，必须配 `introductions[]`（带坐标的现场讲解）。
- **知识层（文化历史）**：抽象概念节点——朝代、制度、审美、技法、人物、传说。它们不可扫描，只能通过边从景点抵达。

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

JSON 结构见 `Services/Knowledge/KnowledgePackModels.swift`，运行时多包按 key 合并（先到先得），两端元素不存在的边会被丢弃。

### 顶层字段

运行时合并后的逻辑模型仍是一张完整 `KnowledgePack`；磁盘上按 sidecar 拆分（见文首「文件布局」）。

| 字段 | 说明 |
|---|---|
| `version` | 包版本，如 `hangzhou-west-lake-v5`。改内容必须升版本号，并同步 `pack-manifest.json`。 |
| `source_language` | BCP-47，默认 `zh-Hans`。 |
| `elements[]` | 图谱节点（看点 + 文化历史）；磁盘上分属 `elements-sight.json` / `elements-history.json`，每条带 `contentRole`。 |
| `attractions[]` | 可扫描景点清单，每个 key 必须有对应 element（可跨包）；磁盘上放在 `elements-sight.json`。 |
| `relations[]` | 图谱边；留在 `knowledge-pack.json`。 |
| `introductions[]` | 现场讲解记录；`introductions.json`。 |
| `themes[]` | 主题探索线路；`themes.json`。 |
| `locales` | 翻译覆盖层；每种语言一个 `locales-<tag>.json`（`en` 必填）。 |

### key 规范

- 小写 kebab-case 英文，描述实体本身而非视角：`leifeng-pagoda` ✓，`leifeng-pagoda-and-evening-glow` ✗（那是两个节点）。
- **同一实体全库共用一个 key**。玉琮王在良渚包和浙博包必须是同一个 `jade-cong-wang`，靠合并去重；不允许出现 `jade-cong-wang` / `liangzhu-cong-wang` 两份。新增节点前先在全部包里搜一遍同名实体。
- **attraction 与其绑定元素共用 key 是设计特性**（景点就是图谱里的实体节点）。代码侧靠命名空间 UUID 消歧（元素 `culturalElement` / 景点 `attraction` / 地图点 `attractionPoint`，见 `agents/PROJECT.md`「身份模型」），不要因为"key 撞名"给景点另造 key。
- key 一旦发布不要改（用户图谱进度、UUIDv5 都按 key 派生）。

### elements[]

```json
{
  "key": "three-pools-mirroring-moon",
  "name": "三潭印月",
  "conceptKind": "基础知识",
  "contentRole": "看点",
  "introduction": { "schemaVersion": 1, "blocks": [ … ] },
  "sources": [ { "title": "…", "publisher": "…", "url": "…" } ]
}
```

- `contentRole` 必填：`看点` 或 `文化历史`（与是否出现在 `attractions[]` 一致）。
- `conceptKind` 必填，取值见 `Domain/CultureModels.swift` 的 `ConceptKind`（9 种）。**实体节点按其文化角色归类**：塔/堤/桥是"基础知识"，遗址格局是"地域"，水利工程是"功能"——不要用"审美"装长城、用"技法"装玉琮王。"相似对象"是边（`相似于`）的语义，一般不作节点身份。
- `introduction` 用 RichTextDocument（paragraph / image blocks）。写法要求：
  - 第一段永远是"你眼前看到的是什么"——用户正站在它面前。
  - 中间讲历史与人：谁造的、哪个朝代、为什么、后来发生了什么。
  - 结尾给一条延伸线索（对应图里的扩展边）。
  - 文化负载词就地一句话解释，或链接到对应节点。
- `sources` 至少一条可信外部来源（Wikipedia / UNESCO / 政府网）。

### attractions[] 与 introductions[]

- **每个景点 key 必须同时存在于 `elements[]`**——扫描识别命中 attraction 后要能落进图谱节点。西湖包 19/23 景点无对应节点的现状属于缺陷，新包不允许。
- `introductions[]` 的 `attractionKey` 与 `culturalElementKey` 对景点节点填同一个 key；`latitude/longitude` 必填，`coordinateSourceUrl` 注明坐标出处。

### relations[]

```json
{
  "elementKey": "three-pools-round-openings",
  "relatedElementKey": "three-pools-light-mechanism",
  "kind": "理解前先懂",
  "explanation": "先认识塔身圆孔，才能理解月光、塔灯与水面如何共同「印月」。"
}
```

- `kind` 与 `explanation` **必填**，缺 kind 的边渲染层没有方向可画，等于废边。
- `explanation` 的方向必须与边的方向一致：读作「`elementKey` （kind） `relatedElementKey`」，解释里先出现的概念应是边的起点一侧。

**12 种 kind 的方向语义**（`elementKey` = A，`relatedElementKey` = B）：

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
- 主题线里至少一半节点应是景点（可扫描），纯知识主题用户无法开始。

### locales.en（必填）

```json
"locales": {
  "en": {
    "elements": {
      "jade-cong-wang": {
        "name": "King Jade Cong",
        "introduction": { "schemaVersion": 1, "blocks": [ … ] }
      }
    },
    "attractions": { "…": { "name": "…" } },
    "introductions": { "…": { "name": "…", "introduction": { … } } }
  }
}
```

- `locales.en.elements` 必须覆盖**每一个** element 的 `name`；`introduction` 英译对区域包（良渚/浙博/历史）为必填，西湖包目前只提供名称，正文由运行时 LLM 翻译兜底（`KnowledgeTranslationService`，设计见 PROJECT.md「多语言」）。
- 英文不是逐字翻译，是给英语读者重写的版本——拼音首次出现要配释义（Cong, a jade tube with a circular inner bore and square outer body）。

## 四、历史与文化内容的编写要点

1. **朝代是锚点**。任何超过一百年前的内容，introduction 里要点明朝代并确保图中有通往该朝代节点的边；朝代节点统一由 chinese-history 包维护，其他包只做引用（共用 key）。
2. **人物要挂在时代上**。人物节点的第一条前置边指向其朝代或历史事件（岳飞 → 靖康之变），避免人物悬浮。
3. **讲因果，不讲罗列**。"苏轼为什么修堤"比"堤长 2.8 公里"重要；数据细节进 introduction 正文，不进节点结构。
4. **区分史实与传说**。传说（白蛇传、济公）是独立的人物/文化节点，用 `象征` 边连到实体景点，explanation 里点明"文学再创作 vs 历史遗址"。
5. **宗教与哲学用生活化入口**。佛教、道教、儒家先落到具体可见物（塔、钟声、碑刻），再上行到思想节点；不要从定义讲起。
6. ** comparisons 用横向边**。与国外读者熟悉的事物类比（如大运河 vs 巴拿马运河）写进 introduction 正文，图里用 `相似于` 连接国内同类对象即可。

## 五、提交前检查清单

- [ ] 每个 attraction 的 key 都存在于 elements（景点可落图）
- [ ] 每条 relation 都有 kind 和 explanation，且方向与上表一致
- [ ] 无成对互链；`理解前先懂` 无环、最终落到地基层
- [ ] 无跨包重复实体（全库搜 key 与中文名）
- [ ] 每个 element 有 `locales.en` 名称覆盖（区域包还需 introduction 英译）
- [ ] 版本号已升级、`pack-manifest.json` 已同步
- [ ] `AbstractionAxisTests` / `InternationalizationTests` 通过

快速自检（在仓库根目录；按**合并宇宙**校验——跨包边与跨包景点引用是设计特性）：

```bash
python3 - <<'EOF'
import json, glob, sys
from pathlib import Path
ok = True
dirs = [Path(p) for p in glob.glob('CultureLens/CultureLens/Resources/KnowledgePack*')
        if 'Fallback' not in p]

def load_pack(d: Path):
    main = json.load(open(d/'knowledge-pack.json'))
    sight = json.load(open(d/'elements-sight.json'))
    hist = json.load(open(d/'elements-history.json'))
    intros = json.load(open(d/'introductions.json'))
    themes = json.load(open(d/'themes.json'))
    locales = {}
    for loc in d.glob('locales-*.json'):
        tag = loc.stem.removeprefix('locales-')
        locales[tag] = json.load(open(loc))
    return {
        'version': main['version'],
        'elements': sight['elements'] + hist['elements'],
        'attractions': sight['attractions'],
        'relations': main['relations'],
        'introductions': intros['introductions'],
        'themes': themes['themes'],
        'locales': locales,
    }

packs = [load_pack(d) for d in dirs]
elems = {}
for d in packs:
    for e in d['elements']:
        if e['key'] in elems:
            ok = False; print(f"跨包重复元素 {e['key']}")
        elems[e['key']] = d['version']
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
    for e in d['elements']:
        role = e.get('contentRole')
        is_attr = e['key'] in {a['key'] for a in d['attractions']}
        expect = '看点' if is_attr else '文化历史'
        # Cross-pack attractions may mark a remote key as attraction without a local element;
        # local elements follow: in this pack's attractions => 看点.
        if role != expect and not (role == '看点' and e['key'] in attrs):
            # Local rule: attraction-key elements must be 看点; others 文化历史
            local_attrs = {a['key'] for a in d['attractions']}
            expect_local = '看点' if e['key'] in local_attrs else '文化历史'
            if role != expect_local:
                ok = False; print(f"{d['version']}: {e['key']} contentRole={role} 期望 {expect_local}")
sys.exit(0 if ok else 1)
EOF
```

## 六、v4/v3 重构基线（2026-08）

四个包已于 2026-08 按本指南整体重构（西湖 v4 / 良渚 v3 / 浙博 v4 / 历史 v3），此前的典型问题——景点不在图、无类型对称边、跨包重复实体、跨包前置缺失——已清除。当前基线：

- 节点：西湖 70 / 良渚 25 / 浙博 35 / 历史 45（历史包含 5 个文化地基节点：中秋节、中国佛教、中国茶文化、中国书法、中国山水画）。
- 边全部有 kind + explanation、单向、无对称对；跨包边统一指向历史包地基（朝代、文化概念）。
- 玉琮王 canonical key 为良渚包 `jade-cong-wang`；河姆渡为浙博包 `hemudu-culture`；施昕更为良渚包 `shi-xingeng-discovery`。新内容引用这些 key，不要再建同义节点。
- 西湖包 `locales.en` 目前只有名称级覆盖；补正文英译是已知的后续工作。
