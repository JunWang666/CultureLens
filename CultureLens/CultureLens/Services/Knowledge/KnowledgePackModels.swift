import Foundation

/// Codable models for the bundled knowledge pack
/// (`Resources/KnowledgePack/knowledge-pack.json`), mirroring the Go backend's
/// `content/hangzhou-west-lake.v1.json` export format.
nonisolated struct KnowledgePack: Decodable, Sendable {
  let version: String
  let elements: [Element]
  let attractions: [Attraction]
  let relations: [Relation]
  let introductions: [IntroductionRecord]

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
      if host.isEmpty { return "外部资料" }
      return host.replacingOccurrences(of: "www.", with: "")
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

  nonisolated struct Element: Decodable, Sendable {
    let key: String
    let name: String
    let introduction: RichTextDocument
    let sources: [Source]

    init(
      key: String,
      name: String,
      introduction: RichTextDocument,
      sources: [Source] = []
    ) {
      self.key = key
      self.name = name
      self.introduction = introduction
      self.sources = sources
    }

    enum CodingKeys: String, CodingKey {
      case key, name, introduction, sources
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      key = try container.decode(String.self, forKey: .key)
      name = try container.decode(String.self, forKey: .name)
      introduction = try container.decode(RichTextDocument.self, forKey: .introduction)
      sources = try container.decodeIfPresent([Source].self, forKey: .sources) ?? []
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

    init(elementKey: String, relatedElementKey: String) {
      self.elementKey = elementKey
      self.relatedElementKey = relatedElementKey
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

  init(
    version: String,
    elements: [Element],
    attractions: [Attraction],
    relations: [Relation],
    introductions: [IntroductionRecord]
  ) {
    self.version = version
    self.elements = elements
    self.attractions = attractions
    self.relations = relations
    self.introductions = introductions
  }
}
