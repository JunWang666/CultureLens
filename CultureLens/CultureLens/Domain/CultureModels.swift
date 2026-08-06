import Foundation

nonisolated enum ObjectCategory: String, Codable, Hashable {
  case architecture = "建筑构件"
  case artifact = "器物"
  case pattern = "纹样"
  case exhibit = "展品"
  case space = "空间"
  case other = "其他"
}

/// Scannable entity vs abstract cultural knowledge — aligns with
/// 「实体即景点」 in `agents/KNOWLEDGE_PACK_GUIDE.md`.
nonisolated enum ContentRole: String, Codable, Hashable, CaseIterable {
  /// Physical entity listed in `attractions[]` (景点 / 文物 / 遗址).
  case sight = "看点"
  /// Abstract knowledge without a scannable entity (朝代、审美、人物、制度…).
  case history = "文化历史"
}

nonisolated enum ConceptKind: String, Codable, Hashable, CaseIterable {
  case foundation = "基础知识"
  case history = "历史"
  case region = "地域"
  case function = "功能"
  case institution = "制度"
  case aesthetics = "审美"
  case people = "人物"
  case technique = "技法"
  case similar = "相似对象"

  var systemImage: String {
    switch self {
    case .foundation: "books.vertical"
    case .history: "clock"
    case .region: "globe.asia.australia"
    case .function: "hammer"
    case .institution: "building.columns"
    case .aesthetics: "paintpalette"
    case .people: "person.2"
    case .technique: "hand.raised.fingers.spread"
    case .similar: "circle.hexagongrid"
    }
  }
}

nonisolated struct KnowledgeSource: Identifiable, Codable, Hashable {
  let id: UUID
  var title: String
  var publisher: String
  var url: URL?

  /// View-facing publisher name in the active app language.
  var displayPublisher: String {
    KnowledgePublisherDisplay.name(for: publisher)
  }
}

nonisolated struct CultureConcept: Identifiable, Codable, Hashable {
  let id: UUID
  var name: String
  var kind: ConceptKind
  var summary: String
  var detail: String

  var distinctDetail: String? {
    let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedDetail.isEmpty else { return nil }

    let normalizedSummary = summary.filter { !$0.isWhitespace }
    let normalizedDetail = trimmedDetail.filter { !$0.isWhitespace }
    return normalizedSummary == normalizedDetail ? nil : trimmedDetail
  }
}

nonisolated struct CultureObject: Identifiable, Hashable {
  var id: UUID
  /// Pack cultural-element UUID when the object is bound to the knowledge pack.
  var culturalElementID: UUID? = nil
  var canonicalName: String
  var summary: String
  var category: ObjectCategory
  var timePeriod: String?
  var region: String?
  var confidence: Double
  var artworkSymbol: String
  var concepts: [CultureConcept]
  var relations: [CultureRelation]
  var sources: [KnowledgeSource]
}

extension CultureObject: Codable {
  enum CodingKeys: String, CodingKey {
    case id
    case culturalElementID
    case culturalElementKey
    case canonicalName
    case summary
    case category
    case timePeriod
    case region
    case confidence
    case artworkSymbol
    case concepts
    case relations
    case sources
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    if container.contains(.culturalElementID),
      !(try container.decodeNil(forKey: .culturalElementID))
    {
      if let uuid = try? container.decode(UUID.self, forKey: .culturalElementID) {
        culturalElementID = uuid
      } else {
        let raw = try container.decode(String.self, forKey: .culturalElementID)
        culturalElementID = raw.isEmpty
          ? nil
          : DeterministicID.resolveCulturalElementID(from: raw)
      }
    } else if let legacy = try container.decodeIfPresent(String.self, forKey: .culturalElementKey),
      !legacy.isEmpty
    {
      // UUID string or kebab slug (pack IDs are UUIDv5(slug)).
      culturalElementID = DeterministicID.resolveCulturalElementID(from: legacy)
    } else {
      culturalElementID = nil
    }
    canonicalName = try container.decode(String.self, forKey: .canonicalName)
    summary = try container.decode(String.self, forKey: .summary)
    category = try container.decode(ObjectCategory.self, forKey: .category)
    timePeriod = try container.decodeIfPresent(String.self, forKey: .timePeriod)
    region = try container.decodeIfPresent(String.self, forKey: .region)
    confidence = try container.decode(Double.self, forKey: .confidence)
    artworkSymbol = try container.decode(String.self, forKey: .artworkSymbol)
    concepts = try container.decodeIfPresent([CultureConcept].self, forKey: .concepts) ?? []
    relations = try container.decodeIfPresent([CultureRelation].self, forKey: .relations) ?? []
    sources = try container.decodeIfPresent([KnowledgeSource].self, forKey: .sources) ?? []
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encodeIfPresent(culturalElementID, forKey: .culturalElementID)
    try container.encode(canonicalName, forKey: .canonicalName)
    try container.encode(summary, forKey: .summary)
    try container.encode(category, forKey: .category)
    try container.encodeIfPresent(timePeriod, forKey: .timePeriod)
    try container.encodeIfPresent(region, forKey: .region)
    try container.encode(confidence, forKey: .confidence)
    try container.encode(artworkSymbol, forKey: .artworkSymbol)
    try container.encode(concepts, forKey: .concepts)
    try container.encode(relations, forKey: .relations)
    try container.encode(sources, forKey: .sources)
  }
}

