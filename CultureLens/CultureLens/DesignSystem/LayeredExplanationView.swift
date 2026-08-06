import SwiftStreamingMarkdown
import SwiftUI

/// Renders a finished knowledge-aware explanation plus source cards.
struct PersonalizedExplanationView: View {
  let explanation: PersonalizedExplanation
  let knowledgeContextSummary: LocalizedStringKey
  var isRegenerating = false
  var onRegenerate: (() -> Void)? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      explanationHeader

      MarkdownView(text: explanation.markdown, config: Self.markdownConfig)
        .frame(maxWidth: .infinity, alignment: .leading)

      if !explanation.citations.existingInKnowledgeBase().isEmpty {
        KnowledgeCitationCardsView(citations: explanation.citations)
      }
    }
    .padding(.vertical, 20)
    .overlay(alignment: .top) { EditorialRule() }
    .overlay(alignment: .bottom) { EditorialRule() }
  }

  private var explanationHeader: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Label(knowledgeContextSummary, systemImage: "person.text.rectangle")
        .font(.caption.weight(.semibold))
        .foregroundStyle(CultureTheme.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: 8)

      HStack(spacing: 14) {
        SpeakTextButton(
          utteranceID: "explanation",
          text: explanation.markdown,
          accessibilityLabelKey: "朗读讲解"
        )

        if isRegenerating {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel("正在重新生成讲解")
        } else if let onRegenerate {
          Button("重新生成", systemImage: "arrow.clockwise", action: onRegenerate)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(CultureTheme.cinnabar)
            .accessibilityHint("使用最新文化图谱重新生成并替换当前讲解")
            .accessibilityIdentifier("explanation.regenerate")
        }
      }
    }
  }

  private static var markdownConfig: MarkdownRenderConfig {
    CultureMarkdownStyle.renderConfig(animated: false)
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
    .padding(.vertical, 20)
    .overlay(alignment: .top) { EditorialRule() }
    .overlay(alignment: .bottom) { EditorialRule() }
  }

  private static var markdownConfig: MarkdownRenderConfig {
    CultureMarkdownStyle.renderConfig(animated: true)
  }
}

enum ExplanationLoadState: Equatable {
  case idle
  case loading(isThinking: Bool)
  case streaming
  case loaded(PersonalizedExplanation)
  case regenerating(PersonalizedExplanation)
  case partial(PersonalizedExplanation, message: String)
  case failed(String)
}
