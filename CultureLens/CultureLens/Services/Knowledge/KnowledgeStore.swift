import Foundation

/// Locates a bundled resource whether the build system flattened the
/// synchronized group into the bundle root or preserved subdirectories.
/// `subdirectory` candidates cover both the ODR pack layout and the embedded
/// fallback copy (`Resources/KnowledgePackFallback/`).
nonisolated func bundledResourceURL(
  _ name: String,
  _ ext: String,
  subdirectory: String,
  bundle: Bundle
) -> URL? {
  let subdirectories = [
    subdirectory,
    "KnowledgePackFallback",
    "Resources/\(subdirectory)",
    "Resources/KnowledgePackFallback",
  ]
  for candidate in subdirectories {
    if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: candidate) {
      return url
    }
  }
  return bundle.url(forResource: name, withExtension: ext)
}

/// Known knowledge-pack resource directories, in merge priority order.
/// Earlier packs win on key collision. `KnowledgePackFallback` is last so the
/// ODR / primary West Lake pack overrides the embedded duplicate.
nonisolated enum KnowledgePackDirectory: String, CaseIterable, Sendable {
  case westLake = "KnowledgePack"
  case chineseHistory = "KnowledgePackChineseHistory"
  case liangzhu = "KnowledgePackLiangzhu"
  case zhejiangMuseum = "KnowledgePackZhejiangMuseum"
  case fallback = "KnowledgePackFallback"

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
/// (`internal/knowledge/postgres.go`), backed by the bundled knowledge pack
/// instead of PostgreSQL.
nonisolated struct KnowledgeStore: Sendable {
  static let defaultCandidateLimit = 12
  static let maximumObjectLimit = 48
  static let maximumGraphExpansionNodes = 48
  static let defaultRadiusMeters = 50_000.0
  /// Pull unbound cultural nodes into the recognition prompt only when fewer
  /// than this many nearby attractions are available.
  static let minimumAttractionsBeforeCulturalFill = 3
  /// Cap nearby attraction candidates sent to the model (nearest first).
  static let maximumAttractionCandidates = 8

  let pack: KnowledgePack

  /// Element keys in `ListCulturalElements` order (`ORDER BY name, key`).
  private let orderedElementKeys: [String]
  private let elementsByKey: [String: KnowledgePack.Element]
  private let elementKeysByID: [UUID: String]
  /// Source pack `version` for each element key (first pack wins on collision).
  private let packVersionByElementKey: [String: String]
  /// Directed pack relations in stable lexicographic order. Endpoint order and
  /// optional `kind` / `explanation` are preserved so typed edges stay usable
  /// downstream; adjacency treats them as undirected for BFS.
  private let relations: [KnowledgePack.Relation]
  private let adjacency: [String: [String]]
  /// Directed indexes keyed by endpoint. `outgoingEdges[k]` lists edges whose
  /// source is `k` (target in `DirectedRelationEdge.key`); `incomingEdges[k]`
  /// lists edges whose target is `k` (source in `.key`).
  private let outgoingEdges: [String: [DirectedRelationEdge]]
  private let incomingEdges: [String: [DirectedRelationEdge]]
  private let introductionsByKey: [String: KnowledgePack.IntroductionRecord]

  init(pack: KnowledgePack, packVersionByElementKey: [String: String] = [:]) {
    self.pack = pack
    elementsByKey = Dictionary(
      pack.elements.map { ($0.key, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    elementKeysByID = Dictionary(
      pack.elements.map { (DeterministicID.culturalElement($0.key), $0.key) },
      uniquingKeysWith: { first, _ in first }
    )
    if packVersionByElementKey.isEmpty {
      self.packVersionByElementKey = Dictionary(
        uniqueKeysWithValues: pack.elements.map { ($0.key, pack.version) }
      )
    } else {
      self.packVersionByElementKey = packVersionByElementKey
    }
    orderedElementKeys = pack.elements
      .sorted { ($0.name, $0.key) < ($1.name, $1.key) }
      .map(\.key)
    let normalizedRelations = pack.relations
      .sorted { ($0.elementKey, $0.relatedElementKey) < ($1.elementKey, $1.relatedElementKey) }
    relations = normalizedRelations
    var adjacencySets: [String: Set<String>] = [:]
    for relation in normalizedRelations {
      adjacencySets[relation.elementKey, default: []].insert(relation.relatedElementKey)
      adjacencySets[relation.relatedElementKey, default: []].insert(relation.elementKey)
    }
    adjacency = adjacencySets.mapValues { $0.sorted() }
    var outgoing: [String: [DirectedRelationEdge]] = [:]
    var incoming: [String: [DirectedRelationEdge]] = [:]
    for relation in normalizedRelations {
      let kind = relation.kind.flatMap { RelationKind(rawValue: $0) }
      outgoing[relation.elementKey, default: []].append(
        DirectedRelationEdge(
          key: relation.relatedElementKey,
          kind: kind,
          explanation: relation.explanation
        )
      )
      incoming[relation.relatedElementKey, default: []].append(
        DirectedRelationEdge(
          key: relation.elementKey,
          kind: kind,
          explanation: relation.explanation
        )
      )
    }
    outgoingEdges = outgoing
    incomingEdges = incoming
    introductionsByKey = Dictionary(
      pack.introductions.map { ($0.key, $0) },
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
      pack: mergePacks(packs),
      packVersionByElementKey: packVersionsByElement(from: packs)
    )
  }

  /// First-seen pack version for each element key.
  static func packVersionsByElement(from packs: [KnowledgePack]) -> [String: String] {
    var map: [String: String] = [:]
    for pack in packs {
      for element in pack.elements where map[element.key] == nil {
        map[element.key] = pack.version
      }
    }
    return map
  }

  /// Decodes packs from `bundle` in `KnowledgePackDirectory` priority order.
  /// Duplicate directory names (e.g. Fallback after West Lake) are skipped when
  /// their content would only repeat already-loaded keys — callers that need
  /// raw per-pack lists should use this before `mergePacks`.
  ///
  /// Layout (sidecar-first, see `agents/KNOWLEDGE_PACK_GUIDE.md`):
  /// - `knowledge-pack.json` — version / source_language / relations
  /// - `elements-sight.json` — 看点 elements + attractions
  /// - `elements-history.json` — 文化历史 elements
  /// - `introductions.json` — on-site introductions
  /// - `themes.json` — exploration themes
  /// - `locales-<tag>.json` — one LocaleOverlay per language (e.g. `locales-en.json`)
  /// - `pack-manifest.json` — counts / sha256 (not loaded into the store)
  static func discoverPacks(in bundle: Bundle) throws -> [KnowledgePack] {
    var packs: [KnowledgePack] = []
    var seenVersions = Set<String>()
    for directory in KnowledgePackDirectory.allCases {
      guard let url = packURL(in: bundle, directory: directory) else { continue }
      do {
        let data = try Data(contentsOf: url)
        var pack = try JSONDecoder().decode(KnowledgePack.self, from: data)
        pack = try mergingPackSidecars(into: pack, directory: directory, bundle: bundle)
        // Skip Fallback when the primary West Lake pack (same version family)
        // was already loaded from ODR / KnowledgePack.
        if directory == .fallback, packs.contains(where: { $0.version == pack.version }) {
          continue
        }
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

  /// Loads optional sidecars and merges them into `pack`. Inline main-file
  /// entries still win on key collision (backward compatible with monolithic JSON).
  private static func mergingPackSidecars(
    into pack: KnowledgePack,
    directory: KnowledgePackDirectory,
    bundle: Bundle
  ) throws -> KnowledgePack {
    var elementsByKey = Dictionary(
      pack.elements.map { ($0.key, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    var attractionsByKey = Dictionary(
      pack.attractions.map { ($0.key, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    var introductionsByKey = Dictionary(
      pack.introductions.map { ($0.key, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    var themesByKey = Dictionary(
      pack.themes.map { ($0.key, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    var locales = pack.locales ?? [:]
    var didLoadSidecar = false

    if let url = sidecarURL(named: "elements-sight", directory: directory, bundle: bundle) {
      let file = try JSONDecoder().decode(
        KnowledgePackSightFile.self,
        from: Data(contentsOf: url)
      )
      didLoadSidecar = true
      for raw in file.elements where elementsByKey[raw.key] == nil {
        elementsByKey[raw.key] = KnowledgePack.Element(
          key: raw.key,
          name: raw.name,
          introduction: raw.introduction,
          sources: raw.sources,
          conceptKind: raw.conceptKind,
          contentRole: .sight
        )
      }
      for attraction in file.attractions where attractionsByKey[attraction.key] == nil {
        attractionsByKey[attraction.key] = attraction
      }
    }

    if let url = sidecarURL(named: "elements-history", directory: directory, bundle: bundle) {
      let file = try JSONDecoder().decode(
        KnowledgePackHistoryFile.self,
        from: Data(contentsOf: url)
      )
      didLoadSidecar = true
      for raw in file.elements where elementsByKey[raw.key] == nil {
        elementsByKey[raw.key] = KnowledgePack.Element(
          key: raw.key,
          name: raw.name,
          introduction: raw.introduction,
          sources: raw.sources,
          conceptKind: raw.conceptKind,
          contentRole: .culturalHistory
        )
      }
    }

    if let url = sidecarURL(named: "introductions", directory: directory, bundle: bundle) {
      let file = try JSONDecoder().decode(
        KnowledgePackIntroductionsFile.self,
        from: Data(contentsOf: url)
      )
      didLoadSidecar = true
      for record in file.introductions where introductionsByKey[record.key] == nil {
        introductionsByKey[record.key] = record
      }
    }

    if let url = sidecarURL(named: "themes", directory: directory, bundle: bundle) {
      let file = try JSONDecoder().decode(
        KnowledgePackThemesFile.self,
        from: Data(contentsOf: url)
      )
      didLoadSidecar = true
      for theme in file.themes where themesByKey[theme.key] == nil {
        themesByKey[theme.key] = theme
      }
    }

    for language in Self.knownLocaleSidecarTags {
      let name = "locales-\(language)"
      guard let url = sidecarURL(named: name, directory: directory, bundle: bundle)
      else { continue }
      let overlay = try JSONDecoder().decode(
        KnowledgePack.LocaleOverlay.self,
        from: Data(contentsOf: url)
      )
      didLoadSidecar = true
      if locales[language] == nil {
        locales[language] = overlay
      } else {
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

    guard didLoadSidecar else { return pack }
    return KnowledgePack(
      version: pack.version,
      sourceLanguage: pack.sourceLanguage,
      elements: elementsByKey.values.sorted { ($0.name, $0.key) < ($1.name, $1.key) },
      attractions: attractionsByKey.values.sorted { ($0.name, $0.key) < ($1.name, $1.key) },
      relations: pack.relations,
      introductions: introductionsByKey.values.sorted { ($0.name, $0.key) < ($1.name, $1.key) },
      themes: themesByKey.values.sorted { ($0.name, $0.key) < ($1.name, $1.key) },
      locales: locales.isEmpty ? nil : locales
    )
  }

  /// Locale tags we look for as `locales-<tag>.json` sidecars.
  private static let knownLocaleSidecarTags = ["en", "zh-Hans"]

  private static func sidecarURL(
    named name: String,
    directory: KnowledgePackDirectory,
    bundle: Bundle
  ) -> URL? {
    for subdirectory in directory.subdirectoryCandidates {
      if let url = bundle.url(forResource: name, withExtension: "json", subdirectory: subdirectory)
      {
        return url
      }
    }
    return bundledResourceURL(name, "json", subdirectory: directory.rawValue, bundle: bundle)
  }

  /// Merges packs; earlier entries win on element / attraction / introduction /
  /// theme key collisions. Relations whose endpoints both survive are kept.
  /// Locale overlays are unioned per language, with earlier packs winning keys.
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

    var elements: [String: KnowledgePack.Element] = [:]
    var attractions: [String: KnowledgePack.Attraction] = [:]
    var introductions: [String: KnowledgePack.IntroductionRecord] = [:]
    var themes: [String: KnowledgePack.Theme] = [:]
    var relations: [KnowledgePack.Relation] = []
    var seenRelation = Set<String>()
    var locales: [String: KnowledgePack.LocaleOverlay] = [:]
    var sourceLanguage = first.sourceLanguage

    for pack in packs {
      if sourceLanguage == nil { sourceLanguage = pack.sourceLanguage }
      for element in pack.elements where elements[element.key] == nil {
        elements[element.key] = element
      }
      for attraction in pack.attractions where attractions[attraction.key] == nil {
        attractions[attraction.key] = attraction
      }
      for introduction in pack.introductions where introductions[introduction.key] == nil {
        introductions[introduction.key] = introduction
      }
      for theme in pack.themes where themes[theme.key] == nil {
        themes[theme.key] = theme
      }
      for relation in pack.relations {
        let signature = [
          relation.elementKey,
          relation.relatedElementKey,
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
      elements[$0.elementKey] != nil && elements[$0.relatedElementKey] != nil
    }
    // Themes may reference keys from their home pack only; drop dangling keys.
    let cleanedThemes = themes.values.map { theme in
      KnowledgePack.Theme(
        key: theme.key,
        name: theme.name,
        summary: theme.summary,
        elementKeys: theme.elementKeys.filter { elements[$0] != nil },
        minContacted: theme.minContacted
      )
    }
    .filter { !$0.elementKeys.isEmpty }
    .sorted { ($0.name, $0.key) < ($1.name, $1.key) }

    let version = packs.map(\.version).joined(separator: "+")
    return KnowledgePack(
      version: version,
      sourceLanguage: sourceLanguage,
      elements: elements.values.sorted { ($0.name, $0.key) < ($1.name, $1.key) },
      attractions: attractions.values.sorted { ($0.name, $0.key) < ($1.name, $1.key) },
      relations: relations.sorted {
        ($0.elementKey, $0.relatedElementKey) < ($1.elementKey, $1.relatedElementKey)
      },
      introductions: introductions.values.sorted { ($0.name, $0.key) < ($1.name, $1.key) },
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

  /// Shared store cached on first access; `nil` when the bundle lacks a pack.
  static let shared: KnowledgeStore? = try? KnowledgeStore.load()

  // MARK: - Basic lookups

  var elements: [KnowledgePack.Element] {
    orderedElementKeys.compactMap { elementsByKey[$0] }
  }

  /// Elements filtered to one or more `ContentRole` values (name, key order).
  func elements(roles: Set<ContentRole>) -> [KnowledgePack.Element] {
    guard !roles.isEmpty else { return [] }
    return elements.filter { roles.contains($0.resolvedContentRole) }
  }

  func elements(role: ContentRole) -> [KnowledgePack.Element] {
    elements(roles: [role])
  }

  /// Photographable attraction-layer nodes (`ContentRole.sight`).
  var sightElements: [KnowledgePack.Element] {
    elements(role: .sight)
  }

  /// Abstract cultural / historical nodes without their own physical target.
  var culturalHistoryElements: [KnowledgePack.Element] {
    elements(role: .culturalHistory)
  }

  func element(key: String) -> KnowledgePack.Element? {
    elementsByKey[key]
  }

  func elementKey(for nodeID: UUID) -> String? {
    elementKeysByID[nodeID]
  }

  func element(id: UUID) -> KnowledgePack.Element? {
    elementKeysByID[id].flatMap { elementsByKey[$0] }
  }

  func introduction(key: String) -> KnowledgePack.IntroductionRecord? {
    introductionsByKey[key]
  }

  func cultureConcept(elementKey: String) -> CultureConcept? {
    guard let element = elementsByKey[elementKey] else { return nil }
    return CultureConcept(
      id: DeterministicID.culturalElement(element.key),
      name: element.name,
      kind: CulturalElementPresentation.conceptKind(element.conceptKind),
      summary: Self.richTextPlainText(element.introduction),
      detail: ""
    )
  }

  /// Best-effort reverse lookup when a citation URL only carries a display name.
  func elementKey(matchingName name: String) -> String? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let exact = elementsByKey.first(where: { $0.value.name == trimmed })?.key {
      return exact
    }
    return elementsByKey.first(where: { $0.value.name.contains(trimmed) || trimmed.contains($0.value.name) })?
      .key
  }

  /// Rich introduction for detail pages; falls back to `nil` when unresolved.
  func introductionDocument(elementKey: String) -> RichTextDocument? {
    elementsByKey[elementKey]?.introduction
  }

  func introductionDocument(nodeID: UUID) -> RichTextDocument? {
    element(id: nodeID)?.introduction
  }

  /// Trusted external sources for an element: pack-level `sources` plus
  /// provenance URLs from linked on-site introductions (Wikipedia, Amap, …).
  func trustedSources(forElementKey key: String) -> [KnowledgeSource] {
    packSources(forElementKey: key).map { $0.asKnowledgeSource() }
  }

  func packSources(forElementKey key: String) -> [KnowledgePack.Source] {
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

    if let element = elementsByKey[key] {
      append(element.sources)
    }
    for record in pack.introductions
    where record.culturalElementKey.caseInsensitiveCompare(key) == .orderedSame {
      append(record.sources)
    }
    return result
  }

  // MARK: - Attraction points (POI map)

  /// All attractions in the bundled packs as map points, aggregated from the
  /// on-site introduction records (which carry the coordinates). Records
  /// cluster per physical location (attraction key + coordinates rounded to 3
  /// decimals): the same attraction key hosted at different sites — across
  /// packs or across intro records — yields one point per site instead of
  /// collapsing into the first record's location.
  func attractionPoints() -> [AttractionPoint] {
    var nameByAttraction: [String: String] = [:]
    for attraction in pack.attractions {
      nameByAttraction[attraction.key] = attraction.name
    }
    var firstRecordByLocation: [String: KnowledgePack.IntroductionRecord] = [:]
    for record in pack.introductions {
      let locationKey = record.attractionKey + "|"
        + String(format: "%.3f", record.latitude) + ","
        + String(format: "%.3f", record.longitude)
      if firstRecordByLocation[locationKey] == nil {
        firstRecordByLocation[locationKey] = record
      }
    }
    return firstRecordByLocation.values.compactMap { record in
      let name = nameByAttraction[record.attractionKey] ?? record.name
      guard !name.isEmpty else { return nil }
      let elementKey = elementsByKey[record.culturalElementKey] != nil
        ? record.culturalElementKey
        : nil
      return AttractionPoint(
        key: record.attractionKey,
        name: name,
        culturalElementKey: elementKey,
        latitude: record.latitude,
        longitude: record.longitude
      )
    }
    .sorted {
      ($0.name, $0.key, $0.latitude, $0.longitude)
        < ($1.name, $1.key, $1.latitude, $1.longitude)
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
    let joinedElementKeys = Set(joinedIDs.compactMap { elementKeysByID[$0] })

    let defaultCenterIDs: [UUID] = {
      let packBacked = orderedElementKeys
        .filter { joinedElementKeys.contains($0) }
        .map(DeterministicID.culturalElement)
      if !packBacked.isEmpty { return packBacked }
      return joinedSeeds.sorted {
        if $0.name != $1.name { return $0.name.localizedCompare($1.name) == .orderedAscending }
        return $0.id.uuidString < $1.id.uuidString
      }.prefix(1).map(\.id)
    }()
    var seenCenterIDs = Set<UUID>()
    let requestedCenters = requestedCenterIDs.filter { id in
      (elementKeysByID[id] != nil || joinedIDs.contains(id))
        && seenCenterIDs.insert(id).inserted
    }
    let centerIDs = requestedCenters.isEmpty ? defaultCenterIDs : requestedCenters
    var seenCenterKeys = Set<String>()
    let centerKeys = centerIDs.compactMap { elementKeysByID[$0] }
      .filter { seenCenterKeys.insert($0).inserted }

    var hops: [String: Int] = [:]
    var queue: [String] = []
    var queueIndex = 0
    var isTruncated = false
    for key in centerKeys {
      hops[key] = 0
      queue.append(key)
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

    var visibleElementKeys = joinedElementKeys
    visibleElementKeys.formUnion(hops.keys)
    var nodes = visibleElementKeys.compactMap { key -> UserKnowledgeGraphNode? in
      guard let element = elementsByKey[key] else { return nil }
      let id = DeterministicID.culturalElement(key)
      return UserKnowledgeGraphNode(
        id: id,
        elementKey: key,
        name: element.name,
        summary: Self.richTextPlainText(element.introduction),
        kind: CulturalElementPresentation.conceptKind(element.conceptKind),
        hop: hops[key] ?? depthLimit + 1,
        isJoined: joinedIDs.contains(id)
      )
    }

    for seed in joinedSeeds where elementKeysByID[seed.id] == nil {
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
        visibleElementKeys.contains(relation.elementKey),
        visibleElementKeys.contains(relation.relatedElementKey)
      else { return nil }
      return UserKnowledgeGraphEdge(
        id: DeterministicID.v5(
          name: "culturelens:user-graph:\(relation.elementKey):\(relation.relatedElementKey)"
        ),
        sourceID: DeterministicID.culturalElement(relation.elementKey),
        targetID: DeterministicID.culturalElement(relation.relatedElementKey),
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

  /// Lightweight candidate contexts for every **看点** element — used to
  /// backfill `cultural_element_key` after recognition when the prompt only
  /// carried a location-narrowed subset. Cultural-history nodes stay out of
  /// this catalog so name binding prefers photographable targets.
  func catalogCandidateContexts() -> [KnowledgeCandidateContext] {
    sightElements.map {
      KnowledgeCandidateContext(
        key: $0.key,
        name: $0.name,
        introduction: $0.introduction,
        nearbyContexts: []
      )
    }
  }

  /// Full-pack catalog (selected roles) for callers that need name resolution
  /// against cultural-history nodes as well (e.g. graph / Q&A).
  func catalogCandidateContexts(includingRoles roles: Set<ContentRole>) -> [KnowledgeCandidateContext] {
    elements(roles: roles).map {
      KnowledgeCandidateContext(
        key: $0.key,
        name: $0.name,
        introduction: $0.introduction,
        nearbyContexts: []
      )
    }
  }

  /// Builds a recognition element (with BFS graph) for a single pack key.
  func recognitionElement(forKey key: String) -> RecognitionElement? {
    guard let element = elementsByKey[key] else { return nil }
    let graph = recognitionGraph(rootKey: key, maxDepth: 3, maxNodes: 32)
    return RecognitionElement(
      key: element.key,
      name: element.name,
      introduction: element.introduction,
      nearbyContexts: [],
      relatedElements: relatedElements(forKey: key, limit: Self.maximumObjectLimit),
      graphElements: graph.elements,
      graphRelations: graph.relations,
      sources: packSources(forElementKey: key)
    )
  }

  /// Undirected related elements, mirroring `ListRelatedCulturalElements`
  /// (`ORDER BY related.name, related.key`, default limit 12, max 20).
  func relatedElements(
    forKey key: String,
    limit: Int = KnowledgeStore.defaultCandidateLimit
  ) -> [KnowledgeGraphElement] {
    let limit = clampedLimit(limit)
    var seen = Set<String>()
    var neighbors: [String] = []
    for relation in relations {
      let neighbor: String?
      if relation.elementKey == key {
        neighbor = relation.relatedElementKey
      } else if relation.relatedElementKey == key {
        neighbor = relation.elementKey
      } else {
        neighbor = nil
      }
      guard let neighbor, elementsByKey[neighbor] != nil, seen.insert(neighbor).inserted
      else { continue }
      neighbors.append(neighbor)
    }
    return neighbors
      .compactMap { elementsByKey[$0] }
      .sorted { ($0.name, $0.key) < ($1.name, $1.key) }
      .prefix(limit)
      .map {
        KnowledgeGraphElement(
          key: $0.key,
          name: $0.name,
          introduction: $0.introduction,
          conceptKind: $0.conceptKind
        )
      }
  }

  // MARK: - Abstraction axis traversal (design 0006)

  /// Edges whose other endpoint is more abstract than `key`: audited upward
  /// outgoing edges (位于/体现/受到影响/受规制于/解释) plus incoming 组成 edges
  /// (a 组成 source is the whole, hence the parent). `产生于` stays out until
  /// its orientation audit lands; pass `includeUnaudited` to opt in.
  func upward(key: String, includeUnaudited: Bool = false) -> [DirectedRelationEdge] {
    let outgoingUp = outgoingEdges[key, default: []].filter { edge in
      guard edge.kind?.abstractionDirection == .up else { return false }
      return includeUnaudited || edge.kind?.isAuditedUpward == true
    }
    let incomingDown = incomingEdges[key, default: []].filter {
      $0.kind?.abstractionDirection == .down
    }
    return outgoingUp + incomingDown
  }

  /// Edges whose other endpoint is more concrete than `key`.
  func downward(key: String, includeUnaudited: Bool = false) -> [DirectedRelationEdge] {
    let outgoingDown = outgoingEdges[key, default: []].filter {
      $0.kind?.abstractionDirection == .down
    }
    let incomingUp = incomingEdges[key, default: []].filter { edge in
      guard edge.kind?.abstractionDirection == .up else { return false }
      return includeUnaudited || edge.kind?.isAuditedUpward == true
    }
    return outgoingDown + incomingUp
  }

  /// Same-level edges (相似于 plus the orientation-pending kinds treated as
  /// lateral until audited: 用于/象征/制作采用).
  func lateral(key: String) -> [DirectedRelationEdge] {
    outgoingEdges[key, default: []].filter { $0.kind?.abstractionDirection == .lateral }
      + incomingEdges[key, default: []].filter { $0.kind?.abstractionDirection == .lateral }
  }

  /// Outgoing + incoming edges of `key` filtered to the given relation kinds,
  /// direction-agnostic (`edge.key` is always the *other* endpoint). Used by
  /// the explanation contract's relation dimensions (历史时期/地域文化/…),
  /// where the edge's `explanation` text carries the semantics and direction
  /// is deliberately not interpreted (`产生于` is still orientation-pending).
  func edges(key: String, kinds: Set<RelationKind>) -> [DirectedRelationEdge] {
    var seen = Set<String>()
    var result: [DirectedRelationEdge] = []
    for edge in outgoingEdges[key, default: []] + incomingEdges[key, default: []] {
      guard let kind = edge.kind, kinds.contains(kind), seen.insert(edge.key).inserted
      else { continue }
      result.append(edge)
    }
    return result
  }

  /// BFS over upward edges, grouped by first-arrival level. A node reached
  /// again through a cycle keeps its earliest level, so results stay
  /// deterministic even while the pack still contains unaudited edges.
  func ancestors(key: String, maxLevels: Int = 5) -> [AbstractionLevel] {
    var levelByKey: [String: Int] = [key: 0]
    var edgeByKey: [String: DirectedRelationEdge] = [:]
    var queue: [String] = [key]
    var queueIndex = 0
    while queueIndex < queue.count {
      let current = queue[queueIndex]
      queueIndex += 1
      let currentLevel = levelByKey[current] ?? 0
      guard currentLevel < maxLevels else { continue }
      for edge in upward(key: current) {
        guard elementsByKey[edge.key] != nil, levelByKey[edge.key] == nil else { continue }
        levelByKey[edge.key] = currentLevel + 1
        edgeByKey[edge.key] = edge
        queue.append(edge.key)
      }
    }

    var elementsByLevel: [Int: [AbstractionAncestor]] = [:]
    for (ancestorKey, level) in levelByKey where level > 0 {
      guard let element = elementsByKey[ancestorKey] else { continue }
      let edge = edgeByKey[ancestorKey]
      elementsByLevel[level, default: []].append(
        AbstractionAncestor(
          key: ancestorKey,
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
          return ($0.name, $0.key) < ($1.name, $1.key)
        }
      )
    }
  }

  /// Nodes sharing at least one upward parent with `key` (同级相关).
  func siblings(key: String) -> [String] {
    var result = Set<String>()
    for parent in upward(key: key) {
      for child in downward(key: parent.key) where child.key != key {
        if elementsByKey[child.key] != nil {
          result.insert(child.key)
        }
      }
    }
    return result.sorted()
  }

  /// Transitive closure of `理解前先懂` edges pointing at `key` (an edge's
  /// source is the prerequisite, its target the dependent), minus the `known`
  /// element keys, in dependency order (nearest prerequisite first).
  func missingPrerequisites(
    key: String,
    known: Set<String>,
    maxCount: Int = 3
  ) -> [MissingPrerequisite] {
    var visited: Set<String> = [key]
    var queue: [String] = [key]
    var queueIndex = 0
    var missing: [MissingPrerequisite] = []
    while queueIndex < queue.count {
      let current = queue[queueIndex]
      queueIndex += 1
      for edge in incomingEdges[current, default: []]
      where edge.kind == .prerequisiteFor && visited.insert(edge.key).inserted {
        queue.append(edge.key)
        guard !known.contains(edge.key), let element = elementsByKey[edge.key]
        else { continue }
        missing.append(
          MissingPrerequisite(
            key: edge.key,
            name: element.name,
            excerpt: Self.richTextPlainText(element.introduction)
          )
        )
        if missing.count >= maxCount { return missing }
      }
    }
    return missing
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
    let a = pow(sin(deltaLatitude / 2), 2)
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
        let element = elementsByKey[record.culturalElementKey],
        let attraction = pack.attractions.first(where: { $0.key == record.attractionKey })
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
        culturalElementKey: element.key,
        culturalElementName: element.name,
        attractionKey: attraction.key,
        attractionName: attraction.name,
        latitude: record.latitude,
        longitude: record.longitude,
        distanceMeters: distance,
        sources: record.sources
      )
    }
    .sorted {
      ($0.distanceMeters, $0.name, $0.key) < ($1.distanceMeters, $1.name, $1.key)
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
    if let latitude, let longitude, !orderedElementKeys.isEmpty {
      nearby = try nearbyIntroductions(
        latitude: latitude,
        longitude: longitude,
        radiusMeters: Self.defaultRadiusMeters,
        limit: max(Self.maximumObjectLimit, pack.introductions.count)
      ).introductions
    }

    var nearbyContexts: [String: [NearbyAttractionIntroduction]] = [:]
    for introduction in nearby where elementsByKey[introduction.culturalElementKey] != nil {
      nearbyContexts[introduction.culturalElementKey, default: []].append(introduction)
    }

    var attractionRoots: [String: String] = [:]
    var attractionNames: [String: String] = [:]
    var attractionBindings: [String: Set<String>] = [:]
    var attractionCandidates: [AttractionCandidate] = []
    var seenAttractions = Set<String>()
    for introduction in nearby {
      if attractionRoots[introduction.attractionKey] == nil {
        attractionRoots[introduction.attractionKey] = introduction.culturalElementKey
        attractionNames[introduction.attractionKey] = introduction.attractionName
      }
      attractionBindings[introduction.attractionKey, default: []]
        .insert(introduction.culturalElementKey)
      guard seenAttractions.insert(introduction.attractionKey).inserted else { continue }
      guard attractionCandidates.count < Self.maximumAttractionCandidates else { continue }
      attractionCandidates.append(
        AttractionCandidate(
          key: introduction.attractionKey,
          name: introduction.attractionName,
          culturalElementKey: attractionRoots[introduction.attractionKey]
            ?? introduction.culturalElementKey,
          summary: Self.richTextPlainText(introduction.introduction, separator: "\n\n"),
          distanceMeters: introduction.distanceMeters,
          sources: introduction.sources
        )
      )
    }

    let selectedAttractionKeys = Set(attractionCandidates.map(\.key))
    let prioritizedKeys = prioritizedRecognitionKeys(
      nearby: nearby,
      attractionRoots: attractionRoots,
      selectedAttractionKeys: selectedAttractionKeys,
      allowCulturalCatalogFill: attractionCandidates.count
        < Self.minimumAttractionsBeforeCulturalFill,
      limit: limit
    )

    var elements: [RecognitionElement] = []
    elements.reserveCapacity(prioritizedKeys.count)
    for key in prioritizedKeys {
      guard let element = elementsByKey[key] else { continue }
      var graph = recognitionGraph(rootKey: key, maxDepth: 3, maxNodes: 32)
      graph = appendAttractionBindings(
        rootKey: key,
        attractionRoots: attractionRoots,
        attractionNames: attractionNames,
        bindings: attractionBindings,
        graphElements: graph.elements,
        graphRelations: graph.relations
      )
      let contexts = nearbyContexts[key] ?? []
      var elementSources = packSources(forElementKey: key)
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
          key: element.key,
          name: element.name,
          introduction: element.introduction,
          nearbyContexts: contexts,
          relatedElements: relatedElements(
            forKey: key,
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
      totalElements: orderedElementKeys.count,
      nearbyContextCount: nearby.count,
      locationMatched: !nearby.isEmpty
    )
  }

  /// Cultural-content candidates for the recognition prompt, nearest-first:
  /// 1. Elements bound to the selected nearby attractions (roots, then others)
  ///    — any `contentRole`, because introductions may cite cultural-history
  ///    nodes that explain a place
  /// 2. Only when nearby attractions < 3: other in-radius elements by distance,
  ///    then remaining **看点** catalog keys by name (not 文化历史)
  private func prioritizedRecognitionKeys(
    nearby: [NearbyAttractionIntroduction],
    attractionRoots: [String: String],
    selectedAttractionKeys: Set<String>,
    allowCulturalCatalogFill: Bool,
    limit: Int
  ) -> [String] {
    var prioritizedKeys: [String] = []
    var seen = Set<String>()

    func append(_ key: String) {
      guard elementsByKey[key] != nil, seen.insert(key).inserted else { return }
      prioritizedKeys.append(key)
    }

    let selectedNearby = nearby.filter { selectedAttractionKeys.contains($0.attractionKey) }

    for introduction in selectedNearby {
      if let key = attractionRoots[introduction.attractionKey] {
        append(key)
        if prioritizedKeys.count >= limit { return prioritizedKeys }
      }
    }
    for introduction in selectedNearby {
      append(introduction.culturalElementKey)
      if prioritizedKeys.count >= limit { return prioritizedKeys }
    }

    guard allowCulturalCatalogFill else { return prioritizedKeys }

    for introduction in nearby {
      append(introduction.culturalElementKey)
      if prioritizedKeys.count >= limit { return prioritizedKeys }
    }
    for key in orderedElementKeys {
      guard elementsByKey[key]?.resolvedContentRole == .sight else { continue }
      append(key)
      if prioritizedKeys.count >= limit { return prioritizedKeys }
    }
    return prioritizedKeys
  }

  // MARK: - Graph traversal (postgres.go recognitionGraph / appendAttractionBindings)

  private func recognitionGraph(
    rootKey: String,
    maxDepth: Int,
    maxNodes: Int
  ) -> (elements: [KnowledgeGraphElement], relations: [KnowledgeGraphRelation]) {
    var depths = [rootKey: 0]
    var queue = [rootKey]
    while !queue.isEmpty && depths.count < maxNodes + 1 {
      let current = queue.removeFirst()
      let depth = depths[current] ?? 0
      guard depth < maxDepth else { continue }
      for relation in relations {
        let next: String
        if relation.elementKey == current {
          next = relation.relatedElementKey
        } else if relation.relatedElementKey == current {
          next = relation.elementKey
        } else {
          continue
        }
        guard elementsByKey[next] != nil else { continue }
        if depths[next] == nil && depths.count < maxNodes + 1 {
          depths[next] = depth + 1
          queue.append(next)
        }
      }
    }

    let sortedKeys = depths.keys.sorted {
      (depths[$0] ?? 0, $0) < (depths[$1] ?? 0, $1)
    }
    let graphElements = sortedKeys
      .filter { $0 != rootKey }
      .compactMap { elementsByKey[$0] }
      .map {
        KnowledgeGraphElement(
          key: $0.key,
          name: $0.name,
          introduction: $0.introduction,
          conceptKind: $0.conceptKind
        )
      }
    let graphRelations = relations.compactMap { relation -> KnowledgeGraphRelation? in
      guard depths[relation.elementKey] != nil, depths[relation.relatedElementKey] != nil
      else { return nil }
      return KnowledgeGraphRelation(
        elementKey: relation.elementKey,
        relatedElementKey: relation.relatedElementKey,
        kind: relation.kind ?? "解释",
        explanation: relation.explanation
          ?? String(localized: "文化内容库记录了两个概念之间的显式关联。")
      )
    }
    return (graphElements, graphRelations)
  }

  private func appendAttractionBindings(
    rootKey: String,
    attractionRoots: [String: String],
    attractionNames: [String: String],
    bindings: [String: Set<String>],
    graphElements: [KnowledgeGraphElement],
    graphRelations: [KnowledgeGraphRelation]
  ) -> (elements: [KnowledgeGraphElement], relations: [KnowledgeGraphRelation]) {
    var graphElements = graphElements
    var graphRelations = graphRelations
    var seenElements: Set<String> = [rootKey]
    seenElements.formUnion(graphElements.map(\.key))
    var seenEdges = Set<String>()
    for relation in graphRelations {
      seenEdges.insert(relation.elementKey + "\0" + relation.relatedElementKey)
      seenEdges.insert(relation.relatedElementKey + "\0" + relation.elementKey)
    }

    for attractionKey in attractionRoots.keys.sorted()
    where attractionRoots[attractionKey] == rootKey {
      for boundKey in (bindings[attractionKey] ?? []).sorted() {
        guard boundKey != rootKey else { continue }
        if !seenElements.contains(boundKey) {
          guard let element = elementsByKey[boundKey] else { continue }
          graphElements.append(
            KnowledgeGraphElement(
              key: element.key,
              name: element.name,
              introduction: element.introduction,
              conceptKind: element.conceptKind
            )
          )
          seenElements.insert(boundKey)
        }
        let edgeKey = rootKey + "\0" + boundKey
        guard !seenEdges.contains(edgeKey) else { continue }
        graphRelations.append(
          KnowledgeGraphRelation(
            elementKey: rootKey,
            relatedElementKey: boundKey,
            kind: "解释",
            explanation: String(
              localized: "该文化元素通过“\(attractionNames[attractionKey] ?? "")”的现场介绍直接关联到当前景点。"
            )
          )
        )
        seenEdges.insert(edgeKey)
        seenEdges.insert(boundKey + "\0" + rootKey)
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
