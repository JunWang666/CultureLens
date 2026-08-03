import Foundation

enum CultureChatError: LocalizedError {
  case knowledgeUnavailable
  case emptyQuestion

  var errorDescription: String? {
    switch self {
    case .knowledgeUnavailable:
      "知识库暂不可用，无法回答追问。"
    case .emptyQuestion:
      "请先输入问题。"
    }
  }
}

/// Multi-turn cultural Q&A via `dynamic/chat`, carrying object + graph context.
nonisolated struct CultureChatService: Sendable {
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

  static func live() -> CultureChatService? {
    try? CultureChatService()
  }

  func contextBootstrap(
    object: CultureObject,
    rationale: String,
    userKnowledgeStates: [UserKnowledgeStateContext]
  ) async throws -> String {
    let store = await KnowledgePackLoader.shared.store(fallback: knowledgeStore) ?? knowledgeStore
    let neighbors = neighborContexts(object: object, store: store)
    let fragments = knowledgeFragments(object: object, neighbors: neighbors, store: store)
    return try promptAssembler.askContextUserText(
      object: ExplanationRecognitionContext(object: object, rationale: rationale),
      neighbors: neighbors,
      knowledgeFragments: fragments,
      userKnowledgeStates: userKnowledgeStates
    )
  }

  func ask(
    object: CultureObject?,
    rationale: String,
    userKnowledgeStates: [UserKnowledgeStateContext],
    history: [ChatTurn],
    question: String
  ) async throws -> CultureChatReply {
    let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw CultureChatError.emptyQuestion }

    var finalContent = ""
    var modelIdentifier = LLMGatewayConfig.chat.model
    for try await event in streamAsk(
      object: object,
      rationale: rationale,
      userKnowledgeStates: userKnowledgeStates,
      history: history,
      question: trimmed
    ) {
      switch event {
      case .delta(let snapshot):
        finalContent = snapshot
      case .finished(let model, let content):
        modelIdentifier = model
        finalContent = content
      }
    }

    return CultureChatReply(
      answer: finalContent.trimmingCharacters(in: .whitespacesAndNewlines),
      citations: Self.extractCitations(from: finalContent),
      modelIdentifier: modelIdentifier
    )
  }

  func streamAsk(
    object: CultureObject?,
    rationale: String,
    userKnowledgeStates: [UserKnowledgeStateContext],
    history: [ChatTurn],
    question: String
  ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else { throw CultureChatError.emptyQuestion }

          let bootstrap: String
          if let object {
            bootstrap = try await self.contextBootstrap(
              object: object,
              rationale: rationale,
              userKnowledgeStates: userKnowledgeStates
            )
          } else {
            bootstrap = try await self.generalContextBootstrap(
              userKnowledgeStates: userKnowledgeStates
            )
          }
          var messages: [ChatTurn] = [
            ChatTurn(role: .user, content: bootstrap)
          ]
          messages.append(contentsOf: history)
          messages.append(ChatTurn(role: .user, content: trimmed))

          for try await event in self.gatewayClient.streamAsk(
            systemPrompt: self.promptAssembler.askSystemPrompt,
            messages: messages
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

  /// Pull simple key/name/fragment triples from a trailing “引用来源” section.
  static func extractCitations(from markdown: String) -> [KnowledgeCitation] {
    guard let range = markdown.range(of: "## 引用来源") ?? markdown.range(of: "##引用来源")
    else { return [] }
    let section = String(markdown[range.upperBound...])
    var citations: [KnowledgeCitation] = []
    for line in section.split(separator: "\n") {
      let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard text.hasPrefix("-") || text.hasPrefix("*") else { continue }
      let body = text.drop(while: { $0 == "-" || $0 == "*" || $0.isWhitespace })
      let parts = body.split(separator: "：", maxSplits: 1).map(String.init)
      let head = parts.first ?? String(body)
      let fragment = parts.count > 1 ? parts[1] : String(body)
      let keyName = head.split(separator: "·").map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      let name = keyName.first ?? head
      let key = keyName.count > 1 ? keyName[1] : name
      citations.append(KnowledgeCitation(key: key, name: name, fragment: fragment))
    }
    return citations
  }

  /// Home-entry chat: seed from joined nodes, then a small pack sample.
  func generalContextBootstrap(
    userKnowledgeStates: [UserKnowledgeStateContext]
  ) async throws -> String {
    let store = await KnowledgePackLoader.shared.store(fallback: knowledgeStore) ?? knowledgeStore
    var fragments: [ExplanationFragmentContext] = []
    var seen = Set<String>()

    func append(key: String, name: String, text: String) {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, seen.insert(key).inserted else { return }
      fragments.append(ExplanationFragmentContext(key: key, name: name, text: trimmed))
    }

    for state in userKnowledgeStates.prefix(8) {
      if let element = store.element(key: state.key) {
        append(
          key: element.key,
          name: element.name,
          text: KnowledgeStore.richTextPlainText(element.introduction)
        )
        for neighbor in store.relatedElements(forKey: element.key, limit: 2) {
          append(
            key: neighbor.key,
            name: neighbor.name,
            text: KnowledgeStore.richTextPlainText(neighbor.introduction)
          )
        }
      }
    }

    if fragments.count < 4 {
      for element in store.elements.prefix(8) {
        append(
          key: element.key,
          name: element.name,
          text: KnowledgeStore.richTextPlainText(element.introduction)
        )
        if fragments.count >= 8 { break }
      }
    }

    guard !fragments.isEmpty else { throw CultureChatError.knowledgeUnavailable }

    let topic = CultureObject(
      id: DeterministicID.v5(name: "culturelens:general-chat"),
      canonicalName: "文化问答",
      summary: "围绕知识库与用户已了解节点自由提问。",
      category: .other,
      timePeriod: nil,
      region: nil,
      confidence: 1,
      artworkSymbol: "text.bubble",
      concepts: [],
      relations: [],
      sources: []
    )
    return try promptAssembler.askContextUserText(
      object: ExplanationRecognitionContext(
        object: topic,
        rationale: "用户从首页直接进入文化问答，没有指定单一识别对象。"
      ),
      neighbors: userKnowledgeStates.prefix(8).map {
        ExplanationNeighborContext(
          key: $0.key,
          name: $0.name,
          relationKind: nil,
          explanation: "用户知识状态：\($0.level)"
        )
      },
      knowledgeFragments: fragments,
      userKnowledgeStates: userKnowledgeStates
    )
  }

  private func neighborContexts(
    object: CultureObject,
    store: KnowledgeStore
  ) -> [ExplanationNeighborContext] {
    if let key = object.culturalElementKey {
      return store.relatedElements(forKey: key, limit: 8).map { element in
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
    object: CultureObject,
    neighbors: [ExplanationNeighborContext],
    store: KnowledgeStore
  ) -> [ExplanationFragmentContext] {
    var fragments: [ExplanationFragmentContext] = []
    var seen = Set<String>()

    func append(key: String, name: String, text: String) {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, seen.insert(key).inserted else { return }
      fragments.append(ExplanationFragmentContext(key: key, name: name, text: trimmed))
    }

    if let key = object.culturalElementKey, let element = store.element(key: key) {
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

    for concept in object.concepts.prefix(6) {
      append(key: concept.id.uuidString, name: concept.name, text: concept.summary)
    }

    return fragments
  }
}
