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
      visualTagsAreValid(
        decision.visualTags,
        permitsFreeformFallback: decision.culturalElementKey.isEmpty && decision.attractionKey.isEmpty
          && decision.category == "其他"
      ),
      isValidKnowledgeReference(
        id: decision.culturalElementKey,
        name: decision.canonicalName,
        candidates: candidates
      ),
      isValidAttractionReference(id: decision.attractionKey, candidates: attractions)
    else {
      throw invalid()
    }

    var seenNames: Set<String> = [
      decision.canonicalName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    ]
    var seenIDs = Set<String>()
    if !decision.culturalElementKey.isEmpty {
      seenIDs.insert(decision.culturalElementKey.lowercased())
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
          id: candidate.culturalElementKey,
          name: candidate.canonicalName,
          candidates: candidates
        ),
        seenNames.insert(name).inserted
      else {
        throw invalid()
      }
      if !candidate.culturalElementKey.isEmpty,
        !seenIDs.insert(candidate.culturalElementKey.lowercased()).inserted
      {
        throw invalid()
      }
    }
  }

  /// Freeform tags are valid only when the model explicitly found no existing
  /// cultural element *and* no nearby attraction. They are never a hint for
  /// candidate resolution.
  private static func visualTagsAreValid(
    _ tags: [ProviderVisualTag],
    permitsFreeformFallback: Bool
  ) -> Bool {
    guard permitsFreeformFallback else { return tags.isEmpty }
    guard (3...6).contains(tags.count) else { return false }

    var labels = Set<String>()
    for tag in tags {
      let label = tag.label.trimmingCharacters(in: .whitespacesAndNewlines)
      let evidence = tag.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
      guard
        (1...24).contains(label.count),
        (2...140).contains(evidence.count),
        labels.insert(normalizeEntityName(label)).inserted
      else {
        return false
      }
    }
    return true
  }

  private static func isValidAttractionReference(
    id: String,
    candidates: [AttractionCandidateContext]
  ) -> Bool {
    guard !id.isEmpty else { return true }
    return candidates.contains { $0.id.caseInsensitiveCompare(id) == .orderedSame }
  }

  private static func isValidKnowledgeReference(
    id: String,
    name: String,
    candidates: [KnowledgeCandidateContext]
  ) -> Bool {
    guard !id.isEmpty else { return true }
    for candidate in candidates
    where candidate.id.caseInsensitiveCompare(id) == .orderedSame {
      return namesAreCompatible(name, candidate.name)
    }
    return false
  }

  /// Exact match, or one normalized name contains the other (min length 2).
  private static func namesAreCompatible(_ lhs: String, _ rhs: String) -> Bool {
    let left = normalizeEntityName(lhs)
    let right = normalizeEntityName(rhs)
    if left == right { return true }
    guard left.count >= 2, right.count >= 2 else { return false }
    return left.contains(right) || right.contains(left)
  }

  // MARK: - mapResponse (pipeline.go:365-664)

  static func mapResponse(
    requestID: String,
    usedPlaceContext: Bool,
    decision: ProviderRecognition,
    modelIdentifier: String,
    knowledge: RecognitionKnowledgeSet
  ) -> RecognitionResult {
    var elementsByID: [UUID: RecognitionElement] = [:]
    for element in knowledge.elements {
      elementsByID[element.id] = element
    }

    let (object, resolutionStatus) = responseObject(
      requestID: requestID,
      decision: decision,
      elements: elementsByID,
      attractions: knowledge.attractionCandidates
    )

    let uncertainty =
      decision.uncertainty.isEmpty
      ? Self.defaultUncertainty()
      : decision.uncertainty

    var alternatives: [RecognitionCandidate] = []

    // Preserve the model's own 2nd/3rd visual guesses — already validated above.
    for (index, candidate) in decision.alternatives.enumerated() {
      alternatives.append(
        visualCandidate(
          candidate,
          requestID: requestID,
          index: index,
          elements: elementsByID,
          attractions: knowledge.attractionCandidates
        )
      )
    }

    // Append nearby attraction candidates (geographic, not visual).
    var attractionCount = 0
    let decisionAttractionID = UUID(uuidString: decision.attractionKey)
    for attraction in knowledge.attractionCandidates {
      if let decisionAttractionID, attraction.id == decisionAttractionID {
        continue
      }
      alternatives.append(attractionCandidate(attraction))
      attractionCount += 1
      if attractionCount == 3 { break }
    }

    return RecognitionResult(
      id: DeterministicID.v5(name: requestID + ":result"),
      object: object,
      alternatives: alternatives,
      visualTags: decision.visualTags.map {
        VisualTag(label: $0.label, evidence: $0.evidence)
      },
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
    elements: [UUID: RecognitionElement],
    attractions: [AttractionCandidate]
  ) -> (CultureObject, String) {
    let decisionAttractionID = UUID(uuidString: decision.attractionKey)
    let decisionElementID = UUID(uuidString: decision.culturalElementKey)

    // Attraction beats element when the visual target *is* the place.
    // Attraction and element UUIDs differ even when they once shared a slug.
    if let decisionAttractionID {
      for attraction in attractions where attraction.id == decisionAttractionID {
        guard shouldResolveAsAttraction(
          decision: decision,
          attraction: attraction,
          decisionElementID: decisionElementID
        ),
          let element = elements[attraction.culturalElementId]
        else { continue }
        var object = knowledgeCultureObject(element: element, decision: decision)
        object.canonicalName = attraction.name
        return (object, "attraction")
      }
    }

    // Model may only fill cultural_element_key; when the name matches an
    // attraction bound to that element it still means the place, not the concept.
    if let decisionElementID {
      for attraction in attractions where attraction.culturalElementId == decisionElementID {
        guard namesAreCompatible(decision.canonicalName, attraction.name),
          let element = elements[attraction.culturalElementId]
        else { continue }
        var object = knowledgeCultureObject(element: element, decision: decision)
        object.canonicalName = attraction.name
        return (object, "attraction")
      }
    }

    // A model may set attraction_key for "I'm at this museum" while the framed
    // target is an exhibit with a filled cultural_element_key — stay catalog-
    // resolved when the attraction branch above did not fire.
    if let decisionElementID, let element = elements[decisionElementID] {
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

  /// Attraction mapping only when the visual target *is* the place (name match
  /// or spatial category), not when attraction_key is merely scene context.
  private static func shouldResolveAsAttraction(
    decision: ProviderRecognition,
    attraction: AttractionCandidate,
    decisionElementID: UUID?
  ) -> Bool {
    if normalizeEntityName(decision.canonicalName) == normalizeEntityName(attraction.name) {
      return true
    }
    if let decisionElementID, decisionElementID == attraction.culturalElementId {
      return true
    }
    return decision.category == "空间"
      && (decision.canonicalName == "其他" || decision.canonicalName.lowercased() == "other"
        || normalizeEntityName(decision.canonicalName) == normalizeEntityName(attraction.name))
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
      ? fallbackGraphRelations(elementID: element.id, related: element.relatedElements)
      : element.graphRelations
    return CultureObject(
      id: element.id,
      culturalElementID: element.id,
      canonicalName: element.name,
      summary: summary,
      category: ObjectCategory(rawValue: decision.category) ?? .other,
      timePeriod: decision.timePeriod.isEmpty ? nil : decision.timePeriod,
      region: decision.region.isEmpty ? nil : decision.region,
      confidence: decision.confidence,
      artworkSymbol: artworkSymbol(for: decision.category),
      concepts: graphElements.map(graphConcept),
      relations: graphRelations.map(graphRelation),
      sources: element.sources.map { $0.asKnowledgeSource() }
    )
  }

  private static func graphConcept(element: KnowledgeGraphElement) -> CultureConcept {
    CultureConcept(
      id: element.id,
      name: element.name,
      kind: CulturalElementPresentation.conceptKind(element.conceptKind),
      summary: KnowledgeStore.richTextPlainText(element.introduction),
      detail: ""
    )
  }

  private static func graphRelation(edge: KnowledgeGraphRelation) -> CultureRelation {
    CultureRelation(
      id: DeterministicID.v5(
        name: edge.elementId.uuidString + ":" + edge.relatedElementId.uuidString + ":" + edge.kind
      ),
      sourceID: edge.elementId,
      targetID: edge.relatedElementId,
      kind: RelationKind(rawValue: edge.kind) ?? .explains,
      explanation: edge.explanation
    )
  }

  private static func fallbackGraphRelations(
    elementID: UUID,
    related: [KnowledgeGraphElement]
  ) -> [KnowledgeGraphRelation] {
    let explanation: String
    switch AppLanguageStore.currentLanguage() {
    case .english:
      explanation =
        "The culture content library records an explicit link between this object and the concept; the relation type is not yet refined."
    case .zhHans:
      explanation = "文化内容库记录了当前对象与该概念的显式关联；关系类型尚未细分。"
    }
    return related.map {
      KnowledgeGraphRelation(
        elementId: elementID,
        relatedElementId: $0.id,
        kind: "解释",
        explanation: explanation
      )
    }
  }

  private static func visualCandidate(
    _ candidate: ProviderCandidate,
    requestID: String,
    index: Int,
    elements: [UUID: RecognitionElement],
    attractions: [AttractionCandidate]
  ) -> RecognitionCandidate {
    let category = ObjectCategory(rawValue: candidate.category) ?? .other
    let symbol = artworkSymbol(for: candidate.category)
    var summary: String? = nil
    var resolutionStatus = "visual"
    let elementID = UUID(uuidString: candidate.culturalElementKey)

    if let elementID, let element = elements[elementID] {
      let plain = KnowledgeStore.richTextPlainText(element.introduction)
      summary = plain.isEmpty ? nil : plain
      resolutionStatus = "resolved"
    }

    // 视觉备选的名称与附近景点候选一致时，视为命中该景点并带上景点 id。
    // 注意不能按文化元素 id 匹配：景点绑定的元素往往是文化概念，命中元素不等于备选本身是景点。
    let normalizedName = normalizeEntityName(candidate.canonicalName)
    let attractionID = attractions.first {
      normalizeEntityName($0.name) == normalizedName
    }?.id

    return RecognitionCandidate(
      id: DeterministicID.v5(
        name: requestID + ":visual:" + String(index) + ":"
          + candidate.canonicalName.lowercased()
      ),
      attractionID: attractionID,
      culturalElementID: elementID,
      canonicalName: candidate.canonicalName,
      category: category,
      confidence: candidate.confidence,
      rationale: candidate.rationale,
      summary: summary,
      artworkSymbol: symbol,
      resolutionStatus: resolutionStatus
    )
  }

  private static func attractionCandidate(
    _ attraction: AttractionCandidate
  ) -> RecognitionCandidate {
    let rationale: String
    switch AppLanguageStore.currentLanguage() {
    case .english:
      rationale =
        "Listed as a nearby attraction from this scan's location; not yet confirmed by the image."
    case .zhHans:
      rationale = "根据当前位置列出的附近景点，仍需结合画面确认。"
    }
    return RecognitionCandidate(
      id: attraction.id,
      attractionID: attraction.id,
      culturalElementID: attraction.culturalElementId,
      canonicalName: attraction.name,
      category: .space,
      confidence: 0,
      rationale: rationale,
      summary: attraction.summary,
      sources: attraction.sources.map { $0.asKnowledgeSource() },
      resolutionStatus: "attraction"
    )
  }

  private static func locationInfluence(
    usedPlaceContext: Bool,
    knowledge: RecognitionKnowledgeSet
  ) -> LocationInfluence? {
    guard usedPlaceContext else { return nil }
    if knowledge.locationMatched {
      let summary: String
      switch AppLanguageStore.currentLanguage() {
      case .english:
        summary =
          "Matched \(knowledge.nearbyContextCount) nearby attraction introductions and produced \(knowledge.attractionCandidates.count) attraction candidates; cultural elements are explanatory only."
      case .zhHans:
        summary =
          "位置匹配到 \(knowledge.nearbyContextCount) 条景点现场介绍，整理出 \(knowledge.attractionCandidates.count) 个附近景点候选；文化元素仅作为解释知识。"
      }
      return LocationInfluence(
        effect: .reordered,
        summary: summary
      )
    }
    let summary: String
    switch AppLanguageStore.currentLanguage() {
    case .english:
      summary =
        "No nearby attraction introductions matched; the model still judged from the image and \(knowledge.elements.count) cultural-element candidates."
    case .zhHans:
      summary =
        "附近没有匹配到景点现场介绍，模型仍按图片和现有 \(knowledge.elements.count) 条文化元素候选判断。"
    }
    return LocationInfluence(
      effect: .none,
      summary: summary
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

  private static func defaultUncertainty() -> String {
    switch AppLanguageStore.currentLanguage() {
    case .english:
      "This judgment is based on visible features; verify with on-site labels or catalog records when possible."
    case .zhHans:
      "该判断基于可见特征，建议结合现场说明牌或馆藏资料进一步核验。"
    }
  }
}
