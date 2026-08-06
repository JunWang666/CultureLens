import SwiftUI

/// Loads knowledge-pack text for the active language: pack overlay first,
/// then cached / live `dynamic/chat` translation when overlays are missing.
/// While a translation is in flight a shimmering skeleton is shown instead of
/// the untranslated fallback, so source-language content never flashes first.
struct LocalizedKnowledgeBlocksView: View {
  let elementKey: String?
  let fallbackName: String
  let fallbackSummary: String
  var textFont: Font = .title3
  var textColor: Color = CultureTheme.inkPrimary

  @Environment(AppLanguageStore.self) private var languageStore
  @State private var title: String = ""
  @State private var document: RichTextDocument?
  @State private var isLoading = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let document, !document.blocks.isEmpty {
        RichTextBlocksView(
          document: document,
          textFont: textFont,
          textColor: textColor
        )
      } else if isLoading {
        SkeletonTextBlock()
      } else {
        Text(fallbackSummary)
          .font(textFont)
          .foregroundStyle(textColor)
          .lineSpacing(6)
      }
    }
    .task(id: "\(elementKey ?? "")|\(languageStore.language.rawValue)") {
      await reload()
    }
  }

  @MainActor
  private func reload() async {
    title = fallbackName
    document = nil
    guard let elementKey,
      let store = KnowledgeStore.shared
    else {
      return
    }

    isLoading = true
    defer { isLoading = false }

    let language = languageStore.language
    let localization = KnowledgeLocalization(pack: store.pack)
    let introduction = store.introductionDocument(elementKey: elementKey)
    let sourcePlain: String
    if let introduction {
      sourcePlain = KnowledgeStore.richTextPlainText(introduction)
    } else {
      sourcePlain = ""
    }
    let sourceName =
      store.pack.elements.first(where: { $0.key == elementKey })?.name ?? fallbackName

    if language.isKnowledgeSource {
      document = introduction
      title = sourceName
      return
    }

    if let overlay = localization.elementText(key: elementKey, language: language),
      !overlay.isSourceFallback
    {
      title = overlay.name
      document = overlay.introduction?.preservingImages(from: introduction)
      return
    }

    let localized = await KnowledgeTranslationService.shared.localizedElement(
      key: elementKey,
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
