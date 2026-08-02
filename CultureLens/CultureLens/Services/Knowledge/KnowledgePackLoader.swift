import Foundation

/// Loads the knowledge pack through On-Demand Resources (tag `knowledge-base`),
/// falling back to the copy embedded in the app bundle.
///
/// The tag is currently in `ON_DEMAND_RESOURCES_INITIAL_INSTALL_TAGS`, so the
/// asset pack installs together with the app and access is effectively local.
/// Removing the tag from that build setting later switches the pack to
/// on-demand download (per-region packs) with no code change; the embedded
/// fallback keeps the app functional in either mode.
actor KnowledgePackLoader {
  static let shared = KnowledgePackLoader()
  static let odrTag = "knowledge-base"

  private var cachedStore: KnowledgeStore?
  private var resourceRequest: NSBundleResourceRequest?

  /// Returns the best available store: the ODR pack when it can be fetched,
  /// otherwise the bundled fallback. The resource request is retained so the
  /// system does not purge the pack while the app is using it.
  func store(fallback: KnowledgeStore? = KnowledgeStore.shared) async -> KnowledgeStore? {
    if let cachedStore { return cachedStore }
    guard let odrStore = await loadODRStore() else { return fallback }
    cachedStore = odrStore
    return odrStore
  }

  private func loadODRStore() async -> KnowledgeStore? {
    let request = resourceRequest ?? NSBundleResourceRequest(tags: [Self.odrTag])
    resourceRequest = request
    request.loadingPriority = NSBundleResourceRequestLoadingPriorityUrgent
    do {
      let alreadyAvailable = await request.conditionallyBeginAccessingResources()
      if !alreadyAvailable {
        try await request.beginAccessingResources()
      }
      return try KnowledgeStore.load(bundle: request.bundle)
    } catch {
      return nil
    }
  }
}
