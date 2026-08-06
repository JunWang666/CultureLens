import SwiftUI

struct ThemeDetailView: View {
  let themeKey: String

  @Environment(KnowledgeProgressStore.self) private var knowledgeProgressStore
  @Environment(AppLanguageStore.self) private var languageStore
  @State private var resolvedNavigationTitle: String?

  private var theme: KnowledgePack.Theme? {
    KnowledgeStore.shared?.pack.themes.first {
      $0.key == themeKey || $0.id.uuidString.caseInsensitiveCompare(themeKey) == .orderedSame
        || $0.sortKey == themeKey
    }
  }

  private var themeCacheKey: String? {
    guard let theme else { return nil }
    return theme.key ?? theme.id.uuidString.lowercased()
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
          LazyVStack(alignment: .leading, spacing: CultureTheme.sectionSpacing) {
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
                Text("文化系已点亮")
                  .font(CultureTypography.title(.headline))
                  .foregroundStyle(CultureTheme.antiqueGold)
                  .transition(.scale.combined(with: .opacity))
              }

              HStack(alignment: .top, spacing: 14) {
                ThemeSeriesThumbnail(theme: theme)

                LocalizedPackText(
                  source: theme.name,
                  cacheNamespace: "theme",
                  cacheKey: themeCacheKey
                )
                .font(CultureTypography.title(.largeTitle))
                .foregroundStyle(CultureTheme.inkPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
              }

              LocalizedPackText(
                source: theme.summary,
                cacheNamespace: "theme",
                cacheKey: themeCacheKey,
                kind: .fragment
              )
              .font(CultureTypography.body(.title3))
              .foregroundStyle(CultureTheme.inkSecondary)
              .lineSpacing(5)

              MagazineDoubleRule()
                .padding(.top, 6)
            }

            VStack(alignment: .leading, spacing: 10) {
              HStack {
                Text("进度")
                  .font(CultureTypography.title(.headline))
                  .foregroundStyle(CultureTheme.inkPrimary)
                Spacer()
                Text("\(progress.contactedCount)/\(progress.requiredCount)")
                  .font(.subheadline.monospacedDigit())
                  .foregroundStyle(CultureTheme.inkSecondary)
              }
              ThinProgressRule(fraction: progress.fractionComplete)
              Text(
                progress.isComplete
                  ? LocalizedStringKey("这条文化系已经点亮。继续收集其余节点，可以让脉络更完整。")
                  : "在现场扫描并加入文化图谱，即可推进主题进度。"
              )
              .font(.caption)
              .foregroundStyle(CultureTheme.inkSecondary)
            }

            VStack(alignment: .leading, spacing: 0) {
              MagazineSectionHeader(eyebrow: "NODES", "主题节点")
                .padding(.bottom, 4)

              ForEach(Array(progress.elementIds.enumerated()), id: \.element) { index, id in
                if index > 0 { EditorialRule() }
                elementRow(
                  id: id,
                  isContacted: progress.contactedIds.contains(id)
                )
              }
              EditorialRule()
            }

            MagazineFooterOrnament()
          }
          .padding(.horizontal, CultureTheme.pagePadding)
          .padding(.top, 20)
          .padding(.bottom, 40)
        }
      } else {
        ContentUnavailableView("主题暂不可用", systemImage: "list.bullet.rectangle")
      }
    }
    .cultureNavigationTitle(
      resolvedNavigationTitle.map { LocalizedStringKey($0) } ?? "主题"
    )
    .task(id: "\(themeCacheKey ?? "")|\(languageStore.language.rawValue)") {
      await reloadNavigationTitle()
    }
  }

  @MainActor
  private func reloadNavigationTitle() async {
    resolvedNavigationTitle = nil
    guard let theme, let themeCacheKey else { return }
    if languageStore.language.isKnowledgeSource {
      resolvedNavigationTitle = theme.name
      return
    }
    resolvedNavigationTitle = await KnowledgeTranslationService.shared.localizedName(
      cacheNamespace: "theme",
      key: themeCacheKey,
      sourceName: theme.name,
      language: languageStore.language
    )
  }

  @ViewBuilder
  private func elementRow(id: UUID, isContacted: Bool) -> some View {
    if let element = KnowledgeStore.shared?.element(id: id) {
      let name = element.name
      let summary = KnowledgeStore.richTextPlainText(element.introduction)
      let elementKey = element.key ?? element.id.uuidString.lowercased()

      NavigationLink(value: AppRoute.knowledgeElement(element.id)) {
        HStack(alignment: .top, spacing: 14) {
          if isContacted {
            SealBadge(character: "访", size: 22)
          } else {
            Image(systemName: "circle")
              .foregroundStyle(CultureTheme.inkSecondary)
              .font(.title3)
              .frame(width: 22, height: 22)
          }

          VStack(alignment: .leading, spacing: 4) {
            LocalizedPackText(
              source: name,
              cacheNamespace: "element",
              cacheKey: elementKey
            )
            .font(CultureTypography.title(.headline))
            .foregroundStyle(CultureTheme.inkPrimary)
            if !summary.isEmpty {
              LocalizedPackText(
                source: summary,
                cacheNamespace: "element",
                cacheKey: elementKey,
                kind: .fragment
              )
              .font(.caption)
              .foregroundStyle(CultureTheme.inkSecondary)
              .lineLimit(2)
            }
          }

          Spacer(minLength: 0)

          Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundStyle(CultureTheme.inkSecondary.opacity(0.7))
        }
        .padding(.vertical, CultureTheme.rowPadding)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }
}

private struct ThemeSeriesThumbnail: View {
  let theme: KnowledgePack.Theme

  var body: some View {
    Image(ExplorationArtwork.seriesImageName(for: theme))
      .resizable()
      .scaledToFill()
      .frame(width: 68, height: 68)
      .clipped()
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(CultureTheme.antiqueGold.opacity(0.75), lineWidth: 1)
      }
      .accessibilityLabel("\(theme.name)主题海报")
  }
}

#Preview {
  NavigationStack {
    ThemeDetailView(themeKey: "moon-pools-reflection")
  }
  .environment(KnowledgeProgressStore())
  .environment(AppLanguageStore())
}
