import Foundation

/// Ports the response post-processing of the Go backend's
/// `internal/recognition/pipeline.go`: knowledge reference resolution,
/// provider output validation, and mapping to `RecognitionResult`.
nonisolated enum RecognitionResponseMapper {
  static let validCategories: Set<String> = [
    "建筑构件", "器物", "纹样", "展品", "空间", "其他",
  ]

  /// `normalizeEntityName`: lowercase, then drop all whitespace.
  static func normalizeEntityName(_ value: String) -> String {
    String(value.lowercased().filter { !$0.isWhitespace })
  }

  // MARK: - resolveKnowledgeReferences (pipeline.go:249-266)

  static func resolveKnowledgeReferences(
    _ decision: inout ProviderRecognition,
    candidates: [KnowledgeCandidateContext]
  ) {
    var keyByName: [String: String] = [:]
    for candidate in candidates {
      keyByName[normalizeEntityName(candidate.name)] = candidate.key
    }
    if decision.culturalElementKey.isEmpty {
      decision.culturalElementKey =
        keyByName[normalizeEntityName(decision.canonicalName)] ?? ""
    }
    for index in decision.alternatives.indices
    where decision.alternatives[index].culturalElementKey.isEmpty {
      decision.alternatives[index].culturalElementKey =
        keyByName[normalizeEntityName(decision.alternatives[index].canonicalName)] ?? ""
    }
  }

  // MARK: - validateDecision (pipeline.go:268-364)

  static func validate(
    _ decision: ProviderRecognition,
    candidates: [KnowledgeCandidateContext],
    attractions: [AttractionCandidateContext]
  ) throws {
    func invalid() -> LLMGatewayError { .invalidProviderOutput }

    guard
      !decision.canonicalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !decision.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !decision.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      validCategories.contains(decision.category),
      (0...1).contains(decision.confidence),
      (1...3).contains(decision.alternatives.count),
      isValidKnowledgeReference(
        key: decision.culturalElementKey,
        name: decision.canonicalName,
        candidates: candidates
      ),
      isValidAttractionReference(key: decision.attractionKey, candidates: attractions)
    else {
      throw invalid()
    }

    var seenNames: Set<String> = [
      decision.canonicalName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    ]
    var seenKeys = Set<String>()
    if !decision.culturalElementKey.isEmpty {
      seenKeys.insert(decision.culturalElementKey.lowercased())
    }
    for candidate in decision.alternatives {
      let name = candidate.canonicalName
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
      guard
        !name.isEmpty,
        !candidate.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        validCategories.contains(candidate.category),
        (0...1).contains(candidate.confidence),
        isValidKnowledgeReference(
          key: candidate.culturalElementKey,
          name: candidate.canonicalName,
          candidates: candidates
        ),
        seenNames.insert(name).inserted
      else {
        throw invalid()
      }
      if !candidate.culturalElementKey.isEmpty,
        !seenKeys.insert(candidate.culturalElementKey.lowercased()).inserted
      {
        throw invalid()
      }
    }
  }

  private static func isValidAttractionReference(
    key: String,
    candidates: [AttractionCandidateContext]
  ) -> Bool {
    guard !key.isEmpty else { return true }
    return candidates.contains { $0.key.caseInsensitiveCompare(key) == .orderedSame }
  }

  private static func isValidKnowledgeReference(
    key: String,
    name: String,
    candidates: [KnowledgeCandidateContext]
  ) -> Bool {
    guard !key.isEmpty else { return true }
    for candidate in candidates
    where candidate.key.caseInsensitiveCompare(key) == .orderedSame {
      return normalizeEntityName(name) == normalizeEntityName(candidate.name)
    }
    return false
  }

  // MARK: - mapResponse (pipeline.go:365-664)

  static func mapResponse(
    requestID: String,
    usedPlaceContext: Bool,
    decision: ProviderRecognition,
    modelIdentifier: String,
    knowledge: RecognitionKnowledgeSet
  ) -> RecognitionResult {
    var elementsByKey: [String: RecognitionElement] = [:]
    for element in knowledge.elements {
      elementsByKey[element.key.lowercased()] = element
    }

    let (object, resolutionStatus) = responseObject(
      requestID: requestID,
      decision: decision,
      elements: elementsByKey,
      attractions: knowledge.attractionCandidates
    )

    let uncertainty =
      decision.uncertainty.isEmpty
      ? "该判断基于可见特征，建议结合现场说明牌或馆藏资料进一步核验。"
      : decision.uncertainty

    var alternatives: [RecognitionCandidate] = []
    for attraction in knowledge.attractionCandidates {
      if !decision.attractionKey.isEmpty,
        attraction.key.caseInsensitiveCompare(decision.attractionKey) == .orderedSame
      {
        continue
      }
      alternatives.append(attractionCandidate(attraction))
      if alternatives.count == 3 { break }
    }

    return RecognitionResult(
      id: DeterministicID.v5(name: requestID + ":result"),
      object: object,
      alternatives: alternatives,
      rationale: decision.rationale,
      uncertainty: uncertainty,
      modelIdentifier: modelIdentifier,
      usedPlaceContext: usedPlaceContext,
      locationInfluence: locationInfluence(
        usedPlaceContext: usedPlaceContext,
        knowledge: knowledge
      ),
      resolutionStatus: resolutionStatus,
      catalogVersion: knowledge.version,
      catalogCandidateCount: knowledge.elements.count
    )
  }

  private static func responseObject(
    requestID: String,
    decision: ProviderRecognition,
    elements: [String: RecognitionElement],
    attractions: [AttractionCandidate]
  ) -> (CultureObject, String) {
    if !decision.attractionKey.isEmpty {
      for attraction in attractions
      where attraction.key.caseInsensitiveCompare(decision.attractionKey) == .orderedSame {
        if let element = elements[attraction.culturalElementKey.lowercased()] {
          var object = knowledgeCultureObject(element: element, decision: decision)
          object.canonicalName = attraction.name
          return (object, "attraction")
        }
      }
    }
    if let element = elements[decision.culturalElementKey.lowercased()],
      !decision.culturalElementKey.isEmpty
    {
      return (knowledgeCultureObject(element: element, decision: decision), "resolved")
    }
    return (
      CultureObject(
        id: DeterministicID.v5(
          name: requestID + ":unresolved:" + decision.canonicalName.lowercased()
        ),
        canonicalName: decision.canonicalName,
        summary: decision.summary,
        category: ObjectCategory(rawValue: decision.category) ?? .other,
        timePeriod: decision.timePeriod.isEmpty ? nil : decision.timePeriod,
        region: decision.region.isEmpty ? nil : decision.region,
        confidence: decision.confidence,
        artworkSymbol: artworkSymbol(for: decision.category),
        concepts: [],
        relations: [],
        sources: []
      ),
      "unresolved"
    )
  }

  private static func knowledgeCultureObject(
    element: RecognitionElement,
    decision: ProviderRecognition
  ) -> CultureObject {
    var summary = KnowledgeStore.richTextPlainText(element.introduction)
    if summary.isEmpty {
      summary = decision.summary
    }
    let graphElements =
      element.graphElements.isEmpty ? element.relatedElements : element.graphElements
    let graphRelations =
      element.graphRelations.isEmpty
      ? fallbackGraphRelations(elementKey: element.key, related: element.relatedElements)
      : element.graphRelations
    return CultureObject(
      id: DeterministicID.culturalElement(element.key),
      culturalElementKey: element.key,
      canonicalName: element.name,
      summary: summary,
      category: ObjectCategory(rawValue: decision.category) ?? .other,
      timePeriod: decision.timePeriod.isEmpty ? nil : decision.timePeriod,
      region: decision.region.isEmpty ? nil : decision.region,
      confidence: decision.confidence,
      artworkSymbol: artworkSymbol(for: decision.category),
      concepts: graphElements.map(graphConcept),
      relations: graphRelations.map(graphRelation),
      sources: []
    )
  }

  private static func graphConcept(element: KnowledgeGraphElement) -> CultureConcept {
    CultureConcept(
      id: DeterministicID.culturalElement(element.key),
      name: element.name,
      kind: CulturalElementPresentation.conceptKind(key: element.key, name: element.name),
      summary: KnowledgeStore.richTextPlainText(element.introduction),
      detail: ""
    )
  }

  private static func graphRelation(edge: KnowledgeGraphRelation) -> CultureRelation {
    CultureRelation(
      id: DeterministicID.v5(
        name: edge.elementKey + ":" + edge.relatedElementKey + ":" + edge.kind
      ),
      sourceID: DeterministicID.culturalElement(edge.elementKey),
      targetID: DeterministicID.culturalElement(edge.relatedElementKey),
      kind: RelationKind(rawValue: edge.kind) ?? .explains,
      explanation: edge.explanation
    )
  }

  private static func fallbackGraphRelations(
    elementKey: String,
    related: [KnowledgeGraphElement]
  ) -> [KnowledgeGraphRelation] {
    related.map {
      KnowledgeGraphRelation(
        elementKey: elementKey,
        relatedElementKey: $0.key,
        kind: "解释",
        explanation: "文化内容库记录了当前对象与该概念的显式关联；关系类型尚未细分。"
      )
    }
  }

  private static func attractionCandidate(
    _ attraction: AttractionCandidate
  ) -> RecognitionCandidate {
    RecognitionCandidate(
      id: DeterministicID.v5(name: "attraction:" + attraction.key),
      attractionKey: attraction.key,
      culturalElementKey: attraction.culturalElementKey,
      canonicalName: attraction.name,
      category: .space,
      confidence: 0,
      rationale: "根据当前位置列出的附近景点，仍需结合画面确认。",
      summary: attraction.summary,
      resolutionStatus: "attraction"
    )
  }

  private static func locationInfluence(
    usedPlaceContext: Bool,
    knowledge: RecognitionKnowledgeSet
  ) -> LocationInfluence? {
    guard usedPlaceContext else { return nil }
    if knowledge.locationMatched {
      return LocationInfluence(
        effect: .reordered,
        summary:
          "位置匹配到 \(knowledge.nearbyContextCount) 条景点现场介绍，整理出 \(knowledge.attractionCandidates.count) 个附近景点候选；文化元素仅作为解释知识。"
      )
    }
    return LocationInfluence(
      effect: .none,
      summary:
        "附近没有匹配到景点现场介绍，模型仍按图片和现有 \(knowledge.elements.count) 条文化元素候选判断。"
    )
  }

  /// `artworkSymbol` in pipeline.go.
  static func artworkSymbol(for category: String) -> String {
    switch category {
    case "建筑构件": "building.columns.fill"
    case "器物": "shippingbox.fill"
    case "纹样": "seal.fill"
    case "展品": "photo.on.rectangle.angled"
    case "空间": "map.fill"
    default: "sparkles"
    }
  }
}
