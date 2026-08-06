import SwiftUI

/// Shared「引用来源」card list used by Ask Culture and layered explanations.
struct KnowledgeCitationCardsView: View {
  let citations: [KnowledgeCitation]
  private let selection: Selection

  /// 引文部分默认折叠，点按标题展开。
  @State private var isExpanded = false

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

  /// Only citations whose element key exists in the loaded knowledge pack.
  private var visibleCitations: [KnowledgeCitation] {
    citations.existingInKnowledgeBase()
  }

  var body: some View {
    let visible = visibleCitations
    if !visible.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        Button {
          withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
          }
        } label: {
          HStack(spacing: 6) {
            Text("引用来源")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(CultureTheme.inkPrimary)
            Text("\(visible.count)")
              .font(.caption.weight(.medium))
              .foregroundStyle(CultureTheme.inkSecondary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
              .font(.caption.weight(.semibold))
              .foregroundStyle(CultureTheme.inkSecondary.opacity(0.75))
              .rotationEffect(.degrees(isExpanded ? 90 : 0))
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(isExpanded ? "折叠引用来源" : "展开引用来源")

        if isExpanded {
          ForEach(visible) { citation in
            citationCard(citation)
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
        if let id = citation.elementID() {
          NavigationLink(value: AppRoute.knowledgeElement(id)) {
            cardLabel(citation)
          }
          .buttonStyle(.plain)
          .accessibilityHint("查看知识节点详情")
        } else {
          cardLabel(citation)
        }
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
    LocalizedCitationLabel(citation: citation)
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
              sourceChip(title: source.title, publisher: source.displayPublisher, isLink: true)
            }
            .accessibilityLabel("打开外部资料：\(source.displayPublisher)")
          } else {
            sourceChip(title: source.title, publisher: source.displayPublisher, isLink: false)
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

/// Citation name + fragment resolved through `KnowledgeTranslationService`
/// with one translate call per citation. A two-line skeleton is shown while a
/// translation is in flight; failures fall back to the source text.
private struct LocalizedCitationLabel: View {
  let citation: KnowledgeCitation

  @Environment(AppLanguageStore.self) private var languageStore
  @State private var resolvedName: String?
  @State private var resolvedFragment: String?

  private var showsSourceDirectly: Bool {
    languageStore.language.isKnowledgeSource
  }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 6) {
        if showsSourceDirectly {
          textContent(name: citation.name, fragment: citation.fragment)
        } else if let resolvedName {
          textContent(name: resolvedName, fragment: resolvedFragment ?? citation.fragment)
        } else {
          SkeletonLine(height: 13, widthFraction: 0.55)
          if !citation.fragment.isEmpty {
            SkeletonLine(height: 11, widthFraction: 0.9)
          }
        }
      }
      .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(CultureTheme.inkSecondary.opacity(0.75))
        .padding(.top, 2)
    }
    .contentShape(Rectangle())
    .task(id: "\(citation.key)|\(languageStore.language.rawValue)") {
      await reload()
    }
  }

  private func textContent(name: String, fragment: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(name)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(CultureTheme.inkPrimary)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
      if !fragment.isEmpty {
        Text(fragment)
          .font(.caption)
          .foregroundStyle(CultureTheme.inkSecondary)
          .lineSpacing(3)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @MainActor
  private func reload() async {
    resolvedName = nil
    resolvedFragment = nil
    guard !languageStore.language.isKnowledgeSource else { return }
    let translated = await KnowledgeTranslationService.shared.localizedNameAndText(
      cacheNamespace: "element",
      key: citation.key,
      sourceName: citation.name,
      sourceText: citation.fragment,
      language: languageStore.language
    )
    guard !Task.isCancelled else { return }
    resolvedName = translated.name
    resolvedFragment = translated.text
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
