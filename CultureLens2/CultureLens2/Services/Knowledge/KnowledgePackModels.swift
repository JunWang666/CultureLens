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
