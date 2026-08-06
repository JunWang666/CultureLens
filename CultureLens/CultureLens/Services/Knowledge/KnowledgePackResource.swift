import Foundation

/// A fresh, view-facing snapshot of one shipped knowledge resource pack.
/// Snapshots are intentionally not persisted so an app update cannot leave
/// stale version or availability information behind.
nonisolated struct KnowledgePackResource: Identifiable, Sendable, Equatable {
  enum Delivery: Sendable, Equatable {
    case onDemand
  }

  enum Availability: Sendable, Equatable {
    case available
    case notDownloaded
    case unavailable
  }

  var id: String { directory.rawValue }

  let directory: KnowledgePackDirectory
  let delivery: Delivery
  let availability: Availability
  let version: String?
  let elementCount: Int
  let attractionCount: Int
  let relationCount: Int
  let introductionCount: Int
  let themeCount: Int

  init(
    directory: KnowledgePackDirectory,
    delivery: Delivery,
    availability: Availability,
    pack: KnowledgePack? = nil
  ) {
    self.directory = directory
    self.delivery = delivery
    self.availability = availability
    version = pack?.version
    elementCount = pack?.elements.count ?? 0
    attractionCount = pack?.attractions.count ?? 0
    relationCount = pack?.relations.count ?? 0
    introductionCount = pack?.introductions.count ?? 0
    themeCount = pack?.themes.count ?? 0
  }
}

nonisolated extension KnowledgePackDirectory {
  var odrTag: String {
    switch self {
    case .westLake: "knowledge-base"
    case .chineseHistory: "knowledge-chinese-history"
    case .liangzhu: "knowledge-liangzhu"
    case .zhejiangMuseum: "knowledge-zhejiang-museum"
    }
  }
}
