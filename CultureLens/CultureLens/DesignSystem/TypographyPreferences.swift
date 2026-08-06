import Foundation
import SwiftUI

/// 正文字号档位（叠在 Dynamic Type 之上的杂志缩放）。
nonisolated enum TypographySizePreference: String, CaseIterable, Identifiable, Codable, Sendable {
  case small
  case standard
  case large
  case extraLarge

  var id: String { rawValue }

  var title: LocalizedStringKey {
    switch self {
    case .small: "较小"
    case .standard: "标准"
    case .large: "较大"
    case .extraLarge: "更大"
    }
  }

  /// 相对标准档的缩放系数。
  var scale: CGFloat {
    switch self {
    case .small: 0.9
    case .standard: 1.0
    case .large: 1.15
    case .extraLarge: 1.3
    }
  }
}

/// 正文字族：杂志宋体或系统字体。
nonisolated enum TypographyFamilyPreference: String, CaseIterable, Identifiable, Codable, Sendable {
  case magazine
  case system

  var id: String { rawValue }

  var title: LocalizedStringKey {
    switch self {
    case .magazine: "杂志宋体"
    case .system: "系统字体"
    }
  }

  var detail: LocalizedStringKey {
    switch self {
    case .magazine: "内置思源宋体，杂志阅读感"
    case .system: "系统默认字体，部分场景更清晰"
    }
  }
}

/// 持久化字体偏好，供设置页与 `CultureTypography` 读取。
@Observable
@MainActor
final class TypographyPreferenceStore {
  nonisolated static let sizeKey = "culturelens.typography.size"
  nonisolated static let familyKey = "culturelens.typography.family"

  var size: TypographySizePreference {
    didSet {
      UserDefaults.standard.set(size.rawValue, forKey: Self.sizeKey)
      revision &+= 1
      CultureTypography.refreshChrome()
    }
  }

  var family: TypographyFamilyPreference {
    didSet {
      UserDefaults.standard.set(family.rawValue, forKey: Self.familyKey)
      revision &+= 1
      CultureTypography.refreshChrome()
    }
  }

  /// 变更计数：根视图用 `.id(revision)` 刷新已渲染页面的字体。
  private(set) var revision: Int = 0

  init(
    size: TypographySizePreference = TypographyPreferenceStore.loadSize(),
    family: TypographyFamilyPreference = TypographyPreferenceStore.loadFamily()
  ) {
    self.size = size
    self.family = family
  }

  var scale: CGFloat { size.scale }

  nonisolated static func loadSize() -> TypographySizePreference {
    guard let raw = UserDefaults.standard.string(forKey: sizeKey),
      let value = TypographySizePreference(rawValue: raw)
    else {
      return .standard
    }
    return value
  }

  nonisolated static func loadFamily() -> TypographyFamilyPreference {
    guard let raw = UserDefaults.standard.string(forKey: familyKey),
      let value = TypographyFamilyPreference(rawValue: raw)
    else {
      return .magazine
    }
    return value
  }

  nonisolated static func currentSize() -> TypographySizePreference { loadSize() }
  nonisolated static func currentFamily() -> TypographyFamilyPreference { loadFamily() }
  nonisolated static func currentScale() -> CGFloat { loadSize().scale }
}
