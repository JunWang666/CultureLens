import Foundation

/// Codable models for the bundled knowledge pack under
/// `Resources/KnowledgePack*/` (sidecar layout: slim `knowledge-pack.json`
/// plus `elements-sight` / `elements-history` / `introductions` / `themes` /
/// `locales-<lang>`). Assembled at load time by `KnowledgeStore.loadPack`.
///
/// Primary identity is `id` (UUIDv5 from the legacy slug, matching
/// `DeterministicID`). Optional `key` retains the human-readable slug for
/// migration, debugging, and display.
nonisolated struct KnowledgePack: Codable, Sendable {
  let version: String
  /// BCP-47 tag for the primary text fields (name / introduction). Defaults to zh-Hans.
  let sourceLanguage: String?
  let elements: [Element]
  let attractions: [Attraction]
  let relations: [Relation]
  let introductions: [IntroductionRecord]
  /// Themed exploration tracks. Older packs may omit this field.
  let themes: [Theme]
  /// Optional translated overlays keyed by BCP-47 tag (e.g. "en"). Overlay
  /// maps inside are keyed by entity UUID string.
  let locales: [String: LocaleOverlay]?

  /// External trusted reference attached to an element or on-site introduction.
  nonisolated struct Source: Codable, Sendable, Hashable {
    let title: String
    let publisher: String
    let url: String?

    init(title: String, publisher: String, url: String?) {
      self.title = title
      self.publisher = publisher
      self.url = url
    }

    /// Builds a displayable source from a raw URL (Wikipedia, Amap, UNESCO, …).
    static func inferred(from urlString: String) -> Source {
      let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
      let host = hostName(from: trimmed)
      let publisher = publisherName(forHost: host)
      return Source(title: publisher, publisher: publisher, url: trimmed)
    }

    /// Prefer Foundation URL parsing; fall back to a lightweight host scrape so
    /// unencoded Chinese paths in the pack still yield a publisher name.
    private static func hostName(from urlString: String) -> String {
      if let host = URL(string: urlString)?.host?.lowercased(), !host.isEmpty {
        return host
      }
      guard let schemeRange = urlString.range(of: "://") else { return "" }
      let afterScheme = urlString[schemeRange.upperBound...]
      let hostPart = afterScheme.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        .first.map(String.init) ?? ""
      return hostPart.split(separator: ":", maxSplits: 1).first.map(String.init)?.lowercased()
        ?? ""
    }

    private static func publisherName(forHost host: String) -> String {
      if host.contains("wikipedia.org") { return "维基百科" }
      if host.contains("wikidata.org") { return "Wikidata" }
      if host.contains("wikimedia.org") { return "Wikimedia Commons" }
      if host.contains("amap.com") { return "高德地图" }
      if host.contains("mapcarta.com") { return "Mapcarta" }
      if host.contains("unesco.org") { return "UNESCO" }
      if host.contains("ehangzhou.gov.cn") { return "杭州政府网" }
      if host.contains("moj.gov.cn") { return "司法部" }
      if host.isEmpty { return String(localized: "外部资料") }
      return host.replacingOccurrences(of: "www.", with: "")
    }

    /// View-facing publisher name in the active app language. The stored
    /// `publisher` stays Chinese (tests and provenance depend on it).
    var displayPublisher: String {
      KnowledgePublisherDisplay.name(for: publisher)
    }

    func asKnowledgeSource() -> KnowledgeSource {
      let identity = (url ?? title).trimmingCharacters(in: .whitespacesAndNewlines)
      // Percent-encode non-ASCII paths so Link/openURL can open Wikipedia CN URLs.
      let resolvedURL = url.flatMap { raw -> URL? in
        if let url = URL(string: raw) { return url }
        return raw.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
          .flatMap(URL.init(string:))
      }
      return KnowledgeSource(
        id: DeterministicID.v5(name: "culturelens:knowledge-source:" + identity.lowercased()),
        title: title,
        publisher: publisher,
        url: resolvedURL
      )
    }
  }

  nonisolated struct Element: Codable, Sendable, Identifiable {
    let id: UUID
    /// Optional human-readable slug (legacy key). Always present in shipped packs.
    let key: String?
    let name: String
    let introduction: RichTextDocument
    let sources: [Source]
    /// Optional `ConceptKind.rawValue`; omitted in older packs.
    let conceptKind: String?
    /// `ContentRole.rawValue`（看点 / 文化历史）. Omitted in older monoliths;
    /// loaders stamp from `attractions[]` membership when missing.
    let contentRole: String?

    init(
      id: UUID,
      key: String? = nil,
      name: String,
      introduction: RichTextDocument,
      sources: [Source] = [],
      conceptKind: String? = nil,
      contentRole: String? = nil
    ) {
      self.id = id
      self.key = key
      self.name = name
      self.introduction = introduction
      self.sources = sources
      self.conceptKind = conceptKind
      self.contentRole = contentRole
    }

    /// Convenience for tests / fixtures that still mint identity from a slug.
    init(
      key: String,
      name: String,
      introduction: RichTextDocument,
      sources: [Source] = [],
      conceptKind: String? = nil,
      contentRole: String? = nil
    ) {
      self.init(
        id: DeterministicID.culturalElement(key),
        key: key,
        name: name,
        introduction: introduction,
        sources: sources,
        conceptKind: conceptKind,
        contentRole: contentRole
      )
    }

    enum CodingKeys: String, CodingKey {
      case id, key, name, introduction, sources, conceptKind, contentRole
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let decodedKey = try container.decodeIfPresent(String.self, forKey: .key)
      if let decodedID = try container.decodeIfPresent(UUID.self, forKey: .id) {
        id = decodedID
      } else if let decodedKey {
        // Legacy monolith / test fixtures that only carry a slug.
        id = DeterministicID.culturalElement(decodedKey)
      } else {
        throw DecodingError.dataCorruptedError(
          forKey: .id,
          in: container,
          debugDescription: "Element requires id or key"
        )
      }
      key = decodedKey
      name = try container.decode(String.self, forKey: .name)
      introduction = try container.decode(RichTextDocument.self, forKey: .introduction)
      sources = try container.decodeIfPresent([Source].self, forKey: .sources) ?? []
      conceptKind = try container.decodeIfPresent(String.self, forKey: .conceptKind)
      contentRole = try container.decodeIfPresent(String.self, forKey: .contentRole)
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(id, forKey: .id)
      try container.encodeIfPresent(key, forKey: .key)
      try container.encode(name, forKey: .name)
      try container.encode(introduction, forKey: .introduction)
      if !sources.isEmpty {
        try container.encode(sources, forKey: .sources)
      }
      try container.encodeIfPresent(conceptKind, forKey: .conceptKind)
      try container.encodeIfPresent(contentRole, forKey: .contentRole)
    }

    /// Resolved role: explicit `contentRole`, else infer from attraction slugs.
    func resolvedContentRole(attractionKeys: Set<String> = []) -> ContentRole {
      if let contentRole, let role = ContentRole(rawValue: contentRole) {
        return role
      }
      if let key, attractionKeys.contains(key) { return .sight }
      return .history
    }

    func withContentRole(_ role: ContentRole) -> Element {
      Element(
        id: id,
        key: key,
        name: name,
        introduction: introduction,
        sources: sources,
        conceptKind: conceptKind,
        contentRole: role.rawValue
      )
    }

    /// Stable sort key: name then slug then UUID.
    var sortKey: String { key ?? id.uuidString }
  }

  nonisolated struct Attraction: Codable, Sendable, Identifiable {
    let id: UUID
    let key: String?
    let name: String

    init(id: UUID, key: String? = nil, name: String) {
      self.id = id
      self.key = key
      self.name = name
    }

    init(key: String, name: String) {
      self.init(id: DeterministicID.attraction(key), key: key, name: name)
    }

    enum CodingKeys: String, CodingKey {
      case id, key, name
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let decodedKey = try container.decodeIfPresent(String.self, forKey: .key)
      if let decodedID = try container.decodeIfPresent(UUID.self, forKey: .id) {
        id = decodedID
      } else if let decodedKey {
        id = DeterministicID.attraction(decodedKey)
      } else {
        throw DecodingError.dataCorruptedError(
          forKey: .id,
          in: container,
          debugDescription: "Attraction requires id or key"
        )
      }
      key = decodedKey
      name = try container.decode(String.self, forKey: .name)
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(id, forKey: .id)
      try container.encodeIfPresent(key, forKey: .key)
      try container.encode(name, forKey: .name)
    }

    var sortKey: String { key ?? id.uuidString }
  }

  nonisolated struct Relation: Codable, Sendable {
    let elementId: UUID
    let relatedElementId: UUID
    /// Optional `RelationKind.rawValue`; omitted in older packs.
    let kind: String?
    /// Human-readable edge gloss; omitted in older packs.
    let explanation: String?

    init(
      elementId: UUID,
      relatedElementId: UUID,
      kind: String? = nil,
      explanation: String? = nil
    ) {
      self.elementId = elementId
      self.relatedElementId = relatedElementId
      self.kind = kind
      self.explanation = explanation
    }

    /// Test / legacy convenience from slugs.
    init(
      elementKey: String,
      relatedElementKey: String,
      kind: String? = nil,
      explanation: String? = nil
    ) {
      self.init(
        elementId: DeterministicID.culturalElement(elementKey),
        relatedElementId: DeterministicID.culturalElement(relatedElementKey),
        kind: kind,
        explanation: explanation
      )
    }

    enum CodingKeys: String, CodingKey {
      case elementId, relatedElementId, kind, explanation
      case elementKey, relatedElementKey
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      if let elementId = try container.decodeIfPresent(UUID.self, forKey: .elementId),
        let relatedElementId = try container.decodeIfPresent(UUID.self, forKey: .relatedElementId)
      {
        self.elementId = elementId
        self.relatedElementId = relatedElementId
      } else if let elementKey = try container.decodeIfPresent(String.self, forKey: .elementKey),
        let relatedElementKey = try container.decodeIfPresent(String.self, forKey: .relatedElementKey)
      {
        self.elementId = DeterministicID.culturalElement(elementKey)
        self.relatedElementId = DeterministicID.culturalElement(relatedElementKey)
      } else {
        throw DecodingError.dataCorruptedError(
          forKey: .elementId,
          in: container,
          debugDescription: "Relation requires elementId/relatedElementId or legacy keys"
        )
      }
      kind = try container.decodeIfPresent(String.self, forKey: .kind)
      explanation = try container.decodeIfPresent(String.self, forKey: .explanation)
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(elementId, forKey: .elementId)
      try container.encode(relatedElementId, forKey: .relatedElementId)
      try container.encodeIfPresent(kind, forKey: .kind)
      try container.encodeIfPresent(explanation, forKey: .explanation)
    }
  }

  nonisolated struct IntroductionRecord: Codable, Sendable, Identifiable {
    let id: UUID
    let key: String?
    let name: String
    let introduction: RichTextDocument
    let culturalElementId: UUID
    let attractionId: UUID
    let latitude: Double
    let longitude: Double
    /// Raw coordinate provenance URL from the pack (Wikipedia, Amap, …).
    let coordinateSourceUrl: String?
    /// Trusted external sources; derived from `coordinateSourceUrl` when the
    /// pack omits an explicit `sources` array.
    let sources: [Source]

    init(
      id: UUID,
      key: String? = nil,
      name: String,
      introduction: RichTextDocument,
      culturalElementId: UUID,
      attractionId: UUID,
      latitude: Double,
      longitude: Double,
      coordinateSourceUrl: String? = nil,
      sources: [Source] = []
    ) {
      self.id = id
      self.key = key
      self.name = name
      self.introduction = introduction
      self.culturalElementId = culturalElementId
      self.attractionId = attractionId
      self.latitude = latitude
      self.longitude = longitude
      self.coordinateSourceUrl = coordinateSourceUrl
      if sources.isEmpty, let coordinateSourceUrl, !coordinateSourceUrl.isEmpty {
        self.sources = [Source.inferred(from: coordinateSourceUrl)]
      } else {
        self.sources = sources
      }
    }

    /// Test / legacy convenience from slugs.
    init(
      key: String,
      name: String,
      introduction: RichTextDocument,
      culturalElementKey: String,
      attractionKey: String,
      latitude: Double,
      longitude: Double,
      coordinateSourceUrl: String? = nil,
      sources: [Source] = []
    ) {
      self.init(
        id: DeterministicID.introduction(key),
        key: key,
        name: name,
        introduction: introduction,
        culturalElementId: DeterministicID.culturalElement(culturalElementKey),
        attractionId: DeterministicID.attraction(attractionKey),
        latitude: latitude,
        longitude: longitude,
        coordinateSourceUrl: coordinateSourceUrl,
        sources: sources
      )
    }

    enum CodingKeys: String, CodingKey {
      case id, key, name, introduction
      case culturalElementId, attractionId
      case culturalElementKey, attractionKey
      case latitude, longitude, coordinateSourceUrl, sources
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let decodedKey = try container.decodeIfPresent(String.self, forKey: .key)
      if let decodedID = try container.decodeIfPresent(UUID.self, forKey: .id) {
        id = decodedID
      } else if let decodedKey {
        id = DeterministicID.introduction(decodedKey)
      } else {
        throw DecodingError.dataCorruptedError(
          forKey: .id,
          in: container,
          debugDescription: "Introduction requires id or key"
        )
      }
      key = decodedKey
      name = try container.decode(String.self, forKey: .name)
      introduction = try container.decode(RichTextDocument.self, forKey: .introduction)
      if let culturalElementId = try container.decodeIfPresent(UUID.self, forKey: .culturalElementId) {
        self.culturalElementId = culturalElementId
      } else if let culturalElementKey = try container.decodeIfPresent(
        String.self,
        forKey: .culturalElementKey
      ) {
        self.culturalElementId = DeterministicID.culturalElement(culturalElementKey)
      } else {
        throw DecodingError.dataCorruptedError(
          forKey: .culturalElementId,
          in: container,
          debugDescription: "Introduction requires culturalElementId or culturalElementKey"
        )
      }
      if let attractionId = try container.decodeIfPresent(UUID.self, forKey: .attractionId) {
        self.attractionId = attractionId
      } else if let attractionKey = try container.decodeIfPresent(String.self, forKey: .attractionKey)
      {
        self.attractionId = DeterministicID.attraction(attractionKey)
      } else {
        throw DecodingError.dataCorruptedError(
          forKey: .attractionId,
          in: container,
          debugDescription: "Introduction requires attractionId or attractionKey"
        )
      }
      latitude = try container.decode(Double.self, forKey: .latitude)
      longitude = try container.decode(Double.self, forKey: .longitude)
      coordinateSourceUrl = try container.decodeIfPresent(String.self, forKey: .coordinateSourceUrl)
      let decodedSources = try container.decodeIfPresent([Source].self, forKey: .sources) ?? []
      if decodedSources.isEmpty,
        let coordinateSourceUrl,
        !coordinateSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        sources = [Source.inferred(from: coordinateSourceUrl)]
      } else {
        sources = decodedSources
      }
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(id, forKey: .id)
      try container.encodeIfPresent(key, forKey: .key)
      try container.encode(name, forKey: .name)
      try container.encode(introduction, forKey: .introduction)
      try container.encode(culturalElementId, forKey: .culturalElementId)
      try container.encode(attractionId, forKey: .attractionId)
      try container.encode(latitude, forKey: .latitude)
      try container.encode(longitude, forKey: .longitude)
      try container.encodeIfPresent(coordinateSourceUrl, forKey: .coordinateSourceUrl)
      if !sources.isEmpty {
        try container.encode(sources, forKey: .sources)
      }
    }

    var sortKey: String { key ?? id.uuidString }
  }

  /// A curated exploration path that binds a set of cultural element IDs
  /// and a completion threshold (`minContacted`).
  nonisolated struct Theme: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    let key: String?
    let name: String
    let summary: String
    let elementIds: [UUID]
    /// Number of theme elements the user must have joined the graph for.
    let minContacted: Int

    init(
      id: UUID,
      key: String? = nil,
      name: String,
      summary: String,
      elementIds: [UUID],
      minContacted: Int
    ) {
      self.id = id
      self.key = key
      self.name = name
      self.summary = summary
      self.elementIds = elementIds
      self.minContacted = minContacted
    }

    init(
      key: String,
      name: String,
      summary: String,
      elementKeys: [String],
      minContacted: Int
    ) {
      self.init(
        id: DeterministicID.theme(key),
        key: key,
        name: name,
        summary: summary,
        elementIds: elementKeys.map(DeterministicID.culturalElement),
        minContacted: minContacted
      )
    }

    enum CodingKeys: String, CodingKey {
      case id, key, name, summary, elementIds, minContacted, elementKeys
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let decodedKey = try container.decodeIfPresent(String.self, forKey: .key)
      if let decodedID = try container.decodeIfPresent(UUID.self, forKey: .id) {
        id = decodedID
      } else if let decodedKey {
        id = DeterministicID.theme(decodedKey)
      } else {
        throw DecodingError.dataCorruptedError(
          forKey: .id,
          in: container,
          debugDescription: "Theme requires id or key"
        )
      }
      key = decodedKey
      name = try container.decode(String.self, forKey: .name)
      summary = try container.decode(String.self, forKey: .summary)
      if let ids = try container.decodeIfPresent([UUID].self, forKey: .elementIds) {
        elementIds = ids
      } else if let keys = try container.decodeIfPresent([String].self, forKey: .elementKeys) {
        elementIds = keys.map(DeterministicID.culturalElement)
      } else {
        elementIds = []
      }
      minContacted = try container.decode(Int.self, forKey: .minContacted)
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(id, forKey: .id)
      try container.encodeIfPresent(key, forKey: .key)
      try container.encode(name, forKey: .name)
      try container.encode(summary, forKey: .summary)
      try container.encode(elementIds, forKey: .elementIds)
      try container.encode(minContacted, forKey: .minContacted)
    }

    var sortKey: String { key ?? id.uuidString }
  }

  enum CodingKeys: String, CodingKey {
    case version
    case sourceLanguage = "source_language"
    case elements
    case attractions
    case relations
    case introductions
    case themes
    case locales
  }

  init(
    version: String,
    sourceLanguage: String? = "zh-Hans",
    elements: [Element],
    attractions: [Attraction],
    relations: [Relation],
    introductions: [IntroductionRecord],
    themes: [Theme] = [],
    locales: [String: LocaleOverlay]? = nil
  ) {
    self.version = version
    self.sourceLanguage = sourceLanguage
    self.elements = elements
    self.attractions = attractions
    self.relations = relations
    self.introductions = introductions
    self.themes = themes
    self.locales = locales
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decode(String.self, forKey: .version)
    sourceLanguage = try container.decodeIfPresent(String.self, forKey: .sourceLanguage)
    // Sidecar layout keeps only version / source_language / relations here;
    // monolith packs still embed the other arrays for tests and legacy.
    elements = try container.decodeIfPresent([Element].self, forKey: .elements) ?? []
    attractions = try container.decodeIfPresent([Attraction].self, forKey: .attractions) ?? []
    relations = try container.decodeIfPresent([Relation].self, forKey: .relations) ?? []
    introductions =
      try container.decodeIfPresent([IntroductionRecord].self, forKey: .introductions) ?? []
    themes = try container.decodeIfPresent([Theme].self, forKey: .themes) ?? []
    locales = try container.decodeIfPresent([String: LocaleOverlay].self, forKey: .locales)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(version, forKey: .version)
    try container.encodeIfPresent(sourceLanguage, forKey: .sourceLanguage)
    try container.encode(elements, forKey: .elements)
    try container.encode(attractions, forKey: .attractions)
    try container.encode(relations, forKey: .relations)
    try container.encode(introductions, forKey: .introductions)
    try container.encode(themes, forKey: .themes)
    try container.encodeIfPresent(locales, forKey: .locales)
  }

  /// Stamps `contentRole` from attractions membership when the field is absent.
  func withStampedContentRoles() -> KnowledgePack {
    let attractionKeys = Set(attractions.compactMap(\.key))
    let stamped = elements.map { element in
      let role = element.resolvedContentRole(attractionKeys: attractionKeys)
      return element.contentRole == role.rawValue ? element : element.withContentRole(role)
    }
    return KnowledgePack(
      version: version,
      sourceLanguage: sourceLanguage,
      elements: stamped,
      attractions: attractions,
      relations: relations,
      introductions: introductions,
      themes: themes,
      locales: locales
    )
  }
}

