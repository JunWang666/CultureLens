import SwiftUI

/// Renders layered teaching text with optional knowledge-base citations.
struct LayeredExplanationView: View {
  let explanation: LayeredExplanation

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      section(title: "一句话结论", symbol: "text.quote", body: explanation.conclusion)
      section(title: "为什么是它", symbol: "eye", body: explanation.why)
      section(title: "向外延展", symbol: "arrow.triangle.branch", body: explanation.extensionText)

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

  private func section(title: String, symbol: String, body: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: symbol)
        .font(.headline)
        .foregroundStyle(CultureTheme.inkPrimary)
      Text(body)
        .font(.body)
        .foregroundStyle(CultureTheme.inkSecondary)
        .lineSpacing(5)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

enum ExplanationLoadState: Equatable {
  case idle
  case loading
  case loaded(LayeredExplanation)
  case failed(String)
}
