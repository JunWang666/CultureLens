import SwiftUI

/// The abstraction ladder above a knowledge element (design 0006 阶段 4):
/// a vertical backbone chain 当前对象 › L1 › L2 … derived from the store's
/// directed `ancestors`, with same-level related chips on each rung.
///
/// Tapping any rung or chip opens its knowledge-element detail, where the
/// ladder re-roots itself on that node — this is how the user「换起点」.
struct AbstractionLadderView: View {
  let rootID: UUID
  let rootName: String
  /// Injectable for previews/tests; defaults to the shared bundled store.
  var store: KnowledgeStore? = KnowledgeStore.shared

  /// Convenience for call sites that still hold a slug or UUID string.
  init(rootKey: String, rootName: String, store: KnowledgeStore? = KnowledgeStore.shared) {
    self.rootID =
      store?.resolveElementID(rootKey)
      ?? UUID(uuidString: rootKey)
      ?? DeterministicID.culturalElement(rootKey)
    self.rootName = rootName
    self.store = store
  }

  init(rootID: UUID, rootName: String, store: KnowledgeStore? = KnowledgeStore.shared) {
    self.rootID = rootID
    self.rootName = rootName
    self.store = store
  }

  /// One displayed rung: the backbone ancestor plus same-level related chips.
  private struct Rung: Identifiable {
    let id: UUID
    let ancestor: AbstractionAncestor
    let siblings: [KnowledgePack.Element]
  }

  private var rungs: [Rung] {
    guard let store, store.element(id: rootID) != nil else { return [] }
    let levels = store.ancestors(id: rootID, maxLevels: 4)
    var pathIDs: Set<UUID> = [rootID]
    var result: [Rung] = []
    var childID = rootID
    for level in levels {
      guard let backbone = level.elements.first else { continue }
      pathIDs.insert(backbone.id)

      // Same-level related: other ancestors at this level plus nodes that
      // share this rung as an upward parent with the previous rung.
      var siblingIDs: [UUID] = level.elements.dropFirst().map(\.id)
      for sibling in store.siblings(id: childID) {
        guard !pathIDs.contains(sibling), !siblingIDs.contains(sibling) else { continue }
        let sharesThisParent = store.upward(id: sibling).contains { $0.id == backbone.id }
        if sharesThisParent {
          siblingIDs.append(sibling)
        }
      }
      let siblingElements = siblingIDs.prefix(4).compactMap { store.element(id: $0) }

      result.append(
        Rung(id: backbone.id, ancestor: backbone, siblings: siblingElements)
      )
      pathIDs.formUnion(siblingIDs)
      childID = backbone.id
    }
    return result
  }

  var body: some View {
    let rungs = rungs
    if !rungs.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        Label("文化脉络", systemImage: "list.bullet.indent")
          .font(CultureTypography.title(.title3))
          .foregroundStyle(CultureTheme.inkPrimary)

        VStack(alignment: .leading, spacing: 0) {
          ladderRow(
            title: rootName,
            titleKey: store?.elementKey(for: rootID) ?? rootID.uuidString.lowercased(),
            subtitle: "当前对象",
            elementID: nil,
            isRoot: true
          )
          ForEach(rungs) { rung in
            connector
            ladderRow(
              title: rung.ancestor.name,
              titleKey: store?.elementKey(for: rung.ancestor.id)
                ?? rung.ancestor.id.uuidString.lowercased(),
              subtitle: rung.ancestor.kind?.rawValue,
              elementID: rung.ancestor.id,
              isRoot: false
            )
            if !rung.siblings.isEmpty {
              siblingChips(rung.siblings)
            }
          }
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("从\(rootName)出发的文化脉络阶梯")
    }
  }

  private var connector: some View {
    Image(systemName: "arrow.up")
      .font(.caption2.weight(.bold))
      .foregroundStyle(CultureTheme.antiqueGold)
      .padding(.leading, 21)
      .padding(.vertical, 2)
  }

  @ViewBuilder
  private func ladderRow(
    title: String,
    titleKey: String,
    subtitle: String?,
    elementID: UUID?,
    isRoot: Bool
  ) -> some View {
    let content = HStack(spacing: 10) {
      Circle()
        .fill(isRoot ? CultureTheme.inkPrimary : CultureTheme.antiqueGold)
        .frame(width: 8, height: 8)
        .padding(.leading, 18)

      VStack(alignment: .leading, spacing: 2) {
        LocalizedPackText(
          source: title,
          cacheNamespace: "element",
          cacheKey: titleKey
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(CultureTheme.inkPrimary)
        .lineLimit(1)
        if let subtitle {
          Text(subtitle)
            .font(.caption2)
            .foregroundStyle(CultureTheme.inkSecondary)
        }
      }

      Spacer(minLength: 8)

      if elementID != nil {
        Image(systemName: "chevron.right")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(CultureTheme.inkSecondary)
      }
    }
    .padding(.vertical, 8)
    .padding(.trailing, 12)
    .background(CultureTheme.surface, in: RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }

    if let elementID {
      NavigationLink(value: AppRoute.knowledgeElement(elementID)) {
        content
      }
      .buttonStyle(.plain)
      .accessibilityLabel("脉络节点 \(title)")
      .accessibilityHint("打开该节点详情，阶梯将以它为起点重新展开")
    } else {
      content
        .accessibilityLabel("当前对象 \(title)")
    }
  }

  private func siblingChips(_ siblings: [KnowledgePack.Element]) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(siblings, id: \.id) { element in
          NavigationLink(value: AppRoute.knowledgeElement(element.id)) {
            LocalizedPackText(
              source: element.name,
              cacheNamespace: "element",
              cacheKey: element.key ?? element.id.uuidString.lowercased()
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(CultureTheme.inkSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(CultureTheme.canvas, in: Capsule())
            .overlay {
              Capsule().stroke(CultureTheme.hairline, lineWidth: 1)
            }
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(.leading, 36)
    .padding(.vertical, 4)
  }
}
