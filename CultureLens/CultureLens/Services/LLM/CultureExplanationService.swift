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
  let knowledgeStore: KnowledgeStore
  let promptAssembler: PromptAssembler
  let gatewayClient: LLMGatewayClient

  init(bundle: Bundle = .main, session: URLSession = .shared) throws {
    knowledgeStore = try KnowledgeStore.load(bundle: bundle)
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
          let store =
            await KnowledgePackLoader.shared.store(fallback: self.knowledgeStore)
            ?? self.knowledgeStore
          let rootKey = result.object.culturalElementKey
          let axisContexts = self.axisContexts(
            rootKey: rootKey,
            store: store,
            object: result.object,
            userKnowledgeStates: userKnowledgeStates
          )
          let fragments = self.knowledgeFragments(
            rootKey: rootKey,
            neighbors: axisContexts.neighbors,
            store: store,
            object: result.object,
            siteContext: siteContext
          )
          guard !fragments.isEmpty || !result.object.summary.isEmpty else {
            throw CultureExplanationError.knowledgeUnavailable
          }

          let assembler = self.promptAssembler.withLanguage(AppLanguageStore.currentLanguage())
          let userText = try assembler.explainUserText(
            recognition: ExplanationRecognitionContext(result: result),
            neighbors: axisContexts.neighbors,
            knowledgeFragments: fragments,
            userKnowledgeStates: axisContexts.relevantKnowledgeStates,
            siteContext: siteContext,
            abstractionPath: axisContexts.abstractionPath,
            missingPrerequisites: axisContexts.missingPrerequisites,
            preferenceProfile: axisContexts.preferenceProfile,
            userKnowledgeTotalCount: userKnowledgeStates.count
          )
          for try await event in self.gatewayClient.streamAsk(
            systemPrompt: assembler.explainSystemPrompt,
            messages: [ChatTurn(role: .user, content: userText)],
            reasoningEffort: .low
          ) {
            continuation.yield(event)
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
  private struct AxisContexts {
    var neighbors: [ExplanationNeighborContext] = []
    var abstractionPath: [AbstractionPathContext] = []
    var missingPrerequisites: [MissingPrerequisiteContext] = []
    var preferenceProfile: [PreferenceProfileContext] = []
    var relevantKnowledgeStates: [UserKnowledgeStateContext] = []
  }

  private func axisContexts(
    rootKey: String?,
    store: KnowledgeStore,
    object: CultureObject,
    userKnowledgeStates: [UserKnowledgeStateContext]
  ) -> AxisContexts {
    var contexts = AxisContexts()
    contexts.preferenceProfile = preferenceProfile(
      from: userKnowledgeStates,
      store: store
    )

    guard let rootKey else {
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

    let knownKeys = Set(userKnowledgeStates.map(\.key))

    // Abstraction path: one backbone ancestor per level, capped at 5.
    contexts.abstractionPath = store.ancestors(key: rootKey, maxLevels: 5)
      .compactMap { level -> AbstractionPathContext? in
        guard let backbone = level.elements.first,
          let element = store.element(key: backbone.key)
        else { return nil }
        return AbstractionPathContext(
          key: backbone.key,
          name: backbone.name,
          excerpt: Self.excerpt(from: element)
        )
      }

    // Missing prerequisites: full transitive closure minus known, capped at 3.
    let missing = store.missingPrerequisites(key: rootKey, known: knownKeys, maxCount: 3)
    contexts.missingPrerequisites = missing.map {
      MissingPrerequisiteContext(key: $0.key, name: $0.name, fragment: $0.excerpt)
    }

    // Neighbor slots by axis.
    var chosen: [ExplanationNeighborContext] = []
    var chosenKeys = Set<String>()

    func appendEdge(_ edge: DirectedRelationEdge, kindOverride: RelationKind? = nil) {
      guard chosenKeys.insert(edge.key).inserted,
        let element = store.element(key: edge.key)
      else { return }
      chosen.append(
        ExplanationNeighborContext(
          key: element.key,
          name: element.name,
          relationKind: (kindOverride ?? edge.kind)?.rawValue,
          explanation: edge.explanation
        )
      )
    }

    for prerequisite in missing {
      appendEdge(
        DirectedRelationEdge(
          key: prerequisite.key,
          kind: .prerequisiteFor,
          explanation: prerequisite.excerpt
        )
      )
    }
    for edge in store.upward(key: rootKey).prefix(3) {
      appendEdge(edge)
    }
    for edge in store.lateral(key: rootKey).prefix(2) {
      appendEdge(edge)
    }
    // Fill remaining slots with other related elements (legacy behavior).
    if chosen.count < 8 {
      for element in store.relatedElements(forKey: rootKey, limit: 20) {
        guard chosen.count < 8, !chosenKeys.contains(element.key) else { continue }
        let relation = object.relations.first {
          $0.targetID == DeterministicID.culturalElement(element.key)
            || $0.sourceID == DeterministicID.culturalElement(element.key)
        }
        chosen.append(
          ExplanationNeighborContext(
            key: element.key,
            name: element.name,
            relationKind: relation?.kind.rawValue,
            explanation: relation?.explanation
          )
        )
        chosenKeys.insert(element.key)
      }
    }
    contexts.neighbors = chosen

    // Narrow the user states to nodes relevant to this object; the total
    // count travels separately so the model still knows the graph size.
    var relevantKeys = Set(chosen.map(\.key))
    relevantKeys.formUnion(contexts.abstractionPath.map(\.key))
    relevantKeys.formUnion(contexts.missingPrerequisites.map(\.key))
    let relevant = userKnowledgeStates.filter { relevantKeys.contains($0.key) }
    contexts.relevantKnowledgeStates = relevant
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
    return counts
      .sorted { ($0.value, $0.key.rawValue) > ($1.value, $1.key.rawValue) }
      .prefix(3)
      .map { PreferenceProfileContext(kind: $0.key.rawValue, count: $0.value) }
  }

  private static func excerpt(from element: KnowledgePack.Element) -> String {
    let text = KnowledgeStore.richTextPlainText(element.introduction)
    return text.count <= 120 ? text : String(text.prefix(120)) + "…"
  }

  private func knowledgeFragments(
    rootKey: String?,
    neighbors: [ExplanationNeighborContext],
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

    if let rootKey, let element = store.element(key: rootKey) {
      append(
        key: element.key,
        name: element.name,
        text: KnowledgeStore.richTextPlainText(element.introduction)
      )
    } else {
      append(key: "object", name: object.canonicalName, text: object.summary)
    }

    for neighbor in neighbors {
      if let element = store.element(key: neighbor.key) {
        append(
          key: element.key,
          name: element.name,
          text: KnowledgeStore.richTextPlainText(element.introduction)
        )
      } else if let explanation = neighbor.explanation {
        append(key: neighbor.key, name: neighbor.name, text: explanation)
      }
    }

    if let siteContext = siteContext?.trimmingCharacters(in: .whitespacesAndNewlines),
      !siteContext.isEmpty
    {
      append(key: "site_context", name: "现场上下文", text: siteContext)
    }

    return fragments
  }
}
