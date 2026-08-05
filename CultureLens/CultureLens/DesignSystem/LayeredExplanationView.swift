import SwiftStreamingMarkdown
import SwiftUI

/// Renders a finished knowledge-aware explanation plus source cards.
struct PersonalizedExplanationView: View {
  let explanation: PersonalizedExplanation
  let knowledgeContextSummary: LocalizedStringKey

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      explanationHeader

      MarkdownView(text: explanation.markdown, config: Self.markdownConfig)
        .frame(maxWidth: .infinity, alignment: .leading)

      if !explanation.citations.isEmpty {
        KnowledgeCitationCardsView(citations: explanation.citations)
      }
    }
    .padding(20)
    .background(CultureTheme.surface, in: RoundedRectangle(cornerRadius: CultureTheme.cardRadius))
    .overlay {
      RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
  }

  private var explanationHeader: some View {
    Label(knowledgeContextSummary, systemImage: "person.text.rectangle")
      .font(.caption.weight(.semibold))
      .foregroundStyle(CultureTheme.inkSecondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private static var markdownConfig: MarkdownRenderConfig {
    .default.withShouldAnimateText(value: false)
  }
}

/// Stable streaming surface used while explanation Markdown is arriving.
struct StreamingPersonalizedExplanationView: View {
  let source: GrowingMarkdownSource
  let knowledgeContextSummary: LocalizedStringKey

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label(knowledgeContextSummary, systemImage: "person.text.rectangle")
        .font(.caption.weight(.semibold))
        .foregroundStyle(CultureTheme.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)

      StreamedMarkdownView(source: source, config: Self.markdownConfig)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(20)
    .background(CultureTheme.surface, in: RoundedRectangle(cornerRadius: CultureTheme.cardRadius))
    .overlay {
      RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
  }

  private static var markdownConfig: MarkdownRenderConfig {
    .default.withShouldAnimateText(value: true)
  }
}

enum ExplanationLoadState: Equatable {
  case idle
  case loading(isThinking: Bool)
  case streaming
  case loaded(PersonalizedExplanation)
  case partial(PersonalizedExplanation, message: String)
  case failed(String)
}
