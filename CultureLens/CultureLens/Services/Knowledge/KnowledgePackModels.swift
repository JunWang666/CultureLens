import Foundation

/// Codable models for the bundled knowledge pack
/// (`Resources/KnowledgePack/knowledge-pack.json`), mirroring the Go backend's
/// `content/hangzhou-west-lake.v1.json` export format.
nonisolated struct KnowledgePack: Decodable, Sendable {
  let version: String
  let elements: [Element]
  let attractions: [Attraction]
  let relations: [Relation]
  let introductions: [IntroductionRecord]
  /// Themed exploration tracks. Older packs may omit this field.
  let themes: [Theme]

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

  /// A curated exploration path that binds a set of cultural element keys
  /// and a completion threshold (`minContacted`).
  nonisolated struct Theme: Decodable, Sendable, Identifiable, Hashable {
    var id: String { key }

    let key: String
    let name: String
    let summary: String
    let elementKeys: [String]
    /// Number of theme elements the user must have joined the graph for.
    let minContacted: Int

    init(
      key: String,
      name: String,
      summary: String,
      elementKeys: [String],
      minContacted: Int
    ) {
      self.key = key
      self.name = name
      self.summary = summary
      self.elementKeys = elementKeys
      self.minContacted = minContacted
    }
  }

  enum CodingKeys: String, CodingKey {
    case version
    case elements
    case attractions
    case relations
    case introductions
    case themes
  }

  init(
    version: String,
    elements: [Element],
    attractions: [Attraction],
    relations: [Relation],
    introductions: [IntroductionRecord],
    themes: [Theme] = []
  ) {
    self.version = version
    self.elements = elements
    self.attractions = attractions
    self.relations = relations
    self.introductions = introductions
    self.themes = themes
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decode(String.self, forKey: .version)
    elements = try container.decode([Element].self, forKey: .elements)
    attractions = try container.decode([Attraction].self, forKey: .attractions)
    relations = try container.decode([Relation].self, forKey: .relations)
    introductions = try container.decode([IntroductionRecord].self, forKey: .introductions)
    themes = try container.decodeIfPresent([Theme].self, forKey: .themes) ?? []
  }
}
