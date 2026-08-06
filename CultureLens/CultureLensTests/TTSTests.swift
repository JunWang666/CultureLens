import Foundation
import Testing

@testable import CultureLens

struct TTSTests {
  @Test
  func speechTextNormalizerStripsMarkdown() {
    let source = """
      ## 文化背景
      这是 **重点** 与 [链接](https://example.com)。
      - 列表一项
      1. 编号
      `代码`
      """
    let plain = SpeechTextNormalizer.plainSpeechText(from: source)
    #expect(!plain.contains("**"))
    #expect(!plain.contains("##"))
    #expect(!plain.contains("https://"))
    #expect(plain.contains("重点"))
    #expect(plain.contains("链接"))
    #expect(plain.contains("列表一项"))
  }

  @Test
  func volcengineStreamParsesAudioAndFinish() throws {
    let chunk = Data([1, 2, 3, 4])
    let audioLine =
      #"{"code":0,"message":"","data":"\#(chunk.base64EncodedString())"}"#
    let finishLine = #"{"code":20000000,"message":"ok","data":null}"#
    let ignoreLine = #"{"code":0,"message":"","data":null,"sentence":{"text":"hi"}}"#

    let audio = try VolcengineTTSClient.parseEvent(audioLine)
    #expect(audio.kind == .audio(chunk))

    let finish = try VolcengineTTSClient.parseEvent(finishLine)
    #expect(finish.kind == .finished)

    let ignore = try VolcengineTTSClient.parseEvent(ignoreLine)
    #expect(ignore.kind == .ignore)
  }

  @Test
  func volcengineStreamThrowsOnErrorCode() {
    let line = #"{"code":3001,"message":"quota exceeded"}"#
    #expect(throws: VolcengineTTSError.self) {
      try VolcengineTTSClient.parseEvent(line)
    }
  }

  @Test
  func volcengineConfigRequiresCredentials() {
    #expect(VolcengineTTSConfig.default.hasCredentials)
    #expect(
      VolcengineTTSConfig.default.speaker(for: .zhHans)
        == "zh_male_qingshuangnanda_uranus_bigtts"
    )

    let empty = VolcengineTTSConfig(
      endpoint: VolcengineTTSConfig.default.endpoint,
      apiKey: "",
      appId: "",
      accessKey: "",
      resourceId: "seed-tts-2.0",
      chineseSpeaker: "zh_male_qingshuangnanda_uranus_bigtts",
      englishSpeaker: "zh_male_qingshuangnanda_uranus_bigtts",
      sampleRate: 24_000,
      timeout: 30
    )
    #expect(!empty.hasCredentials)
  }

  @Test
  func ttsAudioCacheStoresAndClears() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "CultureLens-tts-cache-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }

    let cache = TTSAudioCache(directoryURL: directory)
    let key = TTSAudioCache.cacheKey(
      text: "西湖春来水如蓝",
      language: .zhHans,
      config: .default
    )
    let pcm = Data([0x01, 0x00, 0x02, 0x00, 0x03, 0x00])

    #expect(await cache.pcm(forKey: key) == nil)
    try await cache.store(pcm, forKey: key)
    #expect(await cache.pcm(forKey: key) == pcm)
    #expect(await cache.diskUsageBytes() == Int64(pcm.count))

    try await cache.clear()
    #expect(await cache.pcm(forKey: key) == nil)
    #expect(await cache.diskUsageBytes() == 0)
  }

  @Test
  func ttsCacheKeyStableForSameInput() {
    let a = TTSAudioCache.cacheKey(text: "hello", language: .english, config: .default)
    let b = TTSAudioCache.cacheKey(text: "hello", language: .english, config: .default)
    let c = TTSAudioCache.cacheKey(text: "hello!", language: .english, config: .default)
    #expect(a == b)
    #expect(a != c)
  }

  @Test
  func resolvedConfigUsesPreferredVoice() {
    let speaker = "zh_female_xiaohe_uranus_bigtts"
    let config = VolcengineTTSConfig.resolved(voiceID: speaker)
    #expect(config.speaker(for: .zhHans) == speaker)
    #expect(config.speaker(for: .english) == speaker)
    #expect(config.hasCredentials)
  }

  @Test
  func volcengineVoiceCatalogContainsDefault() {
    #expect(
      VolcengineVoiceOption.catalog.contains {
        $0.speakerID == VolcengineVoiceOption.defaultSpeakerID
      }
    )
  }
}
