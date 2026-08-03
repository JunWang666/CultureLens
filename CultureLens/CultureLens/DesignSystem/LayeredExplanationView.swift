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
        VStack(alignment: .leading, spacing: 8) {
          Label("引用来源", systemImage: "bookmark")
            .font(.headline)
            .foregroundStyle(CultureTheme.inkPrimary)

          ForEach(explanation.citations) { citation in
            VStack(alignment: .leading, spacing: 4) {
              Text(citation.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CultureTheme.inkPrimary)
              Text(citation.fragment)
                .font(.caption)
                .foregroundStyle(CultureTheme.inkSecondary)
                .lineSpacing(3)
              Text(citation.key)
                .font(.caption2)
                .foregroundStyle(CultureTheme.inkSecondary.opacity(0.8))
            }
            .padding(.vertical, 4)
          }
        }
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
    }
  }
}

enum ExplanationLoadState: Equatable {
  case idle
  case loading
  case loaded(LayeredExplanation)
  case failed(String)
}
