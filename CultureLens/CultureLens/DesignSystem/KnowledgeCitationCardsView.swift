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
        citationCard(citation)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      CultureTheme.antiqueGold.opacity(0.08),
      in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
  }

  @ViewBuilder
  private func citationCard(_ citation: KnowledgeCitation) -> some View {
    VStack(alignment: .leading, spacing: 10) {
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

      if !citation.sources.isEmpty {
        externalSourcesRow(citation.sources)
      }
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
    .contentShape(Rectangle())
  }

  private func externalSourcesRow(_ sources: [KnowledgeSource]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("外部资料")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(CultureTheme.inkSecondary)

      FlowLayout(spacing: 8) {
        ForEach(sources) { source in
          if let url = source.url {
            Link(destination: url) {
              sourceChip(title: source.title, publisher: source.publisher, isLink: true)
            }
            .accessibilityLabel("打开外部资料：\(source.publisher)")
          } else {
            sourceChip(title: source.title, publisher: source.publisher, isLink: false)
          }
        }
      }
    }
  }

  private func sourceChip(title: String, publisher: String, isLink: Bool) -> some View {
    HStack(spacing: 4) {
      Text(publisher.isEmpty ? title : publisher)
        .font(.caption.weight(.medium))
      if isLink {
        Image(systemName: "arrow.up.right")
          .font(.caption2.weight(.semibold))
      }
    }
    .foregroundStyle(isLink ? CultureTheme.cinnabar : CultureTheme.inkSecondary)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
      CultureTheme.antiqueGold.opacity(0.14),
      in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
  }
}

/// Simple wrapping layout for external-source chips.
private struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var height: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x + size.width > maxWidth, x > 0 {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      rowHeight = max(rowHeight, size.height)
      x += size.width + spacing
      height = max(height, y + rowHeight)
    }
    return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: height)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    var x = bounds.minX
    var y = bounds.minY
    var rowHeight: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x + size.width > bounds.maxX, x > bounds.minX {
        x = bounds.minX
        y += rowHeight + spacing
        rowHeight = 0
      }
      subview.place(
        at: CGPoint(x: x, y: y),
        proposal: ProposedViewSize(size)
      )
      rowHeight = max(rowHeight, size.height)
      x += size.width + spacing
    }
  }
}
