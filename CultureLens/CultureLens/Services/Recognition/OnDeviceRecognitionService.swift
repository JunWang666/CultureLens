import Foundation

/// On-device recognition pipeline: local knowledge pack lookup → local prompt
/// assembly → Cloudflare AI Gateway → local validation and mapping.
/// Replaces the Go backend (`internal/recognition/pipeline.go` Recognize).
nonisolated struct OnDeviceRecognitionService: Sendable {
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

  func recognize(_ input: RecognitionInput) async throws -> RecognitionResult {
    let requestID = UUID().uuidString.lowercased()
    // Prefer the ODR-delivered pack when available; fall back to the bundled copy.
    let store = await KnowledgePackLoader.shared.store(fallback: knowledgeStore) ?? knowledgeStore
    var knowledge = try store.recognitionKnowledge(
      latitude: input.place?.latitude,
      longitude: input.place?.longitude
    )
    let knowledgeCandidates = knowledge.elements.map { $0.candidateContext }
    let attractionCandidates = knowledge.attractionCandidates.map { $0.candidateContext }
    let catalogCandidates = store.catalogCandidateContexts()
    let language = Self.resolveLanguage(localeIdentifier: input.localeIdentifier)
    let localizedAssembler = promptAssembler.withLanguage(language)
    let userText = try localizedAssembler.userText(
      contextNote: input.contextNote,
      knowledgeCandidates: knowledgeCandidates,
      attractionCandidates: attractionCandidates,
      userKnowledgeStates: input.userKnowledgeStates
    )

    let (rawDecision, modelIdentifier) = try await gatewayClient.recognize(
      systemPrompt: localizedAssembler.systemPrompt,
      userText: userText,
      imageBase64: input.imageBase64
    )

    var decision = rawDecision
    // Prefer keys from the prompt candidates (what the model was allowed to cite).
    RecognitionResponseMapper.resolveKnowledgeReferences(
      &decision,
      candidates: knowledgeCandidates
    )
    // Attraction-first prompts often omit distant exhibit nodes; backfill from
    // the full merged catalog by name so "良渚文化玉琮王" still binds to a key.
    if decision.culturalElementKey.isEmpty
      || decision.alternatives.contains(where: { $0.culturalElementKey.isEmpty })
    {
      RecognitionResponseMapper.resolveKnowledgeReferences(
        &decision,
        candidates: catalogCandidates
      )
    }

    var validationCandidates = knowledgeCandidates
    Self.appendValidationCandidate(
      forKey: decision.culturalElementKey,
      from: catalogCandidates,
      into: &validationCandidates
    )
    for alternative in decision.alternatives {
      Self.appendValidationCandidate(
        forKey: alternative.culturalElementKey,
        from: catalogCandidates,
        into: &validationCandidates
      )
    }

    try RecognitionResponseMapper.validate(
      decision,
      candidates: validationCandidates,
      attractions: attractionCandidates
    )

    knowledge = Self.enriching(
      knowledge,
      withKeys: ([decision.culturalElementKey]
        + decision.alternatives.map(\.culturalElementKey))
        .filter { !$0.isEmpty },
      store: store
    )

    return RecognitionResponseMapper.mapResponse(
      requestID: requestID,
      usedPlaceContext: input.place != nil,
      decision: decision,
      modelIdentifier: modelIdentifier,
      knowledge: knowledge
    )
  }

  private static func appendValidationCandidate(
    forKey key: String,
    from catalog: [KnowledgeCandidateContext],
    into candidates: inout [KnowledgeCandidateContext]
  ) {
    guard !key.isEmpty else { return }
    if candidates.contains(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
      return
    }
    if let match = catalog.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
      candidates.append(match)
    }
  }

  private static func enriching(
    _ knowledge: RecognitionKnowledgeSet,
    withKeys keys: [String],
    store: KnowledgeStore
  ) -> RecognitionKnowledgeSet {
    var enriched = knowledge
    var seen = Set(knowledge.elements.map { $0.key.lowercased() })
    for key in keys {
      let lowered = key.lowercased()
      guard seen.insert(lowered).inserted else { continue }
      guard let element = store.recognitionElement(forKey: key) else { continue }
      enriched = enriched.ensuringElement(element)
    }
    return enriched
  }

  private static func resolveLanguage(localeIdentifier: String) -> AppLanguage {
    if let exact = AppLanguage(rawValue: localeIdentifier) {
      return exact
    }
    // Accept values like "en_US", "zh_CN", "zh-Hans_US".
    let lowered = localeIdentifier.replacingOccurrences(of: "_", with: "-").lowercased()
    if lowered.hasPrefix("zh") {
      return .zhHans
    }
    if lowered.hasPrefix("en") {
      return .english
    }
    return AppLanguagePreference.system.resolved(
      deviceLocale: Locale(identifier: localeIdentifier)
    )
  }
}
