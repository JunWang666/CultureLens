import Foundation

struct RemoteRecognitionService: Sendable {
  let baseURL: URL
  var session: URLSession = .shared

  func recognize(_ input: RecognitionInput) async throws -> RecognitionResult {
    let endpoint = baseURL.appending(path: "v1/recognitions")
    var request = URLRequest(url: endpoint)
    let requestID = UUID()
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(requestID.uuidString, forHTTPHeaderField: "X-Request-ID")

    let body = RecognitionAPIRequest(
      requestID: requestID,
      imageBase64: input.imageBase64,
      mimeType: "image/jpeg",
      location: input.place.map(RecognitionAPILocation.init),
      contextNote: input.contextNote?.nilIfBlank,
      locale: input.localeIdentifier
    )
    request.httpBody = try JSONEncoder().encode(body)

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw RecognitionServiceError.transport(error.localizedDescription)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw RecognitionServiceError.invalidResponse
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      let payload = try? JSONDecoder().decode(APIErrorPayload.self, from: data)
      throw RecognitionServiceError.server(
        statusCode: httpResponse.statusCode,
        message: payload?.error
      )
    }

    do {
      return try JSONDecoder().decode(RecognitionResult.self, from: data)
    } catch {
      throw RecognitionServiceError.invalidResponse
    }
  }
}

private struct RecognitionAPIRequest: Encodable {
  let requestID: UUID
  let imageBase64: String
  let mimeType: String
  let location: RecognitionAPILocation?
  let contextNote: String?
  let locale: String

  enum CodingKeys: String, CodingKey {
    case requestID = "request_id"
    case imageBase64 = "image_base64"
    case mimeType = "mime_type"
    case location
    case contextNote = "context_note"
    case locale
  }
}

private struct RecognitionAPILocation: Encodable {
  let latitude: Double
  let longitude: Double
  let accuracyMeters: Double?
  let cityName: String?
  let regionName: String?
  let regionCode: String?
  let displayName: String?

  init(_ place: PlaceContext) {
    latitude = place.latitude
    longitude = place.longitude
    accuracyMeters = place.accuracyMeters
    cityName = place.cityName
    regionName = place.regionName
    regionCode = place.regionCode
    displayName = place.displayName
  }

  enum CodingKeys: String, CodingKey {
    case latitude
    case longitude
    case accuracyMeters = "accuracy_meters"
    case cityName = "city_name"
    case regionName = "region_name"
    case regionCode = "region_code"
    case displayName = "display_name"
  }
}

private struct APIErrorPayload: Decodable {
  let error: String?
}

extension String {
  fileprivate var nilIfBlank: String? {
    let value = trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}
