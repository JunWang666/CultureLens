import Foundation

enum CultureExplanationError: LocalizedError {
  case knowledgeUnavailable
  case emptyObject

  var errorDescription: String? {
    switch self {
    case .knowledgeUnavailable:
      String(localized: "知识库暂不可用，无法生成讲解。")
    case .emptyObject:
      String(localized: "缺少识别对象，无法生成讲解。")
    }
  }
}

/// Streams knowledge-aware cultural background via `dynamic/chat`, constrained
/// to local knowledge-pack fragments with citations.
nonisolated struct CultureExplanationService: Sendable {
  let knowledgeStore: KnowledgeStore?
  let promptAssembler: PromptAssembler
  let gatewayClient: LLMGatewayClient

  init(bundle: Bundle = .main, session: URLSession = .shared) throws {
    knowledgeStore = try? KnowledgeStore.load(bundle: bundle)
    promptAssembler = try PromptAssembler(bundle: bundle)
    gatewayClient = try LLMGatewayClient(bundle: bundle, session: session)
  }

  init(
    knowledgeStore: KnowledgeStore,
    promptAssembler: PromptAssembler,
    gatewayClient: LLMGatewayClient
  ) {
    self.knowledgeStore = knowledgeStore
    self.promptAssembler = promptAssembler
    self.gatewayClient = gatewayClient
  }

  static func live() -> CultureExplanationService? {
    try? CultureExplanationService()
  }

  func streamExplanation(
    result: RecognitionResult,
    userKnowledgeStates: [UserKnowledgeStateContext],
    siteContext: String?
  ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          guard
            let store = await KnowledgePackLoader.shared.store(
              fallback: self.knowledgeStore)
          else {
            throw CultureExplanationError.knowledgeUnavailable
          }
          let rootID = Self.resolveRootID(object: result.object, store: store)
          let axisContexts = self.axisContexts(
            rootID: rootID,
            store: store,
            object: result.object,
            userKnowledgeStates: userKnowledgeStates
          )
          let fragments = self.knowledgeFragments(
            rootID: rootID,
            neighbors: axisContexts.neighbors,
            relationDimensions: axisContexts.relationDimensions,
            store: store,
            object: result.object,
            siteContext: siteContext
          )
          guard !fragments.isEmpty || !result.object.summary.isEmpty else {
            throw CultureExplanationError.knowledgeUnavailable
          }

          var idSession = LLMIDSession()
          let (
            recognition,
            shortNeighbors,
            shortFragments,
            shortStates,
            shortPath,
            shortMissing,
            shortDimensions
          ) = Self.encodeWithShortIDs(
            result: result,
            rootID: rootID,
            neighbors: axisContexts.neighbors,
            fragments: fragments,
            userKnowledgeStates: axisContexts.relevantKnowledgeStates,
            abstractionPath: axisContexts.abstractionPath,
            missingPrerequisites: axisContexts.missingPrerequisites,
            relationDimensions: axisContexts.relationDimensions,
            store: store,
            session: &idSession
          )

          let assembler = self.promptAssembler.withLanguage(
            AppLanguageStore.currentLanguage())
          let userText = try assembler.explainUserText(
            recognition: recognition,
            neighbors: shortNeighbors,
            knowledgeFragments: shortFragments,
            userKnowledgeStates: shortStates,
            siteContext: siteContext,
            abstractionPath: shortPath,
            missingPrerequisites: shortMissing,
            preferenceProfile: axisContexts.preferenceProfile,
            relationDimensions: shortDimensions,
            userKnowledgeTotalCount: userKnowledgeStates.count
          )
          for try await event in self.gatewayClient.streamAsk(
            systemPrompt: assembler.explainSystemPrompt,
            messages: [ChatTurn(role: .user, content: userText)],
            reasoningEffort: .low
          ) {
            continuation.yield(Self.remapEvent(event, session: idSession))
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  /// Prompt context selected along the abstraction axis (design 0006 阶段 3):
  /// neighbor slots are allocated by direction (upward 2–3, all missing
  /// prerequisites up to 3, lateral 2, then fill to 8) instead of the old
  /// alphabetical first-8, and the payload gains the abstraction path, the
  /// missing-prerequisite closure, a preference profile, and a narrowed
  /// relevant subset of the user's knowledge states.
  ///
  /// Context `key` fields hold pack UUID strings until `encodeWithShortIDs`
  /// remaps them for the model.
  private struct AxisContexts {
    var neighbors: [ExplanationNeighborContext] = []
    var abstractionPath: [AbstractionPathContext] = []
    var missingPrerequisites: [MissingPrerequisiteContext] = []
    var preferenceProfile: [PreferenceProfileContext] = []
    var relationDimensions: [RelationDimensionContext] = []
    var relevantKnowledgeStates: [UserKnowledgeStateContext] = []
  }

  /// Relation dimensions surfaced in the explanation's「关联脉络」section,
  /// each mapped to the knowledge-pack relation kinds that answer it.
  /// `产生于` is taken in both directions (orientation audit pending); the
  /// edge explanation text carries the semantics.
  private static let relationDimensionKinds: [(dimension: String, kinds: Set<RelationKind>)] = [
    ("历史时期", [.emergedIn]),
    ("地域文化", [.locatedIn]),
    ("使用功能", [.usedFor]),
    ("审美观念", [.expresses, .symbolizes, .influencedBy]),
    ("相似对象", [.similarTo]),
  ]

  private static func resolveRootID(
    object: CultureObject,
    store: KnowledgeStore
  ) -> UUID? {
    if let id = object.culturalElementID, store.element(id: id) != nil {
      return id
    }
    if store.element(id: object.id) != nil {
      return object.id
    }
    return nil
  }

  private func axisContexts(
    rootID: UUID?,
    store: KnowledgeStore,
    object: CultureObject,
    userKnowledgeStates: [UserKnowledgeStateContext]
  ) -> AxisContexts {
    var contexts = AxisContexts()
    contexts.preferenceProfile = preferenceProfile(
      from: userKnowledgeStates,
      store: store
    )

    guard let rootID else {
      // No knowledge-pack binding: keep the legacy concept-only neighbors.
      contexts.neighbors = object.concepts.prefix(8).map {
        ExplanationNeighborContext(
          key: $0.id.uuidString,
          name: $0.name,
          relationKind: $0.kind.rawValue,
          explanation: $0.summary
        )
      }
      contexts.relevantKnowledgeStates = userKnowledgeStates
      return contexts
    }

    let knownIDs = Set(
      userKnowledgeStates.compactMap { store.resolveElementID($0.key) }
    )

    // Abstraction path: one backbone ancestor per level, capped at 5.
    contexts.abstractionPath = store.ancestors(id: rootID, maxLevels: 5)
      .compactMap { level -> AbstractionPathContext? in
        guard let backbone = level.elements.first,
          let element = store.element(id: backbone.id)
        else { return nil }
        return AbstractionPathContext(
          key: backbone.id.uuidString,
          name: backbone.name,
          excerpt: Self.excerpt(from: element)
        )
      }

    // Missing prerequisites: full transitive closure minus known, capped at 3.
    let missing = store.missingPrerequisites(id: rootID, known: knownIDs, maxCount: 3)
    contexts.missingPrerequisites = missing.map {
      MissingPrerequisiteContext(
        key: $0.id.uuidString,
        name: $0.name,
        fragment: $0.excerpt
      )
    }

    // Relation dimensions: up to 2 edges per fixed dimension.
    for (dimension, kinds) in Self.relationDimensionKinds {
      for edge in store.edges(id: rootID, kinds: kinds).prefix(2) {
        guard let element = store.element(id: edge.id) else { continue }
        contexts.relationDimensions.append(
          RelationDimensionContext(
            dimension: dimension,
            key: element.id.uuidString,
            name: element.name,
            relationKind: edge.kind?.rawValue,
            explanation: edge.explanation
          )
        )
      }
    }

    // Neighbor slots by axis.
    var chosen: [ExplanationNeighborContext] = []
    var chosenIDs = Set<UUID>()

    func appendEdge(_ edge: DirectedRelationEdge, kindOverride: RelationKind? = nil) {
      guard chosenIDs.insert(edge.id).inserted,
        let element = store.element(id: edge.id)
      else { return }
      chosen.append(
        ExplanationNeighborContext(
          key: element.id.uuidString,
          name: element.name,
          relationKind: (kindOverride ?? edge.kind)?.rawValue,
          explanation: edge.explanation
        )
      )
    }

    for prerequisite in missing {
      appendEdge(
        DirectedRelationEdge(
          id: prerequisite.id,
          kind: .prerequisiteFor,
          explanation: prerequisite.excerpt
        )
      )
    }
    for edge in store.upward(id: rootID).prefix(3) {
      appendEdge(edge)
    }
    for edge in store.lateral(id: rootID).prefix(2) {
      appendEdge(edge)
    }
    // Fill remaining slots with other related elements (legacy behavior).
    if chosen.count < 8 {
      for element in store.relatedElements(forID: rootID, limit: 20) {
        guard chosen.count < 8, !chosenIDs.contains(element.id) else { continue }
        let relation = object.relations.first {
          $0.targetID == element.id || $0.sourceID == element.id
        }
        chosen.append(
          ExplanationNeighborContext(
            key: element.id.uuidString,
            name: element.name,
            relationKind: relation?.kind.rawValue,
            explanation: relation?.explanation
          )
        )
        chosenIDs.insert(element.id)
      }
    }
    contexts.neighbors = chosen

    // Narrow the user states to nodes relevant to this object; the total
    // count travels separately so the model still knows the graph size.
    var relevantIDs = chosenIDs
    relevantIDs.formUnion(
      contexts.abstractionPath.compactMap { UUID(uuidString: $0.key) }
    )
    relevantIDs.formUnion(
      contexts.missingPrerequisites.compactMap { UUID(uuidString: $0.key) }
    )
    relevantIDs.formUnion(
      contexts.relationDimensions.compactMap { UUID(uuidString: $0.key) }
    )
    contexts.relevantKnowledgeStates = userKnowledgeStates.filter {
      guard let id = store.resolveElementID($0.key) else { return false }
      return relevantIDs.contains(id)
    }
    return contexts
  }

  /// Preference profile from the ConceptKind distribution of joined nodes
  /// (design 0006 设计六), top three kinds by count.
  private func preferenceProfile(
    from states: [UserKnowledgeStateContext],
    store: KnowledgeStore
  ) -> [PreferenceProfileContext] {
    var counts: [ConceptKind: Int] = [:]
    for state in states {
      guard let element = store.element(key: state.key) else { continue }
      counts[CulturalElementPresentation.conceptKind(element.conceptKind), default: 0] += 1
    }
    return
      counts
      .sorted { ($0.value, $0.key.rawValue) > ($1.value, $1.key.rawValue) }
      .prefix(3)
      .map { PreferenceProfileContext(kind: $0.key.rawValue, count: $0.value) }
  }

  private static func excerpt(from element: KnowledgePack.Element) -> String {
    let text = KnowledgeStore.richTextPlainText(element.introduction)
    return text.count <= 120 ? text : String(text.prefix(120)) + "…"
  }

  private func knowledgeFragments(
    rootID: UUID?,
    neighbors: [ExplanationNeighborContext],
    relationDimensions: [RelationDimensionContext],
    store: KnowledgeStore,
    object: CultureObject,
    siteContext: String?
  ) -> [ExplanationFragmentContext] {
    var fragments: [ExplanationFragmentContext] = []
    var seen = Set<String>()

    func append(key: String, name: String, text: String) {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, seen.insert(key).inserted else { return }
      fragments.append(ExplanationFragmentContext(key: key, name: name, text: trimmed))
    }

    if let rootID, let element = store.element(id: rootID) {
      append(
        key: element.id.uuidString,
        name: element.name,
        text: KnowledgeStore.richTextPlainText(element.introduction)
      )
    } else {
      append(key: "object", name: object.canonicalName, text: object.summary)
    }

    for neighbor in neighbors {
      if let element = store.element(key: neighbor.key) {
        append(
          key: element.id.uuidString,
          name: element.name,
          text: KnowledgeStore.richTextPlainText(element.introduction)
        )
      } else if let explanation = neighbor.explanation {
        append(key: neighbor.key, name: neighbor.name, text: explanation)
      }
    }

    for dimension in relationDimensions {
      if let element = store.element(key: dimension.key) {
        append(
          key: element.id.uuidString,
          name: element.name,
          text: KnowledgeStore.richTextPlainText(element.introduction)
        )
      } else if let explanation = dimension.explanation {
        append(key: dimension.key, name: dimension.name, text: explanation)
      }
    }

    if let siteContext = siteContext?.trimmingCharacters(in: .whitespacesAndNewlines),
      !siteContext.isEmpty
    {
      append(key: "site_context", name: "现场上下文", text: siteContext)
    }

    return fragments
  }

  /// Registers every element UUID that will appear in the payload and returns
  /// copies whose `key` / `cultural_element_key` fields hold short IDs.
  private static func encodeWithShortIDs(
    result: RecognitionResult,
    rootID: UUID?,
    neighbors: [ExplanationNeighborContext],
    fragments: [ExplanationFragmentContext],
    userKnowledgeStates: [UserKnowledgeStateContext],
    abstractionPath: [AbstractionPathContext],
    missingPrerequisites: [MissingPrerequisiteContext],
    relationDimensions: [RelationDimensionContext],
    store: KnowledgeStore,
    session: inout LLMIDSession
  ) -> (
    ExplanationRecognitionContext,
    [ExplanationNeighborContext],
    [ExplanationFragmentContext],
    [UserKnowledgeStateContext],
    [AbstractionPathContext],
    [MissingPrerequisiteContext],
    [RelationDimensionContext]
  ) {
    var orderedIDs: [UUID] = []
    var seen = Set<UUID>()

    func enqueue(_ id: UUID?) {
      guard let id, seen.insert(id).inserted else { return }
      orderedIDs.append(id)
    }

    enqueue(rootID)
    for neighbor in neighbors {
      enqueue(store.resolveElementID(neighbor.key))
    }
    for fragment in fragments {
      // Non-element sentinel keys (`object`, `site_context`) stay literal.
      enqueue(store.resolveElementID(fragment.key))
    }
    for path in abstractionPath {
      enqueue(store.resolveElementID(path.key))
    }
    for missing in missingPrerequisites {
      enqueue(store.resolveElementID(missing.key))
    }
    for dimension in relationDimensions {
      enqueue(store.resolveElementID(dimension.key))
    }
    for state in userKnowledgeStates {
      enqueue(store.resolveElementID(state.key))
    }

    session.registerElements(orderedIDs)

    func shortKey(_ uuidString: String) -> String {
      guard let id = store.resolveElementID(uuidString),
        let short = session.shortID(forElement: id)
      else { return uuidString }
      return short
    }

    let recognition = ExplanationRecognitionContext(
      result: result,
      culturalElementShortID: rootID.flatMap { session.shortID(forElement: $0) }
    )
    let shortNeighbors = neighbors.map {
      ExplanationNeighborContext(
        key: shortKey($0.key),
        name: $0.name,
        relationKind: $0.relationKind,
        explanation: $0.explanation
      )
    }
    let shortFragments = fragments.map {
      ExplanationFragmentContext(
        key: shortKey($0.key),
        name: $0.name,
        text: $0.text
      )
    }
    let shortStates = userKnowledgeStates.map {
      UserKnowledgeStateContext(
        key: shortKey($0.key),
        name: $0.name,
        level: $0.level
      )
    }
    let shortPath = abstractionPath.map {
      AbstractionPathContext(
        key: shortKey($0.key),
        name: $0.name,
        excerpt: $0.excerpt
      )
    }
    let shortMissing = missingPrerequisites.map {
      MissingPrerequisiteContext(
        key: shortKey($0.key),
        name: $0.name,
        fragment: $0.fragment
      )
    }
    let shortDimensions = relationDimensions.map {
      RelationDimensionContext(
        dimension: $0.dimension,
        key: shortKey($0.key),
        name: $0.name,
        relationKind: $0.relationKind,
        explanation: $0.explanation
      )
    }
    return (
      recognition,
      shortNeighbors,
      shortFragments,
      shortStates,
      shortPath,
      shortMissing,
      shortDimensions
    )
  }

  private static func remapEvent(
    _ event: ChatStreamEvent,
    session: LLMIDSession
  ) -> ChatStreamEvent {
    switch event {
    case .thinking:
      return event
    case .delta(let snapshot):
      return .delta(session.remapElementShortIDs(in: snapshot))
    case .finished(let model, let content):
      return .finished(
        modelIdentifier: model, content: session.remapElementShortIDs(in: content))
    }
  }
}
