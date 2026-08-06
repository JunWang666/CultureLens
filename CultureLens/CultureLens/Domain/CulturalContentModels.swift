import Foundation

nonisolated struct RichTextDocument: Codable, Hashable, Sendable {
  nonisolated struct Block: Codable, Hashable, Sendable {
    let type: String
    let text: String?
    let url: String?
    let caption: String?

    init(
      type: String,
      text: String? = nil,
      url: String? = nil,
      caption: String? = nil
    ) {
      self.type = type
      self.text = text
      self.url = url
      self.caption = caption
    }

    var imageURL: URL? {
      guard
        type == "image",
        let url = url?.trimmingCharacters(in: .whitespacesAndNewlines),
        let resolved = URL(string: url),
        resolved.scheme?.lowercased() == "https",
        resolved.host != nil
      else {
        return nil
      }
      return resolved
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(type, forKey: .type)
      try container.encodeIfPresent(text, forKey: .text)
      try container.encodeIfPresent(url, forKey: .url)
      try container.encodeIfPresent(caption, forKey: .caption)
    }
  }

  let schemaVersion: Int
  let blocks: [Block]

  init(schemaVersion: Int, blocks: [Block]) {
    self.schemaVersion = schemaVersion
    self.blocks = blocks
  }

  var plainText: String {
    blocks
      .compactMap(\.text)
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
  }

  var imageBlocks: [Block] {
    blocks.filter { $0.imageURL != nil }
  }

  /// Translation overlays and live translation results may contain text only.
  /// Keep their localized text while restoring the source document's remote
  /// images after the first text block. A localized document that already owns
  /// image blocks remains authoritative and is returned unchanged.
  func preservingImages(from source: RichTextDocument?) -> RichTextDocument {
    guard imageBlocks.isEmpty, let source else { return self }
    let sourceImages = source.imageBlocks
    guard !sourceImages.isEmpty else { return self }

    var mergedBlocks = blocks
    mergedBlocks.insert(contentsOf: sourceImages, at: min(1, mergedBlocks.count))
    return RichTextDocument(schemaVersion: schemaVersion, blocks: mergedBlocks)
  }
}

nonisolated struct ContentReference: Codable, Hashable, Sendable {
  let key: String
  let name: String
}

nonisolated struct ContentCoordinate: Codable, Hashable, Sendable {
  let latitude: Double
  let longitude: Double
}

nonisolated struct AttractionIntroductionRecommendation: Identifiable, Codable, Hashable, Sendable {
  var id: String { key }

  let key: String
  let name: String
  let introduction: RichTextDocument
  let culturalElement: ContentReference
  let attraction: ContentReference
  let location: ContentCoordinate
  let distanceMeters: Double
}

nonisolated struct RequestedRecommendationLocation: Codable, Hashable, Sendable {
  let latitude: Double
  let longitude: Double
  let radiusMeters: Double
}

nonisolated struct NearbyRecommendationsResponse: Codable, Hashable, Sendable {
  let requestedLocation: RequestedRecommendationLocation
  let totalMatches: Int
  let introductions: [AttractionIntroductionRecommendation]
}
