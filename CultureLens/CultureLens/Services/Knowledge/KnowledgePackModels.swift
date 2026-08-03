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

  nonisolated struct Element: Decodable, Sendable {
    let key: String
    let name: String
    let introduction: RichTextDocument
    /// Optional `ConceptKind.rawValue`; omitted in older packs.
    let conceptKind: String?

    init(
      key: String,
      name: String,
      introduction: RichTextDocument,
      conceptKind: String? = nil
    ) {
      self.key = key
      self.name = name
      self.introduction = introduction
      self.conceptKind = conceptKind
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
    /// Optional `RelationKind.rawValue`; omitted in older packs.
    let kind: String?
    /// Human-readable edge gloss; omitted in older packs.
    let explanation: String?

    init(
      elementKey: String,
      relatedElementKey: String,
      kind: String? = nil,
      explanation: String? = nil
    ) {
      self.elementKey = elementKey
      self.relatedElementKey = relatedElementKey
      self.kind = kind
      self.explanation = explanation
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
    elements: [Element],
    attractions: [Attraction],
    relations: [Relation],
    introductions: [IntroductionRecord]
  ) {
    self.version = version
    self.elements = elements
    self.attractions = attractions
    self.relations = relations
    self.introductions = introductions
  }
}
