import Foundation

/// App-owned memory + disk cache for public remote images.
///
/// `URLCache` remains enabled at the transport layer, but this store provides a
/// deterministic local copy that survives SwiftUI view recreation and app relaunches.
actor RemoteImageCache {
  static let shared = RemoteImageCache()

  enum CacheError: LocalizedError {
    case invalidResponse
    case emptyData

    var errorDescription: String? {
      switch self {
      case .invalidResponse:
        String(localized: "图片服务返回了无效响应。")
      case .emptyData:
        String(localized: "图片内容为空。")
      }
    }
  }

  private let session: URLSession
  private let fileManager: FileManager
  private let directoryURL: URL
  private let memoryCache = NSCache<NSURL, NSData>()
  private var inFlight: [URL: Task<Data, Error>] = [:]

  init(
    session: URLSession = .shared,
    fileManager: FileManager = .default,
    directoryURL: URL? = nil
  ) {
    self.session = session
    self.fileManager = fileManager
    self.directoryURL = directoryURL ?? Self.defaultDirectory(fileManager: fileManager)
    memoryCache.countLimit = 80
    memoryCache.totalCostLimit = 96 * 1_024 * 1_024
  }

  func data(for url: URL) async throws -> Data {
    if let cached = memoryCache.object(forKey: url as NSURL) {
      return cached as Data
    }

    let fileURL = cacheFileURL(for: url)
    if let data = try? Data(contentsOf: fileURL), !data.isEmpty {
      memoryCache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
      return data
    }

    if let task = inFlight[url] {
      return try await task.value
    }

    let task = Task<Data, Error> {
      var request = URLRequest(url: url)
      request.cachePolicy = .reloadRevalidatingCacheData
      let (data, response) = try await session.data(for: request)
      if let httpResponse = response as? HTTPURLResponse,
        !(200..<300).contains(httpResponse.statusCode)
      {
        throw CacheError.invalidResponse
      }
      guard !data.isEmpty else { throw CacheError.emptyData }
      try store(data, for: url)
      return data
    }
    inFlight[url] = task

    do {
      let data = try await task.value
      inFlight[url] = nil
      return data
    } catch {
      inFlight[url] = nil
      throw error
    }
  }

  /// Stores a preloaded image using the same memory + disk path as network responses.
  func store(_ data: Data, for url: URL) throws {
    guard !data.isEmpty else { throw CacheError.emptyData }
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try data.write(to: cacheFileURL(for: url), options: .atomic)
    memoryCache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
  }

  func clear() throws {
    for task in inFlight.values {
      task.cancel()
    }
    inFlight.removeAll()
    memoryCache.removeAllObjects()
    if fileManager.fileExists(atPath: directoryURL.path) {
      try fileManager.removeItem(at: directoryURL)
    }
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
    for case let fileURL as URL in enumerator {
      let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
      total += Int64(values?.fileSize ?? 0)
    }
    return total
  }

  private func cacheFileURL(for url: URL) -> URL {
    directoryURL.appending(path: CacheKeyDigest.sha256(url.absoluteString))
  }

  private nonisolated static func defaultDirectory(fileManager: FileManager) -> URL {
    let caches =
      (try? fileManager.url(
        for: .cachesDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      ))
      ?? fileManager.temporaryDirectory
    return
      caches
      .appending(path: "CultureLens", directoryHint: .isDirectory)
      .appending(path: "RemoteImages", directoryHint: .isDirectory)
  }
}
