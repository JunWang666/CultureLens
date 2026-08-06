import CoreLocation
import Foundation

nonisolated struct ImportedTrackPoint: Codable, Equatable, Sendable {
  let latitude: Double
  let longitude: Double
  let elevationMeters: Double?
  let recordedAt: Date?

  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }
}

nonisolated struct ImportedTrackSegment: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let points: [ImportedTrackPoint]

  init(id: UUID = UUID(), points: [ImportedTrackPoint]) {
    self.id = id
    self.points = points
  }

  /// Keeps the full imported data on disk while bounding MapKit render work.
  func sampledPoints(maximumCount: Int = 10_000) -> [ImportedTrackPoint] {
    guard maximumCount >= 2, points.count > maximumCount else { return points }
    let step = Double(points.count - 1) / Double(maximumCount - 1)
    return (0..<maximumCount).map { sampleIndex in
      if sampleIndex == maximumCount - 1 {
        return points[points.count - 1]
      }
      return points[Int(Double(sampleIndex) * step)]
    }
  }
}

nonisolated enum ImportedTrackSourceKind: String, Codable, Sendable {
  case gpxFile
  case appleFitness
}

nonisolated struct ImportedTrack: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let name: String
  let sourceFileName: String
  /// Optional for backward compatibility with tracks saved before sources were recorded.
  let sourceKind: ImportedTrackSourceKind?
  /// Stable source identity, such as an HKWorkout UUID, used for idempotent imports.
  let sourceIdentifier: String?
  let importedAt: Date
  let sourceStartedAt: Date?
  let distanceMeters: Double
  let segments: [ImportedTrackSegment]

  init(
    id: UUID,
    name: String,
    sourceFileName: String,
    sourceKind: ImportedTrackSourceKind? = .gpxFile,
    sourceIdentifier: String? = nil,
    importedAt: Date,
    sourceStartedAt: Date?,
    distanceMeters: Double,
    segments: [ImportedTrackSegment]
  ) {
    self.id = id
    self.name = name
    self.sourceFileName = sourceFileName
    self.sourceKind = sourceKind
    self.sourceIdentifier = sourceIdentifier
    self.importedAt = importedAt
    self.sourceStartedAt = sourceStartedAt
    self.distanceMeters = distanceMeters
    self.segments = segments
  }

  var pointCount: Int {
    segments.reduce(0) { $0 + $1.points.count }
  }
}

nonisolated struct ParsedGPXTrack: Equatable, Sendable {
  let name: String
  let sourceStartedAt: Date?
  let distanceMeters: Double
  let segments: [ImportedTrackSegment]
}

nonisolated struct FitnessWorkoutRouteDraft: Equatable, Sendable {
  let sourceIdentifier: String
  let name: String
  let sourceName: String
  let startedAt: Date
  let segments: [ImportedTrackSegment]
}

nonisolated enum ImportedTrackError: LocalizedError, Equatable {
  case fileTooLarge
  case tooManyPoints
  case unreadableFile
  case invalidGPX
  case emptyTrack
  case saveFailed

  var errorDescription: String? {
    switch self {
    case .fileTooLarge:
      String(localized: "轨迹文件过大，暂不支持超过 50 MB 的文件。")
    case .tooManyPoints:
      String(localized: "轨迹点过多，暂不支持超过 200,000 个点的文件。")
    case .unreadableFile:
      String(localized: "无法读取这个轨迹文件。")
    case .invalidGPX:
      String(localized: "文件不是有效的 GPX 轨迹。")
    case .emptyTrack:
      String(localized: "记录中没有可绘制的运动轨迹。")
    case .saveFailed:
      String(localized: "轨迹已读取，但无法保存在 App 中。")
    }
  }
}

nonisolated enum GPXTrackParser {
  static func parse(
    data: Data,
    sourceFileName: String,
    maximumPointCount: Int = 200_000
  ) throws -> ParsedGPXTrack {
    let delegate = GPXParserDelegate(
      fallbackName: URL(fileURLWithPath: sourceFileName).deletingPathExtension().lastPathComponent,
      maximumPointCount: maximumPointCount
    )
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.shouldProcessNamespaces = false
    parser.shouldReportNamespacePrefixes = false
    parser.shouldResolveExternalEntities = false

    let parsed = parser.parse()
    if let failure = delegate.failure {
      throw failure
    }
    guard parsed else {
      throw ImportedTrackError.invalidGPX
    }
    return try delegate.result()
  }
}

