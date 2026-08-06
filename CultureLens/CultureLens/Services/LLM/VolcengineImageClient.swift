import Foundation

/// Volcengine Ark Seedream image generation (optional share-cover path).
nonisolated struct VolcengineImageConfig: Sendable {
  let endpoint: URL
  let apiKey: String
  let model: String
  let size: String
  let timeout: TimeInterval

  var hasCredentials: Bool {
    !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  static let `default` = VolcengineImageConfig(
    endpoint: URL(string: "https://ark.cn-beijing.volces.com/api/v3/images/generations")!,
    apiKey: "ark-e08f2a3c-38ec-455d-b5b3-373bbc6ba698-5fe18",
    model: "doubao-seedream-5-0-260128",
    size: "2K",
    timeout: 90
  )
}

enum VolcengineImageError: LocalizedError {
  case disabled
  case missingCredentials
  case invalidResponse
  case emptyImage
  case server(statusCode: Int, message: String?)

  var errorDescription: String? {
    switch self {
    case .disabled:
      String(localized: "图片生成未启用。可在设置中打开。")
    case .missingCredentials:
      String(localized: "图片生成服务未配置。")
    case .invalidResponse:
      String(localized: "图片生成服务返回了无法读取的数据。")
    case .emptyImage:
      String(localized: "图片生成结果为空。")
    case .server(let statusCode, let message):
      message ?? String(localized: "图片生成服务暂时不可用（\(statusCode)）。")
    }
  }
}

/// Thin client for Doubao Seedream image generations.
nonisolated struct VolcengineImageClient: Sendable {
  let config: VolcengineImageConfig
  private let session: URLSession

  init(
    config: VolcengineImageConfig = .default,
    session: URLSession = .shared
  ) {
    self.config = config
    self.session = session
  }

  /// Returns a remote URL for the generated image (`response_format: url`).
  func generateImageURL(prompt: String) async throws -> URL {
    guard config.hasCredentials else { throw VolcengineImageError.missingCredentials }

    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw VolcengineImageError.invalidResponse }

    var request = URLRequest(url: config.endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = config.timeout
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

    let body: [String: Any] = [
      "model": config.model,
      "prompt": trimmed,
      "sequential_image_generation": "disabled",
      "response_format": "url",
      "size": config.size,
      "stream": false,
      "watermark": true,
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw VolcengineImageError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      let message = Self.errorMessage(from: data)
      throw VolcengineImageError.server(statusCode: http.statusCode, message: message)
    }

    guard let payload = try? JSONDecoder().decode(GenerationResponse.self, from: data),
      let raw = payload.data.first?.url?.trimmingCharacters(in: .whitespacesAndNewlines),
      let url = URL(string: raw),
      url.scheme?.lowercased() == "https"
    else {
      throw VolcengineImageError.invalidResponse
    }
    return url
  }

  /// Downloads the generated image bytes (via `RemoteImageCache`).
  func generateImageData(prompt: String) async throws -> Data {
    let url = try await generateImageURL(prompt: prompt)
    return try await RemoteImageCache.shared.data(for: url)
  }

  private static func errorMessage(from data: Data) -> String? {
    guard
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    if let error = object["error"] as? [String: Any] {
      return error["message"] as? String
    }
    return object["message"] as? String
  }

  private struct GenerationResponse: Decodable {
    struct Item: Decodable {
      let url: String?
    }

    let data: [Item]
  }
}
