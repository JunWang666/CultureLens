import Foundation
import SwiftUI

/// Progress against a knowledge-pack theme's completion condition.
nonisolated struct ThemeProgress: Hashable, Sendable {
  let theme: KnowledgePack.Theme
  /// Element IDs that exist in the loaded pack (missing IDs are omitted).
  let elementIds: [UUID]
  let contactedIds: [UUID]
  let remainingIds: [UUID]

  var contactedCount: Int { contactedIds.count }
  var totalCount: Int { elementIds.count }
  var requiredCount: Int { min(theme.minContacted, totalCount) }

  var fractionComplete: Double {
    guard requiredCount > 0 else { return 1 }
    return min(1, Double(contactedCount) / Double(requiredCount))
  }

  var isComplete: Bool {
    contactedCount >= requiredCount
  }

  var statusText: LocalizedStringKey {
    if isComplete {
      return "已点亮"
    }
    return "已点亮 \(contactedCount)/\(requiredCount)"
  }
}

nonisolated enum ThemeProgressCalculator {
  static func progress(
    for theme: KnowledgePack.Theme,
    contactedElementIds: Set<UUID>,
    knowledgeStore: KnowledgeStore? = nil
  ) -> ThemeProgress {
    let elementIds: [UUID]
    if let knowledgeStore {
      elementIds = theme.elementIds.filter { knowledgeStore.element(id: $0) != nil }
    } else {
      elementIds = theme.elementIds
    }
    let contacted = elementIds.filter { contactedElementIds.contains($0) }
    let remaining = elementIds.filter { !contactedElementIds.contains($0) }
    return ThemeProgress(
      theme: theme,
      elementIds: elementIds,
      contactedIds: contacted,
      remainingIds: remaining
    )
  }

  /// Resolves contacted slug keys / UUID strings through the store when provided.
  static func progress(
    for theme: KnowledgePack.Theme,
    contactedElementKeys: Set<String>,
    knowledgeStore: KnowledgeStore? = nil
  ) -> ThemeProgress {
    let contactedIds = Set(
      contactedElementKeys.compactMap { key -> UUID? in
        if let store = knowledgeStore {
          return store.resolveElementID(key)
        }
        return UUID(uuidString: key) ?? DeterministicID.culturalElement(key)
      }
    )
    return progress(
      for: theme,
      contactedElementIds: contactedIds,
      knowledgeStore: knowledgeStore
    )
  }

  static func progressList(
    themes: [KnowledgePack.Theme],
    contactedElementIds: Set<UUID>,
    knowledgeStore: KnowledgeStore? = nil
  ) -> [ThemeProgress] {
    themes
      .map {
        progress(
          for: $0,
          contactedElementIds: contactedElementIds,
          knowledgeStore: knowledgeStore
        )
      }
      .filter { !$0.elementIds.isEmpty }
  }

  static func progressList(
    themes: [KnowledgePack.Theme],
    contactedElementKeys: Set<String>,
    knowledgeStore: KnowledgeStore? = nil
  ) -> [ThemeProgress] {
    themes
      .map {
        progress(
          for: $0,
          contactedElementKeys: contactedElementKeys,
          knowledgeStore: knowledgeStore
        )
      }
      .filter { !$0.elementIds.isEmpty }
  }
}
