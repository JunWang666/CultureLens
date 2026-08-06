import SwiftUI

/// 杂志栏目头：英文小字 eyebrow + 中文衬线标题 + 副题 + 分栏细线。
/// eyebrow 是版面装饰（英文小字加宽字距），不进本地化目录。
struct MagazineSectionHeader: View {
  let eyebrow: String
  let title: LocalizedStringKey
  var subtitle: LocalizedStringKey? = nil

  init(
    eyebrow: String,
    title: LocalizedStringKey,
    subtitle: LocalizedStringKey? = nil
  ) {
    self.eyebrow = eyebrow
    self.title = title
    self.subtitle = subtitle
  }

  /// Trailing title label for magazine layouts: `MagazineSectionHeader(eyebrow: "NEARBY", "附近看点")`.
  init(
    eyebrow: String,
    _ title: LocalizedStringKey,
    subtitle: LocalizedStringKey? = nil
  ) {
    self.eyebrow = eyebrow
    self.title = title
    self.subtitle = subtitle
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(verbatim: eyebrow)
        .font(CultureTypography.eyebrow())
        .tracking(1.8)
        .foregroundStyle(CultureTheme.cinnabar)
      Text(title)
        .font(CultureTypography.title(.title2))
        .foregroundStyle(CultureTheme.inkPrimary)
      if let subtitle {
        Text(subtitle)
          .font(CultureTypography.body(.subheadline))
          .foregroundStyle(CultureTheme.inkSecondary)
      }
      EditorialRule()
        .padding(.top, 6)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

/// 杂志页头：eyebrow + 大号衬线标题 + 引言 + 粗细双线（刊头线）。
struct MagazinePageHeader: View {
  let eyebrow: String
  let title: LocalizedStringKey
  let message: LocalizedStringKey

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(verbatim: eyebrow)
        .font(CultureTypography.eyebrow(.caption))
        .tracking(2)
        .foregroundStyle(CultureTheme.cinnabar)

      Text(title)
        .font(CultureTypography.title(.largeTitle))
        .foregroundStyle(CultureTheme.inkPrimary)

      Text(message)
        .font(CultureTypography.body(.subheadline))
        .foregroundStyle(CultureTheme.inkSecondary)
        .lineSpacing(3)

      MagazineDoubleRule()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

/// 朱砂方印（白文）：纸色字压在朱砂方章上，轻微歪斜模拟手盖。
/// 字是装饰性单字（如「访」「藏」），不进本地化目录。
struct SealBadge: View {
  let character: String
  var size: CGFloat = 26

  var body: some View {
    Text(verbatim: character)
      .font(CultureTypography.display(size: size * 0.58))
      .foregroundStyle(CultureTheme.canvas)
      .frame(width: size, height: size)
      .background(
        CultureTheme.cinnabar,
        in: RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
      )
      .rotationEffect(.degrees(-3))
  }
}

extension View {
  /// 统一暖调照片处理：轻降饱和 + 纸色正片叠底，
  /// 让不同来源的照片看起来像同一本杂志的图。
  func magazinePhoto() -> some View {
    saturation(0.9)
      .overlay(CultureTheme.canvas.opacity(0.18).blendMode(.multiply))
  }
}

#Preview("栏目头") {
  VStack(spacing: 32) {
    MagazineSectionHeader(eyebrow: "NEARBY", "附近看点", subtitle: "离你最近的文化现场")
    MagazinePageHeader(
      eyebrow: "SERIES",
      title: "主题探索",
      message: "沿着一条文化线索连续点亮节点。"
    )
  }
  .padding()
  .background(CulturePageBackground())
}
