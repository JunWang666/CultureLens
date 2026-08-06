import Foundation

enum VolcengineTTSError: LocalizedError, Equatable {
  case missingCredentials
  case emptyText
  case invalidResponse
  case server(code: Int, message: String)
  case transport(String)
  case emptyAudio

  var errorDescription: String? {
    switch self {
    case .missingCredentials:
      String(localized: "火山引擎语音未配置密钥。")
    case .emptyText:
      String(localized: "没有可朗读的内容。")
    case .invalidResponse:
      String(localized: "语音合成返回了无法读取的数据。")
    case .server(_, let message):
      message.isEmpty
        ? String(localized: "语音合成暂时不可用。")
        : message
    case .transport(let message):
      String(localized: "无法连接语音合成服务：\(message)")
    case .emptyAudio:
      String(localized: "语音合成未返回音频。")
    }
  }
}

/// Calls Volcengine V3 HTTP Chunked unidirectional TTS and returns MP3 bytes.
nonisolated struct VolcengineTTSClient: Sendable {
  let config: VolcengineTTSConfig
  private let session: URLSession

  init(config: VolcengineTTSConfig = .default, session: URLSession? = nil) {
    self.config = config
    if let session {
      self.session = session
    } else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = config.timeout
      configuration.timeoutIntervalForResource = config.timeout
      self.session = URLSession(configuration: configuration)
    }
  }

  func synthesize(
    text: String,
    language: AppLanguage,
    requestID: UUID = UUID()
  ) async throws -> Data {
    guard config.hasCredentials else {
      throw VolcengineTTSError.missingCredentials
    }

    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw VolcengineTTSError.emptyText
    }

    var request = URLRequest(url: config.endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(config.resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
    request.setValue(requestID.uuidString, forHTTPHeaderField: "X-Api-Request-Id")

    let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if !apiKey.isEmpty {
      request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
    } else {
      request.setValue(config.appId, forHTTPHeaderField: "X-Api-App-Id")
      request.setValue(config.accessKey, forHTTPHeaderField: "X-Api-Access-Key")
    }

    let additions: [String: Any] = [
      "disable_markdown_filter": true
    ]
    let additionsData = try JSONSerialization.data(withJSONObject: additions)
    let additionsString = String(data: additionsData, encoding: .utf8) ?? "{}"

    let body: [String: Any] = [
      "user": [
        "uid": "culturelens"
      ],
      "req_params": [
        "text": trimmed,
        "speaker": config.speaker(for: language),
        "audio_params": [
          "format": "mp3",
          "sample_rate": config.sampleRate
        ],
        "additions": additionsString
      ]
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (bytes, response) = try await session.bytes(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw VolcengineTTSError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      var preview = Data()
      for try await byte in bytes {
        preview.append(byte)
        if preview.count >= 512 { break }
      }
      let message = String(data: preview, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      throw VolcengineTTSError.server(
        code: http.statusCode,
        message: message ?? String(localized: "语音合成暂时不可用（\(http.statusCode)）。")
      )
    }

    do {
      let audio = try await Self.collectMP3(from: bytes)
      guard !audio.isEmpty else {
        throw VolcengineTTSError.emptyAudio
      }
      return audio
    } catch let error as VolcengineTTSError {
      throw error
    } catch {
      throw VolcengineTTSError.transport(error.localizedDescription)
    }
  }

  /// Parses NDJSON chunked body: audio frames (`code == 0` + base64 `data`)
  /// until terminal success (`code == 20000000`).
  static func collectMP3(from bytes: URLSession.AsyncBytes) async throws -> Data {
    var buffer = Data()
    var audio = Data()
    var finished = false

    for try await byte in bytes {
      buffer.append(byte)
      while let newline = buffer.firstIndex(of: 0x0A) {
        let lineData = buffer.subdata(in: buffer.startIndex..<newline)
        buffer.removeSubrange(buffer.startIndex...newline)
        let line = String(data: lineData, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !line.isEmpty else { continue }
        let event = try parseEvent(line)
        switch event.kind {
        case .audio(let chunk):
          audio.append(chunk)
        case .finished:
          finished = true
        case .ignore:
          break
        }
      }
      if finished { break }
    }

    if !finished {
      let trailing = String(data: buffer, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !trailing.isEmpty {
        let event = try parseEvent(trailing)
        switch event.kind {
        case .audio(let chunk):
          audio.append(chunk)
        case .finished:
          finished = true
        case .ignore:
          break
        }
      }
    }

    guard finished || !audio.isEmpty else {
      throw VolcengineTTSError.invalidResponse
    }
    return audio
  }

  /// Test helper: parse a single NDJSON line.
  static func parseEvent(_ line: String) throws -> VolcengineTTSStreamEvent {
    guard let data = line.data(using: .utf8),
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let code = object["code"] as? Int
    else {
      throw VolcengineTTSError.invalidResponse
    }

    if code == 20_000_000 {
      return VolcengineTTSStreamEvent(kind: .finished)
    }

    if code != 0 {
      let message = (object["message"] as? String) ?? ""
      throw VolcengineTTSError.server(code: code, message: message)
    }

    if let base64 = object["data"] as? String, !base64.isEmpty,
      let chunk = Data(base64Encoded: base64)
    {
      return VolcengineTTSStreamEvent(kind: .audio(chunk))
    }

    return VolcengineTTSStreamEvent(kind: .ignore)
  }
}

nonisolated struct VolcengineTTSStreamEvent: Sendable, Equatable {
  enum Kind: Sendable, Equatable {
    case audio(Data)
    case finished
    case ignore
  }

  let kind: Kind
}
