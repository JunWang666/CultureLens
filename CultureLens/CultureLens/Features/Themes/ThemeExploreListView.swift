import SwiftUI

struct ThemeExploreListView: View {
  @Environment(KnowledgeProgressStore.self) private var knowledgeProgressStore

  private var themes: [KnowledgePack.Theme] {
    KnowledgeStore.shared?.pack.themes ?? []
  }

  private var contactedKeys: Set<String> {
    Set(
      knowledgeProgressStore.entriesByID.values.compactMap(\.elementKey)
    )
  }

  private var progressList: [ThemeProgress] {
    ThemeProgressCalculator.progressList(
      themes: themes,
      contactedElementKeys: contactedKeys
    )
  }

  var body: some View {
    ZStack {
      CulturePageBackground()

      if themes.isEmpty {
        ContentUnavailableView {
          Label("暂无主题", systemImage: "list.bullet.rectangle")
        } description: {
          Text("当前知识包尚未定义探索主题。")
        }
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 16) {
            EditorialHeader(
              eyebrow: nil,
              title: "主题探索",
              message: "沿着一条文化线索连续点亮节点，把零散识别收成可完成的探索路径。"
            )

            ForEach(progressList, id: \.theme.key) { progress in
              NavigationLink(value: AppRoute.theme(progress.theme.key)) {
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
    .cultureNavigationTitle("主题探索")
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

      Text("\(progress.theme.elementKeys.count) 个相关节点 · 完成需点亮 \(progress.requiredCount) 个")
        .font(.caption)
        .foregroundStyle(CultureTheme.inkSecondary)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      CultureTheme.surface,
      in: RoundedRectangle(cornerRadius: CultureTheme.cardRadius, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: CultureTheme.cardRadius, style: .continuous)
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
