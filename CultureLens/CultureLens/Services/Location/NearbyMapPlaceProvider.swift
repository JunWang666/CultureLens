@preconcurrency import CoreLocation
import Contacts
import MapKit

/// Resolves the Apple Maps points of interest that can help a visual model
/// understand the immediate setting of a scan. MapKit may return a larger
/// bounding-area result set, so distance is checked again before trimming.
@MainActor
protocol NearbyMapPlaceProviding {
  func nearbyPlaces(around place: PlaceContext) async -> [NearbyMapPlaceContext]
}

@MainActor
struct NearbyMapPlaceProvider: NearbyMapPlaceProviding {
  static let searchRadiusMeters: CLLocationDistance = 1_000
  static let maximumPlaceCount = 3

  func nearbyPlaces(around place: PlaceContext) async -> [NearbyMapPlaceContext] {
    let coordinate = CLLocationCoordinate2D(
      latitude: place.latitude,
      longitude: place.longitude
    )
    guard CLLocationCoordinate2DIsValid(coordinate) else { return [] }

    let origin = CLLocation(latitude: place.latitude, longitude: place.longitude)
    let request = MKLocalPointsOfInterestRequest(
      center: coordinate,
      radius: Self.searchRadiusMeters
    )

    do {
      let response = try await MKLocalSearch(request: request).start()
      return Self.contexts(from: response.mapItems, origin: origin)
    } catch {
      // Geographic context is optional enrichment. A Maps outage, offline
      // device, or sparse map coverage must never prevent recognition.
      return []
    }
  }

  static func contexts(
    from mapItems: [MKMapItem],
    origin: CLLocation
  ) -> [NearbyMapPlaceContext] {
    var seen = Set<String>()

    return mapItems.compactMap { mapItem in
      guard let name = nonEmpty(mapItem.name) else { return nil }
      let coordinate = mapItem.placemark.coordinate
      guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }

      let distance = origin.distance(
        from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
      )
      guard distance.isFinite, distance <= searchRadiusMeters else { return nil }

      let key = "\(name.lowercased())|\(coordinate.latitude)|\(coordinate.longitude)"
      guard seen.insert(key).inserted else { return nil }

      return NearbyMapPlaceContext(
        name: name,
        latitude: coordinate.latitude,
        longitude: coordinate.longitude,
        distanceMeters: distance,
        address: formattedAddress(for: mapItem.placemark)
      )
    }
    .sorted { lhs, rhs in
      if lhs.distanceMeters != rhs.distanceMeters {
        return lhs.distanceMeters < rhs.distanceMeters
      }
      return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
    .prefix(maximumPlaceCount)
    .map { $0 }
  }

  private static func formattedAddress(for placemark: CLPlacemark) -> String? {
    if let postalAddress = placemark.postalAddress {
      return nonEmpty(CNPostalAddressFormatter.string(from: postalAddress, style: .mailingAddress))
    }

    return nonEmpty(
      [
        placemark.thoroughfare,
        placemark.subLocality,
        placemark.locality,
        placemark.administrativeArea,
        placemark.country,
      ]
      .compactMap { nonEmpty($0) }
      .joined(separator: "，")
    )
  }

  private static func nonEmpty(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }
}
