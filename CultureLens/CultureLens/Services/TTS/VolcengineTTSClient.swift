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

/// Calls Volcengine V3 HTTP Chunked unidirectional TTS and yields PCM audio
/// frames as they arrive (s16le mono at `config.sampleRate`).
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
      // Prefer streaming: don't wait for the full body before delivering bytes.
      configuration.httpMaximumConnectionsPerHost = 4
      self.session = URLSession(configuration: configuration)
    }
  }

  /// Streams decoded PCM chunks from the NDJSON chunked response.
  func synthesizeStream(
    text: String,
    language: AppLanguage,
    requestID: UUID = UUID()
  ) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          try await self.runStream(
            text: text,
            language: language,
            requestID: requestID,
            continuation: continuation
          )
          continuation.finish()
        } catch is CancellationError {
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

  private func runStream(
    text: String,
    language: AppLanguage,
    requestID: UUID,
    continuation: AsyncThrowingStream<Data, Error>.Continuation
  ) async throws {
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

    // PCM streams into AVAudioEngine without waiting for a full MP3 file.
    let body: [String: Any] = [
      "user": [
        "uid": "culturelens"
      ],
      "req_params": [
        "text": trimmed,
        "speaker": config.speaker(for: language),
        "audio_params": [
          "format": "pcm",
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

    var lineBuffer = Data()
    var receivedAudio = false
    var finished = false

    do {
      for try await byte in bytes {
        try Task.checkCancellation()
        lineBuffer.append(byte)
        while let newline = lineBuffer.firstIndex(of: 0x0A) {
          let lineData = lineBuffer.subdata(in: lineBuffer.startIndex..<newline)
          lineBuffer.removeSubrange(lineBuffer.startIndex...newline)
          let line = String(data: lineData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
          guard !line.isEmpty else { continue }
          let event = try Self.parseEvent(line)
          switch event.kind {
          case .audio(let chunk):
            receivedAudio = true
            continuation.yield(chunk)
          case .finished:
            finished = true
          case .ignore:
            break
          }
        }
        if finished { break }
      }

      if !finished {
        let trailing = String(data: lineBuffer, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trailing.isEmpty {
          let event = try Self.parseEvent(trailing)
          switch event.kind {
          case .audio(let chunk):
            receivedAudio = true
            continuation.yield(chunk)
          case .finished:
            finished = true
          case .ignore:
            break
          }
        }
      }
    } catch let error as VolcengineTTSError {
      throw error
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw VolcengineTTSError.transport(error.localizedDescription)
    }

    guard finished || receivedAudio else {
      throw VolcengineTTSError.invalidResponse
    }
    guard receivedAudio else {
      throw VolcengineTTSError.emptyAudio
    }
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
