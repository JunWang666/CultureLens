import Foundation
import ImageIO

enum PhotoLocationProvider {
  /// Reads GPS from image bytes only. Does not touch the Photos library,
  /// so `PhotosPicker` / PHPicker stays permission-free.
  nonisolated static func embeddedPlaceContext(
    in imageData: Data
  ) -> PlaceContext? {
    guard
      let source = CGImageSourceCreateWithData(imageData as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(
        source,
        0,
        nil
      ) as? [CFString: Any],
      let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
      let latitude = coordinateComponent(
        value: gps[kCGImagePropertyGPSLatitude],
        reference: gps[kCGImagePropertyGPSLatitudeRef],
        negativeReference: "S"
      ),
      let longitude = coordinateComponent(
        value: gps[kCGImagePropertyGPSLongitude],
        reference: gps[kCGImagePropertyGPSLongitudeRef],
        negativeReference: "W"
      ),
      isValid(latitude: latitude, longitude: longitude)
    else {
      return nil
    }

    let horizontalAccuracy = number(
      from: gps[kCGImagePropertyGPSHPositioningError]
    ).flatMap { value in
      value.isFinite && value >= 0 ? value : nil
    }

    return PlaceContext(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: horizontalAccuracy,
      cityName: nil,
      regionName: nil,
      regionCode: nil,
      displayName: nil
    )
  }

  private nonisolated static func coordinateComponent(
    value: Any?,
    reference: Any?,
    negativeReference: String
  ) -> Double? {
    guard let value = number(from: value), value.isFinite else { return nil }
    let reference = (reference as? String)?.uppercased()
    if reference == negativeReference {
      return -abs(value)
    }
    if reference != nil {
      return abs(value)
    }
    return value
  }

  private nonisolated static func number(from value: Any?) -> Double? {
    switch value {
    case let number as NSNumber:
      number.doubleValue
    case let text as String:
      Double(text)
    default:
      nil
    }
  }

  private nonisolated static func isValid(
    latitude: Double,
    longitude: Double
  ) -> Bool {
    latitude.isFinite
      && longitude.isFinite
      && (-90...90).contains(latitude)
      && (-180...180).contains(longitude)
  }
}
