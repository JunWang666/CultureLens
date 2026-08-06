import Foundation

/// On-device recognition pipeline: local knowledge pack lookup → local prompt
/// assembly → Cloudflare AI Gateway → local validation and mapping.
/// Replaces the Go backend (`internal/recognition/pipeline.go` Recognize).
nonisolated struct OnDeviceRecognitionService: Sendable {
  let knowledgeStore: KnowledgeStore?
  let promptAssembler: PromptAssembler
  let gatewayClient: LLMGatewayClient

  init(bundle: Bundle = .main, session: URLSession = .shared) throws {
    // All production packs are ODR and cannot be accessed synchronously during
    // service construction. Ordinary bundle loading remains a test fallback.
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

  func recognize(_ input: RecognitionInput) async throws -> RecognitionResult {
    let requestID = UUID().uuidString.lowercased()
    // Prefer the ODR-delivered packs; injected bundle data remains a test fallback.
    guard let store = await KnowledgePackLoader.shared.store(fallback: knowledgeStore) else {
      throw RecognitionServiceError.localResourcesMissing
    }
    var knowledge = try store.recognitionKnowledge(
      latitude: input.place?.latitude,
      longitude: input.place?.longitude
    )

    // UUID-string candidates for post-LLM resolve / validate / map.
    let knowledgeCandidates = knowledge.elements.map(\.candidateContext)
    let attractionCandidates = knowledge.attractionCandidates.map(\.candidateContext)
    let catalogCandidates = store.catalogCandidateContexts()

    // Short numeric ids for the prompt only (elements and attractions independent).
    var idSession = LLMIDSession()
    idSession.registerElements(knowledge.elements.map(\.id))
    idSession.registerAttractions(knowledge.attractionCandidates.map(\.id))
    // Catalog may be used for name backfill — register so short↔UUID stays coherent
    // if a catalog-only hit is later rewritten through the same session.
    idSession.registerElements(store.sightElements.map(\.id))

    let omitIntroductions =
      knowledge.attractionCandidates.count
      > KnowledgeStore.introductionOmissionAttractionThreshold
    let promptKnowledge = Self.withShortElementIDs(
      knowledgeCandidates,
      session: idSession,
      omitIntroductions: omitIntroductions
    )
    let promptAttractions = Self.withShortAttractionIDs(
      attractionCandidates, session: idSession)

    let language = Self.resolveLanguage(localeIdentifier: input.localeIdentifier)
    let localizedAssembler = promptAssembler.withLanguage(language)
    let userText = try localizedAssembler.userText(
      contextNote: input.contextNote,
      knowledgeCandidates: promptKnowledge,
      attractionCandidates: promptAttractions,
      userKnowledgeStates: input.userKnowledgeStates
    )

    let (rawDecision, modelIdentifier) = try await gatewayClient.recognize(
      systemPrompt: localizedAssembler.systemPrompt,
      userText: userText,
      imageBase64: input.imageBase64
    )

    var decision = rawDecision
    Self.rewriteDecisionKeys(&decision, session: idSession)

    // Prefer ids from the prompt candidates (what the model was allowed to cite).
    RecognitionResponseMapper.resolveKnowledgeReferences(
      &decision,
      candidates: knowledgeCandidates
    )
    // Attraction-first prompts often omit distant exhibit nodes; backfill from
    // the full merged catalog by name so "良渚文化玉琮王" still binds to an id.
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
      forID: decision.culturalElementKey,
      from: catalogCandidates,
      into: &validationCandidates
    )
    for alternative in decision.alternatives {
      Self.appendValidationCandidate(
        forID: alternative.culturalElementKey,
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
      withIDs: ([decision.culturalElementKey]
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

  /// Maps model-returned short ids (or empty) onto pack UUID strings so the
  /// rest of the pipeline validates and maps against UUID candidate `id`s.
  private static func rewriteDecisionKeys(
    _ decision: inout ProviderRecognition,
    session: LLMIDSession
  ) {
    if let uuid = session.resolveElement(decision.culturalElementKey) {
      decision.culturalElementKey = uuid.uuidString
    } else if !decision.culturalElementKey.trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty
    {
      // Unknown / invented id — clear so name backfill can run.
      decision.culturalElementKey = ""
    }

    if let uuid = session.resolveAttraction(decision.attractionKey) {
      decision.attractionKey = uuid.uuidString
    } else if !decision.attractionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      decision.attractionKey = ""
    }

    for index in decision.alternatives.indices {
      let key = decision.alternatives[index].culturalElementKey
      if let uuid = session.resolveElement(key) {
        decision.alternatives[index].culturalElementKey = uuid.uuidString
      } else if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        decision.alternatives[index].culturalElementKey = ""
      }
    }
  }

  private static func withShortElementIDs(
    _ candidates: [KnowledgeCandidateContext],
    session: LLMIDSession,
    omitIntroductions: Bool = false
  ) -> [KnowledgeCandidateContext] {
    candidates.map { candidate in
      let short =
        UUID(uuidString: candidate.id).flatMap { session.shortID(forElement: $0) }
        ?? candidate.id
      let remapped = KnowledgeCandidateContext(
        id: short,
        name: candidate.name,
        introduction: candidate.introduction,
        nearbyContexts: candidate.nearbyContexts
      )
      return omitIntroductions ? remapped.omittingIntroductions() : remapped
    }
  }

  private static func withShortAttractionIDs(
    _ candidates: [AttractionCandidateContext],
    session: LLMIDSession
  ) -> [AttractionCandidateContext] {
    candidates.map { candidate in
      let short =
        UUID(uuidString: candidate.id).flatMap { session.shortID(forAttraction: $0) }
        ?? candidate.id
      let elementShort =
        UUID(uuidString: candidate.culturalElementId).flatMap {
          session.shortID(forElement: $0)
        }
        ?? candidate.culturalElementId
      return AttractionCandidateContext(
        id: short,
        name: candidate.name,
        culturalElementId: elementShort
      )
    }
  }

  private static func appendValidationCandidate(
    forID id: String,
    from catalog: [KnowledgeCandidateContext],
    into candidates: inout [KnowledgeCandidateContext]
  ) {
    guard !id.isEmpty else { return }
    if candidates.contains(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) {
      return
    }
    if let match = catalog.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) {
      candidates.append(match)
    }
  }

  private static func enriching(
    _ knowledge: RecognitionKnowledgeSet,
    withIDs ids: [String],
    store: KnowledgeStore
  ) -> RecognitionKnowledgeSet {
    var enriched = knowledge
    var seen = Set(knowledge.elements.map(\.id))
    for idString in ids {
      guard let uuid = UUID(uuidString: idString) else { continue }
      guard seen.insert(uuid).inserted else { continue }
      guard let element = store.recognitionElement(forID: uuid) else { continue }
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