nonisolated enum RelationKind: String, Codable, Hashable, CaseIterable {
  case emergedIn = "产生于"
  case locatedIn = "位于"
  case usedFor = "用于"
  case symbolizes = "象征"
  case influencedBy = "受到影响"
  case similarTo = "相似于"
  case composedOf = "组成"
  case prerequisiteFor = "理解前先懂"
  case expresses = "体现"
  case governedBy = "受规制于"
  case explains = "解释"
  case madeWith = "制作采用"
}

nonisolated struct CultureRelation: Identifiable, Codable, Hashable {
  let id: UUID
  var sourceID: UUID
  var targetID: UUID
  var kind: RelationKind
  var explanation: String
}

nonisolated extension CultureObject {
  /// 知识库元素 → 展示用对象（图谱节点页、追问等场景复用扫描结果页）。
  init(knowledgeElement element: KnowledgePack.Element) {
    self.init(
      id: element.id,
      culturalElementID: element.id,
      canonicalName: element.name,
      summary: KnowledgeStore.richTextPlainText(element.introduction),
      category: .other,
      timePeriod: nil,
      region: nil,
      confidence: 1,
      artworkSymbol: "sparkles",
      concepts: [],
      relations: [],
      sources: element.sources.map { $0.asKnowledgeSource() }
    )
  }

  /// 图谱概念 → 展示用对象。
  init(knowledgeConcept concept: CultureConcept, elementID: UUID?) {
    self.init(
      id: concept.id,
      culturalElementID: elementID ?? concept.id,
      canonicalName: concept.name,
      summary: concept.summary,
      category: .other,
      timePeriod: nil,
      region: nil,
      confidence: 1,
      artworkSymbol: concept.kind.systemImage,
      concepts: [],
      relations: [],
      sources: []
    )
  }
}

nonisolated struct PlaceContext: Codable, Hashable, Sendable {
  var latitude: Double
  var longitude: Double
  var accuracyMeters: Double?
  var cityName: String?
  var regionName: String?
  var regionCode: String?
  var displayName: String?
}

/// A nearby point of interest returned by MapKit for one recognition request.
/// It is intentionally request-scoped: scan history continues to persist only
/// the captured/photo coordinate in `PlaceContext`.
nonisolated struct NearbyMapPlaceContext: Codable, Hashable, Sendable {
  var name: String
  var latitude: Double
  var longitude: Double
  var distanceMeters: Double
  var address: String?

  enum CodingKeys: String, CodingKey {
    case name
    case latitude
    case longitude
    case distanceMeters = "distance_meters"
    case address
  }
}

nonisolated struct RecognitionInput: Sendable {
  let imageBase64: String
  var place: PlaceContext?
  /// Apple Maps points of interest near `place`, ordered by distance.
  var nearbyMapPlaces: [NearbyMapPlaceContext]
  var contextNote: String?
  var localeIdentifier: String
  var userKnowledgeStates: [UserKnowledgeStateContext]

  init(
    imageData: Data,
    place: PlaceContext?,
    nearbyMapPlaces: [NearbyMapPlaceContext] = [],
    contextNote: String?,
    localeIdentifier: String,
    userKnowledgeStates: [UserKnowledgeStateContext] = []
  ) {
    imageBase64 = imageData.base64EncodedString()
    self.place = place
    self.nearbyMapPlaces = nearbyMapPlaces
    self.contextNote = contextNote
    self.localeIdentifier = localeIdentifier
    self.userKnowledgeStates = userKnowledgeStates
  }
}

