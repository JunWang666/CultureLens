import Foundation

extension ObjectCategory {
  var localizedTitle: String {
    String(localized: String.LocalizationValue(rawValue))
  }
}

extension ConceptKind {
  var localizedTitle: String {
    String(localized: String.LocalizationValue(rawValue))
  }
}

extension RelationKind {
  var localizedTitle: String {
    String(localized: String.LocalizationValue(rawValue))
  }
}

extension KnowledgeLevel {
  var localizedTitle: String {
    String(localized: String.LocalizationValue(rawValue))
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
