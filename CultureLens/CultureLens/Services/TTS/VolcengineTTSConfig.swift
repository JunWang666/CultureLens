import Foundation

/// Volcengine Doubao TTS (V3 HTTP Chunked unidirectional).
/// Docs: https://www.volcengine.com/docs/6561/1598757 (HTTP Chunked;
/// same V3 family as unidirectional WebSocket https://docs.volcengine.com/docs/6561/2534913).
nonisolated struct VolcengineTTSConfig: Sendable {
  let endpoint: URL
  /// New console API Key (`X-Api-Key`). Preferred when non-empty.
  let apiKey: String
  /// Legacy console APP ID (`X-Api-App-Id`). Used when `apiKey` is empty.
  let appId: String
  /// Legacy console Access Token (`X-Api-Access-Key`). Used with `appId`.
  let accessKey: String
  /// `seed-tts-2.0` for uranus speakers; `seed-tts-1.0` for moon/mars.
  let resourceId: String
  let chineseSpeaker: String
  let englishSpeaker: String
  let sampleRate: Int
  let timeout: TimeInterval

  var hasCredentials: Bool {
    if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return true
    }
    return !appId.isEmpty && !accessKey.isEmpty
  }

  func speaker(for language: AppLanguage) -> String {
    switch language {
    case .english, .japanese, .russian: englishSpeaker
    case .zhHans: chineseSpeaker
    }
  }

  /// Fill `apiKey` (new console) or `appId` + `accessKey` (legacy) before shipping.
  static let `default` = VolcengineTTSConfig(
    endpoint: URL(string: "https://openspeech.bytedance.com/api/v3/tts/unidirectional")!,
    apiKey: "1f18703b-32f8-4c5f-9c55-8915413a337f",
    appId: "",
    accessKey: "",
    resourceId: "seed-tts-2.0",
    chineseSpeaker: "zh_male_qingshuangnanda_uranus_bigtts",
    englishSpeaker: "zh_male_qingshuangnanda_uranus_bigtts",
    sampleRate: 24_000,
    timeout: 90
  )
}
