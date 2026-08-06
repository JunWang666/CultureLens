import Foundation
import SwiftUI

/// Three-tier user knowledge of a culture graph node.
nonisolated enum KnowledgeLevel: String, Codable, Hashable, CaseIterable, Sendable {
  case contact = "接触"
  case understand = "理解"
  case master = "掌握"

  var sortRank: Int {
    switch self {
    case .contact: 1
    case .understand: 2
    case .master: 3
    }
  }

  /// Levels treated as "already known" for skip/anchor teaching strategy.
  var isKnownEnoughToSkip: Bool {
    switch self {
    case .contact: false
    case .understand, .master: true
    }
  }

  /// View-layer display name; `rawValue` stays the persisted/prompt code.
  var displayName: LocalizedStringKey {
    switch self {
    case .contact: "接触"
    case .understand: "理解"
    case .master: "掌握"
    }
  }
}

/// How a knowledge progress row was last written.
nonisolated enum KnowledgeProgressSource: String, Codable, Hashable, CaseIterable, Sendable {
  case manual
  case migration
  case scan
  case explanation
  case ask
}

/// Snapshot used by prompt assembly and explanation/chat services.
nonisolated struct UserKnowledgeStateContext: Codable, Hashable, Sendable {
  let key: String
  let name: String
  let level: String

  init(key: String, name: String, level: KnowledgeLevel) {
    self.key = key
    self.name = name
    // Keep Chinese label for legacy prompts; append stable code for i18n prompts.
    self.level = "\(level.rawValue)|\(level.promptCode)"
  }

  init(key: String, name: String, level: String) {
    self.key = key
    self.name = name
    self.level = level
  }
}

/// One cited knowledge-base fragment supporting generated teaching text.
nonisolated struct KnowledgeCitation: Identifiable, Codable, Hashable, Sendable {
  var id: String { "\(key)|\(fragment)" }

  let key: String
  let name: String
  let fragment: String
  /// External trusted sources (Wikipedia, Amap, …) for this knowledge node.
  let sources: [KnowledgeSource]

  init(
    key: String,
    name: String,
    fragment: String,
    sources: [KnowledgeSource] = []
  ) {
    self.key = key
    self.name = name
    self.fragment = fragment
    self.sources = sources
  }
}

extension Array where Element == KnowledgeCitation {
  /// Drops citations whose element key is not in the loaded knowledge pack.
  /// When the store is unavailable, returns an empty list so UI never links to
  /// unverified targets.
  func existingInKnowledgeBase(store: KnowledgeStore? = .shared) -> [KnowledgeCitation] {
    guard let store else { return [] }
    return filter { store.element(key: $0.key) != nil }
  }
}

/// Knowledge-aware cultural background constrained to knowledge-base fragments.
nonisolated struct PersonalizedExplanation: Hashable, Sendable {
  let markdown: String
  let citations: [KnowledgeCitation]
  let modelIdentifier: String
}

nonisolated struct CultureChatReply: Hashable, Sendable {
  let answer: String
  let citations: [KnowledgeCitation]
  let modelIdentifier: String
}
