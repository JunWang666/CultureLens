import Foundation
import Synchronization

/// Locates a bundled resource whether the build system flattened the
/// synchronized group into the bundle root or preserved subdirectories.
nonisolated func bundledResourceURL(
  _ name: String,
  _ ext: String,
  subdirectory: String,
  bundle: Bundle
) -> URL? {
  let subdirectories = [
    subdirectory,
    "Resources/\(subdirectory)",
  ]
  for candidate in subdirectories {
    if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: candidate) {
      return url
    }
  }
  return bundle.url(forResource: name, withExtension: ext)
}

/// Known knowledge-pack resource directories, in merge priority order.
/// Earlier packs win on id collision. Every production directory is assigned
/// its own ODR tag; ordinary bundle discovery remains available for tests.
nonisolated enum KnowledgePackDirectory: String, CaseIterable, Sendable {
  case westLake = "KnowledgePack"
  case chineseHistory = "KnowledgePackChineseHistory"
  case liangzhu = "KnowledgePackLiangzhu"
  case zhejiangMuseum = "KnowledgePackZhejiangMuseum"

  var subdirectoryCandidates: [String] {
    [rawValue, "Resources/\(rawValue)"]
  }
}

enum KnowledgeStoreError: LocalizedError {
  case packMissing
  case packInvalid(String)
  case invalidQuery

  var errorDescription: String? {
    switch self {
    case .packMissing:
      String(localized: "应用内缺少知识库数据包。")
    case .packInvalid(let detail):
      String(localized: "知识库数据包无法读取：\(detail)")
    case .invalidQuery:
      String(localized: "附近内容查询参数无效。")
    }
  }
}