// MARK: - Sidecar file shapes

/// Sight elements + scannable attraction registry (`elements-sight.json`).
nonisolated struct KnowledgePackSightSidecar: Codable, Sendable {
  let elements: [KnowledgePack.Element]
  let attractions: [KnowledgePack.Attraction]

  enum CodingKeys: String, CodingKey {
    case elements, attractions
  }

  init(elements: [KnowledgePack.Element], attractions: [KnowledgePack.Attraction]) {
    self.elements = elements
    self.attractions = attractions
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    elements = try container.decodeIfPresent([KnowledgePack.Element].self, forKey: .elements) ?? []
    attractions =
      try container.decodeIfPresent([KnowledgePack.Attraction].self, forKey: .attractions) ?? []
  }
}

/// Abstract cultural-history elements (`elements-history.json`).
nonisolated struct KnowledgePackHistorySidecar: Codable, Sendable {
  let elements: [KnowledgePack.Element]

  init(elements: [KnowledgePack.Element]) {
    self.elements = elements
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    elements = try container.decodeIfPresent([KnowledgePack.Element].self, forKey: .elements) ?? []
  }

  enum CodingKeys: String, CodingKey {
    case elements
  }
}

nonisolated struct KnowledgePackIntroductionsSidecar: Codable, Sendable {
  let introductions: [KnowledgePack.IntroductionRecord]

  init(introductions: [KnowledgePack.IntroductionRecord]) {
    self.introductions = introductions
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    introductions =
      try container.decodeIfPresent([KnowledgePack.IntroductionRecord].self, forKey: .introductions)
      ?? []
  }

  enum CodingKeys: String, CodingKey {
    case introductions
  }
}

nonisolated struct KnowledgePackThemesSidecar: Codable, Sendable {
  let themes: [KnowledgePack.Theme]

  init(themes: [KnowledgePack.Theme]) {
    self.themes = themes
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    themes = try container.decodeIfPresent([KnowledgePack.Theme].self, forKey: .themes) ?? []
  }

  enum CodingKeys: String, CodingKey {
    case themes
  }
}

/// Maps stored (Chinese) publisher names to the active app language for
/// display. Stored values are never mutated — provenance tests depend on them.
enum KnowledgePublisherDisplay {
  nonisolated static func name(for publisher: String) -> String {
    switch AppLanguageStore.currentLanguage() {
    case .zhHans:
      return publisher
    case .english:
      switch publisher {
      case "维基百科": return "Wikipedia"
      case "高德地图": return "Amap"
      case "杭州政府网": return "Hangzhou Gov"
      case "司法部": return "Ministry of Justice"
      case "UNESCO": return "UNESCO"
      case "外部资料": return String(localized: "外部资料")
      default: return publisher
      }
    }
  }
}
