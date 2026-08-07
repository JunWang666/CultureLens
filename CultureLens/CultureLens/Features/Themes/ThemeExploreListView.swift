import SwiftUI

struct ThemeExploreListView: View {
  @Environment(KnowledgeProgressStore.self) private var knowledgeProgressStore

  private var themes: [KnowledgePack.Theme] {
    KnowledgeStore.shared?.pack.themes ?? []
  }

  private var contactedIDs: Set<UUID> {
    Set(
      knowledgeProgressStore.entriesByID.values.compactMap { entry in
        entry.elementKey.flatMap(UUID.init(uuidString:)) ?? entry.nodeID
      }
    )
  }

  private var progressList: [ThemeProgress] {
    ThemeProgressCalculator.progressList(
      themes: themes,
      contactedElementIds: contactedIDs,
      knowledgeStore: KnowledgeStore.shared
    )
  }

  var body: some View {
    ZStack {
      CulturePageBackground()

      if progressList.isEmpty {
        ContentUnavailableView {
          Label("暂无主题", systemImage: "list.bullet.rectangle")
        } description: {
          Text("当前知识包尚未定义探索主题。")
        }
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: CultureTheme.sectionSpacing) {
            MagazinePageHeader(
              eyebrow: "SERIES",
              title: "文化系",
              message: "沿着一条文化线索连续点亮节点。每完成一系，就为你的文化图鉴盖下一枚印章。"
            )

            VStack(alignment: .leading, spacing: 0) {
              ForEach(Array(progressList.enumerated()), id: \.element.theme.id) { index, progress in
                if index > 0 { EditorialRule() }
                NavigationLink(value: AppRoute.theme(progress.theme.sortKey)) {
                  themeRow(progress)
                }
                .buttonStyle(.plain)
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
    }
    .cultureNavigationTitle("文化系")
  }

  private func themeRow(_ progress: ThemeProgress) -> some View {
    let themeKey = progress.theme.key ?? progress.theme.id.uuidString.lowercased()
    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        LocalizedPackText(
          source: progress.theme.name,
          cacheNamespace: "theme",
          cacheKey: themeKey
        )
        .font(CultureTypography.title(.title3))
        .foregroundStyle(CultureTheme.inkPrimary)
        Spacer()
        Text(progress.statusText)
          .font(.caption.weight(.semibold))
          .foregroundStyle(
            progress.isComplete ? CultureTheme.antiqueGold : CultureTheme.cinnabar
          )
      }

      LocalizedPackText(
        source: progress.theme.summary,
        cacheNamespace: "theme",
        cacheKey: themeKey,
        kind: .fragment
      )
      .font(CultureTypography.body(.subheadline))
      .foregroundStyle(CultureTheme.inkSecondary)
      .lineLimit(3)

      ThinProgressRule(fraction: progress.fractionComplete)

      Text("\(progress.totalCount) 个相关节点 · 点亮本系需收集 \(progress.requiredCount) 个")
        .font(.caption)
        .foregroundStyle(CultureTheme.inkSecondary)
    }
    .padding(.vertical, CultureTheme.rowPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

#Preview {
  NavigationStack {
    ThemeExploreListView()
  }
  .environment(KnowledgeProgressStore())
  .environment(AppLanguageStore())
}
