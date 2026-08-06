import Foundation
import Testing

@testable import CultureLens

struct ImportedTrackStoreTests {
  @Test func parsesTrackMetadataAndPreservesSegments() throws {
    let data = Data(
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <gpx version="1.1" creator="CultureLensTests">
        <trk>
          <name>西湖晨跑</name>
          <trkseg>
            <trkpt lat="30.2500" lon="120.1500">
              <ele>8.5</ele>
              <time>2026-08-06T00:00:00Z</time>
            </trkpt>
            <trkpt lat="30.2510" lon="120.1510">
              <time>2026-08-06T00:01:00.500Z</time>
            </trkpt>
          </trkseg>
          <trkseg>
            <trkpt lat="30.3000" lon="120.2000" />
            <trkpt lat="30.3010" lon="120.2010" />
          </trkseg>
        </trk>
      </gpx>
      """.utf8
    )

    let parsed = try GPXTrackParser.parse(data: data, sourceFileName: "morning.gpx")

    #expect(parsed.name == "西湖晨跑")
    #expect(parsed.segments.count == 2)
    #expect(parsed.segments.map(\.points.count) == [2, 2])
    #expect(parsed.segments[0].points[0].elevationMeters == 8.5)
    #expect(parsed.sourceStartedAt != nil)
    #expect(parsed.distanceMeters > 200)
    #expect(parsed.distanceMeters < 400)
  }

  @Test func parsesRoutePointsAndUsesFilenameAsFallbackName() throws {
    let data = Data(
      """
      <gpx version="1.1">
        <rte>
          <rtept lat="30" lon="120" />
          <rtept lat="30.01" lon="120.01" />
        </rte>
      </gpx>
      """.utf8
    )

    let parsed = try GPXTrackParser.parse(data: data, sourceFileName: "周末骑行.gpx")

    #expect(parsed.name == "周末骑行")
    #expect(parsed.segments.count == 1)
    #expect(parsed.segments[0].points.count == 2)
  }

  @Test func rejectsTracksWithoutDrawableSegments() {
    let data = Data(
      """
      <gpx version="1.1">
        <trk><trkseg><trkpt lat="999" lon="120" /></trkseg></trk>
      </gpx>
      """.utf8
    )

    do {
      _ = try GPXTrackParser.parse(data: data, sourceFileName: "empty.gpx")
      Issue.record("Expected an empty-track error")
    } catch {
      #expect(error as? ImportedTrackError == .emptyTrack)
    }
  }

  @Test func rejectsExcessivePointCounts() {
    let data = Data(
      """
      <gpx version="1.1">
        <trk><trkseg>
          <trkpt lat="30" lon="120" />
          <trkpt lat="30.01" lon="120.01" />
        </trkseg></trk>
      </gpx>
      """.utf8
    )

    do {
      _ = try GPXTrackParser.parse(
        data: data,
        sourceFileName: "too-many.gpx",
        maximumPointCount: 1
      )
      Issue.record("Expected a point-limit error")
    } catch {
      #expect(error as? ImportedTrackError == .tooManyPoints)
    }
  }

  @Test func samplesLongSegmentsWithoutDroppingEndpoints() {
    let points = (0..<101).map { index in
      ImportedTrackPoint(
        latitude: 30 + Double(index) / 1_000,
        longitude: 120 + Double(index) / 1_000,
        elevationMeters: nil,
        recordedAt: nil
      )
    }
    let sampled = ImportedTrackSegment(points: points).sampledPoints(maximumCount: 10)

    #expect(sampled.count == 10)
    #expect(sampled.first == points.first)
    #expect(sampled.last == points.last)
  }

  @Test func persistsLoadsAndDeletesImportedTrack() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "CultureLensImportedTrackTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = ImportedTrackStore(directory: directory)
    let data = Data(
      """
      <gpx version="1.1">
        <trk><name>测试轨迹</name><trkseg>
          <trkpt lat="30" lon="120" />
          <trkpt lat="30.01" lon="120.01" />
        </trkseg></trk>
      </gpx>
      """.utf8
    )

    let imported = try await store.importGPX(data: data, sourceFileName: "test.gpx")
    let loaded = try await store.load()

    #expect(loaded == [imported])
    #expect(loaded[0].pointCount == 2)
    #expect(loaded[0].sourceKind == .gpxFile)

    try await store.delete(imported)
    #expect(try await store.load().isEmpty)
  }

  @Test func decodesTracksSavedBeforeSourceMetadataWasAdded() throws {
    let track = ImportedTrack(
      id: UUID(),
      name: "旧轨迹",
      sourceFileName: "legacy.gpx",
      importedAt: Date(timeIntervalSinceReferenceDate: 123),
      sourceStartedAt: nil,
      distanceMeters: 42,
      segments: [
        ImportedTrackSegment(points: [
          ImportedTrackPoint(latitude: 30, longitude: 120, elevationMeters: nil, recordedAt: nil),
          ImportedTrackPoint(latitude: 30.001, longitude: 120.001, elevationMeters: nil, recordedAt: nil),
        ])
      ]
    )
    let encoded = try JSONEncoder().encode(track)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "sourceKind")
    object.removeValue(forKey: "sourceIdentifier")

    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(ImportedTrack.self, from: legacyData)

    #expect(decoded.name == track.name)
    #expect(decoded.sourceKind == nil)
    #expect(decoded.sourceIdentifier == nil)
  }

  @Test func fitnessWorkoutImportIsPersistedAndIdempotent() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "CultureLensFitnessTrackTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = ImportedTrackStore(directory: directory)
    let draft = FitnessWorkoutRouteDraft(
      sourceIdentifier: "00000000-0000-0000-0000-000000000001",
      name: "户外跑步",
      sourceName: "体能训练",
      startedAt: Date(timeIntervalSinceReferenceDate: 456),
      segments: [
        ImportedTrackSegment(points: [
          ImportedTrackPoint(latitude: 30, longitude: 120, elevationMeters: 6, recordedAt: nil),
          ImportedTrackPoint(latitude: 30.01, longitude: 120.01, elevationMeters: 8, recordedAt: nil),
        ])
      ]
    )

    let first = try await store.importFitnessWorkout(draft)
    let second = try await store.importFitnessWorkout(draft)
    let loaded = try await store.load()

    #expect(first == second)
    #expect(loaded == [first])
    #expect(first.sourceKind == .appleFitness)
    #expect(first.sourceIdentifier == draft.sourceIdentifier)
    #expect(first.distanceMeters > 1_000)
  }

  @Test func rejectsFitnessWorkoutWithoutDrawableRoute() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "CultureLensEmptyFitnessTrackTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ImportedTrackStore(directory: directory)
    let draft = FitnessWorkoutRouteDraft(
      sourceIdentifier: UUID().uuidString,
      name: "户外步行",
      sourceName: "体能训练",
      startedAt: .now,
      segments: [
        ImportedTrackSegment(points: [
          ImportedTrackPoint(latitude: 30, longitude: 120, elevationMeters: nil, recordedAt: nil)
        ])
      ]
    )

    do {
      _ = try await store.importFitnessWorkout(draft)
      Issue.record("Expected an empty-track error")
    } catch {
      #expect(error as? ImportedTrackError == .emptyTrack)
    }
  }
}
