import SwiftUI

/// Loads knowledge-pack text for the active language: pack overlay first,
/// then cached / live `dynamic/chat` translation when overlays are missing.
/// While a translation is in flight a shimmering skeleton is shown instead of
/// the untranslated fallback, so source-language content never flashes first.
struct LocalizedKnowledgeBlocksView: View {
  let elementID: UUID?
  let elementKey: String?
  let fallbackName: String
  let fallbackSummary: String
  var textFont: Font = CultureTypography.body(.title3)
  var textColor: Color = CultureTheme.inkPrimary

  @Environment(AppLanguageStore.self) private var languageStore
  @State private var title: String = ""
  @State private var document: RichTextDocument?
  @State private var isLoading = false

  init(
    elementID: UUID? = nil,
    elementKey: String? = nil,
    fallbackName: String,
    fallbackSummary: String,
    textFont: Font = CultureTypography.body(.title3),
    textColor: Color = CultureTheme.inkPrimary
  ) {
    self.elementID = elementID
    self.elementKey = elementKey
    self.fallbackName = fallbackName
    self.fallbackSummary = fallbackSummary
    self.textFont = textFont
    self.textColor = textColor
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let document, !document.blocks.isEmpty {
        HStack(alignment: .center, spacing: 12) {
          Spacer(minLength: 0)
          SpeakTextButton(
            utteranceID: "knowledge.\(elementID?.uuidString ?? elementKey ?? fallbackName)",
            text: KnowledgeStore.richTextPlainText(document),
            accessibilityLabelKey: "朗读介绍"
          )
        }
        RichTextBlocksView(
          document: document,
          textFont: textFont,
          textColor: textColor
        )
      } else if isLoading {
        SkeletonTextBlock()
      } else {
        HStack(alignment: .top, spacing: 12) {
          Text(fallbackSummary)
            .font(textFont)
            .foregroundStyle(textColor)
            .lineSpacing(6)
            .frame(maxWidth: .infinity, alignment: .leading)
          if !fallbackSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            SpeakTextButton(
              utteranceID: "knowledge.fallback.\(elementID?.uuidString ?? elementKey ?? fallbackName)",
              text: fallbackSummary,
              accessibilityLabelKey: "朗读介绍"
            )
          }
        }
      }
    }
    .task(
      id: "\(elementID?.uuidString ?? "")|\(elementKey ?? "")|\(languageStore.language.rawValue)"
    ) {
      await reload()
    }
  }

  @MainActor
  private func reload() async {
    title = fallbackName
    document = nil
    guard let store = KnowledgeStore.shared else { return }
    let resolvedID =
      elementID
      ?? elementKey.flatMap { store.resolveElementID($0) }
    let resolvedKey =
      resolvedID.flatMap { store.elementKey(for: $0) }
      ?? elementKey
    guard resolvedID != nil || resolvedKey != nil else { return }

    isLoading = true
    defer { isLoading = false }

    let language = languageStore.language
    let localization = KnowledgeLocalization(pack: store.pack)
    let introduction =
      resolvedID.flatMap { store.introductionDocument(elementID: $0) }
      ?? resolvedKey.flatMap { store.introductionDocument(elementKey: $0) }
    let sourcePlain: String
    if let introduction {
      sourcePlain = KnowledgeStore.richTextPlainText(introduction)
    } else {
      sourcePlain = ""
    }
    let sourceName =
      resolvedID.flatMap { store.element(id: $0)?.name }
      ?? resolvedKey.flatMap { store.element(key: $0)?.name }
      ?? fallbackName
    let lookupKey = resolvedKey ?? resolvedID?.uuidString.lowercased() ?? ""

    if language.isKnowledgeSource {
      document = introduction
      title = sourceName
      return
    }

    if !lookupKey.isEmpty,
      let overlay = localization.elementText(key: lookupKey, language: language),
      !overlay.isSourceFallback
    {
      title = overlay.name
      document = overlay.introduction?.preservingImages(from: introduction)
      return
    }

    let localized = await KnowledgeTranslationService.shared.localizedElement(
      key: lookupKey.isEmpty ? (resolvedID?.uuidString.lowercased() ?? "") : lookupKey,
      sourceName: sourceName,
      sourcePlainText: sourcePlain.isEmpty ? fallbackSummary : sourcePlain,
      language: language,
      localization: localization
    )
    guard !localized.isSourceFallback else {
      document = RichTextDocument.plain(fallbackSummary).preservingImages(from: introduction)
      return
    }
    title = localized.name
    document = localized.introduction?.preservingImages(from: introduction)
  }
}
