import SwiftUI

struct ThemeDetailView: View {
  let themeKey: String

  @Environment(KnowledgeProgressStore.self) private var knowledgeProgressStore

  private var theme: KnowledgePack.Theme? {
    KnowledgeStore.shared?.pack.themes.first { $0.key == themeKey }
  }

  private var contactedKeys: Set<String> {
    Set(
      knowledgeProgressStore.entriesByID.values.compactMap(\.elementKey)
    )
  }

  private var progress: ThemeProgress? {
    guard let theme else { return nil }
    return ThemeProgressCalculator.progress(
      for: theme,
      contactedElementKeys: contactedKeys
    )
  }

  var body: some View {
    ZStack {
      CulturePageBackground()

      if let theme, let progress {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
              Text(progress.statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                  progress.isComplete ? CultureTheme.antiqueGold : CultureTheme.cinnabar
                )

              Text(theme.name)
                .font(.cultureSerif(.largeTitle))
                .foregroundStyle(CultureTheme.inkPrimary)

              Text(theme.summary)
                .font(.title3)
                .foregroundStyle(CultureTheme.inkSecondary)
                .lineSpacing(5)
            }

            VStack(alignment: .leading, spacing: 10) {
              HStack {
                Text("进度")
                  .font(.headline)
                Spacer()
                Text("\(progress.contactedCount)/\(progress.requiredCount)")
                  .font(.subheadline.monospacedDigit())
                  .foregroundStyle(CultureTheme.inkSecondary)
              }
              ProgressView(value: progress.fractionComplete)
                .tint(CultureTheme.cinnabar)
              Text(
                progress.isComplete
                  ? "已达到完成条件。可以继续点亮其余节点，加深理解。"
                  : "在现场扫描并加入文化图谱，即可推进主题进度。"
              )
              .font(.caption)
              .foregroundStyle(CultureTheme.inkSecondary)
            }
            .padding(18)
            .background(
              CultureTheme.surface,
              in: RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
            )

            sectionTitle("主题节点")

            ForEach(theme.elementKeys, id: \.self) { key in
              elementRow(
                key: key,
                isContacted: progress.contactedKeys.contains(key)
              )
            }
          }
          .padding(.horizontal, CultureTheme.pagePadding)
          .padding(.top, 20)
          .padding(.bottom, 40)
        }
      } else {
        ContentUnavailableView("主题暂不可用", systemImage: "list.bullet.rectangle")
      }
    }
    .cultureNavigationTitle(theme.map { LocalizedStringKey($0.name) } ?? "主题")
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.cultureSerif(.title2))
      .foregroundStyle(CultureTheme.inkPrimary)
  }

  @ViewBuilder
  private func elementRow(key: String, isContacted: Bool) -> some View {
    let name = KnowledgeStore.shared?.element(key: key)?.name ?? key
    let summary =
      KnowledgeStore.shared?.element(key: key).map {
        KnowledgeStore.richTextPlainText($0.introduction)
      } ?? ""

    NavigationLink(value: AppRoute.knowledgeElement(key)) {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: isContacted ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(
            isContacted ? CultureTheme.antiqueGold : CultureTheme.inkSecondary
          )
          .font(.title3)

        VStack(alignment: .leading, spacing: 4) {
          Text(name)
            .font(.headline)
            .foregroundStyle(CultureTheme.inkPrimary)
          if !summary.isEmpty {
            Text(summary)
              .font(.caption)
              .foregroundStyle(CultureTheme.inkSecondary)
              .lineLimit(2)
          }
        }

        Spacer(minLength: 0)

        Image(systemName: "chevron.right")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(16)
      .background(
        CultureTheme.surface,
        in: RoundedRectangle(cornerRadius: 18)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 18)
          .stroke(CultureTheme.hairline, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }
}

#Preview {
  NavigationStack {
    ThemeDetailView(themeKey: "moon-pools-reflection")
  }
  .environment(KnowledgeProgressStore())
}
