# 0026 知识包编辑器 MapKit 选位置

- 状态：已实现，待真机/模拟器验证（2026-08-07）

## 背景

知识包「现场介绍」编辑（`PackIntroductionEditorView`）要求填写 `latitude` / `longitude` 与可选 `coordinateSourceUrl`，但目前只有手动文本框。维护者需要对照地图核对或挑选坐标，复制粘贴易出错。

App 已在足迹页与扫描识别中使用 MapKit（搜索、定位、POI）；编辑器应复用同一套能力，把选中坐标写回草稿字段。

## 决策

1. 在介绍编辑表单的坐标区增加「在地图上选择」入口，并在已有有效坐标时显示小型只读地图预览。
2. 选点以全屏 sheet `PackLocationPickerView` 完成：
   - 地图采用「中心钉」交互：固定钉在屏幕中心，拖动/缩放底图；确认时取相机中心坐标。
   - 支持 `MKLocalSearch` 地点/地址搜索，选中结果后相机跳到该坐标。
   - 支持「定位到我」：复用 `LocationContextProvider` 一帧定位。
   - 保留底部实时经纬度读数；确认后写回 `EditableIntroduction.latitude` / `longitude`（格式化为最多 6 位小数）。
3. 若当前 `coordinateSourceUrl` 为空，确认时自动填入 Apple Maps 链接 `https://maps.apple.com/?ll=lat,lon`；已有来源 URL 不覆盖。
4. 打开选点器时：若草稿坐标合法且非 `(0,0)`，以该点为初始中心；否则优先用户位置，再回退西湖（约 `30.242, 120.148`）作为默认取景，避免世界地图原点。
5. 手动经纬度文本框保留，可与地图选点互相覆盖；地图预览随文本框解析结果更新。

## 边界

- 不改知识包 schema、校验规则或导出格式。
- 不把 MapKit 搜索结果写入景点 / 元素身份字段；仅更新坐标与可选来源 URL。
- 不新增定位权限文案或 entitlement（沿用既有 When-In-Use）。
- 本期不在元素/关系/主题编辑器接入地图。

## 验证

- 单测：坐标解析/格式化、`(0,0)` 与非法值判定、Apple Maps URL 生成。
- 构建：在 macOS + Xcode 上编译 App / 测试 target；本 Linux Cloud VM 无法跑 iOS 构建。
- 真机/模拟器：打开介绍编辑 → 地图选点 → 确认后经纬度与空来源 URL 回填；已有 `coordinateSourceUrl` 不被覆盖；搜索与定位可用。
