import SwiftUI

/// 分栏细线：杂志用线而不是盒子分隔条目。
struct EditorialRule: View {
  var body: some View {
    Rectangle()
      .fill(CultureTheme.hairline)
      .frame(height: 1)
  }
}

/// 1.5pt 细线进度条，替代系统 ProgressView 的「设置页」感。
struct ThinProgressRule: View {
  let fraction: Double
  var tint: Color = CultureTheme.cinnabar

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Rectangle().fill(CultureTheme.hairline)
        Rectangle()
          .fill(tint)
          .frame(width: proxy.size.width * min(max(fraction, 0), 1))
      }
    }
    .frame(height: 1.5)
  }
}

/// 刊头式双线（粗 + 细），页级标题下方使用。
struct MagazineDoubleRule: View {
  var body: some View {
    VStack(spacing: 3) {
      Rectangle().fill(CultureTheme.inkPrimary).frame(height: 2)
      Rectangle().fill(CultureTheme.inkPrimary.opacity(0.35)).frame(height: 0.5)
    }
  }
}

/// 页脚装饰：细线 + 朱砂菱花。
struct MagazineFooterOrnament: View {
  var body: some View {
    HStack(spacing: 10) {
      EditorialRule()
      Text(verbatim: "❖")
        .font(.caption2)
        .foregroundStyle(CultureTheme.cinnabar)
      EditorialRule()
    }
    .padding(.top, 8)
    .accessibilityHidden(true)
  }
}

/// 杂志式导航行：衬线标题 + 副文 + chevron，上下细线分隔，无卡片盒。
struct MagazineDestinationRow: View {
  let title: LocalizedStringKey
  let message: LocalizedStringKey
  var systemImage: String? = nil

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      if let systemImage {
        Image(systemName: systemImage)
          .font(.body)
          .foregroundStyle(CultureTheme.antiqueGold)
          .frame(width: 22)
          .padding(.top, 2)
          .accessibilityHidden(true)
      }

      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.magazineDisplay(.headline))
          .foregroundStyle(CultureTheme.inkPrimary)
        Text(message)
          .font(.caption)
          .foregroundStyle(CultureTheme.inkSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 8)

      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(CultureTheme.inkSecondary.opacity(0.7))
        .padding(.top, 4)
        .accessibilityHidden(true)
    }
    .padding(.vertical, CultureTheme.rowPadding)
    .contentShape(Rectangle())
  }
}

/// 杂志式列表条目外壳：上下细线，去掉圆角 surface 盒。
struct MagazineListRowChrome<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      EditorialRule()
      content()
        .padding(.vertical, CultureTheme.rowPadding)
      EditorialRule()
    }
  }
}

extension View {
  /// 列表条目上下各一条细线，替代 surface 圆角卡片。
  func magazineListSeparators(showsTop: Bool = true, showsBottom: Bool = true) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if showsTop { EditorialRule() }
      self.padding(.vertical, CultureTheme.rowPadding)
      if showsBottom { EditorialRule() }
    }
  }
}
