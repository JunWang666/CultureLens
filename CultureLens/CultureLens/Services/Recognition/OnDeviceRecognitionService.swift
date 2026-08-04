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
    let knowledge = try store.recognitionKnowledge(
      latitude: input.place?.latitude,
      longitude: input.place?.longitude,
      limit: 12
    )
    let knowledgeCandidates = knowledge.elements.map { $0.candidateContext }
    let attractionCandidates = knowledge.attractionCandidates.map { $0.candidateContext }
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
    RecognitionResponseMapper.resolveKnowledgeReferences(
      &decision,
      candidates: knowledgeCandidates
    )
    try RecognitionResponseMapper.validate(
      decision,
      candidates: knowledgeCandidates,
      attractions: attractionCandidates
    )
    return RecognitionResponseMapper.mapResponse(
      requestID: requestID,
      usedPlaceContext: input.place != nil,
      decision: decision,
      modelIdentifier: modelIdentifier,
      knowledge: knowledge
    )
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
