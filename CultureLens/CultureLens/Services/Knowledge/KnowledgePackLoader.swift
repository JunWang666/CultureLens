import Foundation

/// Loads knowledge packs through On-Demand Resources (tag `knowledge-base`) and
/// merges them with any additional packs embedded in the app bundle
/// (Liangzhu / Zhejiang Museum / Chinese History).
///
/// The ODR tag is currently in `ON_DEMAND_RESOURCES_INITIAL_INSTALL_TAGS`, so the
/// West Lake asset pack installs with the app. Extra regional packs ship as
/// regular bundle resources today; giving each its own ODR tag later does not
/// require changing call sites.
actor KnowledgePackLoader {
  static let shared = KnowledgePackLoader()
  static let odrTag = "knowledge-base"

  private var cachedStore: KnowledgeStore?
  private var resourceRequest: NSBundleResourceRequest?

  /// Returns the merged store: ODR West Lake (when available) plus every other
  /// pack found in the main bundle. Falls back to `fallback` when nothing loads.
  func store(fallback: KnowledgeStore? = KnowledgeStore.shared) async -> KnowledgeStore? {
    if let cachedStore { return cachedStore }
    if let merged = await loadMergedStore() {
      cachedStore = merged
      return merged
    }
    return fallback
  }

  private func loadMergedStore() async -> KnowledgeStore? {
    var packs: [KnowledgePack] = []

    if let odrPacks = await loadODRPacks() {
      packs.append(contentsOf: odrPacks)
    }

    if let bundled = try? KnowledgeStore.discoverPacks(in: .main) {
      for pack in bundled where !packs.contains(where: { $0.version == pack.version }) {
        packs.append(pack)
      }
    }

    guard !packs.isEmpty else { return nil }
    return KnowledgeStore.store(merging: packs)
  }

  private func loadODRPacks() async -> [KnowledgePack]? {
    let request = resourceRequest ?? NSBundleResourceRequest(tags: [Self.odrTag])
    resourceRequest = request
    request.loadingPriority = NSBundleResourceRequestLoadingPriorityUrgent
    do {
      let alreadyAvailable = await request.conditionallyBeginAccessingResources()
      if !alreadyAvailable {
        try await request.beginAccessingResources()
      }
      let packs = try KnowledgeStore.discoverPacks(in: request.bundle)
      return packs.isEmpty ? nil : packs
    } catch {
      return nil
    }
  }
}