nonisolated struct RecognitionCandidate: Identifiable, Hashable, Sendable {
  let id: UUID
  var attractionID: UUID? = nil
  var culturalElementID: UUID? = nil
  var canonicalName: String
  var category: ObjectCategory
  var confidence: Double
  var rationale: String
  var summary: String? = nil
  var timePeriod: String? = nil
  var region: String? = nil
  var artworkSymbol: String? = nil
  var sources: [KnowledgeSource]? = nil
  var resolutionStatus: String? = nil

  var informativeSummary: String? {
    guard let summary else { return nil }
    let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return Self.normalizedText(trimmed) == Self.normalizedText(rationale)
      ? nil
      : trimmed
  }

  var cultureObject: CultureObject {
    CultureObject(
      id: id,
      culturalElementID: culturalElementID,
      canonicalName: canonicalName,
      summary: informativeSummary ?? Self.missingIntroductionSummary,
      category: category,
      timePeriod: timePeriod,
      region: region,
      confidence: confidence,
      artworkSymbol: artworkSymbol ?? Self.symbol(for: category),
      concepts: [],
      relations: [],
      sources: sources ?? []
    )
  }

  private static func symbol(for category: ObjectCategory) -> String {
    switch category {
    case .architecture: "building.columns.fill"
    case .artifact: "seal.fill"
    case .pattern: "camera.macro"
    case .exhibit: "photo.artframe"
    case .space: "square.3.layers.3d"
    case .other: "sparkles"
    }
  }

  private static var missingIntroductionSummary: String {
    switch AppLanguageStore.currentLanguage() {
    case .english:
      "No attraction introduction available."
    case .zhHans:
      "暂无可展示的景点介绍。"
    }
  }

  private static func normalizedText(_ value: String) -> String {
    value.filter { !$0.isWhitespace }.lowercased()
  }
}

extension RecognitionCandidate: Codable {
  enum CodingKeys: String, CodingKey {
    case id
    case attractionID
    case attractionKey
    case culturalElementID
    case culturalElementKey
    case canonicalName
    case category
    case confidence
    case rationale
    case summary
    case timePeriod
    case region
    case artworkSymbol
    case sources
    case resolutionStatus
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    if container.contains(.attractionID),
      !(try container.decodeNil(forKey: .attractionID))
    {
      if let uuid = try? container.decode(UUID.self, forKey: .attractionID) {
        attractionID = uuid
      } else {
        let raw = try container.decode(String.self, forKey: .attractionID)
        attractionID = raw.isEmpty ? nil : DeterministicID.resolveAttractionID(from: raw)
      }
    } else if let legacy = try container.decodeIfPresent(String.self, forKey: .attractionKey),
      !legacy.isEmpty
    {
      attractionID = DeterministicID.resolveAttractionID(from: legacy)
    } else {
      attractionID = nil
    }
    if container.contains(.culturalElementID),
      !(try container.decodeNil(forKey: .culturalElementID))
    {
      if let uuid = try? container.decode(UUID.self, forKey: .culturalElementID) {
        culturalElementID = uuid
      } else {
        let raw = try container.decode(String.self, forKey: .culturalElementID)
        culturalElementID = raw.isEmpty
          ? nil
          : DeterministicID.resolveCulturalElementID(from: raw)
      }
    } else if let legacy = try container.decodeIfPresent(String.self, forKey: .culturalElementKey),
      !legacy.isEmpty
    {
      culturalElementID = DeterministicID.resolveCulturalElementID(from: legacy)
    } else {
      culturalElementID = nil
    }
    canonicalName = try container.decode(String.self, forKey: .canonicalName)
    category = try container.decode(ObjectCategory.self, forKey: .category)
    confidence = try container.decode(Double.self, forKey: .confidence)
    rationale = try container.decode(String.self, forKey: .rationale)
    summary = try container.decodeIfPresent(String.self, forKey: .summary)
    timePeriod = try container.decodeIfPresent(String.self, forKey: .timePeriod)
    region = try container.decodeIfPresent(String.self, forKey: .region)
    artworkSymbol = try container.decodeIfPresent(String.self, forKey: .artworkSymbol)
    sources = try container.decodeIfPresent([KnowledgeSource].self, forKey: .sources)
    resolutionStatus = try container.decodeIfPresent(String.self, forKey: .resolutionStatus)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encodeIfPresent(attractionID, forKey: .attractionID)
    try container.encodeIfPresent(culturalElementID, forKey: .culturalElementID)
    try container.encode(canonicalName, forKey: .canonicalName)
    try container.encode(category, forKey: .category)
    try container.encode(confidence, forKey: .confidence)
    try container.encode(rationale, forKey: .rationale)
    try container.encodeIfPresent(summary, forKey: .summary)
    try container.encodeIfPresent(timePeriod, forKey: .timePeriod)
    try container.encodeIfPresent(region, forKey: .region)
    try container.encodeIfPresent(artworkSymbol, forKey: .artworkSymbol)
    try container.encodeIfPresent(sources, forKey: .sources)
    try container.encodeIfPresent(resolutionStatus, forKey: .resolutionStatus)
  }
}

