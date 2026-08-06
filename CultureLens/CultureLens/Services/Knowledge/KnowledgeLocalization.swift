import Foundation

extension KnowledgePack {
  /// Optional per-locale text overlays. Keys match element / attraction /
  /// introduction keys. Missing entries fall back to the pack's source-language
  /// fields (today: Simplified Chinese). Content may be absent until packs ship
  /// translations; the App then uses `KnowledgeTranslationService`.
  nonisolated struct LocaleOverlay: Codable, Sendable {
    var elements: [String: LocalizedElementText]
    var attractions: [String: LocalizedAttractionText]
    var introductions: [String: LocalizedIntroductionText]

    init(
      elements: [String: LocalizedElementText] = [:],
      attractions: [String: LocalizedAttractionText] = [:],
      introductions: [String: LocalizedIntroductionText] = [:]
    ) {
      self.elements = elements
      self.attractions = attractions
      self.introductions = introductions
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      elements = try container.decodeIfPresent([String: LocalizedElementText].self, forKey: .elements) ?? [:]
      attractions =
        try container.decodeIfPresent([String: LocalizedAttractionText].self, forKey: .attractions)
        ?? [:]
      introductions =
        try container.decodeIfPresent(
          [String: LocalizedIntroductionText].self,
          forKey: .introductions
        ) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      if !elements.isEmpty {
        try container.encode(elements, forKey: .elements)
      }
      if !attractions.isEmpty {
        try container.encode(attractions, forKey: .attractions)
      }
      if !introductions.isEmpty {
        try container.encode(introductions, forKey: .introductions)
      }
    }

    enum CodingKeys: String, CodingKey {
      case elements
      case attractions
      case introductions
    }
  }

  nonisolated struct LocalizedElementText: Codable, Sendable {
    let name: String?
    let introduction: RichTextDocument?

    init(name: String? = nil, introduction: RichTextDocument? = nil) {
      self.name = name
      self.introduction = introduction
    }
  }

  nonisolated struct LocalizedAttractionText: Codable, Sendable {
    let name: String?

    init(name: String? = nil) {
      self.name = name
    }
  }

  nonisolated struct LocalizedIntroductionText: Codable, Sendable {
    let name: String?
    let introduction: RichTextDocument?

    init(name: String? = nil, introduction: RichTextDocument? = nil) {
      self.name = name
      self.introduction = introduction
    }
  }
}

/// Resolved display text for a knowledge entity in a target language.
nonisolated struct LocalizedKnowledgeText: Sendable, Hashable {
  let name: String
  let introduction: RichTextDocument?
  /// True when text came from source language without a pack overlay or cache.
  let isSourceFallback: Bool
  let language: AppLanguage
}

/// Looks up pack locale overlays; does not call the network.
nonisolated struct KnowledgeLocalization: Sendable {
  let pack: KnowledgePack
  let sourceLanguage: AppLanguage

  init(pack: KnowledgePack, sourceLanguage: AppLanguage = .knowledgeSource) {
    self.pack = pack
    self.sourceLanguage = sourceLanguage
  }

  func elementText(key: String, language: AppLanguage) -> LocalizedKnowledgeText? {
    guard let element = pack.elements.first(where: { $0.key == key }) else { return nil }
    if language == sourceLanguage {
      return LocalizedKnowledgeText(
        name: element.name,
        introduction: element.introduction,
        isSourceFallback: false,
        language: language
      )
    }
    if let overlay = pack.locales?[language.rawValue]?.elements[key],
      let name = overlay.name, !name.isEmpty
    {
      return LocalizedKnowledgeText(
        name: name,
        introduction: overlay.introduction ?? element.introduction,
        isSourceFallback: overlay.introduction == nil,
        language: language
      )
    }
    return LocalizedKnowledgeText(
      name: element.name,
      introduction: element.introduction,
      isSourceFallback: true,
      language: sourceLanguage
    )
  }

  func attractionName(key: String, language: AppLanguage) -> (name: String, isSourceFallback: Bool)? {
    guard let attraction = pack.attractions.first(where: { $0.key == key }) else { return nil }
    if language == sourceLanguage {
      return (attraction.name, false)
    }
    if let name = pack.locales?[language.rawValue]?.attractions[key]?.name, !name.isEmpty {
      return (name, false)
    }
    return (attraction.name, true)
  }

  func introductionText(key: String, language: AppLanguage) -> LocalizedKnowledgeText? {
    guard let record = pack.introductions.first(where: { $0.key == key }) else { return nil }
    if language == sourceLanguage {
      return LocalizedKnowledgeText(
        name: record.name,
        introduction: record.introduction,
        isSourceFallback: false,
        language: language
      )
    }
    if let overlay = pack.locales?[language.rawValue]?.introductions[key],
      let name = overlay.name, !name.isEmpty
    {
      return LocalizedKnowledgeText(
        name: name,
        introduction: overlay.introduction ?? record.introduction,
        isSourceFallback: overlay.introduction == nil,
        language: language
      )
    }
    return LocalizedKnowledgeText(
      name: record.name,
      introduction: record.introduction,
      isSourceFallback: true,
      language: sourceLanguage
    )
  }
}