/// In-memory port of the Go backend's knowledge repository
/// (`internal/knowledge/postgres.go`), backed by locally decoded knowledge
/// packs instead of PostgreSQL.
nonisolated struct KnowledgeStore: Sendable {
  static let defaultCandidateLimit = 12
  static let maximumObjectLimit = 48
  static let maximumGraphExpansionNodes = 48
  /// Explore / content nearby search default (not recognition).
  static let defaultRadiusMeters = 50_000.0
  /// Recognition only considers on-site introductions within this radius.
  /// Every unique attraction inside the radius is passed to the vision model.
  static let recognitionRadiusMeters = 1_000.0
  /// Pull unbound cultural nodes into the recognition prompt only when fewer
  /// than this many nearby attractions are available.
  static let minimumAttractionsBeforeCulturalFill = 3
  /// When more than this many nearby attractions are sent, prompt assembly
  /// omits introduction / nearby_contexts text to keep the payload small.
  static let introductionOmissionAttractionThreshold = 10

  let pack: KnowledgePack

  /// Element IDs in `ListCulturalElements` order (`ORDER BY name, sortKey`).
  private let orderedElementIDs: [UUID]
  private let elementsByID: [UUID: KnowledgePack.Element]
  private let attractionsByID: [UUID: KnowledgePack.Attraction]
  /// Slug → UUID for migration / debug lookups (keys are lowercased).
  private let elementIDsByKey: [String: UUID]
  /// Source pack `version` for each element id (first pack wins on collision).
  private let packVersionByElementID: [UUID: String]
  /// Directed pack relations in stable lexicographic order. Endpoint order and
  /// optional `kind` / `explanation` are preserved so typed edges stay usable
  /// downstream; adjacency treats them as undirected for BFS.
  private let relations: [KnowledgePack.Relation]
  private let adjacency: [UUID: [UUID]]
  /// Directed indexes keyed by endpoint. `outgoingEdges[id]` lists edges whose
  /// source is `id` (target in `DirectedRelationEdge.id`); `incomingEdges[id]`
  /// lists edges whose target is `id` (source in `.id`).
  private let outgoingEdges: [UUID: [DirectedRelationEdge]]
  private let incomingEdges: [UUID: [DirectedRelationEdge]]
  private let introductionsByID: [UUID: KnowledgePack.IntroductionRecord]
  /// Optional slug → introduction for lookups that still use intro keys.
  private let introductionsByKey: [String: KnowledgePack.IntroductionRecord]

  init(pack: KnowledgePack, packVersionByElementID: [UUID: String] = [:]) {
    let pack = pack.withStampedContentRoles()
    self.pack = pack
    elementsByID = Dictionary(
      pack.elements.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    attractionsByID = Dictionary(
      pack.attractions.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    elementIDsByKey = Dictionary(
      pack.elements.compactMap { element -> (String, UUID)? in
        guard let key = element.key?.lowercased(), !key.isEmpty else { return nil }
        return (key, element.id)
      },
      uniquingKeysWith: { first, _ in first }
    )
    if packVersionByElementID.isEmpty {
      self.packVersionByElementID = Dictionary(
        uniqueKeysWithValues: pack.elements.map { ($0.id, pack.version) }
      )
    } else {
      self.packVersionByElementID = packVersionByElementID
    }
    orderedElementIDs = pack.elements
      .sorted { ($0.name, $0.sortKey) < ($1.name, $1.sortKey) }
      .map(\.id)
    let normalizedRelations = pack.relations
      .sorted {
        ($0.elementId.uuidString, $0.relatedElementId.uuidString)
          < ($1.elementId.uuidString, $1.relatedElementId.uuidString)
      }
    relations = normalizedRelations
    var adjacencySets: [UUID: Set<UUID>] = [:]
    for relation in normalizedRelations {
      adjacencySets[relation.elementId, default: []].insert(relation.relatedElementId)
      adjacencySets[relation.relatedElementId, default: []].insert(relation.elementId)
    }
    adjacency = adjacencySets.mapValues { $0.sorted { $0.uuidString < $1.uuidString } }
    var outgoing: [UUID: [DirectedRelationEdge]] = [:]
    var incoming: [UUID: [DirectedRelationEdge]] = [:]
    for relation in normalizedRelations {
      let kind = relation.kind.flatMap { RelationKind(rawValue: $0) }
      outgoing[relation.elementId, default: []].append(
        DirectedRelationEdge(
          id: relation.relatedElementId,
          kind: kind,
          explanation: relation.explanation
        )
      )
      incoming[relation.relatedElementId, default: []].append(
        DirectedRelationEdge(
          id: relation.elementId,
          kind: kind,
          explanation: relation.explanation
        )
      )
    }
    outgoingEdges = outgoing
    incomingEdges = incoming
    introductionsByID = Dictionary(
      pack.introductions.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    introductionsByKey = Dictionary(
      pack.introductions.compactMap { record -> (String, KnowledgePack.IntroductionRecord)? in
        guard let key = record.key?.lowercased(), !key.isEmpty else { return nil }
        return (key, record)
      },
      uniquingKeysWith: { first, _ in first }
    )
  }

  /// Loads and merges every discoverable `knowledge-pack.json` in `bundle`.
  static func load(bundle: Bundle = .main) throws -> KnowledgeStore {
    let packs = try discoverPacks(in: bundle)
    guard !packs.isEmpty else { throw KnowledgeStoreError.packMissing }
    return store(merging: packs)
  }

  /// Builds a store from already-decoded packs (ODR + bundle merge).
  static func store(merging packs: [KnowledgePack]) -> KnowledgeStore {
    KnowledgeStore(
      pack: mergePacks(packs.map { $0.withStampedContentRoles() }),
      packVersionByElementID: packVersionsByElement(from: packs)
    )
  }

  /// First-seen pack version for each element id.
  static func packVersionsByElement(from packs: [KnowledgePack]) -> [UUID: String] {
    var map: [UUID: String] = [:]
    for pack in packs {
      for element in pack.elements where map[element.id] == nil {
        map[element.id] = pack.version
      }
    }
    return map
  }

  /// Decodes packs from `bundle` in `KnowledgePackDirectory` priority order.
  /// Each directory is assembled from `knowledge-pack.json` plus optional
  /// sidecar files (`elements-sight`, `elements-history`, `introductions`,
  /// `themes`, `locales-<lang>`). Same `version` is loaded once.
  static func discoverPacks(in bundle: Bundle) throws -> [KnowledgePack] {
    var packs: [KnowledgePack] = []
    var seenVersions = Set<String>()
    for directory in KnowledgePackDirectory.allCases {
      guard let url = packURL(in: bundle, directory: directory) else { continue }
      do {
        let pack = try loadPack(fromBaseURL: url)
        if seenVersions.insert(pack.version).inserted {
          packs.append(pack)
        }
      } catch let error as KnowledgeStoreError {
        throw error
      } catch {
        throw KnowledgeStoreError.packInvalid(error.localizedDescription)
      }
    }
    return packs
  }

  /// Loads `knowledge-pack.json` and merges sibling sidecar JSON files into a
  /// complete `KnowledgePack`, then stamps `contentRole` on every element.
  static func loadPack(fromBaseURL baseURL: URL) throws -> KnowledgePack {
    let data = try Data(contentsOf: baseURL)
    var pack = try JSONDecoder().decode(KnowledgePack.self, from: data)
    let directory = baseURL.deletingLastPathComponent()
    let decoder = JSONDecoder()

    func decodeSidecar<T: Decodable>(_ name: String, as type: T.Type) throws -> T? {
      let url = directory.appendingPathComponent("\(name).json")
      guard FileManager.default.fileExists(atPath: url.path) else { return nil }
      return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    var elements = pack.elements
    var attractions = pack.attractions
    var introductions = pack.introductions
    var themes = pack.themes
    var locales = pack.locales ?? [:]

    if let sight = try decodeSidecar("elements-sight", as: KnowledgePackSightSidecar.self) {
      if !sight.elements.isEmpty { elements.append(contentsOf: sight.elements) }
      if !sight.attractions.isEmpty { attractions = sight.attractions }
    }
    if let history = try decodeSidecar(
      "elements-history", as: KnowledgePackHistorySidecar.self),
      !history.elements.isEmpty
    {
      elements.append(contentsOf: history.elements)
    }
    if let intro = try decodeSidecar(
      "introductions", as: KnowledgePackIntroductionsSidecar.self),
      !intro.introductions.isEmpty
    {
      introductions = intro.introductions
    }
    if let themeSidecar = try decodeSidecar("themes", as: KnowledgePackThemesSidecar.self),
      !themeSidecar.themes.isEmpty
    {
      themes = themeSidecar.themes
    }

    // `locales-<lang>.json` — one overlay file per language; replaces nested
    // `locales` in the main JSON when present.
    let localePrefix = "locales-"
    if let entries = try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    ) {
      for url in entries where url.pathExtension == "json" {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.hasPrefix(localePrefix) else { continue }
        let lang = String(name.dropFirst(localePrefix.count))
        guard !lang.isEmpty else { continue }
        let overlay = try decoder.decode(
          KnowledgePack.LocaleOverlay.self,
          from: Data(contentsOf: url)
        )
        locales[lang] = overlay
      }
    }

    // Deduplicate elements by id (first wins: sight before history append).
    var seenElementIDs = Set<UUID>()
    elements = elements.filter { seenElementIDs.insert($0.id).inserted }

    pack = KnowledgePack(
      version: pack.version,
      sourceLanguage: pack.sourceLanguage,
      elements: elements,
      attractions: attractions,
      relations: pack.relations,
      introductions: introductions,
      themes: themes,
      locales: locales.isEmpty ? nil : locales
    )
    return pack.withStampedContentRoles()
  }

  /// Merges packs; earlier entries win on element / attraction / introduction /
  /// theme id collisions. Relations whose endpoints both survive are kept.
  /// Locale overlays are unioned per language, with earlier packs winning keys
  /// (UUID strings).
  static func mergePacks(_ packs: [KnowledgePack]) -> KnowledgePack {
    guard let first = packs.first else {
      return KnowledgePack(
        version: "empty",
        elements: [],
        attractions: [],
        relations: [],
        introductions: []
      )
    }
    if packs.count == 1 { return first }

    var elements: [UUID: KnowledgePack.Element] = [:]
    var attractions: [UUID: KnowledgePack.Attraction] = [:]
    var introductions: [UUID: KnowledgePack.IntroductionRecord] = [:]
    var themes: [UUID: KnowledgePack.Theme] = [:]
    var relations: [KnowledgePack.Relation] = []
    var seenRelation = Set<String>()
    var locales: [String: KnowledgePack.LocaleOverlay] = [:]
    var sourceLanguage = first.sourceLanguage

    for pack in packs {
      if sourceLanguage == nil { sourceLanguage = pack.sourceLanguage }
      for element in pack.elements where elements[element.id] == nil {
        elements[element.id] = element
      }
      for attraction in pack.attractions where attractions[attraction.id] == nil {
        attractions[attraction.id] = attraction
      }
      for introduction in pack.introductions where introductions[introduction.id] == nil {
        introductions[introduction.id] = introduction
      }
      for theme in pack.themes where themes[theme.id] == nil {
        themes[theme.id] = theme
      }
      for relation in pack.relations {
        let signature = [
          relation.elementId.uuidString,
          relation.relatedElementId.uuidString,
          relation.kind ?? "",
          relation.explanation ?? "",
        ].joined(separator: "\u{1f}")
        guard seenRelation.insert(signature).inserted else { continue }
        relations.append(relation)
      }
      guard let packLocales = pack.locales else { continue }
      for (language, overlay) in packLocales {
        var merged = locales[language] ?? KnowledgePack.LocaleOverlay()
        for (key, value) in overlay.elements where merged.elements[key] == nil {
          merged.elements[key] = value
        }
        for (key, value) in overlay.attractions where merged.attractions[key] == nil {
          merged.attractions[key] = value
        }
        for (key, value) in overlay.introductions where merged.introductions[key] == nil {
          merged.introductions[key] = value
        }
        locales[language] = merged
      }
    }

    // Drop relations that point at elements lost to collision filtering.
    relations = relations.filter {
      elements[$0.elementId] != nil && elements[$0.relatedElementId] != nil
    }
    // Themes may reference ids from their home pack only; drop dangling ids.
    let cleanedThemes = themes.values.map { theme in
      KnowledgePack.Theme(
        id: theme.id,
        key: theme.key,
        name: theme.name,
        summary: theme.summary,
        elementIds: theme.elementIds.filter { elements[$0] != nil },
        minContacted: theme.minContacted
      )
    }
    .filter { !$0.elementIds.isEmpty }
    .sorted { ($0.name, $0.sortKey) < ($1.name, $1.sortKey) }

    let version = packs.map(\.version).joined(separator: "+")
    return KnowledgePack(
      version: version,
      sourceLanguage: sourceLanguage,
      elements: elements.values.sorted { ($0.name, $0.sortKey) < ($1.name, $1.sortKey) },
      attractions: attractions.values.sorted {
        ($0.name, $0.sortKey) < ($1.name, $1.sortKey)
      },
      relations: relations.sorted {
        ($0.elementId.uuidString, $0.relatedElementId.uuidString)
          < ($1.elementId.uuidString, $1.relatedElementId.uuidString)
      },
      introductions: introductions.values.sorted {
        ($0.name, $0.sortKey) < ($1.name, $1.sortKey)
      },
      themes: cleanedThemes,
      locales: locales.isEmpty ? nil : locales
    )
  }

  private static func packURL(in bundle: Bundle, directory: KnowledgePackDirectory) -> URL? {
    for subdirectory in directory.subdirectoryCandidates {
      if let url = bundle.url(
        forResource: "knowledge-pack",
        withExtension: "json",
        subdirectory: subdirectory
      ) {
        return url
      }
    }
    return nil
  }

  /// Thread-safe runtime snapshot. It starts with any ordinary bundle packs
  /// (useful in tests), then the ODR loader replaces it with the merged store.
  private static let sharedState = Mutex<KnowledgeStore?>(try? KnowledgeStore.load())

  static var shared: KnowledgeStore? {
    sharedState.withLock { $0 }
  }

  static func installShared(_ store: KnowledgeStore) {
    sharedState.withLock { $0 = store }
  }

  // MARK: - Basic lookups

  var elements: [KnowledgePack.Element] {
    orderedElementIDs.compactMap { elementsByID[$0] }
  }

  /// Scannable sight elements only (`ContentRole.sight`).
  var sightElements: [KnowledgePack.Element] {
    elements.filter { $0.resolvedContentRole() == .sight }
  }

  /// Abstract cultural-history elements (`ContentRole.history`).
  var historyElements: [KnowledgePack.Element] {
    elements.filter { $0.resolvedContentRole() == .history }
  }

  func element(id: UUID) -> KnowledgePack.Element? {
    elementsByID[id]
  }

  func attraction(id: UUID) -> KnowledgePack.Attraction? {
    attractionsByID[id]
  }

  /// Resolves via slug map, or accepts a UUID string.
  func element(key: String) -> KnowledgePack.Element? {
    resolveElementID(key).flatMap { elementsByID[$0] }
  }

  /// Optional pack slug for a node id.
  func elementKey(for nodeID: UUID) -> String? {
    elementsByID[nodeID]?.key
  }

  /// Accepts a UUID string or kebab slug (case-insensitive).
  func resolveElementID(_ string: String) -> UUID? {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let uuid = UUID(uuidString: trimmed) {
      return uuid
    }
    return elementIDsByKey[trimmed.lowercased()]
  }

  func introduction(id: UUID) -> KnowledgePack.IntroductionRecord? {
    introductionsByID[id]
  }

  func introduction(key: String) -> KnowledgePack.IntroductionRecord? {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    if let uuid = UUID(uuidString: trimmed) {
      return introductionsByID[uuid]
    }
    return introductionsByKey[trimmed.lowercased()]
  }

  func cultureConcept(elementID: UUID) -> CultureConcept? {
    guard let element = elementsByID[elementID] else { return nil }
    return CultureConcept(
      id: element.id,
      name: element.name,
      kind: CulturalElementPresentation.conceptKind(element.conceptKind),
      summary: Self.richTextPlainText(element.introduction),
      detail: ""
    )
  }

  func cultureConcept(elementKey: String) -> CultureConcept? {
    resolveElementID(elementKey).flatMap(cultureConcept(elementID:))
  }

  /// Best-effort reverse lookup when a citation URL only carries a display name.
  func elementKey(matchingName name: String) -> String? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let exact = elementsByID.values.first(where: { $0.name == trimmed }) {
      return exact.key ?? exact.id.uuidString
    }
    return elementsByID.values.first(where: {
      $0.name.contains(trimmed) || trimmed.contains($0.name)
    }).map { $0.key ?? $0.id.uuidString }
  }

  /// Best-effort reverse lookup returning the element UUID.
  func elementID(matchingName name: String) -> UUID? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let exact = elementsByID.values.first(where: { $0.name == trimmed }) {
      return exact.id
    }
    return elementsByID.values.first(where: {
      $0.name.contains(trimmed) || trimmed.contains($0.name)
    })?.id
  }

  /// Rich introduction for detail pages; falls back to `nil` when unresolved.
  func introductionDocument(elementID: UUID) -> RichTextDocument? {
    elementsByID[elementID]?.introduction
  }

  func introductionDocument(elementKey: String) -> RichTextDocument? {
    resolveElementID(elementKey).flatMap(introductionDocument(elementID:))
  }

  func introductionDocument(nodeID: UUID) -> RichTextDocument? {
    introductionDocument(elementID: nodeID)
  }

  /// Trusted external sources for an element: pack-level `sources` plus
  /// provenance URLs from linked on-site introductions (Wikipedia, Amap, …).
  func trustedSources(forElementID id: UUID) -> [KnowledgeSource] {
    packSources(forElementID: id).map { $0.asKnowledgeSource() }
  }

  func trustedSources(forElementKey key: String) -> [KnowledgeSource] {
    guard let id = resolveElementID(key) else { return [] }
    return trustedSources(forElementID: id)
  }

  func packSources(forElementID id: UUID) -> [KnowledgePack.Source] {
    var result: [KnowledgePack.Source] = []
    var seen = Set<String>()

    func append(_ sources: [KnowledgePack.Source]) {
      for source in sources {
        let identity =
          (source.url ?? "\(source.publisher)|\(source.title)")
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .lowercased()
        guard !identity.isEmpty, seen.insert(identity).inserted else { continue }
        result.append(source)
      }
    }

    if let element = elementsByID[id] {
      append(element.sources)
    }
    for record in pack.introductions where record.culturalElementId == id {
      append(record.sources)
    }
    return result
  }

  func packSources(forElementKey key: String) -> [KnowledgePack.Source] {
    guard let id = resolveElementID(key) else { return [] }
    return packSources(forElementID: id)
  }

  // MARK: - Attraction points (POI map)

  /// All attractions in the loaded packs as map points, aggregated from the
  /// on-site introduction records (which carry the coordinates). Records
  /// cluster per physical location (attraction id + coordinates rounded to 3
  /// decimals): the same attraction hosted at different sites — across packs
  /// or across intro records — yields one point per site instead of collapsing
  /// into the first record's location.
  func attractionPoints() -> [AttractionPoint] {
    var firstRecordByLocation: [String: KnowledgePack.IntroductionRecord] = [:]
    for record in pack.introductions {
      let locationKey =
        record.attractionId.uuidString + "|"
        + String(format: "%.3f", record.latitude) + ","
        + String(format: "%.3f", record.longitude)
      if firstRecordByLocation[locationKey] == nil {
        firstRecordByLocation[locationKey] = record
      }
    }
    return firstRecordByLocation.values.compactMap { record in
      let attraction = attractionsByID[record.attractionId]
      let name = attraction?.name ?? record.name
      guard !name.isEmpty else { return nil }
      // A physical attraction can have many introduction records at the same
      // coordinate, including history/context elements. The map marker names
      // the attraction, so its navigation target must be the scannable sight
      // that shares the attraction slug rather than whichever introduction
      // happened to be encountered first.
      let culturalElementId =
        sightElementID(forAttraction: record.attractionId)
        ?? (elementsByID[record.culturalElementId] != nil
          ? record.culturalElementId
          : nil)
      return AttractionPoint(
        attractionId: record.attractionId,
        key: attraction?.key,
        name: name,
        culturalElementId: culturalElementId,
        latitude: record.latitude,
        longitude: record.longitude
      )
    }
    .sorted {
      ($0.name, $0.sortKey, $0.latitude, $0.longitude)
        < ($1.name, $1.sortKey, $1.latitude, $1.longitude)
    }
  }

  // MARK: - User knowledge graph

  /// Builds the graph shown in the Graph tab. Every joined node remains
  /// visible, while knowledge-pack expansion is limited to three shortest-hop
  /// rings and a fixed node budget. Expansion radiates from every center:
  /// each requested center starts at hop 0 and hops are the shortest distance
  /// to any of them. An empty `centerIDs` defaults to all joined nodes that
  /// are backed by a pack element.
  func userKnowledgeGraph(
    centerIDs requestedCenterIDs: [UUID],
    joinedSeeds: [UserKnowledgeGraphSeed],
    maximumDepth: Int = 3,
    maximumExpandedNodes: Int = KnowledgeStore.maximumGraphExpansionNodes
  ) -> UserKnowledgeGraphSnapshot {
    let depthLimit = max(0, maximumDepth)
    let expansionLimit = max(1, maximumExpandedNodes)
    let seedByID = Dictionary(
      joinedSeeds.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let joinedIDs = Set(seedByID.keys)
    let joinedElementIDs = Set(joinedIDs.filter { elementsByID[$0] != nil })

    let defaultCenterIDs: [UUID] = {
      let packBacked = orderedElementIDs.filter { joinedElementIDs.contains($0) }
      if !packBacked.isEmpty { return packBacked }
      return joinedSeeds.sorted {
        if $0.name != $1.name {
          return $0.name.localizedCompare($1.name) == .orderedAscending
        }
        return $0.id.uuidString < $1.id.uuidString
      }.prefix(1).map(\.id)
    }()
    var seenCenterIDs = Set<UUID>()
    let requestedCenters = requestedCenterIDs.filter { id in
      (elementsByID[id] != nil || joinedIDs.contains(id))
        && seenCenterIDs.insert(id).inserted
    }
    let centerIDs = requestedCenters.isEmpty ? defaultCenterIDs : requestedCenters

    var hops: [UUID: Int] = [:]
    var queue: [UUID] = []
    var queueIndex = 0
    var isTruncated = false
    for id in centerIDs where elementsByID[id] != nil {
      hops[id] = 0
      queue.append(id)
    }

    while queueIndex < queue.count {
      let current = queue[queueIndex]
      queueIndex += 1
      let currentDepth = hops[current] ?? 0
      guard currentDepth < depthLimit else { continue }

      for neighbor in adjacency[current, default: []] where hops[neighbor] == nil {
        guard hops.count < expansionLimit else {
          isTruncated = true
          continue
        }
        hops[neighbor] = currentDepth + 1
        queue.append(neighbor)
      }
    }

    var visibleElementIDs = joinedElementIDs
    visibleElementIDs.formUnion(hops.keys)
    var nodes = visibleElementIDs.compactMap { id -> UserKnowledgeGraphNode? in
      guard let element = elementsByID[id] else { return nil }
      return UserKnowledgeGraphNode(
        id: id,
        elementKey: element.key,
        name: element.name,
        summary: Self.richTextPlainText(element.introduction),
        kind: CulturalElementPresentation.conceptKind(element.conceptKind),
        hop: hops[id] ?? depthLimit + 1,
        isJoined: joinedIDs.contains(id)
      )
    }

    for seed in joinedSeeds where elementsByID[seed.id] == nil {
      nodes.append(
        UserKnowledgeGraphNode(
          id: seed.id,
          elementKey: nil,
          name: seed.name,
          summary: seed.summary,
          kind: .foundation,
          hop: centerIDs.contains(seed.id) ? 0 : depthLimit + 1,
          isJoined: true
        )
      )
    }
    nodes.sort {
      if $0.hop != $1.hop { return $0.hop < $1.hop }
      if $0.name != $1.name { return $0.name.localizedCompare($1.name) == .orderedAscending }
      return $0.id.uuidString < $1.id.uuidString
    }

    let edges = relations.compactMap { relation -> UserKnowledgeGraphEdge? in
      guard
        visibleElementIDs.contains(relation.elementId),
        visibleElementIDs.contains(relation.relatedElementId)
      else { return nil }
      return UserKnowledgeGraphEdge(
        id: DeterministicID.v5(
          name:
            "culturelens:user-graph:\(relation.elementId.uuidString):\(relation.relatedElementId.uuidString)"
        ),
        sourceID: relation.elementId,
        targetID: relation.relatedElementId,
        kind: relation.kind.flatMap { RelationKind(rawValue: $0) },
        explanation: relation.explanation
      )
    }

    return UserKnowledgeGraphSnapshot(
      centerID: centerIDs.first,
      centerIDs: centerIDs,
      nodes: nodes,
      edges: edges,
      maximumDepth: depthLimit,
      isExpansionTruncated: isTruncated
    )
  }

  /// Single-center convenience overload kept for existing callers and tests.
  func userKnowledgeGraph(
    centerID requestedCenterID: UUID?,
    joinedSeeds: [UserKnowledgeGraphSeed],
    maximumDepth: Int = 3,
    maximumExpandedNodes: Int = KnowledgeStore.maximumGraphExpansionNodes
  ) -> UserKnowledgeGraphSnapshot {
    userKnowledgeGraph(
      centerIDs: requestedCenterID.map { [$0] } ?? [],
      joinedSeeds: joinedSeeds,
      maximumDepth: maximumDepth,
      maximumExpandedNodes: maximumExpandedNodes
    )
  }

  /// Lightweight candidate contexts for **sight** elements — used to backfill
  /// cultural element identity after recognition when the prompt only carried a
  /// location-narrowed subset. Abstract cultural-history nodes are excluded
  /// so the model only binds scans to scannable entities.
  func catalogCandidateContexts() -> [KnowledgeCandidateContext] {
    sightElements.map {
      KnowledgeCandidateContext(
        id: $0.id.uuidString,
        name: $0.name,
        introduction: $0.introduction,
        nearbyContexts: []
      )
    }
  }

  /// Builds a recognition element (with BFS graph) for a single pack element.
  func recognitionElement(forID id: UUID) -> RecognitionElement? {
    guard let element = elementsByID[id] else { return nil }
    let graph = recognitionGraph(rootID: id, maxDepth: 3, maxNodes: 32)
    return RecognitionElement(
      id: element.id,
      key: element.key,
      name: element.name,
      introduction: element.introduction,
      nearbyContexts: [],
      relatedElements: relatedElements(forID: id, limit: Self.maximumObjectLimit),
      graphElements: graph.elements,
      graphRelations: graph.relations,
      sources: packSources(forElementID: id)
    )
  }

  func recognitionElement(forKey key: String) -> RecognitionElement? {
    resolveElementID(key).flatMap(recognitionElement(forID:))
  }

  /// Undirected related elements, mirroring `ListRelatedCulturalElements`
  /// (`ORDER BY related.name, related.sortKey`, default limit 12, max 20).
  func relatedElements(
    forID id: UUID,
    limit: Int = KnowledgeStore.defaultCandidateLimit
  ) -> [KnowledgeGraphElement] {
    let limit = clampedLimit(limit)
    var seen = Set<UUID>()
    var neighbors: [UUID] = []
    for relation in relations {
      let neighbor: UUID?
      if relation.elementId == id {
        neighbor = relation.relatedElementId
      } else if relation.relatedElementId == id {
        neighbor = relation.elementId
      } else {
        neighbor = nil
      }
      guard let neighbor, elementsByID[neighbor] != nil, seen.insert(neighbor).inserted
      else { continue }
      neighbors.append(neighbor)
    }
    return
      neighbors
      .compactMap { elementsByID[$0] }
      .sorted { ($0.name, $0.sortKey) < ($1.name, $1.sortKey) }
      .prefix(limit)
      .map {
        KnowledgeGraphElement(
          id: $0.id,
          key: $0.key,
          name: $0.name,
          introduction: $0.introduction,
          conceptKind: $0.conceptKind
        )
      }
  }

  func relatedElements(
    forKey key: String,
    limit: Int = KnowledgeStore.defaultCandidateLimit
  ) -> [KnowledgeGraphElement] {
    guard let id = resolveElementID(key) else { return [] }
    return relatedElements(forID: id, limit: limit)
  }

  // MARK: - Abstraction axis traversal (design 0006)

  /// Edges whose other endpoint is more abstract than `id`: audited upward
  /// outgoing edges (位于/体现/受到影响/受规制于/解释) plus incoming 组成 edges
  /// (a 组成 source is the whole, hence the parent). `产生于` stays out until
  /// its orientation audit lands; pass `includeUnaudited` to opt in.
  func upward(id: UUID, includeUnaudited: Bool = false) -> [DirectedRelationEdge] {
    let outgoingUp = outgoingEdges[id, default: []].filter { edge in
      guard edge.kind?.abstractionDirection == .up else { return false }
      return includeUnaudited || edge.kind?.isAuditedUpward == true
    }
    let incomingDown = incomingEdges[id, default: []].filter {
      $0.kind?.abstractionDirection == .down
    }
    return outgoingUp + incomingDown
  }

  func upward(key: String, includeUnaudited: Bool = false) -> [DirectedRelationEdge] {
    guard let id = resolveElementID(key) else { return [] }
    return upward(id: id, includeUnaudited: includeUnaudited)
  }

  /// Edges whose other endpoint is more concrete than `id`.
  func downward(id: UUID, includeUnaudited: Bool = false) -> [DirectedRelationEdge] {
    let outgoingDown = outgoingEdges[id, default: []].filter {
      $0.kind?.abstractionDirection == .down
    }
    let incomingUp = incomingEdges[id, default: []].filter { edge in
      guard edge.kind?.abstractionDirection == .up else { return false }
      return includeUnaudited || edge.kind?.isAuditedUpward == true
    }
    return outgoingDown + incomingUp
  }

  func downward(key: String, includeUnaudited: Bool = false) -> [DirectedRelationEdge] {
    guard let id = resolveElementID(key) else { return [] }
    return downward(id: id, includeUnaudited: includeUnaudited)
  }

  /// Same-level edges (相似于 plus the orientation-pending kinds treated as
  /// lateral until audited: 用于/象征/制作采用).
  func lateral(id: UUID) -> [DirectedRelationEdge] {
    outgoingEdges[id, default: []].filter { $0.kind?.abstractionDirection == .lateral }
      + incomingEdges[id, default: []].filter { $0.kind?.abstractionDirection == .lateral }
  }

  func lateral(key: String) -> [DirectedRelationEdge] {
    guard let id = resolveElementID(key) else { return [] }
    return lateral(id: id)
  }

  /// Outgoing + incoming edges of `id` filtered to the given relation kinds,
  /// direction-agnostic (`edge.id` is always the *other* endpoint). Used by
  /// the explanation contract's relation dimensions (历史时期/地域文化/…),
  /// where the edge's `explanation` text carries the semantics and direction
  /// is deliberately not interpreted (`产生于` is still orientation-pending).
  func edges(id: UUID, kinds: Set<RelationKind>) -> [DirectedRelationEdge] {
    var seen = Set<UUID>()
    var result: [DirectedRelationEdge] = []
    for edge in outgoingEdges[id, default: []] + incomingEdges[id, default: []] {
      guard let kind = edge.kind, kinds.contains(kind), seen.insert(edge.id).inserted
      else { continue }
      result.append(edge)
    }
    return result
  }

  func edges(key: String, kinds: Set<RelationKind>) -> [DirectedRelationEdge] {
    guard let id = resolveElementID(key) else { return [] }
    return edges(id: id, kinds: kinds)
  }

  /// BFS over upward edges, grouped by first-arrival level. A node reached
  /// again through a cycle keeps its earliest level, so results stay
  /// deterministic even while the pack still contains unaudited edges.
  func ancestors(id: UUID, maxLevels: Int = 5) -> [AbstractionLevel] {
    var levelByID: [UUID: Int] = [id: 0]
    var edgeByID: [UUID: DirectedRelationEdge] = [:]
    var queue: [UUID] = [id]
    var queueIndex = 0
    while queueIndex < queue.count {
      let current = queue[queueIndex]
      queueIndex += 1
      let currentLevel = levelByID[current] ?? 0
      guard currentLevel < maxLevels else { continue }
      for edge in upward(id: current) {
        guard elementsByID[edge.id] != nil, levelByID[edge.id] == nil else { continue }
        levelByID[edge.id] = currentLevel + 1
        edgeByID[edge.id] = edge
        queue.append(edge.id)
      }
    }

    var elementsByLevel: [Int: [AbstractionAncestor]] = [:]
    for (ancestorID, level) in levelByID where level > 0 {
      guard let element = elementsByID[ancestorID] else { continue }
      let edge = edgeByID[ancestorID]
      elementsByLevel[level, default: []].append(
        AbstractionAncestor(
          id: ancestorID,
          key: element.key,
          name: element.name,
          kind: edge?.kind,
          explanation: edge?.explanation
        )
      )
    }
    return elementsByLevel.keys.sorted().map { level in
      AbstractionLevel(
        level: level,
        elements: (elementsByLevel[level] ?? []).sorted {
          let lhsPriority = $0.kind?.abstractionBackbonePriority ?? .max
          let rhsPriority = $1.kind?.abstractionBackbonePriority ?? .max
          if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
          return ($0.name, $0.key ?? $0.id.uuidString) < (
            $1.name, $1.key ?? $1.id.uuidString
          )
        }
      )
    }
  }

  func ancestors(key: String, maxLevels: Int = 5) -> [AbstractionLevel] {
    guard let id = resolveElementID(key) else { return [] }
    return ancestors(id: id, maxLevels: maxLevels)
  }

  /// Nodes sharing at least one upward parent with `id` (同级相关).
  func siblings(id: UUID) -> [UUID] {
    var result = Set<UUID>()
    for parent in upward(id: id) {
      for child in downward(id: parent.id) where child.id != id {
        if elementsByID[child.id] != nil {
          result.insert(child.id)
        }
      }
    }
    return result.sorted { $0.uuidString < $1.uuidString }
  }

  func siblings(key: String) -> [UUID] {
    guard let id = resolveElementID(key) else { return [] }
    return siblings(id: id)
  }

  /// Transitive closure of `理解前先懂` edges pointing at `id` (an edge's
  /// source is the prerequisite, its target the dependent), minus the `known`
  /// element ids, in dependency order (nearest prerequisite first).
  func missingPrerequisites(
    id: UUID,
    known: Set<UUID>,
    maxCount: Int = 3
  ) -> [MissingPrerequisite] {
    var visited: Set<UUID> = [id]
    var queue: [UUID] = [id]
    var queueIndex = 0
    var missing: [MissingPrerequisite] = []
    while queueIndex < queue.count {
      let current = queue[queueIndex]
      queueIndex += 1
      for edge in incomingEdges[current, default: []]
      where edge.kind == .prerequisiteFor && visited.insert(edge.id).inserted {
        queue.append(edge.id)
        guard !known.contains(edge.id), let element = elementsByID[edge.id]
        else { continue }
        missing.append(
          MissingPrerequisite(
            id: edge.id,
            key: element.key,
            name: element.name,
            excerpt: Self.richTextPlainText(element.introduction)
          )
        )
        if missing.count >= maxCount { return missing }
      }
    }
    return missing
  }

  func missingPrerequisites(
    key: String,
    known: Set<String>,
    maxCount: Int = 3
  ) -> [MissingPrerequisite] {
    guard let id = resolveElementID(key) else { return [] }
    let knownIDs = Set(known.compactMap(resolveElementID))
    return missingPrerequisites(id: id, known: knownIDs, maxCount: maxCount)
  }

  // MARK: - Nearby introductions (Haversine, content.sql:209-267)

  /// Mean Earth radius used by the Go SQL query.
  private static let earthRadiusMeters = 6_371_008.8

  static func haversineDistanceMeters(
    fromLatitude: Double,
    fromLongitude: Double,
    toLatitude: Double,
    toLongitude: Double
  ) -> Double {
    let radians = Double.pi / 180
    let deltaLatitude = (toLatitude - fromLatitude) * radians
    let deltaLongitude = (toLongitude - fromLongitude) * radians
    let a =
      pow(sin(deltaLatitude / 2), 2)
      + cos(fromLatitude * radians) * cos(toLatitude * radians)
      * pow(sin(deltaLongitude / 2), 2)
    return earthRadiusMeters * 2 * asin(min(1, sqrt(a)))
  }

  func nearbyIntroductions(
    latitude: Double,
    longitude: Double,
    radiusMeters: Double,
    limit: Int = KnowledgeStore.defaultCandidateLimit
  ) throws -> NearbyIntroductionResult {
    guard
      latitude.isFinite, longitude.isFinite, radiusMeters.isFinite,
      (-90...90).contains(latitude),
      (-180...180).contains(longitude),
      radiusMeters > 0
    else {
      throw KnowledgeStoreError.invalidQuery
    }
    let limit = clampedLimit(limit)

    let matched: [NearbyAttractionIntroduction] = pack.introductions.compactMap { record in
      guard
        let element = elementsByID[record.culturalElementId],
        let attraction = attractionsByID[record.attractionId]
      else { return nil }
      let distance = Self.haversineDistanceMeters(
        fromLatitude: record.latitude,
        fromLongitude: record.longitude,
        toLatitude: latitude,
        toLongitude: longitude
      )
      guard distance <= radiusMeters else { return nil }
      return NearbyAttractionIntroduction(
        key: record.key,
        name: record.name,
        introduction: record.introduction,
        culturalElementId: element.id,
        culturalElementName: element.name,
        attractionId: attraction.id,
        attractionKey: attraction.key,
        attractionName: attraction.name,
        latitude: record.latitude,
        longitude: record.longitude,
        distanceMeters: distance,
        sources: record.sources
      )
    }
    .sorted {
      ($0.distanceMeters, $0.name, $0.sortKey) < ($1.distanceMeters, $1.name, $1.sortKey)
    }

    return NearbyIntroductionResult(
      introductions: Array(matched.prefix(limit)),
      totalMatches: matched.count
    )
  }

  // MARK: - Recognition knowledge (postgres.go RecognitionKnowledge)

  func recognitionKnowledge(
    latitude: Double?,
    longitude: Double?,
    limit: Int = KnowledgeStore.defaultCandidateLimit
  ) throws -> RecognitionKnowledgeSet {
    let limit = clampedLimit(limit)

    var nearby: [NearbyAttractionIntroduction] = []
    if let latitude, let longitude, !orderedElementIDs.isEmpty {
      nearby = try nearbyIntroductions(
        latitude: latitude,
        longitude: longitude,
        radiusMeters: Self.recognitionRadiusMeters,
        limit: max(Self.maximumObjectLimit, pack.introductions.count)
      ).introductions
    }

    var attractionRoots: [UUID: UUID] = [:]
    var attractionNames: [UUID: String] = [:]
    var attractionBindings: [UUID: Set<UUID>] = [:]
    var attractionCandidates: [AttractionCandidate] = []
    var seenAttractions = Set<UUID>()
    for introduction in nearby {
      // Prefer the scannable sight that shares the attraction slug (实体即景点).
      // History intro bindings stay in nearby_contexts / post-bind graph only.
      let preferredRoot =
        sightElementID(forAttraction: introduction.attractionId)
        ?? (isSight(introduction.culturalElementId) ? introduction.culturalElementId : nil)
      if attractionRoots[introduction.attractionId] == nil {
        if let preferredRoot {
          attractionRoots[introduction.attractionId] = preferredRoot
        }
        attractionNames[introduction.attractionId] = introduction.attractionName
      }
      if let root = attractionRoots[introduction.attractionId] {
        attractionBindings[introduction.attractionId, default: []].insert(root)
      }
      // History targets remain graph bindings under the sight root after resolve.
      attractionBindings[introduction.attractionId, default: []]
        .insert(introduction.culturalElementId)

      guard seenAttractions.insert(introduction.attractionId).inserted else { continue }
      let rootID = attractionRoots[introduction.attractionId] ?? preferredRoot
      guard let rootID else { continue }
      let rootElement = elementsByID[rootID]
      attractionCandidates.append(
        AttractionCandidate(
          id: introduction.attractionId,
          key: introduction.attractionKey,
          name: introduction.attractionName,
          culturalElementId: rootID,
          culturalElementKey: rootElement?.key,
          summary: Self.richTextPlainText(introduction.introduction, separator: "\n\n"),
          distanceMeters: introduction.distanceMeters,
          sources: introduction.sources
        )
      )
    }

    let selectedAttractionIDs = Set(attractionCandidates.map(\.id))
    let prioritizedIDs = prioritizedRecognitionIDs(
      nearby: nearby,
      attractionRoots: attractionRoots,
      selectedAttractionIDs: selectedAttractionIDs,
      allowCulturalCatalogFill: attractionCandidates.count
        < Self.minimumAttractionsBeforeCulturalFill,
      limit: limit
    )

    // Attach every on-site intro to the sight root for that attraction so the
    // model still sees history context without being allowed to cite it as id.
    var nearbyContexts: [UUID: [NearbyAttractionIntroduction]] = [:]
    for introduction in nearby {
      let attachID =
        attractionRoots[introduction.attractionId]
        ?? sightElementID(forAttraction: introduction.attractionId)
      guard let attachID, elementsByID[attachID] != nil else { continue }
      nearbyContexts[attachID, default: []].append(introduction)
    }

    var elements: [RecognitionElement] = []
    elements.reserveCapacity(prioritizedIDs.count)
    for id in prioritizedIDs {
      guard let element = elementsByID[id] else { continue }
      var graph = recognitionGraph(rootID: id, maxDepth: 3, maxNodes: 32)
      graph = appendAttractionBindings(
        rootID: id,
        attractionRoots: attractionRoots,
        attractionNames: attractionNames,
        bindings: attractionBindings,
        graphElements: graph.elements,
        graphRelations: graph.relations
      )
      let contexts = nearbyContexts[id] ?? []
      var elementSources = packSources(forElementID: id)
      var seenSourceURLs = Set(
        elementSources.compactMap { $0.url?.lowercased() }
      )
      for context in contexts {
        for source in context.sources {
          let identity = (source.url ?? source.title).lowercased()
          guard seenSourceURLs.insert(identity).inserted else { continue }
          elementSources.append(source)
        }
      }
      elements.append(
        RecognitionElement(
          id: element.id,
          key: element.key,
          name: element.name,
          introduction: element.introduction,
          nearbyContexts: contexts,
          relatedElements: relatedElements(
            forID: id,
            limit: Self.maximumObjectLimit
          ),
          graphElements: graph.elements,
          graphRelations: graph.relations,
          sources: elementSources
        )
      )
    }

    return RecognitionKnowledgeSet(
      version: pack.version,
      elements: elements,
      attractionCandidates: attractionCandidates,
      totalElements: orderedElementIDs.count,
      nearbyContextCount: nearby.count,
      locationMatched: !nearby.isEmpty
    )
  }

  /// Cultural-content candidates for the recognition prompt — **sights only**.
  /// History nodes may appear in nearby_contexts / graph after binding, but the
  /// model must not cite them as the primary cultural element id.
  /// Priority:
  /// 1. Sight roots for selected nearby attractions (uncapped — all within 1 km)
  /// 2. Other sight elements bound via introductions to those attractions
  /// 3. Only when nearby attractions < 3: remaining sight catalog by name (capped)
  private func prioritizedRecognitionIDs(
    nearby: [NearbyAttractionIntroduction],
    attractionRoots: [UUID: UUID],
    selectedAttractionIDs: Set<UUID>,
    allowCulturalCatalogFill: Bool,
    limit: Int
  ) -> [UUID] {
    var prioritizedIDs: [UUID] = []
    var seen = Set<UUID>()

    func appendSight(_ id: UUID) {
      guard isSight(id), seen.insert(id).inserted else { return }
      prioritizedIDs.append(id)
    }

    let selectedNearby = nearby.filter { selectedAttractionIDs.contains($0.attractionId) }

    for introduction in selectedNearby {
      if let id = attractionRoots[introduction.attractionId] {
        appendSight(id)
      }
      // Entity-as-attraction: inject the sight that shares the attraction slug.
      if let sightID = sightElementID(forAttraction: introduction.attractionId) {
        appendSight(sightID)
      }
    }
    for introduction in selectedNearby {
      appendSight(introduction.culturalElementId)
    }

    guard allowCulturalCatalogFill else { return prioritizedIDs }

    for introduction in nearby {
      if let sightID = sightElementID(forAttraction: introduction.attractionId) {
        appendSight(sightID)
      }
      appendSight(introduction.culturalElementId)
      if prioritizedIDs.count >= limit { return prioritizedIDs }
    }
    for id in orderedElementIDs {
      appendSight(id)
      if prioritizedIDs.count >= limit { return prioritizedIDs }
    }
    return prioritizedIDs
  }

  /// True when the element exists and resolves to `ContentRole.sight`.
  private func isSight(_ id: UUID) -> Bool {
    guard let element = elementsByID[id] else { return false }
    return element.resolvedContentRole() == .sight
  }

  /// Sight element that shares the attraction slug, when present (实体即景点).
  private func sightElementID(forAttraction attractionId: UUID) -> UUID? {
    guard let attraction = attractionsByID[attractionId],
      let slug = attraction.key?.lowercased(),
      let elementID = elementIDsByKey[slug],
      isSight(elementID)
    else { return nil }
    return elementID
  }

  // MARK: - Graph traversal (postgres.go recognitionGraph / appendAttractionBindings)

  private func recognitionGraph(
    rootID: UUID,
    maxDepth: Int,
    maxNodes: Int
  ) -> (elements: [KnowledgeGraphElement], relations: [KnowledgeGraphRelation]) {
    var depths = [rootID: 0]
    var queue = [rootID]
    while !queue.isEmpty && depths.count < maxNodes + 1 {
      let current = queue.removeFirst()
      let depth = depths[current] ?? 0
      guard depth < maxDepth else { continue }
      for relation in relations {
        let next: UUID
        if relation.elementId == current {
          next = relation.relatedElementId
        } else if relation.relatedElementId == current {
          next = relation.elementId
        } else {
          continue
        }
        guard elementsByID[next] != nil else { continue }
        if depths[next] == nil && depths.count < maxNodes + 1 {
          depths[next] = depth + 1
          queue.append(next)
        }
      }
    }

    let sortedIDs = depths.keys.sorted {
      (depths[$0] ?? 0, $0.uuidString) < (depths[$1] ?? 0, $1.uuidString)
    }
    let graphElements =
      sortedIDs
      .filter { $0 != rootID }
      .compactMap { elementsByID[$0] }
      .map {
        KnowledgeGraphElement(
          id: $0.id,
          key: $0.key,
          name: $0.name,
          introduction: $0.introduction,
          conceptKind: $0.conceptKind
        )
      }
    let graphRelations = relations.compactMap { relation -> KnowledgeGraphRelation? in
      guard depths[relation.elementId] != nil, depths[relation.relatedElementId] != nil
      else { return nil }
      return KnowledgeGraphRelation(
        elementId: relation.elementId,
        relatedElementId: relation.relatedElementId,
        kind: relation.kind ?? "解释",
        explanation: relation.explanation
          ?? String(localized: "文化内容库记录了两个概念之间的显式关联。")
      )
    }
    return (graphElements, graphRelations)
  }

  private func appendAttractionBindings(
    rootID: UUID,
    attractionRoots: [UUID: UUID],
    attractionNames: [UUID: String],
    bindings: [UUID: Set<UUID>],
    graphElements: [KnowledgeGraphElement],
    graphRelations: [KnowledgeGraphRelation]
  ) -> (elements: [KnowledgeGraphElement], relations: [KnowledgeGraphRelation]) {
    var graphElements = graphElements
    var graphRelations = graphRelations
    var seenElements: Set<UUID> = [rootID]
    seenElements.formUnion(graphElements.map(\.id))
    var seenEdges = Set<String>()
    for relation in graphRelations {
      seenEdges.insert(
        relation.elementId.uuidString + "\0" + relation.relatedElementId.uuidString)
      seenEdges.insert(
        relation.relatedElementId.uuidString + "\0" + relation.elementId.uuidString)
    }

    for attractionID in attractionRoots.keys.sorted(by: { $0.uuidString < $1.uuidString })
    where attractionRoots[attractionID] == rootID {
      for boundID in (bindings[attractionID] ?? []).sorted(by: {
        $0.uuidString < $1.uuidString
      }) {
        guard boundID != rootID else { continue }
        if !seenElements.contains(boundID) {
          guard let element = elementsByID[boundID] else { continue }
          graphElements.append(
            KnowledgeGraphElement(
              id: element.id,
              key: element.key,
              name: element.name,
              introduction: element.introduction,
              conceptKind: element.conceptKind
            )
          )
          seenElements.insert(boundID)
        }
        let edgeKey = rootID.uuidString + "\0" + boundID.uuidString
        guard !seenEdges.contains(edgeKey) else { continue }
        graphRelations.append(
          KnowledgeGraphRelation(
            elementId: rootID,
            relatedElementId: boundID,
            kind: "解释",
            explanation: String(
              localized:
                "该文化元素通过“\(attractionNames[attractionID] ?? "")”的现场介绍直接关联到当前景点。"
            )
          )
        )
        seenEdges.insert(edgeKey)
        seenEdges.insert(boundID.uuidString + "\0" + rootID.uuidString)
      }
    }
    return (graphElements, graphRelations)
  }

  // MARK: - Helpers

  private func clampedLimit(_ limit: Int) -> Int {
    if limit <= 0 { return Self.defaultCandidateLimit }
    return min(limit, Self.maximumObjectLimit)
  }

  /// Flattens rich text blocks like the Go pipeline: trimmed, non-empty block
  /// texts joined by the given separator ("\n" in the response mapper,
  /// "\n\n" for attraction candidate summaries).
  static func richTextPlainText(
    _ document: RichTextDocument,
    separator: String = "\n"
  ) -> String {
    document.blocks
      .compactMap(\.text)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: separator)
  }
}
