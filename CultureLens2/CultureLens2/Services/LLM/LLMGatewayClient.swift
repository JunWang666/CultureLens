import Foundation

enum LLMGatewayError: LocalizedError {
  case schemaMissing
  case invalidResponse
  case invalidProviderOutput
  case server(statusCode: Int, message: String?)
  case transport(String)

  var errorDescription: String? {
    switch self {
    case .schemaMissing:
      "应用内缺少识别响应结构资源。"
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
/// Gateway. Sends the system prompt, assembled user text and the photo as
/// multimodal content parts, constrained by the bundled JSON schema.
nonisolated struct LLMGatewayClient: Sendable {
  let config: LLMGatewayConfig
  /// Raw contents of `Resources/Prompts/v5.schema.json`.
  private let responseSchemaData: Data
  private let session: URLSession

  init(
    config: LLMGatewayConfig = .default,
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
      throw LLMGatewayError.schemaMissing
    }
    self.init(config: config, responseSchemaData: data, session: session)
  }

  init(config: LLMGatewayConfig, responseSchemaData: Data, session: URLSession = .shared) {
    self.config = config
    self.responseSchemaData = responseSchemaData
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
    var request = URLRequest(url: config.endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = config.timeout
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

    let schema = try JSONSerialization.jsonObject(with: responseSchemaData)
    let body: [String: Any] = [
      "model": config.model,
      "messages": [
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
      ],
      "response_format": [
        "type": "json_schema",
        "json_schema": [
          "name": "provider_recognition",
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
        print("LLMGatewayClient: empty content in gateway response: \(String(decoding: data.prefix(800), as: UTF8.self))")
      #endif
      throw LLMGatewayError.invalidProviderOutput
    }
    do {
      let decision = try JSONDecoder().decode(
        ProviderRecognition.self,
        from: Data(content.utf8)
      )
      return (decision, completion.model ?? config.model)
    } catch {
      #if DEBUG
        print("LLMGatewayClient: decode failure \(error)\ncontent: \(content.prefix(1200))")
      #endif
      throw LLMGatewayError.invalidProviderOutput
    }
  }
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

private nonisolated struct GatewayErrorPayload: Decodable {
  let error: ErrorBody?

  struct ErrorBody: Decodable {
    let message: String?
  }
}
