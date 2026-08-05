import SwiftUI

/// The abstraction ladder above a knowledge element (design 0006 阶段 4):
/// a vertical backbone chain 当前对象 › L1 › L2 … derived from the store's
/// directed `ancestors`, with same-level related chips on each rung.
///
/// Tapping any rung or chip opens its knowledge-element detail, where the
/// ladder re-roots itself on that node — this is how the user「换起点」.
struct AbstractionLadderView: View {
  let rootKey: String
  let rootName: String
  /// Injectable for previews/tests; defaults to the shared bundled store.
  var store: KnowledgeStore? = KnowledgeStore.shared

  /// One displayed rung: the backbone ancestor plus same-level related chips.
  private struct Rung: Identifiable {
    let id: String
    let ancestor: AbstractionAncestor
    let siblings: [KnowledgePack.Element]
  }

  private var rungs: [Rung] {
    guard let store else { return [] }
    let levels = store.ancestors(key: rootKey, maxLevels: 4)
    var pathKeys: Set<String> = [rootKey]
    var result: [Rung] = []
    var childKey = rootKey
    for level in levels {
      guard let backbone = level.elements.first else { continue }
      pathKeys.insert(backbone.key)

      // Same-level related: other ancestors at this level plus nodes that
      // share this rung as an upward parent with the previous rung.
      var siblingKeys: [String] = level.elements.dropFirst().map(\.key)
      for sibling in store.siblings(key: childKey) {
        guard !pathKeys.contains(sibling), !siblingKeys.contains(sibling) else { continue }
        let sharesThisParent = store.upward(key: sibling).contains { $0.key == backbone.key }
        if sharesThisParent {
          siblingKeys.append(sibling)
        }
      }
      let siblingElements = siblingKeys.prefix(4).compactMap { store.element(key: $0) }

      result.append(
        Rung(id: backbone.key, ancestor: backbone, siblings: siblingElements)
      )
      pathKeys.formUnion(siblingKeys)
      childKey = backbone.key
    }
    return result
  }

  var body: some View {
    let rungs = rungs
    if !rungs.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        Label("文化脉络", systemImage: "list.bullet.indent")
          .font(.cultureSerif(.title3))
          .foregroundStyle(CultureTheme.inkPrimary)

        VStack(alignment: .leading, spacing: 0) {
          ladderRow(
            title: rootName,
            subtitle: "当前对象",
            key: nil,
            isRoot: true
          )
          ForEach(rungs) { rung in
            connector
            ladderRow(
              title: rung.ancestor.name,
              subtitle: rung.ancestor.kind?.rawValue,
              key: rung.ancestor.key,
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
    subtitle: String?,
    key: String?,
    isRoot: Bool
  ) -> some View {
    let content = HStack(spacing: 10) {
      Circle()
        .fill(isRoot ? CultureTheme.inkPrimary : CultureTheme.antiqueGold)
        .frame(width: 8, height: 8)
        .padding(.leading, 18)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
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

      if key != nil {
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

    if let key {
      NavigationLink(value: AppRoute.knowledgeElement(key)) {
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
        ForEach(siblings, id: \.key) { element in
          NavigationLink(value: AppRoute.knowledgeElement(element.key)) {
            Text(element.name)
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
          .accessibilityLabel("同级相关 \(element.name)")
        }
      }
      .padding(.leading, 46)
      .padding(.vertical, 4)
    }
  }
}

#Preview {
  NavigationStack {
    ScrollView {
      if let store = KnowledgeStore.shared {
        AbstractionLadderView(
          rootKey: "three-pools-mirroring-moon",
          rootName: "三潭印月",
          store: store
        )
        .padding()
      }
    }
    .background(CultureTheme.canvas)
  }
}
