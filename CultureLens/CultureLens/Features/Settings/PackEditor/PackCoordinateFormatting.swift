import CoreLocation
import Foundation

/// Pure helpers for pack-editor latitude/longitude text fields and MapKit pickers.
enum PackCoordinateFormatting {
  /// West Lake default framing when the draft has no usable coordinates.
  static let defaultEditorCoordinate = CLLocationCoordinate2D(
    latitude: 30.242_5,
    longitude: 120.148_3
  )

  static func parse(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite else { return nil }
    return value
  }

  static func format(_ value: Double) -> String {
    String(format: "%.6f", value)
  }

  static func isValid(latitude: Double, longitude: Double) -> Bool {
    latitude.isFinite
      && longitude.isFinite
      && (-90...90).contains(latitude)
      && (-180...180).contains(longitude)
  }

  /// Treat the unset draft default `(0, 0)` as "no location yet".
  static func isUnsetOrigin(latitude: Double, longitude: Double) -> Bool {
    latitude == 0 && longitude == 0
  }

  static func coordinate(
    latitudeText: String,
    longitudeText: String
  ) -> CLLocationCoordinate2D? {
    guard let latitude = parse(latitudeText),
          let longitude = parse(longitudeText),
          isValid(latitude: latitude, longitude: longitude)
    else { return nil }
    return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  /// Prefer the draft coordinate when it is valid and not the unset origin.
  static func initialCoordinate(
    latitudeText: String,
    longitudeText: String
  ) -> CLLocationCoordinate2D {
    guard let coordinate = coordinate(latitudeText: latitudeText, longitudeText: longitudeText),
          !isUnsetOrigin(latitude: coordinate.latitude, longitude: coordinate.longitude)
    else {
      return defaultEditorCoordinate
    }
    return coordinate
  }

  static func appleMapsURL(latitude: Double, longitude: Double) -> String {
    let lat = format(latitude)
    let lon = format(longitude)
    return "https://maps.apple.com/?ll=\(lat),\(lon)"
  }
}
