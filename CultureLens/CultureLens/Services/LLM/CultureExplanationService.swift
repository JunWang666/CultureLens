import Foundation

enum CultureExplanationError: LocalizedError {
  case knowledgeUnavailable
  case emptyObject

  var errorDescription: String? {
    switch self {
    case .knowledgeUnavailable:
      "知识库暂不可用，无法生成讲解。"
    case .emptyObject:
      "缺少识别对象，无法生成讲解。"
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
          let neighbors = self.neighborContexts(
            rootKey: rootKey,
            store: store,
            object: result.object
          )
          let fragments = self.knowledgeFragments(
            rootKey: rootKey,
            neighbors: neighbors,
            store: store,
            object: result.object,
            siteContext: siteContext
          )
          guard !fragments.isEmpty || !result.object.summary.isEmpty else {
            throw CultureExplanationError.knowledgeUnavailable
          }

          let userText = try self.promptAssembler.explainUserText(
            recognition: ExplanationRecognitionContext(result: result),
            neighbors: neighbors,
            knowledgeFragments: fragments,
            userKnowledgeStates: userKnowledgeStates,
            siteContext: siteContext
          )
          for try await event in self.gatewayClient.streamAsk(
            systemPrompt: self.promptAssembler.explainSystemPrompt,
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

  private func neighborContexts(
    rootKey: String?,
    store: KnowledgeStore,
    object: CultureObject
  ) -> [ExplanationNeighborContext] {
    if let rootKey {
      let related = store.relatedElements(forKey: rootKey, limit: 8)
      return related.map { element in
        let relation = object.relations.first {
          $0.targetID == DeterministicID.culturalElement(element.key)
            || $0.sourceID == DeterministicID.culturalElement(element.key)
        }
        return ExplanationNeighborContext(
          key: element.key,
          name: element.name,
          relationKind: relation?.kind.rawValue,
          explanation: relation?.explanation
        )
      }
    }
    return object.concepts.prefix(8).map {
      ExplanationNeighborContext(
        key: $0.id.uuidString,
        name: $0.name,
        relationKind: $0.kind.rawValue,
        explanation: $0.summary
      )
    }
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
