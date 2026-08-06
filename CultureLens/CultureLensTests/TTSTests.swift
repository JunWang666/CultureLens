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
}
