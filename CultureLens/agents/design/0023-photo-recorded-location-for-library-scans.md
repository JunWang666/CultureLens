# 0023 相册扫描使用照片记录位置

- 状态：已确认
- 日期：2026-08-01
- 影响范围：相册选择、扫描位置来源、识别 API 契约、历史保存、隐私处理和测试

本设计按产品新决定取代 `0003`、`0005`、`0007` 中“扫描位置固定降到两位小数、误差至少 1 km”
的约束。地点名称仍保持城市/地区级，不新增街道、POI 或完整地址采集。

## 1. 背景

扫描页当前在拍照和从相册选图后都会请求一次设备约略位置。对于相册中的旧照片，设备当前位置通常
不是拍摄地点，会给识别候选检索引入错误地域先验。

相册照片可能同时存在两类本机位置记录：

- Photos 资料库中 `PHAsset.location` 保存的拍摄位置；
- 图片原始数据中的 EXIF/GPS 字典。

图片规范化会主动移除 EXIF/GPS，因此位置必须在规范化前读取，但原始元数据仍不得上传或持久化。

## 2. 决策

扫描输入显式区分三种位置来源：

1. `currentDevice`：相机拍摄请求系统当前可提供的最佳精度单次定位。
2. `photoMetadata`：相册选择只使用所选照片记录的位置。
3. `none`：测试或明确禁用位置时不读取位置。

相册位置按以下顺序读取：

1. 使用 `PhotosPickerItem.itemIdentifier` 获取对应 `PHAsset.location`；
2. 若 Photos 资料库没有可读位置，读取已选择原始图片的 EXIF/GPS；
3. 两处都没有合法坐标时返回无位置，不请求设备当前位置。

照片和相机位置不再做小数位四舍五入，也不再把误差半径强制扩大到 1 km。识别 API 接受 WGS84
十进制度的完整 `Double` 精度；请求同时发送系统或照片记录的实际误差值，扫描历史保存同一坐标。

相机使用 `kCLLocationAccuracyBest`。如果用户在系统设置中关闭“精确位置”，应用尊重系统返回的
reduced-accuracy 坐标，不绕过系统权限选择。

## 3. 数据流

```text
PhotosPickerItem
  -> 原始图片 Data + itemIdentifier
  -> PHAsset.location / EXIF GPS
  -> PlaceContext（保留照片记录精度）
  -> FocusSelectionView（图片和位置来源一起保留）
  -> ScanCoordinator
  -> RecognitionInput / ScanSession
```

相机链路保持：

```text
AVCapturePhotoOutput
  -> FocusSelectionView
  -> ScanCoordinator
  -> LocationContextProvider.requestBestPlace()
  -> RecognitionInput / ScanSession
```

## 4. 失败与隐私行为

- 相册照片没有位置时显示“照片未记录地理信息”，继续只根据图片识别。
- 相册元数据读取失败不得阻断图片识别，也不得退回设备定位。
- 非法、非有限或超出 WGS84 范围的 GPS 坐标视为无位置。
- 南纬和西经按 EXIF `LatitudeRef` / `LongitudeRef` 转为负数。
- 图片仍在上传前规范化为无元数据 JPEG；识别服务只接收单独的结构化位置，不接收原始 EXIF。

## 5. 验证

- 单元测试覆盖 EXIF GPS 读取、南纬/西经符号、原始精度和无 GPS 行为。
- 验证规范化 JPEG 仍不包含 GPS 字典。
- Go 合约测试覆盖多于两位小数的坐标，并继续拒绝超范围、非有限坐标。
- iOS Debug build 和 Swift 单元测试通过。
- 真机补充验证：分别选择有位置和无位置照片，确认前者使用拍摄地、后者不请求当前位置。
