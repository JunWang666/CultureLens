import CryptoKit
import Foundation

/// Sidecar file map + pack-manifest for a knowledge pack export.
nonisolated struct KnowledgePackExportBundle: Sendable {
  /// Relative path → UTF-8 JSON bytes.
  let files: [String: Data]
  let directoryName: String
  let manifest: KnowledgePackManifest

  /// Sorted sidecar filenames (includes `pack-manifest.json`).
  var fileNames: [String] { files.keys.sorted() }
}

nonisolated struct KnowledgePackManifest: Codable, Sendable, Hashable {
  let packVersion: String
  let generatedAt: String
  let recordCounts: RecordCounts
  let sha256: String
  let files: [String]

  nonisolated struct RecordCounts: Codable, Sendable, Hashable {
    let elements: Int
    let elementsSight: Int
    let elementsHistory: Int
    let relations: Int
    let introductions: Int
    let attractions: Int
    let themes: Int
  }
}

/// Writes knowledge packs as the repository sidecar layout (slim main JSON +
/// per-type sidecars + `pack-manifest.json`), and packages them as a zip for
/// sharing from the in-app editor.
enum KnowledgePackExporter {
  /// Builds the sidecar file map for `pack` without touching the filesystem.
  nonisolated static func makeExportBundle(
    for pack: KnowledgePack,
    generatedAt: Date = Date(),
    directoryName: String? = nil
  ) throws -> KnowledgePackExportBundle {
    let stamped = pack.withStampedContentRoles()
    let encoder = makeEncoder()

    let sightElements = stamped.elements.filter {
      $0.resolvedContentRole(attractionKeys: Set(stamped.attractions.map(\.key))) == .sight
    }
    let historyElements = stamped.elements.filter {
      $0.resolvedContentRole(attractionKeys: Set(stamped.attractions.map(\.key))) == .history
    }

    var files: [String: Data] = [:]
    files["knowledge-pack.json"] = try encoder.encode(
      KnowledgePackMainSidecar(
        version: stamped.version,
        sourceLanguage: stamped.sourceLanguage,
        relations: stamped.relations
      )
    )
    files["elements-sight.json"] = try encoder.encode(
      KnowledgePackSightSidecar(elements: sightElements, attractions: stamped.attractions)
    )
    files["elements-history.json"] = try encoder.encode(
      KnowledgePackHistorySidecar(elements: historyElements)
    )
    files["introductions.json"] = try encoder.encode(
      KnowledgePackIntroductionsSidecar(introductions: stamped.introductions)
    )
    files["themes.json"] = try encoder.encode(
      KnowledgePackThemesSidecar(themes: stamped.themes)
    )

    if let locales = stamped.locales {
      for (language, overlay) in locales.sorted(by: { $0.key < $1.key }) {
        files["locales-\(language).json"] = try encoder.encode(overlay)
      }
    }

    let contentFiles = files.keys.sorted()
    let digest = sha256Hex(of: contentFiles.compactMap { files[$0] })
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let manifest = KnowledgePackManifest(
      packVersion: stamped.version,
      generatedAt: formatter.string(from: generatedAt),
      recordCounts: .init(
        elements: stamped.elements.count,
        elementsSight: sightElements.count,
        elementsHistory: historyElements.count,
        relations: stamped.relations.count,
        introductions: stamped.introductions.count,
        attractions: stamped.attractions.count,
        themes: stamped.themes.count
      ),
      sha256: digest,
      files: contentFiles
    )
    files["pack-manifest.json"] = try encoder.encode(manifest)

    let folder = directoryName ?? sanitizeDirectoryName(stamped.version)
    return KnowledgePackExportBundle(files: files, directoryName: folder, manifest: manifest)
  }

  /// Writes sidecar files under `directoryURL` (created if needed).
  @discardableResult
  nonisolated static func writeSidecars(
    _ bundle: KnowledgePackExportBundle,
    to directoryURL: URL
  ) throws -> URL {
    let fm = FileManager.default
    try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    for (name, data) in bundle.files {
      try data.write(to: directoryURL.appendingPathComponent(name), options: .atomic)
    }
    return directoryURL
  }

  /// Encodes a zip archive whose root folder is `bundle.directoryName`.
  nonisolated static func zipData(for bundle: KnowledgePackExportBundle) throws -> Data {
    var entries: [(name: String, data: Data)] = []
    let root = bundle.directoryName
    for name in bundle.fileNames {
      guard let data = bundle.files[name] else { continue }
      entries.append(("\(root)/\(name)", data))
    }
    return try ZipArchive.store(entries: entries)
  }

