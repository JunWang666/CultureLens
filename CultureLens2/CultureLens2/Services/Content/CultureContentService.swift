import Foundation

enum CultureContentServiceError: LocalizedError {
  case invalidResponse
  case serverUnavailable
  case transport(String)

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      "附近内容的数据格式无效，请稍后重试。"
    case .serverUnavailable:
      "附近内容暂时不可用，请稍后重试。"
    case .transport:
      "无法连接文化内容服务，请检查网络后重试。"
    }
  }
}

struct CultureContentService: Sendable {
  var nearbyRecommendations:
    @Sendable (
      _ latitude: Double,
      _ longitude: Double,
      _ radiusMeters: Double,
      _ limit: Int
    ) async throws -> NearbyRecommendationsResponse

  /// Local implementation backed by the bundled knowledge pack; performs the
  /// same Haversine query the Go backend ran in PostgreSQL.
  static func live() -> CultureContentService {
    CultureContentService { latitude, longitude, radiusMeters, limit in
      guard let store = await KnowledgePackLoader.shared.store() else {
        throw CultureContentServiceError.serverUnavailable
      }
      let result: NearbyIntroductionResult
      do {
        result = try store.nearbyIntroductions(
          latitude: latitude,
          longitude: longitude,
          radiusMeters: radiusMeters,
          limit: limit
        )
      } catch {
        throw CultureContentServiceError.invalidResponse
      }
      return NearbyRecommendationsResponse(
        requestedLocation: RequestedRecommendationLocation(
          latitude: latitude,
          longitude: longitude,
          radiusMeters: radiusMeters
        ),
        totalMatches: result.totalMatches,
        introductions: result.introductions.map {
          AttractionIntroductionRecommendation(
            key: $0.key,
            name: $0.name,
            introduction: $0.introduction,
            culturalElement: ContentReference(
              key: $0.culturalElementKey,
              name: $0.culturalElementName
            ),
            attraction: ContentReference(
              key: $0.attractionKey,
              name: $0.attractionName
            ),
            location: ContentCoordinate(
              latitude: $0.latitude,
              longitude: $0.longitude
            ),
            distanceMeters: $0.distanceMeters
          )
        }
      )
    }
  }
}
