import SwiftUI

struct ThemeDetailView: View {
  let themeKey: String

  @Environment(KnowledgeProgressStore.self) private var knowledgeProgressStore

  private var theme: KnowledgePack.Theme? {
    KnowledgeStore.shared?.pack.themes.first {
      $0.key == themeKey || $0.id.uuidString.caseInsensitiveCompare(themeKey) == .orderedSame
        || $0.sortKey == themeKey
    }
  }

  private var contactedIDs: Set<UUID> {
    Set(
      knowledgeProgressStore.entriesByID.values.compactMap { entry in
        entry.elementKey.flatMap(UUID.init(uuidString:)) ?? entry.nodeID
      }
    )
  }

  private var progress: ThemeProgress? {
    guard let theme else { return nil }
    return ThemeProgressCalculator.progress(
      for: theme,
      contactedElementIds: contactedIDs,
      knowledgeStore: KnowledgeStore.shared
    )
  }

  var body: some View {
    ZStack {
      CulturePageBackground()

      if let theme, let progress, !progress.elementIds.isEmpty {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
              Text(verbatim: "SERIES")
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundStyle(CultureTheme.cinnabar)

              Text(progress.statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                  progress.isComplete ? CultureTheme.antiqueGold : CultureTheme.cinnabar
                )

              if progress.isComplete {
                Label("文化系已点亮", systemImage: "seal.fill")
                  .font(.headline)
                  .foregroundStyle(CultureTheme.antiqueGold)
                  .transition(.scale.combined(with: .opacity))
              }

              Text(theme.name)
                .font(.cultureSerif(.largeTitle))
                .foregroundStyle(CultureTheme.inkPrimary)

              Text(theme.summary)
                .font(.title3)
                .foregroundStyle(CultureTheme.inkSecondary)
                .lineSpacing(5)

              VStack(spacing: 3) {
                Rectangle().fill(CultureTheme.inkPrimary).frame(height: 2)
                Rectangle().fill(CultureTheme.inkPrimary.opacity(0.35)).frame(height: 0.5)
              }
              .padding(.top, 6)
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
                  ? LocalizedStringKey("这条文化系已经点亮。继续收集其余节点，可以让脉络更完整。")
                  : "在现场扫描并加入文化图谱，即可推进主题进度。"
              )
              .font(.caption)
              .foregroundStyle(CultureTheme.inkSecondary)
            }
            .padding(18)
            .background(
              CultureTheme.surface,
              in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )

            MagazineSectionHeader(eyebrow: "NODES", "主题节点")

            ForEach(progress.elementIds, id: \.self) { id in
              elementRow(
                id: id,
                isContacted: progress.contactedIds.contains(id)
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

  @ViewBuilder
  private func elementRow(id: UUID, isContacted: Bool) -> some View {
    if let element = KnowledgeStore.shared?.element(id: id) {
      let name = element.name
      let summary = KnowledgeStore.richTextPlainText(element.introduction)

      NavigationLink(value: AppRoute.knowledgeElement(element.id)) {
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
          in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(CultureTheme.hairline, lineWidth: 1)
        }
      }
      .buttonStyle(.plain)
    }
  }
}

#Preview {
  NavigationStack {
    ThemeDetailView(themeKey: "moon-pools-reflection")
  }
  .environment(KnowledgeProgressStore())
}
