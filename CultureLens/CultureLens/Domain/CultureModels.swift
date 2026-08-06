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

nonisolated struct CultureObject: Identifiable, Codable, Hashable {
  var id: UUID
  var culturalElementKey: String? = nil
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
      id: DeterministicID.culturalElement(element.key),
      culturalElementKey: element.key,
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
  init(knowledgeConcept concept: CultureConcept, elementKey: String?) {
    self.init(
      id: concept.id,
      culturalElementKey: elementKey,
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

nonisolated struct RecognitionInput: Sendable {
  let imageBase64: String
  var place: PlaceContext?
  var contextNote: String?
  var localeIdentifier: String
  var userKnowledgeStates: [UserKnowledgeStateContext]

  init(
    imageData: Data,
    place: PlaceContext?,
    contextNote: String?,
    localeIdentifier: String,
    userKnowledgeStates: [UserKnowledgeStateContext] = []
  ) {
    imageBase64 = imageData.base64EncodedString()
    self.place = place
    self.contextNote = contextNote
    self.localeIdentifier = localeIdentifier
    self.userKnowledgeStates = userKnowledgeStates
  }
}

nonisolated struct RecognitionCandidate: Identifiable, Codable, Hashable, Sendable {
  let id: UUID
  var attractionKey: String? = nil
  var culturalElementKey: String? = nil
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
      culturalElementKey: culturalElementKey,
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

nonisolated struct LocationInfluence: Codable, Hashable, Sendable {
  enum Effect: String, Codable, Hashable, Sendable {
    case none
    case reordered
    case narrowed
  }

  var effect: Effect
  var summary: String
}

nonisolated struct RecognitionResult: Identifiable, Codable, Hashable, Sendable {
  let id: UUID
  var object: CultureObject
  var alternatives: [RecognitionCandidate]
  var rationale: String
  var uncertainty: String?
  var modelIdentifier: String
  var usedPlaceContext: Bool
  var locationInfluence: LocationInfluence?
  var resolutionStatus: String? = nil
  var catalogVersion: String? = nil
  var catalogCandidateCount: Int? = nil

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

nonisolated struct ScanSession: Identifiable, Sendable {
  let id: UUID
  var imageData: Data
  var result: RecognitionResult
  var place: PlaceContext?
  var createdAt: Date
  var isDemo: Bool
}
