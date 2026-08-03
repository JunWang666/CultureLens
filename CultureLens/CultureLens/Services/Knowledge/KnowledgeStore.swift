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
        targetID: DeterministicID.culturalElement(relation.relatedElementKey)
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
        distanceMeters: distance
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
      elements.append(
        RecognitionElement(
          key: element.key,
          name: element.name,
          introduction: element.introduction,
          nearbyContexts: nearbyContexts[key] ?? [],
          relatedElements: relatedElements(
            forKey: key,
            limit: Self.maximumObjectLimit
          ),
          graphElements: graph.elements,
          graphRelations: graph.relations
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
          distanceMeters: introduction.distanceMeters
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
