import CryptoKit
import Foundation

/// RFC 4122 UUIDv5 (SHA-1, name-based), byte-compatible with Go's
/// `uuid.NewSHA1(uuid.NameSpaceURL, name)` used by the backend pipeline to
/// derive deterministic identifiers.
///
/// Pack JSON entities carry these UUIDs as primary `id` values (minted from
/// the legacy slug). Runtime identity uses the pack UUID directly;
/// `culturalElement(_:)` / `attraction(_:)` remain for migration, fixtures,
/// and minting IDs for cross-pack slug references.
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

  /// Element identity from a legacy slug. Pack `Element.id` is this value.
  static func culturalElement(_ key: String) -> UUID {
    v5(name: "culturelens:cultural-element:" + key.lowercased())
  }

  /// Resolves a cultural-element UUID from a UUID string or legacy kebab slug.
  /// Used when decoding persisted scan/chat/progress rows that predate pack UUIDs.
  static func resolveCulturalElementID(from string: String) -> UUID {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    if let uuid = UUID(uuidString: trimmed) { return uuid }
    return culturalElement(trimmed)
  }

  /// True when `string` is not a UUID and looks like a legacy kebab slug.
  static func looksLikeLegacyElementSlug(_ string: String) -> Bool {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, UUID(uuidString: trimmed) == nil else { return false }
    return trimmed.contains("-")
  }

  /// Attraction (scannable POI) identity. Kept in a separate namespace from
  /// `culturalElement` because pack data intentionally shares key strings
  /// between an attraction and its bound element.
  static func attraction(_ key: String) -> UUID {
    v5(name: "culturelens:attraction:" + key.lowercased())
  }

  /// Resolves an attraction UUID from a UUID string or legacy kebab slug.
  static func resolveAttractionID(from string: String) -> UUID {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    if let uuid = UUID(uuidString: trimmed) { return uuid }
    return attraction(trimmed)
  }

  /// On-site introduction record identity.
  static func introduction(_ key: String) -> UUID {
    v5(name: "culturelens:introduction:" + key.lowercased())
  }

  /// Theme identity.
  static func theme(_ key: String) -> UUID {
    v5(name: "culturelens:theme:" + key.lowercased())
  }

  /// Map-point identity: one per physical location of an attraction. The same
  /// attraction can live at several sites across packs (e.g. an exhibit on
  /// loan); coordinates rounded to 3 decimals (~110 m) cluster on-site records.
  static func attractionPoint(attractionId: UUID, latitude: Double, longitude: Double) -> UUID {
    let lat = String(format: "%.3f", latitude)
    let lng = String(format: "%.3f", longitude)
    return v5(
      name: "culturelens:attraction-point:" + attractionId.uuidString.lowercased() + ":" + lat
        + "," + lng
    )
  }

  /// Legacy map-point identity from attraction slug (scan/history compat).
  static func attractionPoint(key: String, latitude: Double, longitude: Double) -> UUID {
    attractionPoint(
      attractionId: attraction(key),
      latitude: latitude,
      longitude: longitude
    )
  }
}
