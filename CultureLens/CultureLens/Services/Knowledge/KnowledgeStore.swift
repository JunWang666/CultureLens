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

enum KnowledgeStoreError: LocalizedError {
  case packMissing
  case packInvalid(String)
  case invalidQuery

  var errorDescription: String? {
    switch self {
    case .packMissing:
      "应用内缺少知识库数据包。"
    case .packInvalid(let detail):
      "知识库数据包无法读取：\(detail)"
    case .invalidQuery:
      "附近内容查询参数无效。"
    }
  }
}

/// In-memory port of the Go backend's knowledge repository
/// (`internal/knowledge/postgres.go`), backed by the bundled knowledge pack
/// instead of PostgreSQL.
nonisolated struct KnowledgeStore: Sendable {
  static let defaultCandidateLimit = 12
  static let maximumObjectLimit = 20
  static let maximumGraphExpansionNodes = 48
  static let defaultRadiusMeters = 50_000.0

  let pack: KnowledgePack

  /// Element keys in `ListCulturalElements` order (`ORDER BY name, key`).
  private let orderedElementKeys: [String]
  private let elementsByKey: [String: KnowledgePack.Element]
  private let elementKeysByID: [UUID: String]
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

  init(pack: KnowledgePack) {
    self.pack = pack
    elementsByKey = Dictionary(
      pack.elements.map { ($0.key, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    elementKeysByID = Dictionary(
      pack.elements.map { (DeterministicID.culturalElement($0.key), $0.key) },
      uniquingKeysWith: { first, _ in first }
    )
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

  /// Loads `knowledge-pack.json` from the app bundle.
  static func load(bundle: Bundle = .main) throws -> KnowledgeStore {
    guard
      let url = bundledResourceURL(
        "knowledge-pack",
        "json",
        subdirectory: "KnowledgePack",
        bundle: bundle
      )
    else {
      throw KnowledgeStoreError.packMissing
    }
    do {
      let data = try Data(contentsOf: url)
      return KnowledgeStore(pack: try JSONDecoder().decode(KnowledgePack.self, from: data))
    } catch let error as KnowledgeStoreError {
      throw error
    } catch {
      throw KnowledgeStoreError.packInvalid(error.localizedDescription)
    }
  }

  /// Shared store cached on first access; `nil` when the bundle lacks a pack.
  static let shared: KnowledgeStore? = try? KnowledgeStore.load()

  // MARK: - Basic lookups

  var elements: [KnowledgePack.Element] {
    orderedElementKeys.compactMap { elementsByKey[$0] }
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

  // MARK: - User knowledge graph

  /// Builds the graph shown in the Graph tab. Every joined node remains
  /// visible, while knowledge-pack expansion is limited to three shortest-hop
  /// rings and a fixed node budget.
  func userKnowledgeGraph(
    centerID requestedCenterID: UUID?,
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

    let defaultCenterID = orderedElementKeys
      .first { joinedElementKeys.contains($0) }
      .map(DeterministicID.culturalElement)
      ?? joinedSeeds.sorted {
        if $0.name != $1.name { return $0.name.localizedCompare($1.name) == .orderedAscending }
        return $0.id.uuidString < $1.id.uuidString
      }.first?.id
    let requestedCenterIsAvailable = requestedCenterID.map {
      elementKeysByID[$0] != nil || joinedIDs.contains($0)
    } ?? false
    let centerID = requestedCenterIsAvailable ? requestedCenterID : defaultCenterID
    let centerKey = centerID.flatMap { elementKeysByID[$0] }

    var hops: [String: Int] = [:]
    var queue: [String] = []
    var queueIndex = 0
    var isTruncated = false
    if let centerKey {
      hops[centerKey] = 0
      queue.append(centerKey)
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
          hop: seed.id == centerID ? 0 : depthLimit + 1,
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
      centerID: centerID,
      nodes: nodes,
      edges: edges,
      maximumDepth: depthLimit,
      isExpansionTruncated: isTruncated
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
        limit: Self.maximumObjectLimit
      ).introductions
    }

    var nearbyContexts: [String: [NearbyAttractionIntroduction]] = [:]
    for introduction in nearby where elementsByKey[introduction.culturalElementKey] != nil {
      nearbyContexts[introduction.culturalElementKey, default: []].append(introduction)
    }

    var attractionRoots: [String: String] = [:]
    var attractionNames: [String: String] = [:]
    var attractionBindings: [String: Set<String>] = [:]
    for introduction in nearby {
      if attractionRoots[introduction.attractionKey] == nil {
        attractionRoots[introduction.attractionKey] = introduction.culturalElementKey
        attractionNames[introduction.attractionKey] = introduction.attractionName
      }
      attractionBindings[introduction.attractionKey, default: []]
        .insert(introduction.culturalElementKey)
    }

    // Candidate priority: attraction root elements → nearby bound elements →
    // remaining elements in (name, key) order.
    var prioritizedKeys: [String] = []
    var seen = Set<String>()
    for introduction in nearby {
      guard
        let key = attractionRoots[introduction.attractionKey],
        elementsByKey[key] != nil,
        seen.insert(key).inserted
      else { continue }
      prioritizedKeys.append(key)
    }
    for introduction in nearby {
      let key = introduction.culturalElementKey
      guard elementsByKey[key] != nil, seen.insert(key).inserted else { continue }
      prioritizedKeys.append(key)
    }
    for key in orderedElementKeys where seen.insert(key).inserted {
      prioritizedKeys.append(key)
    }

    let selectedKeys = prioritizedKeys.prefix(limit)
    var elements: [RecognitionElement] = []
    elements.reserveCapacity(selectedKeys.count)
    for key in selectedKeys {
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

    var attractionCandidates: [AttractionCandidate] = []
    var seenAttractions = Set<String>()
    for introduction in nearby where seenAttractions.insert(introduction.attractionKey).inserted {
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

    return RecognitionKnowledgeSet(
      version: pack.version,
      elements: elements,
      attractionCandidates: attractionCandidates,
      totalElements: orderedElementKeys.count,
      nearbyContextCount: nearby.count,
      locationMatched: !nearby.isEmpty
    )
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
          ?? "文化内容库记录了两个概念之间的显式关联。"
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
            explanation:
              "该文化元素通过“\(attractionNames[attractionKey] ?? "")”的现场介绍直接关联到当前景点。"
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
