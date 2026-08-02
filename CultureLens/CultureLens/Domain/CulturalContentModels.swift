import Foundation

nonisolated struct RichTextDocument: Codable, Hashable, Sendable {
  nonisolated struct Block: Codable, Hashable, Sendable {
    let type: String
    let text: String
  }

  let schemaVersion: Int
  let blocks: [Block]

  var plainText: String {
    blocks
      .map(\.text)
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
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