actor ImportedTrackStore {
  static let shared = ImportedTrackStore()

  private static let maximumFileSize = 50 * 1_024 * 1_024

  private let fileManager: FileManager
  private let directoryOverride: URL?
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(fileManager: FileManager = .default, directory: URL? = nil) {
    self.fileManager = fileManager
    directoryOverride = directory

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    self.encoder = encoder

    decoder = JSONDecoder()
  }

  func load() throws -> [ImportedTrack] {
    let directory = try tracksDirectory()
    let urls = try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    return urls
      .filter { $0.pathExtension.lowercased() == "json" }
      .compactMap { url in
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(ImportedTrack.self, from: data)
      }
      .sorted { $0.importedAt > $1.importedAt }
  }

  func importGPX(from sourceURL: URL) throws -> ImportedTrack {
    let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if hasSecurityScope {
        sourceURL.stopAccessingSecurityScopedResource()
      }
    }

    if let fileSize = try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
      fileSize > Self.maximumFileSize
    {
      throw ImportedTrackError.fileTooLarge
    }

    guard let data = try? Data(contentsOf: sourceURL, options: [.mappedIfSafe]) else {
      throw ImportedTrackError.unreadableFile
    }
    return try importGPX(data: data, sourceFileName: sourceURL.lastPathComponent)
  }

  @discardableResult
  func importGPX(data: Data, sourceFileName: String) throws -> ImportedTrack {
    guard data.count <= Self.maximumFileSize else {
      throw ImportedTrackError.fileTooLarge
    }

    let parsed = try GPXTrackParser.parse(data: data, sourceFileName: sourceFileName)
    let track = ImportedTrack(
      id: UUID(),
      name: parsed.name,
      sourceFileName: sourceFileName,
      sourceKind: .gpxFile,
      importedAt: .now,
      sourceStartedAt: parsed.sourceStartedAt,
      distanceMeters: parsed.distanceMeters,
      segments: parsed.segments
    )

    return try persist(track)
  }

  /// Copies a HealthKit workout route into the App-owned track store.
  /// Re-importing the same workout is idempotent and returns the existing track.
  @discardableResult
  func importFitnessWorkout(_ draft: FitnessWorkoutRouteDraft) throws -> ImportedTrack {
    if let existing = try load().first(where: {
      $0.sourceKind == .appleFitness && $0.sourceIdentifier == draft.sourceIdentifier
    }) {
      return existing
    }

    let segments = draft.segments.filter { $0.points.count >= 2 }
    guard !segments.isEmpty else {
      throw ImportedTrackError.emptyTrack
    }
    let pointCount = segments.reduce(0) { $0 + $1.points.count }
    guard pointCount <= 200_000 else {
      throw ImportedTrackError.tooManyPoints
    }

    let track = ImportedTrack(
      id: UUID(),
      name: draft.name,
      sourceFileName: draft.sourceName,
      sourceKind: .appleFitness,
      sourceIdentifier: draft.sourceIdentifier,
      importedAt: .now,
      sourceStartedAt: draft.startedAt,
      distanceMeters: Self.distance(of: segments),
      segments: segments
    )

    return try persist(track)
  }

  private func persist(_ track: ImportedTrack) throws -> ImportedTrack {
    do {
      let directory = try tracksDirectory()
      let data = try encoder.encode(track)
      try data.write(to: fileURL(for: track.id, in: directory), options: [.atomic])
      return track
    } catch let error as ImportedTrackError {
      throw error
    } catch {
      throw ImportedTrackError.saveFailed
    }
  }

  private static func distance(of segments: [ImportedTrackSegment]) -> Double {
    segments.reduce(0) { total, segment in
      total + zip(segment.points, segment.points.dropFirst()).reduce(0) { partial, pair in
        partial + CLLocation(
          latitude: pair.0.latitude,
          longitude: pair.0.longitude
        ).distance(
          from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
        )
      }
    }
  }

  func delete(_ track: ImportedTrack) throws {
    let url = fileURL(for: track.id, in: try tracksDirectory())
    guard fileManager.fileExists(atPath: url.path) else { return }
    try fileManager.removeItem(at: url)
  }

  private func tracksDirectory() throws -> URL {
    let directory: URL
    if let directoryOverride {
      directory = directoryOverride
    } else {
      let applicationSupport = try fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      directory = applicationSupport
        .appending(path: "CultureLens", directoryHint: .isDirectory)
        .appending(path: "ImportedTracks", directoryHint: .isDirectory)
    }
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func fileURL(for id: UUID, in directory: URL) -> URL {
    directory.appending(path: "\(id.uuidString.lowercased()).json")
  }
}

