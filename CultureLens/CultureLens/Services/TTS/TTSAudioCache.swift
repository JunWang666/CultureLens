import Foundation

/// Disk cache for Volcengine TTS PCM (s16le mono).
actor TTSAudioCache {
  static let shared = TTSAudioCache()

  private let fileManager: FileManager
  private let directoryURL: URL

  init(fileManager: FileManager = .default, directoryURL: URL? = nil) {
    self.fileManager = fileManager
    self.directoryURL = directoryURL ?? Self.defaultDirectory(fileManager: fileManager)
    try? fileManager.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
  }

  static func cacheKey(
    text: String,
    language: AppLanguage,
    config: VolcengineTTSConfig
  ) -> String {
    let speaker = config.speaker(for: language)
    return CacheKeyDigest.sha256(
      "tts-pcm-v1|\(language.rawValue)|\(config.resourceId)|\(speaker)|\(config.sampleRate)|\(text)"
    )
  }

  func pcm(forKey key: String) -> Data? {
    let url = fileURL(for: key)
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    return try? Data(contentsOf: url)
  }

  func store(_ pcm: Data, forKey key: String) throws {
    guard !pcm.isEmpty else { return }
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try pcm.write(to: fileURL(for: key), options: .atomic)
  }

  func clear() throws {
    guard fileManager.fileExists(atPath: directoryURL.path) else { return }
    try fileManager.removeItem(at: directoryURL)
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
  }

  func diskUsageBytes() -> Int64 {
    guard
      let enumerator = fileManager.enumerator(
        at: directoryURL,
        includingPropertiesForKeys: [.fileSizeKey],
        options: [.skipsHiddenFiles]
      )
    else { return 0 }

    var total: Int64 = 0
    for case let url as URL in enumerator {
      let values = try? url.resourceValues(forKeys: [.fileSizeKey])
      total += Int64(values?.fileSize ?? 0)
    }
    return total
  }

  private func fileURL(for key: String) -> URL {
    directoryURL.appending(path: "\(key).pcm")
  }

  private static func defaultDirectory(fileManager: FileManager) -> URL {
    let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return caches.appending(path: "CultureLensTTS", directoryHint: .isDirectory)
  }
}
