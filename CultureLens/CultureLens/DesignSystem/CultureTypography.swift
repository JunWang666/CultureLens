import SwiftUI
import UIKit

/// 杂志字体唯一入口。改字族、字号、角色映射只动这里。
///
/// 角色：
/// - `display`：刊头巨型字、封面标题、统计数字
/// - `title`：页头 / 栏目 / 列表主标题
/// - `body`：段落、摘要、讲解与介绍
/// - `meta`：次要说明（脚注级阅读文字）
/// - `eyebrow`：英文装饰小字（有意保留系统无衬线 + 字距）
///
/// 用户偏好（设置页）经 `TypographyPreferenceStore` 写入，本类型读取缩放与字族。
enum CultureTypography {
  enum Role: Sendable {
    case display
    case title
    case body
    case meta
    case eyebrow
  }

  // MARK: - Semantic API

  static func display(_ style: Font.TextStyle = .largeTitle) -> Font {
    font(style, role: .display)
  }

  static func display(size: CGFloat) -> Font {
    font(size: size, role: .display)
  }

  static func title(_ style: Font.TextStyle = .title2) -> Font {
    font(style, role: .title)
  }

  static func body(_ style: Font.TextStyle = .body) -> Font {
    font(style, role: .body)
  }

  static func meta(_ style: Font.TextStyle = .caption) -> Font {
    font(style, role: .meta)
  }

  /// 英文 eyebrow：系统无衬线，由视图自行加 tracking；仍跟随字号缩放。
  static func eyebrow(_ style: Font.TextStyle = .caption2) -> Font {
    let size = scaledPointSize(for: style)
    return .system(size: size, weight: .semibold, design: .default)
  }

  static func font(_ role: Role, style: Font.TextStyle) -> Font {
    switch role {
    case .display: display(style)
    case .title: title(style)
    case .body: body(style)
    case .meta: meta(style)
    case .eyebrow: eyebrow(style)
    }
  }

  static func font(_ role: Role, size: CGFloat) -> Font {
    font(size: size, role: role)
  }

  // MARK: - Bootstrap

  /// App 启动时注册内置宋体，并把导航栏标题切到杂志字体。
  static func bootstrap() {
    _ = resolvedSerifName
    refreshChrome()
  }

  /// 设置变更后刷新 UIKit 导航栏字体。
  static func refreshChrome() {
    applyNavigationChrome()
  }

  // MARK: - Shared metrics / UIKit / Markdown

  /// 当前可用的杂志宋体族名（忽略用户是否选用系统字体）。
  static var serifFamilyName: String? { resolvedSerifName }

  static func pointSize(for style: Font.TextStyle) -> CGFloat {
    basePointSize(for: style)
  }

  static func scaledPointSize(for style: Font.TextStyle) -> CGFloat {
    basePointSize(for: style) * TypographyPreferenceStore.currentScale()
  }

  static func scaledSize(_ size: CGFloat) -> CGFloat {
    size * TypographyPreferenceStore.currentScale()
  }

  static func uiFont(style: Font.TextStyle, role: Role = .title) -> UIFont {
    let size = scaledPointSize(for: style)
    if role != .eyebrow,
      prefersMagazineFamily,
      let name = resolvedSerifName,
      let font = UIFont(name: name, size: size)
    {
      return UIFontMetrics(forTextStyle: uiTextStyle(for: style)).scaledFont(for: font)
    }
    let weight: UIFont.Weight = (role == .display || role == .title || role == .eyebrow)
      ? .semibold : .regular
    return UIFontMetrics(forTextStyle: uiTextStyle(for: style)).scaledFont(
      for: .systemFont(ofSize: size, weight: weight)
    )
  }

  /// Markdown 渲染器用的缩放字体。
  static func markdownFont(size: CGFloat) -> UIFont? {
    let scaled = UIFontMetrics.default.scaledValue(for: scaledSize(size))
    if prefersMagazineFamily, let name = resolvedSerifName {
      return UIFont(name: name, size: scaled)
    }
    return .systemFont(ofSize: scaled, weight: .regular)
  }
}

// MARK: - Internals

private extension CultureTypography {
  static let bundledFontResource = "CultureLensSerif-SemiBold"
  static let bundledFontPostScriptName = "CultureLensSerif-SemiBold"

  static var prefersMagazineFamily: Bool {
    TypographyPreferenceStore.currentFamily() == .magazine
  }

  /// 首次访问时注册内置字体；回退链：内置宋体 → Songti SC → nil。
  static let resolvedSerifName: String? = {
    if let url = Bundle.main.url(forResource: bundledFontResource, withExtension: "ttf") {
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
    if UIFont(name: bundledFontPostScriptName, size: 12) != nil {
      return bundledFontPostScriptName
    }
    if UIFont(name: "Songti SC", size: 12) != nil {
      return "Songti SC"
    }
    return nil
  }()

  static func basePointSize(for style: Font.TextStyle) -> CGFloat {
    switch style {
    case .largeTitle: return 34
    case .title: return 28
    case .title2: return 22
    case .title3: return 20
    case .headline: return 17
    case .body: return 17
    case .callout: return 16
    case .subheadline: return 15
    case .footnote: return 13
    case .caption: return 12
    case .caption2: return 11
    @unknown default: return 17
    }
  }

  static func font(_ style: Font.TextStyle, role: Role) -> Font {
    let size = scaledPointSize(for: style)
    return resolvedFont(size: size, relativeTo: style, role: role)
  }

  static func font(size: CGFloat, role: Role) -> Font {
    resolvedFont(size: scaledSize(size), relativeTo: nil, role: role)
  }

  static func resolvedFont(size: CGFloat, relativeTo style: Font.TextStyle?, role: Role) -> Font {
    if role == .eyebrow {
      return .system(size: size, weight: .semibold, design: .default)
    }

    if prefersMagazineFamily, let name = resolvedSerifName {
      if let style {
        return .custom(name, size: size, relativeTo: style)
      }
      return .custom(name, size: size)
    }

    let weight: Font.Weight = (role == .display || role == .title) ? .semibold : .regular
    if let style {
      return .system(style, design: .default, weight: weight)
    }
    return .system(size: size, weight: weight, design: .default)
  }

  static func uiTextStyle(for style: Font.TextStyle) -> UIFont.TextStyle {
    switch style {
    case .largeTitle: return .largeTitle
    case .title: return .title1
    case .title2: return .title2
    case .title3: return .title3
    case .headline: return .headline
    case .body: return .body
    case .callout: return .callout
    case .subheadline: return .subheadline
    case .footnote: return .footnote
    case .caption: return .caption1
    case .caption2: return .caption2
    @unknown default: return .body
    }
  }

  static func applyNavigationChrome() {
    let appearance = UINavigationBarAppearance()
    appearance.configureWithTransparentBackground()
    appearance.titleTextAttributes = [
      .font: uiFont(style: .headline, role: .title),
      .foregroundColor: UIColor(named: "InkPrimary") ?? .label,
    ]
    appearance.largeTitleTextAttributes = [
      .font: uiFont(style: .largeTitle, role: .display),
      .foregroundColor: UIColor(named: "InkPrimary") ?? .label,
    ]

    let nav = UINavigationBar.appearance()
    nav.standardAppearance = appearance
    nav.compactAppearance = appearance
    nav.scrollEdgeAppearance = appearance
    nav.tintColor = UIColor(named: "Cinnabar")
  }
}
