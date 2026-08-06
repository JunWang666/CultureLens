import Foundation

extension KnowledgePack {
  /// Optional per-locale text overlays. Keys are entity UUID strings (with
  /// legacy slug fallback during migration). Missing entries fall back to the
  /// pack's source-language fields (today: Simplified Chinese). Content may be
  /// absent until packs ship translations; the App then uses
  /// `KnowledgeTranslationService`.
  nonisolated struct LocaleOverlay: Decodable, Sendable {
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

    enum CodingKeys: String, CodingKey {
      case elements
      case attractions
      case introductions
    }
  }

  nonisolated struct LocalizedElementText: Decodable, Sendable {
    let name: String?
    let introduction: RichTextDocument?
  }

  nonisolated struct LocalizedAttractionText: Decodable, Sendable {
    let name: String?
  }

  nonisolated struct LocalizedIntroductionText: Decodable, Sendable {
    let name: String?
    let introduction: RichTextDocument?
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

  // MARK: - Element

  func elementText(id: UUID, language: AppLanguage) -> LocalizedKnowledgeText? {
    guard let element = pack.elements.first(where: { $0.id == id }) else { return nil }
    return elementText(element: element, language: language)
  }

  /// Accepts a UUID string or legacy kebab slug.
  func elementText(key: String, language: AppLanguage) -> LocalizedKnowledgeText? {
    if let uuid = UUID(uuidString: key) {
      return elementText(id: uuid, language: language)
    }
    let needle = key.lowercased()
    guard let element = pack.elements.first(where: {
      $0.key?.lowercased() == needle
    }) else { return nil }
    return elementText(element: element, language: language)
  }

  private func elementText(
    element: KnowledgePack.Element,
    language: AppLanguage
  ) -> LocalizedKnowledgeText {
    if language == sourceLanguage {
      return LocalizedKnowledgeText(
        name: element.name,
        introduction: element.introduction,
        isSourceFallback: false,
        language: language
      )
    }
    if let overlay = localizedElementOverlay(for: element, language: language),
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

  private func localizedElementOverlay(
    for element: KnowledgePack.Element,
    language: AppLanguage
  ) -> KnowledgePack.LocalizedElementText? {
    let map = pack.locales?[language.rawValue]?.elements ?? [:]
    if let byID = map[element.id.uuidString.lowercased()] ?? map[element.id.uuidString] {
      return byID
    }
    if let slug = element.key {
      return map[slug] ?? map[slug.lowercased()]
    }
    return nil
  }

  // MARK: - Attraction

  func attractionName(id: UUID, language: AppLanguage) -> (name: String, isSourceFallback: Bool)? {
    guard let attraction = pack.attractions.first(where: { $0.id == id }) else { return nil }
    return attractionName(attraction: attraction, language: language)
  }

  /// Accepts a UUID string or legacy kebab slug.
  func attractionName(key: String, language: AppLanguage) -> (name: String, isSourceFallback: Bool)? {
    if let uuid = UUID(uuidString: key) {
      return attractionName(id: uuid, language: language)
    }
    let needle = key.lowercased()
    guard let attraction = pack.attractions.first(where: {
      $0.key?.lowercased() == needle
    }) else { return nil }
    return attractionName(attraction: attraction, language: language)
  }

  private func attractionName(
    attraction: KnowledgePack.Attraction,
    language: AppLanguage
  ) -> (name: String, isSourceFallback: Bool) {
    if language == sourceLanguage {
      return (attraction.name, false)
    }
    if let name = localizedAttractionOverlay(for: attraction, language: language)?.name,
      !name.isEmpty
    {
      return (name, false)
    }
    return (attraction.name, true)
  }

  private func localizedAttractionOverlay(
    for attraction: KnowledgePack.Attraction,
    language: AppLanguage
  ) -> KnowledgePack.LocalizedAttractionText? {
    let map = pack.locales?[language.rawValue]?.attractions ?? [:]
    if let byID = map[attraction.id.uuidString.lowercased()] ?? map[attraction.id.uuidString] {
      return byID
    }
    if let slug = attraction.key {
      return map[slug] ?? map[slug.lowercased()]
    }
    return nil
  }

  // MARK: - Introduction

  func introductionText(id: UUID, language: AppLanguage) -> LocalizedKnowledgeText? {
    guard let record = pack.introductions.first(where: { $0.id == id }) else { return nil }
    return introductionText(record: record, language: language)
  }

  /// Accepts a UUID string or legacy kebab slug.
  func introductionText(key: String, language: AppLanguage) -> LocalizedKnowledgeText? {
    if let uuid = UUID(uuidString: key) {
      return introductionText(id: uuid, language: language)
    }
    let needle = key.lowercased()
    guard let record = pack.introductions.first(where: {
      $0.key?.lowercased() == needle
    }) else { return nil }
    return introductionText(record: record, language: language)
  }

  private func introductionText(
    record: KnowledgePack.IntroductionRecord,
    language: AppLanguage
  ) -> LocalizedKnowledgeText {
    if language == sourceLanguage {
      return LocalizedKnowledgeText(
        name: record.name,
        introduction: record.introduction,
        isSourceFallback: false,
        language: language
      )
    }
    if let overlay = localizedIntroductionOverlay(for: record, language: language),
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

  private func localizedIntroductionOverlay(
    for record: KnowledgePack.IntroductionRecord,
    language: AppLanguage
  ) -> KnowledgePack.LocalizedIntroductionText? {
    let map = pack.locales?[language.rawValue]?.introductions ?? [:]
    if let byID = map[record.id.uuidString.lowercased()] ?? map[record.id.uuidString] {
      return byID
    }
    if let slug = record.key {
      return map[slug] ?? map[slug.lowercased()]
    }
    return nil
  }
}
