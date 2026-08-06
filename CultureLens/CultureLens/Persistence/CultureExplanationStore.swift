import Foundation

/// Durable storage for completed AI culture explanations.
///
/// Unlike a cache, these records live in Application Support, are not evicted,
/// and are not removed by the Settings cache-cleanup action. Regeneration is
/// the explicit way to replace a stored explanation.
actor CultureExplanationStore {
  static let shared = CultureExplanationStore()

  private struct Entry: Codable {
    let explanation: PersonalizedExplanation
    let savedAt: Date
  }

  private struct KeyPayload: Codable {
    let identityVersion: Int
    let language: String
    let resultID: UUID
    let objectID: UUID
    let culturalElementID: UUID?
    let siteContext: String?
  }

  private let fileManager: FileManager
  private let fileURL: URL
  private var entries: [String: Entry]

  init(
    fileManager: FileManager = .default,
    fileURL: URL? = nil
  ) {
    self.fileManager = fileManager
    self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    entries = Self.loadEntries(from: self.fileURL)
  }

  func explanation(for key: String) -> PersonalizedExplanation? {
    entries[key]?.explanation
  }

  func save(_ explanation: PersonalizedExplanation, for key: String) throws {
    entries[key] = Entry(explanation: explanation, savedAt: .now)
    try persist()
  }

  nonisolated static func key(
    result: RecognitionResult,
    siteContext: String?,
    language: AppLanguage
  ) -> String {
    let payload = KeyPayload(
      identityVersion: 1,
      language: language.rawValue,
      resultID: result.id,
      objectID: result.object.id,
      culturalElementID: result.object.culturalElementID,
      siteContext: siteContext
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = (try? encoder.encode(payload)) ?? Data()
    return "explanation-\(CacheKeyDigest.sha256(data))"
  }

  private func persist() throws {
    try fileManager.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(entries).write(to: fileURL, options: .atomic)
  }

  private nonisolated static func loadEntries(from fileURL: URL) -> [String: Entry] {
    guard let data = try? Data(contentsOf: fileURL) else { return [:] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([String: Entry].self, from: data)) ?? [:]
  }

  private nonisolated static func defaultFileURL(fileManager: FileManager) -> URL {
    let applicationSupport =
      (try? fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      ))
      ?? fileManager.temporaryDirectory
    return
      applicationSupport
      .appending(path: "CultureLens", directoryHint: .isDirectory)
      .appending(path: "Explanations", directoryHint: .isDirectory)
      .appending(path: "explanations-v1.json")
  }
}
