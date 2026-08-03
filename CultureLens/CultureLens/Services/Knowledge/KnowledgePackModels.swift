import Foundation

/// Codable models for the bundled knowledge pack
/// (`Resources/KnowledgePack/knowledge-pack.json`), mirroring the Go backend's
/// `content/hangzhou-west-lake.v1.json` export format.
nonisolated struct KnowledgePack: Decodable, Sendable {
  let version: String
  /// BCP-47 tag for the primary text fields (name / introduction). Defaults to zh-Hans.
  let sourceLanguage: String?
  let elements: [Element]
  let attractions: [Attraction]
  let relations: [Relation]
  let introductions: [IntroductionRecord]
  /// Optional translated overlays keyed by BCP-47 tag (e.g. "en"). May be empty
  /// until multilingual packs ship; runtime falls back to `dynamic/chat` translation.
  let locales: [String: LocaleOverlay]?

  nonisolated struct Element: Decodable, Sendable {
    let key: String
    let name: String
    let introduction: RichTextDocument

    init(key: String, name: String, introduction: RichTextDocument) {
      self.key = key
      self.name = name
      self.introduction = introduction
    }
  }

  nonisolated struct Attraction: Decodable, Sendable {
    let key: String
    let name: String

    init(key: String, name: String) {
      self.key = key
      self.name = name
    }
  }

  nonisolated struct Relation: Decodable, Sendable {
    let elementKey: String
    let relatedElementKey: String

    init(elementKey: String, relatedElementKey: String) {
      self.elementKey = elementKey
      self.relatedElementKey = relatedElementKey
    }
  }

  nonisolated struct IntroductionRecord: Decodable, Sendable {
    let key: String
    let name: String
    let introduction: RichTextDocument
    let culturalElementKey: String
    let attractionKey: String
    let latitude: Double
    let longitude: Double

    init(
      key: String,
      name: String,
      introduction: RichTextDocument,
      culturalElementKey: String,
      attractionKey: String,
      latitude: Double,
      longitude: Double
    ) {
      self.key = key
      self.name = name
      self.introduction = introduction
      self.culturalElementKey = culturalElementKey
      self.attractionKey = attractionKey
      self.latitude = latitude
      self.longitude = longitude
    }
  }

  init(
    version: String,
    sourceLanguage: String? = "zh-Hans",
    elements: [Element],
    attractions: [Attraction],
    relations: [Relation],
    introductions: [IntroductionRecord],
    locales: [String: LocaleOverlay]? = nil
  ) {
    self.version = version
    self.sourceLanguage = sourceLanguage
    self.elements = elements
    self.attractions = attractions
    self.relations = relations
    self.introductions = introductions
    self.locales = locales
  }

  enum CodingKeys: String, CodingKey {
    case version
    case sourceLanguage = "source_language"
    case elements
    case attractions
    case relations
    case introductions
    case locales
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decode(String.self, forKey: .version)
    sourceLanguage = try container.decodeIfPresent(String.self, forKey: .sourceLanguage)
    elements = try container.decode([Element].self, forKey: .elements)
    attractions = try container.decode([Attraction].self, forKey: .attractions)
    relations = try container.decode([Relation].self, forKey: .relations)
    introductions = try container.decode([IntroductionRecord].self, forKey: .introductions)
    locales = try container.decodeIfPresent([String: LocaleOverlay].self, forKey: .locales)
  }
}