nonisolated private final class GPXParserDelegate: NSObject, XMLParserDelegate {
  private struct PendingPoint {
    let latitude: Double
    let longitude: Double
    var elevationMeters: Double?
    var recordedAt: Date?
  }

  private let fallbackName: String
  private let maximumPointCount: Int
  private var elementStack: [String] = []
  private var textStack: [String] = []
  private var parsedName: String?
  private var completedSegments: [ImportedTrackSegment] = []
  private var currentSegment: [ImportedTrackPoint]?
  private var currentPoint: PendingPoint?
  private var pointCount = 0

  private let fractionalDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private let dateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  fileprivate var failure: ImportedTrackError?

  init(fallbackName: String, maximumPointCount: Int) {
    let trimmed = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
    self.fallbackName = trimmed.isEmpty ? String(localized: "导入的运动轨迹") : trimmed
    self.maximumPointCount = maximumPointCount
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    let element = normalized(elementName)
    elementStack.append(element)
    textStack.append("")

    switch element {
    case "trkseg":
      flushCurrentSegment()
      currentSegment = []
    case "rte":
      flushCurrentSegment()
      currentSegment = []
    case "trkpt", "rtept":
      guard
        let latitudeText = attributeDict["lat"],
        let longitudeText = attributeDict["lon"],
        let latitude = Double(latitudeText),
        let longitude = Double(longitudeText),
        (-90...90).contains(latitude),
        (-180...180).contains(longitude)
      else {
        currentPoint = nil
        return
      }
      if currentSegment == nil {
        currentSegment = []
      }
      currentPoint = PendingPoint(latitude: latitude, longitude: longitude)
    default:
      break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    guard !textStack.isEmpty else { return }
    textStack[textStack.count - 1].append(string)
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    let element = normalized(elementName)
    let text = textStack.popLast()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let parent = elementStack.dropLast().last

    switch element {
    case "name" where parsedName == nil && (parent == "trk" || parent == "rte"):
      if !text.isEmpty {
        parsedName = String(text.prefix(120))
      }
    case "ele":
      if var point = currentPoint, let elevation = Double(text) {
        point.elevationMeters = elevation
        currentPoint = point
      }
    case "time":
      if var point = currentPoint, let date = parseDate(text) {
        point.recordedAt = date
        currentPoint = point
      }
    case "trkpt", "rtept":
      appendCurrentPoint(to: parser)
    case "trkseg", "rte":
      flushCurrentSegment()
    case "trk":
      flushCurrentSegment()
    default:
      break
    }

    _ = elementStack.popLast()
  }

  fileprivate func result() throws -> ParsedGPXTrack {
    flushCurrentSegment()
    let drawableSegments = completedSegments.filter { $0.points.count >= 2 }
    guard !drawableSegments.isEmpty else {
      throw ImportedTrackError.emptyTrack
    }

    let dates = drawableSegments.flatMap(\.points).compactMap(\.recordedAt)
    return ParsedGPXTrack(
      name: parsedName ?? fallbackName,
      sourceStartedAt: dates.min(),
      distanceMeters: Self.distance(of: drawableSegments),
      segments: drawableSegments
    )
  }

  private func appendCurrentPoint(to parser: XMLParser) {
    guard let currentPoint else { return }
    pointCount += 1
    guard pointCount <= maximumPointCount else {
      failure = .tooManyPoints
      parser.abortParsing()
      return
    }
    currentSegment?.append(
      ImportedTrackPoint(
        latitude: currentPoint.latitude,
        longitude: currentPoint.longitude,
        elevationMeters: currentPoint.elevationMeters,
        recordedAt: currentPoint.recordedAt
      )
    )
    self.currentPoint = nil
  }

  private func flushCurrentSegment() {
    guard let currentSegment else { return }
    if currentSegment.count >= 2 {
      completedSegments.append(ImportedTrackSegment(points: currentSegment))
    }
    self.currentSegment = nil
  }

  private func parseDate(_ value: String) -> Date? {
    fractionalDateFormatter.date(from: value) ?? dateFormatter.date(from: value)
  }

  private func normalized(_ elementName: String) -> String {
    elementName.split(separator: ":").last.map(String.init)?.lowercased()
      ?? elementName.lowercased()
  }

  private static func distance(of segments: [ImportedTrackSegment]) -> Double {
    segments.reduce(0) { total, segment in
      total + zip(segment.points, segment.points.dropFirst()).reduce(0) { partial, pair in
        partial + haversineDistance(from: pair.0, to: pair.1)
      }
    }
  }

  private static func haversineDistance(
    from start: ImportedTrackPoint,
    to end: ImportedTrackPoint
  ) -> Double {
    let earthRadius = 6_371_000.0
    let latitude1 = start.latitude * .pi / 180
    let latitude2 = end.latitude * .pi / 180
    let deltaLatitude = (end.latitude - start.latitude) * .pi / 180
    let deltaLongitude = (end.longitude - start.longitude) * .pi / 180
    let a = sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
      + cos(latitude1) * cos(latitude2)
      * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
    return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
  }
}
