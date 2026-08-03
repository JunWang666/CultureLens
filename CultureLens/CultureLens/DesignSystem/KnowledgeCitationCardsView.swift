import SwiftUI

/// Shared「引用来源」card list used by Ask Culture and layered explanations.
struct KnowledgeCitationCardsView: View {
  let citations: [KnowledgeCitation]
  private let selection: Selection

  private enum Selection {
    case action((KnowledgeCitation) -> Void)
    case appRoute
  }

  /// Button-driven selection (e.g. Ask Culture sets a navigation item).
  init(citations: [KnowledgeCitation], onSelect: @escaping (KnowledgeCitation) -> Void) {
    self.citations = citations
    self.selection = .action(onSelect)
  }

  /// `NavigationLink` to `AppRoute.knowledgeElement` (layered explanation, scan, etc.).
  init(citations: [KnowledgeCitation]) {
    self.citations = citations
    self.selection = .appRoute
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("引用来源")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(CultureTheme.inkPrimary)

      ForEach(citations) { citation in
        switch selection {
        case .action(let onSelect):
          Button {
            onSelect(citation)
          } label: {
            cardLabel(citation)
          }
          .buttonStyle(.plain)
          .accessibilityHint("查看知识节点详情")
        case .appRoute:
          NavigationLink(value: AppRoute.knowledgeElement(citation.key)) {
            cardLabel(citation)
          }
          .buttonStyle(.plain)
          .accessibilityHint("查看知识节点详情")
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      CultureTheme.antiqueGold.opacity(0.08),
      in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
  }

  private func cardLabel(_ citation: KnowledgeCitation) -> some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 6) {
        Text(citation.name)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(CultureTheme.inkPrimary)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
        if !citation.fragment.isEmpty {
          Text(citation.fragment)
            .font(.caption)
            .foregroundStyle(CultureTheme.inkSecondary)
            .lineSpacing(3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(CultureTheme.inkSecondary.opacity(0.75))
        .padding(.top, 2)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      CultureTheme.canvas.opacity(0.85),
      in: RoundedRectangle(cornerRadius: 14, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}
