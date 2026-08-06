import CryptoKit
import Foundation

/// RFC 4122 UUIDv5 (SHA-1, name-based), byte-compatible with Go's
/// `uuid.NewSHA1(uuid.NameSpaceURL, name)` used by the backend pipeline to
/// derive deterministic identifiers.
nonisolated enum DeterministicID {
  /// RFC 4122 URL namespace, identical to Go's `uuid.NameSpaceURL`.
  static let nameSpaceURL = UUID(
    uuidString: "6ba7b811-9dad-11d1-80b4-00c04fd430c8"
  )!

  static func v5(namespace: UUID = nameSpaceURL, name: String) -> UUID {
    var data = Data()
    withUnsafeBytes(of: namespace.uuid) { data.append(contentsOf: $0) }
    data.append(contentsOf: name.utf8)

    var digest = Array(Insecure.SHA1.hash(data: data).prefix(16))
    digest[6] = (digest[6] & 0x0F) | 0x50  // version 5
    digest[8] = (digest[8] & 0x3F) | 0x80  // RFC 4122 variant
    return UUID(
      uuid: (
        digest[0], digest[1], digest[2], digest[3],
        digest[4], digest[5], digest[6], digest[7],
        digest[8], digest[9], digest[10], digest[11],
        digest[12], digest[13], digest[14], digest[15]
      )
    )
  }

  /// `culturalElementID` in pipeline.go.
  static func culturalElement(_ key: String) -> UUID {
    v5(name: "culturelens:cultural-element:" + key.lowercased())
  }

  /// Attraction (scannable POI) identity. Kept in a separate namespace from
  /// `culturalElement` because pack data intentionally shares key strings
  /// between an attraction and its bound element.
  static func attraction(_ key: String) -> UUID {
    v5(name: "culturelens:attraction:" + key.lowercased())
  }

  /// Map-point identity: one per physical location of an attraction. The same
  /// attraction key can live at several sites across packs (e.g. an exhibit on
  /// loan); coordinates rounded to 3 decimals (~110 m) cluster on-site records.
  static func attractionPoint(key: String, latitude: Double, longitude: Double) -> UUID {
    let lat = String(format: "%.3f", latitude)
    let lng = String(format: "%.3f", longitude)
    return v5(name: "culturelens:attraction-point:" + key.lowercased() + ":" + lat + "," + lng)
  }
}
