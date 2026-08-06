import Foundation

/// Recognition-side knowledge models, mirroring the Go backend's
/// `internal/knowledge/types.go` and `internal/recognition/types.go`.

nonisolated struct NearbyAttractionIntroduction: Sendable, Equatable {
  /// Optional introduction slug from the pack.
  let key: String?
  let name: String
  let introduction: RichTextDocument
  let culturalElementId: UUID
  let culturalElementName: String
  let attractionId: UUID
  /// Optional attraction slug for prompt / display convenience.
  let attractionKey: String?
  let attractionName: String
  let latitude: Double
  let longitude: Double
  let distanceMeters: Double
  let sources: [KnowledgePack.Source]

  init(
    key: String? = nil,
    name: String,
    introduction: RichTextDocument,
    culturalElementId: UUID,
    culturalElementName: String,
    attractionId: UUID,
    attractionKey: String? = nil,
    attractionName: String,
    latitude: Double,
    longitude: Double,
    distanceMeters: Double,
    sources: [KnowledgePack.Source] = []
  ) {
    self.key = key
    self.name = name
    self.introduction = introduction
    self.culturalElementId = culturalElementId
    self.culturalElementName = culturalElementName
    self.attractionId = attractionId
    self.attractionKey = attractionKey
    self.attractionName = attractionName
    self.latitude = latitude
    self.longitude = longitude
    self.distanceMeters = distanceMeters
    self.sources = sources
  }

  /// Stable sort / display identity when slug is absent.
  var sortKey: String { key ?? culturalElementId.uuidString }

  /// Short attraction identity for LLM prompts.
  var attractionPromptID: String { attractionKey ?? attractionId.uuidString.lowercased() }
}

nonisolated struct NearbyIntroductionResult: Sendable, Equatable {
  let introductions: [NearbyAttractionIntroduction]
  let totalMatches: Int
}

nonisolated struct KnowledgeGraphElement: Sendable, Equatable {
  let id: UUID
  /// Optional human-readable slug from the pack.
  let key: String?
  let name: String
  let introduction: RichTextDocument
  /// Optional `ConceptKind.rawValue` from the knowledge pack.
  let conceptKind: String?

  init(
    id: UUID,
    key: String? = nil,
    name: String,
    introduction: RichTextDocument,
    conceptKind: String? = nil
  ) {
    self.id = id
    self.key = key
    self.name = name
    self.introduction = introduction
    self.conceptKind = conceptKind
  }

  /// Convenience for fixtures that still mint identity from a slug.
  init(
    key: String,
    name: String,
    introduction: RichTextDocument,
    conceptKind: String? = nil
  ) {
    self.init(
      id: DeterministicID.culturalElement(key),
      key: key,
      name: name,
      introduction: introduction,
      conceptKind: conceptKind
    )
  }

  var sortKey: String { key ?? id.uuidString }
}

nonisolated struct KnowledgeGraphRelation: Sendable, Equatable {
  let elementId: UUID
  let relatedElementId: UUID
  let kind: String
  let explanation: String

  init(
    elementId: UUID,
    relatedElementId: UUID,
    kind: String,
    explanation: String
  ) {
    self.elementId = elementId
    self.relatedElementId = relatedElementId
    self.kind = kind
    self.explanation = explanation
  }

  /// Convenience for fixtures that still mint identity from slugs.
  init(
    elementKey: String,
    relatedElementKey: String,
    kind: String,
    explanation: String
  ) {
    self.init(
      elementId: DeterministicID.culturalElement(elementKey),
      relatedElementId: DeterministicID.culturalElement(relatedElementKey),
      kind: kind,
      explanation: explanation
    )
  }
}

