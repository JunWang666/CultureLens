import Foundation
import SwiftUI

/// Progress against a knowledge-pack theme's completion condition.
nonisolated struct ThemeProgress: Hashable, Sendable {
  let theme: KnowledgePack.Theme
  let contactedKeys: [String]
  let remainingKeys: [String]

  var contactedCount: Int { contactedKeys.count }
  var totalCount: Int { theme.elementKeys.count }
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
      return "已完成"
    }
    return "已点亮 \(contactedCount)/\(requiredCount)"
  }
}

nonisolated enum ThemeProgressCalculator {
  static func progress(
    for theme: KnowledgePack.Theme,
    contactedElementKeys: Set<String>
  ) -> ThemeProgress {
    let contacted = theme.elementKeys.filter { contactedElementKeys.contains($0) }
    let remaining = theme.elementKeys.filter { !contactedElementKeys.contains($0) }
    return ThemeProgress(
      theme: theme,
      contactedKeys: contacted,
      remainingKeys: remaining
    )
  }

  static func progressList(
    themes: [KnowledgePack.Theme],
    contactedElementKeys: Set<String>
  ) -> [ThemeProgress] {
    themes.map { progress(for: $0, contactedElementKeys: contactedElementKeys) }
  }
}
