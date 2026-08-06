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
    case .japanese:
      switch self {
      case .architecture: "建築部材"
      case .artifact: "器物"
      case .pattern: "文様"
      case .exhibit: "展示品"
      case .space: "空間"
      case .other: "その他"
      }
    case .russian:
      switch self {
      case .architecture: "Архитектурный элемент"
      case .artifact: "Артефакт"
      case .pattern: "Орнамент"
      case .exhibit: "Экспонат"
      case .space: "Пространство"
      case .other: "Другое"
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
    case .japanese:
      switch self {
      case .foundation: "基礎"
      case .history: "歴史"
      case .region: "地域"
      case .function: "機能"
      case .institution: "制度"
      case .aesthetics: "美意識"
      case .people: "人物"
      case .technique: "技法"
      case .similar: "類似する対象"
      }
    case .russian:
      switch self {
      case .foundation: "Основа"
      case .history: "История"
      case .region: "Регион"
      case .function: "Функция"
      case .institution: "Институт"
      case .aesthetics: "Эстетика"
      case .people: "Люди"
      case .technique: "Техника"
      case .similar: "Похожие объекты"
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
    case .japanese:
      switch self {
      case .emergedIn: "生じた時代・文脈"
      case .locatedIn: "所在"
      case .usedFor: "用途"
      case .symbolizes: "象徴する"
      case .influencedBy: "影響を受けた"
      case .similarTo: "類似する"
      case .composedOf: "構成される"
      case .prerequisiteFor: "理解の前提"
      case .expresses: "表現する"
      case .governedBy: "規定される"
      case .explains: "説明する"
      case .madeWith: "技法・材料"
      }
    case .russian:
      switch self {
      case .emergedIn: "Возникло в"
      case .locatedIn: "Находится в"
      case .usedFor: "Используется для"
      case .symbolizes: "Символизирует"
      case .influencedBy: "Под влиянием"
      case .similarTo: "Сходно с"
      case .composedOf: "Состоит из"
      case .prerequisiteFor: "Предпосылка для"
      case .expresses: "Выражает"
      case .governedBy: "Регулируется"
      case .explains: "Объясняет"
      case .madeWith: "Сделано с помощью"
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
    case .japanese:
      switch self {
      case .contact: "触れた"
      case .understand: "理解した"
      case .master: "習得した"
      }
    case .russian:
      switch self {
      case .contact: "Встречал"
      case .understand: "Понял"
      case .master: "Освоил"
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
