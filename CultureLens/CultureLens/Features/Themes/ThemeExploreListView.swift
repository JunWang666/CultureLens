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
          LazyVStack(alignment: .leading, spacing: 16) {
            MagazinePageHeader(
              eyebrow: "SERIES",
              title: "文化系",
              message: "沿着一条文化线索连续点亮节点。每完成一系，就为你的文化图鉴盖下一枚印章。"
            )

            ForEach(progressList, id: \.theme.id) { progress in
              NavigationLink(value: AppRoute.theme(progress.theme.sortKey)) {
                themeRow(progress)
              }
              .buttonStyle(.plain)
            }
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
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text(progress.theme.name)
          .font(.cultureSerif(.title3))
          .foregroundStyle(CultureTheme.inkPrimary)
        Spacer()
        Text(progress.statusText)
          .font(.caption.weight(.semibold))
          .foregroundStyle(
            progress.isComplete ? CultureTheme.antiqueGold : CultureTheme.cinnabar
          )
      }

      Text(progress.theme.summary)
        .font(.subheadline)
        .foregroundStyle(CultureTheme.inkSecondary)
        .lineLimit(3)

      ProgressView(value: progress.fractionComplete)
        .tint(CultureTheme.cinnabar)

      Text("\(progress.totalCount) 个相关节点 · 点亮本系需收集 \(progress.requiredCount) 个")
        .font(.caption)
        .foregroundStyle(CultureTheme.inkSecondary)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      CultureTheme.surface,
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }
}

#Preview {
  NavigationStack {
    ThemeExploreListView()
  }
  .environment(KnowledgeProgressStore())
}
