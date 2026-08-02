import Foundation

/// Recognition-side knowledge models, mirroring the Go backend's
/// `internal/knowledge/types.go` and `internal/recognition/types.go`.

nonisolated struct NearbyAttractionIntroduction: Sendable, Equatable {
  let key: String
  let name: String
  let introduction: RichTextDocument
  let culturalElementKey: String
  let culturalElementName: String
  let attractionKey: String
  let attractionName: String
  let latitude: Double
  let longitude: Double
  let distanceMeters: Double
}

nonisolated struct NearbyIntroductionResult: Sendable, Equatable {
  let introductions: [NearbyAttractionIntroduction]
  let totalMatches: Int
}

nonisolated struct KnowledgeGraphElement: Sendable, Equatable {
  let key: String
  let name: String
  let introduction: RichTextDocument
}

nonisolated struct KnowledgeGraphRelation: Sendable, Equatable {
  let elementKey: String
  let relatedElementKey: String
  let kind: String
  let explanation: String
}

nonisolated struct RecognitionElement: Sendable {
  let key: String
  let name: String
  let introduction: RichTextDocument
  let nearbyContexts: [NearbyAttractionIntroduction]
  let relatedElements: [KnowledgeGraphElement]
  let graphElements: [KnowledgeGraphElement]
  let graphRelations: [KnowledgeGraphRelation]
}

nonisolated struct AttractionCandidate: Sendable {
  let key: String
  let name: String
  let culturalElementKey: String
  let summary: String
  let distanceMeters: Double
}

nonisolated struct RecognitionKnowledgeSet: Sendable {
  let version: String
  let elements: [RecognitionElement]
  let attractionCandidates: [AttractionCandidate]
  let totalElements: Int
  let nearbyContextCount: Int
  let locationMatched: Bool
}

// MARK: - LLM prompt contexts (recognition/types.go JSON shapes)

nonisolated struct PlaceKnowledgeContext: Encodable, Sendable {
  let introductionKey: String
  let introductionName: String
  let introduction: RichTextDocument
  let attractionKey: String
  let attractionName: String

  enum CodingKeys: String, CodingKey {
    case introductionKey = "introduction_key"
    case introductionName = "introduction_name"
    case introduction
    case attractionKey = "attraction_key"
    case attractionName = "attraction_name"
  }
}

nonisolated struct KnowledgeCandidateContext: Encodable, Sendable {
  let key: String
  let name: String
  let introduction: RichTextDocument
  let nearbyContexts: [PlaceKnowledgeContext]

  enum CodingKeys: String, CodingKey {
    case key
    case name
    case introduction
    case nearbyContexts = "nearby_contexts"
  }

  /// `nearby_contexts` carries `omitempty` on the Go side; skip it when empty.
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(key, forKey: .key)
    try container.encode(name, forKey: .name)
    try container.encode(introduction, forKey: .introduction)
    if !nearbyContexts.isEmpty {
      try container.encode(nearbyContexts, forKey: .nearbyContexts)
    }
  }
}

nonisolated struct AttractionCandidateContext: Encodable, Sendable {
  let key: String
  let name: String
  let culturalElementKey: String

  enum CodingKeys: String, CodingKey {
    case key
    case name
    case culturalElementKey = "cultural_element_key"
  }
}

extension RecognitionElement {
  /// `knowledgeContext` in pipeline.go: the per-candidate slice sent to the LLM.
  nonisolated var candidateContext: KnowledgeCandidateContext {
    KnowledgeCandidateContext(
      key: key,
      name: name,
      introduction: introduction,
      nearbyContexts: nearbyContexts.map {
        PlaceKnowledgeContext(
          introductionKey: $0.key,
          introductionName: $0.name,
          introduction: $0.introduction,
          attractionKey: $0.attractionKey,
          attractionName: $0.attractionName
        )
      }
    )
  }
}

extension AttractionCandidate {
  /// `attractionContext` in pipeline.go.
  nonisolated var candidateContext: AttractionCandidateContext {
    AttractionCandidateContext(
      key: key,
      name: name,
      culturalElementKey: culturalElementKey
    )
  }
}
