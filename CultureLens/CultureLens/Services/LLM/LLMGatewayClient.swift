import Foundation

enum LLMGatewayError: LocalizedError {
  case schemaMissing(String)
  case invalidResponse
  case invalidProviderOutput
  case server(statusCode: Int, message: String?)
  case transport(String)

  var errorDescription: String? {
    switch self {
    case .schemaMissing(let name):
      "应用内缺少响应结构资源（\(name)）。"
    case .invalidResponse:
      "识别服务返回了无法读取的数据。"
    case .invalidProviderOutput:
      "识别服务返回了无法校验的数据。"
    case .server(let statusCode, let message):
      message ?? "识别服务暂时不可用（\(statusCode)）。"
    case .transport(let message):
      "无法连接识别服务：\(message)"
    }
  }
}

/// Minimal OpenAI-compatible chat/completions client for the Cloudflare AI
/// Gateway. Recognition uses multimodal `dynamic/culturelens`; explanation and
/// Q&A use `dynamic/chat` (Q&A turns may include OpenAI-style `image_url` parts).
nonisolated struct LLMGatewayClient: Sendable {
  let config: LLMGatewayConfig
  let chatConfig: LLMGatewayConfig
  /// Raw contents of `Resources/Prompts/v5.schema.json`.
  private let responseSchemaData: Data
  private let explainSchemaData: Data
  private let askSchemaData: Data
  private let session: URLSession

  init(
    config: LLMGatewayConfig = .default,
    chatConfig: LLMGatewayConfig = .chat,
    bundle: Bundle = .main,
    session: URLSession = .shared
  ) throws {
    guard
      let url = bundledResourceURL(
        "v5.schema",
        "json",
        subdirectory: "Prompts",
        bundle: bundle
      ),
      let data = try? Data(contentsOf: url)
    else {
      throw LLMGatewayError.schemaMissing("v5.schema.json")
    }
    guard
      let explainURL = bundledResourceURL(
        "explain.schema",
        "json",
        subdirectory: "Prompts",
        bundle: bundle
      ),
      let explainData = try? Data(contentsOf: explainURL)
    else {
      throw LLMGatewayError.schemaMissing("explain.schema.json")
    }
    guard
      let askURL = bundledResourceURL(
        "ask.schema",
        "json",
        subdirectory: "Prompts",
        bundle: bundle
      ),
      let askData = try? Data(contentsOf: askURL)
    else {
      throw LLMGatewayError.schemaMissing("ask.schema.json")
    }
    self.init(
      config: config,
      chatConfig: chatConfig,
      responseSchemaData: data,
      explainSchemaData: explainData,
      askSchemaData: askData,
      session: session
    )
  }

  init(
    config: LLMGatewayConfig,
    chatConfig: LLMGatewayConfig = .chat,
    responseSchemaData: Data,
    explainSchemaData: Data = Data(),
    askSchemaData: Data = Data(),
    session: URLSession = .shared
  ) {
    self.config = config
    self.chatConfig = chatConfig
    self.responseSchemaData = responseSchemaData
    self.explainSchemaData = explainSchemaData
    self.askSchemaData = askSchemaData
    self.session = session
  }

  /// Returns the validated-shape provider output plus the model identifier
  /// reported by the gateway.
  func recognize(
    systemPrompt: String,
    userText: String,
    imageBase64: String,
    mimeType: String = "image/jpeg"
  ) async throws -> (decision: ProviderRecognition, modelIdentifier: String) {
    let messages: [[String: Any]] = [
      ["role": "system", "content": systemPrompt],
      [
        "role": "user",
        "content": [
          ["type": "text", "text": userText],
          [
            "type": "image_url",
            "image_url": ["url": "data:\(mimeType);base64,\(imageBase64)"],
          ],
        ],
      ],
    ]
    let content = try await complete(
      config: config,
      messages: messages,
      schemaName: "provider_recognition",
      schemaData: responseSchemaData
    )
    do {
      let decision = try JSONDecoder().decode(
        ProviderRecognition.self,
        from: Data(content.content.utf8)
      )
      return (decision, content.modelIdentifier)
    } catch {
      #if DEBUG
        print(
          "LLMGatewayClient: decode failure \(error)\ncontent: \(content.content.prefix(1200))"
        )
      #endif
      throw LLMGatewayError.invalidProviderOutput
    }
  }

  func explain(
    systemPrompt: String,
    userText: String
  ) async throws -> (decision: ProviderLayeredExplanation, modelIdentifier: String) {
    let messages: [[String: Any]] = [
      ["role": "system", "content": systemPrompt],
      ["role": "user", "content": userText],
    ]
    let content = try await complete(
      config: chatConfig,
      messages: messages,
      schemaName: "layered_explanation",
      schemaData: explainSchemaData
    )
    do {
      let decision = try JSONDecoder().decode(
        ProviderLayeredExplanation.self,
        from: Data(content.content.utf8)
      )
      return (decision, content.modelIdentifier)
    } catch {
      throw LLMGatewayError.invalidProviderOutput
    }
  }

  func ask(
    systemPrompt: String,
    messages: [ChatTurn]
  ) async throws -> (decision: ProviderChatAnswer, modelIdentifier: String) {
    var payload: [[String: Any]] = [
      ["role": "system", "content": systemPrompt]
    ]
    for turn in messages {
      payload.append(turn.asAPIMessage())
    }
    let content = try await complete(
      config: chatConfig,
      messages: payload,
      schemaName: "culture_chat_answer",
      schemaData: askSchemaData
    )
    do {
      let decision = try JSONDecoder().decode(
        ProviderChatAnswer.self,
        from: Data(content.content.utf8)
      )
      return (decision, content.modelIdentifier)
    } catch {
      throw LLMGatewayError.invalidProviderOutput
    }
  }

  /// Free-text completion via `dynamic/chat` (no JSON schema). Used for
  /// on-demand knowledge-pack translation when a locale overlay is missing.
  func completeText(
    systemPrompt: String,
    userText: String,
    reasoningEffort: LLMReasoningEffort? = .low
  ) async throws -> (content: String, modelIdentifier: String) {
    let messages: [[String: Any]] = [
      ["role": "system", "content": systemPrompt],
      ["role": "user", "content": userText],
    ]
    return try await completeFreeform(
      config: chatConfig,
      messages: messages,
      reasoningEffort: reasoningEffort
    )
  }

  /// Streams assistant Markdown tokens from `dynamic/chat` (SSE).
  /// Turns may include OpenAI-style `image_url` parts for photo follow-ups.
  func streamAsk(
    systemPrompt: String,
    messages: [ChatTurn],
    reasoningEffort: LLMReasoningEffort? = nil
  ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          var payload: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
          ]
          for turn in messages {
            payload.append(turn.asAPIMessage())
          }
          try await self.streamComplete(
            config: self.chatConfig,
            messages: payload,
            reasoningEffort: reasoningEffort,
            continuation: continuation
          )
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

  private func streamComplete(
    config: LLMGatewayConfig,
    messages: [[String: Any]],
    reasoningEffort: LLMReasoningEffort?,
    continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
  ) async throws {
    var request = URLRequest(url: config.endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = max(config.timeout, 90)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

    request.httpBody = try Self.streamingRequestBody(
      model: config.model,
      messages: messages,
      reasoningEffort: reasoningEffort
    )

    let (bytes, response) = try await session.bytes(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMGatewayError.invalidResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw LLMGatewayError.server(statusCode: httpResponse.statusCode, message: nil)
    }

    var modelIdentifier = config.model
    var assembled = ""
    var sawSSE = false
    var sawThinking = false
    var rawBuffer = Data()

    for try await line in bytes.lines {
      try Task.checkCancellation()
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

      // Some gateways ignore stream=true and return one JSON object.
      if !sawSSE, !trimmed.hasPrefix("data:"), !trimmed.isEmpty {
        if let chunkData = (trimmed + "\n").data(using: .utf8) {
          rawBuffer.append(chunkData)
        }
        continue
      }

      guard trimmed.hasPrefix("data:") else { continue }
      sawSSE = true
      let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
      if payload == "[DONE]" { break }
      guard let data = payload.data(using: .utf8) else { continue }
      guard let chunk = try? JSONDecoder().decode(ChatStreamChunk.self, from: data) else {
        continue
      }
      if let model = chunk.model, !model.isEmpty {
        modelIdentifier = model
      }

      let delta = chunk.choices.first?.delta
      let contentDelta = delta?.content ?? ""
      let reasoningDelta = delta?.reasoningContent ?? ""

      // DeepSeek-style models stream reasoning before answer content.
      if assembled.isEmpty, !reasoningDelta.isEmpty, !sawThinking {
        sawThinking = true
        continuation.yield(.thinking)
      }

      guard !contentDelta.isEmpty else { continue }
      assembled += contentDelta
      continuation.yield(.delta(assembled))
    }

    if assembled.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !rawBuffer.isEmpty
    {
      // Non-SSE fallback: whole completion JSON arrived as buffered lines.
      if let completion = try? JSONDecoder().decode(
        ChatCompletionResponse.self,
        from: rawBuffer
      ),
        let content = completion.choices.first?.message.content,
        !content.isEmpty
      {
        modelIdentifier = completion.model ?? modelIdentifier
        // Reveal progressively so the UI still streams when the gateway buffers.
        let step = max(8, content.count / 24)
        var end =
          content.index(content.startIndex, offsetBy: step, limitedBy: content.endIndex)
          ?? content.endIndex
        while true {
          try Task.checkCancellation()
          let snapshot = String(content[content.startIndex..<end])
          continuation.yield(.delta(snapshot))
          if end == content.endIndex { break }
          try await Task.sleep(for: .milliseconds(18))
          end =
            content.index(end, offsetBy: step, limitedBy: content.endIndex)
            ?? content.endIndex
        }
        assembled = content
      }
    }

    if assembled.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw LLMGatewayError.invalidProviderOutput
    }
    continuation.yield(.finished(modelIdentifier: modelIdentifier, content: assembled))
  }

  static func streamingRequestBody(
    model: String,
    messages: [[String: Any]],
    reasoningEffort: LLMReasoningEffort?
  ) throws -> Data {
    var body: [String: Any] = [
      "model": model,
      "stream": true,
      "messages": messages,
    ]
    if let reasoningEffort {
      body["reasoning_effort"] = reasoningEffort.rawValue
    }
    return try JSONSerialization.data(withJSONObject: body)
  }

  private func completeFreeform(
    config: LLMGatewayConfig,
    messages: [[String: Any]],
    reasoningEffort: LLMReasoningEffort?
  ) async throws -> (content: String, modelIdentifier: String) {
    var request = URLRequest(url: config.endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = min(config.timeout, 60)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

    var body: [String: Any] = [
      "model": config.model,
      "messages": messages,
    ]
    if let reasoningEffort {
      body["reasoning_effort"] = reasoningEffort.rawValue
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw LLMGatewayError.transport(error.localizedDescription)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMGatewayError.invalidResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      let payload = try? JSONDecoder().decode(GatewayErrorPayload.self, from: data)
      throw LLMGatewayError.server(
        statusCode: httpResponse.statusCode,
        message: payload?.error?.message
      )
    }

    let completion: ChatCompletionResponse
    do {
      completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
    } catch {
      throw LLMGatewayError.invalidResponse
    }
    guard let content = completion.choices.first?.message.content, !content.isEmpty else {
      throw LLMGatewayError.invalidProviderOutput
    }
    return (content, completion.model ?? config.model)
  }

  private func complete(
    config: LLMGatewayConfig,
    messages: [[String: Any]],
    schemaName: String,
    schemaData: Data
  ) async throws -> (content: String, modelIdentifier: String) {
    var request = URLRequest(url: config.endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = config.timeout
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

    let schema = try JSONSerialization.jsonObject(with: schemaData)
    let body: [String: Any] = [
      "model": config.model,
      "messages": messages,
      "response_format": [
        "type": "json_schema",
        "json_schema": [
          "name": schemaName,
          "strict": true,
          "schema": schema,
        ],
      ],
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw LLMGatewayError.transport(error.localizedDescription)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMGatewayError.invalidResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      let payload = try? JSONDecoder().decode(GatewayErrorPayload.self, from: data)
      throw LLMGatewayError.server(
        statusCode: httpResponse.statusCode,
        message: payload?.error?.message
      )
    }

    let completion: ChatCompletionResponse
    do {
      completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
    } catch {
      throw LLMGatewayError.invalidResponse
    }
    guard let content = completion.choices.first?.message.content, !content.isEmpty else {
      #if DEBUG
        print(
          "LLMGatewayClient: empty content in gateway response: \(String(decoding: data.prefix(800), as: UTF8.self))"
        )
      #endif
      throw LLMGatewayError.invalidProviderOutput
    }
    return (content, completion.model ?? config.model)
  }
}

nonisolated struct ChatTurn: Sendable, Hashable {
  enum Role: String, Sendable {
    case user
    case assistant
  }

  struct ImageAttachment: Sendable, Hashable {
    let base64JPEG: String
    let mimeType: String

    init(base64JPEG: String, mimeType: String = "image/jpeg") {
      self.base64JPEG = base64JPEG
      self.mimeType = mimeType
    }

    init(jpegData: Data, mimeType: String = "image/jpeg") {
      self.base64JPEG = jpegData.base64EncodedString()
      self.mimeType = mimeType
    }
  }

  let role: Role
  let content: String
  let image: ImageAttachment?

  init(role: Role, content: String, image: ImageAttachment? = nil) {
    self.role = role
    self.content = content
    self.image = image
  }

  var hasImage: Bool { image != nil }

  /// OpenAI-compatible message dict; multimodal when `image` is set.
  func asAPIMessage() -> [String: Any] {
    guard let image else {
      return ["role": role.rawValue, "content": content]
    }
    let text =
      content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? "请结合这张图片，在已提供资料范围内回答。"
      : content
    return [
      "role": role.rawValue,
      "content": [
        ["type": "text", "text": text] as [String: Any],
        [
          "type": "image_url",
          "image_url": ["url": "data:\(image.mimeType);base64,\(image.base64JPEG)"],
        ] as [String: Any],
      ],
    ]
  }
}

nonisolated enum LLMReasoningEffort: String, Sendable {
  case low
}

nonisolated enum ChatStreamEvent: Sendable {
  /// Upstream is producing reasoning tokens; answer content has not started yet.
  case thinking
  case delta(String)
  case finished(modelIdentifier: String, content: String)
}

nonisolated struct ProviderLayeredExplanation: Decodable, Sendable {
  let conclusion: String
  let why: String
  let extensionText: String
  let citations: [ProviderCitation]

  enum CodingKeys: String, CodingKey {
    case conclusion
    case why
    case extensionText = "extension"
    case citations
  }
}

nonisolated struct ProviderChatAnswer: Decodable, Sendable {
  let answer: String
  let citations: [ProviderCitation]
}

nonisolated struct ProviderCitation: Decodable, Sendable {
  let key: String
  let name: String
  let fragment: String
}

/// `choices[].message` carries extra gateway fields (e.g. `extra_content`,
/// `thought_signature`); `Decodable` ignores them by default.
private nonisolated struct ChatCompletionResponse: Decodable {
  let model: String?
  let choices: [Choice]

  struct Choice: Decodable {
    let message: Message
  }

  struct Message: Decodable {
    let content: String?
  }
}

private nonisolated struct ChatStreamChunk: Decodable {
  let model: String?
  let choices: [Choice]

  struct Choice: Decodable {
    let delta: Delta
  }

  struct Delta: Decodable {
    let content: String?
    let reasoningContent: String?

    enum CodingKeys: String, CodingKey {
      case content
      case reasoningContent = "reasoning_content"
    }
  }
}

private nonisolated struct GatewayErrorPayload: Decodable {
  let error: ErrorBody?

  struct ErrorBody: Decodable {
    let message: String?
  }
}
