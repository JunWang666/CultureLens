import Foundation

/// Loads and merges the four independently tagged knowledge ODR packs.
/// Every tag is currently initial-install, but each remains independently
/// queryable and downloadable from the settings resource manager.
actor KnowledgePackLoader {
  static let shared = KnowledgePackLoader()

  private var cachedStore: KnowledgeStore?
  private var resourceRequests: [KnowledgePackDirectory: NSBundleResourceRequest] = [:]
  private var accessedDirectories = Set<KnowledgePackDirectory>()
  /// ODR 请求不支持并发 begin；actor 在 await 处可重入，用共享 Task 去重。
  private var inFlightAccess: [KnowledgePackDirectory: Task<Bool, Error>] = [:]

  /// Returns the merged ODR store. Missing initial-install resources are
  /// downloaded on demand; `fallback` keeps injected test stores supported.
  func store(fallback: KnowledgeStore? = KnowledgeStore.shared) async -> KnowledgeStore? {
    if let cachedStore { return cachedStore }
    if let merged = await loadMergedStore(downloadIfNeeded: true) {
      cachedStore = merged
      KnowledgeStore.installShared(merged)
      return merged
    }
    return fallback
  }

  /// Returns one fresh status snapshot per known pack, in merge-priority order.
  /// Merely opening the manager never starts a missing ODR download.
  func resourceStatuses() async -> [KnowledgePackResource] {
    var resources: [KnowledgePackResource] = []
    for directory in KnowledgePackDirectory.allCases {
      let available =
        (try? await ensureAccess(to: directory, downloadIfNeeded: false)) == true
      let pack = available ? loadPack(directory) : nil
      resources.append(
        KnowledgePackResource(
          directory: directory,
          delivery: .onDemand,
          availability: pack == nil
            ? (available ? .unavailable : .notDownloaded)
            : .available,
          pack: pack
        )
      )
    }
    return resources
  }

  /// Downloads one missing ODR pack and refreshes the merged runtime snapshot.
  func downloadOnDemandPack(_ directory: KnowledgePackDirectory) async throws {
    guard try await ensureAccess(to: directory, downloadIfNeeded: true) else {
      throw KnowledgeStoreError.packMissing
    }
    guard loadPack(directory) != nil else {
      throw KnowledgeStoreError.packMissing
    }
    cachedStore = await loadMergedStore(downloadIfNeeded: false)
    if let cachedStore {
      KnowledgeStore.installShared(cachedStore)
    }
  }

  private func loadMergedStore(downloadIfNeeded: Bool) async -> KnowledgeStore? {
    var packs: [KnowledgePack] = []
    for directory in KnowledgePackDirectory.allCases {
      do {
        guard try await ensureAccess(to: directory, downloadIfNeeded: downloadIfNeeded)
        else {
          continue
        }
        if let pack = loadPack(directory) {
          packs.append(pack)
        }
      } catch {
        continue
      }
    }

    guard !packs.isEmpty else { return nil }
    return KnowledgeStore.store(merging: packs)
  }

  private func ensureAccess(
    to directory: KnowledgePackDirectory,
    downloadIfNeeded: Bool
  ) async throws -> Bool {
    if accessedDirectories.contains(directory) { return true }
    if let inFlight = inFlightAccess[directory] {
      return try await inFlight.value
    }

    let request = request(for: directory)
    let task = Task { () throws -> Bool in
      if await request.conditionallyBeginAccessingResources() { return true }
      guard downloadIfNeeded else { return false }
      try await request.beginAccessingResources()
      return true
    }
    inFlightAccess[directory] = task
    defer { inFlightAccess[directory] = nil }

    do {
      let accessed = try await task.value
      if accessed {
        accessedDirectories.insert(directory)
      }
      return accessed
    } catch {
      // begin 失败的请求实例不能再次 begin（再次调用会抛 NSException 闪退），
      // 丢弃实例，下次重试时创建新请求。
      resourceRequests[directory] = nil
      throw error
    }
  }

  private func request(for directory: KnowledgePackDirectory) -> NSBundleResourceRequest {
    if let request = resourceRequests[directory] { return request }
    let request = NSBundleResourceRequest(tags: [directory.odrTag])
    request.loadingPriority = NSBundleResourceRequestLoadingPriorityUrgent
    resourceRequests[directory] = request
    return request
  }

  private func loadPack(_ directory: KnowledgePackDirectory) -> KnowledgePack? {
    let bundle = request(for: directory).bundle
    // ODR asset pack 内文件是扁平的（根目录），bundle 资源则带目录前缀。
    for subdirectory in directory.subdirectoryCandidates + [nil] {
      guard
        let url = bundle.url(
          forResource: "knowledge-pack",
          withExtension: "json",
          subdirectory: subdirectory
        )
      else { continue }
      return try? KnowledgeStore.loadPack(fromBaseURL: url)
    }
    return nil
  }
}
