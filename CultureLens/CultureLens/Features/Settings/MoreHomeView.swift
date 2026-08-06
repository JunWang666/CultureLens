import SwiftUI

/// Compact overflow hub: magazine rows that push secondary destinations.
struct MoreHomeView: View {
  var body: some View {
    ZStack {
      CulturePageBackground()

      ScrollView {
        VStack(alignment: .leading, spacing: CultureTheme.sectionSpacing) {
          MagazinePageHeader(
            eyebrow: "MORE",
            title: "更多",
            message: "足迹、回顾与设置——探索之外的工具页。"
          )

          VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(Self.destinations.enumerated()), id: \.element.id) { index, item in
              if index > 0 { EditorialRule() }
              NavigationLink(value: item.route) {
                MagazineDestinationRow(
                  title: item.title,
                  message: item.message,
                  systemImage: item.systemImage
                )
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier(item.accessibilityID)
            }
            EditorialRule()
          }

          MagazineFooterOrnament()
        }
        .padding(.horizontal, CultureTheme.pagePadding)
        .padding(.top, 20)
        .padding(.bottom, 40)
      }
    }
    .cultureNavigationTitle("更多", showsBackButton: false)
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
      message: "在地图上回看扫描记录与兴趣点。",
      systemImage: "map",
      route: .footprint,
      accessibilityID: "more.openHistory"
    ),
    Destination(
      id: "review",
      title: "回顾",
      message: "按时间线回看扫描，或把相近识别收成参观汇总。",
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