nonisolated struct LocationInfluence: Codable, Hashable, Sendable {
  enum Effect: String, Codable, Hashable, Sendable {
    case none
    case reordered
    case narrowed
  }

  var effect: Effect
  var summary: String
}

/// A model-generated observation used only when no existing cultural point is
/// a suitable match for the current photo. It intentionally has no knowledge
/// pack ID or taxonomy: the words describe what is visible, not what is known.
nonisolated struct VisualTag: Identifiable, Codable, Hashable, Sendable {
  var label: String
  var evidence: String

  var id: String { label }
}

nonisolated struct RecognitionResult: Identifiable, Codable, Hashable, Sendable {
  let id: UUID
  var object: CultureObject
  var alternatives: [RecognitionCandidate]
  /// Present only for the freeform visual fallback, never for a pack-backed
  /// object or attraction result.
  var visualTags: [VisualTag] = []
  var rationale: String
  var uncertainty: String?
  var modelIdentifier: String
  var usedPlaceContext: Bool
  var locationInfluence: LocationInfluence?
  var resolutionStatus: String? = nil
  var catalogVersion: String? = nil
  var catalogCandidateCount: Int? = nil

  /// Routes unbound results with model observations to their own UI instead of
  /// presenting a guessed object as a normal culture-detail result.
  var isFreeformVisualResult: Bool {
    resolutionStatus == "unresolved" && !visualTags.isEmpty
  }

  /// Nearby place candidates derived from GPS / introductions (not model guesses).
  var displayAttractionCandidates: [RecognitionCandidate] {
    alternatives.filter { candidate in
      guard candidate.resolutionStatus == "attraction" else { return false }
      guard resolutionStatus == "attraction" else { return true }
      return Self.normalizedName(candidate.canonicalName)
        != Self.normalizedName(object.canonicalName)
    }
  }

  /// Model visual alternatives (2nd/3rd guesses), excluding geographic candidates.
  var displayVisualAlternatives: [RecognitionCandidate] {
    alternatives.filter { candidate in
      let status = candidate.resolutionStatus
      return status != "attraction"
    }
  }

  private static func normalizedName(_ value: String) -> String {
    value.filter { !$0.isWhitespace }.lowercased()
  }
}

/// `visualTags` was introduced after scan-history snapshots had already
/// shipped. Old snapshots intentionally decode to a regular unresolved result.
extension RecognitionResult {
  enum CodingKeys: String, CodingKey {
    case id
    case object
    case alternatives
    case visualTags
    case rationale
    case uncertainty
    case modelIdentifier
    case usedPlaceContext
    case locationInfluence
    case resolutionStatus
    case catalogVersion
    case catalogCandidateCount
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    object = try container.decode(CultureObject.self, forKey: .object)
    alternatives = try container.decode([RecognitionCandidate].self, forKey: .alternatives)
    visualTags = try container.decodeIfPresent([VisualTag].self, forKey: .visualTags) ?? []
    rationale = try container.decode(String.self, forKey: .rationale)
    uncertainty = try container.decodeIfPresent(String.self, forKey: .uncertainty)
    modelIdentifier = try container.decode(String.self, forKey: .modelIdentifier)
    usedPlaceContext = try container.decode(Bool.self, forKey: .usedPlaceContext)
    locationInfluence = try container.decodeIfPresent(LocationInfluence.self, forKey: .locationInfluence)
    resolutionStatus = try container.decodeIfPresent(String.self, forKey: .resolutionStatus)
    catalogVersion = try container.decodeIfPresent(String.self, forKey: .catalogVersion)
    catalogCandidateCount = try container.decodeIfPresent(Int.self, forKey: .catalogCandidateCount)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(object, forKey: .object)
    try container.encode(alternatives, forKey: .alternatives)
    try container.encode(visualTags, forKey: .visualTags)
    try container.encode(rationale, forKey: .rationale)
    try container.encodeIfPresent(uncertainty, forKey: .uncertainty)
    try container.encode(modelIdentifier, forKey: .modelIdentifier)
    try container.encode(usedPlaceContext, forKey: .usedPlaceContext)
    try container.encodeIfPresent(locationInfluence, forKey: .locationInfluence)
    try container.encodeIfPresent(resolutionStatus, forKey: .resolutionStatus)
    try container.encodeIfPresent(catalogVersion, forKey: .catalogVersion)
    try container.encodeIfPresent(catalogCandidateCount, forKey: .catalogCandidateCount)
  }
}

nonisolated struct ScanSession: Identifiable, Sendable {
  let id: UUID
  var imageData: Data
  var result: RecognitionResult
  var place: PlaceContext?
  var createdAt: Date
  var isDemo: Bool
}
