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

  static func live(
    baseURL: URL = CultureLensAPI.shared.baseURL,
    session: URLSession = .shared
  ) -> CultureContentService {
    CultureContentService { latitude, longitude, radiusMeters, limit in
      let endpoint = baseURL.appending(
        path: "v1/attraction-introductions/recommendations"
      )
      guard
        var components = URLComponents(
          url: endpoint,
          resolvingAgainstBaseURL: false
        )
      else {
        throw CultureContentServiceError.invalidResponse
      }
      components.queryItems = [
        URLQueryItem(name: "latitude", value: String(latitude)),
        URLQueryItem(name: "longitude", value: String(longitude)),
        URLQueryItem(name: "radiusMeters", value: String(radiusMeters)),
        URLQueryItem(name: "limit", value: String(limit)),
      ]
      guard let url = components.url else {
        throw CultureContentServiceError.invalidResponse
      }

      var request = URLRequest(url: url)
      request.timeoutInterval = 20
      request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")

      let data: Data
      let response: URLResponse
      do {
        (data, response) = try await session.data(for: request)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw CultureContentServiceError.transport(error.localizedDescription)
      }

      guard
        let httpResponse = response as? HTTPURLResponse,
        (200..<300).contains(httpResponse.statusCode)
      else {
        throw CultureContentServiceError.serverUnavailable
      }

      do {
        return try JSONDecoder().decode(
          NearbyRecommendationsResponse.self,
          from: data
        )
      } catch {
        throw CultureContentServiceError.invalidResponse
      }
    }
  }
}
