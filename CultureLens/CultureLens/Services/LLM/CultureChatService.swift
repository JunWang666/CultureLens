import Foundation

enum CultureChatError: LocalizedError {
  case knowledgeUnavailable
  case emptyQuestion

  var errorDescription: String? {
    switch self {
    case .knowledgeUnavailable:
      "知识库暂不可用，无法回答追问。"
    case .emptyQuestion:
      "请先输入问题或上传图片。"
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
    let assembler = promptAssembler.withLanguage(AppLanguageStore.currentLanguage())
    return try assembler.askContextUserText(
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
    question: String,
    imageJPEG: Data? = nil
  ) async throws -> CultureChatReply {
    let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty || imageJPEG != nil else {
      throw CultureChatError.emptyQuestion
    }

    var finalContent = ""
    var modelIdentifier = LLMGatewayConfig.chat.model
    for try await event in streamAsk(
      object: object,
      rationale: rationale,
      userKnowledgeStates: userKnowledgeStates,
      history: history,
      question: trimmed,
      imageJPEG: imageJPEG
    ) {
      switch event {
      case .thinking:
        break
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
    question: String,
    imageJPEG: Data? = nil
  ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty || imageJPEG != nil else {
            throw CultureChatError.emptyQuestion
          }

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
          let image = imageJPEG.map { ChatTurn.ImageAttachment(jpegData: $0) }
          let questionText =
            trimmed.isEmpty
            ? "请结合这张图片，根据已提供资料说明你看到了什么、能关联到哪些文化内容。"
            : trimmed
          messages.append(
            ChatTurn(role: .user, content: questionText, image: image)
          )

          for try await event in self.gatewayClient.streamAsk(
            systemPrompt: self.promptAssembler.withLanguage(AppLanguageStore.currentLanguage())
              .askSystemPrompt,
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

  /// Splits streamed Markdown into display body + structured citation cards.
  /// The trailing sources section (「引用来源」/ Sources / …) is removed from
  /// the body so it is not rendered twice (once as Markdown, once as cards).
  static func parseAnswer(
    _ markdown: String,
    store: KnowledgeStore? = .shared
  ) -> (body: String, citations: [KnowledgeCitation]) {
    let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
    guard
      let regex = try? NSRegularExpression(
        pattern: CitationMarkup.sourceHeadingPattern(),
        options: []
      ),
      let match = regex.firstMatch(
        in: normalized,
        options: [],
        range: NSRange(normalized.startIndex..., in: normalized)
      ),
      let headerRange = Range(match.range, in: normalized)
    else {
      return (
        body: CultureCiteURL.sanitizeInlineCitations(
          normalized.trimmingCharacters(in: .whitespacesAndNewlines),
          store: store
        ),
        citations: []
      )
    }

    let body = CultureCiteURL.sanitizeInlineCitations(
      String(normalized[..<headerRange.lowerBound])
        .trimmingCharacters(in: .whitespacesAndNewlines),
      store: store
    )
    let section = String(normalized[headerRange.upperBound...])
    return (body, parseCitationSection(section, store: store))
  }

  static func displayBody(from markdown: String, store: KnowledgeStore? = .shared) -> String {
    parseAnswer(markdown, store: store).body
  }

  static func extractCitations(
    from markdown: String,
    store: KnowledgeStore? = .shared
  ) -> [KnowledgeCitation] {
    parseAnswer(markdown, store: store).citations
  }

  private static func parseCitationSection(
    _ section: String,
    store: KnowledgeStore?
  ) -> [KnowledgeCitation] {
    var citations: [KnowledgeCitation] = []
    var current: (key: String, name: String, fragment: String)?

    func commit() {
      guard let current else { return }
      let key = current.key.trimmingCharacters(in: .whitespacesAndNewlines)
      let name = current.name.trimmingCharacters(in: .whitespacesAndNewlines)
      let fragment = current.fragment.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !key.isEmpty || !name.isEmpty else { return }
      let resolvedKey = key.isEmpty ? name : key
      citations.append(
        KnowledgeCitation(
          key: resolvedKey,
          name: name.isEmpty ? key : name,
          fragment: fragment,
          sources: store?.trustedSources(forElementKey: resolvedKey) ?? []
        )
      )
    }

    let keyNamePattern = #/(?:[-*]\s*)?key:\s*`?([^`,\n]+)`?\s*,\s*name:\s*(.+)/#
    let pipePattern = #/(?:[-*]\s*)?(.+?)\s*\|\s*(.+?)\s*\|\s*(.+)/#
    let bulletNamePattern = #/^[-*]\s+(.+?)(?:\s*[·•]\s*|\s+)([a-z0-9][\w.-]*|[0-9A-F-]{20,})$/#

    for rawLine in section.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.isEmpty { continue }

      if line.hasPrefix("#") { continue }

      if let match = line.firstMatch(of: keyNamePattern) {
        commit()
        current = (
          key: String(match.1).trimmingCharacters(in: .whitespacesAndNewlines),
          name: String(match.2).trimmingCharacters(in: .whitespacesAndNewlines),
          fragment: ""
        )
        continue
      }

      if line.contains("|"), let match = line.firstMatch(of: pipePattern) {
        commit()
        current = (
          key: String(match.1).trimmingCharacters(in: .whitespacesAndNewlines),
          name: String(match.2).trimmingCharacters(in: .whitespacesAndNewlines),
          fragment: String(match.3).trimmingCharacters(in: .whitespacesAndNewlines)
        )
        continue
      }

      if CitationMarkup.lineLooksLikeExcerpt(line)
        || line.hasPrefix("摘录：") || line.hasPrefix("摘录:")
        || line.hasPrefix("- 摘录")
      {
        let value =
          line.split(whereSeparator: { $0 == "：" || $0 == ":" }).dropFirst().joined(
            separator: ":"
          )
        let fragment = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if current != nil, !fragment.isEmpty {
          if !current!.fragment.isEmpty { current!.fragment += " " }
          current!.fragment += fragment
        }
        continue
      }

      if line.hasPrefix("-") || line.hasPrefix("*") {
        let body = line.drop(while: { $0 == "-" || $0 == "*" || $0.isWhitespace })
        if let match = String(body).firstMatch(of: bulletNamePattern) {
          commit()
          current = (key: String(match.2), name: String(match.1), fragment: "")
          continue
        }
        // Nested fragment under current item.
        if current != nil {
          let text = String(body)
          if !current!.fragment.isEmpty { current!.fragment += " " }
          current!.fragment += text
        }
        continue
      }

      if current != nil {
        if !current!.fragment.isEmpty { current!.fragment += " " }
        current!.fragment += line
      }
    }
    commit()

    // Deduplicate by key while preserving order.
    var seen = Set<String>()
    return citations.filter { citation in
      seen.insert(citation.key).inserted
    }
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

    let topicCanonicalName: String
    let topicSummary: String
    let topicRationale: String
    switch AppLanguageStore.currentLanguage() {
    case .english:
      topicCanonicalName = "Cultural Q&A"
      topicSummary = "Ask freely about the knowledge base and nodes you already know."
      topicRationale =
        "The user opened cultural Q&A from the home screen without a single recognition target."
    case .zhHans:
      topicCanonicalName = "文化问答"
      topicSummary = "围绕知识库与用户已了解节点自由提问。"
      topicRationale = "用户从首页直接进入文化问答，没有指定单一识别对象。"
    }
    let topic = CultureObject(
      id: DeterministicID.v5(name: "culturelens:general-chat"),
      canonicalName: topicCanonicalName,
      summary: topicSummary,
      category: .other,
      timePeriod: nil,
      region: nil,
      confidence: 1,
      artworkSymbol: "text.bubble",
      concepts: [],
      relations: [],
      sources: []
    )
    let assembler = promptAssembler.withLanguage(AppLanguageStore.currentLanguage())
    return try assembler.askContextUserText(
      object: ExplanationRecognitionContext(
        object: topic,
        rationale: topicRationale
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
