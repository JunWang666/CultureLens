import Foundation
import Observation

/// Persists pack drafts under Application Support so the editor can resume work.
@Observable
@MainActor
final class KnowledgePackDraftStore {
  static let shared = KnowledgePackDraftStore()

  private(set) var drafts: [KnowledgePackDraft] = []
  private let fileManager = FileManager.default

  private var rootURL: URL {
    let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return base.appendingPathComponent("CultureLens/PackDrafts", isDirectory: true)
  }

  init() {
    reload()
  }

  func reload() {
    try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    guard let contents = try? fileManager.contentsOfDirectory(
      at: rootURL,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    ) else {
      drafts = []
      return
    }

    var loaded: [KnowledgePackDraft] = []
    for directory in contents where directory.hasDirectoryPath {
      if let draft = try? loadDraft(from: directory) {
        loaded.append(draft)
      }
    }
    drafts = loaded.sorted { $0.updatedAt > $1.updatedAt }
  }

  @discardableResult
  func save(_ draft: KnowledgePackDraft) throws -> KnowledgePackDraft {
    draft.markUpdated()
    draft.syncAttractionsFromElements()
    let directory = rootURL.appendingPathComponent(draft.id.uuidString, isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

    let pack = draft.buildPack()
    let bundle = try KnowledgePackExporter.makeExportBundle(
      for: pack,
      generatedAt: draft.updatedAt,
      directoryName: draft.id.uuidString
    )
    try KnowledgePackExporter.writeSidecars(bundle, to: directory)

    let meta = DraftMeta(
      id: draft.id,
      displayName: draft.displayName,
      updatedAt: draft.updatedAt
    )
    let metaData = try KnowledgePackExporter.makeEncoder().encode(meta)
    try metaData.write(
      to: directory.appendingPathComponent("draft-meta.json"),
      options: .atomic
    )

    if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
      drafts[index] = draft
    } else {
      drafts.insert(draft, at: 0)
    }
    drafts.sort { $0.updatedAt > $1.updatedAt }
    return draft
  }

  func delete(_ draft: KnowledgePackDraft) throws {
    let directory = rootURL.appendingPathComponent(draft.id.uuidString, isDirectory: true)
    if fileManager.fileExists(atPath: directory.path) {
      try fileManager.removeItem(at: directory)
    }
    drafts.removeAll { $0.id == draft.id }
  }

  func draft(id: UUID) -> KnowledgePackDraft? {
    drafts.first { $0.id == id }
  }

  /// Bundled packs available as copy sources (skips fallback duplicate).
  func bundledPackSummaries(bundle: Bundle = .main) -> [BundledPackSummary] {
    (try? KnowledgeStore.discoverPacks(in: bundle))?.map {
      BundledPackSummary(
        version: $0.version,
        elementCount: $0.elements.count,
        relationCount: $0.relations.count,
        attractionCount: $0.attractions.count
      )
    } ?? []
  }

  func makeDraft(fromBundledVersion version: String, bundle: Bundle = .main) throws
    -> KnowledgePackDraft
  {
    let packs = try KnowledgeStore.discoverPacks(in: bundle)
    guard let pack = packs.first(where: { $0.version == version }) else {
      throw KnowledgeStoreError.packInvalid("未找到内置包 \(version)")
    }
    let draft = KnowledgePackDraft(pack: pack, displayName: "副本 · \(pack.version)")
    try save(draft)
    return draft
  }

  func makeBlankDraft() throws -> KnowledgePackDraft {
    let draft = KnowledgePackDraft.blank()
    try save(draft)
    return draft
  }

  func importMonolithJSON(from url: URL) throws -> KnowledgePackDraft {
    let accessing = url.startAccessingSecurityScopedResource()
    defer {
      if accessing { url.stopAccessingSecurityScopedResource() }
    }
    let data = try Data(contentsOf: url)
    let pack = try JSONDecoder().decode(KnowledgePack.self, from: data).withStampedContentRoles()
    let name = url.deletingPathExtension().lastPathComponent
    let draft = KnowledgePackDraft(pack: pack, displayName: name)
    try save(draft)
    return draft
  }

  func importSidecarDirectory(from directoryURL: URL) throws -> KnowledgePackDraft {
    let accessing = directoryURL.startAccessingSecurityScopedResource()
    defer {
      if accessing { directoryURL.stopAccessingSecurityScopedResource() }
    }
    let packURL = directoryURL.appendingPathComponent("knowledge-pack.json")
    let pack = try KnowledgeStore.loadPack(fromBaseURL: packURL)
    let draft = KnowledgePackDraft(
      pack: pack,
      displayName: directoryURL.lastPathComponent
    )
    try save(draft)
    return draft
  }

  private func loadDraft(from directory: URL) throws -> KnowledgePackDraft {
    let packURL = directory.appendingPathComponent("knowledge-pack.json")
    let pack = try KnowledgeStore.loadPack(fromBaseURL: packURL)
    let metaURL = directory.appendingPathComponent("draft-meta.json")
    let meta: DraftMeta
    if let data = try? Data(contentsOf: metaURL),
      let decoded = try? JSONDecoder().decode(DraftMeta.self, from: data)
    {
      meta = decoded
    } else {
      let id = UUID(uuidString: directory.lastPathComponent) ?? UUID()
      meta = DraftMeta(id: id, displayName: pack.version, updatedAt: Date())
    }
    return KnowledgePackDraft(
      pack: pack,
      id: meta.id,
      displayName: meta.displayName,
      updatedAt: meta.updatedAt
    )
  }
}

nonisolated struct DraftMeta: Codable, Sendable {
  let id: UUID
  var displayName: String
  var updatedAt: Date
}

nonisolated struct BundledPackSummary: Identifiable, Hashable, Sendable {
  var id: String { version }
  let version: String
  let elementCount: Int
  let relationCount: Int
  let attractionCount: Int
}
