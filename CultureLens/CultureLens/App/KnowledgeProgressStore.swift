import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class KnowledgeProgressStore {
  /// Legacy UserDefaults key. Rows migrate into SwiftData as `.understand`.
  nonisolated static let defaultStorageKey = "culturelens.understood-node-ids.v1"
  nonisolated static let migrationFlagKey = "culturelens.knowledge-progress.migrated-v2"
  nonisolated static let elementKeyUUIDMigrationFlagKey =
    "culturelens.knowledge-progress.element-key-uuid-v1"

  private(set) var entriesByID: [UUID: KnowledgeProgressEntry] = [:]

  @ObservationIgnored private var modelContext: ModelContext?
  @ObservationIgnored private let userDefaults: UserDefaults
  @ObservationIgnored private let storageKey: String
  @ObservationIgnored private let migrationFlagKey: String
  @ObservationIgnored private let elementKeyUUIDMigrationFlagKey: String

  /// In-memory entry used by the store and prompt assembly.
  /// `elementKey` persists a UUID string (legacy kebab slugs are migrated on load).
  struct KnowledgeProgressEntry: Hashable, Sendable {
    let nodeID: UUID
    var level: KnowledgeLevel
    var updatedAt: Date
    var source: KnowledgeProgressSource
    var elementKey: String?
  }

  var graphNodeIDs: Set<UUID> {
    Set(entriesByID.keys)
  }

  init(
    userDefaults: UserDefaults = .standard,
    storageKey: String = KnowledgeProgressStore.defaultStorageKey,
    migrationFlagKey: String = KnowledgeProgressStore.migrationFlagKey,
    elementKeyUUIDMigrationFlagKey: String = KnowledgeProgressStore
      .elementKeyUUIDMigrationFlagKey
  ) {
    self.userDefaults = userDefaults
    self.storageKey = storageKey
    self.migrationFlagKey = migrationFlagKey
    self.elementKeyUUIDMigrationFlagKey = elementKeyUUIDMigrationFlagKey
    // Provisional in-memory seed so UI works before SwiftData configure.
    if !userDefaults.bool(forKey: migrationFlagKey) {
      let legacyIDs =
        (userDefaults.stringArray(forKey: storageKey) ?? [])
        .compactMap(UUID.init(uuidString:))
      entriesByID = Dictionary(
        uniqueKeysWithValues: legacyIDs.map { id in
          (
            id,
            KnowledgeProgressEntry(
              nodeID: id,
              level: .understand,
              updatedAt: .now,
              source: .migration,
              elementKey: nil
            )
          )
        }
      )
    }
  }

  /// Binds SwiftData and loads (or migrates) progress rows.
  func configure(modelContext: ModelContext) {
    self.modelContext = modelContext
    migrateFromUserDefaultsIfNeeded()
    migrateElementKeysToUUIDIfNeeded()
    reload()
  }

  func isInGraph(_ nodeID: UUID, elementID: UUID? = nil) -> Bool {
    entry(for: nodeID, elementID: elementID) != nil
  }

  func level(for nodeID: UUID, elementID: UUID? = nil) -> KnowledgeLevel? {
    entry(for: nodeID, elementID: elementID)?.level
  }

  /// Resolves by node ID first, then by shared cultural-element UUID so the
  /// same attraction is treated as one graph node across scans.
  func entry(for nodeID: UUID, elementID: UUID? = nil) -> KnowledgeProgressEntry? {
    if let entry = entriesByID[nodeID] {
      return entry
    }
    guard let elementID else { return nil }
    let key = elementID.uuidString
    return entriesByID.values.first {
      $0.elementKey?.caseInsensitiveCompare(key) == .orderedSame
    }
  }

  /// Binary join/leave kept for graph UI; joining defaults to `.contact`.
  func toggleGraphMembership(_ nodeID: UUID, elementID: UUID? = nil) {
    if isInGraph(nodeID, elementID: elementID) {
      remove(nodeID, elementID: elementID)
    } else {
      setLevel(.contact, for: nodeID, source: .manual, elementID: elementID)
    }
  }

  func setLevel(
    _ level: KnowledgeLevel,
    for nodeID: UUID,
    source: KnowledgeProgressSource,
    elementID: UUID? = nil
  ) {
    let now = Date()
    let existing = entry(for: nodeID, elementID: elementID)
    let storedID = existing?.nodeID ?? nodeID
    let storedKey = elementID.map { $0.uuidString } ?? existing?.elementKey
    var entry = existing
      ?? KnowledgeProgressEntry(
        nodeID: storedID,
        level: level,
        updatedAt: now,
        source: source,
        elementKey: storedKey
      )
    entry.level = level
    entry.updatedAt = now
    entry.source = source
    if let elementID {
      entry.elementKey = elementID.uuidString
    }
    entriesByID[storedID] = entry
    persist(entry)
  }

  func remove(_ nodeID: UUID, elementID: UUID? = nil) {
    let storedID = entry(for: nodeID, elementID: elementID)?.nodeID ?? nodeID
    entriesByID.removeValue(forKey: storedID)
    guard let modelContext else { return }
    let predicate = #Predicate<KnowledgeProgressRecord> { $0.nodeID == storedID }
    var descriptor = FetchDescriptor<KnowledgeProgressRecord>(predicate: predicate)
    descriptor.fetchLimit = 1
    if let existing = try? modelContext.fetch(descriptor).first {
      modelContext.delete(existing)
      try? modelContext.save()
    }
  }

  /// Builds prompt-ready states for nodes that map into the knowledge pack.
  /// Keys are UUID strings (prefer pack element id) before short-ID encoding.
  func userKnowledgeStates(knowledgeStore: KnowledgeStore?) -> [UserKnowledgeStateContext] {
    guard let knowledgeStore else {
      return entriesByID.values.compactMap { entry in
        guard let key = entry.elementKey else { return nil }
        return UserKnowledgeStateContext(
          key: key,
          name: key,
          level: entry.level
        )
      }
      .sorted { ($0.key, $0.level) < ($1.key, $1.level) }
    }

    return entriesByID.values.compactMap { entry -> UserKnowledgeStateContext? in
      let element =
        knowledgeStore.element(id: entry.nodeID)
        ?? entry.elementKey.flatMap { knowledgeStore.element(key: $0) }
      guard let element else { return nil }
      return UserKnowledgeStateContext(
        key: element.id.uuidString.lowercased(),
        name: element.name,
        level: entry.level
      )
    }
    .sorted { ($0.key, $0.level) < ($1.key, $1.level) }
  }

  private func reload() {
    guard let modelContext else { return }
    let descriptor = FetchDescriptor<KnowledgeProgressRecord>(
      sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
    )
    let records = (try? modelContext.fetch(descriptor)) ?? []
    entriesByID = Dictionary(
      uniqueKeysWithValues: records.map { record in
        (
          record.nodeID,
          KnowledgeProgressEntry(
            nodeID: record.nodeID,
            level: record.level,
            updatedAt: record.updatedAt,
            source: record.source,
            elementKey: Self.normalizedElementKey(record.elementKey)
          )
        )
      }
    )
  }

  private func persist(_ entry: KnowledgeProgressEntry) {
    guard let modelContext else { return }
    let nodeID = entry.nodeID
    let predicate = #Predicate<KnowledgeProgressRecord> { $0.nodeID == nodeID }
    var descriptor = FetchDescriptor<KnowledgeProgressRecord>(predicate: predicate)
    descriptor.fetchLimit = 1
    if let existing = try? modelContext.fetch(descriptor).first {
      existing.level = entry.level
      existing.updatedAt = entry.updatedAt
      existing.source = entry.source
      existing.elementKey = entry.elementKey
    } else {
      modelContext.insert(
        KnowledgeProgressRecord(
          nodeID: entry.nodeID,
          level: entry.level,
          updatedAt: entry.updatedAt,
          source: entry.source,
          elementKey: entry.elementKey
        )
      )
    }
    try? modelContext.save()
  }

  private func migrateFromUserDefaultsIfNeeded() {
    guard let modelContext else { return }
    guard !userDefaults.bool(forKey: migrationFlagKey) else { return }

    let legacyIDs =
      (userDefaults.stringArray(forKey: storageKey) ?? [])
      .compactMap(UUID.init(uuidString:))
    for id in legacyIDs {
      let predicate = #Predicate<KnowledgeProgressRecord> { $0.nodeID == id }
      var descriptor = FetchDescriptor<KnowledgeProgressRecord>(predicate: predicate)
      descriptor.fetchLimit = 1
      if (try? modelContext.fetch(descriptor).first) != nil { continue }
      modelContext.insert(
        KnowledgeProgressRecord(
          nodeID: id,
          level: .understand,
          source: .migration
        )
      )
    }
    try? modelContext.save()
    userDefaults.set(true, forKey: migrationFlagKey)
  }

  /// Rewrites kebab `elementKey` values to UUIDv5 strings. `nodeID` already
  /// matches the element UUID for pack-backed rows.
  private func migrateElementKeysToUUIDIfNeeded() {
    guard let modelContext else { return }
    guard !userDefaults.bool(forKey: elementKeyUUIDMigrationFlagKey) else { return }

    let descriptor = FetchDescriptor<KnowledgeProgressRecord>()
    let records = (try? modelContext.fetch(descriptor)) ?? []
    var changed = false
    for record in records {
      guard let key = record.elementKey, !key.isEmpty else { continue }
      if UUID(uuidString: key) != nil { continue }
      record.elementKey = DeterministicID.culturalElement(key).uuidString
      changed = true
    }
    if changed {
      try? modelContext.save()
    }
    userDefaults.set(true, forKey: elementKeyUUIDMigrationFlagKey)
  }

  /// Normalizes a stored element key to a UUID string when it is a legacy slug.
  nonisolated private static func normalizedElementKey(_ key: String?) -> String? {
    guard let key, !key.isEmpty else { return nil }
    if UUID(uuidString: key) != nil { return key }
    return DeterministicID.culturalElement(key).uuidString
  }
}