  /// Full monolith JSON (all arrays inline) — useful for round-trip import tests.
  nonisolated static func monolithData(for pack: KnowledgePack) throws -> Data {
    try makeEncoder().encode(pack.withStampedContentRoles())
  }

  nonisolated static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  nonisolated static func sanitizeDirectoryName(_ version: String) -> String {
    let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
    let cleaned = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
    let name = String(cleaned)
    return name.isEmpty ? "knowledge-pack" : name
  }

  nonisolated private static func sha256Hex(of parts: [Data]) -> String {
    var hasher = SHA256()
    for part in parts {
      hasher.update(data: part)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}

/// Slim main sidecar: version / source_language / relations only.
nonisolated struct KnowledgePackMainSidecar: Codable, Sendable {
  let version: String
  let sourceLanguage: String?
  let relations: [KnowledgePack.Relation]

  enum CodingKeys: String, CodingKey {
    case version
    case sourceLanguage = "source_language"
    case relations
  }
}

// MARK: - Minimal ZIP (store method)

enum ZipArchive {
  /// Builds an uncompressed ZIP from `(archive path, bytes)` entries.
  nonisolated static func store(entries: [(name: String, data: Data)]) throws -> Data {
    var central: Data = Data()
    var local: Data = Data()
    var offset: UInt32 = 0

    for entry in entries {
      let nameData = Data(entry.name.utf8)
      guard nameData.count <= UInt16.max else {
        throw KnowledgeStoreError.packInvalid("ZIP entry name too long: \(entry.name)")
      }
      let crc = crc32(entry.data)
      let size = UInt32(entry.data.count)
      let nameLen = UInt16(nameData.count)

      var localHeader = Data()
      localHeader.appendUInt32(0x0403_4b50) // local file header
      localHeader.appendUInt16(20) // version needed
      localHeader.appendUInt16(0) // flags
      localHeader.appendUInt16(0) // method: store
      localHeader.appendUInt16(0) // time
      localHeader.appendUInt16(0) // date
      localHeader.appendUInt32(crc)
      localHeader.appendUInt32(size)
      localHeader.appendUInt32(size)
      localHeader.appendUInt16(nameLen)
      localHeader.appendUInt16(0) // extra
      localHeader.append(nameData)
      localHeader.append(entry.data)
      local.append(localHeader)

      var centralHeader = Data()
      centralHeader.appendUInt32(0x0201_4b50) // central directory
      centralHeader.appendUInt16(20) // version made by
      centralHeader.appendUInt16(20) // version needed
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt32(crc)
      centralHeader.appendUInt32(size)
      centralHeader.appendUInt32(size)
      centralHeader.appendUInt16(nameLen)
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt16(0)
      centralHeader.appendUInt32(0)
      centralHeader.appendUInt32(offset)
      centralHeader.append(nameData)
      central.append(centralHeader)

      offset += UInt32(localHeader.count)
    }

    var end = Data()
    end.appendUInt32(0x0605_4b50)
    end.appendUInt16(0)
    end.appendUInt16(0)
    end.appendUInt16(UInt16(entries.count))
    end.appendUInt16(UInt16(entries.count))
    end.appendUInt32(UInt32(central.count))
    end.appendUInt32(UInt32(local.count))
    end.appendUInt16(0)

    var zip = Data()
    zip.append(local)
    zip.append(central)
    zip.append(end)
    return zip
  }

  /// CRC-32 (ISO 3309 / ZIP).
  nonisolated static func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xffff_ffff
    for byte in data {
      let idx = Int((crc ^ UInt32(byte)) & 0xff)
      crc = (crc >> 8) ^ crcTable[idx]
    }
    return crc ^ 0xffff_ffff
  }

  private nonisolated static let crcTable: [UInt32] = {
    (0..<256).map { i -> UInt32 in
      var c = UInt32(i)
      for _ in 0..<8 {
        c = (c & 1) != 0 ? (0xedb8_8320 ^ (c >> 1)) : (c >> 1)
      }
      return c
    }
  }()
}

private extension Data {
  mutating func appendUInt16(_ value: UInt16) {
    var le = value.littleEndian
    Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
  }

  mutating func appendUInt32(_ value: UInt32) {
    var le = value.littleEndian
    Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
  }
}