nonisolated struct RecognitionElement: Sendable {
  let id: UUID
  /// Optional human-readable slug from the pack.
  let key: String?
  let name: String
  let introduction: RichTextDocument
  let nearbyContexts: [NearbyAttractionIntroduction]
  let relatedElements: [KnowledgeGraphElement]
  let graphElements: [KnowledgeGraphElement]
  let graphRelations: [KnowledgeGraphRelation]
  /// Trusted external sources for this element (pack `sources` plus linked
  /// introduction provenance such as Wikipedia / Amap URLs).
  let sources: [KnowledgePack.Source]

  init(
    id: UUID,
    key: String? = nil,
    name: String,
    introduction: RichTextDocument,
    nearbyContexts: [NearbyAttractionIntroduction],
    relatedElements: [KnowledgeGraphElement],
    graphElements: [KnowledgeGraphElement],
    graphRelations: [KnowledgeGraphRelation],
    sources: [KnowledgePack.Source] = []
  ) {
    self.id = id
    self.key = key
    self.name = name
    self.introduction = introduction
    self.nearbyContexts = nearbyContexts
    self.relatedElements = relatedElements
    self.graphElements = graphElements
    self.graphRelations = graphRelations
    self.sources = sources
  }

  /// Convenience for fixtures that still mint identity from a slug.
  init(
    key: String,
    name: String,
    introduction: RichTextDocument,
    nearbyContexts: [NearbyAttractionIntroduction],
    relatedElements: [KnowledgeGraphElement],
    graphElements: [KnowledgeGraphElement],
    graphRelations: [KnowledgeGraphRelation],
    sources: [KnowledgePack.Source] = []
  ) {
    self.init(
      id: DeterministicID.culturalElement(key),
      key: key,
      name: name,
      introduction: introduction,
      nearbyContexts: nearbyContexts,
      relatedElements: relatedElements,
      graphElements: graphElements,
      graphRelations: graphRelations,
      sources: sources
    )
  }

  /// Short identity for LLM prompts (slug when present).
  var promptID: String { key ?? id.uuidString }
}

/// A bundled-pack attraction as a map point ("所有兴趣点"足迹地图), aggregated
/// from the pack's on-site introduction records which carry the coordinates.
/// Identity is per physical location: the same attraction at different sites
/// produces separate points.
nonisolated struct AttractionPoint: Sendable, Hashable, Identifiable {
  /// Namespaced deterministic UUID (attraction id + rounded coordinates).
  let id: UUID
  /// Pack attraction identity.
  let attractionId: UUID
  /// Optional attraction slug from the pack.
  let key: String?
  let name: String
  /// Root cultural element for detail navigation, when resolvable.
  let culturalElementId: UUID?
  let latitude: Double
  let longitude: Double

  init(
    attractionId: UUID,
    key: String? = nil,
    name: String,
    culturalElementId: UUID?,
    latitude: Double,
    longitude: Double
  ) {
    self.id = DeterministicID.attractionPoint(
      attractionId: attractionId,
      latitude: latitude,
      longitude: longitude
    )
    self.attractionId = attractionId
    self.key = key
    self.name = name
    self.culturalElementId = culturalElementId
    self.latitude = latitude
    self.longitude = longitude
  }

  var sortKey: String { key ?? attractionId.uuidString }
}

nonisolated struct AttractionCandidate: Sendable {
  /// Pack attraction identity.
  let id: UUID
  /// Optional attraction slug from the pack.
  let key: String?
  let name: String
  let culturalElementId: UUID
  /// Optional bound-element slug for LLM short ids.
  let culturalElementKey: String?
  let summary: String
  let distanceMeters: Double
  let sources: [KnowledgePack.Source]

  init(
    id: UUID,
    key: String? = nil,
    name: String,
    culturalElementId: UUID,
    culturalElementKey: String? = nil,
    summary: String,
    distanceMeters: Double,
    sources: [KnowledgePack.Source] = []
  ) {
    self.id = id
    self.key = key
    self.name = name
    self.culturalElementId = culturalElementId
    self.culturalElementKey = culturalElementKey
    self.summary = summary
    self.distanceMeters = distanceMeters
    self.sources = sources
  }

  /// Convenience for fixtures that still mint identity from a slug.
  init(
    key: String,
    name: String,
    culturalElementId: UUID,
    culturalElementKey: String? = nil,
    summary: String,
    distanceMeters: Double,
    sources: [KnowledgePack.Source] = []
  ) {
    self.init(
      id: DeterministicID.attraction(key),
      key: key,
      name: name,
      culturalElementId: culturalElementId,
      culturalElementKey: culturalElementKey,
      summary: summary,
      distanceMeters: distanceMeters,
      sources: sources
    )
  }

  /// Short identity for LLM prompts (slug when present).
  var promptID: String { key ?? id.uuidString }

  /// Short cultural-element identity for LLM prompts.
  var culturalElementPromptID: String {
    culturalElementKey ?? culturalElementId.uuidString.lowercased()
  }
}

