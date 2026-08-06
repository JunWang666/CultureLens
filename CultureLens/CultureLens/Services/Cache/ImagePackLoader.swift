import Foundation

/// Owns the single `images` ODR tag and resolves hosted R2 URLs to local pack files.
///
/// Lookup order inside an accessed pack mirrors knowledge JSON ODR:
/// flat asset-pack root first, then subdirectory layouts used when packs are
/// embedded in the product bundle for side-loading.
actor ImagePackLoader {
  static let shared = ImagePackLoader()
  static let odrTag = "images"

  private var resourceRequest: NSBundleResourceRequest?
  private var hasAccess = false
  private var inFlightAccess: Task<Bool, Error>?

  /// Ensures the image pack is available (downloading if needed). Safe to call at launch.
  @discardableResult
  func ensureAvailable(downloadIfNeeded: Bool = true) async -> Bool {
    (try? await ensureAccess(downloadIfNeeded: downloadIfNeeded)) == true
  }

  /// Status snapshot for settings. Never starts a download by itself.
  func resourceStatus() async -> ImagePackResource {
    let available = (try? await ensureAccess(downloadIfNeeded: false)) == true
    let count = available ? countImages() : 0
    let availability: ImagePackResource.Availability
    if !available {
      availability = .notDownloaded
    } else if count == 0 {
      availability = .unavailable
    } else {
      availability = .available
    }
    return ImagePackResource(
      delivery: .onDemand,
      availability: availability,
      imageCount: count
    )
  }

  /// Downloads the missing image ODR pack.
  func downloadOnDemandPack() async throws {
    guard try await ensureAccess(downloadIfNeeded: true) else {
      throw ImagePackError.packMissing
    }
    guard countImages() > 0 else {
      throw ImagePackError.packMissing
    }
  }

  /// Ends access to the image ODR pack. Embedded builds keep files on disk.
  func releaseOnDemandPack() async {
    resourceRequest?.endAccessingResources()
    resourceRequest = nil
    hasAccess = false
    inFlightAccess?.cancel()
    inFlightAccess = nil
  }

  /// Returns local file bytes for a hosted image URL when the ODR pack contains it.
  func dataIfAvailable(for url: URL) async -> Data? {
    guard let components = ImagePackPathMapping.resourceComponents(for: url) else {
      return nil
    }
    guard (try? await ensureAccess(downloadIfNeeded: true)) == true else {
      return nil
    }
    guard let fileURL = fileURL(for: components) else { return nil }
    guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return nil }
    return data
  }

  private func ensureAccess(downloadIfNeeded: Bool) async throws -> Bool {
    if hasAccess { return true }
    if let inFlightAccess {
      return try await inFlightAccess.value
    }

    let request = currentRequest()
    let task = Task { () throws -> Bool in
      if await request.conditionallyBeginAccessingResources() { return true }
      guard downloadIfNeeded else { return false }
      try await request.beginAccessingResources()
      return true
    }
    inFlightAccess = task
    defer { inFlightAccess = nil }

    do {
      let accessed = try await task.value
      if accessed {
        hasAccess = true
      }
      return accessed
    } catch {
      // Failed begin instances must not be reused (can throw NSException on retry).
      resourceRequest = nil
      throw error
    }
  }

  private func currentRequest() -> NSBundleResourceRequest {
    if let resourceRequest { return resourceRequest }
    let request = NSBundleResourceRequest(tags: [Self.odrTag])
    request.loadingPriority = NSBundleResourceRequestLoadingPriorityUrgent
    resourceRequest = request
    return request
  }

  private func fileURL(
    for components: (subdirectory: String, name: String, ext: String)
  ) -> URL? {
    let bundle = currentRequest().bundle
    let subdirectoryCandidates: [String?] = [
      nil, // ODR asset packs flatten to pack root
      components.subdirectory,
      "images/\(components.subdirectory)",
    ]
    for subdirectory in subdirectoryCandidates {
      if let url = bundle.url(
        forResource: components.name,
        withExtension: components.ext,
        subdirectory: subdirectory
      ) {
        return url
      }
    }
    return nil
  }

  private func countImages() -> Int {
    let bundle = currentRequest().bundle
    var seen = Set<String>()
    let layouts: [String?] = [
      nil,
      "west-lake",
      "chinese-history",
      "liangzhu",
      "zhejiang-museum",
      "images/west-lake",
      "images/chinese-history",
      "images/liangzhu",
      "images/zhejiang-museum",
    ]
    for subdirectory in layouts {
      for ext in ["jpg", "jpeg", "png", "webp"] {
        guard
          let urls = bundle.urls(forResourcesWithExtension: ext, subdirectory: subdirectory)
        else { continue }
        for url in urls {
          seen.insert(url.lastPathComponent)
        }
      }
    }
    return seen.count
  }
}

enum ImagePackError: LocalizedError {
  case packMissing

  var errorDescription: String? {
    switch self {
    case .packMissing:
      String(localized: "图片资源包不可用。")
    }
  }
}
