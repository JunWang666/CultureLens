import SwiftUI

/// A `Text` replacement that resolves one knowledge-pack string through
/// `KnowledgeTranslationService` in the active app language. A nil `cacheKey`
/// means the string was already generated in the target language, and the
/// source language needs no translation — both render the source immediately.
/// Otherwise a shimmering skeleton is shown while translating so
/// source-language content never flashes first. Callers apply `.font` /
/// `.foregroundStyle` / `.lineLimit` externally.
struct LocalizedPackText: View {
  enum Kind {
    case name
    case fragment
  }

  let source: String
  let cacheNamespace: String
  var cacheKey: String? = nil
  var kind: Kind = .name

  @Environment(AppLanguageStore.self) private var languageStore
  @State private var resolved: String?

  private var showsSourceDirectly: Bool {
    cacheKey == nil || languageStore.language.isKnowledgeSource
  }

  var body: some View {
    Group {
      if showsSourceDirectly {
        Text(source)
      } else if let resolved {
        Text(resolved)
      } else {
        skeleton
      }
    }
    .task(id: "\(cacheNamespace)|\(cacheKey ?? "")|\(languageStore.language.rawValue)") {
      await reload()
    }
  }

  @ViewBuilder
  private var skeleton: some View {
    switch kind {
    case .name:
      SkeletonLine(height: 14, widthFraction: 0.45)
    case .fragment:
      VStack(alignment: .leading, spacing: 6) {
        SkeletonLine(height: 12, widthFraction: 1.0)
        SkeletonLine(height: 12, widthFraction: 0.6)
      }
    }
  }

  @MainActor
  private func reload() async {
    resolved = nil
    guard let cacheKey, !languageStore.language.isKnowledgeSource else { return }
    let language = languageStore.language
    let value: String
    switch kind {
    case .name:
      value = await KnowledgeTranslationService.shared.localizedName(
        cacheNamespace: cacheNamespace,
        key: cacheKey,
        sourceName: source,
        language: language
      )
    case .fragment:
      value = await KnowledgeTranslationService.shared.localizedText(
        cacheNamespace: cacheNamespace,
        key: cacheKey,
        sourceText: source,
        language: language
      )
    }
    guard !Task.isCancelled else { return }
    resolved = value
  }
}
