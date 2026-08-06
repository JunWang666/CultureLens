import Foundation
import Testing

@testable import CultureLens

struct NetworkCacheTests {
  @Test
  func remoteImageCachePersistsAndClears() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "CultureLens-image-cache-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = try #require(URL(string: "https://example.com/culture.jpg"))
    let expected = Data([0xFF, 0xD8, 0xFF, 0x01, 0x02])
    let writer = RemoteImageCache(directoryURL: directory)
    try await writer.store(expected, for: url)

    let reader = RemoteImageCache(directoryURL: directory)
    #expect(try await reader.data(for: url) == expected)
    #expect(await reader.diskUsageBytes() == Int64(expected.count))

    try await reader.clear()
    #expect(await reader.diskUsageBytes() == 0)
  }

  @Test
  func explanationStorePersistsAcrossInstances() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "CultureLens-explanation-cache-tests-\(UUID().uuidString)")
    let fileURL = directory.appending(path: "explanations.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let explanation = PersonalizedExplanation(
      markdown: "## 文化背景\n正文",
      citations: [],
      modelIdentifier: "test-model"
    )
    let writer = CultureExplanationStore(fileURL: fileURL)
    try await writer.save(explanation, for: "key")

    let reader = CultureExplanationStore(fileURL: fileURL)
    #expect(await reader.explanation(for: "key") == explanation)
    #expect(FileManager.default.fileExists(atPath: fileURL.path))
  }

  @Test
  func explanationStorageKeyIsStableAndTracksLanguage() {
    let result = RecognitionResult(
      id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
      object: SampleCultureData.featured,
      alternatives: [],
      rationale: "test",
      modelIdentifier: "recognition-model",
      usedPlaceContext: false
    )
    let chinese = CultureExplanationStore.key(
      result: result,
      siteContext: nil,
      language: .zhHans
    )
    let chineseAgain = CultureExplanationStore.key(
      result: result,
      siteContext: nil,
      language: .zhHans
    )
    let english = CultureExplanationStore.key(
      result: result,
      siteContext: nil,
      language: .english
    )

    #expect(chinese == chineseAgain)
    #expect(chinese != english)
    #expect(chinese.hasPrefix("explanation-"))
  }
}
