import SwiftUI

/// Compact overflow hub: card rows that push secondary destinations.
struct MoreHomeView: View {
  var body: some View {
    ZStack {
      CulturePageBackground()

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(Self.destinations) { item in
            NavigationLink(value: item.route) {
              moreCard(item)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(item.accessibilityID)
          }
        }
        .padding(.horizontal, CultureTheme.pagePadding)
        .padding(.top, 16)
        .padding(.bottom, 40)
      }
    }
    .cultureNavigationTitle("更多", showsBackButton: false)
  }

  private func moreCard(_ item: Destination) -> some View {
    HStack(alignment: .center, spacing: 16) {
      Image(systemName: item.systemImage)
        .font(.title3)
        .foregroundStyle(CultureTheme.antiqueGold)
        .frame(width: 36)

      VStack(alignment: .leading, spacing: 4) {
        Text(item.title)
          .font(.headline)
          .foregroundStyle(CultureTheme.inkPrimary)
        Text(item.message)
          .font(.caption)
          .foregroundStyle(CultureTheme.inkSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 8)

      Image(systemName: "chevron.right")
        .font(.body.weight(.semibold))
        .foregroundStyle(CultureTheme.inkSecondary)
        .accessibilityHidden(true)
    }
    .padding(18)
    .background(
      CultureTheme.surface,
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
  }
}

private extension MoreHomeView {
  struct Destination: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let systemImage: String
    let route: AppRoute
    let accessibilityID: String
  }

  static let destinations: [Destination] = [
    Destination(
      id: "history",
      title: "足迹",
      message: "在地图与时间线里回看扫描记录。",
      systemImage: "map",
      route: .footprint,
      accessibilityID: "more.openHistory"
    ),
    Destination(
      id: "review",
      title: "文化回顾",
      message: "把相近时间与地点的扫描收成一次参观汇总。",
      systemImage: "book.pages",
      route: .visitTrips,
      accessibilityID: "more.openReview"
    ),
    Destination(
      id: "settings",
      title: "设置",
      message: "语言偏好、资源包工具与其他选项。",
      systemImage: "gearshape",
      route: .settings,
      accessibilityID: "more.openSettings"
    ),
  ]
}

#Preview {
  NavigationStack {
    MoreHomeView()
  }
}