nonisolated struct RecognitionKnowledgeSet: Sendable {
  let version: String
  let elements: [RecognitionElement]
  let attractionCandidates: [AttractionCandidate]
  let totalElements: Int
  let nearbyContextCount: Int
  let locationMatched: Bool

  /// Appends `element` when its id is missing so post-prompt catalog binding
  /// can still map a resolved object with graph edges.
  func ensuringElement(_ element: RecognitionElement) -> RecognitionKnowledgeSet {
    if elements.contains(where: { $0.id == element.id }) {
      return self
    }
    return RecognitionKnowledgeSet(
      version: version,
      elements: elements + [element],
      attractionCandidates: attractionCandidates,
      totalElements: totalElements,
      nearbyContextCount: nearbyContextCount,
      locationMatched: locationMatched
    )
  }
}

// MARK: - LLM prompt contexts (recognition/types.go JSON shapes)

nonisolated struct PlaceKnowledgeContext: Encodable, Sendable {
  let introductionId: String
  let introductionName: String
  let introduction: RichTextDocument
  let attractionId: String
  let attractionName: String

  enum CodingKeys: String, CodingKey {
    case introductionId = "introduction_id"
    case introductionName = "introduction_name"
    case introduction
    case attractionId = "attraction_id"
    case attractionName = "attraction_name"
  }
}

nonisolated struct KnowledgeCandidateContext: Encodable, Sendable {
  /// Short prompt identity (pack slug when present; not necessarily a UUID).
  let id: String
  let name: String
  let introduction: RichTextDocument
  let nearbyContexts: [PlaceKnowledgeContext]

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case introduction
    case nearbyContexts = "nearby_contexts"
  }

  /// Drop introduction bodies (and nearby contexts) when the prompt would
  /// otherwise include too many nearby attractions.
  func omittingIntroductions() -> KnowledgeCandidateContext {
    KnowledgeCandidateContext(
      id: id,
      name: name,
      introduction: RichTextDocument(schemaVersion: 1, blocks: []),
      nearbyContexts: []
    )
  }

  /// `nearby_contexts` / empty `introduction` omit like Go `omitempty`.
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    if !introduction.blocks.isEmpty {
      try container.encode(introduction, forKey: .introduction)
    }
    if !nearbyContexts.isEmpty {
      try container.encode(nearbyContexts, forKey: .nearbyContexts)
    }
  }
}

nonisolated struct AttractionCandidateContext: Encodable, Sendable {
  /// Short prompt identity (pack slug when present; not necessarily a UUID).
  let id: String
  let name: String
  let culturalElementId: String

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case culturalElementId = "cultural_element_id"
  }
}

extension RecognitionElement {
  /// `knowledgeContext` in pipeline.go: the per-candidate slice.
  /// `id` is the pack element UUID string; `OnDeviceRecognitionService` remaps
  /// to a per-request short numeric id before encoding the prompt.
  nonisolated var candidateContext: KnowledgeCandidateContext {
    KnowledgeCandidateContext(
      id: id.uuidString,
      name: name,
      introduction: introduction,
      nearbyContexts: nearbyContexts.map {
        PlaceKnowledgeContext(
          introductionId: $0.key ?? $0.sortKey,
          introductionName: $0.name,
          introduction: $0.introduction,
          attractionId: $0.attractionId.uuidString,
          attractionName: $0.attractionName
        )
      }
    )
  }
}

extension AttractionCandidate {
  /// `attractionContext` in pipeline.go.
  /// `id` / `culturalElementId` are pack UUID strings; remapped to short ids
  /// for the recognition prompt.
  nonisolated var candidateContext: AttractionCandidateContext {
    AttractionCandidateContext(
      id: id.uuidString,
      name: name,
      culturalElementId: culturalElementId.uuidString
    )
  }
}
