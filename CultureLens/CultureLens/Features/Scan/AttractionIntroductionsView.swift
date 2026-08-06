import SwiftUI

/// 景点候选的「现场知识」：按扫描位置读取该景点的现场介绍。
/// 从原候选详情页抽出，供扫描结果页在展示景点候选时复用。
struct AttractionIntroductionsView: View {
  let place: PlaceContext?
  let attractionID: UUID
  /// 候选自带的介绍（用于去重，也决定空态是否展示）。
  let existingSummary: String?
  private let contentService: CultureContentService

  @State private var state: IntroductionState = .idle

  init(
    place: PlaceContext?,
    attractionID: UUID,
    existingSummary: String?,
    contentService: CultureContentService = .live()
  ) {
    self.place = place
    self.attractionID = attractionID
    self.existingSummary = existingSummary
    self.contentService = contentService
  }

  private var loadedIntroductions: [AttractionIntroductionRecommendation] {
    guard case .loaded(let introductions) = state else {
      return []
    }
    return introductions
  }

  private var additionalIntroductions: [AttractionIntroductionRecommendation] {
    var seen = Set<String>()
    if let existingSummary {
      seen.insert(normalized(existingSummary))
    }
    return loadedIntroductions.filter { introduction in
      let key = normalized(introduction.introduction.plainText)
      return !key.isEmpty && seen.insert(key).inserted
    }
  }

  var body: some View {
    content
      .task(id: attractionID) {
        await loadIntroductions()
      }
  }

  @ViewBuilder
  private var content: some View {
    switch state {
    case .idle, .loading:
      HStack(spacing: 10) {
        ProgressView()
        Text(existingSummary == nil ? "正在读取景点介绍…" : "正在读取更多现场知识…")
      }
      .font(.subheadline)
      .foregroundStyle(CultureTheme.inkSecondary)

    case .loaded:
      if !additionalIntroductions.isEmpty {
        VStack(alignment: .leading, spacing: 14) {
          Text("现场知识")
            .font(.cultureSerif(.title2))
            .foregroundStyle(CultureTheme.inkPrimary)

          ForEach(additionalIntroductions) { introduction in
            LocalizedIntroductionCard(introduction: introduction)
          }
        }
      } else if existingSummary == nil {
        contentUnavailable("数据库中没有匹配到这个景点的现场介绍。")
      }

    case .failed(let message):
      contentUnavailableText(message)
    }
  }

  private func contentUnavailable(_ message: LocalizedStringKey) -> some View {
    contentUnavailableBody(Label(message, systemImage: "exclamationmark.circle"))
  }

  /// Runtime strings arrive already localized (or from the service); show verbatim.
  private func contentUnavailableText(_ message: String) -> some View {
    contentUnavailableBody(Label(message, systemImage: "exclamationmark.circle"))
  }

  private func contentUnavailableBody(_ label: some View) -> some View {
    label
      .font(.subheadline)
      .foregroundStyle(CultureTheme.inkSecondary)
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        CultureTheme.surface,
        in: RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
      )
  }

  @MainActor
  private func loadIntroductions() async {
    guard let place else {
      state = .failed(String(localized: "本次扫描缺少位置或景点标识，无法读取现场介绍。"))
      return
    }

    state = .loading
    do {
      let response = try await contentService.nearbyRecommendations(
        place.latitude,
        place.longitude,
        50_000,
        20
      )
      let targetKey = attractionID.uuidString.lowercased()
      let slug = KnowledgeStore.shared?.attraction(id: attractionID)?.key
      state = .loaded(
        response.introductions.filter { intro in
          intro.attraction.key.caseInsensitiveCompare(targetKey) == .orderedSame
            || (slug.map {
              intro.attraction.key.caseInsensitiveCompare($0) == .orderedSame
            } ?? false)
        }
      )
    } catch is CancellationError {
      return
    } catch {
      state = .failed(error.localizedDescription)
    }
  }

  private func normalized(_ value: String) -> String {
    value.filter { !$0.isWhitespace }.lowercased()
  }
}

private enum IntroductionState {
  case idle
  case loading
  case loaded([AttractionIntroductionRecommendation])
  case failed(String)
}

/// On-site introduction card that translates the pack name + body into the
/// active app language, showing a skeleton while a translation is in flight.
private struct LocalizedIntroductionCard: View {
  let introduction: AttractionIntroductionRecommendation

  @Environment(AppLanguageStore.self) private var languageStore
  @State private var resolvedName: String?
  @State private var resolvedText: String?

  private var showsSourceDirectly: Bool {
    languageStore.language.isKnowledgeSource
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if showsSourceDirectly {
        sourceContent
      } else if let resolvedName, let resolvedText {
        Text(resolvedName)
          .font(.headline)
          .foregroundStyle(CultureTheme.inkPrimary)
        RichTextBlocksView(document: .plain(resolvedText))
      } else {
        SkeletonLine(height: 14, widthFraction: 0.45)
        SkeletonTextBlock(widthFractions: [1.0, 0.9])
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      CultureTheme.surface,
      in: RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
    )
    .overlay {
      RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
    .task(id: "\(introduction.key)|\(languageStore.language.rawValue)") {
      await reload()
    }
  }

  private var sourceContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(introduction.name)
        .font(.headline)
        .foregroundStyle(CultureTheme.inkPrimary)
      RichTextBlocksView(document: introduction.introduction)
    }
  }

  @MainActor
  private func reload() async {
    resolvedName = nil
    resolvedText = nil
    guard !languageStore.language.isKnowledgeSource else { return }
    let translated = await KnowledgeTranslationService.shared.localizedNameAndText(
      cacheNamespace: "introduction",
      key: introduction.key,
      sourceName: introduction.name,
      sourceText: introduction.introduction.plainText,
      language: languageStore.language
    )
    guard !Task.isCancelled else { return }
    resolvedName = translated.name
    resolvedText = translated.text
  }
}
