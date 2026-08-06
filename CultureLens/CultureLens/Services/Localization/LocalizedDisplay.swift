import Foundation

// Display names follow the in-app language preference, not the device locale,
// so they resolve via `AppLanguageStore.currentLanguage()` instead of
// `String(localized:)`. `rawValue` stays the persisted/prompt value (Chinese).

nonisolated extension ObjectCategory {
  var localizedTitle: String {
    switch AppLanguageStore.currentLanguage() {
    case .zhHans:
      rawValue
    case .english:
      switch self {
      case .architecture: "Architectural element"
      case .artifact: "Artifact"
      case .pattern: "Pattern"
      case .exhibit: "Exhibit"
      case .space: "Space"
      case .other: "Other"
      }
    }
  }
}

nonisolated extension ConceptKind {
  var localizedTitle: String {
    switch AppLanguageStore.currentLanguage() {
    case .zhHans:
      rawValue
    case .english:
      switch self {
      case .foundation: "Foundation"
      case .history: "History"
      case .region: "Region"
      case .function: "Function"
      case .institution: "Institution"
      case .aesthetics: "Aesthetics"
      case .people: "People"
      case .technique: "Technique"
      case .similar: "Similar objects"
      }
    }
  }
}

nonisolated extension RelationKind {
  var localizedTitle: String {
    switch AppLanguageStore.currentLanguage() {
    case .zhHans:
      rawValue
    case .english:
      switch self {
      case .emergedIn: "Emerged in"
      case .locatedIn: "Located in"
      case .usedFor: "Used for"
      case .symbolizes: "Symbolizes"
      case .influencedBy: "Influenced by"
      case .similarTo: "Similar to"
      case .composedOf: "Composed of"
      case .prerequisiteFor: "Prerequisite for"
      case .expresses: "Expresses"
      case .governedBy: "Governed by"
      case .explains: "Explains"
      case .madeWith: "Made with"
      }
    }
  }
}

nonisolated extension KnowledgeLevel {
  var localizedTitle: String {
    switch AppLanguageStore.currentLanguage() {
    case .zhHans:
      rawValue
    case .english:
      switch self {
      case .contact: "Encountered"
      case .understand: "Understood"
      case .master: "Mastered"
      }
    }
  }

  /// Stable code sent alongside the Chinese raw value in prompts.
  var promptCode: String {
    switch self {
    case .contact: "contact"
    case .understand: "understand"
    case .master: "master"
    }
  }
}
