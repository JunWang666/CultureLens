import Foundation

/// Codable models for the bundled knowledge pack
/// (`Resources/KnowledgePack/knowledge-pack.json`), mirroring the Go backend's
/// `content/hangzhou-west-lake.v1.json` export format.
nonisolated struct KnowledgePack: Decodable, Sendable {
  let version: String
  /// BCP-47 tag for the primary text fields (name / introduction). Defaults to zh-Hans.
  let sourceLanguage: String?
  let elements: [Element]
  let attractions: [Attraction]
  let relations: [Relation]
  let introductions: [IntroductionRecord]
  /// Themed exploration tracks. Older packs may omit this field.
  let themes: [Theme]
  /// Optional translated overlays keyed by BCP-47 tag (e.g. "en"). May be empty
  /// until multilingual packs ship; runtime falls back to `dynamic/chat` translation.
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

    func asKnowledgeSource() -> KnowledgeSource {      let identity = (url ?? title).trimmingCharacters(in: .whitespacesAndNewlines)
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

  nonisolated struct Element: Decodable, Sendable {
    let key: String
    let name: String
    let introduction: RichTextDocument
    let sources: [Source]
    /// Optional `ConceptKind.rawValue`; omitted in older packs.
    let conceptKind: String?
    /// `ContentRole.rawValue`. Older packs / fixtures without the field decode as
    /// `.culturalHistory`; production packs set it explicitly (and split files
    /// by role under `elements-sight.json` / `elements-history.json`).
    let contentRole: String

    var resolvedContentRole: ContentRole {
      ContentRole(rawValue: contentRole) ?? .culturalHistory
    }

    init(
      key: String,
      name: String,
      introduction: RichTextDocument,
      sources: [Source] = [],
      conceptKind: String? = nil,
      contentRole: ContentRole = .culturalHistory
    ) {
      self.key = key
      self.name = name
      self.introduction = introduction
      self.sources = sources
      self.conceptKind = conceptKind
      self.contentRole = contentRole.rawValue
    }

    enum CodingKeys: String, CodingKey {
      case key, name, introduction, sources, conceptKind, contentRole
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      key = try container.decode(String.self, forKey: .key)
      name = try container.decode(String.self, forKey: .name)
      introduction = try container.decode(RichTextDocument.self, forKey: .introduction)
      sources = try container.decodeIfPresent([Source].self, forKey: .sources) ?? []
      conceptKind = try container.decodeIfPresent(String.self, forKey: .conceptKind)
      if let raw = try container.decodeIfPresent(String.self, forKey: .contentRole),
        ContentRole(rawValue: raw) != nil
      {
        contentRole = raw
      } else {
        contentRole = ContentRole.culturalHistory.rawValue
      }
    }
  }

  nonisolated struct Attraction: Decodable, Sendable {
    let key: String
    let name: String

    init(key: String, name: String) {
      self.key = key
      self.name = name
    }
  }

  nonisolated struct Relation: Decodable, Sendable {
    let elementKey: String
    let relatedElementKey: String
    /// Optional `RelationKind.rawValue`; omitted in older packs.
    let kind: String?
    /// Human-readable edge gloss; omitted in older packs.
    let explanation: String?

    init(
      elementKey: String,
      relatedElementKey: String,
      kind: String? = nil,
      explanation: String? = nil
    ) {
      self.elementKey = elementKey
      self.relatedElementKey = relatedElementKey
      self.kind = kind
      self.explanation = explanation
    }
  }

  nonisolated struct IntroductionRecord: Decodable, Sendable {
    let key: String
    let name: String
    let introduction: RichTextDocument
    let culturalElementKey: String
    let attractionKey: String
    let latitude: Double
    let longitude: Double
    /// Raw coordinate provenance URL from the pack (Wikipedia, Amap, …).
    let coordinateSourceUrl: String?
    /// Trusted external sources; derived from `coordinateSourceUrl` when the
    /// pack omits an explicit `sources` array.
    let sources: [Source]

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
      self.key = key
      self.name = name
      self.introduction = introduction
      self.culturalElementKey = culturalElementKey
      self.attractionKey = attractionKey
      self.latitude = latitude
      self.longitude = longitude
      self.coordinateSourceUrl = coordinateSourceUrl
      if sources.isEmpty, let coordinateSourceUrl, !coordinateSourceUrl.isEmpty {
        self.sources = [Source.inferred(from: coordinateSourceUrl)]
      } else {
        self.sources = sources
      }
    }

    enum CodingKeys: String, CodingKey {
      case key, name, introduction, culturalElementKey, attractionKey
      case latitude, longitude, coordinateSourceUrl, sources
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      key = try container.decode(String.self, forKey: .key)
      name = try container.decode(String.self, forKey: .name)
      introduction = try container.decode(RichTextDocument.self, forKey: .introduction)
      culturalElementKey = try container.decode(String.self, forKey: .culturalElementKey)
      attractionKey = try container.decode(String.self, forKey: .attractionKey)
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
  }

  /// A curated exploration path that binds a set of cultural element keys
  /// and a completion threshold (`minContacted`).
  nonisolated struct Theme: Decodable, Sendable, Identifiable, Hashable {
    var id: String { key }

    let key: String
    let name: String
    let summary: String
    let elementKeys: [String]
    /// Number of theme elements the user must have joined the graph for.
    let minContacted: Int

    init(
      key: String,
      name: String,
      summary: String,
      elementKeys: [String],
      minContacted: Int
    ) {
      self.key = key
      self.name = name
      self.summary = summary
      self.elementKeys = elementKeys
      self.minContacted = minContacted
    }
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
    elements = try container.decode([Element].self, forKey: .elements)
    attractions = try container.decode([Attraction].self, forKey: .attractions)
    relations = try container.decode([Relation].self, forKey: .relations)
    introductions = try container.decode([IntroductionRecord].self, forKey: .introductions)
    themes = try container.decodeIfPresent([Theme].self, forKey: .themes) ?? []
    locales = try container.decodeIfPresent([String: LocaleOverlay].self, forKey: .locales)
  }
}

/// Sidecar JSON for role-split element lists (`elements-sight.json` /
/// `elements-history.json`). Same element shape as the main pack.
nonisolated struct KnowledgePackElementFile: Decodable, Sendable {
  let elements: [KnowledgePack.Element]
}
  static func name(for publisher: String) -> String {
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
